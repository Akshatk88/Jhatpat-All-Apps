import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:food_user_application/config/router/app_router.dart';
import 'package:food_user_application/config/theme/app_colors.dart';
import 'package:food_user_application/core/network/api_exception.dart';
import 'package:food_user_application/core/services/audio_service.dart';
import 'package:food_user_application/core/services/local_notification_service.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';
import 'package:food_user_application/features/orders/data/order_repository.dart';
import 'package:food_user_application/features/orders/domain/order_model.dart';
import 'package:food_user_application/features/orders/presentation/controllers/live_orders_controller.dart';
import 'package:food_user_application/features/orders/presentation/widgets/incoming_order_request_view.dart';

export 'package:food_user_application/features/orders/presentation/widgets/incoming_order_request_view.dart'
    show orderPaymentLabel;

/// How long a request stays on screen when neither the push nor the order
/// carries an `acceptanceDeadlineAt`. Expiry only closes the card and stops
/// the ringing — the order itself stays in the Orders list untouched.
const _defaultAcceptWindow = Duration(seconds: 60);

/// Routes that exist before a restaurant session does. The request screen is
/// never put over these: the splash screen replaces its whole route stack
/// right after the session is restored, which would silently tear down a
/// screen pushed on top of it.
const _preSessionPaths = {
  '/',
  '/onboarding',
  '/login',
  '/register',
  '/register/success',
  '/application-status',
};

/// One new order waiting for Accept/Reject on the request screen.
///
/// Rendered from the push data first (it carries everything the card shows,
/// so a cold start over the lock screen does not have to wait for the API),
/// and from the full order once it has been loaded — which wins, being the
/// server's current truth.
class IncomingOrderRequest {
  IncomingOrderRequest._({
    required this.orderId,
    required this.data,
    required this.order,
    required this.deadline,
    required this.windowSeconds,
    required this.openDetailsIfHandled,
  });

  final String orderId;
  final Map<String, dynamic> data;
  OrderModel? order;
  final DateTime deadline;
  final int windowSeconds;

  /// Set when the restaurant opened this from the notification: if the order
  /// turns out to be handled already, they land on its details instead.
  bool openDetailsIfHandled;

  bool _resolving = false;
  bool _resolved = false;

  bool matches(OrderModel o) =>
      o.id == orderId ||
      o.displayId == orderId ||
      (order != null && order!.id.isNotEmpty && o.id == order!.id);

  /// The id the status endpoint expects (the Mongo id).
  String get statusTargetId =>
      (order != null && order!.id.isNotEmpty) ? order!.id : orderId;

