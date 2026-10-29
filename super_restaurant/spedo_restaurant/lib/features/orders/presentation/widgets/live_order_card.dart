import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:food_user_application/config/theme/app_colors.dart';
import 'package:food_user_application/features/orders/domain/order_model.dart';
import 'package:food_user_application/features/orders/presentation/controllers/live_orders_controller.dart';

class LiveOrderCard extends ConsumerStatefulWidget {
  const LiveOrderCard({super.key, required this.order});

  final OrderModel order;

  @override
  ConsumerState<LiveOrderCard> createState() => _LiveOrderCardState();
}

class _LiveOrderCardState extends ConsumerState<LiveOrderCard> {
  bool _isExpanded = true;

  /// Which of Accept/Reject is in flight, so the buttons can't fire twice.
  String? _pendingAction;

  bool _resending = false;

  /// Re-dispatching restarts the rider search, so a second tap within this
  /// window would only cancel the round that was just sent.
  DateTime? _resendCooldownUntil;

  /// Same rule as the backend's resend endpoint: an accepted, still-active
  /// order that no rider has taken yet.
  bool get _canResendToRiders =>
      const ['confirmed', 'preparing', 'ready_for_pickup', 'ready']
          .contains(widget.order.orderStatus) &&
      !widget.order.hasRider &&
      widget.order.dispatchStatus != 'accepted';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: isDarkMode ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDarkMode ? Colors.black.withOpacity(0.3) : Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          if (_isExpanded) ...[
            const SizedBox(height: 16),
            _buildTimeline(context),
            const SizedBox(height: 16),
            if (widget.order.dispatchStatus == 'picked_up' || widget.order.dispatchStatus == 'reached_drop')
              _buildMapBanner(context),
            _buildInfoGrid(context),
            const SizedBox(height: 16),
            if (widget.order.orderStatus == 'created')
              _buildAcceptRejectBar(context),
            if (_canResendToRiders) _buildResendBar(context),
            _buildActionButtons(context),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(widget.order.createdAt.toLocal());
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    Color pillColor;
    Color pillTextColor;
    IconData pillIcon;
    String pillText;

    switch (widget.order.orderStatus) {
      case 'created':
        // Not accepted yet: this used to share the "Accepted" pill with
        // 'confirmed', so a brand-new order looked auto-accepted and offered
        // no way to accept or reject it.
        pillColor = Colors.red.shade50;
        pillTextColor = Colors.red.shade700;
        pillIcon = Icons.notifications_active;
        pillText = 'New Order';
        break;
      case 'confirmed':
        pillColor = Colors.orange.shade50;
        pillTextColor = Colors.orange.shade700;
        pillIcon = Icons.check_circle;
        pillText = 'Accepted';
        break;
      case 'preparing':
        pillColor = Colors.orange.shade50;
        pillTextColor = Colors.orange.shade700;
        pillIcon = Icons.soup_kitchen;
        pillText = 'Preparing Food';
        break;
      case 'ready_for_pickup':
        pillColor = Colors.green.shade50;
        pillTextColor = Colors.green.shade700;
        pillIcon = Icons.shopping_bag;
        pillText = 'Ready for Pickup';
        break;
      case 'reached_pickup':
      case 'picked_up':
      case 'reached_drop':
        pillColor = Colors.blue.shade50;
        pillTextColor = Colors.blue.shade700;
        pillIcon = Icons.two_wheeler;
        pillText = 'Picked Up';
        break;
      default:
        pillColor = Colors.grey.shade100;
        pillTextColor = Colors.grey.shade700;
        pillIcon = Icons.info;
        pillText = widget.order.orderStatus;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.order.displayId.toUpperCase().startsWith('FOD')
                          ? '#${widget.order.displayId}'
                          : '#FOD-${widget.order.displayId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$timeStr  •  ${widget.order.items.length} items',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                // Long/raw status names truncate instead of pushing the row
                // past the card edge on narrow phones or large text.
                constraints: const BoxConstraints(maxWidth: 160),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pillColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(pillIcon, color: pillTextColor, size: 16),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          pillText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: pillTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    _isExpanded = !_isExpanded;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey.shade700,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          if (widget.order.orderStatus == 'preparing' || widget.order.orderStatus == 'ready_for_pickup')
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 12, color: pillTextColor),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.order.orderStatus == 'preparing' ? 'Preparing' : 'Ready'} since $timeStr', // Mocking timestamp
                      style: TextStyle(color: pillTextColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          if (widget.order.dispatchStatus == 'picked_up' || widget.order.dispatchStatus == 'reached_drop')
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.access_time, size: 12, color: pillTextColor),
                    const SizedBox(width: 4),
                    Text(
                      'Picked up at $timeStr', // Mocking timestamp
                      style: TextStyle(color: pillTextColor, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline(BuildContext context) {
    int currentStep = 0;
    if (widget.order.orderStatus == 'created') {
      currentStep = -1; // awaiting accept: no step reached yet
    } else if (widget.order.orderStatus == 'confirmed') {
      currentStep = 0;
    } else if (widget.order.orderStatus == 'preparing') {
      currentStep = 1;
    } else if (widget.order.orderStatus == 'ready_for_pickup' || widget.order.dispatchStatus == 'reached_pickup') {
      currentStep = 2;
    } else if (widget.order.dispatchStatus == 'picked_up' || widget.order.dispatchStatus == 'reached_drop') {
      currentStep = 3;
    } else if (widget.order.orderStatus == 'delivered' || widget.order.orderStatus == 'completed') {
      currentStep = 4;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Five labels side by side outgrow a narrow card at large text
          // sizes: cap each step so the labels scale down instead.
          final stepMaxWidth = (constraints.maxWidth - 4 * 8) / 5;
          return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimelineStep(
            maxWidth: stepMaxWidth,
            title: 'Accepted',
            time: currentStep >= 0 ? DateFormat('h:mm a').format(widget.order.createdAt.toLocal()) : 'Pending',
            icon: Icons.check,
            isActive: currentStep >= 0,
            isCurrent: currentStep == 0,
            color: Colors.green,
            isFirst: true,
          ),
          _TimelineLine(isActive: currentStep >= 1),
          _TimelineStep(
            maxWidth: stepMaxWidth,
            title: 'Preparing',
            time: currentStep >= 1 ? DateFormat('h:mm a').format(widget.order.createdAt.toLocal()) : 'Pending', // Mock
            icon: Icons.soup_kitchen,
            isActive: currentStep >= 1,
            isCurrent: currentStep == 1,
            color: Colors.orange,
          ),
          _TimelineLine(isActive: currentStep >= 2),
          _TimelineStep(
            maxWidth: stepMaxWidth,
            title: 'Ready',
            time: currentStep >= 2 ? DateFormat('h:mm a').format(widget.order.createdAt.toLocal()) : 'Pending', // Mock
            icon: Icons.shopping_bag,
            isActive: currentStep >= 2,
            isCurrent: currentStep == 2,
            color: Colors.green,
          ),
          _TimelineLine(isActive: currentStep >= 3),
          _TimelineStep(
            maxWidth: stepMaxWidth,
            title: 'Picked Up',
            time: currentStep >= 3 ? DateFormat('h:mm a').format(widget.order.createdAt.toLocal()) : 'Pending', // Mock
            icon: Icons.two_wheeler,
            isActive: currentStep >= 3,
            isCurrent: currentStep == 3,
            color: Colors.blue,
          ),
          _TimelineLine(isActive: currentStep >= 4),
          _TimelineStep(
            maxWidth: stepMaxWidth,
            title: 'Delivered',
            time: currentStep >= 4 ? DateFormat('h:mm a').format(widget.order.createdAt.toLocal()) : 'Pending', // Mock
            icon: Icons.check_circle_outline,
            isActive: currentStep >= 4,
            isCurrent: currentStep == 4,
            color: Colors.grey.shade700, // Typically green when done, grey otherwise
            isLast: true,
          ),
        ],
          );
        },
      ),
    );
  }

  Widget _buildMapBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 60,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        image: const DecorationImage(
          image: AssetImage('assets/image/map_placeholder.png'), // Need a placeholder or just a generic background
          fit: BoxFit.cover,
        ),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Stack(
        children: [
          // Simulated map path and icons
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Icon(Icons.store, color: Colors.orange.shade700, size: 24),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Divider(color: Colors.blue, thickness: 2, height: 2), // Dashed in real map
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.two_wheeler, color: Colors.blue, size: 20),
                ),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Divider(color: Colors.blue, thickness: 2, height: 2), // Dashed in real map
                  ),
                ),
                Icon(Icons.location_on, color: Colors.red.shade700, size: 24),
              ],
            ),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.circle, size: 8, color: Colors.green),
                  const SizedBox(width: 4),
                  const Text('Live Tracking', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoGrid(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.person_outline, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Customer',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.order.customerName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDarkMode ? Colors.white : Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.phone, size: 12, color: Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        widget.order.customerPhone.isNotEmpty ? '+91 ${widget.order.customerPhone}' : 'No phone',
                        style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 50, color: Colors.grey.shade200),
          const SizedBox(width: 12),
          // Delivery Partner
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(widget.order.hasRider ? Icons.circle : Icons.circle_outlined, size: 10, color: widget.order.hasRider ? Colors.green : Colors.grey.shade400),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Delivery Partner',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (widget.order.hasRider) ...[
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey.shade200,
                        ),
                        child: const Icon(Icons.person, size: 16, color: Colors.grey),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.order.riderName,
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDarkMode ? Colors.white : Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.order.riderRating != null) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.star, size: 12, color: Colors.orange),
                                  Text(widget.order.riderRating!.toStringAsFixed(1), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.phone, size: 10, color: Colors.orange),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    '+91 ${widget.order.riderPhone}',
                                    style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ] else
                  const Padding(
                    padding: EdgeInsets.only(top: 4.0),
                    child: Text('Looking for partner...', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.grey)),
                  ),
              ],
            ),
          ),
          Container(width: 1, height: 50, color: Colors.grey.shade200),
          const SizedBox(width: 12),
          // ETA
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'ETA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '15 mins', // Mocked ETA
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isDarkMode ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Dist: 2.1 km', // Mocked distance
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Accept / Reject for an order still in 'created'. Same statuses the Orders
  /// screen sends: 'confirmed' to accept, 'cancelled_by_restaurant' to reject.
  Widget _buildAcceptRejectBar(BuildContext context) {
    final busy = _pendingAction != null;

    Future<void> act(String status) async {
      if (status == 'cancelled_by_restaurant') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Reject this order?'),
            content: const Text('The customer will be told the restaurant declined it.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Reject', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
      }
      setState(() => _pendingAction = status);
      try {
        await ref
            .read(liveOrdersControllerProvider.notifier)
            .updateStatus(widget.order.id, status);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update the order. Please try again.')),
          );
        }
      } finally {
        if (mounted) setState(() => _pendingAction = null);
      }
    }

    Widget spinner(Color color) => SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: color),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : () => act('cancelled_by_restaurant'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                side: BorderSide(color: Colors.red.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _pendingAction == 'cancelled_by_restaurant'
                  ? spinner(Colors.red.shade700)
                  : const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: busy ? null : () => act('confirmed'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _pendingAction == 'confirmed'
                  ? spinner(Colors.white)
                  : const Text('Accept Order', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  /// "Resend to delivery partners": re-notifies nearby riders when nobody has
  /// accepted the delivery yet (`POST /food/restaurant/orders/:id/resend-notification`).
  Widget _buildResendBar(BuildContext context) {
    final cooling = _resendCooldownUntil != null &&
        DateTime.now().isBefore(_resendCooldownUntil!);

    Future<void> resend() async {
      setState(() => _resending = true);
      try {
        await ref
            .read(liveOrdersControllerProvider.notifier)
            .resendNotification(widget.order.id);
        if (!mounted) return;
        _resendCooldownUntil = DateTime.now().add(const Duration(seconds: 30));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Delivery partners notified again')),
        );
        // Re-enable the button once the cooldown has passed.
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted) setState(() {});
        });
      } catch (e) {
        if (!mounted) return;
        final data = e is DioException ? e.response?.data : null;
        final message = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Could not resend. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      } finally {
        if (mounted) setState(() => _resending = false);
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (_resending || cooling) ? null : resend,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange.shade800,
            side: BorderSide(color: Colors.orange.shade300),
            minimumSize: const Size(0, 46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: _resending
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.orange.shade800,
                  ),
                )
              : const Icon(Icons.campaign_rounded, size: 20),
          label: Text(
            cooling ? 'Riders notified — wait a moment' : 'Resend to delivery partners',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: widget.order.hasRider ? () {} : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Icon(Icons.phone_outlined, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () {},
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Icon(Icons.chat_bubble_outline, size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: () => context.push('/order-details/${widget.order.id}'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade700,
                side: BorderSide(color: Colors.orange.shade200),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Icon(Icons.visibility_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineStep extends StatelessWidget {
  final String title;
  final String time;
  final IconData icon;
  final bool isActive;
  final bool isCurrent;
  final Color color;
  final bool isFirst;
  final bool isLast;
  final double maxWidth;

  const _TimelineStep({
    this.maxWidth = double.infinity,
    required this.title,
    required this.time,
    required this.icon,
    required this.isActive,
    required this.isCurrent,
    required this.color,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive ? color : Colors.grey.shade200,
            boxShadow: isCurrent
                ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]
                : null,
          ),
          child: Icon(
            icon,
            size: 16,
            color: isActive ? Colors.white : Colors.grey.shade500,
          ),
        ),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            title,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.black87 : Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            time,
            maxLines: 1,
            style: TextStyle(
              fontSize: 10,
              color: isActive ? (isCurrent ? color : Colors.grey.shade600) : Colors.grey.shade400,
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
      ),
    );
  }
}

class _TimelineLine extends StatelessWidget {
  final bool isActive;

  const _TimelineLine({required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(top: 15), // Align with center of 32px circle
        height: 2,
        color: isActive ? Colors.green : Colors.grey.shade300,
      ),
    );
  }
}
