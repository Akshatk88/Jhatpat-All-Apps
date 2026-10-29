import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/core/maps/vehicle_marker_icons.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_providers.dart';
import 'package:superapp_user/modules/taxi/home/data/models/set_price_model.dart';
import 'package:superapp_user/modules/taxi/home/data/models/vehicle_type_model.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_state.dart';
import 'package:superapp_user/modules/taxi/home/application/fare_calculator.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/ride_search_controller.dart';
import 'package:superapp_user/core/i18n/tr.dart';

/// Average city-traffic speed assumed for client-side ETA estimation only.
const double _assumedSpeedKmph = 25;

class BookingController extends Notifier<BookingState> {

  @override
  BookingState build() => const BookingState();

  Future<void> loadCatalog() async {
    final repo = ref.read(homeRepositoryProvider);
    state = state.copyWith(clearError: true);

    // Fetched independently, NOT with Future.wait. A single Future.wait rejects
    // as soon as either call throws, so a missing fare table took the vehicle
    // list down with it — and because the screen shows a spinner whenever the
    // list is empty, that surfaced as an endless loader with no error.
    //
    // The vehicle list is the screen's reason to exist; prices are an
    // enrichment. Losing the enrichment must not lose the screen.
    // 1. The device copy from last time, at once — prices show instantly
    //    instead of after the 10–20 s catalogue download.
    final cachedTypes = await repo.cachedVehicleTypes();
    final cachedPrices = await repo.cachedSetPrices();
    if (cachedTypes != null && cachedTypes.isNotEmpty) {
      _applyCatalog(cachedTypes, cachedPrices);
    }

    // 2. Fresh copies, both downloads at the same time (they used to run one
    //    after the other). Each is guarded, so one failing keeps the other.
    final results = await Future.wait([
      _guard(repo.getVehicleTypes, 'vehicle types'),
      _guard(repo.getSetPrices, 'fare table'),
    ]);
    final vehicleTypes = results[0] as List<VehicleTypeModel>?;
    final setPrices = results[1] as List<SetPriceModel>?;

    if (vehicleTypes == null) {
      if (state.vehicleTypes.isEmpty) {
        state = state.copyWith(
          error: 'Could not load vehicles. Check your connection and try again.'.tr,
        );
      }
      return;
    }
    _applyCatalog(vehicleTypes, setPrices ?? cachedPrices);
    unawaited(_loadDriverEtas());
    unawaited(_loadServerQuotes());
  }

  /// Puts a vehicle list and price table on screen, keeping the rider's pick.
  void _applyCatalog(
    List<VehicleTypeModel> vehicleTypes,
    List<SetPriceModel>? setPrices,
  ) {
    // Cheapest class first (bike → auto → cab) so the default pick is the
    // budget option; the screen re-orders by the real fare once it is known.
    final ordered = [...vehicleTypes]
      ..sort((a, b) => vehicleClassRank(a).compareTo(vehicleClassRank(b)));

    final previous = state.selectedVehicle;
    final kept = previous == null
        ? null
        : ordered.where((v) => v.id == previous.id).firstOrNull;

    state = state.copyWith(
      vehicleTypes: ordered,
      selectedVehicle: kept ?? (ordered.isNotEmpty ? ordered.first : null),
      setPrices: setPrices,
    );

    // The default pick must be a vehicle the admin has priced; an unpriced
    // one is refused by the server at booking.
    final selected = state.selectedVehicle;
    if (setPrices != null && selected != null && state.isUnpriced(selected.id)) {
      final priced =
          state.vehicleTypes.where((v) => !state.isUnpriced(v.id)).toList();
      if (priced.isNotEmpty) {
        state = state.copyWith(selectedVehicle: priced.first);
      }
    }
    _recalculateFare();
  }

  /// Runs [fetch], returning null instead of throwing so one failed call
  /// cannot abort the rest of the catalogue load.
  Future<T?> _guard<T>(Future<T> Function() fetch, String label) async {
    try {
      return await fetch();
    } catch (e) {
      if (kDebugMode) debugPrint('[booking] $label failed: $e');
      return null;
    }
  }

  /// Fetches the closest available driver's ETA per vehicle type in
  /// parallel so the ride-type list can show a real "X mins away" instead
  /// of a hardcoded placeholder. Best-effort: failures are swallowed per
  /// vehicle type so one missing driver pool doesn't block the others.
  Future<void> _loadDriverEtas() async {
    final pickup = state.pickup;
    if (pickup == null || state.vehicleTypes.isEmpty) return;

    final repo = ref.read(homeRepositoryProvider);
    final entries = await Future.wait(state.vehicleTypes.map((vehicle) async {
      try {
        final eta = await repo.getClosestDriverEtaMinutes(
          lat: pickup.lat,
          lng: pickup.lng,
          vehicleTypeId: vehicle.id,
        );
        return MapEntry(vehicle.id, eta);
      } catch (_) {
        return MapEntry(vehicle.id, null);
      }
    }));

    final etaMap = <String, int>{
      for (final e in entries)
        if (e.value != null) e.key: e.value!,
    };
    state = state.copyWith(etaMinutesByVehicle: etaMap);
  }

