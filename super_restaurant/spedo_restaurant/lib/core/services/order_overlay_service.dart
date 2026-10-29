import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _applicationId = 'com.restaurant.jhatpat';

/// Orders waiting on the overlay, as a JSON list. The single source of truth
/// shared by the three isolates involved: the FCM background handler writes
/// it, the overlay engine draws and answers from it, and the app takes it
/// over when it is opened.
const _pendingKey = 'overlay_pending_orders';

/// Order the overlay accepted; the app opens its details on launch.
const _openOrderKey = 'overlay_open_order';

/// Message the app sends the overlay engine: re-read [_pendingKey].
const overlaySyncMessage = 'sync';

/// How long a request stays up when the push carries no
/// `acceptanceDeadlineAt` — same as the in-app request screen.
const _defaultAcceptWindow = Duration(seconds: 60);

/// SharedPreferences as they are on disk right now. `getInstance()` is a
/// per-isolate snapshot that never re-reads, and these keys are written by
/// other isolates.
Future<SharedPreferences> _freshPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  try {
    await prefs.reload();
  } catch (_) {
    // Best effort — fall back to the cached copy.
  }
  return prefs;
}

/// One order waiting on the overlay.
class OverlayOrder {
  OverlayOrder({
    required this.orderId,
    required this.data,
    required this.deadline,
    required this.windowSeconds,
  });

  final String orderId;

  /// The `new_order` push data (all Strings).
  final Map<String, dynamic> data;
  final DateTime deadline;
  final int windowSeconds;

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    'data': data,
    'deadline': deadline.toIso8601String(),
    'window': windowSeconds,
  };

  static OverlayOrder? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['orderId']?.toString() ?? '';
    final deadline = DateTime.tryParse(json['deadline']?.toString() ?? '');
    final rawData = json['data'];
    if (id.isEmpty || deadline == null) return null;
    return OverlayOrder(
      orderId: id,
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{},
      deadline: deadline,
      windowSeconds: (json['window'] as num?)?.toInt() ?? 60,
    );
  }
}

/// What the app inherits from the overlay when it is opened.
class OverlayHandoff {
  const OverlayHandoff({required this.pending, required this.openOrderId});

  /// Still unanswered — the in-app request screen takes these over.
  final List<OverlayOrder> pending;

  /// Accepted from the overlay — open its details.
  final String? openOrderId;
}

