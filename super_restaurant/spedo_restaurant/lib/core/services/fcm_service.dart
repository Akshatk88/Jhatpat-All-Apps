import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:food_user_application/config/constants/app_constants.dart';
import 'package:food_user_application/config/router/app_router.dart';
import 'package:food_user_application/core/network/dio_client.dart';
import 'package:food_user_application/core/providers/core_providers.dart';
import 'package:food_user_application/core/services/local_notification_service.dart';
import 'package:food_user_application/core/services/order_notification_action_handler.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';
import 'package:food_user_application/features/notifications/presentation/controllers/notifications_controller.dart';
import 'package:food_user_application/features/orders/presentation/controllers/live_orders_controller.dart';
import 'package:food_user_application/features/orders/data/order_repository.dart';
import 'package:food_user_application/features/orders/presentation/views/incoming_order_dialog.dart';

const _kOrderNotificationTypes = {
  'new_order',
  'order_status_update',
  'order_cancelled',
  'cancel_order',
  'order_accepted',
  'order_rejected',
};

/// Push-data fields the in-app request screen renders. Carried in the
/// notification payload so a tap or a full-screen launch over the lock screen
/// can show the card at once, without waiting for the API.
const _kRequestCardKeys = [
  'orderDisplayId',
  'customerName',
  'itemCount',
  'itemsList',
  'address',
  'total',
  'paymentMethod',
  'acceptanceDeadlineAt',
];

String _encodeTapPayload({
  String? type,
  String? orderId,
  Map<String, dynamic>? data,
}) => jsonEncode({
  'type': type,
  'orderId': orderId,
  if (type == 'new_order' && data != null)
    'data': {
      for (final key in _kRequestCardKeys)
        if (_nonEmpty(data[key]) != null) key: data[key].toString(),
    },
});

Map<String, dynamic>? _decodeTapPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _orderIdFromData(Map<String, dynamic> data) {
  final id = (data['orderMongoId'] ?? data['orderId'])?.toString();
  return (id == null || id.isEmpty) ? null : id;
}

String? _nonEmpty(Object? value) {
  final text = value?.toString().trim();
  return (text == null || text.isEmpty) ? null : text;
}

/// Body text for a new-order notification, composed from the data map when the
/// server did not send a ready-made one.
///
/// A data-only push has no `notification` block, so `message.notification` is
/// null and the only text available is whatever sits in `data`. Falling back to
/// an empty string there produced a notification with a title and no content —
/// which reads as a broken push rather than a missing field. The order details
/// are always present in `data`, so build the text from them instead of
/// depending on the server to pre-format it.
///
/// Customer first, then the items — what the restaurant needs to decide at a
/// glance in the heads-up banner — with the address in the expanded view. The
/// amount is in the title ([buildOrderNotificationTitle]).
String buildOrderNotificationBody(Map<String, dynamic> data) {
  final lines = <String>[];
  final items = _nonEmpty(data['itemsList']);
  final customer = _nonEmpty(data['customerName']);
  final address = _nonEmpty(data['address']);
  final payment = orderPaymentLabel(_nonEmpty(data['paymentMethod']));

  if (customer != null) {
    lines.add(payment != null ? '$customer  ·  $payment' : customer);
  }
  if (items != null) lines.add(items);
  if (address != null) lines.add(address);
  if (lines.isNotEmpty) return lines.join('\n');

  final provided = _nonEmpty(data['body']);
  if (provided != null) return provided;

  // Last resort: an order reference beats a blank notification.
  final ref = _nonEmpty(data['orderDisplayId']) ?? _nonEmpty(data['orderId']);
  return ref != null ? 'Order #$ref is waiting for review.' : '';
}

/// "New order ₹total" when the push carries the amount, else the server's
/// title (or a plain "New order received").
String buildOrderNotificationTitle(Map<String, dynamic> data) {
  final total = double.tryParse(_nonEmpty(data['total']) ?? '');
  if (total != null && total > 0) {
    final amount = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
    return 'New order ₹$amount';
  }
  return _nonEmpty(data['title']) ?? 'New order received';
}

DateTime? _deadlineFromData(Map<String, dynamic> data) =>
    DateTime.tryParse(_nonEmpty(data['acceptanceDeadlineAt']) ?? '');

/// Whether the native FCM receiver (android/…/NewOrderReceiver.kt) has
/// already raised this order's alert — the overlay and/or the ringing
/// notification, same ids and tags as ours. It runs for every push, before
/// any Dart handler, and records the time under `native_new_order_<id>`.
/// Alerting again from Dart would only duplicate it (or turn a silent
/// notification next to the overlay into a second ringing source).
Future<bool> _alertedNatively(String? orderId) async {
  if (orderId == null || orderId.isEmpty) return false;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final at = prefs.getInt('native_new_order_$orderId');
    return at != null &&
        DateTime.now().millisecondsSinceEpoch - at <
            const Duration(minutes: 2).inMilliseconds;
  } catch (_) {
    return false;
  }
}

