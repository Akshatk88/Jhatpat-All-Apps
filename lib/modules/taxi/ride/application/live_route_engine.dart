import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:superapp_user/core/maps/geo_math.dart';
import 'package:superapp_user/core/maps/route_polyline_service.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';

/// Which part of the trip the map is showing a route for.
enum TrackingLeg {
  /// No driver yet, or the ride is over: nothing to route.
  none,

  /// Driver heading to the pickup.
  toPickup,

  /// Driver waiting at the pickup: the marker matters, a route doesn't.
  atPickup,

  /// Trip started: driver (with rider) heading to the drop.
  toDrop;

  static TrackingLeg of(RideModel? ride) {
    if (ride == null || ride.isCompleted || ride.isCancelled) return none;
    // k9: `arriving` = at the pickup, `arrived` = at the drop (see RideModel.stage).
    switch (ride.stage) {
      case RideStage.toPickup:
        return toPickup;
      case RideStage.atPickup:
        return atPickup;
      case RideStage.onTrip:
      case RideStage.atDrop:
        return toDrop;
      case RideStage.searching:
      case RideStage.completed:
      case RideStage.cancelled:
        return none;
    }
  }
}

/// What the map draws for the current leg.
@immutable
class RouteView {
  /// Remaining path, already trimmed to the driver's position.
  final List<LatLng> points;
  final double? remainingMeters;
  final double? etaSeconds;

  /// True when routing was unavailable and [points] is a straight line.
  final bool approximate;
  final int version;

  const RouteView({
    required this.points,
    required this.version,
    this.remainingMeters,
    this.etaSeconds,
    this.approximate = false,
  });

  static const empty = RouteView(points: [], version: 0);
}

/// Owns the route polyline for live tracking.
///
/// Routing policy (OSRM — Google Directions/Routes are disabled for the key):
/// * one request when a leg begins (driver→pickup, then driver→drop);
/// * a re-route only after [_offRouteConfirmations] consecutive fixes farther
///   than an accuracy-aware threshold from the route, and never sooner than
///   [_rerouteCooldown] after the previous request;
/// * while only a straight-line fallback is shown, a retry at most every
///   [_failureRetry].
/// Never per location packet, poll or rebuild.
///
/// Responses carry a request sequence number: one that returns after the
/// leg changed, or after a newer request was issued, is discarded. A failed
/// re-route keeps the route already on screen.
///
/// Between requests the travelled part is trimmed locally by projecting the
/// marker onto the nearest route segment, and remaining distance / ETA come
/// from that local progress.
class LiveRouteEngine {
  LiveRouteEngine({
    Future<RouteResult?> Function({
      required LatLng origin,
      required LatLng destination,
      List<LatLng> waypoints,
      CancelToken? cancelToken,
    })? fetcher,
  }) : _fetcher = fetcher ?? RoutePolylineService.fetchRoute;

  final Future<RouteResult?> Function({
    required LatLng origin,
    required LatLng destination,
    List<LatLng> waypoints,
    CancelToken? cancelToken,
  }) _fetcher;

  static const _rerouteCooldown = Duration(seconds: 25);
  static const _failureRetry = Duration(seconds: 30);
  static const _offRouteConfirmations = 3;
  static const _minOffRouteMeters = 50.0;
  static const _maxOffRouteMeters = 150.0;

  /// Rough city speed for ETA when the router gave no duration (m/s).
  static const _fallbackSpeed = 6.5;

  final ValueNotifier<RouteView> view = ValueNotifier(RouteView.empty);

  TrackingLeg _leg = TrackingLeg.none;
  TrackingLeg get leg => _leg;
  LatLng? _target;
  LatLng? get target => _target;
  List<LatLng> _waypoints = const [];
  LatLng? _legOrigin;

  List<LatLng> _route = const [];

  /// `_suffix[i]` = metres from route point i to the end.
  List<double> _suffix = const [];
  bool _approximate = false;
  double? _routeSpeed;

  /// Route index the driver's latest fix projects onto (forward only).
  int _progressIdx = 0;