  void setPickup(BookingLocation location) {
    state = state.copyWith(pickup: location, clearError: true);
    _recalculateRoute();
    unawaited(_loadDriverEtas());
  }

  void setDrop(BookingLocation location) {
    state = state.copyWith(drop: location, clearError: true);
    _recalculateRoute();
  }

  void setStops(List<BookingLocation> stops) {
    state = state.copyWith(stops: stops, clearError: true);
    _recalculateRoute();
  }

  void selectVehicle(VehicleTypeModel vehicle) {
    state = state.copyWith(selectedVehicle: vehicle);
    _recalculateFare();
  }

  void setPaymentMethod(String method) {
    state = state.copyWith(paymentMethod: method);
  }

  void applyPromoCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      state = state.copyWith(clearPromo: true);
    } else {
      state = state.copyWith(promoCode: code.trim());
    }
  }

  void setScheduledAt(DateTime? time) {
    if (time == null) {
      state = state.copyWith(clearScheduledAt: true);
    } else {
      state = state.copyWith(scheduledAt: time);
    }
  }

  void goToStep(BookingStep step) {
    state = state.copyWith(step: step);
  }

  void _recalculateRoute() {
    final pickup = state.pickup;
    final drop = state.drop;
    if (pickup == null || drop == null) return;

    final locationService = ref.read(taxiLocationServiceProvider);
    double totalDistanceMeters = 0;
    BookingLocation current = pickup;

    for (final stop in state.stops) {
      totalDistanceMeters += locationService.distanceMeters(
        current.lat,
        current.lng,
        stop.lat,
        stop.lng,
      );
      current = stop;
    }

    totalDistanceMeters += locationService.distanceMeters(
      current.lat,
      current.lng,
      drop.lat,
      drop.lng,
    );

    final durationSeconds = (totalDistanceMeters / 1000) / _assumedSpeedKmph * 3600;

    state = state.copyWith(
      distanceMeters: totalDistanceMeters,
      durationSeconds: durationSeconds,
      // Old quotes belong to the old route.
      quotedFares: const {},
      quoteUnavailable: const {},
    );
    _recalculateFare();
    unawaited(_loadServerQuotes());
  }

  void _recalculateFare() {
    final vehicle = state.selectedVehicle;
    if (vehicle == null) return;
    final breakdown = fareForVehicle(vehicle);
    if (breakdown == null) return;
    state = state.copyWith(fareBreakdown: breakdown);
  }

  /// The vehicle list as the rider sees it: lowest fare first. Vehicles
  /// without a fare yet (route or price table still loading) fall back to
  /// class order — bike, auto, then cabs — and go after the priced ones.
  List<VehicleTypeModel> vehiclesByPrice() {
    final fares = {
      for (final v in state.vehicleTypes) v.id: fareForVehicle(v)?.total,
    };
    return [...state.vehicleTypes]..sort((a, b) {
        final fa = fares[a.id];
        final fb = fares[b.id];
        if (fa != null && fb != null && fa != fb) return fa.compareTo(fb);
        if (fa != null && fb == null) return -1;
        if (fa == null && fb != null) return 1;
        return vehicleClassRank(a).compareTo(vehicleClassRank(b));
      });
  }

  /// 0 bike / scooter (incl. bike lite), 1 auto, 2 cab, 3 bigger cabs.
  static int vehicleClassRank(VehicleTypeModel v) {
    final s = '${v.iconType} ${v.name}'.toLowerCase();
    if (s.contains('bike') || s.contains('moto') || s.contains('scooty') ||
        s.contains('scooter') || s.contains('2 wheeler') ||
        s.contains('two wheeler')) {
      return 0;
    }
    if (s.contains('auto') || s.contains('rickshaw') || s.contains('e-rick')) {
      return 1;
    }
    if (s.contains('suv') || s.contains('xl') || s.contains('premium') ||
        s.contains('luxury') || s.contains('innova')) {
      return 3;
    }
    return 2;
  }

  FareBreakdown? fareForVehicle(VehicleTypeModel vehicle) {
    // The server quote is the exact charge (road distance, platform fee,
    // surge, rounding). The local estimate only fills in while it loads.
    final quoted = state.quotedFares[vehicle.id];
    if (quoted != null) return quoted;
    if (state.quoteUnavailable.contains(vehicle.id)) return null;

    final distanceMeters = state.distanceMeters;
    final durationSeconds = state.durationSeconds;
    if (distanceMeters == null || durationSeconds == null) return null;

    final pricing = state.pricingFor(vehicle.id);
    if (pricing == null) return null;

    return FareCalculator.estimate(
      pricing: pricing,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
    );
  }

  int _quoteRequest = 0;

  /// Asks the server for every vehicle's fare on the current route. Stale
  /// answers (route changed meanwhile) are dropped; on failure the local
  /// estimate stays on screen.
  Future<void> _loadServerQuotes() async {
    final pickup = state.pickup;
    final drop = state.drop;
    final ids = state.vehicleTypes.map((v) => v.id).where((id) => id.isNotEmpty).toList();
    if (pickup == null || drop == null || ids.isEmpty) return;
    final request = ++_quoteRequest;
    try {
      final rows = await ref.read(homeRepositoryProvider).getRideQuotes(
        pickup: [pickup.lng, pickup.lat],
        drop: [drop.lng, drop.lat],
        stops: [for (final s in state.stops) [s.lng, s.lat]],
        vehicleTypeIds: ids,
      );
      if (request != _quoteRequest) return;
      final fares = <String, FareBreakdown>{};
      final unavailable = <String>{};
      double? meters;
      double? minutes;
      for (final row in rows) {
        final id = (row['vehicleTypeId'] ?? '').toString();
        final fare = row['fare'];
        final breakdown = row['available'] == true && fare is Map
            ? FareBreakdown.fromQuote(Map<String, dynamic>.from(fare))
            : null;
        if (breakdown == null) {
          unavailable.add(id);
          continue;
        }
        fares[id] = breakdown;
        meters ??= double.tryParse('${row['measuredDistanceMeters'] ?? ''}');
        minutes ??= double.tryParse('${row['measuredDurationMinutes'] ?? ''}');
      }
      state = state.copyWith(
        quotedFares: fares,
        quoteUnavailable: unavailable,
        distanceMeters: meters,
        durationSeconds: minutes == null ? null : minutes * 60,
      );
      final selected = state.selectedVehicle;
      if (selected != null && state.isUnpriced(selected.id)) {
        final priced = vehiclesByPrice().where((v) => !state.isUnpriced(v.id));
        if (priced.isNotEmpty) state = state.copyWith(selectedVehicle: priced.first);
      }
      _recalculateFare();
    } catch (e) {
      if (kDebugMode) debugPrint('[booking] fare quote failed: $e');
    }
  }

  Future<bool> confirmBooking() async {
    final pickup = state.pickup;
    final drop = state.drop;
    final vehicle = state.selectedVehicle;
    final fare = state.fareBreakdown;
    if (pickup == null || drop == null || vehicle == null || fare == null) {
      state = state.copyWith(error: 'Please select pickup, drop and a ride type'.tr);
      return false;
    }

    state = state.copyWith(isSubmitting: true, clearError: true, step: BookingStep.findingDriver);

    // Armed before the POST so a driver who accepts immediately can't beat us
    // to the `rideAccepted` event.
    final search = ref.read(rideSearchControllerProvider.notifier);
    search.beginCreating();

    try {
      final ride = await ref.read(rideRepositoryProvider).createRide(
            pickup: [pickup.lng, pickup.lat],
            drop: [drop.lng, drop.lat],
            pickupAddress: pickup.address,
            dropAddress: drop.address,
            stops: state.stops
                .map((s) => {
                      'lat': s.lat,
                      'lng': s.lng,
                      'address': s.address,
                    })
                .toList(),
            fare: fare.total,
            estimatedDistanceMeters: state.distanceMeters ?? 0,
            estimatedDurationMinutes: (state.durationSeconds ?? 0) / 60,
            vehicleTypeId: vehicle.id,
            vehicleIconType: VehicleMarkerIcons.familyFor(
              iconType: vehicle.iconType,
              vehicleType: vehicle.name,
            ),
            paymentMethod: state.paymentMethod,
            promoCode: state.promoCode,
            scheduledAt: state.scheduledAt,
          );
      search.attachRide(ride);
      state = state.copyWith(
        isSubmitting: false,
        createdRide: ride,
        step: BookingStep.dispatched,
      );
      return true;
    } catch (e) {
      search.failCreate(e.toString());
      state = state.copyWith(
        isSubmitting: false,
        error: e.toString(),
        step: BookingStep.noDriverFound,
      );
      return false;
    }
  }

  void reset() {
    ref.read(rideSearchControllerProvider.notifier).reset();
    state = const BookingState();
  }
}

final bookingControllerProvider =
    NotifierProvider<BookingController, BookingState>(BookingController.new);