/// Must stay top-level (not a class method) — Firebase invokes this in a
/// separate background isolate that has no access to app state, so it needs
/// its own Firebase configuration before touching any Firebase API.
///
/// `new_order` pushes to the restaurant are sent `dataOnly` (no
/// `notification` block) precisely so the OS never auto-displays a plain
/// alert here — that path can't carry the Accept/Reject action buttons. This
/// handler builds that local notification itself instead. Other push types
/// still include a `notification` block and are shown by the OS as before,
/// so nothing else needs to happen here.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      // Same order as `main()`: the platform config decides the project, and
      // the constants are only a fallback. A background isolate that initialised
      // against a different project than the foreground one would hold a token
      // the backend never targets. See `config/constants/app_constants.dart`.
      try {
        await Firebase.initializeApp();
      } on Exception {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: AppConstants.firbaseApiKey,
            appId: AppConstants.firebaseAppId,
            messagingSenderId: AppConstants.firebasemessagingSenderId,
            projectId: AppConstants.firebaseProjectId,
          ),
        );
      }
    }
  } catch (_) {
    // Best-effort — the OS-rendered notification doesn't depend on this.
  }

  if (message.data['type']?.toString() != 'new_order') return;
  if (await _alertedNatively(_orderIdFromData(message.data))) return;

  if (kDebugMode) {
    debugPrint('[FCM background] new_order push received: ${message.data}');
  }

  try {
    // Fresh isolate — this instance hasn't been initialized yet. The
    // `onResponse` callback given here only fires for the plain-tap case
    // (never for the Accept/Reject actions, which always route through
    // `notificationBackgroundResponseHandler` regardless of app state), and
    // this isolate is torn down right after this function returns, so there
    // is nothing useful to do with a tap here.
    // requestPermission: false — no Activity exists in this isolate, and asking
    // there can throw and abort the whole handler before show() runs.
    await LocalNotificationService.instance.initialize(
      onResponse: (_) {},
      requestPermission: false,
    );
    final orderId = _orderIdFromData(message.data);
    // With "display over other apps" granted, the request is drawn over
    // whatever is on screen and rings there — the one ringing source; the
    // notification below is then silent. Without it, nothing changes.
    final overlayShown = await OrderOverlayService.showForOrder(message.data);
    // Rings insistently (until acted on, expired or handled elsewhere) and
    // takes over a locked screen; the full-screen launch opens the app's own
    // request screen for this order (which then closes the overlay).
    final shown = await LocalNotificationService.instance.show(
      title: buildOrderNotificationTitle(message.data),
      body: buildOrderNotificationBody(message.data),
      payload: _encodeTapPayload(
        type: 'new_order',
        orderId: orderId,
        data: message.data,
      ),
      isNewOrder: true,
      orderId: orderId,
      acceptanceDeadline: _deadlineFromData(message.data),
      silent: overlayShown,
    );

    if (kDebugMode) {
      debugPrint(
        '[FCM background] LocalNotificationService.show() returned $shown',
      );
    }

    // Only take down the OS-rendered copy once ours is provably on screen.
    // Ordering alone was not enough: show() used to report success even when it
    // had failed or was never initialized, so this ran anyway and removed the
    // only alert left. The tag is set by the backend and the two must agree.
    if (shown || overlayShown) await cancelFcmTrayCopy(orderId);
  } catch (e) {
    // Deliberately leaves the OS tray copy in place — it is the only thing
    // left telling the restaurant an order arrived.
    if (kDebugMode) {
      debugPrint('[FCM background] new_order handling threw: $e');
    }
  }
}

/// The app's process is alive but nothing of it is on screen — another app is
/// in front, or the screen is off. (`inactive` is not background: that is the
/// notification shade or a dialog over the app.)
bool _isAppInBackground() {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden ||
      state == AppLifecycleState.detached;
}

/// Removes the OS-rendered copy of the new-order push.
///
/// The push is hybrid: FCM posts a tray notification itself, tagged
/// `order_<id>` by the backend, so ROMs that refuse to start the app in the
/// background still alert the restaurant. Wherever the app's own alert does
/// show, this takes the tray copy down so only one is visible. FCM posts
/// tagged notifications under id 0.
Future<void> cancelFcmTrayCopy(String? orderId) async {
  if (orderId == null || orderId.isEmpty) return;
  try {
    await FlutterLocalNotificationsPlugin().cancel(0, tag: 'order_$orderId');
  } catch (_) {
    // Worst case the tray copy stays — a duplicate, not a missed order.
  }
}

