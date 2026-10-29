import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:food_user_application/core/services/order_notification_action_handler.dart';

/// Displays a system notification for FCM messages that arrive while the
/// app is in the foreground — Android/iOS never auto-display those (only
/// background/terminated pushes with a `notification` block do), so without
/// this the restaurant would never see a "new order" alert while the app is
/// open.
///
/// Every channel the backend can name must be created here. Android silently
/// ignores an unknown channel id and falls back to a low-importance default, so
/// a mismatch looks exactly like the push never arriving. The backend uses
/// `high_importance_channel` for ordinary alerts (FCM_DEFAULT_CHANNEL_ID) and
/// omits the channel entirely for data-only new-order pushes, where the app
/// picks its own — see `Backend/src/core/notifications/firebase.service.js`.
class LocalNotificationService {
  LocalNotificationService._();
  static final LocalNotificationService instance = LocalNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _defaultChannel = AndroidNotificationChannel(
    'default',
    'General notifications',
    description: 'Order updates and general alerts from Jhatpat Restaurant.',
    importance: Importance.high,
  );

  /// The backend's FCM_DEFAULT_CHANNEL_ID. Order status updates arrive WITH a
  /// notification block, so the OS renders them against this id directly — and
  /// the app previously never created it, leaving those alerts on Android's
  /// fallback channel with no heads-up display.
  static const _highImportanceChannel = AndroidNotificationChannel(
    'high_importance_channel',
    'Order updates',
    description: 'Order status updates and alerts from Jhatpat Restaurant.',
    importance: Importance.max,
  );

  // Android locks a channel's sound/importance the first time it's created —
  // calling createNotificationChannel again with the same id and different
  // settings is silently ignored. Any device that already got this channel
  // from an earlier build (before the custom sound was wired up correctly)
  // is stuck with that old, wrong sound forever. The id was bumped to _v2 so
  // every device creates a fresh channel and actually picks up `tujh_bin`.
  static const _newOrderChannel = AndroidNotificationChannel(
    'new_order_channel_v2',
    'Order Alerts',
    description: 'High priority alerts for new orders.',
    importance: Importance.max,
    sound: RawResourceAndroidNotificationSound('tujh_bin'),
    playSound: true,
  );

  // Accept opens the app: the restaurant has just taken the order and needs to
  // start preparing it, so landing them on the order is the point. Launching also
  // means the tap is delivered to the app's own (main-isolate) response handler.
  static const _acceptOrderAction = AndroidNotificationAction(
    orderAcceptActionId,
    'Accept',
    showsUserInterface: true,
    cancelNotification: true,
  );

  // Reject deliberately does NOT launch the app — declining an order should not
  // drag the restaurant out of whatever they were doing. With
  // `showsUserInterface: false` the OS routes it to
  // `onDidReceiveBackgroundNotificationResponse` when nothing is running, and to
  // the normal response handler when the app is already alive.
  //
  static const _rejectOrderAction = AndroidNotificationAction(
    orderRejectActionId,
    'Reject',
    showsUserInterface: false,
    cancelNotification: true,
  );

