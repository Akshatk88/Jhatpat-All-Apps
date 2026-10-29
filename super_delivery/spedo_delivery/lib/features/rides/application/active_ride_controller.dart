import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/error/result.dart';
import '../../../core/services/gps_fix_filter.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/socket_service.dart';
import '../data/models/taxi_ride.dart';
import '../data/rides_repository.dart';

/// The one ride this driver is currently on, `null` when free.
///
/// Every stage transition goes through here so the ride can only ever move
/// forward one step at a time — the server rejects out-of-order transitions,
/// and a screen calling `setStage` directly could ask for one.
///
/// A finished ride stays in state for a moment with stage `completed` /
/// `cancelled` so the trip screen can show the outcome (fare, earnings, or
/// "passenger cancelled") instead of vanishing mid-tap; [dismissFinished]
/// clears it, and a timer does so on its own so it never blocks the next offer
/// for long.
class ActiveRideController extends AsyncNotifier<TaxiRide?> {
  StreamSubscription<Map<String, dynamic>>? _stateSub;
  StreamSubscription<bool>? _connectionSub;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  Timer? _finishedTimer;
  Timer? _arrivalPoll;

  /// A status write (or accept) is in flight; socket echoes of it are left to
  /// the HTTP response so they cannot race it.
  bool _busy = false;

  // ── Live ride location feed ───────────────────────────────────────
  DateTime _lastLocationSent = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastSentPosition;
  double? _lastSentHeading;
  Timer? _heartbeat;

  /// Captured when sharing starts so teardown never needs `ref` (which is not
  /// usable inside onDispose).
  LocationService? _sharingLocationService;

  /// No emit closer together than this (unless forced).
  static const _minEmitGap = Duration(seconds: 2);

  /// A position is sent at least this often while a ride is live, moving or
  /// not, so the passenger's map never looks frozen.
  static const _heartbeatEvery = Duration(seconds: 8);

  /// Below this movement (and without a turn) a fix is not worth an emit.
  static const _minMoveMeters = 3.0;
  static const _minTurnDegrees = 15.0;

  /// How long the end-of-trip summary stays up if the driver does not tap Done.
  static const _finishedHold = Duration(seconds: 15);

  RidesRepository get _repository => ref.read(ridesRepositoryProvider);
  SocketService get _socket => ref.read(socketServiceProvider);

  /// The ride, but only while it is still being driven.
  TaxiRide? get _live {
    final ride = state.value;
    if (ride == null || ride.stage.isFinished) return null;
    return ride;
  }

  @override
  Future<TaxiRide?> build() async {
    _stateSub = _socket.onRideState.listen(_onServerState);
    _messageSub = _socket.onRideMessage.listen((data) {
      final rideId = data['rideId']?.toString();
      if (rideId != null && rideId != state.value?.id) return;
      addMessage(RideChatMessage.fromJson(data));
    });

    // Socket.IO rooms are per-connection: a reconnect gets a new socket id and
    // the server drops every room this client had joined. Nothing re-sends
    // ride:join on its own, so without this the driver silently stops
    // receiving ride events — including a passenger cancellation — after any
    // network blip mid-trip.
    //
    // With no ride in hand the connect is also the moment to re-ask the server:
    // the launch-time read fails when the app starts offline or before sign-in,
    // and nothing else would ever restore a trip that is in fact running.
    _connectionSub = _socket.onConnectionChange.listen((connected) {
      if (!connected) return;
      final ride = _live;
      if (ride != null) {
        _socket.joinRide(ride.id);
        // Nothing was sent while the socket was down (see
        // sendRideDriverLocation); put the driver back on the passenger's map
        // straight away instead of after the next movement or heartbeat.
        _pushCurrentRideLocation();
      } else if (state.value == null && !_busy) {
        unawaited(_restore());
      }
    });

    ref.onDispose(() {
      _stateSub?.cancel();
      _messageSub?.cancel();
      _connectionSub?.cancel();
      _positionSub?.cancel();
      _heartbeat?.cancel();
      _sharingLocationService?.setRideMode(false);
      _finishedTimer?.cancel();
      _arrivalPoll?.cancel();
    });

    // Recovery path: a killed app misses every socket event, so the active
    // ride is always re-read rather than assumed absent.
    final result = await _repository.getActiveRide();
    final ride = result.when(success: (r) => r, failure: (_) => null);
    if (ride != null) {
      _socket.joinRide(ride.id);
      _startLocationSharing();
      _syncArrivalPoll(ride);
    }
    return ride;
  }

