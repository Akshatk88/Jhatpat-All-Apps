import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/design_system/components/layout/app_refresh_indicator.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/maps/geo_math.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/modules/food/data/models/order_model.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/shared/support/presentation/chat/screens/chat_screen.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/design_system/components/skeletons/skeleton_loading.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/modules/food/presentation/coupons/viewmodels/coupons_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/home/viewmodels/banners_viewmodel.dart';
import 'package:superapp_user/app/routing/route_names.dart';
import 'package:superapp_user/modules/food/data/models/chat_model.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/active_order_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/order_conversations_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/order_tracking_viewmodel.dart';
import 'package:superapp_user/modules/food/presentation/orders/widgets/live_tracking_map.dart';

class OrderTrackingScreen extends ConsumerStatefulWidget {
  final String orderId;

  const OrderTrackingScreen({super.key, required this.orderId});

  @override
  ConsumerState<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends ConsumerState<OrderTrackingScreen> {
  @override
  void initState() {
    super.initState();
    if (kDebugMode) debugPrint('[TRACKING] Tracking page opened for order: ${widget.orderId}');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(orderTrackingProvider.notifier).start(widget.orderId);
    });
  }

  @override
  void dispose() {
    ref.read(orderTrackingProvider.notifier).stop();
    super.dispose();
  }

  /// Back that always resolves: pops when there's a stack, else falls back to
  /// the orders list (the push-notification deep-link case).
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(RouteNames.orders);
    }
  }

  Future<void> _refresh() => ref.read(orderTrackingProvider.notifier).refresh();

  @override
  Widget build(BuildContext context) {
    ref.listen<OrderTrackingState>(orderTrackingProvider, (previous, next) {
      final order = next.order;
      if (order == null) return;

      if (!order.isActive) {
        ref.read(orderTrackingProvider.notifier).stop();
        ref.read(activeOrderViewModelProvider.notifier).fetchActiveOrder();

        if (mounted) {
          if (order.isCancelled) {
            final reason = order.cancellationReason.isNotEmpty
                ? order.cancellationReason
                : 'Order has been cancelled.'.tr;
            AppSnackbar.error(context, reason, duration: const Duration(seconds: 4));
          } else if (order.isDelivered || order.orderStatus == 'completed') {
            AppSnackbar.success(
              context,
              '🎉 Order Delivered! Enjoy your meal.'.tr,
              duration: const Duration(seconds: 4),
            );
            context.go('/orders/delivered/${order.id}');
            return;
          }

          context.go(RouteNames.home);
        }
      }
    });

    final state = ref.watch(orderTrackingProvider);
    final order = state.order;
    final theme = Theme.of(context);

    if (order != null && !order.isActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(orderTrackingProvider.notifier).stop();
          ref.read(activeOrderViewModelProvider.notifier).fetchActiveOrder();
          if (order.isDelivered || order.orderStatus == 'completed') {
            context.go('/orders/delivered/${order.id}');
          } else {
            context.go(RouteNames.home);
          }
        }
      });
    }

    final isDark = theme.brightness == Brightness.dark;
    final showOrangeHeader = !state.isLoading && order != null;

    final overlayStyle = showOrangeHeader
        ? SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          )
        : (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: theme.brightness == Brightness.dark
            ? AppColors.backgroundDark
            : const Color(0xFFF4F5F7),
        body: Column(
          children: [
            if (showOrangeHeader) ...[
              Container(
                height: MediaQuery.of(context).padding.top,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFFFB800), Color(0xFFFFC700)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
              _TrackingHeader(
                order: order,
                state: state,
                onBack: _goBack,
                onShare: () => _shareOrder(order),
              ),
            ],
            Expanded(
              child: SafeArea(
                top: !showOrangeHeader,
                child: state.isLoading && order == null
                    ? const SkeletonOrderTracking()
                    : order == null
                        ? _ErrorState(message: state.error, onRetry: _refresh, onBack: _goBack)
                        : AppRefreshIndicator(
                            onRefresh: _refresh,
                            child: CustomScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                SliverToBoxAdapter(child: _MapSection(order: order, state: state)),
            
                                SliverPadding(
                                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                                  sliver: SliverList.list(
                                    children: [
                                      if (state.dropOtp != null && state.dropOtp!.isNotEmpty)
                                        _DropOtpCard(otp: state.dropOtp!),
                                      const _PromoBannerCarousel(),
                                      const _CouponCards(),
                                      if (order.hasRider)
                                        _DeliveryPartnerCard(
                                          partner: order.deliveryPartner!,
                                          statusLabel: order.statusLabel,
                                          onCall: () => _dial(order.deliveryPartner!.phone),
                                          onChat: () => _openChat(order),
                                          unread: riderUnreadCount(
                                            ref.watch(orderConversationsProvider(order.id)).value ??
                                                const <ChatConversation>[],
                                          ),
                                        ),
                                      const _SafetyCard(),
                                      _DeliveryDetailsCard(order: order),
                                      _OrderSummaryCard(order: order),
                                      _StatusTimelineCard(order: order),
                                      // Cancel is offered only while the backend still
                                      // allows it (before the food is on its way).
                                      if (order.canCancel)
                                        _CancelButton(onCancel: _confirmCancel),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancel() async {
    Haptics.medium();
    final reason = await askCancelReason(
      context,
      title: 'Cancel order?',
      reasons: CancelReasons.food,
      confirmLabel: 'Cancel order',
      keepLabel: 'Keep order',
    );
    if (reason == null || !mounted) return;

    final err = await ref.read(orderTrackingProvider.notifier).cancel(reason: reason);
    if (!mounted) return;
    if (err != null) {
      AppSnackbar.error(context, err);
    } else {
      AppSnackbar.success(context, 'Order cancelled.'.tr);
      _goBack();
    }
  }

  void _openChat(OrderModel order) {
    Haptics.light();
    final partner = order.deliveryPartner;
    if (partner == null) return;
    context.push(
      RouteNames.chat,
      extra: ChatArgs(
        orderId: order.id,
        peerId: partner.id,
        peerName: partner.name.isEmpty ? 'Delivery partner'.tr : partner.name,
      ),
    );
  }

  Future<void> _dial(String phone) async {
    Haptics.light();
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else if (mounted) {
      AppSnackbar.error(context, 'Could not open the dialer.'.tr);
    }
  }

  void _shareOrder(OrderModel order) {
    Haptics.light();
    final id = order.orderNumber.isNotEmpty ? order.orderNumber : order.id;
    final parts = [
      order.restaurantName.isEmpty
          ? 'My JhatPat order'.tr
          : 'My JhatPat order from {name}'.trArgs({'name': order.restaurantName}),
      if (order.statusLabel.isNotEmpty) 'Status: {status}'.trArgs({'status': order.statusLabel.tr}),
      if (order.etaLabel != null) order.etaLabel!,
      if (id.isNotEmpty) 'Order {id}'.trArgs({'id': id}),
    ];
    SharePlus.instance.share(ShareParams(text: parts.join('\n')));
  }
}

// ─────────────────────────────────────────────────────────── header + map

class _TrackingHeader extends StatelessWidget {
  final OrderModel order;
  final OrderTrackingState state;
  final VoidCallback onBack;
  final VoidCallback onShare;

  const _TrackingHeader({
    required this.order,
    required this.state,
    required this.onBack,
    required this.onShare,
  });

  /// Remaining time/distance along the current route from the rider's live
  /// position, recomputed on every state change so it counts down as they move.
  /// Null until a route and a real rider fix exist (then etaLabel is used).
  ({int mins, double km, DateTime arrival})? get _liveEta {
    final pts = state.routePoints;
    final lat = state.riderLat;
    final lng = state.riderLng;
    if (pts.length < 2 || lat == null || lng == null || !state.hasRiderFix) return null;
    if (state.routeTarget == null) return null;

    final route = [for (final p in pts) LatLng(p.latitude, p.longitude)];
    final rider = LatLng(lat, lng);
    var bestIdx = 0;
    var bestDist = double.infinity;
    var bestPoint = route.first;
    for (var i = 0; i < route.length - 1; i++) {
      final hit = GeoMath.projectOnSegment(rider, route[i], route[i + 1]);
      final d = GeoMath.distance(rider, hit.point);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
        bestPoint = hit.point;
      }
    }
    final meters =
        GeoMath.distance(bestPoint, route[bestIdx + 1]) + GeoMath.pathLength(route, bestIdx + 1);

    // Router pace for this leg; 20 km/h when the response lacked either figure.
    final mins = state.routeDurationMins;
    final km = state.routeDistanceKm;
    final secPerMeter = (mins != null && km != null && mins > 0 && km > 0)
        ? (mins * 60) / (km * 1000)
        : 3.6 / 20;
    final seconds = meters * secPerMeter;
    return (
      mins: math.max(1, (seconds / 60).ceil()),
      km: meters / 1000,
      arrival: DateTime.now().add(Duration(seconds: seconds.round())),
    );
  }

  String get _displayStatusText {
    if (order.isDelivered) return 'Delivered'.tr;
    if (order.isCancelled) return order.statusLabel.tr;
    final live = _liveEta;
    if (live != null) {
      return (state.routeTarget == 'restaurant'
              ? 'Rider reaching restaurant in {min} min'
              : 'Delivery in {min} min')
          .trArgs({'min': live.mins});
    }
    final eta = order.etaLabel;
    if (eta != null && eta != 'Calculating...') {
      return '{eta} • On Time'.trArgs({'eta': eta});
    }
    if (order.isAwaitingAcceptance || order.dispatchStatus == 'searching') {
      return 'Waiting for delivery partner'.tr;
    }
    return order.statusLabel.tr;
  }

  @override
  Widget build(BuildContext context) {
    final showGif = order.isActive;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFB800), Color(0xFFFFC700)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CircleButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    order.restaurantName.isEmpty ? 'Your order'.tr : order.restaurantName,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF121212), fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              _CircleButton(icon: Icons.share_outlined, onTap: onShare),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 6,
              children: [
                Text(
                  _displayStatusText,
                  style: const TextStyle(
                    color: Color(0xFF121212),
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                if (showGif) const _DeliveryGifWidget(),
              ],
            ),
          ),
          if (order.isActive && _liveEta != null) ...[
            const SizedBox(height: 4),
            Text(
              '{km} km away · Arrives {time}'.trArgs({
                'km': _liveEta!.km.toStringAsFixed(1),
                'time': DateFormat('h:mm a').format(_liveEta!.arrival),
              }),
              style: const TextStyle(
                color: Color(0xFF3F3F46),
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DeliveryGifWidget extends StatelessWidget {
  const _DeliveryGifWidget();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 62,
      child: Image.asset(
        'assets/gif/delivery.gif',
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(
            'assets/images/delivery.gif',
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return const Icon(
                Icons.directions_bike_rounded,
                color: Color(0xFF121212),
                size: 42,
              );
            },
          );
        },
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF121212), size: 20),
      ),
    );
  }
}

/// Chooses the map surface:
///  * a real [LiveTrackingMap] once the order is out for delivery and we have
///    the rider's coordinates (the reference's "show map after pickup"), or
///  * a styled preview before that / when coordinates aren't available yet.
///
/// The real map needs a Google Maps API key in the manifest to render tiles;
/// all marker/route/animation logic runs regardless of the key.
class _MapSection extends StatelessWidget {
  final OrderModel order;
  final OrderTrackingState state;

  const _MapSection({required this.order, required this.state});

  void _showExpandedMapBottomSheet(BuildContext context) {
    Haptics.light();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      // The sheet's drag-to-dismiss competed with the map for vertical drags and
      // pinches, so the expanded map could not be panned or zoomed. There is a
      // close button, so dragging was never the only way out.
      enableDrag: false,
      builder: (modalContext) {
        final isDark = Theme.of(modalContext).brightness == Brightness.dark;
        final screenHeight = MediaQuery.of(modalContext).size.height;
        final targetHeight = screenHeight * 0.70;

        return Container(
          height: targetHeight,
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Consumer(
              builder: (context, ref, child) {
                final liveState = ref.watch(orderTrackingProvider);
                final liveOrder = liveState.order ?? order;

                // No hardcoded coordinate fallbacks. They used to default to
                // Indore's centre, so a missing coordinate rendered as a real place
                // that could be hundreds of km from the customer. The map treats
                // null as "unknown" and simply omits that marker.
                final resLat = liveState.restaurantLat ?? liveOrder.restaurantLat;
                final resLng = liveState.restaurantLng ?? liveOrder.restaurantLng;
                final custLat = liveState.customerLat ?? liveOrder.dropLat;
                final custLng = liveState.customerLng ?? liveOrder.dropLng;
                // Only ever a genuine fix — hasRiderFix distinguishes a real ping
                // from the RTDB node's accept-time restaurant coordinates.
                final rLat = liveState.hasRiderFix ? liveState.riderLat : null;
                final rLng = liveState.hasRiderFix ? liveState.riderLng : null;

                return Column(
                  children: [
                    // Top Drag Handle & Title Bar
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.cardDark : Colors.white,
                        border: Border(
                          bottom: BorderSide(
                            color: isDark ? AppColors.borderDark : const Color(0xFFE2E4E8),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Drag Handle Pill
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white30 : Colors.black26,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.delivery_dining_rounded,
                                  color: AppColors.primary,
                                  size: 22,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      liveOrder.statusLabel.isNotEmpty
                                          ? liveOrder.statusLabel.tr
                                          : 'Tracking Delivery Partner'.tr,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      liveOrder.etaLabel?.tr ?? 'Live tracking active'.tr,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFFE5A600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(modalContext),
                                icon: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isDark ? const Color(0xFF2C2C2C) : const Color(0xFFF0F0F0),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.close_rounded,
                                    color: isDark ? Colors.white : Colors.black87,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 70% Height Interactive Map View
                    Expanded(
                      child: Stack(
                        children: [
                          LiveTrackingMap(
                            riderLat: rLat,
                            riderLng: rLng,
                            heading: liveState.heading,
                            restaurantLat: resLat,
                            restaurantLng: resLng,
                            customerLat: custLat,
                            customerLng: custLng,
                            routePoints: liveState.routePoints,
                          ),

                          // Floating Rider Partner Card Overlay
                          if (liveOrder.hasRider)
                            Positioned(
                              bottom: 16,
                              left: 16,
                              right: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.cardDark : Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    Image.asset(
                                      'assets/images/bike.png',
                                      width: 32,
                                      height: 32,
                                      errorBuilder: (context, error, stackTrace) => Icon(
                                        Icons.two_wheeler_rounded,
                                        color: AppColors.primary,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            liveOrder.deliveryPartner?.name ?? 'Delivery Partner'.tr,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white : AppColors.textPrimaryLight,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'On the way to your delivery address'.tr,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: const Color(0xFFE5A600),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // See the expanded map above: no invented coordinates.
    final resLat = state.restaurantLat ?? order.restaurantLat;
    final resLng = state.restaurantLng ?? order.restaurantLng;
    final custLat = state.customerLat ?? order.dropLat;
    final custLng = state.customerLng ?? order.dropLng;
    final rLat = state.hasRiderFix ? state.riderLat : null;
    final rLng = state.hasRiderFix ? state.riderLng : null;

    return GestureDetector(
      onTap: () => _showExpandedMapBottomSheet(context),
      child: Container(
        height: 220,
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          children: [
            Positioned.fill(
              child: LiveTrackingMap(
                riderLat: rLat,
                riderLng: rLng,
                heading: state.heading,
                restaurantLat: resLat,
                restaurantLng: resLng,
                customerLat: custLat,
                customerLng: custLng,
                routePoints: state.routePoints,
              ),
            ),

            // Now that the bike marker hides without a real fix, say so. An
            // assigned-but-unlocated rider previously showed a marker parked on the
            // restaurant; an empty map with no explanation is just as confusing.
            if (order.hasRider && !state.hasRiderFix)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Locating your rider'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // Tap hint button overlay
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Expand Map'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.open_in_full_rounded,
                      color: Colors.white,
                      size: 12,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



// ─────────────────────────────────────────────────────────────── cards

/// Shared card shell so every section matches the app's card styling.
class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark
            ? null
            : [BoxShadow(color: AppColors.shadow1, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: child,
    );
  }
}

class _DropOtpCard extends StatelessWidget {
  final String otp;
  const _DropOtpCard({required this.otp});

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DELIVERY OTP'.tr, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE5A600))),
                const SizedBox(height: 3),
                Text('Share this code with your delivery partner'.tr, style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
            child: Text(otp, style: const TextStyle(color: Color(0xFF121212), fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: 3)),
          ),
        ],
      ),
    );
  }
}

/// Promotional banners. Auto-advances when there is more than one; hides
/// itself entirely when the backend returns none.
class _PromoBannerCarousel extends ConsumerStatefulWidget {
  const _PromoBannerCarousel();

  @override
  ConsumerState<_PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends ConsumerState<_PromoBannerCarousel> {
  final _controller = PageController();
  Timer? _timer;
  int _page = 0;
  int _count = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _ensureAutoScroll(int count) {
    _count = count;
    if (count > 1 && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_controller.hasClients || _count <= 1) return;
        _page = (_page + 1) % _count;
        _controller.animateToPage(_page, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      });
    } else if (count <= 1) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final banners = ref.watch(heroBannersProvider).value ?? const <String>[];
    if (banners.isEmpty) return const SizedBox.shrink();
    _ensureAutoScroll(banners.length);

    return Column(
      children: [
        SizedBox(
          height: 120,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: banners.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SmartImage(url: banners[i], category: ImageCategory.food, fit: BoxFit.cover, width: double.infinity),
              ),
            ),
          ),
        ),
        if (banners.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                banners.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? AppColors.primary : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Live coupons/offers below the map. Hidden when there are none.
class _CouponCards extends ConsumerWidget {
  const _CouponCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coupons = ref.watch(couponsProvider).value ?? const [];
    if (coupons.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 14),
        itemCount: coupons.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final c = coupons[i];
          return Container(
            width: 260,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).brightness == Brightness.dark ? AppColors.cardDark : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.local_offer_rounded, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.discountText, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      if (c.code.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Code {code}'.trArgs({'code': c.code}), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeliveryPartnerCard extends StatelessWidget {
  final DeliveryPartner partner;
  final String statusLabel;
  final VoidCallback onCall;
  final VoidCallback onChat;

  /// Unread messages from the rider, shown on the chat button.
  final int unread;

  const _DeliveryPartnerCard({
    required this.partner,
    required this.statusLabel,
    required this.onCall,
    required this.onChat,
    this.unread = 0,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: partner.photoUrl.isEmpty
                    ? Icon(Icons.person_rounded, color: AppColors.primary, size: 28)
                    : ClipOval(
                        child: SmartImage(url: partner.photoUrl, category: ImageCategory.food, width: 52, height: 52, fit: BoxFit.cover),
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.name.isEmpty ? 'Delivery partner'.tr : partner.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5, color: textColor),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (partner.rating > 0) ...[
                          const Icon(Icons.star_rounded, color: Color(0xFF1FA855), size: 15),
                          const SizedBox(width: 2),
                          Text(partner.rating.toStringAsFixed(1), style: TextStyle(fontSize: 12.5, color: secondary, fontWeight: FontWeight.w500)),
                        ],
                        if (partner.totalRatings > 0) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '{count} ratings'.trArgs({'count': partner.totalRatings}),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: secondary),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(statusLabel.tr, style: TextStyle(fontSize: 12.5, color: AppColors.primary, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (partner.hasPhone)
                InkWell(
                  onTap: onCall,
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.call_rounded, color: AppColors.primary, size: 20),
                  ),
                ),
              const SizedBox(width: 8),
              // Opens the order chat with the assigned rider (/food/chat).
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: onChat,
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: secondary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: secondary.withValues(alpha: 0.3)),
                      ),
                      child: Icon(Icons.chat_bubble_outline_rounded, color: secondary, size: 19),
                    ),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: IgnorePointer(
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: Text(
                            unread > 9 ? '9+' : '$unread',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.two_wheeler_rounded, size: 18, color: secondary),
              const SizedBox(width: 8),
              Expanded(
                child: partner.hasVehicleInfo
                    ? Text(
                        [partner.vehicleType, partner.vehicleNumber].where((s) => s.isNotEmpty).join(' · '),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
                      )
                    : Row(
                        children: [
                          Text('Vehicle info'.tr, style: TextStyle(fontSize: 13, color: secondary)),
                          const SizedBox(width: 6),
                          const Flexible(child: _PendingBadge()),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small "not wired to the backend yet" indicator — used wherever the spec
/// asks for a feature the backend doesn't support so the UI stays complete
/// instead of silently hiding the row.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Backend implementation pending'.tr,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Color(0xFF9A6B00)),
      ),
    );
  }
}

class _CancelButton extends StatelessWidget {
  final VoidCallback onCancel;
  const _CancelButton({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFFF6464)),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        onPressed: onCancel,
        icon: const Icon(Icons.close_rounded, color: Color(0xFFFF6464), size: 18),
        label: Text('Cancel order'.tr, style: const TextStyle(color: Color(0xFFFF6464), fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF1FA855), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Your order is protected with JhatPat delivery safety.'.tr, style: TextStyle(fontSize: 13, color: secondary)),
          ),
        ],
      ),
    );
  }
}

class _DeliveryDetailsCard extends StatelessWidget {
  final OrderModel order;
  const _DeliveryDetailsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    final rows = <Widget>[
      if (order.customerName.isNotEmpty)
        _detailRow(Icons.person_outline_rounded, 'Delivering to', order.customerName, textColor, secondary),
      if (order.customerPhone.isNotEmpty)
        _detailRow(Icons.phone_outlined, 'Contact', order.customerPhone, textColor, secondary),
      if (order.deliveryAddress.isNotEmpty)
        _detailRow(Icons.location_on_outlined, 'Address', order.deliveryAddress, textColor, secondary),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Delivery details'.tr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 12),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value, Color textColor, Color secondary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.tr, style: TextStyle(fontSize: 11.5, color: secondary)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: textColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final OrderModel order;
  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Order summary'.tr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
              if (order.orderNumber.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '#${order.orderNumber}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          ...order.items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Text('${item.quantity}×', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary, fontSize: 13)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.variants.isEmpty ? item.name : '${item.name} (${item.variants.join(', ')})',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, color: textColor),
                    ),
                  ),
                  Text('₹${item.lineTotal.toStringAsFixed(0)}', style: TextStyle(fontSize: 13.5, color: secondary)),
                ],
              ),
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total paid'.tr, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
              Text('₹${order.total.toStringAsFixed(0)}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFFE5A600))),
            ],
          ),
          if (order.paymentMethod.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Paid via {method}'.trArgs({'method': _paymentLabel(order.paymentMethod)}), style: TextStyle(fontSize: 12, color: secondary)),
          ],
        ],
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'Cash on Delivery'.tr;
      case 'razorpay':
        return 'Online (Card/NetBanking)'.tr;
      case 'razorpay_qr':
        return 'Pay on delivery (QR)'.tr;
      case 'wallet':
        return 'JhatPat Wallet'.tr;
      default:
        return method;
    }
  }
}

/// Dynamic timeline rendered from the order's lifecycle — no hardcoded stages.
class _StatusTimelineCard extends StatelessWidget {
  final OrderModel order;
  const _StatusTimelineCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    if (order.isCancelled) {
      return _Card(
        child: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: Color(0xFFFF6464), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(order.statusLabel.tr, style: TextStyle(fontWeight: FontWeight.w600, color: textColor)),
                  if (order.cancellationReason.isNotEmpty)
                    Text(order.cancellationReason, style: TextStyle(fontSize: 12.5, color: secondary)),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final stages = order.timeline;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order status'.tr, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: textColor)),
          const SizedBox(height: 14),
          for (var i = 0; i < stages.length; i++)
            _StageRow(stage: stages[i], isLast: i == stages.length - 1, textColor: textColor, secondary: secondary),
        ],
      ),
    );
  }
}

class _StageRow extends StatelessWidget {
  final OrderStage stage;
  final bool isLast;
  final Color textColor;
  final Color secondary;

  const _StageRow({required this.stage, required this.isLast, required this.textColor, required this.secondary});

  @override
  Widget build(BuildContext context) {
    final reached = stage.isReached;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(
              stage.isCompleted
                  ? Icons.check_circle_rounded
                  : stage.isCurrent
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
              color: reached ? AppColors.primary : Colors.grey.shade400,
              size: 20,
            ),
            if (!isLast)
              Container(width: 2, height: 30, color: stage.isCompleted ? AppColors.primary : Colors.grey.shade300),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stage.label.tr,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: stage.isCurrent ? FontWeight.w600 : FontWeight.w500,
                      color: reached ? textColor : secondary,
                    ),
                  ),
                ),
                if (stage.at != null)
                  Text(_time(stage.at!), style: TextStyle(fontSize: 11.5, color: secondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _time(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}

class _ErrorState extends StatelessWidget {
  final String? message;
  final Future<void> Function() onRetry;
  final VoidCallback onBack;

  const _ErrorState({required this.message, required this.onRetry, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: onBack),
          ),
          const Spacer(),
          const Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message ?? 'Could not load your order.'.tr, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: onRetry,
            child: Text('Retry'.tr, style: const TextStyle(color: Color(0xFF121212))),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
