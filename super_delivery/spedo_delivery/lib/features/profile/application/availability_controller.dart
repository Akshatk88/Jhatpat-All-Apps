import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/error/result.dart';
import '../../../core/services/device_readiness_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/rider_online_service.dart';
import '../../../core/services/socket_service.dart';
import '../../auth/application/auth_state.dart';
import '../../auth/application/auth_controller.dart';
import '../../orders/application/orders_controller.dart';
import '../../orders/application/orders_state.dart';
import '../../work_mode/application/work_mode_controller.dart';
import '../../work_mode/data/driver_availability_repository.dart';
import '../../work_mode/data/work_mode.dart';
import '../../work_mode/data/work_mode_repository.dart';
import '../data/profile_repository.dart';

/// [AvailabilityController.goOnline] refused because a device setting that
/// decides whether offers reach the rider is missing (see
/// DeviceReadinessService). Not a failure to show as text: the caller opens the
/// setup screen.
class SetupRequiredError extends AppError {
  SetupRequiredError() : super('Finish phone setup to receive orders');
}

/// The rider's ONLINE switch, applied to exactly one dispatcher.
///
/// The app has three modules over two server dispatchers (see [WorkMode]):
///
/// | module | food availability (`/food/delivery/availability`) | taxi `Driver.isOnline` (`/taxi/drivers/online`) |
/// |--------|--------------------------|-------------------------|
/// | Food   | online                   | offline                 |
/// | Parcel | offline                  | online                  |
/// | Rider  | offline                  | online                  |
///
/// Being online on the *other* dispatcher is what let food orders keep
/// arriving in Rider mode (and rides in Food): the server's own `workMode`
/// filter only runs when `UNIFIED_DISPATCH_ENABLED` is set, and a dispatch
/// round started before a switch still finishes. Standing down from the other
/// dispatcher stops those offers at the source; the app- and native-side
/// module filters catch whatever is already in flight.
///
/// [state] is "the rider is working", whichever dispatcher that is. Because
/// Parcel and Rider keep food availability offline, a restart cannot read the
/// online state from the food profile alone — it also reads `Driver.isOnline`
/// ([WorkModeStatus.taxiOnline]).
class AvailabilityController extends Notifier<bool> {
  late final ProfileRepository _repository;
  StreamSubscription<Position>? _positionSub;
  Timer? _keepAliveTimer;
  DateTime _lastPing = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  bool build() {
    _repository = ref.read(profileRepositoryProvider);
    final authState = ref.read(authControllerProvider);
    final startedOnline = authState is AuthAuthenticated && authState.user.isOnline;

    ref.onDispose(() {
      _positionSub?.cancel();
      _keepAliveTimer?.cancel();
      // Covers logout, which tears this controller down without going through
      // goOffline — otherwise the service and its notification outlive the
      // session, claiming a signed-out rider is online.
      unawaited(RiderOnlineService.stop());
    });

    if (authState is AuthAuthenticated) {
      Future.microtask(() => _resume(foodOnline: startedOnline));
    }
    return startedOnline;
  }

  /// Picks the shift back up after a cold start.
  ///
  /// Waits for the module first: tracking pings write the food availability,
  /// and doing that while the module is still loading (it reads as Food until
  /// then) would put a Parcel/Rider rider back on the food dispatcher.
  Future<void> _resume({required bool foodOnline}) async {
    final status = await _modeStatus();
    if (!ref.mounted) return;
    final WorkModeSet mode = status?.mode ?? ref.read(currentWorkModeProvider);

    final taxiOnline = status?.taxiOnline ?? false;
    final online = foodOnline || (mode.acceptsRides && taxiOnline);
    if (!online) {
      // Offline in Food but still `isOnline` on the taxi side (a shift that
      // ended without reaching the server): stand down, or the ride
      // dispatcher keeps offering jobs to a rider who is not working.
      if (taxiOnline) {
        unawaited(ref.read(driverAvailabilityRepositoryProvider).goOffline());
      }
      return;
    }

    if (!state) state = true;
    _startTracking();
    ref.read(ordersControllerProvider.notifier).startPolling();

    // A Food rider left online on the taxi side (or a Rider left online for
    // food) is brought back to one dispatcher. Food mode only touches the taxi
    // document when it is actually online there.
    if (!mode.acceptsRides && !taxiOnline) {
      return;
    }
    await syncDispatchers();
  }