  Future<void> _restore() async {
    final result = await _repository.getActiveRide();
    final ride = result.when(success: (r) => r, failure: (_) => null);
    if (ride == null || state.value != null || _busy) return;
    state = AsyncData(ride);
    _socket.joinRide(ride.id);
    _startLocationSharing();
    _syncArrivalPoll(ride);
  }

  /// Server-pushed movement on the current ride: a full document from
  /// `ride:state` (sent on `ride:join` and after every transition), or a
  /// status-only `ride:status:updated` / `rideCancelled`.
  void _onServerState(Map<String, dynamic> data) {
    final ride = _live;
    if (ride == null) return;
    final rideId = (data['rideId'] ?? data['_id'] ?? data['id'])?.toString();
    if (rideId != null && rideId.isNotEmpty && rideId != ride.id) return;

    final stage = RideStage.parse(
      (data['liveStatus'] ?? data['status'])?.toString(),
    );
    if (stage == RideStage.searching) return; // no usable status in the payload

    if (stage == RideStage.cancelled) {
      // The passenger (or support) cancelled. Shown, not silently dropped.
      _endWith(ride.copyWith(stage: RideStage.cancelled));
      return;
    }

    // Our own transition echoing back: the HTTP response is authoritative.
    if (_busy) return;

    if (stage == RideStage.completed) {
      _endWith(ride.copyWith(stage: RideStage.completed));
      return;
    }

    if (TaxiRide.isFullDocument(data)) {
      // Full ride document: take it whole. This is what fills in what the
      // offer did not carry (waiting-charge pricing, parcel contacts, chat
      // history) and what corrects a stage the app had wrong.
      final full = TaxiRide.fromJson(data);
      if (full.id.isNotEmpty) {
        state = AsyncData(_withMergedMessages(full));
        _syncArrivalPoll(full);
        return;
      }
    }

    if (stage != ride.stage) {
      final updated = ride.copyWith(stage: stage);
      state = AsyncData(updated);
      _syncArrivalPoll(updated);
    }
  }

  /// Claims an offered ride.
  ///
  /// Acceptance is socket-only on the backend and deliberately racy: several
  /// drivers are offered the same ride and the first transaction wins. There is
  /// no per-call ack, so success arrives as `rideAccepted` and loss as
  /// `errorMessage`, and this waits on whichever lands first.
  Future<Result<TaxiRide, AppError>> acceptRide(TaxiRide offer) async {
    _busy = true;
    try {
      return await _accept(offer);
    } finally {
      _busy = false;
    }
  }

