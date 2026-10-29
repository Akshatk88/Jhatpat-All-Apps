import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:food_user_application/core/presentation/widgets/offer_request_card.dart';
import 'package:food_user_application/core/presentation/widgets/offer_ringing.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/core/services/location_service.dart';
import 'package:food_user_application/features/orders/application/incoming_order_controller.dart';
import 'package:food_user_application/features/orders/data/models/delivery_order.dart';

/// Default accept window when the offer names none — the push itself tells the
/// rider "You have 60 seconds to accept".
const _defaultOfferSeconds = 60;

/// Full-screen incoming food offer, in the same captain-style
/// card as the ride offer ([OfferRequestView]). Stacked over the entire app by
/// [main.dart]'s overlay builder whenever [incomingOrderControllerProvider] is
/// non-null — works regardless of the current GoRouter location, and is the
/// single UI path for orders arriving via Socket.IO, FCM or the poll.
class IncomingOrderScreen extends ConsumerStatefulWidget {
  const IncomingOrderScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<IncomingOrderScreen> createState() => _IncomingOrderScreenState();
}

class _IncomingOrderScreenState extends ConsumerState<IncomingOrderScreen>
    with OfferRinging<IncomingOrderScreen> {
  // ValueNotifier so the once-a-second tick only rebuilds the countdown rings.
  late final ValueNotifier<int> _secondsLeft;
  late final int _totalSeconds;
  Timer? _timer;
  bool _resolving = false;

  /// The rider's last fix, for the pickup distance when the offer carries
  /// none (every push-delivered and polled offer).
  Position? _here;

  @override
  String get ringingOfferId => widget.order.id;

  @override
  void initState() {
    super.initState();
    HapticService.light();
    startRinging();

    final deadline = widget.order.acceptanceDeadlineAt;
    _totalSeconds = deadline != null
        ? deadline.difference(DateTime.now()).inSeconds.clamp(1, 300)
        : _defaultOfferSeconds;
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
    _loadPosition();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _secondsLeft.dispose();
    disposeRinging();
    super.dispose();
  }

  Future<void> _loadPosition() async {
    Position? here = ref.read(locationServiceProvider).lastPosition;
    if (here == null) {
      try {
        here = await Geolocator.getLastKnownPosition();
      } catch (_) {
        // No fix or no permission: the pickup leg shows without a distance.
      }
    }
    if (here != null && mounted) setState(() => _here = here);
  }

  Future<void> _accept() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    _timer?.cancel();
    stopRinging();
    HapticService.medium();
    final error =
        await ref.read(incomingOrderControllerProvider.notifier).accept();
    // Without this the rider watched the order disappear with no explanation
    // and reasonably concluded the app had invented it.
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _decline() async {
    if (_resolving) return;
    _resolving = true;
    _timer?.cancel();
    stopRinging();
    HapticService.light();
    await ref.read(incomingOrderControllerProvider.notifier).decline();
  }

  Future<void> _expire() async {
    if (_resolving) return;
    _resolving = true;
    stopRinging();
    await ref.read(incomingOrderControllerProvider.notifier).expire();
  }

  /// Rider → restaurant: dispatch's figure when it sent one, else measured from
  /// the last fix once the restaurant's coordinates are known (the socket
  /// payload and the hydrated order carry them; the push does not).
  double? get _toPickupKm {
    final sent = widget.order.pickupDistanceKm;
    if (sent != null && sent > 0) return sent;
    final restaurant = widget.order.restaurant.location;
    final here = _here;
    if (restaurant == null || here == null) return null;
    return Geolocator.distanceBetween(
          here.latitude,
          here.longitude,
          restaurant.lat,
          restaurant.lng,
        ) /
        1000;
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final toPickupKm = _toPickupKm;
    final tripKm = order.tripDistanceKm;
    final tripMins = order.tripDurationMins;

    final restaurantAddress = order.restaurant.address;
    final pickup = order.restaurant.name.trim().isNotEmpty
        ? OfferStop(name: order.restaurant.name.trim(), detail: restaurantAddress)
        : OfferStop.fromAddress(
            restaurantAddress.isEmpty ? 'Pickup location' : restaurantAddress,
          );

    final dropAddress = order.deliveryAddress.fullAddress;
    final drop = dropAddress.isNotEmpty
        ? OfferStop.fromAddress(dropAddress)
        : OfferStop(
            name: order.customerName.trim().isEmpty ? 'Drop location' : order.customerName.trim(),
          );

    return PopScope(
      canPop: false,
      child: OfferRequestView(
        secondsLeft: _secondsLeft,
        totalSeconds: _totalSeconds,
        fare: order.riderEarning > 0 ? order.riderEarning : null,
        jobLabel: 'Food delivery',
        jobIcon: Icons.delivery_dining_rounded,
        pickup: OfferStop(
          name: pickup.name,
          detail: pickup.detail,
          distance: toPickupKm == null ? null : '${toPickupKm.toStringAsFixed(1)} km',
          duration: toPickupKm == null
              ? null
              : '(${OfferRequestView.minsForKm(toPickupKm)} mins)',
        ),
        drop: OfferStop(
          name: drop.name,
          detail: drop.detail,
          distance: tripKm != null && tripKm > 0 ? '${tripKm.toStringAsFixed(1)} km' : null,
          duration: tripMins != null && tripMins > 0
              ? '(${tripMins.toStringAsFixed(0)} mins)'
              : null,
        ),
        soundOn: soundOn,
        onToggleSound: toggleSound,
        resolving: _resolving,
        onAccept: _accept,
        onDecline: _decline,
      ),
    );
  }
}
