import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/design_system/components/ride/empty_state.dart';
import 'package:superapp_user/design_system/components/ride/loading_widget.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/vehicle_image.dart';
import 'package:superapp_user/modules/taxi/home/data/models/vehicle_type_model.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_history_controller.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_history_state.dart';
import 'package:superapp_user/modules/taxi/ride/presentation/widgets/recent_activity_card.dart';

/// Normalized history entry for a ride.
class _HistoryEntry {
  final String rideId;
  final String title;
  final String subtitle;
  final String pickup;
  final String drop;
  final DateTime date;
  final double fare;
  final String status;
  final String serviceType;
  final String? vehicleIconType;
  final String? vehicleType;
  final String route;

  const _HistoryEntry({
    this.vehicleType,
    required this.rideId,
    required this.title,
    required this.subtitle,
    required this.pickup,
    required this.drop,
    required this.date,
    required this.fare,
    required this.status,
    required this.serviceType,
    this.vehicleIconType,
    required this.route,
  });

  factory _HistoryEntry.fromRide(RideModel ride) {
    final serviceType = (ride.serviceType ?? '').toLowerCase();
    final vehicle = ride.vehicleType ?? ride.vehicleIconType ?? '';

    String title;
    String subtitle;
    if (serviceType == 'parcel') {
      title = 'Parcel delivery';
      subtitle = 'DELIVERY BOOKING';
    } else if (serviceType == 'intercity' || serviceType == 'outstation') {
      title = 'Outstation Ride';
      subtitle = 'INTERCITY TRIP';
    } else if (serviceType == 'bus') {
      title = 'Bus Booking';
      subtitle = 'BUS TICKET';
    } else {
      title = vehicle.isEmpty ? 'Taxi Ride' : vehicle;
      subtitle = 'DRIVER TRIP';
    }

    return _HistoryEntry(
      rideId: ride.rideId,
      title: title,
      subtitle: subtitle,
      pickup: ride.pickupAddress,
      drop: ride.dropAddress,
      date: ride.completedAt ??
          ride.startedAt ??
          ride.acceptedAt ??
          ride.scheduledAt ??
          DateTime.now(),
      fare: ride.fare,
      status: ride.status,
      serviceType: serviceType,
      vehicleIconType: ride.vehicleIconType,
      vehicleType: ride.vehicleType,
      route: '/taxi/rides/${ride.rideId}',
    );
  }

}

class _HistoryFilter {
  final String id;
  final String label;

  /// Category query sent to backend.
  final String rideCategory;

  const _HistoryFilter({
    required this.id,
    required this.label,
    required this.rideCategory,
  });
}

class RideHistoryScreen extends ConsumerStatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  ConsumerState<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends ConsumerState<RideHistoryScreen> {
  final _scrollController = ScrollController();

  static const _filters = <_HistoryFilter>[
    _HistoryFilter(id: 'all', label: 'ALL', rideCategory: 'all'),
    _HistoryFilter(id: 'rides', label: 'RIDES', rideCategory: 'rides'),
    _HistoryFilter(id: 'parcels', label: 'PARCELS', rideCategory: 'parcels'),
  ];

  String _selectedId = 'all';

