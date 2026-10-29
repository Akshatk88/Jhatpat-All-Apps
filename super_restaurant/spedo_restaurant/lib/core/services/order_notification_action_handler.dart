import 'dart:convert';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:food_user_application/config/constants/app_constants.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const orderAcceptActionId = 'accept_order';
const orderRejectActionId = 'reject_order';

const _claimPrefix = 'order_action_claim_';
const _claimTtl = Duration(minutes: 10);

/// Claims the one Accept/Reject an order may receive, across every isolate
/// that can send one: the app itself (notification action while running), the
/// notification's background action isolate (Reject while closed) and the
/// over-other-apps overlay's engine. Returns false when another of them has
/// already claimed it, so the order is never accepted (or rejected) twice.
///
/// SharedPreferences is the only store all three share; each isolate keeps its
/// own cached snapshot, hence the reload before reading.
Future<bool> claimOrderAction(String orderId) async {
  if (orderId.isEmpty) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(_claimPrefix)) continue;
      final at = prefs.getInt(key) ?? 0;
      if (now - at > const Duration(days: 1).inMilliseconds) {
        await prefs.remove(key);
      }
    }
    final key = '$_claimPrefix$orderId';
    final previous = prefs.getInt(key);
    if (previous != null && now - previous < _claimTtl.inMilliseconds) {
      return false;
    }
    await prefs.setInt(key, now);
    return true;
  } catch (_) {
    // Storage unavailable — better a possible duplicate than a lost action.
    return true;
  }
}

/// Gives the claim back after the request failed, so the order can still be
/// accepted or rejected from somewhere else.
Future<void> releaseOrderAction(String orderId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_claimPrefix$orderId');
  } catch (_) {}
}

/// A bare, one-off API client for isolates with no Riverpod container: the
/// access token straight from secure storage (the key `TokenStorage` uses).
/// Null when signed out.
Future<Dio?> _directClient() async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: 'access_token');
  if (token == null || token.isEmpty) return null;
  return Dio(
    BaseOptions(
      baseUrl: AppConstants.baseUrl,
      headers: {'Authorization': 'Bearer $token'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );
}

/// `PATCH /food/restaurant/orders/{id}/status` from an isolate with no app
/// state. True when the server accepted the change.
Future<bool> patchOrderStatusDirect(String orderId, String orderStatus) async {
  try {
    final dio = await _directClient();
    if (dio == null) return false;
    await dio.patch(
      '/food/restaurant/orders/$orderId/status',
      data: {'orderStatus': orderStatus},
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// The order's current `orderStatus`, or null if it could not be read.
Future<String?> fetchOrderStatusDirect(String orderId) async {
  try {
    final dio = await _directClient();
    if (dio == null) return null;
    final response = await dio.get('/food/restaurant/orders/$orderId');
    final data = response.data;
    final order = data is Map ? data['order'] : null;
    final status = order is Map ? order['orderStatus']?.toString() : null;
    return (status == null || status.isEmpty) ? null : status;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _decodePayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

/// Handles taps on the Accept/Reject buttons of the new-order notification.
///
/// Accept is declared `showsUserInterface: true`, so Android routes it through
/// MainActivity and it also reaches the app's normal main-isolate handler.
/// Reject is `showsUserInterface: false` on purpose — declining should not drag
/// the restaurant out of whatever they were doing — so the OS dispatches it to
/// this callback in a fresh background isolate instead. That requires
/// ActionBroadcastReceiver to be declared in AndroidManifest.xml; without it the
/// press is swallowed and the order is never rejected.
///
/// Being a fresh isolate, there is no Riverpod container or cached Dio client
/// here: the access token is read straight from secure storage (the same key
/// `TokenStorage` uses) and the request goes out on a bare, one-off Dio.
@pragma('vm:entry-point')
Future<void> notificationBackgroundResponseHandler(
  NotificationResponse response,
) async {
  final actionId = response.actionId;
  if (actionId != orderAcceptActionId && actionId != orderRejectActionId) {
    return;
  }

  final orderId = _decodePayload(response.payload)?['orderId'] as String?;
  if (orderId == null || orderId.isEmpty) return;

  // A background isolate starts with no plugins registered. Without this,
  // FlutterSecureStorage below throws MissingPluginException — and that read is
  // the first plugin call in the function, so the whole handler dies before it
  // ever reaches the try/catch and the rejection is lost silently.
  //
  // Harmless and idempotent when the isolate already has them (the foreground
  // delegation path in FcmService calls this same function).
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {
    // Already initialized, or a platform where it does not apply.
  }

  final orderStatus = actionId == orderAcceptActionId
      ? 'confirmed'
      : 'cancelled_by_restaurant';

  // The overlay (or the app) may already have answered this order.
  if (!await claimOrderAction(orderId)) return;

  // Best-effort — there is no UI running in this isolate to surface a retry.
  // Every plugin call (token read included) is caught inside, since an
  // uncaught throw here takes the isolate down mid-action.
  final ok = await patchOrderStatusDirect(orderId, orderStatus);
  if (!ok) {
    await releaseOrderAction(orderId);
    return;
  }
  // Answered from the notification: the overlay, if up, must not keep ringing.
  await OrderOverlayService.dismissOrders({orderId});
}

/// Whether an Accept/Reject for [orderId] is claimed (in flight or done)
/// anywhere — see [claimOrderAction].
Future<bool> isOrderActionClaimed(String orderId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final at = prefs.getInt('$_claimPrefix$orderId');
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at < _claimTtl.inMilliseconds;
  } catch (_) {
    return false;
  }
}