  Future<WorkModeStatus?> _modeStatus() async {
    try {
      return await ref.read(workModeControllerProvider.future);
    } catch (_) {
      return null;
    }
  }

  Future<Result<void, AppError>> toggle({bool skipSetupCheck = false}) async {
    if (state) {
      return goOffline();
    }
    return goOnline(skipSetupCheck: skipSetupCheck);
  }

  /// [skipSetupCheck]: the rider has just been through the setup screen and
  /// chose to continue, so it is not shown again for the same attempt.
  Future<Result<void, AppError>> goOnline({bool skipSetupCheck = false}) async {
    // Going online with the phone set up to drop offers is the failure the
    // rider cannot see. The UI reacts to this error by opening the setup
    // screen and calling again with [skipSetupCheck].
    if (!skipSetupCheck && await DeviceReadinessService.hasBlockingIssues()) {
      return Result.failure(SetupRequiredError());
    }

    final locationService = ref.read(locationServiceProvider);
    final hasPermission = await locationService.ensurePermissions();
    if (!hasPermission) {
      return Result.failure(
        NetworkError('Location permission is required to go online'),
      );
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition();
      locationService.lastPosition = position;
    } catch (_) {
      // fall through — the availability ping will pick up the next fix
    }

    final WorkModeSet mode =
        (await _modeStatus())?.mode ?? ref.read(currentWorkModeProvider);
    taxiOnlineError = null;

    // Each module that is on puts the rider on its dispatcher; one that is
    // off takes them off it. Online when at least one dispatcher took them.
    String? foodError;
    var foodOk = false;
    if (mode.acceptsFood) {
      final food = await _repository.updateAvailability(
        true,
        lat: position?.latitude,
        lng: position?.longitude,
      );
      food.when(
        success: (_) => foodOk = true,
        failure: (e) => foodError = e.message,
      );
    }

    var ridesOk = false;
    if (mode.acceptsRides) {
      position ??= await _resolvePosition();
      if (position == null) {
        taxiOnlineError =
            'Waiting for GPS — ride and parcel requests need your location';
      } else {
        final rides =
            await ref.read(driverAvailabilityRepositoryProvider).goOnline(
                  lat: position.latitude,
                  lng: position.longitude,
                );
        rides.when(
          success: (_) => ridesOk = true,
          failure: (e) => taxiOnlineError = e.message,
        );
      }
    }

    if (!foodOk && !ridesOk) {
      return Result.failure(
        NetworkError(foodError ?? taxiOnlineError ?? 'Could not go online'),
      );
    }

    _markOnline();
    final pos = position;
    if (ridesOk && pos != null) _pushTaxiLocation(pos);
    if (!mode.acceptsRides) {
      // Food only: make sure the ride dispatcher is not still offering rides
      // from an earlier Parcel/Rider shift.
      unawaited(ref.read(driverAvailabilityRepositoryProvider).goOffline());
    }
    if (!mode.acceptsFood) {
      // Off the food dispatcher (location still uploaded, harmlessly).
      unawaited(_repository.updateAvailability(
        false,
        lat: pos?.latitude,
        lng: pos?.longitude,
      ));
    }
    return const Result.success(null);
  }

  void _markOnline() {
    state = true;
    ref.read(ordersControllerProvider.notifier).startPolling();
    _startTracking();
  }

  /// Why the taxi half of going online failed, or null.
  ///
  /// Set by [syncDispatchers] when switching into Parcel/Rider while already
  /// online; [goOnline] reports its own failure directly.
  String? taxiOnlineError;

