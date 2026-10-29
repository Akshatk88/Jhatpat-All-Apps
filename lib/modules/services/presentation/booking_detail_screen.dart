import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/application/sp_payment_controller.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/rate_service_sheet.dart';
import 'package:superapp_user/modules/services/presentation/widgets/services_bottom_nav.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';

/// One booking, from confirmed through to paid and rated.
///
/// Works from the id alone — reachable from a push notification, a shared link
/// or a cold start with nothing preloaded.
///
/// Refresh strategy mirrors the searching screen: socket events invalidate the
/// document rather than patching state from the payload, and a 15-second poll
/// backs that up because a backgrounded socket misses everything. The REST
/// document is always what is rendered.
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();

    // Join the booking's live-location room. The server verifies this customer
    // is a party to the booking and ignores the join otherwise, so it is safe
    // to call before we know the status.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(spRealtimeProvider)?.joinTracking(widget.bookingId);
    });

    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(spBookingProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    // Read, not watch — the provider scope may already be tearing down.
    ref.read(spRealtimeProvider)?.leaveTracking(widget.bookingId);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Any lifecycle event for this booking means the document changed.
    ref.listen(spBookingEventsProvider(widget.bookingId), (_, _) {
      ref.invalidate(spBookingProvider(widget.bookingId));
      ref.read(myBookingsProvider.notifier).refresh();
    });

    final booking = ref.watch(spBookingProvider(widget.bookingId));

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('Booking'.tr),
        backgroundColor: spSurface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
      ),
      bottomNavigationBar:
          const ServicesBottomNav(current: ServicesTab.track),
      body: switch (booking) {
        AsyncData(:final value) => _Detail(booking: value),
        AsyncError(:final error) => SpErrorState(
            message: error.toString().contains('Not found')
                ? 'This booking no longer exists.'.tr
                : 'We could not load this booking.'.tr,
            onRetry: () => ref.invalidate(spBookingProvider(widget.bookingId)),
          ),
        _ => const SpListSkeleton(itemCount: 4, height: 120),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      color: spAccent,
      onRefresh: () async => ref.invalidate(spBookingProvider(booking.id)),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 16, bottom: 40 + MediaQuery.of(context).padding.bottom),
        children: [
          _StatusHeader(booking: booking),

          if (booking.status.isLive) _Timeline(status: booking.status),

          if (booking.attendingPartner != null)
            _PartnerCard(booking: booking),

          // The visit OTP is what proves to the customer that the person at the
          // door is the one the platform sent. It only exists once someone is
          // assigned, and it stops mattering once they are inside.
          if (booking.visitOtp.isNotEmpty &&
              (booking.status == SpBookingStatus.journeyStarted ||
                  booking.status == SpBookingStatus.assigned))
            _OtpCard(
              title: 'Share this code at the door'.tr,
              subtitle: 'Only give it to the professional once they arrive.'.tr,
              otp: booking.visitOtp,
            ),

          if (booking.paymentOtp.isNotEmpty && !booking.paymentStatus.isSettled)
            _OtpCard(
              title: 'Payment code'.tr,
              subtitle: 'Share only after the work is finished and billed.'.tr,
              otp: booking.paymentOtp,
            ),

          _ScheduleCard(booking: booking),

          _BillCard(booking: booking),

          if (booking.canReview)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () => showRateServiceSheet(context, ref, booking),
                  icon: const Icon(Icons.star_rounded, size: 19),
                  label: Text('Rate this service'.tr),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: spAccent,
                    foregroundColor: spOnAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),

          if (booking.rating > 0) _YourRating(booking: booking),

          if (booking.canCancel) _CancelButton(booking: booking),

          if (booking.status.isDead && booking.cancellationReason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Reason: {reason}'.trArgs({'reason': booking.cancellationReason}),
                style: TextStyle(fontSize: 12.5, color: spTextSecondary(context)),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context) {
    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.serviceName.isEmpty
                      ? 'Service booking'.tr
                      : booking.serviceName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: spTextPrimary(context),
                  ),
                ),
              ),
              SpStatusChip(status: booking.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            booking.bookingNumber,
            style: TextStyle(fontSize: 12, color: spTextSecondary(context)),
          ),
        ],
      ),
    );
  }
}

