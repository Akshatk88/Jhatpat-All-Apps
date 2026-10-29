import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:superapp_user/core/maps/geo_math.dart';

/// Where the driver marker is drawn right now.
@immutable
class DriverPose {
  final LatLng position;

  /// Degrees clockwise from north.
  final double rotation;
  const DriverPose(this.position, this.rotation);
}

/// Glides the driver marker between GPS fixes instead of teleporting it.
///
/// * Each fix starts one segment from wherever the marker is *displayed*
///   (mid-animation included) to the fix, lasting about the observed
///   inter-packet interval — so a new fix replaces the running segment
///   rather than queueing behind it, and the marker keeps pace with the feed.
/// * Heading turns along the shorter arc (359° → 1° is a 2° turn).
/// * A jump over [_snapDistance] (GPS glitch, reconnect after a long gap)
///   snaps instead of sliding across the city.
/// * After reaching the fix, a short, capped prediction (≤ [_maxPredictTime],
///   ≤ [_maxPredictMeters]) continues along the heading when the driver is
///   moving, and never when the feed has gone quiet.
/// * [pose] is published at most ~30 times a second, and the ticker stops
///   between segments, so a parked driver costs no frames at all.
class DriverMarkerAnimator {
  DriverMarkerAnimator(TickerProvider vsync) {
    _ticker = vsync.createTicker(_onTick);
  }

  static const double _snapDistance = 500;
  static const int _minSegmentMs = 300;
  static const int _maxSegmentMs = 5000;
  static const int _maxPredictMs = 2000;
  static const double _maxPredictMeters = 30;
  static const double _minPredictSpeed = 1.5; // m/s
  static const int _emitEveryMs = 33;

  final ValueNotifier<DriverPose?> pose = ValueNotifier(null);
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch();

  LatLng? _from;
  LatLng? _to;
  double _fromRot = 0;
  double _toRot = 0;
  int _segmentMs = 0;
  LatLng? _predictTo;
  int _predictMs = 0;
  bool _predicting = false;
  int _lastEmitMs = -1000;

  DateTime? _lastFixAt;
  double _intervalMs = 3000;
  bool _disposed = false;

  void onFix(LatLng target, {double? heading, double? speed}) {
    if (_disposed) return;
    final now = DateTime.now();
    final previousFixAt = _lastFixAt;
    if (previousFixAt != null) {
      final dt = now.difference(previousFixAt).inMilliseconds.toDouble();
      if (dt > 200 && dt < 30000) _intervalMs = _intervalMs * 0.6 + dt * 0.4;
    }
    _lastFixAt = now;

    final current = pose.value;
    final moved = current == null ? 0.0 : GeoMath.distance(current.position, target);
    final rotation = _resolveRotation(current, target, heading, speed);

    if (current == null || moved > _snapDistance) {
      _stop();
      _from = target;
      _to = target;
      _toRot = rotation;
      _predictTo = null;
      pose.value = DriverPose(target, rotation);
      return;
    }

    // Parked / GPS jitter: nothing worth spending frames on.
    final turn = (((rotation - current.rotation) + 540) % 360 - 180).abs();
    if (moved < 1 && turn < 2) {
      _stop();
      _to = target;
      return;
    }

    _from = current.position;
    _fromRot = current.rotation;
    _to = target;
    _toRot = rotation;
    _segmentMs = _intervalMs.round().clamp(_minSegmentMs, _maxSegmentMs);

    _predictTo = null;
    _predictMs = 0;
    _predicting = false;
    if (speed != null && speed >= _minPredictSpeed && speed < 60) {
      final meters = math.min(_maxPredictMeters, speed * _maxPredictMs / 1000);
      _predictMs = (meters / speed * 1000).round();
      _predictTo = GeoMath.offset(target, rotation, meters);
    }

    _clock
      ..reset()
      ..start();
    _lastEmitMs = -1000;
    if (!_ticker.isActive) _ticker.start();
  }

  double _resolveRotation(
    DriverPose? current,
    LatLng target,
    double? heading,
    double? speed,
  ) {
    final moving = speed == null || speed > 0.8;
    // Many devices report heading 0 when the bearing is unknown.
    final usableHeading = heading != null && moving && !(heading == 0 && speed == null);
    if (usableHeading) return GeoMath.normalizeAngle(heading);
    // Bearing from the previous *fix*, not the displayed marker: after a
    // prediction the marker can sit slightly ahead, and a bearing from there
    // would flip the vehicle backwards.
    final origin = _to ?? current?.position;
    if (origin != null && GeoMath.distance(origin, target) > 3) {
      return GeoMath.bearing(origin, target);
    }
    return current?.rotation ?? GeoMath.normalizeAngle(heading ?? 0);
  }

  void _onTick(Duration _) {
    final from = _from;
    final to = _to;
    if (from == null || to == null) {
      _stop();
      return;
    }
    final ms = _clock.elapsedMilliseconds;
    LatLng position;
    double rotation;
    var done = false;

    if (ms < _segmentMs) {
      final t = ms / _segmentMs;
      position = GeoMath.lerp(from, to, t);
      // Turn a little faster than the move so the nose leads the body.
      rotation = GeoMath.lerpAngle(_fromRot, _toRot, math.min(1.0, t * 2));
    } else if (_predictTo != null && ms < _segmentMs + _predictMs && _feedIsFresh()) {
      final t = (ms - _segmentMs) / _predictMs;
      position = GeoMath.lerp(to, _predictTo!, t);
      rotation = _toRot;
      _predicting = true;
    } else {
      // Motion over: rest on the fix; on the prediction's end if it ran to
      // completion; or where it was cut short when the feed went quiet.
      if (_predictTo == null || !_predicting) {
        position = to;
      } else if (ms >= _segmentMs + _predictMs && _feedIsFresh()) {
        position = _predictTo!;
      } else {
        position = pose.value?.position ?? to;
      }
      rotation = _toRot;
      done = true;
    }

    if (!done && ms - _lastEmitMs < _emitEveryMs) return;
    _lastEmitMs = ms;
    pose.value = DriverPose(position, rotation);
    if (done) _stop();
  }

  /// Prediction only while packets are arriving on their usual cadence.
  bool _feedIsFresh() {
    final at = _lastFixAt;
    if (at == null) return false;
    final age = DateTime.now().difference(at).inMilliseconds;
    return age < math.min(_intervalMs + 2500, 15000);
  }

  void _stop() {
    if (_ticker.isActive) _ticker.stop();
    _clock.stop();
  }

  void dispose() {
    _disposed = true;
    _ticker.dispose();
    pose.dispose();
  }
}
