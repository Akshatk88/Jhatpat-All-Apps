import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Where the rider is on a route: the path still ahead of them, and how long
/// it is. [remaining] starts at the point on the route closest to the rider
/// (not at the raw GPS fix), so the line begins under the bike and everything
/// behind it is gone, like a navigation app.
class RouteProgress {
  const RouteProgress({
    required this.remaining,
    required this.remainingMeters,
    required this.offRouteMeters,
  });

  final List<LatLng> remaining;
  final double remainingMeters;

  /// Straight-line distance from the GPS fix to the route. Large means the
  /// rider left the route and it should be re-fetched.
  final double offRouteMeters;
}

enum TurnKind { straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, arrive }

/// The next manoeuvre ahead on a route, derived from the polyline's own
/// geometry (the route endpoint returns no step list).
class NextTurn {
  const NextTurn({required this.kind, required this.distanceMeters, required this.at});

  final TurnKind kind;
  final double distanceMeters;

  /// Where the manoeuvre happens; used to look up the road name.
  final LatLng at;
}

/// Follows a rider along one route. Create one per screen, call [setRoute]
/// when a route arrives and [update] on every position fix.
class RouteTracker {
  List<LatLng> _route = const [];
  List<double> _cumulative = const [];
  int _segment = 0;

  bool get hasRoute => _route.length > 1;

  /// How many segments ahead of the last match are searched first. The route
  /// is followed forward so a road that loops back near itself cannot make the
  /// line jump backwards.
  static const _window = 40;

  void setRoute(List<LatLng> points) {
    _route = points;
    _segment = 0;
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + _distance(points[i - 1], points[i]));
    }
    _cumulative = cumulative;
  }

  void clear() => setRoute(const []);

  double get totalMeters => _cumulative.isEmpty ? 0 : _cumulative.last;

  RouteProgress? update(LatLng position) {
    if (!hasRoute) return null;

    var best = _closest(position, _segment, math.min(_route.length - 1, _segment + _window));
    // Nothing near within the window: look at the whole route before deciding
    // the rider is off it (e.g. after a long GPS gap).
    if (best.distance > 80) {
      final whole = _closest(position, 0, _route.length - 1);
      if (whole.distance < best.distance) best = whole;
    }
    _segment = best.segment;

    final remaining = <LatLng>[best.snapped, ..._route.sublist(best.segment + 1)];
    final alongMeters = _cumulative[best.segment] + _distance(_route[best.segment], best.snapped);
    return RouteProgress(
      remaining: remaining,
      remainingMeters: math.max(0, totalMeters - alongMeters),
      offRouteMeters: best.distance,
    );
  }

  ({int segment, LatLng snapped, double distance}) _closest(LatLng p, int from, int to) {
    var bestSegment = from;
    var bestSnapped = _route[from];
    var bestDistance = double.infinity;
    for (var i = from; i < to && i < _route.length - 1; i++) {
      final snapped = _project(p, _route[i], _route[i + 1]);
      final d = _distance(p, snapped);
      if (d < bestDistance) {
        bestDistance = d;
        bestSegment = i;
        bestSnapped = snapped;
      }
    }
    return (segment: bestSegment, snapped: bestSnapped, distance: bestDistance);
  }

  /// Finds the first real turn on [progress]'s remaining path.
  ///
  /// A polyline has a vertex at every kink in the road, so a turn is judged
  /// from the direction of travel [_look] metres before the vertex against
  /// [_look] metres after it, which ignores small wobbles and curves.
  NextTurn nextTurn(RouteProgress progress, {double minAngle = 35}) {
    final pts = progress.remaining;
    final end = pts.last;
    if (pts.length < 3) {
      return NextTurn(kind: TurnKind.arrive, distanceMeters: progress.remainingMeters, at: end);
    }

    final cumulative = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cumulative.add(cumulative.last + _distance(pts[i - 1], pts[i]));
    }

    LatLng pointAt(double meters) {
      final target = meters.clamp(0, cumulative.last).toDouble();
      for (var i = 1; i < pts.length; i++) {
        if (cumulative[i] >= target) {
          final seg = cumulative[i] - cumulative[i - 1];
          final t = seg == 0 ? 0.0 : (target - cumulative[i - 1]) / seg;
          return LatLng(
            pts[i - 1].latitude + (pts[i].latitude - pts[i - 1].latitude) * t,
            pts[i - 1].longitude + (pts[i].longitude - pts[i - 1].longitude) * t,
          );
        }
      }
      return pts.last;
    }

    for (var i = 1; i < pts.length - 1; i++) {
      final at = cumulative[i];
      // Too close to the end for a meaningful "after" leg: that is arrival.
      if (cumulative.last - at < 15) break;
      final before = pointAt(math.max(0, at - _look));
      final after = pointAt(at + _look);
      final inBearing = _bearing(before, pts[i]);
      final outBearing = _bearing(pts[i], after);
      var delta = outBearing - inBearing;
      while (delta > 180) {
        delta -= 360;
      }
      while (delta < -180) {
        delta += 360;
      }
      if (delta.abs() >= minAngle) {
        return NextTurn(kind: _kindFor(delta), distanceMeters: at, at: pts[i]);
      }
    }
    return NextTurn(kind: TurnKind.arrive, distanceMeters: progress.remainingMeters, at: end);
  }

  /// Next turn along a path that is already trimmed to the vehicle, for
  /// screens that keep their own trimmed list.
  static NextTurn? turnAlong(List<LatLng> remaining) {
    if (remaining.length < 2) return null;
    final tracker = RouteTracker()..setRoute(remaining);
    final progress = tracker.update(remaining.first);
    return progress == null ? null : tracker.nextTurn(progress);
  }

  static const _look = 25.0;

  static TurnKind _kindFor(double delta) {
    final a = delta.abs();
    final right = delta > 0;
    if (a >= 150) return TurnKind.uTurn;
    if (a >= 110) return right ? TurnKind.sharpRight : TurnKind.sharpLeft;
    if (a >= 60) return right ? TurnKind.right : TurnKind.left;
    return right ? TurnKind.slightRight : TurnKind.slightLeft;
  }
}

