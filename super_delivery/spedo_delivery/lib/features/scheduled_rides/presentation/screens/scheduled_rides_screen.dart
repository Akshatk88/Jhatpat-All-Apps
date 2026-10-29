import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/features/scheduled_rides/application/scheduled_rides_controller.dart';
import 'package:food_user_application/features/scheduled_rides/data/models/scheduled_ride.dart';

const _jhatpatYellow = Color(0xFFFFB800);
const _dangerRed = Color(0xFFE53935);
const _green = Color(0xFF1EBE5D);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Today, 4:30 PM" / "Tomorrow, 9:05 AM" / "Mon 14 Oct, 7:00 PM".
String formatPickupTime(DateTime? at) {
  if (at == null) return 'Time not set';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = day.difference(today).inDays;
  final h = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final m = at.minute.toString().padLeft(2, '0');
  final time = '$h:$m ${at.hour < 12 ? 'AM' : 'PM'}';
  if (diff == 0) return 'Today, $time';
  if (diff == 1) return 'Tomorrow, $time';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${days[at.weekday - 1]} ${at.day} ${_months[at.month - 1]}, $time';
}

/// Upcoming scheduled bookings: the driver's own, plus open ones in their zone.
class ScheduledRidesScreen extends ConsumerWidget {
  const ScheduledRidesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(scheduledRidesControllerProvider);
    final data = async.value;

    Widget body;
    if (data == null && async.isLoading) {
      body = const Center(child: CircularProgressIndicator(color: _jhatpatYellow));
    } else if (data == null) {
      final err = async.error;
      body = _Message(
        icon: Icons.cloud_off_rounded,
        title: 'Could not load scheduled rides',
        body: err is AppError ? err.message : 'Something went wrong.',
        action: 'Try again',
        onAction: () => ref.read(scheduledRidesControllerProvider.notifier).reload(),
      );
    } else {
      body = RefreshIndicator(
        color: Colors.black,
        backgroundColor: _jhatpatYellow,
        onRefresh: () async {
          ref.read(scheduledRidesControllerProvider.notifier).reload();
          try {
            await ref.read(scheduledRidesControllerProvider.future);
          } catch (_) {}
        },
        child: data.rides.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: 80.h),
                  const _Message(
                    icon: Icons.event_available_rounded,
                    title: 'No scheduled rides',
                    body: 'Upcoming bookings assigned to you, and open scheduled '
                        'requests in your zone, will show here.',
                  ),
                ],
              )
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 32.h),
                itemCount: data.rides.length + (data.hasNextPage ? 1 : 0),
                separatorBuilder: (_, _) => SizedBox(height: 12.h),
                itemBuilder: (context, i) {
                  if (i == data.rides.length) {
                    return Center(
                      child: data.loadingMore
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(color: _jhatpatYellow),
                            )
                          : TextButton(
                              onPressed: () async {
                                final err = await ref
                                    .read(scheduledRidesControllerProvider.notifier)
                                    .loadMore();
                                if (err != null && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(err), backgroundColor: _dangerRed),
                                  );
                                }
                              },
                              child: const Text(
                                'Load more',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                    );
                  }
                  return _ScheduledRideCard(ride: data.rides[i]);
                },
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled rides')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: body,
          ),
        ),
      ),
    );
  }
}

class _ScheduledRideCard extends ConsumerStatefulWidget {
  const _ScheduledRideCard({required this.ride});

  final ScheduledRide ride;

  @override
  ConsumerState<_ScheduledRideCard> createState() => _ScheduledRideCardState();
}

class _ScheduledRideCardState extends ConsumerState<_ScheduledRideCard> {
  bool _cancelling = false;

  static const _cancelReasons = <String>[
    'Not available at that time',
    'Vehicle problem',
    'Pickup is too far',
    'Customer asked me to cancel',
    'Personal emergency',
  ];

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Why are you cancelling?'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'The customer will need another driver. A cancellation fee may be '
              'charged to your wallet.',
            ),
          ),
          for (final r in _cancelReasons)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(r),
              child: Text(r),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Keep booking', style: TextStyle(color: _dangerRed)),
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _cancelling = true);
    final result = await ref
        .read(scheduledRidesControllerProvider.notifier)
        .cancel(widget.ride.id, reason: reason);
    if (!mounted) return;
    setState(() => _cancelling = false);
    result.when(
      success: (message) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Booking cancelled')),
      ),
      failure: (e) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: _dangerRed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.ride;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[600];

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20.r),
        border: r.isAssignedToMe
            ? Border.all(color: _jhatpatYellow, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(8.r),
                decoration: BoxDecoration(
                  color: _jhatpatYellow,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Icon(
                  r.isParcel ? Icons.inventory_2_rounded : Icons.schedule_rounded,
                  color: Colors.black,
                  size: 18.sp,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatPickupTime(r.scheduledAt),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 15.sp,
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      '${r.kindLabel}'
                      '${r.distanceMeters > 0 ? ' · ${(r.distanceMeters / 1000).toStringAsFixed(1)} km' : ''}'
                      ' · ${r.paymentMethod.toLowerCase() == 'cash' ? 'Cash' : 'Online'}',
                      style: TextStyle(color: subText, fontSize: 12.sp),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                '₹${r.fare.toStringAsFixed(0)}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 16.sp,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          _addressRow(Icons.my_location_rounded, _green, r.pickupAddress, textColor),
          SizedBox(height: 8.h),
          _addressRow(Icons.flag_rounded, _dangerRed, r.dropAddress, textColor),
          SizedBox(height: 12.h),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: r.isAssignedToMe
                      ? Colors.black
                      : (subText ?? Colors.grey).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(
                  r.statusLabel,
                  style: TextStyle(
                    color: r.isAssignedToMe ? _jhatpatYellow : textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.sp,
                  ),
                ),
              ),
              if (r.isAssignedToMe)
                _cancelling
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: _cancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _dangerRed,
                          side: const BorderSide(color: _dangerRed),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                        ),
                        child: const Text('Cancel booking'),
                      ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _addressRow(IconData icon, Color color, String address, Color textColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16.sp, color: color),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            address.isEmpty ? 'Address unavailable' : address,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: textColor, fontSize: 13.sp),
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52.sp, color: Colors.grey),
            SizedBox(height: 12.h),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15.sp,
                color: isDark ? Colors.white : const Color(0xFF1E1E1E),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: Colors.grey[600]),
            ),
            if (action != null) ...[
              SizedBox(height: 16.h),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _jhatpatYellow,
                  foregroundColor: Colors.black,
                  elevation: 0,
                ),
                child: Text(action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