/// Wraps device push-token registration against the two endpoints the
/// backend exposes for restaurant partners: `/fcm-tokens/mobile/save` and
/// `/fcm-tokens/remove`. Token saves are best-effort — a failure here should
/// never block login or app startup.
class FcmService {
  FcmService(this._dio, this._ref);

  final Dio _dio;
  final Ref _ref;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  bool _foregroundHandlingWired = false;

  Future<void> requestPermission() async {
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (_) {
      // Permission prompt failing (e.g. unsupported platform) shouldn't crash startup.
    }
  }

  /// Why the last registration attempt failed, for the diagnostics screen.
  ///
  /// Every step here used to swallow its error, so a restaurant with no push
  /// notifications produced no evidence anywhere — on the device or the server.
  /// Suvio had logged in twelve times with zero tokens saved and nothing said
  /// why. Keeping the reason costs nothing and turns "notifications don't work"
  /// into an answerable question.
  static String? lastRegistrationError;

  /// How long to wait for a token before giving up on one.
  ///
  /// `getToken()` does not always fail — on a device with broken or outdated
  /// Play Services it can simply never return. This sits in the login path, so
  /// without a bound a sign-in stalls forever with nothing on screen to explain
  /// it. A push token is not worth blocking a login for; it is re-registered
  /// after sign-in anyway.
  static const _tokenTimeout = Duration(seconds: 10);

