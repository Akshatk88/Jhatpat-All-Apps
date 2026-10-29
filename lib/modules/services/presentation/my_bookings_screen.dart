import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/components/media/empty_state_widget.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/presentation/widgets/services_bottom_nav.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// The customer's service bookings, split into Active / Completed / Cancelled.
///
/// One list is loaded and filtered client-side across the three tabs — see
/// [MyBookingsController] for why that beats a request per tab.
class MyBookingsScreen extends ConsumerStatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  ConsumerState<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends ConsumerState<MyBookingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: BookingsFilter.values.length, vsync: this);
    _scroll.addListener(() {
      // Prefetch one screen ahead of the bottom so the list rarely stalls.
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400) {
        ref.read(myBookingsProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(myBookingsProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('My bookings'.tr),
        backgroundColor: spSurface(context),
        surfaceTintColor: Colors.transparent,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabs,
          labelColor: spAccentText(context),
          unselectedLabelColor: spTextSecondary(context),
          indicatorColor: spAccent,
          tabs: [
            for (final filter in BookingsFilter.values) Tab(text: filter.label.tr),
          ],
        ),
      ),
      bottomNavigationBar:
          const ServicesBottomNav(current: ServicesTab.bookings),
      body: state.loading
          ? const SpListSkeleton(itemCount: 4, height: 128)
          : state.error != null && state.bookings.isEmpty
              ? SpErrorState(
                  message: state.error!,
                  onRetry: () => ref.read(myBookingsProvider.notifier).refresh(),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    for (final filter in BookingsFilter.values)
                      _BookingList(
                        bookings: state.forFilter(filter),
                        filter: filter,
                        loadingMore: state.loadingMore,
                        controller:
                            filter == BookingsFilter.active ? _scroll : null,
                        onRefresh: () =>
                            ref.read(myBookingsProvider.notifier).refresh(),
                      ),
                  ],
                ),
    );
  }
}

class _BookingList extends StatelessWidget {
  const _BookingList({
    required this.bookings,
    required this.filter,
    required this.loadingMore,
    required this.onRefresh,
    this.controller,
  });

  final List<SpBooking> bookings;
  final BookingsFilter filter;
  final bool loadingMore;
  final Future<void> Function() onRefresh;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return RefreshIndicator(
        color: spAccent,
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.15),
            EmptyStateWidget(
              title: switch (filter) {
                BookingsFilter.active => 'Nothing booked right now'.tr,
                BookingsFilter.completed => 'No completed services yet'.tr,
                BookingsFilter.cancelled => 'Nothing cancelled'.tr,
              },
              subtitle: switch (filter) {
                BookingsFilter.active =>
                  'Book a service and track it here.'.tr,
                BookingsFilter.completed =>
                  'Your finished services will appear here.'.tr,
                BookingsFilter.cancelled =>
                  'Cancelled bookings will appear here.'.tr,
              },
              icon: Icons.receipt_long_rounded,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: spAccent,
      onRefresh: onRefresh,
      child: ListView.builder(
        controller: controller,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: bookings.length + (loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= bookings.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: spAccent),
                ),
              ),
            );
          }
          return _BookingCard(booking: bookings[index]);
        },
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final SpBooking booking;

  @override
  Widget build(BuildContext context) {
    final scheduled = booking.scheduledDate;

    return SpCard(
      // A booking still being matched belongs on the searching screen; anything
      // else on the detail/tracking screen.
      onTap: () => context.push(
        booking.status.isSearching
            ? ServicesRoutePaths.searchingFor(booking.id)
            : ServicesRoutePaths.bookingOf(booking.id),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: spAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.handyman_rounded, size: 20, color: spAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      booking.serviceName.isEmpty
                          ? 'Service booking'.tr
                          : booking.serviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: spTextPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      booking.bookingNumber,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: spTextSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              SpStatusChip(status: booking.status, compact: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.event_rounded, size: 15, color: spTextSecondary(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  scheduled == null
                      ? booking.scheduledTime
                      : '${DateFormat('d MMM').format(scheduled)}'
                          '${booking.slotStart.isEmpty ? '' : ', ${booking.slotStart} - ${booking.slotEnd}'}',
                  style: TextStyle(fontSize: 12.5, color: spTextSecondary(context)),
                ),
              ),
              Text(
                formatPaise(
                  booking.hasBill ? booking.billTotalPaise : booking.finalAmountPaise,
                ),
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: spTextPrimary(context),
                ),
              ),
            ],
          ),
          if (booking.attendingPartner != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_rounded, size: 15, color: spTextSecondary(context)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    booking.attendingPartner!.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: spTextSecondary(context)),
                  ),
                ),
              ],
            ),
          ],
          if (booking.canReview) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () =>
                    context.push(ServicesRoutePaths.bookingOf(booking.id)),
                icon: const Icon(Icons.star_rounded, size: 16),
                label: Text('Rate this service'.tr),
                style: OutlinedButton.styleFrom(
                  foregroundColor: spAccentText(context),
                  side: const BorderSide(color: spAccent),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