/// Seconds to cover [remainingMeters].
///
/// Uses the route's own average speed (distance / duration from the server)
/// as the baseline, blended with the rider's live speed once they are really
/// moving, and clamped so a red light or a GPS spike cannot show 2 hours.
double etaSeconds({
  required double remainingMeters,
  double? routeAverageMps,
  double? liveSpeedMps,
}) {
  var mps = (routeAverageMps != null && routeAverageMps > 0) ? routeAverageMps : 5.0; // 18 km/h
  if (liveSpeedMps != null && liveSpeedMps >= 3) {
    mps = (mps + liveSpeedMps) / 2;
  }
  mps = mps.clamp(1.7, 14.0); // 6 .. 50 km/h
  return remainingMeters / mps;
}

double _distance(LatLng a, LatLng b) {
  const r = 6371000.0;
  final dLat = _rad(b.latitude - a.latitude);
  final dLng = _rad(b.longitude - a.longitude);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Closest point to [p] on segment a-b, on a local flat approximation (exact
/// enough at the few-hundred-metre scale of one segment).
LatLng _project(LatLng p, LatLng a, LatLng b) {
  final cosLat = math.cos(_rad(a.latitude));
  final ax = a.longitude * cosLat, ay = a.latitude;
  final bx = b.longitude * cosLat, by = b.latitude;
  final px = p.longitude * cosLat, py = p.latitude;
  final dx = bx - ax, dy = by - ay;
  final len2 = dx * dx + dy * dy;
  if (len2 == 0) return a;
  final t = (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0);
  return LatLng(a.latitude + (b.latitude - a.latitude) * t, a.longitude + (b.longitude - a.longitude) * t);
}

double _bearing(LatLng a, LatLng b) {
  final dLng = _rad(b.longitude - a.longitude);
  final y = math.sin(dLng) * math.cos(_rad(b.latitude));
  final x = math.cos(_rad(a.latitude)) * math.sin(_rad(b.latitude)) -
      math.sin(_rad(a.latitude)) * math.cos(_rad(b.latitude)) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

double _rad(double deg) => deg * math.pi / 180;