  String? _str(String key) {
    final v = data[key]?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  double? get total => order?.total ?? double.tryParse(_str('total') ?? '');

  String? get paymentLabel {
    final m = order?.paymentMethod ?? '';
    return orderPaymentLabel(m.isNotEmpty ? m : _str('paymentMethod'));
  }

  int? get itemCount {
    final o = order;
    if (o != null && o.items.isNotEmpty) {
      return o.items.fold<int>(0, (sum, i) => sum + i.quantity);
    }
    return int.tryParse(_str('itemCount') ?? '');
  }

  String? get customerName {
    final name = order?.customerName ?? '';
    return name.isNotEmpty ? name : _str('customerName');
  }

  String? get address {
    final a = order?.deliveryAddress.fullAddress ?? '';
    return a.isNotEmpty ? a : _str('address');
  }

  String? get itemsSummary {
    final o = order;
    if (o != null && o.items.isNotEmpty) {
      return o.items.map((i) => '${i.quantity}x ${i.name}').join(', ');
    }
    return _str('itemsList');
  }

  String? get displayId {
    final d = order?.displayId ?? '';
    return d.isNotEmpty ? d : _str('orderDisplayId');
  }
}

/// Pending requests, oldest first. The screen shows the first one.
final ValueNotifier<List<IncomingOrderRequest>> _queue =
    ValueNotifier<List<IncomingOrderRequest>>(const []);

/// The same order reaches the app several times — the backend sends a plain
/// and a data-only push, plus the socket event — possibly after the first
/// card was already answered. Each order is presented once per process unless
/// the restaurant explicitly opens it again from its notification.
final Set<String> _presentedOrderIds = <String>{};

bool _requestRouteActive = false;

/// Queues [orderId] on the full-screen new-order request screen, opening the
/// screen if it is not up yet.
///
/// Returns true when the order is (or already was) taken care of in-app, so
/// the caller does not need a ringing notification of its own; false when
/// there is no UI to show it on.
///
/// [fromNotification] is for an explicit open from the notification (tap,
/// full-screen intent on the lock screen): it re-presents an order shown
/// before, and lands on the order's details if it was already handled.
bool showIncomingOrderRequest({
  required String orderId,
  Map<String, dynamic>? data,
  OrderModel? order,
  bool fromNotification = false,
}) {
  if (orderId.isEmpty) return false;
  for (final r in _queue.value) {
    if (r.orderId == orderId) {
      if (fromNotification) r.openDetailsIfHandled = true;
      return true;
    }
  }
  if (!fromNotification && _presentedOrderIds.contains(orderId)) return true;
  if (rootNavigatorKey.currentState == null) return false;

  final payload = data == null
      ? <String, dynamic>{}
      : Map<String, dynamic>.from(data);
  final now = DateTime.now();
  final serverDeadline =
      DateTime.tryParse(payload['acceptanceDeadlineAt']?.toString() ?? '') ??
      order?.acceptanceDeadlineAt;
  // A deadline already behind the device clock is far more often clock skew
  // than a dead order — and a missed order costs more than a stale card, whose
  // Accept the server will simply refuse.
  final deadline = (serverDeadline != null && serverDeadline.isAfter(now))
      ? serverDeadline
      : now.add(_defaultAcceptWindow);

  _presentedOrderIds.add(orderId);
  _queue.value = [
    ..._queue.value,
    IncomingOrderRequest._(
      orderId: orderId,
      data: payload,
      order: order,
      deadline: deadline,
      windowSeconds: math.max(1, deadline.difference(now).inSeconds),
      openDetailsIfHandled: fromNotification,
    ),
  ];
  unawaited(_ensureRequestScreen());
  return true;
}

/// Drops [orderId] from the request screen — it was accepted/rejected from its
/// notification. Closes the screen when nothing else is waiting.
void dismissIncomingOrderRequest(String orderId) {
  final remaining = [
    for (final r in _queue.value)
      if (r.orderId != orderId && r.order?.id != orderId) r,
  ];
  if (remaining.length != _queue.value.length) _queue.value = remaining;
}

/// The app went to the background with requests still on screen: move them
/// to the over-other-apps overlay, so they stay in sight over whatever app is
/// opened next, and drop them here — which closes this screen and stops its
/// ringing. One ringing source at a time; the overlay hands them back when the
/// app returns ([OrderOverlayService.takeOver]). Without the permission, or
/// if the overlay can't be shown, they simply stay here as before.
Future<void> handOffIncomingRequestsToOverlay() async {
  final pending = List.of(_queue.value);
  if (pending.isEmpty || !await OrderOverlayService.hasPermission()) return;
  for (final r in pending) {
    if (!_queue.value.contains(r)) continue;
    final id = r.statusTargetId;
    final total = r.total;
    final data = <String, dynamic>{
      ...r.data,
      'type': 'new_order',
      'orderId': id,
      'orderMongoId': id,
      'orderDisplayId': ?r.displayId,
      'customerName': ?r.customerName,
      'address': ?r.address,
      'itemsList': ?r.itemsSummary,
      if (r.itemCount != null) 'itemCount': '${r.itemCount}',
      if (total != null) 'total': '$total',
      'paymentMethod': ?r.paymentLabel,
      'acceptanceDeadlineAt': r.deadline.toUtc().toIso8601String(),
    };
    if (!await OrderOverlayService.showForOrder(data)) return;
    dismissIncomingOrderRequest(r.orderId);
    // Lets the app present it again when the overlay hands it back.
    _presentedOrderIds
      ..remove(r.orderId)
      ..remove(id);
  }
}

/// The root navigator, once the app is past splash/login and showing the
/// restaurant's own screens. Null if that does not happen within ~15s.
///
/// A notification can open the app cold, while the session is still being
/// restored; anything pushed then is wiped by the splash screen's own
/// navigation a moment later.
Future<NavigatorState?> waitForOrdersUi() async {
  var waited = false;
  for (var i = 0; i < 60; i++) {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx != null && ctx.mounted && rootNavigatorKey.currentState != null) {
      var path = '';
      try {
        path =
            GoRouter.maybeOf(
              ctx,
            )?.routerDelegate.currentConfiguration.uri.path ??
            '';
      } catch (_) {
        // Router not ready yet.
      }
      if (path.isNotEmpty && !_preSessionPaths.contains(path)) {
        // Splash follows the auth redirect with its own go('/orders'); let it
        // land before putting anything on top.
        if (waited) await Future.delayed(const Duration(milliseconds: 500));
        return rootNavigatorKey.currentState;
      }
    }
    waited = true;
    await Future.delayed(const Duration(milliseconds: 250));
  }
  return null;
}