  /// Route index the rendered marker last projected onto.
  int _renderIdx = 0;
  int _offRouteCount = 0;

  LatLng? _lastFix;
  LatLng? _lastAnchor;
  DateTime? _lastRequestAt;
  int _requestSeq = 0;
  bool _requestInFlight = false;
  CancelToken? _cancelToken;
  int _version = 0;
  bool _disposed = false;

  bool get _legNeedsRoute =>
      (_leg == TrackingLeg.toPickup || _leg == TrackingLeg.toDrop) && _target != null;

  /// Sets the leg. A no-op unless the leg, its target or its stops changed;
  /// otherwise the old route is dropped and a new one requested.
  void setLeg(
    TrackingLeg leg, {
    LatLng? target,
    List<LatLng> waypoints = const [],
    LatLng? origin,
  }) {
    if (_disposed) return;
    if (leg == _leg && target == _target && listEquals(waypoints, _waypoints)) return;

    _leg = leg;
    _target = target;
    _waypoints = List.unmodifiable(waypoints);
    _legOrigin = origin;

    // Anything in flight belongs to the previous leg.
    _cancelToken?.cancel();
    _requestSeq++;
    _requestInFlight = false;
    _lastRequestAt = null;
    _setRoute(const [], approximate: false, speed: null);
    _offRouteCount = 0;

    if (_legNeedsRoute) {
      final from = _lastFix ?? _legOrigin;
      if (from != null) _request(from);
    }
    _render(_lastAnchor ?? _lastFix, force: true);
  }

  /// A new accepted driver fix: progress, off-route detection, and the
  /// decision whether a routing request is due. Does not redraw by itself —
  /// call [renderFrom] with the marker's displayed position.
  void onFix(LatLng fix, {double? accuracy}) {
    if (_disposed) return;
    _lastFix = fix;
    if (!_legNeedsRoute) return;

    final now = DateTime.now();
    final last = _lastRequestAt;

    if (_route.isEmpty || _approximate) {
      // First route of the leg (fix arrived after setLeg), or retrying after
      // the router failed.
      if (!_requestInFlight && (last == null || now.difference(last) >= _failureRetry)) {
        _request(fix);
      }
      return;
    }

    final hit = _project(fix, math.max(0, _progressIdx - 2));
    final threshold = ((accuracy ?? 0) * 2).clamp(_minOffRouteMeters, _maxOffRouteMeters);
    if (hit.distance > threshold) {
      _offRouteCount++;
      if (_offRouteCount >= _offRouteConfirmations &&
          !_requestInFlight &&
          (last == null || now.difference(last) >= _rerouteCooldown)) {
        _request(fix);
      }
    } else {
      _offRouteCount = 0;
      _progressIdx = hit.index;
    }
  }

  /// Redraws the remaining route from [anchor] (the marker's displayed
  /// position). Cheap; skipped when the anchor barely moved.
  void renderFrom(LatLng? anchor) => _render(anchor);

  void _render(LatLng? anchor, {bool force = false}) {
    if (_disposed) return;
    if (!force && anchor != null && _lastAnchor != null &&
        GeoMath.distance(anchor, _lastAnchor!) < 2) {
      return;
    }
    if (anchor != null) _lastAnchor = anchor;

    final target = _target;
    if (!_legNeedsRoute || target == null) {
      _emit(const []);
      return;
    }

    if (_route.isEmpty) {
      // First request still in flight: draw nothing rather than a line that
      // is replaced a moment later.
      _emit(const []);
      return;
    }

    if (_approximate) {
      final start = anchor ?? _route.first;
      final pts = [start, ..._waypoints, target];
      final meters = GeoMath.pathLength(pts);
      _emit(pts, remaining: meters, approximate: true);
      return;
    }

    if (anchor == null) {
      _emit(_route, remaining: _suffix.isEmpty ? null : _suffix.first);
      return;
    }

    final hit = _project(anchor, math.max(0, _renderIdx - 3));
    _renderIdx = hit.index;
    final next = hit.index + 1;
    final pts = <LatLng>[
      if (hit.distance > 8) anchor,
      hit.point,
      if (next < _route.length) ..._route.sublist(next),
    ];
    final remaining = next < _route.length
        ? GeoMath.distance(hit.point, _route[next]) + _suffix[next]
        : 0.0;
    _emit(pts, remaining: remaining);
  }