  /// Puts the rider on the dispatcher of the current module and takes them off
  /// the other one. Called after every module switch.
  ///
  /// Also re-uploads the location with the switch: food dispatch skips riders
  /// whose `lastLocationAt` is older than 45 minutes, and taxi `goOnline`
  /// stores the position and replays any still-searching job
  /// (`notifyLateAvailableDriver`) — so the first request of the new module
  /// can arrive straight away instead of after the next ping.
  ///
  /// Returns why the new module's dispatcher refused the rider, or null.
  Future<String?> syncDispatchers() async {
    if (!state) return null;
    final mode = ref.read(currentWorkModeProvider);
    final pos = await _resolvePosition();
    if (!ref.mounted || !state) return null;

    // Food dispatcher: on when Food is on, off otherwise (location is
    // uploaded either way so a later switch-on is dispatchable at once).
    taxiOnlineError = null;
    final food = await _repository.updateAvailability(
      mode.acceptsFood,
      lat: pos?.latitude,
      lng: pos?.longitude,
    );
    final foodError = mode.acceptsFood
        ? food.when(success: (_) => null, failure: (e) => e.message)
        : null;

    // Ride dispatcher: on when Parcel or Rider is on, off otherwise, or rides
    // and parcels keep arriving for modules the rider just turned off.
    if (mode.acceptsRides) {
      await _goOnlineForRides(pos);
      if (pos != null) _pushTaxiLocation(pos);
    } else {
      await ref.read(driverAvailabilityRepositoryProvider).goOffline();
    }
    return foodError ?? taxiOnlineError;
  }

  /// Mirrors the online state onto the unified taxi driver document.
  ///
  /// Taxi dispatch matches on `Driver.isOnline` and `acceptRideAssignment`
  /// re-checks it, so without this every ride would pass the rider by and any
  /// offer that did arrive could not be accepted.
  Future<void> _goOnlineForRides(Position? position) async {
    taxiOnlineError = null;
    if (!ref.read(currentWorkModeProvider).acceptsRides) return;

    final pos = position ?? ref.read(locationServiceProvider).lastPosition;
    if (pos == null) {
      taxiOnlineError = 'Waiting for GPS before ride requests can start';
      return;
    }

    final result = await ref.read(driverAvailabilityRepositoryProvider).goOnline(
          lat: pos.latitude,
          lng: pos.longitude,
        );
    result.when(
      success: (_) => taxiOnlineError = null,
      failure: (error) => taxiOnlineError = error.message,
    );
  }

  /// Best available fix without waiting on movement: the tracked position,
  /// else the last known one, else a fresh read. Null when there is none.
  Future<Position?> _resolvePosition() async {
    final service = ref.read(locationServiceProvider);
    try {
      final pos = service.lastPosition ??
          await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition()
              .timeout(const Duration(seconds: 10));
      service.lastPosition = pos;
      return pos;
    } catch (_) {
      return service.lastPosition;
    }
  }

  Future<Result<void, AppError>> goOffline() async {
    final result = await _repository.updateAvailability(false);
    _stopTracking();
    ref.read(ordersControllerProvider.notifier).stopPolling();
    state = false;
    taxiOnlineError = null;
    // Always sent, regardless of work mode: a driver who switches to Food-only
    // and then goes offline would otherwise stay `isOnline` on the taxi side
    // and keep being offered rides they never see.
    unawaited(ref.read(driverAvailabilityRepositoryProvider).goOffline());
    return result.when(
      success: (_) => const Result.success(null),
      failure: (error) => Result.failure(error),
    );
  }

