import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_user_application/core/services/fcm_service.dart';
import 'package:food_user_application/core/services/local_notification_service.dart';
import 'package:food_user_application/core/services/order_overlay_service.dart';
import 'package:food_user_application/core/services/socket_service.dart';
import 'package:food_user_application/features/orders/data/order_repository.dart';
import 'package:food_user_application/features/orders/domain/order_model.dart';
import 'package:food_user_application/features/orders/presentation/views/incoming_order_dialog.dart';

/// Backs the main Orders tab: one list of current orders, bucketed
/// client-side into the 7 status tabs (see [OrderModel.restaurantBucket]),
/// kept fresh by the `new_order` / `order_status_update` socket events.
///
/// Socket.IO never replays events missed while disconnected (app
/// backgrounded, brief network drop, etc.), so a status change like a
/// cancellation during that window would otherwise sit stale until a manual
/// pull-to-refresh — also refresh on reconnect and on app resume to close
/// that gap.
class LiveOrdersController extends AsyncNotifier<List<OrderModel>> {
  bool _socketWired = false;
  AppLifecycleListener? _lifecycleListener;

  @override
  Future<List<OrderModel>> build() async {
    await _wireSocket();
    _lifecycleListener ??= AppLifecycleListener(onResume: _onResume);
    ref.onDispose(() => _lifecycleListener?.dispose());
    return _fetch();
  }

  Future<List<OrderModel>> _fetch() async {
    final orders = await ref.read(orderRepositoryProvider).listCurrent();
    // An order that is past accept/reject no longer needs its ringing,
    // non-swipeable new-order alert — whoever handled it, wherever.
    final handled = <String>{
      for (final o in orders)
        if (o.orderStatus != 'created') ...[o.id, o.displayId],
    }..remove('');
    unawaited(
      LocalNotificationService.instance.dismissHandledOrderAlerts(handled),
    );
    // ...and the over-other-apps request, if it is up for one of them.
    unawaited(OrderOverlayService.dismissOrders(handled));
    return orders;
  }

  /// A `new_order` socket event is the only alert the restaurant gets while the
  /// app is open if the push is lost or delayed (FCM throttling, or a backend
  /// sending through a Firebase project this app's token is not registered
  /// with). It used to only refresh the list silently; surface it the same way
  /// the foreground push does. Both paths are deduplicated per order.
  void _onSocketNewOrder(dynamic data) {
    refresh();
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final map = data is Map ? data : const {};
    final rawOrder = map['order'];
    final order = rawOrder is Map ? rawOrder : const {};
    final orderId = [
      map['orderMongoId'],
      map['orderId'],
      map['_id'],
      order['_id'],
      order['id'],
    ].map((v) => v?.toString() ?? '').firstWhere(
      (v) => v.isNotEmpty,
      orElse: () => '',
    );
    if (orderId.isEmpty) return;

    // The socket payload is the order document itself, so the request card
    // can render from it straight away without another fetch.
    OrderModel? seed;
    if (order.isNotEmpty || map['items'] is List) {
      try {
        seed = OrderModel.fromJson(
          Map<String, dynamic>.from(order.isNotEmpty ? order : map),
        );
        if (seed.id != orderId || seed.orderStatus != 'created') seed = null;
      } catch (_) {
        seed = null;
      }
    }

    // The request screen rings in-app; the notification is only the fallback
    // when there is no UI to put it on.
    if (showIncomingOrderRequest(
      orderId: orderId,
      data: Map<String, dynamic>.from(map),
      order: seed,
    )) {
      return;
    }

    LocalNotificationService.instance.show(
      title: 'New order received',
      body: buildOrderNotificationBody(Map<String, dynamic>.from(map)),
      payload: jsonEncode({'type': 'new_order', 'orderId': orderId}),
      isNewOrder: true,
      fullScreenIntent: false,
      orderId: orderId,
    );
  }

  /// Back in the foreground: refresh, then bring any order whose new-order
  /// alert is still ringing in the tray onto the request screen — the
  /// restaurant opened the app some other way than through that alert.
  Future<void> _onResume() async {
    await refresh();
    final alerting = await LocalNotificationService.instance
        .activeOrderAlertIds();
    if (alerting.isEmpty) return;
    for (final o in state.value ?? const <OrderModel>[]) {
      if (o.orderStatus != 'created') continue;
      if (alerting.contains(o.id) || alerting.contains(o.displayId)) {
        showIncomingOrderRequest(
          orderId: o.id.isNotEmpty ? o.id : o.displayId,
          order: o,
          fromNotification: true,
        );
      }
    }
  }

  Future<void> _wireSocket() async {
    if (_socketWired) return;
    _socketWired = true;
    final socket = ref.read(socketServiceProvider);
    await socket.connect();
    socket.on('new_order', _onSocketNewOrder);
    socket.on('order_status_update', (_) => refresh());
    socket.on('order_cancelled', (_) => refresh());
    socket.on('cancel_order', (_) => refresh());
    socket.on('order_accepted', (_) => refresh());
    socket.on('order_rejected', (_) => refresh());
    socket.on('connect', (_) => refresh());
    ref.onDispose(() {
      socket.off('new_order');
      socket.off('order_status_update');
      socket.off('order_cancelled');
      socket.off('cancel_order');
      socket.off('order_accepted');
      socket.off('order_rejected');
      socket.off('connect');
    });
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> updateStatus(
    String orderId,
    String orderStatus, {
    String? note,
  }) async {
    await ref
        .read(orderRepositoryProvider)
        .updateStatus(orderId, orderStatus, note: note);
    await refresh();
  }

  Future<void> resendNotification(String orderId) async {
    await ref.read(orderRepositoryProvider).resendNotification(orderId);
  }
}

final liveOrdersControllerProvider =
    AsyncNotifierProvider<LiveOrdersController, List<OrderModel>>(
      LiveOrdersController.new,
    );