  Future<String?> currentToken() async {
    try {
      final token = await _messaging.getToken().timeout(_tokenTimeout);
      if (token == null || token.isEmpty) {
        lastRegistrationError = 'FCM returned no token for this device';
      }
      return token;
    } on TimeoutException {
      lastRegistrationError =
          'FCM getToken timed out after ${_tokenTimeout.inSeconds}s';
      if (kDebugMode) debugPrint('[FCM] getToken timed out');
      return null;
    } catch (e) {
      lastRegistrationError = 'FCM getToken failed: $e';
      if (kDebugMode) debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  /// Registers this device against the logged-in restaurant.
  ///
  /// Retried, because the common failure is a race rather than a permanent
  /// fault: this runs immediately after login, and a token save that lands
  /// before the access token is readable comes back 401 and was then simply
  /// dropped — leaving the restaurant permanently unreachable until the next
  /// login happened to win the race. Push is how a restaurant learns it has an
  /// order, so one silent miss is worth three cheap retries.
  Future<bool> saveTokenToServer() async {
    // Resume and onTokenRefresh call this whether or not anyone is signed in.
    // Signed out, every attempt is a guaranteed 401 (plus a refresh attempt in
    // the Dio interceptor), so skip it; the next login registers the token.
    final accessToken = await _ref.read(tokenStorageProvider).accessToken;
    if (accessToken == null || accessToken.isEmpty) return false;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(seconds: attempt * 2));
      }

      final token = await currentToken();
      if (token == null || token.isEmpty) continue;

      try {
        await _dio.post('/fcm-tokens/mobile/save', data: {'token': token});
        lastRegistrationError = null;
        if (kDebugMode) debugPrint('[FCM] token registered');
        return true;
      } catch (e) {
        lastRegistrationError = 'Token save failed: $e';
        if (kDebugMode)
          debugPrint('[FCM] save attempt ${attempt + 1} failed: $e');
      }
    }
    return false;
  }

  Future<void> removeTokenFromServer() async {
    final token = await currentToken();
    if (token == null || token.isEmpty) return;
    try {
      await _dio.delete('/fcm-tokens/remove', data: {'token': token});
    } catch (_) {
      // Best-effort — logging out should proceed regardless.
    }
  }

  void listenForTokenRefresh(void Function() onRefresh) {
    _messaging.onTokenRefresh.listen((_) => onRefresh());
  }

  /// Sets up everything needed for a push to actually be *visible*:
  /// - foreground messages (never auto-displayed by the OS) get shown via
  ///   [LocalNotificationService], and a `new_order` also pops an immediate
  ///   in-app accept/reject dialog so the restaurant doesn't have to notice
  ///   and tap a system notification while the app is already open.
  /// - taps on a background/terminated notification, and taps on the local
  ///   one we show ourselves, both route through [_navigateForType] straight
  ///   to the Order Details screen.
  ///
  /// Safe to call multiple times — wiring only happens once.
  Future<void> initForegroundHandling() async {
    if (_foregroundHandlingWired) return;
    _foregroundHandlingWired = true;

    await LocalNotificationService.instance.initialize(
      onResponse: _handleNotificationResponse,
    );

    // The OS can rotate the FCM token at any time (rare, but it happens) —
    // keep the backend's copy in sync or pushes silently stop working.
    listenForTokenRefresh(saveTokenToServer);

    // Explicitly save the token on initialization in case it wasn't saved yet
    await saveTokenToServer();

    FirebaseMessaging.onMessage.listen((message) async {
      final notification = message.notification;
      final type = message.data['type']?.toString();
      final orderId = _orderIdFromData(message.data);
      final isNewOrder = type == 'new_order';

      if (_kOrderNotificationTypes.contains(type)) {
        _ref.read(liveOrdersControllerProvider.notifier).refresh();
      } else {
        _ref.read(notificationsControllerProvider.notifier).refresh();
      }

      // Alive but not in front (another app on screen, or the screen off):
      // the same over-other-apps request the background handler shows, ringing
      // on its own with the tray copy silent. No permission (or no window) —
      // falls through to the existing handling below. Already raised by the
      // native receiver (which only acts while the app is not in front):
      // nothing more to do here.
      if (isNewOrder &&
          orderId != null &&
          _isAppInBackground() &&
          await _alertedNatively(orderId)) {
        return;
      }
      if (isNewOrder &&
          orderId != null &&
          _isAppInBackground() &&
          await OrderOverlayService.showForOrder(message.data)) {
        await LocalNotificationService.instance.show(
          title: buildOrderNotificationTitle(message.data),
          body: buildOrderNotificationBody(message.data),
          payload: _encodeTapPayload(
            type: type,
            orderId: orderId,
            data: message.data,
          ),
          isNewOrder: true,
          orderId: orderId,
          acceptanceDeadline: _deadlineFromData(message.data),
          silent: true,
        );
        await cancelFcmTrayCopy(orderId);
        return;
      }

      // App is already open — surface the order on the full-screen request
      // screen, which rings in-app until it is answered. It replaces the tray
      // alert entirely (two rings at once helps nobody); the notification is
      // only the fallback when there is no UI to show it on.
      if (isNewOrder &&
          orderId != null &&
          showIncomingOrderRequest(orderId: orderId, data: message.data)) {
        return;
      }

      final title = isNewOrder
          ? buildOrderNotificationTitle(message.data)
          : (_nonEmpty(notification?.title) ??
                _nonEmpty(message.data['title']) ??
                'Jhatpat Restaurant');
      final body = isNewOrder
          ? buildOrderNotificationBody(message.data)
          : (_nonEmpty(notification?.body) ??
                _nonEmpty(message.data['body']) ??
                '');

      LocalNotificationService.instance
          .show(
            title: title,
            body: body,
            payload: _encodeTapPayload(
              type: type,
              orderId: orderId,
              data: message.data,
            ),
            isNewOrder: isNewOrder,
            orderId: orderId,
            acceptanceDeadline: isNewOrder
                ? _deadlineFromData(message.data)
                : null,
            // The app is already in the foreground — a full-screen intent on
            // top of it races the OS's screen takeover against Flutter's, which
            // is what was hanging the app/phone on order receipt.
            fullScreenIntent: false,
          )
          .then((shown) {
            if (kDebugMode && isNewOrder) {
              debugPrint(
                '[FCM foreground] LocalNotificationService.show() returned $shown',
              );
            }
            // Cancelled only once ours is provably on screen — same reason as the
            // background handler: assuming success turns any failure to show into
            // no notification at all.
            if (isNewOrder && shown) cancelFcmTrayCopy(orderId);
          });
    });

    // Tap on the OS-rendered tray copy of a push.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _openFromNotification(
        message.data['type']?.toString(),
        _orderIdFromData(message.data),
        message.data,
      );
    });

    // Accept launches the app, so when it was TERMINATED the button press arrives
    // here rather than at onResponse — flutter_local_notifications delivers the
    // launching interaction through getNotificationAppLaunchDetails, not the live
    // callback. Without this the app simply opened and the order was never
    // accepted. The same goes for a plain tap and for the full-screen launch over
    // the lock screen, which both open the request screen for the order.
    final launchDetails = await LocalNotificationService.instance
        .launchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if ((launchDetails?.didNotificationLaunchApp ?? false) &&
        launchResponse != null) {
      _handleNotificationResponse(launchResponse);
    }

    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type']?.toString();
      final orderId = _orderIdFromData(initialMessage.data);
      if (type == 'new_order') {
        // The request screen waits for the session restore by itself.
        _openFromNotification(type, orderId, initialMessage.data);
      } else {
        // This runs inside the same login/session-restore chain that the
        // splash screen awaits before doing its own default `go('/orders')` —
        // deferring a beat lets our deep link win that race instead of being
        // immediately overwritten.
        Future.delayed(const Duration(milliseconds: 400), () {
          _navigateForType(type, orderId);
        });
      }
    }
  }

  /// Orders whose notification Accept/Reject has already been handled in this
  /// process. The same press can reach the app twice — the live callback and
  /// the launch details of a cold start — and must hit the API once.
  static final Set<String> _handledOrderActions = <String>{};

  /// Routes an Accept/Reject action button or a plain notification tap.
  ///
  /// Shared by the live-tap callback and the cold-start path, because which of the
  /// two fires depends only on whether the app happened to be running — and both
  /// have to perform the action, not merely open the order.
  ///
  /// Only Accept normally arrives here: it opens the app
  /// (`showsUserInterface: true`). Reject does not open the app and is handled
  /// by [notificationBackgroundResponseHandler] in a background isolate.
  void _handleNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    final isAccept = actionId == orderAcceptActionId;
    final isReject = actionId == orderRejectActionId;
    final decoded = _decodeTapPayload(response.payload);
    final orderId = decoded?['orderId'] as String?;

    if (isAccept || isReject) {
      if (orderId == null || orderId.isEmpty) return;
      if (!_handledOrderActions.add(orderId)) return;
      // The plugin cancels an app-opening action's notification by id only;
      // ours is tagged, so it would keep ringing after the Accept.
      unawaited(LocalNotificationService.instance.cancelOrderAlert(orderId));
      dismissIncomingOrderRequest(orderId);
      unawaited(_respondFromNotification(orderId, accept: isAccept));
      return;
    }

    final rawData = decoded?['data'];
    _openFromNotification(
      decoded?['type'] as String?,
      orderId,
      rawData is Map ? Map<String, dynamic>.from(rawData) : null,
    );
  }

  /// Accept/Reject pressed on the notification, performed in the app's own
  /// isolate with the app's own API client (token refresh included).
  Future<void> _respondFromNotification(
    String orderId, {
    required bool accept,
  }) async {
    // Shared with the over-other-apps overlay and the background Reject: the
    // order may already have been answered there.
    var ok = false;
    if (await claimOrderAction(orderId)) {
      try {
        await _ref
            .read(orderRepositoryProvider)
            .updateStatus(
              orderId,
              accept ? 'confirmed' : 'cancelled_by_restaurant',
            );
        ok = true;
      } catch (e) {
        if (kDebugMode) debugPrint('[FCM] notification action failed: $e');
      }
      if (ok) {
        // The overlay, if up for this order, must stop ringing.
        unawaited(OrderOverlayService.dismissOrders({orderId}));
      } else {
        await releaseOrderAction(orderId);
      }
    } else {
      // Answered elsewhere first — nothing to send; Accept still lands on the
      // order below.
      ok = true;
    }

    // The order list is stale the moment the status changes.
    unawaited(_ref.read(liveOrdersControllerProvider.notifier).refresh());
    if (!accept && ok) return;

    final navigator = await waitForOrdersUi();
    final context = navigator?.context;
    if (context == null || !context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? "Couldn't accept the order. Please accept it from the order screen."
                : "Couldn't reject the order. Please try again from the order screen.",
          ),
        ),
      );
    }
    // Accept opened the app — land on the order just taken on (or, if the
    // accept failed, on the order so it can be retried there).
    GoRouter.of(context).push('/order-details/$orderId');
  }

  /// A notification was opened (tap, or full-screen launch over the lock
  /// screen). A new order goes to the request screen — which itself lands on
  /// the order's details if it turns out to be handled already.
  void _openFromNotification(
    String? type,
    String? orderId,
    Map<String, dynamic>? data,
  ) {
    if (type == 'new_order' &&
        orderId != null &&
        orderId.isNotEmpty &&
        showIncomingOrderRequest(
          orderId: orderId,
          data: data,
          fromNotification: true,
        )) {
      return;
    }
    _navigateForType(type, orderId);
  }

  void _navigateForType(String? type, String? orderId) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    if (_kOrderNotificationTypes.contains(type)) {
      if (orderId != null && orderId.isNotEmpty) {
        GoRouter.of(context).push('/order-details/$orderId');
      } else {
        GoRouter.of(context).go('/orders');
      }
    } else {
      GoRouter.of(context).go('/notifications');
    }
  }
}

final fcmServiceProvider = Provider<FcmService>((ref) {
  return FcmService(ref.watch(dioProvider), ref);
});