Future<void> _ensureRequestScreen() async {
  if (_requestRouteActive) return;
  _requestRouteActive = true;
  var shown = false;
  try {
    final navigator = await waitForOrdersUi();
    if (navigator == null || _queue.value.isEmpty) return;
    shown = true;
    await navigator.push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const IncomingOrderRequestScreen(),
      ),
    );
  } catch (e) {
    if (kDebugMode) debugPrint('IncomingOrderRequest: could not show: $e');
  } finally {
    _requestRouteActive = false;
    // Whatever closed the screen, nothing may keep ringing behind it.
    unawaited(OrderRingtone.stop());
    if (_queue.value.isNotEmpty) {
      if (shown) {
        // An order arrived while the screen was closing, or the screen was
        // torn down by navigation: bring it back for what is still waiting.
        unawaited(_ensureRequestScreen());
      } else {
        // No restaurant UI to show it on (signed out) — nothing to wait for.
        _queue.value = const [];
      }
    }
  }
}

/// Full-screen new-order request, laid out like a captain app's offer card:
/// the amount up front, who and what on a two-stop timeline, one big Accept,
/// and the countdown ring doubling as the Reject button.
///
/// Rings (looped `tujh_bin`) until the order is accepted, rejected, expires,
/// or the sound is muted. Several pending orders queue up behind each other,
/// one card at a time.
class IncomingOrderRequestScreen extends ConsumerStatefulWidget {
  const IncomingOrderRequestScreen({super.key});

  @override
  ConsumerState<IncomingOrderRequestScreen> createState() =>
      _IncomingOrderRequestScreenState();
}