  Future<Result<TaxiRide, AppError>> _accept(TaxiRide offer) async {
    // A finished trip's summary must not block the next job.
    if (state.value?.stage.isFinished ?? false) _clear();

    final accepted = _socket.onRideAccepted
        .firstWhere((data) => _idOf(data) == offer.id || _idOf(data).isEmpty)
        .then<Object?>((data) => data);
    final failed = _socket.onSocketError.first.then<Object?>((data) => data);

    _socket.acceptRide(offer.id);

    Object? outcome;
    try {
      outcome = await Future.any([accepted, failed]).timeout(
        const Duration(seconds: 12),
      );
    } catch (_) {
      // Timed out, or the socket went away mid-claim. Silence is not failure —
      // the claim may well have landed — so fall back to the authoritative
      // read rather than guessing in either direction.
      await refresh();
      final ride = _live;
      if (ride == null) {
        return Result.failure(
          NetworkError('No response from the server. Check your connection.'),
        );
      }
      _afterClaim(ride);
      return Result.success(ride);
    }

    final data = outcome is Map<String, dynamic> ? outcome : const {};
    if (data.containsKey('message') && !data.containsKey('liveStatus')) {
      return Result.failure(
        UnknownError(data['message']?.toString() ?? 'Ride is no longer available'),
      );
    }

    // `rideAccepted` is an acknowledgement, not the ride document — it carries
    // no passenger, addresses or fare. Keep the offer's details and take only
    // the confirmed stage from the server; the full document follows on
    // `ride:join` (and the fetch below).
    final ride = offer.copyWith(
      stage: RideStage.parse(
        (data['liveStatus'] ?? data['status'])?.toString(),
      ),
    );
    final confirmed =
        ride.stage == RideStage.searching ? offer.copyWith(stage: RideStage.accepted) : ride;
    state = AsyncData(confirmed);
    _afterClaim(confirmed);
    unawaited(_hydrate(confirmed.id));
    return Result.success(confirmed);
  }

  /// Replaces the offer-shaped ride with the full document (pricing snapshot,
  /// parcel contacts, chat). Best effort — the trip works without it.
  Future<void> _hydrate(String rideId) async {
    final result = await _repository.getRide(rideId);
    result.when(
      success: (full) {
        final current = _live;
        if (current == null || current.id != full.id || _busy) return;
        if (!full.stage.isActive) return;
        state = AsyncData(_withMergedMessages(full));
        _syncArrivalPoll(full);
      },
      failure: (_) {},
    );
  }

  void _afterClaim(TaxiRide ride) {
    _socket.joinRide(ride.id);
    _startLocationSharing();
    _syncArrivalPoll(ride);
  }

  static String _idOf(Map<String, dynamic> data) =>
      (data['rideId'] ?? data['_id'] ?? data['id'] ?? '').toString();

  /// Moves the ride to the next stage in the lifecycle.
  ///
  /// Deliberately takes no target: the sequence is fixed
  /// (accepted → arriving → started → arrived → completed) and letting callers
  /// name a stage is how a screen ends up skipping the pickup.
  /// [collectedByDriver] records that the driver physically took the money, for
  /// the cash-in-hand ledger. It is intentionally not sent to the server: the
  /// backend derives cash owed from `paymentMethod` on completion, and the only
  /// ride field named for a payment collection is the Razorpay link object,
  /// which a boolean cannot be cast into. The server also ignores any fare the
  /// app sends; it is passed only for logging parity with the web app.
  Future<Result<TaxiRide, AppError>> advance({
    String? otp,
    String? paymentMethod,
    double? fare,
    bool? collectedByDriver,
  }) async {
    final ride = _live;
    if (ride == null) {
      return Result.failure(UnknownError('No ride in progress'));
    }
    final next = ride.stage.next;
    if (next == null) {
      return Result.failure(UnknownError('This ride is already finished'));
    }

    _busy = true;
    final Result<TaxiRide, AppError> result;
    try {
      result = await _repository.setStage(
        ride.id,
        next,
        otp: otp,
        paymentMethod: paymentMethod,
        fare: fare,
      );
    } finally {
      _busy = false;
    }

    return result.when(
      success: (updated) {
        if (updated.stage == RideStage.cancelled) {
          _endWith(updated);
        } else if (updated.stage == RideStage.completed) {
          _endWith(updated);
        } else {
          state = AsyncData(updated);
          _syncArrivalPoll(updated);
          if (updated.stage == RideStage.arriving) _pushArrivalLocation();
        }
        return Result.success(updated);
      },
      failure: (error) {
        // A 409 means the server is on a different stage than this screen
        // (another device, a lost response, an admin action). Re-read so the
        // next tap asks for the right thing instead of failing forever. A bad
        // OTP is the exception: nothing is out of sync, and the sheet retries.
        if (!error.message.toLowerCase().contains('otp')) {
          unawaited(refresh());
        }
        return Result.failure(error);
      },
    );
  }

