import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Small, allocation-light geometry helpers for live tracking.
///
/// Distances are great-circle (haversine); projections use a local
/// equirectangular approximation, which is accurate to well under a metre at
/// the few-hundred-metre scale a route segment spans.
class GeoMath {
  GeoMath._();

  static const double _earthRadius = 6371000.0;
  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;

  /// True for a coordinate worth drawing: finite, in range, and not the
  /// (0,0) "no fix" sentinel some payloads carry.
  static bool isValid(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return false;
    return true;
  }

  static double distance(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(a.latitude)) *
            math.cos(_rad(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * _earthRadius * math.asin(math.min(1.0, math.sqrt(s)));
  }

  /// Initial bearing from [a] to [b], degrees clockwise from north, 0..360.
  static double bearing(LatLng a, LatLng b) {
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final dLng = _rad(b.longitude - a.longitude);
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  static LatLng lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );

  /// Normalises any angle to 0..360.
  static double normalizeAngle(double deg) {
    final r = deg % 360;
    return r < 0 ? r + 360 : r;
  }

  /// Interpolates between two headings along the shorter arc, so 359° → 1°
  /// turns 2° instead of spinning the marker 358° the other way.
  static double lerpAngle(double from, double to, double t) {
    final delta = ((to - from + 540) % 360) - 180;
    return normalizeAngle(from + delta * t);
  }

  /// The point [meters] from [origin] along [bearingDeg].
  static LatLng offset(LatLng origin, double bearingDeg, double meters) {
    final d = meters / _earthRadius;
    final b = _rad(bearingDeg);
    final lat1 = _rad(origin.latitude);
    final lng1 = _rad(origin.longitude);
    final lat2 = math.asin(math.sin(lat1) * math.cos(d) +
        math.cos(lat1) * math.sin(d) * math.cos(b));
    final lng2 = lng1 +
        math.atan2(math.sin(b) * math.sin(d) * math.cos(lat1),
            math.cos(d) - math.sin(lat1) * math.sin(lat2));
    return LatLng(_deg(lat2), _deg(lng2));
  }

  /// Projects [p] onto segment [a]→[b]. Returns the closest point on the
  /// segment and the fraction along it (0..1).
  static ({LatLng point, double t}) projectOnSegment(LatLng p, LatLng a, LatLng b) {
    final cosLat = math.cos(_rad(p.latitude));
    final ax = a.longitude * cosLat, ay = a.latitude;
    final bx = b.longitude * cosLat, by = b.latitude;
    final px = p.longitude * cosLat, py = p.latitude;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    return (point: lerp(a, b, t), t: t);
  }

  /// Total length of a polyline in metres.
  static double pathLength(List<LatLng> points, [int from = 0]) {
    var sum = 0.0;
    for (var i = math.max(1, from + 1); i < points.length; i++) {
      sum += distance(points[i - 1], points[i]);
    }
    return sum;
  }
}
