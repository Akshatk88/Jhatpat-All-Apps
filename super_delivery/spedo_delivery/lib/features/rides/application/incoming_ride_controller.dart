import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/incoming_alert_channel.dart';
import '../../../core/services/socket_service.dart';
import '../../work_mode/application/work_mode_controller.dart';
import '../data/models/taxi_ride.dart';
import '../data/rides_repository.dart';
import 'active_ride_controller.dart';

/// The ride-offer equivalent of `IncomingOrderController`.
///
/// `null` means no offer on screen. Offers reach the app two ways — the socket
/// while it is open, FCM `type: ride_request` while it is backgrounded — and
/// both funnel here so the alert is raised exactly once either way.
class IncomingRideController extends Notifier<TaxiRide?> {
  StreamSubscription<Map<String, dynamic>>? _requestSub;
  StreamSubscription<Map<String, dynamic>>? _closedSub;
  StreamSubscription<Map<String, dynamic>>? _fcmReceivedSub;
  StreamSubscription<Map<String, dynamic>>? _fcmTapSub;
  StreamSubscription<Map<String, String>>? _nativeResolvedSub;

  /// Dispatch re-offers a ride to the same driver across retry rounds. Without
  /// this the alert reappears seconds after being declined.
  final Set<String> _dismissedRideIds = {};

  /// `type` values that mean "ride-dispatcher offer": the FCM push's
  /// `ride_request`, and the socket's serviceType-valued `type`.
  static const _rideTypes = {'ride_request', 'ride', 'parcel'};

  @override
  TaxiRide? build() {
    final socket = ref.read(socketServiceProvider);
    _requestSub = socket.onRideRequest.listen(_onOffer);
    _closedSub = socket.onRideRequestClosed.listen(_onClosed);

    final fcm = ref.read(fcmServiceProvider);
    _fcmReceivedSub = fcm.onNotificationReceived.listen(_onOffer);
    _fcmTapSub = fcm.onNotificationTap.listen(_onOffer);

    IncomingAlertChannel.listen();
    _nativeResolvedSub =
        IncomingAlertChannel.nativelyResolved.listen(_onNativelyResolved);

    ref.onDispose(() {
      _requestSub?.cancel();
      _closedSub?.cancel();
      _fcmReceivedSub?.cancel();
      _fcmTapSub?.cancel();
      _nativeResolvedSub?.cancel();
    });

    return null;
  }

  /// [honourModule] is false only for an Accept the rider tapped on the native
  /// lock-screen card. Kotlin already filters by the saved module before
  /// raising that card, but the rider may have switched parcel ↔ rider since;
  /// once they have chosen to take the job, silently dropping it would be
  /// worse than honouring it.
  Future<void> _onOffer(
    Map<String, dynamic> data, {
    bool honourModule = true,
  }) async {
    // FCM carries every push type on one stream (a food `new_order` included),
    // so only ride-dispatcher types get past here.
    //
    // The socket's `rideRequest` sets `type` to the ride's serviceType —
    // `ride | parcel` (dispatchService.emitRideRequestToDrivers). Intercity was
    // removed server-side, so it is no longer accepted here.
    final type = data['type']?.toString();
    if (type != null && !_rideTypes.contains(type)) return;

    // A driver in Food-only mode must never see a ride, even if a stale offer
    // arrives from a dispatch round that started before they switched.
    if (!ref.read(workModeControllerProvider.notifier).acceptsRides) return;

    final rideId = (data['rideId'] ?? data['_id'] ?? data['id'])?.toString();
    if (rideId == null || rideId.isEmpty) return;
    if (_dismissedRideIds.contains(rideId)) return;
    if (state?.id == rideId) return;

    // Already driving? A second offer would be a backend bug, but showing it
    // would let the driver abandon a passenger mid-trip.
    // A finished ride lingers briefly for its summary; only a live trip blocks offers.
    if (ref.read(activeRideControllerProvider).value?.stage.isActive == true) return;

    final offer = TaxiRide.fromJson(data);

    // Parcel and passenger jobs share the ride dispatcher (and the server's
    // `taxi` work mode), so the module split happens here: a Rider ignores
    // parcels, a Parcel rider ignores passengers. "Ignore" means not shown and
    // not rung — never rejected, so the offer just expires server-side and the
    // driver is not penalised for it. Only decided now when the payload says
    // what it is; a bare push is checked again once the ride is fetched.
    final declaresKind =
        data['serviceType'] != null || (type != null && type != 'ride_request');
    if (honourModule && declaresKind && !_belongsToModule(offer)) return;

    // The push carries only {type, rideId, serviceType, userId} — no fare, no
    // addresses — so an offer that arrived that way has to be filled in before
    // it can be shown. The socket payload is already complete and skips this.
    if (offer.pickup == null && offer.fare == 0) {
      final full = await ref.read(ridesRepositoryProvider).getRide(rideId);
      // Re-check: the driver may have declined or taken another job while the
      // fetch was in flight.
      if (_dismissedRideIds.contains(rideId)) return;
    // A finished ride lingers briefly for its summary; only a live trip blocks offers.
    if (ref.read(activeRideControllerProvider).value?.stage.isActive == true) return;
      full.when(
        success: (ride) {
          // Someone else won it, or the passenger cancelled, between the push
          // being sent and this reaching the server.
          if (ride.stage != RideStage.searching) return;
          if (honourModule && !_belongsToModule(ride)) return;
          state = ride;
        },
        failure: (_) {},
      );
      return;
    }

    state = offer;
  }