/// Where the job has got to.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.status});

  final SpBookingStatus status;

  /// The customer-visible milestones, in order.
  ///
  /// The backend has more states than this (`confirmed`, `work_done`, …); they
  /// are folded into the nearest milestone rather than shown, because a
  /// twelve-step tracker tells the customer less, not more.
  static const _steps = [
    (SpBookingStatus.accepted, 'Confirmed', Icons.check_circle_rounded),
    (SpBookingStatus.assigned, 'Professional assigned', Icons.person_pin_rounded),
    (SpBookingStatus.journeyStarted, 'On the way', Icons.directions_run_rounded),
    (SpBookingStatus.visited, 'Arrived', Icons.home_rounded),
    (SpBookingStatus.inProgress, 'Work in progress', Icons.build_rounded),
    (SpBookingStatus.completed, 'Completed', Icons.verified_rounded),
  ];

  int get _reached {
    final effective =
        (status == SpBookingStatus.workDone || status == SpBookingStatus.completed)
            ? SpBookingStatus.completed
            : status;
    final index = _steps.indexWhere((s) => s.$1 == effective);
    if (index >= 0) return index;
    // `confirmed` and anything else live map to the first milestone.
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final reached = _reached;

    return SpCard(
      child: Column(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Builder(builder: (context) {
              final (_, label, icon) = _steps[i];
              final done = i <= reached;
              final isLast = i == _steps.length - 1;

              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: done
                                ? spAccent
                                : spTextSecondary(context).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            size: 16,
                            color: done ? spOnAccent : spTextSecondary(context),
                          ),
                        ),
                        if (!isLast)
                          Expanded(
                            child: Container(
                              width: 2,
                              margin: const EdgeInsets.symmetric(vertical: 2),
                              color: i < reached
                                  ? spAccent
                                  : spTextSecondary(context).withValues(alpha: 0.15),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: 5),
                        child: Text(
                          label.tr,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: i == reached ? FontWeight.w700 : FontWeight.w500,
                            color: done
                                ? spTextPrimary(context)
                                : spTextSecondary(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PartnerCard extends ConsumerWidget {
  const _PartnerCard({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partner = booking.attendingPartner!;

    // Live position, when someone is actually travelling. Rendered as a
    // distance-free "moving now" indicator rather than a map: the customer's
    // own coordinates are optional on an SP booking, so a map could not
    // reliably show both ends, and a map with one pin is worse than a
    // sentence.
    final live = booking.status.isEnRoute
        ? ref.watch(spLiveLocationProvider(booking.id))
        : const AsyncValue<void>.data(null);

    return SpCard(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: spAccent.withValues(alpha: 0.12),
                backgroundImage:
                    partner.photoUrl.isEmpty ? null : NetworkImage(partner.photoUrl),
                child: partner.photoUrl.isEmpty
                    ? const Icon(Icons.person_rounded, color: spAccent)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      partner.displayName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: spTextPrimary(context),
                      ),
                    ),
                    if (partner.rating > 0)
                      Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 14, color: AppColors.ratingStar),
                          const SizedBox(width: 3),
                          Text(
                            partner.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12.5,
                              color: spTextSecondary(context),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (partner.phone.isNotEmpty)
                IconButton(
                  onPressed: () => launchUrl(Uri.parse('tel:${partner.phone}')),
                  icon: const Icon(Icons.call_rounded, color: spAccent),
                  style: IconButton.styleFrom(
                    backgroundColor: spAccent.withValues(alpha: 0.1),
                  ),
                ),
            ],
          ),
          if (booking.status.isEnRoute && live.hasValue) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'On the move — arriving shortly'.tr,
                    style: TextStyle(fontSize: 12.5, color: spTextSecondary(context)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OtpCard extends StatelessWidget {
  const _OtpCard({required this.title, required this.subtitle, required this.otp});

  final String title;
  final String subtitle;
  final String otp;

  @override
  Widget build(BuildContext context) {
    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: spTextPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: spTextSecondary(context)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final digit in otp.split(''))
                Container(
                  width: 38,
                  height: 46,
                  margin: const EdgeInsets.only(right: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: spAccent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: spAccent.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    digit,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: spAccentText(context),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context) {
    final date = booking.scheduledDate;

    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            icon: Icons.event_rounded,
            label: 'Scheduled'.tr,
            value: date == null
                ? booking.scheduledTime
                : '${DateFormat('EEEE, d MMMM').format(date)}'
                    '${booking.slotStart.isEmpty ? '' : '\n${booking.slotStart} - ${booking.slotEnd}'}',
          ),
          const SizedBox(height: 14),
          _Row(
            icon: Icons.place_rounded,
            label: 'Address'.tr,
            value: booking.address.singleLine,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: spTextSecondary(context)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: spTextSecondary(context)),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: spTextPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BillCard extends ConsumerStatefulWidget {
  const _BillCard({required this.booking});

  final SpBooking booking;

  @override
  ConsumerState<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends ConsumerState<_BillCard> {
  bool _confirming = false;

  Future<void> _confirmDoorstepPayment() async {
    setState(() => _confirming = true);
    final error = await ref
        .read(spPaymentControllerProvider)
        .confirmDoorstepCollection(widget.booking.id);
    if (!mounted) return;
    setState(() => _confirming = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error ?? 'Payment confirmed. Thank you!'.tr),
      ),
    );
    ref.read(myBookingsProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;

    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.hasBill ? 'Final bill'.tr : 'Estimated bill'.tr,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: spTextPrimary(context),
                  ),
                ),
              ),
              Text(
                booking.paymentStatus.label.tr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: booking.paymentStatus.isSettled
                      ? AppColors.success
                      : spTextSecondary(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (booking.hasBill) ...[
            for (final line in booking.billLines)
              SpPriceRow(
                label: line.quantity > 1
                    ? '${line.name} ×${line.quantity}'
                    : line.name,
                pricePaise: line.totalPaise,
              ),
            Divider(color: spBorder(context), height: 22),
            SpPriceRow(
              label: 'Total'.tr,
              pricePaise: booking.billTotalPaise,
              emphasised: true,
            ),
          ] else ...[
            SpPriceRow(label: 'Service'.tr, pricePaise: booking.basePricePaise),
            if (booking.discountPaise > 0)
              SpPriceRow(
                label: 'Discount'.tr,
                pricePaise: booking.discountPaise,
                isCredit: true,
              ),
            if (booking.taxPaise > 0)
              SpPriceRow(label: 'Taxes'.tr, pricePaise: booking.taxPaise),
            if (booking.visitingChargesPaise > 0)
              SpPriceRow(
                label: 'Visiting charge'.tr,
                pricePaise: booking.visitingChargesPaise,
              ),
            Divider(color: spBorder(context), height: 22),
            SpPriceRow(
              label: 'Total'.tr,
              pricePaise: booking.finalAmountPaise,
              emphasised: true,
            ),
          ],

          // The doorstep handshake. The professional initiates collection on
          // their app; this is the customer's half. Only offered once the work
          // is actually finished — confirming payment for a job still in
          // progress is how a customer ends up paying for work not done.
          if (!booking.paymentStatus.isSettled &&
              (booking.status == SpBookingStatus.workDone ||
                  booking.status == SpBookingStatus.completed)) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _confirming ? null : _confirmDoorstepPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: spAccent,
                  foregroundColor: spOnAccent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _confirming
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(spOnAccent),
                        ),
                      )
                    : Text(
                        'I have paid {amount}'.trArgs({'amount': formatPaise(booking.outstandingPaise)}),
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _YourRating extends StatelessWidget {
  const _YourRating({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context) {
    return SpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Your rating'.tr,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: spTextPrimary(context),
                ),
              ),
              const Spacer(),
              for (var i = 1; i <= 5; i++)
                Icon(
                  i <= booking.rating
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 18,
                  color: AppColors.ratingStar,
                ),
            ],
          ),
          if (booking.review.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              booking.review,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: spTextSecondary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelButton extends ConsumerWidget {
  const _CancelButton({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextButton(
        onPressed: () async {
          final reason = await askCancelReason(
            context,
            title: 'Cancel booking?',
            reasons: CancelReasons.service,
            confirmLabel: 'Cancel booking',
            keepLabel: 'Keep booking',
          );
          if (reason == null || !context.mounted) return;

          final error = await ref
              .read(myBookingsProvider.notifier)
              .cancel(booking.id, reason: reason);
          if (!context.mounted) return;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(error ?? 'Booking cancelled.'.tr)),
          );
        },
        child: Text(
          'Cancel booking'.tr,
          style: const TextStyle(color: AppColors.error),
        ),
      ),
    );
  }
}
