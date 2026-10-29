import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:food_user_application/config/theme/app_theme.dart';
import 'package:food_user_application/core/services/audio_service.dart';
import 'package:food_user_application/core/services/local_notification_service.dart';
import 'package:food_user_application/core/services/order_notification_action_handler.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';
import 'package:food_user_application/features/orders/presentation/widgets/incoming_order_request_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The new-order request drawn over other apps — run by `overlayMain` in the
/// overlay plugin's own Flutter engine, where there is no Riverpod, router or
/// app session. It draws the same [IncomingOrderRequestView] as the in-app
/// request screen, reads its orders from [OrderOverlayService]'s pending
/// list, and answers them straight against the API.
///
/// It is the only thing ringing while it is up: the order's tray notification
/// is posted silent (see `firebaseMessagingBackgroundHandler`).
class OrderOverlayApp extends StatefulWidget {
  const OrderOverlayApp({super.key});

  @override
  State<OrderOverlayApp> createState() => _OrderOverlayAppState();
}

class _OrderOverlayAppState extends State<OrderOverlayApp> {
  /// The app's chosen theme (ThemeModeNotifier's key), so the overlay looks
  /// like the in-app screen on this device.
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier(ThemeMode.light);

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final saved = prefs.getString('app_theme_mode');
      if (saved == null) return;
      _themeMode.value = ThemeMode.values.firstWhere(
        (e) => e.toString() == saved,
        orElse: () => ThemeMode.light,
      );
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadThemeMode();
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        // Transparent around the floating card.
        color: Colors.transparent,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: mode,
        home: _OverlayRequestPage(onShown: _loadThemeMode),
      ),
    );
  }
}

class _OverlayRequestPage extends StatefulWidget {
  const _OverlayRequestPage({required this.onShown});

  final VoidCallback onShown;

  @override
  State<_OverlayRequestPage> createState() => _OverlayRequestPageState();
}

