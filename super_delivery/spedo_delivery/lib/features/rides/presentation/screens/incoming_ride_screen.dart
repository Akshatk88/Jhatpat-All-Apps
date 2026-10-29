import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/core/presentation/widgets/offer_request_card.dart';
import 'package:food_user_application/core/presentation/widgets/offer_ringing.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/features/rides/application/incoming_ride_controller.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';
import 'package:food_user_application/features/rides/presentation/ride_job_kind.dart';
import 'package:food_user_application/features/rides/presentation/widgets/driveu_job_banner.dart';

/// Screen 1 of the ride flow — **request coming**.
///
/// Stacked over the whole app by [main.dart] whenever
/// [incomingRideControllerProvider] is non-null, exactly like the food
/// incoming-order alert, so it works from any route and covers offers that
/// arrive over the socket or over FCM.
///
/// Laid out like a captain app's offer card (see [OfferRequestView], shared
/// with the food offer and the overlay): fare up front, the distance to the
/// pickup and the trip itself on a two-stop timeline, and one big Accept with
/// the countdown ring doubling as the decline button.
class IncomingRideScreen extends ConsumerStatefulWidget {
  const IncomingRideScreen({super.key, required this.ride});

  final TaxiRide ride;

  @override
  ConsumerState<IncomingRideScreen> createState() => _IncomingRideScreenState();
}

class _IncomingRideScreenState extends ConsumerState<IncomingRideScreen>
    with OfferRinging<IncomingRideScreen> {
  /// A ValueNotifier rather than setState so the per-second tick rebuilds only
  /// the countdown rings, not the whole card.
  late final ValueNotifier<int> _secondsLeft;
  Timer? _timer;
  bool _resolving = false;

  /// Driver → pickup, from the phone's last fix. Null until known; the offer
  /// payload does not carry it.
  double? _toPickupKm;

  int get _totalSeconds => widget.ride.expiresInSeconds ?? 20;

  @override
  String get ringingOfferId => widget.ride.id;

  @override
  void initState() {
    super.initState();
    HapticService.light();
    startRinging();

    // The server sends the real accept window; 20s is only the fallback for a
    // payload that predates it. Counting down longer than the server allows
    // would show a live button for an offer already reassigned.
    _secondsLeft = ValueNotifier<int>(_totalSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft.value <= 1) {
        timer.cancel();
        _expire();
        return;
      }
      _secondsLeft.value--;
    });
    _loadDistanceToPickup();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsLeft.dispose();
    disposeRinging();
    super.dispose();
  }

  Future<void> _loadDistanceToPickup() async {
    final pickup = widget.ride.pickup;
    if (pickup == null) return;
    try {
      final here = await Geolocator.getLastKnownPosition();
      if (here == null || !mounted) return;
      final meters = Geolocator.distanceBetween(
        here.latitude,
        here.longitude,
        pickup.latitude,
        pickup.longitude,
      );
      setState(() => _toPickupKm = meters / 1000);
    } catch (_) {
      // No fix or no permission: the leg just shows without a distance.
    }
  }

  void _expire() {
    if (_resolving) return;
    _resolving = true;
    stopRinging();
    ref.read(incomingRideControllerProvider.notifier).expire();
  }

  Future<void> _accept() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    _timer?.cancel();
    stopRinging();
    HapticService.medium();

    final result = await ref.read(incomingRideControllerProvider.notifier).accept();
    if (!mounted) return;
    result.when(
      // The trip screen takes over from the active-ride controller; nothing to
      // navigate to here.
      success: (_) {},
      failure: (error) {
        setState(() => _resolving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.message), backgroundColor: kOfferRed),
        );
      },
    );
  }

  void _decline() {
    if (_resolving) return;
    _resolving = true;
    _timer?.cancel();
    stopRinging();
    HapticService.light();
    ref.read(incomingRideControllerProvider.notifier).decline();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    return OfferRequestView(
      secondsLeft: _secondsLeft,
      totalSeconds: _totalSeconds,
      fare: ride.fare,
      bonus: ride.bonus,
      // "Parcel" with a box for parcel jobs, the vehicle for passengers.
      jobLabel: RideJobKind.labelOf(ride),
      jobIcon: RideJobKind.iconOf(ride),
      // Above the fare on purpose: what the job actually is matters more than
      // what it pays, and a DriveU job is easy to misread.
      banner: DriveUJobBanner(ride: ride),
      paymentNote: ride.isCash ? 'Collect cash' : 'Paid online',
      paymentNoteColor: ride.isCash ? const Color(0xFFB7791F) : kOfferGreen,
      pickup: OfferStop.fromAddress(
        ride.pickupAddress.isEmpty ? 'Pickup location' : ride.pickupAddress,
        distance: _toPickupKm == null ? null : '${_toPickupKm!.toStringAsFixed(1)} km',
        duration: _toPickupKm == null
            ? null
            : '(${OfferRequestView.minsForKm(_toPickupKm!)} mins)',
      ),
      drop: OfferStop.fromAddress(
        ride.dropAddress.isEmpty ? 'Drop location' : ride.dropAddress,
        distance: ride.distanceMeters > 0 ? '${ride.distanceKm.toStringAsFixed(1)} km' : null,
        duration: ride.durationMinutes > 0 ? '(${ride.durationMinutes} mins)' : null,
      ),
      soundOn: soundOn,
      onToggleSound: toggleSound,
      resolving: _resolving,
      onAccept: _accept,
      onDecline: _decline,
    );
  }
}
