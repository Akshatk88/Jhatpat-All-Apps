import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:food_user_application/core/constants/map_styles.dart';
import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/core/services/gps_fix_filter.dart';
import 'package:food_user_application/core/services/location_service.dart';
import 'package:food_user_application/core/utils/map_launcher.dart';
import 'package:food_user_application/features/rides/application/active_ride_controller.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';
import 'package:food_user_application/features/rides/presentation/ride_job_kind.dart';
import 'package:food_user_application/features/rides/presentation/widgets/driveu_job_banner.dart';
import 'package:food_user_application/features/rides/data/ride_route_service.dart';
import 'package:food_user_application/features/rides/presentation/widgets/cancel_reason_sheet.dart';
import 'package:food_user_application/features/rides/presentation/widgets/collect_fare_sheet.dart';
import 'package:food_user_application/features/rides/presentation/widgets/driver_bike_marker.dart';
import 'package:food_user_application/features/rides/presentation/widgets/driver_marker_animator.dart';
import 'package:food_user_application/features/rides/presentation/widgets/ride_chat_sheet.dart';
import 'package:food_user_application/features/rides/presentation/widgets/ride_otp_sheet.dart';
import 'package:food_user_application/features/rides/presentation/widgets/ride_stage_timeline.dart';
import 'package:food_user_application/features/rides/presentation/widgets/parcel_proof_card.dart';
import 'package:food_user_application/features/safety/presentation/sos_flow.dart';
import 'package:food_user_application/core/services/road_name_service.dart';
import 'package:food_user_application/core/utils/route_progress.dart';
import 'package:food_user_application/features/orders/presentation/widgets/trip_nav_widgets.dart';

const _rideBlue = Color(0xFF1B6FF3);
const _rideGreen = Color(0xFF1EBE5D);
const _rideRed = Color(0xFFF04438);
const _rideAmber = Color(0xFFF79009);

/// The server stamps the waiting clock only within this distance of the pickup
/// (`ARRIVAL_RADIUS_M` in rideService / the socket `locationUpdate` handler).
const _arrivalRadiusMeters = 500.0;

/// Off the drawn line by more than this (plus the fix's accuracy, capped) counts
/// as an off-route fix.
const _offRouteMeters = 50.0;

/// A reroute needs this many off-route fixes in a row (one bad fix is GPS
/// noise, not a wrong turn) ...
const _offRouteFixesNeeded = 3;

/// ... and at least this long since the previous route request.
const _rerouteCooldown = Duration(seconds: 25);

/// Screens 2–5 of the ride flow — **Accept, Arrive, Pickup, Drop** — as one
/// stage-driven trip screen.
///
/// Four separate routes would each need the same map, the same passenger card
/// and the same reconnect handling, and would let the driver navigate back to
/// a stage the server has already moved past. Instead the stage drives the
/// panel: the map target, the headline and the single primary action all come
/// from [TaxiRide.stage], which is whatever the server last confirmed.
class ActiveRideScreen extends ConsumerStatefulWidget {
  const ActiveRideScreen({super.key});

  @override
  ConsumerState<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends ConsumerState<ActiveRideScreen> {
  GoogleMapController? _mapController;
  bool _busy = false;

  List<LatLng> _routePoints = const [];
  bool _routeApproximate = false;
  final RoadNameService _roads = RoadNameService();
  String? _turnRoad;
  LatLng? _turnRoadFor;
  double? _etaMins;
  double? _distanceKm;
  Timer? _routeTimer;
  StreamSubscription<Position>? _positionSub;

  /// The driver's bike marker, built once (see [DriverBikeMarker]).
  BitmapDescriptor? _bikeIcon;
  Position? _driverPosition;

  /// Glides the bike between fixes. Only the GoogleMap listens to it, so a GPS
  /// fix no longer rebuilds the whole trip screen.
  final _markerAnimator = DriverMarkerAnimator();
  DateTime? _lastFixAt;

  /// Bumped for every route request; a response is applied only if it is
  /// still the latest, so a slow answer for an old origin or leg can never
  /// overwrite a newer one.
  int _routeSeq = 0;

  /// Consecutive fixes found off the drawn route (see [_offRouteFixesNeeded]).
  int _offRouteStreak = 0;

  /// Which leg the drawn route belongs to, so it is refetched when the target
  /// changes at pickup rather than continuing to show the way to a place the
  /// driver has already reached.
  String? _routeLegKey;

  /// The leg the camera has already been framed for, so it is only fitted once.
  String? _fittedLegKey;
  bool _routeFetchInFlight = false;
  DateTime _lastRouteFetch = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastTrim = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastCameraMove = DateTime.fromMillisecondsSinceEpoch(0);

  /// Camera follows the driver until they pan the map; the recenter button
  /// turns it back on.
  bool _follow = true;

  /// Measured overlay heights, so the map keeps its markers and the camera
  /// target out from under the header and the action sheet.
  final _headerKey = GlobalKey();
  final _sheetKey = GlobalKey();
  double _headerHeight = 0;
  double _sheetHeight = 0;

  /// Chat messages already seen, for the unread dot. Null until first build.
  int? _seenMessages;

  /// The point the driver is heading to right now: the pickup until the
  /// passenger is on board, the drop afterwards.
  LatLng? _targetOf(TaxiRide ride) => ride.stage.isOnBoard ? ride.drop : ride.pickup;

  String _legKeyOf(TaxiRide ride) => '${ride.id}:${ride.stage.isOnBoard}';

  @override
  void initState() {
    super.initState();
    _driverPosition = ref.read(locationServiceProvider).lastPosition;
    final seed = _driverPosition;
    if (seed != null) {
      _markerAnimator.moveTo(
        LatLng(seed.latitude, seed.longitude),
        rotation: _validHeading(seed),
      );
    }
    _positionSub =
        ref.read(locationServiceProvider).positionStream.listen(_onPosition);
    DriverBikeMarker.icon().then((icon) {
      if (mounted) setState(() => _bikeIcon = icon);
    });
    // The route needs a GPS fix; if one is already warm draw immediately,
    // otherwise the first position event below triggers it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshRoute());
    // Routing is requested only initially, on a leg change and on a confirmed
    // off-route. The timer exists solely to retry a *road* route while only
    // the straight-line fallback could be drawn (OSRM briefly down); with a
    // road route on screen it makes no request at all. ETA/distance between
    // requests are scaled from the remaining polyline in _trackAlongRoute.
    _routeTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) {
        if (_routePoints.isEmpty || _routeApproximate) _refreshRoute();
      },
    );
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    _positionSub?.cancel();
    _markerAnimator.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  /// The device heading, when it means something (moving, valid value).
  static double? _validHeading(Position p) {
    final h = p.heading;
    if (p.speed.isFinite && p.speed >= 1.0 && h.isFinite && h >= 0) {
      return h % 360;
    }
    return null;
  }

