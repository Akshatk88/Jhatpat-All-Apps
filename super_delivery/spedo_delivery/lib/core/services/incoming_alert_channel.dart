import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import "package:flutter/material.dart" show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import "package:shared_preferences/shared_preferences.dart";
import "package:food_user_application/features/rides/presentation/widgets/cancel_reason_sheet.dart";

import 'package:food_user_application/features/orders/application/incoming_order_controller.dart';
import 'package:food_user_application/features/orders/application/orders_controller.dart';
import 'package:food_user_application/features/orders/application/orders_state.dart';
import 'package:food_user_application/features/rides/application/incoming_ride_controller.dart';

/// The Dart end of the native lock-screen offer alert.
///
/// The alert itself is posted and drawn in Kotlin — see
/// `android/app/src/main/kotlin/com/delivery/jhatpat/IncomingOrderNotifier.kt`
/// — because it has to appear on a locked phone with the app dead, before any
/// Flutter engine exists. What Kotlin deliberately does *not* do is decide
/// anything: when the rider taps Accept or Reject it records the choice and
/// launches the app, and this collects it.
///
/// Pulled rather than pushed. The activity is launched from the notification
/// long before Dart has a listener attached, so an event emitted at that moment
/// would land on nobody and the rider's Accept would vanish. Kotlin holds the
/// choice until it is asked for.
class IncomingAlertChannel {
  const IncomingAlertChannel._();

  static const _channel = MethodChannel('app.fooddelivery/incoming_alert');

  static bool _listening = false;

  /// Offers the native alert is currently ringing for. A set, not only a
  /// stream, because the native alert usually goes up before the in-app screen
  /// for the same offer exists.
  static final Set<String> _nativeAlerts = {};

  /// Offers answered on the native card or its notification buttons.
  static final Set<String> _answered = {};

  static final _nativeShown = StreamController<String>.broadcast();
  static final _resolved = StreamController<Map<String, String>>.broadcast();

  /// Emits an offer id when the native alert starts ringing for it.
  static Stream<String> get nativeAlertShown => _nativeShown.stream;

  /// Emits `{orderId, action, type}` when the rider answers natively while the
  /// app is alive in the background.
  static Stream<Map<String, String>> get nativelyResolved => _resolved.stream;

  static bool hasNativeAlert(String orderId) => _nativeAlerts.contains(orderId);

  static bool wasAnsweredNatively(String orderId) => _answered.contains(orderId);