class _IncomingOrderRequestScreenState
    extends ConsumerState<IncomingOrderRequestScreen> {
  /// A ValueNotifier rather than setState so the per-second tick rebuilds only
  /// the countdown rings, not the whole card.
  final ValueNotifier<DateTime> _now = ValueNotifier<DateTime>(DateTime.now());
  Timer? _ticker;
  bool _muted = false;
  bool _closing = false;
  String? _actingOrderId;
  int _lastQueueLength = 0;

  /// Orders whose tray alert has been taken down — this screen rings instead.
  final Set<String> _silencedAlerts = <String>{};

  @override
  void initState() {
    super.initState();
    _queue.addListener(_onQueueChanged);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    WidgetsBinding.instance.addPostFrameCallback((_) => _onQueueChanged());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _queue.removeListener(_onQueueChanged);
    _now.dispose();
    unawaited(OrderRingtone.stop());
    super.dispose();
  }

  void _onQueueChanged() {
    if (!mounted || _closing) return;
    final queue = _queue.value;
    if (queue.isEmpty) {
      _close();
      return;
    }
    // A new order rings again even if the previous one was muted.
    if (queue.length > _lastQueueLength) _muted = false;
    _lastQueueLength = queue.length;
    for (final r in queue) {
      if (_silencedAlerts.add(r.orderId)) {
        unawaited(LocalNotificationService.instance.cancelOrderAlert(r.orderId));
      }
      unawaited(_resolve(r));
    }
    _syncRinging();
    setState(() {});
  }

  void _syncRinging() {
    final shouldRing =
        !_muted && !_closing && _queue.value.isNotEmpty && _actingOrderId == null;
    unawaited(shouldRing ? OrderRingtone.start() : OrderRingtone.stop());
  }

  void _tick() {
    if (!mounted) return;
    final now = DateTime.now();
    _now.value = now;
    final queue = _queue.value;
    // Expired: just close that card and stop ringing for it. The order is not
    // rejected — it stays in the Orders list for the restaurant to act on.
    final live = [
      for (final r in queue)
        if (r.orderId == _actingOrderId || r.deadline.isAfter(now)) r,
    ];
    if (live.length != queue.length) _queue.value = live;
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    unawaited(OrderRingtone.stop());
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      // A dialog (the reject confirmation) is on top — take this out from
      // under it rather than popping the dialog instead.
      Navigator.of(context).removeRoute(route);
    }
  }

  void _remove(IncomingOrderRequest r) {
    _queue.value = [
      for (final x in _queue.value)
        if (!identical(x, r)) x,
    ];
  }

  OrderModel? _fromLiveList(IncomingOrderRequest r) {
    final orders = ref.read(liveOrdersControllerProvider).value;
    return orders?.where(r.matches).firstOrNull;
  }

  Future<void> _resolve(IncomingOrderRequest r) async {
    if (r._resolved || r._resolving) return;
    if (r.order != null) {
      r._resolved = true;
      return;
    }
    r._resolving = true;
    OrderModel? order = _fromLiveList(r);
    // A push can beat the order being readable from the API by a beat — a
    // couple of quick retries cover that timing gap.
    for (var attempt = 0; order == null && attempt < 3; attempt++) {
      if (attempt > 0) await Future.delayed(const Duration(milliseconds: 700));
      if (!mounted) break;
      try {
        order = await ref.read(orderRepositoryProvider).getById(r.orderId);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('IncomingOrderRequest: fetch failed (attempt $attempt): $e');
        }
      }
    }
    r._resolving = false;
    r._resolved = true;
    if (!mounted || !_queue.value.contains(r)) return;
    // Not loadable: keep the card on the push data — Accept/Reject work by id.
    if (order == null) {
      setState(() {});
      return;
    }
    r.order = order;
    if (order.orderStatus != 'created') {
      _handledElsewhere(r, order);
      return;
    }
    setState(() {});
  }

  /// The order is past accept/reject — accepted or rejected from the
  /// notification or another device, or cancelled by the customer.
  void _handledElsewhere(IncomingOrderRequest r, OrderModel order) {
    _remove(r);
    final targetId = order.id.isNotEmpty ? order.id : r.orderId;
    if (r.openDetailsIfHandled) {
      final ctx = rootNavigatorKey.currentContext;
      if (ctx != null) GoRouter.of(ctx).push('/order-details/$targetId');
      return;
    }
    final label = r.displayId != null ? ' #${r.displayId}' : '';
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          order.isCancelled
              ? 'Order$label was cancelled.'
              : 'Order$label was already handled.',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleSound() {
    setState(() => _muted = !_muted);
    _syncRinging();
  }

  Future<void> _accept(IncomingOrderRequest r) =>
      _respond(r, 'confirmed', failure: 'Failed to accept the order.');

  Future<void> _reject(IncomingOrderRequest r) async {
    if (_actingOrderId != null) return;
    final confirmed = await confirmRejectOrder(context);
    if (!confirmed || !mounted || !_queue.value.contains(r)) return;
    await _respond(
      r,
      'cancelled_by_restaurant',
      failure: 'Failed to reject the order.',
    );
  }

  /// Same calls as Accept/Reject on the live order card.
  Future<void> _respond(
    IncomingOrderRequest r,
    String orderStatus, {
    required String failure,
  }) async {
    if (_actingOrderId != null) return;
    setState(() => _actingOrderId = r.orderId);
    _syncRinging();
    final controller = ref.read(liveOrdersControllerProvider.notifier);
    try {
      await controller.updateStatus(r.statusTargetId, orderStatus);
      _actingOrderId = null;
      _remove(r);
      if (mounted) {
        setState(() {});
        _syncRinging();
      }
    } catch (e) {
      _actingOrderId = null;
      if (!mounted) return;
      setState(() {});
      _syncRinging();
      final message = e is ApiException ? e.message : '$failure Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Closes a card as soon as the list shows its order past `created` —
    // handled from the notification, another device, or cancelled. Absent
    // from the list is not "gone": a push can beat the order being listable.
    ref.listen<AsyncValue<List<OrderModel>>>(liveOrdersControllerProvider, (
      prev,
      next,
    ) {
      final orders = next.value;
      if (orders == null || !mounted) return;
      var changed = false;
      for (final r in List.of(_queue.value)) {
        if (r.orderId == _actingOrderId) continue;
        final match = orders.where(r.matches).firstOrNull;
        if (match == null) continue;
        if (match.orderStatus != 'created') {
          _handledElsewhere(r, match);
        } else if (r.order == null) {
          r.order = match;
          changed = true;
        }
      }
      if (changed && mounted) setState(() {});
    });

    final queue = _queue.value;
    final first = queue.isEmpty ? null : queue.first;

    return PopScope(
      // Accept, reject, mute or let it run out — a stray back press must not
      // be how a new order gets lost.
      canPop: false,
      child: IncomingOrderRequestView(
        orderCount: queue.length,
        card: first == null ? null : _cardData(first),
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

  IncomingOrderCardData _cardData(IncomingOrderRequest r) =>
      IncomingOrderCardData(
        deadline: r.deadline,
        windowSeconds: r.windowSeconds,
        total: r.total,
        paymentLabel: r.paymentLabel,
        itemCount: r.itemCount,
        displayId: r.displayId,
        customerName: r.customerName,
        address: r.address,
        itemsSummary: r.itemsSummary,
        loading: r._resolving && r.order == null,
      );
}