  /// Releases the ride back to dispatch. The backend allows this only while
  /// the driver is still heading to the pickup (`accepted`), and may charge
  /// the admin-configured driver cancellation fee.
  Future<Result<void, AppError>> cancel({String? reason}) async {
    final ride = _live;
    if (ride == null) return const Result.success(null);
    if (!ride.stage.driverCanCancel) {
      return Result.failure(
        UnknownError(
          'This ride can no longer be cancelled from the app. '
          'Call the passenger or contact support.',
        ),
      );
    }
    _busy = true;
    final Result<void, AppError> result;
    try {
      result = await _repository.cancel(ride.id, reason: reason);
    } finally {
      _busy = false;
    }
    return result.when(
      success: (_) {
        _clear();
        return const Result.success(null);
      },
      failure: (error) {
        unawaited(refresh());
        return Result.failure(error);
      },
    );
  }

  Future<void> refresh() async {
    final result = await _repository.getActiveRide();
    result.when(
      success: (ride) {
        // Keep an on-screen summary; the server no longer lists that ride.
        if (ride == null && (state.value?.stage.isFinished ?? false)) return;
        final previousLiveId = _live?.id;
        state = AsyncData(ride);
        if (ride == null) {
          _stopLocationSharing();
        } else {
          // A ride this controller had not been driving (restored by a
          // re-read): join its room and start the feed, which nothing else
          // would do on this path.
          if (!ride.stage.isFinished) {
            if (previousLiveId != ride.id) _socket.joinRide(ride.id);
            if (_positionSub == null) _startLocationSharing();
          }
          _syncArrivalPoll(ride);
        }
      },
      failure: (_) {},
    );
  }

  /// Re-reads just this ride (used by the trip screen to pick up a server-side
  /// `arrivedAt`, fare change or new chat messages).
  Future<void> reload() async {
    final ride = _live;
    if (ride == null) return;
    final result = await _repository.getRide(ride.id);
    result.when(
      success: (fresh) {
        if (_live?.id != fresh.id || _busy) return;
        if (fresh.stage.isFinished) {
          _endWith(fresh);
        } else if (fresh.stage.isActive) {
          state = AsyncData(_withMergedMessages(fresh));
          _syncArrivalPoll(fresh);
        }
      },
      failure: (_) {},
    );
  }

  /// Adds a chat message to the ride in state (from the socket echo).
  void addMessage(RideChatMessage message) {
    final ride = state.value;
    if (ride == null || message.id.isEmpty) return;
    if (ride.messages.any((m) => m.id == message.id)) return;
    state = AsyncData(ride.copyWith(messages: _merge(ride.messages, [message])));
  }

  /// A fresh ride document carries only the last 30 messages, and a read
  /// issued before a live `ride:message:new` landed would drop that message
  /// (and shrink the count the unread dot is based on). Keep the union.
  TaxiRide _withMergedMessages(TaxiRide fresh) {
    final current = state.value;
    if (current == null || current.id != fresh.id || current.messages.isEmpty) return fresh;
    return fresh.copyWith(messages: _merge(current.messages, fresh.messages));
  }

  static List<RideChatMessage> _merge(
    List<RideChatMessage> current,
    List<RideChatMessage> incoming,
  ) {
    final byId = <String, RideChatMessage>{
      for (final m in current)
        if (m.id.isNotEmpty) m.id: m,
      for (final m in incoming)
        if (m.id.isNotEmpty) m.id: m,
    };
    final all = byId.values.toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    all.sort((a, b) => (a.sentAt ?? epoch).compareTo(b.sentAt ?? epoch));
    return all;
  }