  bool _belongsToModule(TaxiRide ride) => ref
      .read(workModeControllerProvider.notifier)
      .acceptsOffer(isParcel: ride.isParcel);

  void _onClosed(Map<String, dynamic> data) {
    final rideId = (data['rideId'] ?? data['_id'] ?? data['id'])?.toString();
    if (rideId == null || rideId.isEmpty) return;
    // Recorded even when nothing is on screen: a queued FCM offer can be
    // delivered after the close event, and would otherwise raise an alert for
    // a ride that is already gone.
    _dismissedRideIds.add(rideId);
    if (state?.id == rideId) state = null;
    // Also takes down the native lock-screen alert raised for this ride.
    unawaited(IncomingAlertChannel.dismiss(rideId));
  }

  /// Reject tapped on the native card or notification while this engine is
  /// alive. Kotlin cannot decline a ride (socket only), so it is sent from
  /// here; an Accept is left to [acceptFromAlert], which the app opening runs.
  void _onNativelyResolved(Map<String, String> event) {
    if (event['type'] != 'ride_request' || event['action'] != 'reject') return;
    final rideId = event['orderId'];
    if (rideId == null || rideId.isEmpty) return;
    if (state?.id == rideId) {
      decline();
      return;
    }
    if (_dismissedRideIds.add(rideId)) {
      ref.read(socketServiceProvider).rejectRide(rideId);
    }
  }

  /// Accept tapped on the native lock-screen card. Ride claims go over the
  /// socket only (there is no REST accept), so Kotlin cannot send this one
  /// itself — it hands the choice over and the claim is made here, once.
  Future<void> acceptFromAlert(Map<String, dynamic> data) async {
    await _onOffer(
      {...data, 'type': 'ride_request'},
      honourModule: false,
    );
    final rideId = (data['rideId'] ?? data['_id'] ?? data['id'])?.toString();
    if (rideId == null || state?.id != rideId) return;
    await accept();
  }

  /// Takes the ride. On success the active-ride controller owns it from here
  /// and the trip screen takes over.
  Future<Result<TaxiRide, AppError>> accept() async {
    final ride = state;
    if (ride == null) {
      return Result.failure(UnknownError('This ride is no longer available'));
    }
    _dismissedRideIds.add(ride.id);
    unawaited(IncomingAlertChannel.dismiss(ride.id));

    final result =
        await ref.read(activeRideControllerProvider.notifier).acceptRide(ride);
    // Cleared either way — on success the trip screen replaces it, on failure
    // the offer is stale (another driver won it) and re-showing it is a lie.
    state = null;
    return result;
  }

  /// Declines. Told to the server over the socket so dispatch moves on at once
  /// instead of waiting out the accept window.
  void decline() {
    final ride = state;
    if (ride == null) return;
    _dismissedRideIds.add(ride.id);
    state = null;
    unawaited(IncomingAlertChannel.dismiss(ride.id));
    ref.read(socketServiceProvider).rejectRide(ride.id);
  }

  /// The countdown ran out on this device. Same wire call as a decline — the
  /// server's own dispatch timer remains the authority.
  void expire() => decline();

  void dismiss() => state = null;
}

final incomingRideControllerProvider =
    NotifierProvider<IncomingRideController, TaxiRide?>(
  IncomingRideController.new,
);