class _OverlayRequestPageState extends State<_OverlayRequestPage>
    with WidgetsBindingObserver {
  final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(DateTime.now());

  // The window is shrunk to the card so the rest of the screen stays visible
  // and usable behind it, instead of a full-screen grey sheet.
  final GlobalKey _cardKey = GlobalKey();
  double? _windowHeight;

  void _fitWindowToCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (!mounted || box == null || !box.hasSize) return;
      // Card plus its margins (8 top, 12 bottom) and a little shadow room.
      final height = (box.size.height + 28).clamp(120.0, 520.0).ceilToDouble();
      if (_windowHeight == height) return;
      _windowHeight = height;
      // Width -1 keeps the window full width; height is in dp.
      await FlutterOverlayWindow.resizeOverlay(-1, height.toInt(), false);
      // The plugin opens the window shifted up by the status bar height, but
      // treats that pixel value as dp, so on a 3x screen the top ~70dp of the
      // card ended up above the screen. Place it just below the status bar.
      // y is from the top: both start paths use top gravity (showForOrder's
      // topCenter, and NativeOverlayWindowSetup when NewOrderReceiver.kt
      // starts the service natively).
      await FlutterOverlayWindow.moveOverlay(const OverlayPosition(0, 32));
    });
  }
  List<OverlayOrder> _queue = const [];
  Timer? _ticker;
  int _ticks = 0;
  bool _muted = false;
  String? _actingOrderId;
  StreamSubscription<dynamic>? _messages;
  bool _syncing = false;
  bool _syncAgain = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = FlutterOverlayWindow.overlayListener.listen((message) {
      if (message == overlaySyncMessage) _sync();
    });
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messages?.cancel();
    _ticker?.cancel();
    _now.dispose();
    unawaited(OrderRingtone.stop());
    super.dispose();
  }

  // The engine outlives the window: it is created once and the window is
  // attached to it each time the overlay is shown. A new window shows up here
  // as a size change — the cue to re-read the orders.
  @override
  void didChangeMetrics() => _sync();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  /// Re-reads the pending list — the single source of truth, which the app,
  /// the notification actions and the FCM handler all write to.
  Future<void> _sync() async {
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    try {
      final active = await FlutterOverlayWindow.isActive();
      if (!mounted) return;
      if (!active) {
        // No window (the engine pre-starts with the app, or it was closed
        // from outside): nothing may ring unseen.
        _ticker?.cancel();
        _ticker = null;
        if (_queue.isNotEmpty) setState(() => _queue = const []);
        unawaited(OrderRingtone.stop());
        return;
      }

      final pending = await OrderOverlayService.readPending();
      final now = DateTime.now();
      final expired = {
        for (final o in pending)
          if (!o.deadline.isAfter(now) && o.orderId != _actingOrderId)
            o.orderId,
      };
      if (expired.isNotEmpty) await _expire(expired);
      if (!mounted) return;

      final live = [
        for (final o in pending)
          if (!expired.contains(o.orderId)) o,
      ];
      final known = {for (final o in _queue) o.orderId};
      final arrived = live.any((o) => !known.contains(o.orderId));
      if (arrived) widget.onShown();
      setState(() {
        _queue = live;
        // A new order rings again even if the previous one was muted.
        if (arrived) _muted = false;
      });
      _now.value = now;

      if (live.isEmpty) {
        await _closeWindow();
        return;
      }
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _syncRinging();
    } catch (_) {
      // Keep whatever is on screen; the next tick retries.
    } finally {
      _syncing = false;
      if (_syncAgain) {
        _syncAgain = false;
        unawaited(_sync());
      }
    }
  }

  void _tick() {
    if (!mounted) return;
    _ticks++;
    final now = DateTime.now();
    _now.value = now;
    final head = _queue.isEmpty ? null : _queue.first;
    if (_queue.any(
          (o) => o.orderId != _actingOrderId && !o.deadline.isAfter(now),
        ) ||
        _ticks % 3 == 0) {
      // Expiry, plus anything handled elsewhere in the meantime.
      unawaited(_sync());
    }
    // Answered on another device, or cancelled by the customer, while nobody
    // had the app open to notice.
    if (head != null && head.orderId != _actingOrderId && _ticks % 10 == 0) {
      unawaited(_checkStillOpen(head.orderId));
    }
  }

  Future<void> _checkStillOpen(String orderId) async {
    final status = await fetchOrderStatusDirect(orderId);
    if (status == null || status == 'created') return;
    if (orderId == _actingOrderId) return;
    await _drop(orderId);
  }

  void _syncRinging() {
    final shouldRing =
        !_muted && _queue.isNotEmpty && _actingOrderId == null;
    unawaited(shouldRing ? OrderRingtone.start() : OrderRingtone.stop());
  }

  /// Expired: off the overlay, alert taken down, not rejected — the order
  /// stays in the Orders list, as with the in-app screen.
  Future<void> _expire(Set<String> orderIds) async {
    await OrderOverlayService.removePending(orderIds);
    for (final id in orderIds) {
      await LocalNotificationService.instance.cancelOrderAlert(id);
    }
  }

  /// Gone from the overlay without an answer from here.
  Future<void> _drop(String orderId) async {
    await OrderOverlayService.removePending({orderId});
    await LocalNotificationService.instance.cancelOrderAlert(orderId);
    await _sync();
  }

  Future<void> _closeWindow() async {
    _ticker?.cancel();
    _ticker = null;
    await OrderRingtone.stop();
    await OrderOverlayService.close();
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _syncRinging();
  }

  void _setActing(String? orderId) {
    if (!mounted) return;
    setState(() => _actingOrderId = orderId);
    _syncRinging();
  }

  /// Accepts once (the claim is shared with the notification's Accept/Reject),
  /// then opens the app on the order.
  Future<void> _accept(OverlayOrder order) async {
    if (_actingOrderId != null) return;
    final id = order.orderId;
    _setActing(id);
    if (!await claimOrderAction(id)) {
      // Already answered from the notification.
      _setActing(null);
      await _drop(id);
      return;
    }
    final ok = await patchOrderStatusDirect(id, 'confirmed');
    if (ok) {
      await LocalNotificationService.instance.cancelOrderAlert(id);
      await OrderOverlayService.removePending({id});
      await OrderOverlayService.setOpenOrder(id);
    } else {
      // Left pending: the app takes it over on its request screen, where the
      // accept can be retried with the app's own session.
      await releaseOrderAction(id);
    }
    _setActing(null);
    await OrderOverlayService.launchApp();
    await _sync();
  }

  /// Rejects after a confirm, without opening the app.
  Future<void> _reject(OverlayOrder order) async {
    if (_actingOrderId != null) return;
    // The window is only as tall as the card; give the confirm dialog room,
    // then shrink back to the card.
    await FlutterOverlayWindow.resizeOverlay(-1, 460, false);
    if (!mounted) return;
    final confirmed = await confirmRejectOrder(context);
    _windowHeight = null;
    _fitWindowToCard();
    if (!confirmed || !mounted) return;
    final id = order.orderId;
    if (!_queue.any((o) => o.orderId == id)) return;
    _setActing(id);
    if (!await claimOrderAction(id)) {
      _setActing(null);
      await _drop(id);
      return;
    }
    final ok = await patchOrderStatusDirect(id, 'cancelled_by_restaurant');
    if (ok) {
      await OrderOverlayService.removePending({id});
      await LocalNotificationService.instance.cancelOrderAlert(id);
    } else {
      await releaseOrderAction(id);
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text("Couldn't reject the order. Please try again."),
          ),
        );
      }
    }
    _setActing(null);
    await _sync();
  }

  @override
  Widget build(BuildContext context) {
    final first = _queue.isEmpty ? null : _queue.first;
    _fitWindowToCard();
    return PopScope(
      // Same as in-app: a stray back press must not lose an order.
      canPop: false,
      child: IncomingOrderRequestView(
        compact: true,
        cardKey: _cardKey,
        orderCount: _queue.length,
        card: first == null
            ? null
            : IncomingOrderCardData.fromPushData(
                first.data,
                deadline: first.deadline,
                windowSeconds: first.windowSeconds,
              ),
        now: _now,
        muted: _muted,
        acting: _actingOrderId != null,
        onToggleSound: _toggleSound,
        onAccept: () {
          if (first != null) _accept(first);
        },
        onReject: () {
          if (first != null) _reject(first);
        },
      ),
    );
  }
}