  void _startTracking() {
    // Ask Android to stop freezing us first. Everything below — the position
    // stream and the keep-alive ping — silently stops running once the process
    // is backgrounded without this, which is what let riders go stale and drop
    // out of dispatch while believing they were online.
    unawaited(RiderOnlineService.start());

    final locationService = ref.read(locationServiceProvider);
    locationService.startTracking();
    _positionSub?.cancel();
    _positionSub = locationService.positionStream.listen(_onPosition);

    // The position stream only emits on movement (distanceFilter), so a
    // stationary rider would otherwise never refresh lastLocationAt and
    // silently drop out of dispatch once the backend's GPS staleness
    // window elapses. Ping on a timer too, independent of movement.
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer.periodic(const Duration(minutes: 3), (_) => _pingLocation());
    // Ping immediately as well. build() starts tracking for a rider who was
    // already online without ever taking a fix (unlike goOnline, which calls
    // getCurrentPosition), so without this their first ping is 3 minutes away
    // at best — and never, if they don't move.
    unawaited(_pingLocation());
  }

  /// Refreshes lastLocationAt server-side so dispatch keeps considering this rider.
  ///
  /// Resolving a position here rather than bailing on null is the whole point:
  /// LocationService.lastPosition stays null until the movement-gated stream first
  /// emits, which never happens for a rider who resumed the app already-online and
  /// hasn't moved 15m. Those riders were being dropped from every order offer, so
  /// they never even received the new-order push.
  ///
  /// The food write carries the module's availability, not a blanket "online":
  /// in Parcel/Rider it re-asserts *offline* every few minutes, so nothing
  /// (another device, an old build) can quietly put the rider back on food.
  Future<void> _pingLocation() async {
    final service = ref.read(locationServiceProvider);
    var pos = service.lastPosition ?? await Geolocator.getLastKnownPosition();
    if (pos == null) {
      try {
        pos = await Geolocator.getCurrentPosition();
      } catch (_) {
        return; // No fix available at all — nothing useful to report.
      }
    }
    service.lastPosition = pos;
    _lastPing = DateTime.now();
    await _repository.updateAvailability(
      ref.read(currentWorkModeProvider).acceptsFood,
      lat: pos.latitude,
      lng: pos.longitude,
    );
    _pushTaxiLocation(pos);
  }

  /// Taxi dispatch matches on the unified driver's own `location` field, which
  /// the food availability ping never touches. Without this a driver in Parcel
  /// or Rider mode sits at whatever coordinates they last had — or none at
  /// all — and falls outside every dispatch radius while believing they are
  /// online.
  void _pushTaxiLocation(Position position) {
    if (!ref.read(currentWorkModeProvider).acceptsRides) return;
    ref.read(socketServiceProvider).sendDriverLocation(
          lat: position.latitude,
          lng: position.longitude,
        );
  }

  void _stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    ref.read(locationServiceProvider).stopTracking();

    // The notification must go the moment the rider goes offline. A lingering
    // "You're online" is both a lie and a battery drain, and it is the single
    // fastest way to get uninstalled.
    unawaited(RiderOnlineService.stop());
  }

  void _onPosition(Position position) {
    final now = DateTime.now();
    if (now.difference(_lastPing) < const Duration(seconds: 4)) return;
    _lastPing = now;

    // Moving pings only matter to the dispatcher the rider is on; Parcel/Rider
    // keep food offline via the keep-alive ping instead of every few metres.
    if (ref.read(currentWorkModeProvider).acceptsFood) {
      _repository.updateAvailability(
        true,
        lat: position.latitude,
        lng: position.longitude,
      );
    }
    _pushTaxiLocation(position);

    final ordersState = ref.read(ordersControllerProvider);
    if (ordersState is OrdersLoaded && ordersState.currentOrder != null) {
      ref.read(socketServiceProvider).sendLocationUpdate(
        orderId: ordersState.currentOrder!.id,
        lat: position.latitude,
        lng: position.longitude,
        heading: position.heading,
        speed: position.speed,
        accuracy: position.accuracy,
      );
    }
  }
}

final availabilityControllerProvider =
    NotifierProvider<AvailabilityController, bool>(AvailabilityController.new);