  void _onPosition(Position position) {
    if (!mounted) return;
    final previous = _driverPosition;
    _driverPosition = position;
    final here = LatLng(position.latitude, position.longitude);

    // Facing: device heading while moving; else the bearing of the last
    // movement; else unchanged (no snapping to north at a standstill).
    var rotation = _validHeading(position);
    if (rotation == null && previous != null) {
      final moved = RideRouteService.distanceMeters(
        LatLng(previous.latitude, previous.longitude),
        here,
      );
      if (moved >= 3) {
        rotation = GpsFixFilter.bearingDegrees(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }
    // Glide for about as long as fixes are apart, so the bike arrives as the
    // next fix lands instead of sprinting and waiting.
    final now = DateTime.now();
    final gapMs = _lastFixAt == null
        ? 1000
        : now.difference(_lastFixAt!).inMilliseconds.clamp(300, 2500);
    _lastFixAt = now;
    _markerAnimator.moveTo(
      here,
      rotation: rotation,
      duration: Duration(milliseconds: (gapMs * 0.9).round()),
    );

    final ride = ref.read(activeRideControllerProvider).value;
    if (ride == null || ride.stage.isFinished) return;

    if (_routePoints.isEmpty || _routeLegKey != _legKeyOf(ride)) {
      _refreshRoute();
    } else {
      _trackAlongRoute(here);
    }
    _followCamera(ride);
  }

  /// Keeps the drawn line attached to the driver: the part already driven is
  /// dropped, and a driver who has left the line gets a fresh route.
  void _trackAlongRoute(LatLng here) {
    final now = DateTime.now();
    if (_routeApproximate) {
      // Straight-line fallback: just re-anchor it on the driver.
      if (now.difference(_lastTrim) < const Duration(seconds: 3)) return;
      _lastTrim = now;
      final target = _routePoints.last;
      setState(() {
        _routePoints = [here, target];
        final km = RideRouteService.distanceMeters(here, target) / 1000.0;
        _distanceKm = km;
        _etaMins = km * 1.3 / 25 * 60;
      });
      return;
    }

    final located = RideRouteService.locateOnRoute(here, _routePoints);
    final rawAccuracy = _driverPosition?.accuracy ?? 0;
    final accuracy = rawAccuracy.isFinite && rawAccuracy > 0 ? rawAccuracy : 0.0;
    if (located.offMeters > _offRouteMeters + math.min(accuracy, 50.0)) {
      // A fix this vague cannot prove a wrong turn; neither count nor reset.
      if (accuracy > 50) return;
      _offRouteStreak++;
      if (_offRouteStreak >= _offRouteFixesNeeded &&
          now.difference(_lastRouteFetch) >= _rerouteCooldown) {
        _offRouteStreak = 0;
        _refreshRoute();
      }
      return;
    }
    _offRouteStreak = 0;
    if (now.difference(_lastTrim) < const Duration(seconds: 3)) return;
    if (located.segment == 0 && _routePoints.length < 3) return;
    _lastTrim = now;
    final rest = _routePoints.sublist(located.segment + 1);
    if (rest.isEmpty) return;
    setState(() {
      _routePoints = [here, ...rest];
      // Remaining distance along the line; ETA scaled to match.
      var meters = 0.0;
      for (var i = 0; i < _routePoints.length - 1; i++) {
        meters += RideRouteService.distanceMeters(_routePoints[i], _routePoints[i + 1]);
      }
      final km = meters / 1000.0;
      if (_distanceKm != null && _distanceKm! > 0 && _etaMins != null) {
        _etaMins = _etaMins! * (km / _distanceKm!);
      }
      _distanceKm = km;
    });
  }

  /// Resolves a position for the route origin.
  ///
  /// `lastPosition` stays null until the movement-gated stream first emits,
  /// which never happens for a driver sitting still at the pickup — the exact
  /// case where the route matters most. Falling back rather than giving up is
  /// the difference between a drawn route and a blank map.
  Future<Position?> _resolveOrigin() async {
    final cached = _driverPosition ?? ref.read(locationServiceProvider).lastPosition;
    if (cached != null) return cached;
    try {
      return await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();
    } catch (_) {
      return null;
    }
  }

  /// Redraws the road route from the driver to whatever they are heading for.
  ///
  /// Called initially, on a leg change ([legChange]: supersedes any request
  /// still out for the old leg), on a confirmed off-route and by
  /// the straight-line retry timer. Every request gets a sequence number and
  /// only the latest one's answer is drawn.
  Future<void> _refreshRoute({bool legChange = false}) async {
    if (_routeFetchInFlight && !legChange) return;
    final ride = ref.read(activeRideControllerProvider).value;
    if (ride == null || ride.stage.isFinished) return;

    final target = _targetOf(ride);
    if (target == null) return;

    final seq = ++_routeSeq;
    _routeFetchInFlight = true;
    _lastRouteFetch = DateTime.now();
    final from = await _resolveOrigin();
    if (!mounted || seq != _routeSeq) return; // superseded; the newer one owns the flag
    if (from == null) {
      _routeFetchInFlight = false;
      return;
    }
    _driverPosition ??= from;
    if (_markerAnimator.pose.value == null) {
      _markerAnimator.moveTo(LatLng(from.latitude, from.longitude));
    }

    final route = await ref.read(rideRouteServiceProvider).fetch(
          from: LatLng(from.latitude, from.longitude),
          to: target,
        );
    if (!mounted || seq != _routeSeq) return;
    _routeFetchInFlight = false;
    if (route.isEmpty) return;

    // The stage may have moved on while the request was out.
    final current = ref.read(activeRideControllerProvider).value;
    if (current == null || current.stage.isFinished) return;
    if (_legKeyOf(current) != _legKeyOf(ride)) return;

    final legKey = _legKeyOf(ride);

    // Both road routers failed and only the straight-line fallback came back:
    // keep the road route already drawn for this leg rather than replacing a
    // real line with a dashed guess.
    if (route.isApproximate &&
        _routeLegKey == legKey &&
        !_routeApproximate &&
        _routePoints.length >= 2) {
      return;
    }

    setState(() {
      _routePoints = route.points;
      _routeApproximate = route.isApproximate;
      _etaMins = route.durationMins;
      _distanceKm = route.distanceKm;
      _routeLegKey = legKey;
    });
    _offRouteStreak = 0;

    // Frame the route once per leg. Re-fitting on every refresh would yank
    // the camera back while the driver is panning or zooming to read the road.
    if (_fittedLegKey != legKey) {
      _fittedLegKey = legKey;
      _fitRoute();
    }
  }

  void _fitRoute() {
    final controller = _mapController;
    if (controller == null || _routePoints.isEmpty) return;
    _lastCameraMove = DateTime.now();
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(_boundsOf(_routePoints), 56),
    );
  }

  static LatLngBounds _boundsOf(List<LatLng> points) {
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    // A degenerate box (driver standing on the target) makes the SDK throw.
    if ((maxLat - minLat).abs() < 0.0005) {
      minLat -= 0.0005;
      maxLat += 0.0005;
    }
    if ((maxLng - minLng).abs() < 0.0005) {
      minLng -= 0.0005;
      maxLng += 0.0005;
    }
    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  /// Keeps the driver and where they are going in view. Close to the target
  /// both are framed together; far from it the camera centres on the driver at
  /// street zoom so the next turns are readable.
  void _followCamera(TaxiRide ride, {bool force = false}) {
    final controller = _mapController;
    final pos = _driverPosition;
    if (controller == null || pos == null || (!_follow && !force)) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastCameraMove) < const Duration(seconds: 3)) {
      return;
    }
    _lastCameraMove = now;
    final here = LatLng(pos.latitude, pos.longitude);
    final target = _targetOf(ride);
    if (target != null &&
        RideRouteService.distanceMeters(here, target) < 2500) {
      controller.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsOf([here, target]), 72),
      );
    } else {
      controller.animateCamera(CameraUpdate.newLatLngZoom(here, 16));
    }
  }

  Future<void> _advance(TaxiRide ride) async {
    if (_busy) return;

    // "Arrived at pickup" tells the passenger the driver is there and starts
    // their clock, so a tap from far away is confirmed rather than sent.
    if (ride.stage == RideStage.accepted && ride.pickup != null) {
      final from = await _resolveOrigin();
      if (!mounted) return;
      if (from != null) {
        final meters = RideRouteService.distanceMeters(
          LatLng(from.latitude, from.longitude),
          ride.pickup!,
        );
        if (meters > _arrivalRadiusMeters) {
          final go = await _confirmFarArrival(meters, ride.isParcel);
          if (go != true || !mounted) return;
        }
      }
    }

    // Parcel jobs: ask for a proof photo at the hand-over (pickup / drop)
    // before the stage moves. The server does not demand one, so the captain
    // may skip it; backing out of the prompt leaves the stage where it is.
    if (ride.isParcel) {
      final proceed = await ensureParcelProof(context, ref, ride);
      if (!proceed || !mounted) return;
    }

    // Two of the four transitions need something from the driver first. Both
    // are hard gates the backend also enforces — the OTP because it proves the
    // right passenger boarded, the fare because completion settles money and
    // cannot be undone from the app.
    if (ride.stage.nextNeedsOtp) {
      // Loop rather than one shot: a mistyped code is the common case, and
      // making the driver find the button again for every retry — with a
      // passenger waiting — is the wrong place to be strict.
      while (mounted) {
        final otp = await showRideOtpSheet(context, isParcel: ride.isParcel);
        if (!mounted) return;
        if (otp == null) {
          // Dismissed without a code. Say so — silently returning to a screen
          // that still reads "Start trip" is indistinguishable from the button
          // being broken.
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ride.isParcel
                    ? 'Pickup not confirmed — the customer code is needed'
                    : 'Trip not started — the passenger code is needed',
              ),
            ),
          );
          return;
        }

        setState(() => _busy = true);
        HapticService.medium();
        final result =
            await ref.read(activeRideControllerProvider.notifier).advance(otp: otp);
        if (!mounted) return;
        setState(() => _busy = false);

        final failure = result.when(
          success: (_) => null,
          failure: (error) => error.message,
        );
        if (failure == null) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure), backgroundColor: _rideRed),
        );
        // Only a wrong code is worth retrying in place; anything else (the
        // ride moved on, network) has already triggered a re-read.
        if (!failure.toLowerCase().contains('otp')) return;
      }
      return;
    }

    if (ride.stage.nextSettlesFare) {
      final settlement = await showCollectFareSheet(context, ride);
      if (settlement == null || !mounted) return;
      await _run(
        () => ref.read(activeRideControllerProvider.notifier).advance(
              paymentMethod: settlement.paymentMethod,
              fare: settlement.fare,
              collectedByDriver: settlement.collectedByDriver,
            ),
      );
      return;
    }

    await _run(() => ref.read(activeRideControllerProvider.notifier).advance());
  }

  Future<bool?> _confirmFarArrival(double meters, bool isParcel) {
    final away = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} km'
        : '${meters.round()} m';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not at the pickup yet?'),
        content: Text(
          'You are $away from the pickup. Marking arrived tells the '
          '${isParcel ? 'customer' : 'passenger'} you are there, and you can no '
          'longer cancel this job. Waiting charges only start within 500 m.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I have arrived'),
          ),
        ],
      ),
    );
  }

  Future<void> _run(
    Future<Result<TaxiRide, AppError>> Function() action,
  ) async {
    setState(() => _busy = true);
    HapticService.medium();
    final result = await action();
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_) {},
      failure: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: _rideRed),
      ),
    );
  }


  Future<void> _confirmCancel(TaxiRide ride) async {
    if (!ride.stage.driverCanCancel) {
      // The backend only releases a ride before the driver reaches the pickup.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'You have already reached the pickup, so this '
            '${ride.isParcel ? 'delivery' : 'ride'} cannot be cancelled from '
            'the app. Call the ${ride.isParcel ? 'customer' : 'passenger'} or '
            'contact support.',
          ),
        ),
      );
      return;
    }

    final feeNote = ride.driverCancellationFee > 0
        ? (ride.driverCancellationFeeIsPercent
            ? 'A cancellation fee of ${ride.driverCancellationFee.toStringAsFixed(0)}% '
                'of the fare may be deducted from your wallet.'
            : 'A cancellation fee of ₹${ride.driverCancellationFee.toStringAsFixed(0)} '
                'may be deducted from your wallet.')
        : 'Frequent cancellations reduce how many rides you are offered.';

    final reason = await showDriverCancelReasonSheet(
      context,
      partyLabel: ride.isParcel ? 'Customer' : 'Passenger',
      note: feeNote,
    );
    if (reason == null || !mounted) return;

    setState(() => _busy = true);
    final result =
        await ref.read(activeRideControllerProvider.notifier).cancel(reason: reason);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_) {},
      failure: (error) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message), backgroundColor: _rideRed),
      ),
    );
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final ok = await MapLauncher.dial(phone);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the dialer. Number: $phone')),
      );
    }
  }

  Future<void> _navigate(LatLng target) async {
    final ok = await MapLauncher.launchGoogleMaps(target.latitude, target.longitude);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No maps app found to start navigation')),
      );
    }
  }

  Future<void> _openChat(TaxiRide ride) async {
    setState(() => _seenMessages = ride.messages.length);
    await showRideChatSheet(context);
    if (!mounted) return;
    final latest = ref.read(activeRideControllerProvider).value;
    setState(() => _seenMessages = latest?.messages.length ?? _seenMessages);
  }

  /// Re-measures the header and sheet after layout; the map padding follows.
  void _measureOverlays() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _headerKey.currentContext?.size?.height ?? 0;
      final s = _sheetKey.currentContext?.size?.height ?? 0;
      if ((h - _headerHeight).abs() > 4 || (s - _sheetHeight).abs() > 4) {
        setState(() {
          _headerHeight = h;
          _sheetHeight = s;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rideAsync = ref.watch(activeRideControllerProvider);
    final ride = rideAsync.value;

    // At pickup the destination flips from pickup to drop, so the route has to
    // be redrawn for the new leg the moment the stage advances.
    //
    // Deferred to after the frame on purpose: this listener fires while the
    // provider is updating, which can be mid-build, and calling setState there
    // throws — which is what froze the screen the instant the OTP was accepted.
    ref.listen(activeRideControllerProvider, (previous, next) {
      final prevRide = previous?.value;
      final nextRide = next.value;
      if (nextRide == null || nextRide.stage.isFinished) return;
      final changedLeg = prevRide == null ||
          prevRide.id != nextRide.id ||
          prevRide.stage.isOnBoard != nextRide.stage.isOnBoard;
      if (!changedLeg) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _routePoints = const [];
          _etaMins = null;
          _distanceKm = null;
          _routeLegKey = null;
          _fittedLegKey = null;
          _follow = true;
          _offRouteStreak = 0;
        });
        _refreshRoute(legChange: true);
      });
    });

    if (rideAsync.isLoading && ride == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (ride == null) {
      // Completed or cancelled while this screen was open. Pop back rather
      // than showing an empty trip.
      return _buildNoRide(isDark);
    }

    _seenMessages ??= ride.messages.length;
    _measureOverlays();
    final media = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF10131A) : Colors.white,
      body: Stack(
        children: [
          Positioned.fill(child: _buildMap(ride)),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            // Phone-width on tablets/desktop rather than spanning the window.
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: KeyedSubtree(
                    key: _headerKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildStageHeader(ride, isDark),
                        _buildTurnBanner(ride),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              // Never taller than ~62% of the screen, so the map (and the
              // header) stay visible on a small phone; the sheet scrolls.
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: media.size.height * 0.62,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!_follow && !ride.stage.isFinished)
                    Padding(
                      padding: EdgeInsets.only(right: 14.w, bottom: 10.h),
                      child: FloatingActionButton.small(
                        heroTag: 'ride-recenter',
                        backgroundColor: isDark ? const Color(0xFF181C25) : Colors.white,
                        foregroundColor: _rideBlue,
                        onPressed: () {
                          setState(() => _follow = true);
                          _followCamera(ride, force: true);
                        },
                        child: const Icon(Icons.my_location_rounded),
                      ),
                    ),
                  Flexible(
                    child: KeyedSubtree(
                      key: _sheetKey,
                      child: ride.stage.isFinished
                          ? _buildFinishedSheet(ride, isDark)
                          : _buildActionSheet(ride, isDark),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRide(bool isDark) {
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF10131A) : Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 64.sp, color: _rideGreen),
            SizedBox(height: 12.h),
            Text(
              'No ride in progress',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16.sp,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            SizedBox(height: 16.h),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back to home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(TaxiRide ride) {
    final target = _targetOf(ride);
    final driver = _driverPosition;
    final initial = driver != null
        ? LatLng(driver.latitude, driver.longitude)
        : (target ?? ride.pickup ?? ride.drop);
    if (initial == null) {
      return Container(color: const Color(0xFFEFF1F5));
    }

    // The leg changes at pickup; drop a stale route rather than drawing the way
    // to somewhere the driver has already been.
    final points = _routeLegKey == _legKeyOf(ride) ? _routePoints : const <LatLng>[];
    final media = MediaQuery.of(context);
    final bikeIcon = _bikeIcon;

    return Listener(
      // Any touch on the map means the driver wants to look around: stop
      // dragging the camera back until they tap recenter.
      onPointerDown: (_) {
        if (_follow) setState(() => _follow = false);
      },
      // Only the map rebuilds as the bike glides between fixes; the header,
      // action sheet and the rest of the screen are untouched.
      child: ValueListenableBuilder<DriverMarkerPose?>(
        valueListenable: _markerAnimator.pose,
        builder: (context, pose, _) => GoogleMap(
        initialCameraPosition: CameraPosition(target: initial, zoom: 15),
        style: MapStyles.mutedGrey,
        // The driver is the bike marker below, not the native blue dot (which
        // showed as a bare point). The dot stays only until the icon is built.
        myLocationEnabled: _bikeIcon == null,
        myLocationButtonEnabled: false,
        zoomControlsEnabled: false,
        compassEnabled: false,
        mapToolbarEnabled: false,
        padding: EdgeInsets.only(
          top: _headerHeight + media.padding.top,
          bottom: _sheetHeight,
        ),
        markers: {
          if (pose != null && bikeIcon != null)
            Marker(
              markerId: const MarkerId('driver'),
              position: pose.position,
              icon: bikeIcon,
              anchor: const Offset(0.5, 0.5),
              // Top-down bike: point it the way the driver is heading
              // (interpolated the short way round by DriverMarkerAnimator).
              rotation: pose.rotation,
              flat: true,
              zIndexInt: 2,
              infoWindow: const InfoWindow(title: 'You'),
            ),
          if (ride.pickup != null && !ride.stage.isOnBoard)
            Marker(
              markerId: const MarkerId('pickup'),
              position: ride.pickup!,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(
                title: ride.isParcel ? 'Pickup (sender)' : 'Pickup',
                snippet: ride.pickupAddress,
              ),
            ),
          if (ride.drop != null)
            Marker(
              markerId: const MarkerId('drop'),
              position: ride.drop!,
              alpha: ride.stage.isOnBoard ? 1 : 0.6,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: InfoWindow(
                title: ride.isParcel ? 'Drop (receiver)' : 'Drop',
                snippet: ride.dropAddress,
              ),
            ),
        },
        polylines: {
          if (points.length >= 2)
            Polyline(
              polylineId: const PolylineId('leg'),
              points: points,
              color: _rideBlue,
              width: 6,
              startCap: Cap.roundCap,
              endCap: Cap.roundCap,
              jointType: JointType.round,
              patterns: _routeApproximate
                  ? [PatternItem.dash(24), PatternItem.gap(14)]
                  : const <PatternItem>[],
            ),
        },
        onMapCreated: (controller) {
          _mapController = controller;
          if (points.isNotEmpty) {
            _fitRoute();
          } else {
            _refreshRoute();
          }
        },
        ),
      ),
    );
  }

  /// Green next-turn banner under the stage header. Only for a real road route
  /// (not the dashed straight-line fallback) while the trip is running.
  Widget _buildTurnBanner(TaxiRide ride) {
    if (ride.stage.isFinished || _routeApproximate || _routePoints.length < 3) {
      return const SizedBox.shrink();
    }
    final turn = RouteTracker.turnAlong(_routePoints);
    if (turn == null) return const SizedBox.shrink();

    // Road name, looked up once per new turn point.
    if (turn.kind != TurnKind.arrive && !_samePlace(_turnRoadFor, turn.at)) {
      _turnRoadFor = turn.at;
      _turnRoad = null;
      _roads.nameAt(turn.at).then((name) {
        if (mounted && _samePlace(_turnRoadFor, turn.at)) setState(() => _turnRoad = name);
      });
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 8.h),
      child: TripNavBanner(
        turn: turn,
        roadName: _turnRoad,
        destinationLabel: ride.stage.isOnBoard ? 'Drop point' : 'Pickup point',
      ),
    );
  }

  bool _samePlace(LatLng? a, LatLng b) =>
      a != null && (a.latitude - b.latitude).abs() < 0.00005 && (a.longitude - b.longitude).abs() < 0.00005;

  Widget _buildStageHeader(TaxiRide ride, bool isDark) {
    final eta = _etaMins;
    final km = _distanceKm;
    final finished = ride.stage.isFinished;
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 10.w, 14.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF181C25) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  ride.stage.headlineFor(isParcel: ride.isParcel),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 17.sp,
                    color: isDark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                ),
              ),
              if (!finished && eta != null)
                Padding(
                  padding: EdgeInsets.only(right: 4.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        km != null
                            ? '${eta.round()} min · ${km.toStringAsFixed(km < 10 ? 1 : 0)} km'
                            : '${eta.round()} min',
                        style: TextStyle(
                          color: _rideBlue,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.sp,
                        ),
                      ),
                      Text(
                        'Arrive ${formatClock(DateTime.now().add(Duration(seconds: (eta * 60).round())))}',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontWeight: FontWeight.w600,
                          fontSize: 11.sp,
                        ),
                      ),
                    ],
                  ),
                ),
              if (!finished) ...[
                SizedBox(width: 4.w),
                SosButton(
                  size: 34.r,
                  request: () => SosRequest(
                    rideId: ride.id,
                    serviceType: ride.isParcel ? 'parcel' : 'ride',
                    pickupAddress: ride.pickupAddress,
                    dropAddress: ride.dropAddress,
                  ),
                ),
                GestureDetector(
                  onTap: _busy ? null : () => _confirmCancel(ride),
                  child: Padding(
                    padding: EdgeInsets.all(8.r),
                    child: Icon(
                      Icons.close_rounded,
                      size: 20.sp,
                      color: ride.stage.driverCanCancel
                          ? _rideRed
                          : (isDark ? Colors.white24 : Colors.grey[350]),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: 6.h),
          // Parcel or passenger — the same trip flow serves both, so say which.
          Row(
            children: [
              Icon(RideJobKind.iconOf(ride), size: 14.sp, color: _rideBlue),
              SizedBox(width: 5.w),
              Flexible(
                child: Text(
                  RideJobKind.labelOf(ride),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _rideBlue,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.sp,
                  ),
                ),
              ),
            ],
          ),
          if (!finished) ...[
            SizedBox(height: 10.h),
            RideStageTimeline(stage: ride.stage),
          ],
        ],
      ),
    );
  }

  Widget _buildActionSheet(TaxiRide ride, bool isDark) {
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[600];
    final target = _targetOf(ride);
    final address =
        ride.stage.isOnBoard ? ride.dropAddress : ride.pickupAddress;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        // Scrolls instead of overflowing on a short/landscape screen or at
        // large text; sized to its content otherwise.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kept on the active job too, not just the offer: a driver who
              // accepted an hour ago, or reopened the app mid-trip, still needs
              // to know whose car they are driving.
              DriveUJobBanner(ride: ride, compact: true),
              _buildContactRow(ride, textColor, subText),
              SizedBox(height: 16.h),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    ride.stage.isOnBoard
                        ? Icons.flag_rounded
                        : Icons.my_location_rounded,
                    size: 18.sp,
                    color: ride.stage.isOnBoard ? _rideRed : _rideGreen,
                  ),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      address.isEmpty ? 'Location unavailable' : address,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 14.sp,
                      ),
                    ),
                  ),
                  if (target != null)
                    GestureDetector(
                      onTap: () => _navigate(target),
                      child: Container(
                        margin: EdgeInsets.only(left: 6.w),
                        padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        decoration: BoxDecoration(
                          color: _rideBlue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(18.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.navigation_rounded, color: _rideBlue, size: 18.sp),
                            SizedBox(width: 4.w),
                            Text(
                              'Navigate',
                              style: TextStyle(
                                color: _rideBlue,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.sp,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (ride.isParcel && (ride.parcelCategory.isNotEmpty || ride.parcelWeight.isNotEmpty)) ...[
                SizedBox(height: 8.h),
                Text(
                  [ride.parcelCategory, ride.parcelWeight]
                      .where((s) => s.isNotEmpty)
                      .join(' · '),
                  style: TextStyle(color: subText, fontSize: 12.sp),
                ),
              ],
              if (ride.stage == RideStage.arriving) ...[
                SizedBox(height: 14.h),
                _WaitingPanel(ride: ride, isDark: isDark),
              ] else if (ride.stage.isOnBoard && ride.waitingChargeAmount > 0) ...[
                SizedBox(height: 10.h),
                Text(
                  'Waiting charge ₹${ride.waitingChargeAmount.toStringAsFixed(0)} added to the fare',
                  style: TextStyle(
                    color: _rideAmber,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.sp,
                  ),
                ),
              ],
              // Warns before the button is tapped, so the driver asks for the
              // code while the passenger is getting in rather than after.
              if (ride.stage.nextNeedsOtp) ...[
                SizedBox(height: 14.h),
                _buildOtpHint(ride, isDark),
              ],
              if (parcelProofStageOf(ride) != null) ...[
                SizedBox(height: 14.h),
                ParcelProofCard(ride: ride),
              ],
              SizedBox(height: 18.h),
              SizedBox(
                height: 54.h,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : () => _advance(ride),
                  style: ElevatedButton.styleFrom(
                    // Green only on the step that ends the trip, so the final,
                    // irreversible tap does not look like the three before it.
                    backgroundColor:
                        ride.stage.nextSettlesFare ? _rideGreen : _rideBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27.r),
                    ),
                  ),
                  child: _busy
                      ? SizedBox(
                          width: 22.w,
                          height: 22.w,
                          child: const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      // Shrink-to-fit rather than ellipsise: the labels are
                      // long, and uppercase with letter-spacing makes them
                      // longer still. Truncating the one button that drives
                      // the trip forward would be worse than a slightly
                      // smaller label on a narrow phone.
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            ride.stage
                                .actionLabelFor(isParcel: ride.isParcel)
                                .toUpperCase(),
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15.sp,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shown for a few seconds after the trip ends (or the passenger cancels),
  /// so the driver sees what happened instead of the screen vanishing.
  Widget _buildFinishedSheet(TaxiRide ride, bool isDark) {
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[600];
    final completed = ride.stage == RideStage.completed;
    final earnings = ride.driverEarnings;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 16.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                completed ? Icons.check_circle_rounded : Icons.cancel_rounded,
                color: completed ? _rideGreen : _rideRed,
                size: 52.sp,
              ),
              SizedBox(height: 10.h),
              Text(
                ride.stage.headlineFor(isParcel: ride.isParcel),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 18.sp,
                ),
              ),
              if (!completed) ...[
                SizedBox(height: 6.h),
                Text(
                  'It was cancelled by the ${ride.isParcel ? 'customer' : 'passenger'} '
                  'or by support. You can take new jobs now.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subText, fontSize: 13.sp, height: 1.4),
                ),
              ],
              if (completed) ...[
                SizedBox(height: 10.h),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '₹${ride.fare.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 34.sp,
                    ),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  ride.isCash ? 'Collected in cash' : 'Paid online',
                  style: TextStyle(color: subText, fontSize: 13.sp),
                ),
                if (earnings != null && earnings > 0) ...[
                  SizedBox(height: 6.h),
                  Text(
                    'Your earnings ₹${earnings.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: _rideGreen,
                      fontWeight: FontWeight.w800,
                      fontSize: 14.sp,
                    ),
                  ),
                ],
              ],
              SizedBox(height: 18.h),
              SizedBox(
                height: 50.h,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      ref.read(activeRideControllerProvider.notifier).dismissFinished(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rideBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25.r),
                    ),
                  ),
                  child: Text(
                    'DONE',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15.sp,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContactRow(TaxiRide ride, Color textColor, Color? subText) {
    final phone = ride.contactPhone;
    final unread = ride.messages
        .skip(_seenMessages ?? ride.messages.length)
        .any((m) => !m.isMine);
    final role = ride.isParcel
        ? (ride.stage.isOnBoard ? 'Receiver' : 'Sender')
        : null;
    return Row(
      children: [
        CircleAvatar(
          radius: 22.r,
          backgroundColor: _rideBlue.withValues(alpha: 0.12),
          child: Icon(
            ride.isParcel ? Icons.inventory_2_rounded : Icons.person_rounded,
            color: _rideBlue,
            size: 24.sp,
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role == null ? ride.contactName : '$role · ${ride.contactName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15.sp,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                '₹${ride.fare.toStringAsFixed(0)} · '
                '${ride.isCash ? 'Cash' : 'Online'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: subText, fontSize: 12.sp),
              ),
            ],
          ),
        ),
        _roundButton(
          icon: Icons.chat_bubble_rounded,
          color: _rideBlue,
          badge: unread,
          onTap: () => _openChat(ride),
        ),
        if (phone.isNotEmpty) ...[
          SizedBox(width: 10.w),
          _roundButton(
            icon: Icons.call_rounded,
            color: _rideGreen,
            onTap: () => _call(phone),
          ),
        ],
      ],
    );
  }

  Widget _roundButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool badge = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: EdgeInsets.all(9.r),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 18.sp),
          ),
          if (badge)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 11.r,
                height: 11.r,
                decoration: BoxDecoration(
                  color: _rideRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOtpHint(TaxiRide ride, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: _rideBlue.withValues(alpha: isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(Icons.pin_rounded, color: _rideBlue, size: 20.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              ride.isParcel
                  ? 'Ask the customer for the 4-digit pickup code'
                  : 'Ask the passenger for their start code',
              style: TextStyle(
                color: _rideBlue,
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Waiting at the pickup: the clock the passenger is billed on.
///
/// Mirrors the server's `computeRideWaitingCharge`: from `arrivedAt` (stamped
/// once the driver is within 500 m), the first `free_waiting_before` minutes
/// are free and each started minute after costs `waiting_charge`. Ticks on its
/// own so the map is not rebuilt every second.
class _WaitingPanel extends StatefulWidget {
  const _WaitingPanel({required this.ride, required this.isDark});

  final TaxiRide ride;
  final bool isDark;

  @override
  State<_WaitingPanel> createState() => _WaitingPanelState();
}

class _WaitingPanelState extends State<_WaitingPanel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.ride.arrivedAt != null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ride = widget.ride;
    final rate = ride.waitingChargePerMinute;
    final free = ride.freeWaitingMinutes;
    final arrivedAt = ride.arrivedAt;
    final subText = widget.isDark ? Colors.grey[400] : Colors.grey[700];

    if (arrivedAt == null) {
      if (rate <= 0) return const SizedBox.shrink();
      return Text(
        'Waiting charges (₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}/min after '
        '${free.toStringAsFixed(0)} free min) start once you are within 500 m of the pickup.',
        style: TextStyle(color: subText, fontSize: 12.sp, height: 1.35),
      );
    }

    final elapsed = DateTime.now().difference(arrivedAt);
    final seconds = math.max(0, elapsed.inSeconds);
    final minutesStarted = (seconds / 60).ceil();
    final chargeable = math.max(0, minutesStarted - free.ceil());
    final charge = chargeable * rate;
    final paid = rate > 0 && chargeable > 0;
    final clock =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final color = paid ? _rideRed : _rideAmber;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isDark ? 0.18 : 0.08),
        borderRadius: BorderRadius.circular(14.r),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: color, size: 20.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paid ? 'Paid waiting · $clock' : 'Waiting · $clock',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.sp,
                  ),
                ),
                if (rate > 0)
                  Text(
                    '${free.toStringAsFixed(0)} min free, then '
                    '₹${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}/min',
                    style: TextStyle(color: subText, fontSize: 11.sp),
                  ),
              ],
            ),
          ),
          if (paid)
            Text(
              '+₹${charge.toStringAsFixed(0)}',
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 16.sp,
              ),
            ),
        ],
      ),
    );
  }
}