  /// Starts receiving the native side's events. Idempotent; called by both
  /// offer controllers on build.
  ///
  /// Without it, a Reject tapped on the notification left the in-app offer
  /// (raised by the socket while backgrounded) up and ringing until its own
  /// countdown ran out.
  static void listen() {
    if (_listening || !_supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? call.arguments as Map : const {};
      final orderId = (args['orderId'] ?? '').toString();
      if (orderId.isEmpty) return null;
      switch (call.method) {
        case 'nativeAlertShown':
          _nativeAlerts.add(orderId);
          _nativeShown.add(orderId);
        case 'nativeAlertCleared':
          _nativeAlerts.remove(orderId);
        case 'resolved':
          _nativeAlerts.remove(orderId);
          _answered.add(orderId);
          _resolved.add({
            'orderId': orderId,
            'action': (args['action'] ?? '').toString(),
            'type': (args['type'] ?? '').toString(),
          });
      }
      return null;
    });
  }

  /// Takes the native alert down once the offer has been dealt with elsewhere
  /// — accepted in-app, or withdrawn.
  ///
  /// The notification id is computed on the Kotlin side from the order id,
  /// because Dart's `String.hashCode` and Java's are different numbers; only
  /// one of them may own that arithmetic.
  static Future<void> dismiss(String orderId) async {
    if (!_supported || orderId.isEmpty) return;
    _nativeAlerts.remove(orderId);
    try {
      await _channel.invokeMethod<bool>('dismiss', {'orderId': orderId});
    } on PlatformException {
      // Losing a stale notification is not worth an error path; it carries its
      // own timeout.
    } on MissingPluginException {
      // Older build without the native half.
    }
  }

  /// Brings the app in line with a choice already made on the lock screen.
  ///
  /// The accept or reject call has **already been sent** — Kotlin does it, so
  /// that Reject can answer without opening the app at all. This does not
  /// repeat it; sending it twice would accept an order the rider accepted once
  /// and, on the reject side, decline a job they had already declined.
  ///
  /// What is left is the app's own view of the world: the rider arrives on a
  /// screen still showing the order as merely offered. Refreshing is what turns
  /// it into the job they just took.
  ///
  /// Safe to call on every resume: the choice is consumed on read, so a second
  /// call finds nothing.
  static Future<void> applyPendingAction(WidgetRef ref, {BuildContext? context}) async {
    if (!_supported) return;

    final Map<Object?, Object?>? pending;
    try {
      pending = await _channel.invokeMapMethod<Object?, Object?>(
        'consumePendingAction',
      );
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
    if (pending == null) return;

    final action = (pending['action'] ?? '').toString();
    final orderId = (pending['orderId'] ?? '').toString();
    if (orderId.isEmpty) return;

    // Rejected on the native card or notification: the reject itself was
    // already sent (food) or lapses (ride), so only the reason is asked here.
    if (action == "reject_reason") {
      await dismiss(orderId);
      if (context == null || !context.mounted) return;
      final isRide = (pending["payload"] is Map) &&
          (pending["payload"] as Map)["type"] == "ride_request";
      final reason = await showDriverCancelReasonSheet(
        context,
        partyLabel: isRide ? "Passenger" : "Customer",
        note: "Your answer helps us send you better jobs.",
        rejectOffer: true,
      );
      if (reason != null) await _recordRejectReason(orderId, isRide, reason);
      return;
    }

    // 'open' means the rider tapped the card rather than a button — nothing has
    // been answered on their behalf, and the offer is already arriving through
    // the socket and the poll.
    if (action != 'accept' && action != 'reject') return;

    await dismiss(orderId);

    final payload = <String, dynamic>{};
    final rawPayload = pending['payload'];
    if (rawPayload is Map) {
      rawPayload.forEach((k, v) => payload[k.toString()] = v);
    }

    // Rides are claimed over the socket only, so Kotlin did NOT send this
    // accept (see IncomingOrderActivity.handOff) — it is made here, once.
    if (payload['type'] == 'ride_request') {
      if (action == 'accept') {
        await ref
            .read(incomingRideControllerProvider.notifier)
            .acceptFromAlert({...payload, 'rideId': payload['rideId'] ?? orderId});
      }
      return;
    }

    // The same offer usually also reached the in-app alert (FCM onMessage /
    // socket / poll). Clear it, or the rider could accept it a second time.
    ref.read(incomingOrderControllerProvider.notifier).resolvedNatively(orderId);

    // Pull the order's real state rather than assuming the accept succeeded:
    // it may have been given to a faster rider between the tap and the app
    // opening, and showing a job they do not have is worse than showing none.
    final orders = ref.read(ordersControllerProvider.notifier);
    await orders.refreshCurrent();
    // Kotlin's accept is sent in parallel with the app starting, so a warm
    // start can ask before the server has assigned it. A few short retries let
    // the rider land on the job instead of an empty map.
    if (action == 'accept') {
      for (var attempt = 0; attempt < 3 && !_hasCurrentOrder(ref); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await orders.refreshCurrent();
      }
    }
    await orders.refreshAvailable();
  }

  /// Neither the food reject endpoint nor the ride decline carries a reason
  /// server-side, so it is kept on the device (last 50) and logged.
  static Future<void> _recordRejectReason(
    String orderId,
    bool isRide,
    String reason,
  ) async {
    debugPrint("Offer $orderId (${isRide ? "ride" : "food"}) rejected: $reason");
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList("offer_reject_reasons") ?? <String>[];
      list.add("${DateTime.now().toIso8601String()}|$orderId|$reason");
      await prefs.setStringList(
        "offer_reject_reasons",
        list.length > 50 ? list.sublist(list.length - 50) : list,
      );
    } catch (_) {}
  }

  static bool _hasCurrentOrder(WidgetRef ref) {
    final state = ref.read(ordersControllerProvider);
    return state is OrdersLoaded && state.currentOrder != null;
  }

  /// The native half is Android-only; iOS has no equivalent surface here.
  static bool get _supported => defaultTargetPlatform == TargetPlatform.android;
}