/// The new-order request drawn over other apps (Android
/// `SYSTEM_ALERT_WINDOW`), for when a `new_order` push arrives and this app is
/// not in the foreground.
///
/// Ringing: while the overlay is up IT is the only thing ringing (looped
/// `tujh_bin` in the overlay engine); the order's tray notification is posted
/// silent. Without the permission nothing changes — the insistent
/// notification rings as before.
///
/// Safe to call from any isolate: the app, the FCM background handler, the
/// notification-action isolate and the overlay engine itself.
class OrderOverlayService {
  OrderOverlayService._();

  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      return await FlutterOverlayWindow.isPermissionGranted();
    } catch (_) {
      return false;
    }
  }

  /// Opens the system "Display over other apps" screen. App isolate only (it
  /// needs the Activity). Returns whether the permission is granted after.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      if (await FlutterOverlayWindow.isPermissionGranted()) return true;
      await FlutterOverlayWindow.requestPermission();
    } catch (e) {
      if (kDebugMode) debugPrint('[Overlay] permission request failed: $e');
    }
    return hasPermission();
  }

  /// Queues [data] (a `new_order` push) on the overlay and shows it.
  ///
  /// Returns true only when the overlay is confirmed on screen; false means
  /// the caller must alert the usual way (insistent notification): no
  /// permission, or the window could not be added (some OEM ROMs drop overlay
  /// windows even with the permission). Works with the app killed too: the
  /// plugin's service starts the overlay engine itself when none exists.
  static Future<bool> showForOrder(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return false;
    final orderId = (data['orderMongoId'] ?? data['orderId'])?.toString() ?? '';
    if (orderId.isEmpty) return false;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) return false;
      final prefs = await _freshPrefs();

      final now = DateTime.now();
      final serverDeadline = DateTime.tryParse(
        data['acceptanceDeadlineAt']?.toString() ?? '',
      );
      // Same rule as the in-app screen: a deadline already behind the device
      // clock is more likely clock skew than a dead order.
      final deadline = (serverDeadline != null && serverDeadline.isAfter(now))
          ? serverDeadline
          : now.add(_defaultAcceptWindow);
      final pending = _readPending(prefs)
        ..removeWhere((o) => o.orderId == orderId || !o.deadline.isAfter(now))
        ..add(
          OverlayOrder(
            orderId: orderId,
            data: {
              for (final e in data.entries)
                if (e.value != null) e.key: e.value.toString(),
            },
            deadline: deadline,
            windowSeconds: deadline.difference(now).inSeconds.clamp(1, 3600),
          ),
        );
      await _writePending(prefs, pending);

      if (await FlutterOverlayWindow.isActive()) {
        await _ping();
        return true;
      }

      await FlutterOverlayWindow.showOverlay(
        // A popup at the top, not a full-screen sheet. A Flutter view never
        // reports its content height, so the window opens at a typical card
        // height (dp) and the overlay then resizes it to the measured card
        // (OrderOverlayApp._fitWindowToCard).
        height: 360,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.topCenter,
        // Focusable and touchable, so Accept/Reject (and the reject dialog)
        // receive input.
        flag: OverlayFlag.focusPointer,
        enableDrag: false,
        positionGravity: PositionGravity.none,
        overlayTitle: 'New order',
        overlayContent: 'A new order is waiting for you',
        visibility: NotificationVisibility.visibilityPublic,
      );

      // Let the service actually add the window before trusting it.
      await Future.delayed(const Duration(milliseconds: 400));
      final active = await FlutterOverlayWindow.isActive();
      // Awaited: in the FCM background isolate nothing outlives the handler.
      if (active) await _pingRepeatedly();
      return active;
    } catch (e) {
      if (kDebugMode) debugPrint('[Overlay] show failed: $e');
      return false;
    }
  }

  /// The overlay engine registers its message listener asynchronously, and an
  /// early message is simply dropped — so the nudge is repeated. The overlay
  /// also re-reads on its own (first frame, window size change, periodically
  /// while it has orders), so a lost nudge only costs a moment.
  static Future<void> _pingRepeatedly() async {
    for (var attempt = 0; attempt < 3; attempt++) {
      await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
      await _ping();
    }
  }

  /// Tells the overlay engine to re-read the pending list. Only while the
  /// overlay is up: the plugin forwards the message to its engine without a
  /// null check.
  static Future<void> _ping() async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.shareData(
        overlaySyncMessage,
      ).timeout(const Duration(seconds: 2));
    } catch (_) {
      // Engine not listening yet — the next attempt or its own poll covers it.
    }
  }

  static List<OverlayOrder> _readPending(SharedPreferences prefs) {
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return <OverlayOrder>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <OverlayOrder>[];
      return [
        for (final e in decoded) ?OverlayOrder.fromJson(e),
      ];
    } catch (_) {
      return <OverlayOrder>[];
    }
  }

  static Future<void> _writePending(
    SharedPreferences prefs,
    List<OverlayOrder> orders,
  ) async {
    if (orders.isEmpty) {
      await prefs.remove(_pendingKey);
    } else {
      await prefs.setString(
        _pendingKey,
        jsonEncode([for (final o in orders) o.toJson()]),
      );
    }
  }

  /// The orders waiting on the overlay, oldest first.
  static Future<List<OverlayOrder>> readPending() async =>
      _readPending(await _freshPrefs());

  /// Drops [orderIds] from the overlay's list (no message to the overlay).
  static Future<void> removePending(Set<String> orderIds) async {
    if (orderIds.isEmpty) return;
    try {
      final prefs = await _freshPrefs();
      final pending = _readPending(prefs);
      final before = pending.length;
      pending.removeWhere((o) => orderIds.contains(o.orderId));
      if (pending.length != before) await _writePending(prefs, pending);
    } catch (_) {}
  }

  /// [orderIds] were answered or are past accept/reject somewhere else (the
  /// notification, the app, another device, the customer cancelled): take
  /// them off the overlay, which closes itself — and stops ringing — once
  /// nothing is left.
  static Future<void> dismissOrders(Set<String> orderIds) async {
    if (!Platform.isAndroid || orderIds.isEmpty) return;
    final prefs = await _freshPrefs();
    final pending = _readPending(prefs);
    if (!pending.any((o) => orderIds.contains(o.orderId))) return;
    pending.removeWhere((o) => orderIds.contains(o.orderId));
    await _writePending(prefs, pending);
    await _ping();
  }

  /// The app came to the foreground: the in-app request screen takes over.
  ///
  /// Clears the overlay's list, tells it to stop ringing, closes it, and hands
  /// back what was still unanswered plus the order to open if the overlay was
  /// used to accept one.
  static Future<OverlayHandoff> takeOver() async {
    if (!Platform.isAndroid) {
      return const OverlayHandoff(pending: [], openOrderId: null);
    }
    try {
      final prefs = await _freshPrefs();
      final now = DateTime.now();
      final pending = _readPending(prefs)
        ..removeWhere((o) => !o.deadline.isAfter(now));
      final openId = prefs.getString(_openOrderKey);
      await prefs.remove(_pendingKey);
      await prefs.remove(_openOrderKey);
      if (await FlutterOverlayWindow.isActive()) {
        // Stop the overlay's ringing first (it re-reads an empty list), then
        // take the window down.
        await _ping();
        await close();
      }
      return OverlayHandoff(
        pending: pending,
        openOrderId: (openId == null || openId.isEmpty) ? null : openId,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Overlay] take over failed: $e');
      return const OverlayHandoff(pending: [], openOrderId: null);
    }
  }

  /// Overlay side: remember the accepted order for the app to open.
  static Future<void> setOpenOrder(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_openOrderKey, orderId);
    } catch (_) {}
  }

  /// Closes the window. Guarded: the plugin's closeOverlay never answers when
  /// no overlay is running.
  static Future<void> close() async {
    if (!Platform.isAndroid) return;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay().timeout(
          const Duration(seconds: 2),
        );
      }
    } catch (_) {}
  }

  /// Brings the app to the front (overlay engine; allowed in the background
  /// because the app holds the overlay permission).
  static Future<void> launchApp() async {
    if (!Platform.isAndroid) return;
    try {
      const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        category: 'android.intent.category.LAUNCHER',
        package: _applicationId,
        componentName: '$_applicationId.MainActivity',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_ACTIVITY_REORDER_TO_FRONT,
        ],
      );
      await intent.launch();
    } catch (e) {
      if (kDebugMode) debugPrint('[Overlay] could not open the app: $e');
    }
  }
}