  void _emit(List<LatLng> points, {double? remaining, bool approximate = false}) {
    // Nothing drawn before and nothing now: don't wake the map.
    if (points.isEmpty && view.value.points.isEmpty && view.value.remainingMeters == null) return;
    double? eta;
    if (remaining != null && !approximate) {
      final speed = (_routeSpeed != null && _routeSpeed! > 0.5) ? _routeSpeed! : _fallbackSpeed;
      eta = remaining / speed;
    }
    view.value = RouteView(
      points: points,
      remainingMeters: remaining,
      etaSeconds: eta,
      approximate: approximate,
      version: ++_version,
    );
  }

  Future<void> _request(LatLng origin) async {
    final target = _target;
    if (target == null || _disposed) return;

    final seq = ++_requestSeq;
    final legAtRequest = _leg;
    _requestInFlight = true;
    _lastRequestAt = DateTime.now();
    _cancelToken?.cancel();
    final token = _cancelToken = CancelToken();

    final result = await _fetcher(
      origin: origin,
      destination: target,
      waypoints: _waypoints,
      cancelToken: token,
    );

    // Superseded (newer request, or the leg changed) or torn down.
    if (_disposed || seq != _requestSeq || legAtRequest != _leg) return;
    _requestInFlight = false;

    if (result == null) {
      // Keep a real route already on screen; only fall back to a straight
      // line when there is nothing better to show.
      if (_route.isEmpty) {
        _setRoute([origin, ..._waypoints, target], approximate: true, speed: null);
        _render(_lastAnchor ?? _lastFix ?? origin, force: true);
      }
      _offRouteCount = 0;
      return;
    }

    final speed = (result.durationSeconds > 0 && result.distanceMeters > 0)
        ? result.distanceMeters / result.durationSeconds
        : null;
    _setRoute(result.points, approximate: false, speed: speed);
    _offRouteCount = 0;
    _render(_lastAnchor ?? _lastFix ?? origin, force: true);
  }

  void _setRoute(List<LatLng> points, {required bool approximate, required double? speed}) {
    _route = points;
    _approximate = approximate;
    _routeSpeed = speed;
    _progressIdx = 0;
    _renderIdx = 0;
    final suffix = List<double>.filled(points.length, 0);
    for (var i = points.length - 2; i >= 0; i--) {
      suffix[i] = suffix[i + 1] + GeoMath.distance(points[i], points[i + 1]);
    }
    _suffix = suffix;
  }

  /// Nearest point on the route at or after segment [from]. Searches forward
  /// and stops once well past a close match, so a route that doubles back on
  /// itself can't snap the driver to the later pass.
  ({int index, LatLng point, double distance}) _project(LatLng p, int from) {
    var bestIdx = from;
    var bestPoint = _route[math.min(from, _route.length - 1)];
    var bestDist = double.infinity;
    var bestAlong = 0.0;
    var along = 0.0;
    for (var i = from; i < _route.length - 1; i++) {
      final hit = GeoMath.projectOnSegment(p, _route[i], _route[i + 1]);
      final d = GeoMath.distance(p, hit.point);
      if (d < bestDist) {
        bestDist = d;
        bestIdx = i;
        bestPoint = hit.point;
        bestAlong = along;
      }
      along += _suffix[i] - _suffix[i + 1];
      if (bestDist < 25 && along - bestAlong > 400) break;
    }
    if (bestDist == double.infinity) {
      bestDist = GeoMath.distance(p, bestPoint);
    }
    return (index: bestIdx, point: bestPoint, distance: bestDist);
  }

  void dispose() {
    _disposed = true;
    _cancelToken?.cancel();
    view.dispose();
  }
}