  _HistoryFilter get _selected =>
      _filters.firstWhere((f) => f.id == _selectedId, orElse: () => _filters.first);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(rideHistoryControllerProvider.notifier).loadNextPage();
    }
  }

  void _onFilterSelected(String id) {
    if (id == _selectedId) return;
    setState(() => _selectedId = id);

    final filter = _filters.firstWhere((f) => f.id == id);
    ref.read(rideHistoryControllerProvider.notifier).setCategory(filter.rideCategory);
  }

  List<_HistoryEntry> _entriesFor(
    _HistoryFilter filter,
    RideHistoryState rideState,
  ) {
    final entries = <_HistoryEntry>[];

    {
      final rides = rideState.rides.map(_HistoryEntry.fromRide);
      if (filter.id == 'all') {
        entries.addAll(rides);
      } else if (filter.id == 'rides') {
        entries.addAll(rides.where((e) =>
            e.serviceType != 'parcel' &&
            e.serviceType != 'intercity' &&
            e.serviceType != 'outstation' &&
            e.serviceType != 'bus'));
      } else if (filter.id == 'parcels') {
        entries.addAll(rides.where((e) => e.serviceType == 'parcel'));
      } else {
        entries.addAll(rides);
      }
    }

    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final rideState = ref.watch(rideHistoryControllerProvider);
    final filter = _selected;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? TaxiColors.darkTextPrimary : TaxiColors.lightTextPrimary;
    final textSecondary = isDark ? TaxiColors.darkTextSecondary : TaxiColors.lightTextSecondary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent activity'.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                  fontSize: 24,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Your recent trips, deliveries, and bookings'.tr,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        _FilterBar(
          filters: _filters,
          selectedId: _selectedId,
          onSelected: _onFilterSelected,
        ),
        Expanded(
          child: _buildBody(filter, rideState),
        ),
      ],
    );
  }

  Widget _buildBody(
    _HistoryFilter filter,
    RideHistoryState rideState,
  ) {
    if (rideState.isLoading) {
      return LoadingWidget(message: 'Loading your bookings…'.tr);
    }

    final entries = _entriesFor(filter, rideState);

    if (entries.isEmpty && rideState.error != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Could not load your bookings'.tr,
        message: 'Please check your connection and try again.'.tr,
        actionLabel: 'Retry'.tr,
        onAction: _refresh,
      );
    }

    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No bookings yet'.tr,
        message: filter.id == 'all'
            ? 'Your trips will appear here once you make your first booking.'.tr
            : 'Nothing under {label} yet.'.trArgs({'label': filter.label.tr}),
        actionLabel: 'Book now'.tr,
        onAction: () => context.go('/taxi'),
      );
    }

    final showFooterLoader = rideState.isLoadingMore;
    // Admin vehicle art; empty until it loads, so cards show bundled art first.
    final vehicleCatalog =
        ref.watch(allVehicleTypesProvider).asData?.value ?? const <VehicleTypeModel>[];

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: entries.length + (showFooterLoader ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= entries.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final entry = entries[index];
          return RecentActivityCard(
            title: entry.title,
            subtitle: entry.subtitle,
            pickup: entry.pickup,
            drop: entry.drop,
            date: entry.date,
            fare: entry.fare,
            status: entry.status,
            serviceType: entry.serviceType,
            vehicleIconType: entry.vehicleIconType,
            vehicleImageUrl: adminVehicleImage(findVehicleType(
              vehicleCatalog,
              idOrName: entry.vehicleType,
              iconType: entry.vehicleIconType,
            )),
            onTap: () {
              if (entry.route.isNotEmpty) {
                context.push(entry.route);
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    await ref.read(rideHistoryControllerProvider.notifier).loadFirstPage();
  }
}

class _FilterBar extends StatelessWidget {
  final List<_HistoryFilter> filters;
  final String selectedId;
  final ValueChanged<String> onSelected;

  const _FilterBar({
    required this.filters,
    required this.selectedId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg = isDark ? TaxiColors.primary : const Color(0xFF0F172A);
    final unselectedBg = isDark ? TaxiColors.darkSurface : Colors.white;
    final unselectedText = isDark ? TaxiColors.darkTextSecondary : const Color(0xFF475569);
    final unselectedBorder = isDark ? TaxiColors.darkBorder : const Color(0xFFE2E8F0);

    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: filters.map((filter) {
            final selected = filter.id == selectedId;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(filter.label.tr),
                selected: selected,
                onSelected: (_) => onSelected(filter.id),
                showCheckmark: false,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: selected ? (isDark ? const Color(0xFF121212) : Colors.white) : unselectedText,
                ),
                selectedColor: selectedBg,
                backgroundColor: unselectedBg,
                side: BorderSide(
                  color: selected ? Colors.transparent : unselectedBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