  /// [requestPermission] must be false when called from a background isolate.
  ///
  /// There is no Activity there, so asking for the notification permission can
  /// throw or hang — and since the background handler wraps this whole call in a
  /// try/catch, a throw here meant initialization never completed, show() was
  /// never reached, and the failure was swallowed silently. That is what made
  /// new-order notifications vanish whenever the app was closed. The permission
  /// is a startup concern anyway: by the time a push arrives it has already been
  /// granted or denied.
  Future<void> initialize({
    required void Function(NotificationResponse response) onResponse,
    bool requestPermission = true,
  }) async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onResponse,
      onDidReceiveBackgroundNotificationResponse:
          notificationBackgroundResponseHandler,
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_defaultChannel);
    await androidPlugin?.createNotificationChannel(_highImportanceChannel);
    await androidPlugin?.createNotificationChannel(_newOrderChannel);

    // Set once the plugin and channels really exist, and BEFORE the permission
    // request below — that request is optional and must never be able to leave
    // the service permanently uninitialized.
    _initialized = true;

    if (requestPermission) {
      try {
        await androidPlugin?.requestNotificationsPermission();

        // Android 14+ revokes USE_FULL_SCREEN_INTENT by default for apps that are
        // not phone/alarm apps, even with the manifest entry — so a full-screen
        // alert silently downgrades to an ordinary heads-up banner without this
        // explicit grant. No-op on older versions or once already granted.
        await androidPlugin?.requestFullScreenIntentPermission();
      } catch (e) {
        // Never fatal: a denied or unavailable prompt must not stop us posting
        // notifications the user has already allowed.
        if (kDebugMode) debugPrint('requestNotificationsPermission failed: $e');
      }
    }
  }

  /// The interaction that launched the app, if any.
  ///
  /// An Accept press on a terminated app is delivered here rather than through the
  /// live response callback, so the caller must check it or the action is lost.
  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  static const _newOrderNotificationId = 7001;
  static const _newOrderTagPrefix = 'new_order_';

  /// Takes down (and so silences) the new-order alert of every order that is
  /// known to be past the accept/reject stage.
  ///
  /// [handledOrderIds] are ids of orders the API reports as no longer awaiting
  /// a decision — accepted or rejected here, from the notification, from
  /// another device, or cancelled by the customer. Orders the API does not
  /// return at all are left alone: a fresh push can beat the order being
  /// readable, and removing its alert then would hide a live order.
  Future<void> dismissHandledOrderAlerts(Set<String> handledOrderIds) async {
    if (!_initialized || handledOrderIds.isEmpty) return;
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return;
    try {
      final active = await androidPlugin.getActiveNotifications();
      for (final n in active) {
        final tag = n.tag;
        if (tag == null || !tag.startsWith(_newOrderTagPrefix)) continue;
        final orderId = tag.substring(_newOrderTagPrefix.length);
        if (handledOrderIds.contains(orderId)) {
          await androidPlugin.cancel(n.id ?? _newOrderNotificationId, tag: tag);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalNotification] dismiss failed: $e');
    }
  }

  /// Takes down — and so silences — the new-order alert of one order: our own
  /// (fixed id + `new_order_<id>` tag) and the OS-rendered FCM tray copy
  /// (id 0, tag `order_<id>`, set by the backend).
  ///
  /// Needed wherever an alert must stop ringing on purpose: the in-app request
  /// screen taking over, or the notification's own Accept button. The plugin
  /// cancels a foreground (app-opening) action's notification by id only, and
  /// these alerts are tagged — without this an accepted order kept ringing.
  Future<void> cancelOrderAlert(String orderId) async {
    if (orderId.isEmpty) return;
    try {
      await _plugin.cancel(
        _newOrderNotificationId,
        tag: '$_newOrderTagPrefix$orderId',
      );
      await _plugin.cancel(0, tag: 'order_$orderId');
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalNotification] cancel failed: $e');
    }
  }

  /// Order ids whose new-order alert is currently in the tray (and so still
  /// ringing). Lets the app bring those orders up on its own request screen
  /// when the restaurant opens it some other way than through the alert.
  Future<Set<String>> activeOrderAlertIds() async {
    if (!_initialized) return const {};
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return const {};
    try {
      final active = await androidPlugin.getActiveNotifications();
      final ids = <String>{};
      for (final n in active) {
        final tag = n.tag;
        if (tag == null || !tag.startsWith(_newOrderTagPrefix)) continue;
        final id = tag.substring(_newOrderTagPrefix.length);
        if (id.isNotEmpty) ids.add(id);
      }
      return ids;
    } catch (e) {
      if (kDebugMode) debugPrint('[LocalNotification] active read failed: $e');
      return const {};
    }
  }

  /// Android's FLAG_INSISTENT (Notification.FLAG_INSISTENT = 4): the alert
  /// sound repeats until the notification is cancelled, the way an incoming
  /// call rings, instead of one chime that is easy to miss in a busy kitchen.
  static final Int32List _insistentFlag = Int32List.fromList(<int>[4]);

  /// Returns true only if the notification is actually on screen.
  ///
  /// This used to return void and swallow everything, so a failure was
  /// indistinguishable from success. Callers use the result to decide whether to
  /// take down the OS-rendered copy of the same push — and told it had worked
  /// when it had not, they removed the only alert the restaurant had left. In a
  /// release build the swallowed exception is not even printed, which is why
  /// this looked like "works in debug, silent in the APK".
  Future<bool> show({
    required String title,
    required String body,
    String? payload,
    bool isNewOrder = false,
    // Only meaningful when [isNewOrder] is true. A full-screen intent tells
    // Android to launch a full-screen Activity over whatever is currently
    // showing — appropriate when the app is backgrounded/terminated and the
    // screen may be locked, but firing it while the app is already open
    // races the OS's own full-screen takeover against the in-app "new order"
    // dialog this same event triggers, which is what was hanging the app
    // (and sometimes the whole phone) the instant an order came in while the
    // restaurant already had the app open. Foreground callers pass `false`.
    bool fullScreenIntent = true,
    // Gives a new-order alert a stable identity (fixed id + `new_order_<id>`
    // tag) so the push and socket copies of one order collapse into a single
    // notification, and so [dismissHandledOrderAlerts] can take it down once
    // the order is accepted/rejected. Without it the alert used a timestamp id
    // and `ongoing: true`, so it could never be removed — not by the app, not
    // by a swipe — after the order had long been handled.
    String? orderId,
    // When the order must be accepted by. The alert removes itself — and so
    // stops ringing — at that moment. Without one it rings until it is acted
    // on or the order is handled elsewhere ([dismissHandledOrderAlerts]).
    DateTime? acceptanceDeadline,
    // The over-other-apps request is up and ringing for this order: the tray
    // copy stays (Accept/Reject, lock screen, full-screen launch) but makes no
    // sound of its own, so only one thing rings.
    bool silent = false,
  }) async {
    if (!_initialized) {
      if (kDebugMode) {
        debugPrint('[LocalNotification] show() skipped — not initialized');
      }
      return false;
    }

    final channel = isNewOrder ? _newOrderChannel : _defaultChannel;
    final useFullScreen = isNewOrder && fullScreenIntent;
    final orderTag = (isNewOrder && orderId != null && orderId.isNotEmpty)
        ? '$_newOrderTagPrefix$orderId'
        : null;

    final remaining = acceptanceDeadline?.difference(DateTime.now());
    final timeoutAfterMs =
        (isNewOrder && remaining != null && remaining > Duration.zero)
        ? remaining.inMilliseconds
        : null;

    if (kDebugMode && isNewOrder) {
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await androidPlugin?.areNotificationsEnabled();
      debugPrint(
        '[LocalNotification] about to show new_order notification — '
        'channel: ${channel.id}, sound: tujh_bin, '
        'actions: [Accept($orderAcceptActionId), Reject($orderRejectActionId)], '
        'notificationsEnabledAtOsLevel: $enabled',
      );
    }

    try {
      await _plugin.show(
        orderTag != null
            ? _newOrderNotificationId
            : DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            // A new order is time-critical, so it still takes over a locked
            // screen (fullScreenIntent) and can't be swiped away without
            // acting on it (ongoing below). category: call was dropped —
            // several OEM skins (MIUI in particular, which this app already
            // special-cases for autostart) reformat "call" category
            // notifications into their own floating call UI and silently
            // drop custom actions, which is why Accept/Reject stopped
            // rendering as buttons.
            fullScreenIntent: useFullScreen,
            ongoing: useFullScreen,
            autoCancel: !useFullScreen,
            tag: orderTag,
            // Re-posting the same order (push + socket) must not ring twice.
            // (A re-post does not stop an insistent loop already running.)
            onlyAlertOnce: orderTag != null,
            // Rings until accepted, rejected, expired or handled elsewhere —
            // each of those paths cancels this notification.
            additionalFlags: (isNewOrder && !silent) ? _insistentFlag : null,
            // `alarm`, not `call` — see above for why `call` lost the
            // action buttons on MIUI.
            category: isNewOrder ? AndroidNotificationCategory.alarm : null,
            visibility: isNewOrder ? NotificationVisibility.public : null,
            timeoutAfter: timeoutAfterMs,
            sound: isNewOrder
                ? const RawResourceAndroidNotificationSound('tujh_bin')
                : null,
            playSound: !silent,
            silent: silent,
            styleInformation: isNewOrder ? BigTextStyleInformation(body) : null,
            actions: isNewOrder
                ? const [_acceptOrderAction, _rejectOrderAction]
                : null,
          ),
          iOS: DarwinNotificationDetails(
            sound: isNewOrder ? 'tujh_bin.mp3' : null,
            presentSound: true,
            // Cuts through Focus modes and shows on the lock screen at full
            // prominence — matches the Android `max` importance channel.
            interruptionLevel: isNewOrder
                ? InterruptionLevel.timeSensitive
                : InterruptionLevel.active,
          ),
        ),
        payload: payload,
      );
      if (kDebugMode && isNewOrder) {
        debugPrint('[LocalNotification] new_order notification posted OK');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          '[LocalNotification] show() threw for isNewOrder=$isNewOrder: $e',
        );
      }
      return false;
    }
  }
}