  /// Driver tapped Done on the finished-trip summary.
  void dismissFinished() {
    if (state.value?.stage.isFinished ?? false) _clear();
  }

  void _endWith(TaxiRide finished) {
    _stopLocationSharing();
    _arrivalPoll?.cancel();
    _arrivalPoll = null;
    state = AsyncData(finished);
    _finishedTimer?.cancel();
    _finishedTimer = Timer(_finishedHold, () {
      if (state.value?.id == finished.id && (state.value?.stage.isFinished ?? false)) {
        _clear();
      }
    });
  }

  void _clear() {
    _finishedTimer?.cancel();
    _finishedTimer = null;
    _arrivalPoll?.cancel();
    _arrivalPoll = null;
    _stopLocationSharing();
    state = const AsyncData(null);
  }

  /// While the driver is at the pickup and the server has not stamped
  /// `arrivedAt` yet, re-read the ride every 20 s. `arrivedAt` is set by the
  /// socket `locationUpdate` handler once the driver is within 500 m, and that
  /// path emits nothing, so polling is the only way the waiting clock appears.
  void _syncArrivalPoll(TaxiRide ride) {
    final needed = ride.stage == RideStage.arriving && ride.arrivedAt == null;
    if (!needed) {
      _arrivalPoll?.cancel();
      _arrivalPoll = null;
      return;
    }
    _arrivalPoll ??= Timer.periodic(const Duration(seconds: 20), (_) {
      final live = _live;
      if (live == null || live.stage != RideStage.arriving || live.arrivedAt != null) {
        _arrivalPoll?.cancel();
        _arrivalPoll = null;
        return;
      }
      unawaited(reload());
    });
  }

  /// Right after `arriving` is accepted, push a fresh `locationUpdate`: the
  /// server stamps the waiting clock from the driver's position (≤ 500 m from
  /// the pickup) and a stationary driver's stream would not emit one.
  Future<void> _pushArrivalLocation() async {
    final service = ref.read(locationServiceProvider);
    var pos = service.lastPosition;
    try {
      pos ??= await Geolocator.getLastKnownPosition();
      pos ??= await Geolocator.getCurrentPosition();
    } catch (_) {}
    if (pos == null) return;
    _socket.sendDriverLocation(lat: pos.latitude, lng: pos.longitude);
    _sendRideLocation(pos, force: true);
    // Give the server a moment to stamp arrivedAt, then pick it up.
    unawaited(Future<void>.delayed(const Duration(seconds: 3), reload));
  }

