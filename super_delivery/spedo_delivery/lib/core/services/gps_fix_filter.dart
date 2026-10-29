import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Drops GPS fixes that would make the driver's marker (ours and the
/// passenger's) jump, jitter or run backwards, before anything is drawn or
/// sent.
///
/// Rejected:
///  * null-island / NaN / out-of-range coordinates;
///  * poor accuracy (> [maxAccuracyMeters]) — unless nothing has been accepted
///    for [starvationWindow], so a driver in an urban canyon is never frozen;
///  * fixes older than (or a duplicate of) the last accepted one;
///  * jumps no vehicle could make: implied speed above [maxSpeedMps] after
///    allowing for both fixes' accuracy. After [maxConsecutiveJumps] such
///    rejections in a row the new position is taken as the truth (the earlier
///    anchor was the outlier, or the device really did move, e.g. a resumed
///    app after a long background freeze).
///
/// Pure Dart and stateful; one instance per stream.
class GpsFixFilter {
  GpsFixFilter({
    this.maxAccuracyMeters = 50,
    this.maxSpeedMps = 50,
    this.starvationWindow = const Duration(seconds: 15),
    this.maxConsecutiveJumps = 3,
  });

  final double maxAccuracyMeters;
  final double maxSpeedMps;
  final Duration starvationWindow;
  final int maxConsecutiveJumps;

  Position? _last;
  DateTime? _lastAcceptedAt; // wall clock, for the starvation window
  int _jumpRejects = 0;

  Position? get lastAccepted => _last;

  /// Forget the anchor (e.g. tracking restarted after going offline).
  void reset() {
    _last = null;
    _lastAcceptedAt = null;
    _jumpRejects = 0;
  }

  /// True when [p] is usable. Accepted fixes become the new anchor.
  bool accept(Position p) {
    if (!isValidCoordinate(p.latitude, p.longitude)) return false;

    final now = DateTime.now();
    final starving = _lastAcceptedAt == null ||
        now.difference(_lastAcceptedAt!) > starvationWindow;

    final accuracy = p.accuracy;
    final accuracyKnown = accuracy.isFinite && accuracy > 0;
    if (accuracyKnown && accuracy > maxAccuracyMeters && !starving) {
      return false;
    }

    final last = _last;
    if (last != null) {
      final dtMs = p.timestamp.difference(last.timestamp).inMilliseconds;
      // Out of order, or the same fix delivered twice.
      if (dtMs < 0) return false;
      if (dtMs == 0 &&
          p.latitude == last.latitude &&
          p.longitude == last.longitude) {
        return false;
      }

      final meters = distanceMeters(
        last.latitude,
        last.longitude,
        p.latitude,
        p.longitude,
      );
      // Accuracy circles may overlap; only movement beyond them counts.
      final slack = _acc(last) + _acc(p);
      final effective = math.max(0.0, meters - slack);
      final secs = math.max(dtMs / 1000.0, 1.0);
      if (effective / secs > maxSpeedMps) {
        _jumpRejects++;
        if (_jumpRejects < maxConsecutiveJumps) return false;
      }
    }

    _jumpRejects = 0;
    _last = p;
    _lastAcceptedAt = now;
    return true;
  }

  static double _acc(Position p) {
    final a = p.accuracy;
    if (!a.isFinite || a <= 0) return 0;
    return math.min(a, 100.0);
  }

  static bool isValidCoordinate(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return false;
    // (0, 0) is what a failed fix reports on several chipsets.
    if (lat.abs() < 1e-6 && lng.abs() < 1e-6) return false;
    return true;
  }

  /// Great-circle distance in metres.
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h.toDouble())));
  }

  /// Initial bearing from point 1 to point 2, degrees in [0, 360).
  static double bearingDegrees(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    double rad(double d) => d * math.pi / 180;
    final p1 = rad(lat1), p2 = rad(lat2);
    final dl = rad(lng2 - lng1);
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl);
    final deg = math.atan2(y, x) * 180 / math.pi;
    return (deg + 360) % 360;
  }

  /// Smallest signed difference b - a, in (-180, 180].
  static double angleDelta(double a, double b) {
    var d = (b - a) % 360;
    if (d > 180) d -= 360;
    if (d <= -180) d += 360;
    return d;
  }
}