  /// Feeds the passenger's live map for the duration of the ride.
  ///
  /// Separate from the food flow's `update-location`, which is keyed by order
  /// id and would not reach the taxi ride room. Sent as
  /// `ride:driver-location:update { rideId, coordinates: [lng, lat], heading,
  /// speed, accuracy, timestamp }`; the server stores it on the ride and
  /// relays it to the room.
  ///
  /// Fixes arrive already filtered by [LocationService] (bad coordinates, poor
  /// accuracy, out-of-order and impossible jumps are dropped there). Here they
  /// are throttled: at most one emit per [_minEmitGap], only for meaningful
  /// movement or a turn, plus a heartbeat every [_heartbeatEvery] so a driver
  /// standing at a signal is still visibly "live".
  void _startLocationSharing() {
    _positionSub?.cancel();
    final locationService = ref.read(locationServiceProvider);
    _sharingLocationService = locationService;
    // Finer GPS cadence for the duration of the ride (restarts the stream
    // only if it is running with the idle settings).
    locationService.setRideMode(true);
    locationService.startTracking();
    _positionSub = locationService.positionStream.listen(_sendRideLocation);

    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_live == null) {
        _stopLocationSharing();
        return;
      }
      if (DateTime.now().difference(_lastLocationSent) >= _heartbeatEvery) {
        _pushCurrentRideLocation();
      }
    });

    // The stream only emits on movement; send the current fix now so the
    // passenger sees the driver straight away rather than after the first
    // few metres.
    final last = locationService.lastPosition;
    if (last != null) {
      _sendRideLocation(last, force: true);
    } else {
      unawaited(
        Geolocator.getLastKnownPosition().then((p) {
          if (p != null) _sendRideLocation(p, force: true);
        }).catchError((_) {}),
      );
    }
  }

  /// Re-sends the best position on hand (heartbeat, reconnect).
  void _pushCurrentRideLocation() {
    final pos = _sharingLocationService?.lastPosition ?? _lastSentPosition;
    if (pos != null) _sendRideLocation(pos, force: true);
  }

  void _sendRideLocation(Position position, {bool force = false}) {
    final ride = _live;
    if (ride == null) return;
    if (!GpsFixFilter.isValidCoordinate(position.latitude, position.longitude)) {
      return;
    }
    final now = DateTime.now();
    final sinceLast = now.difference(_lastLocationSent);
    final heading = _headingFor(position);

    if (!force) {
      if (sinceLast < _minEmitGap) return;
      final prev = _lastSentPosition;
      final moved = prev == null
          ? double.infinity
          : GpsFixFilter.distanceMeters(
              prev.latitude,
              prev.longitude,
              position.latitude,
              position.longitude,
            );
      final prevHeading = _lastSentHeading;
      final turned = prevHeading != null &&
          heading != null &&
          GpsFixFilter.angleDelta(prevHeading, heading).abs() >= _minTurnDegrees;
      // Not worth an emit; the heartbeat covers a stationary driver.
      if (moved < _minMoveMeters && !turned && sinceLast < _heartbeatEvery) {
        return;
      }
    }

    final speed = position.speed;
    final accuracy = position.accuracy;
    final sent = _socket.sendRideDriverLocation(
      rideId: ride.id,
      lat: position.latitude,
      lng: position.longitude,
      heading: heading,
      speed: speed.isFinite && speed >= 0 ? speed : null,
      accuracy: accuracy.isFinite && accuracy > 0 ? accuracy : null,
      timestamp: position.timestamp.millisecondsSinceEpoch,
    );
    // Socket down: nothing went out. The reconnect handler pushes a fresh fix.
    if (!sent) return;
    _lastLocationSent = now;
    _lastSentPosition = position;
    _lastSentHeading = heading;
  }

  /// Direction of travel for the passenger's marker.
  ///
  /// The device heading is only meaningful while moving (most chipsets report
  /// 0 or noise when stationary), so below walking pace the bearing from the
  /// last sent point is used, and when not moving at all the last heading is
  /// kept — the bike does not snap to north at every red light.
  double? _headingFor(Position p) {
    final h = p.heading;
    if (p.speed.isFinite && p.speed >= 1.0 && h.isFinite && h >= 0) {
      return h % 360;
    }
    final prev = _lastSentPosition;
    if (prev != null) {
      final d = GpsFixFilter.distanceMeters(
        prev.latitude,
        prev.longitude,
        p.latitude,
        p.longitude,
      );
      if (d >= 5) {
        return GpsFixFilter.bearingDegrees(
          prev.latitude,
          prev.longitude,
          p.latitude,
          p.longitude,
        );
      }
    }
    return _lastSentHeading;
  }

  void _stopLocationSharing() {
    // Only the ride feed stops; GPS tracking itself belongs to the online
    // state (availability controller), which still needs it — back on the
    // idle cadence.
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _sharingLocationService?.setRideMode(false);
    _lastSentPosition = null;
    _lastSentHeading = null;
    _lastLocationSent = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

final activeRideControllerProvider =
    AsyncNotifierProvider<ActiveRideController, TaxiRide?>(
  ActiveRideController.new,
);
