import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/services/gps_fix_filter.dart';

/// Where the driver's bike marker is drawn right now, and which way it faces.
@immutable
class DriverMarkerPose {
  const DriverMarkerPose(this.position, this.rotation);

  final LatLng position;

  /// Degrees clockwise from north, [0, 360).
  final double rotation;
}

/// Glides the driver's marker between GPS fixes instead of teleporting it.
///
/// Each new fix starts a short linear interpolation from wherever the marker
/// is *currently drawn* (so a fix that lands mid-glide does not snap back) to
/// the new point. Rotation takes the shortest way round, so 359° → 2° turns
/// 3° clockwise, not 357° anticlockwise.
///
/// Ticks on a ~15 fps timer rather than a 60 fps ticker: every frame is a
/// marker update over the Maps platform channel, and 15 fps is visually
/// smooth for a vehicle at street zoom.
///
/// Only listeners of [pose] rebuild — wrap just the GoogleMap in a
/// ValueListenableBuilder, not the whole screen.
class DriverMarkerAnimator {
  DriverMarkerAnimator();

  final ValueNotifier<DriverMarkerPose?> pose = ValueNotifier(null);

  static const _frame = Duration(milliseconds: 66);

  /// Above this jump the marker is placed, not animated (a re-anchored fix
  /// after a long gap would otherwise draw the bike flying over buildings).
  static const _teleportMeters = 500.0;

  Timer? _timer;
  bool _disposed = false;

  /// Moves the marker to [target], facing [rotation] (null keeps the current
  /// facing), over [duration].
  void moveTo(
    LatLng target, {
    double? rotation,
    Duration duration = const Duration(milliseconds: 1000),
  }) {
    if (_disposed) return;
    final from = pose.value;
    final toRotation = rotation ?? from?.rotation ?? 0;
    if (from == null) {
      _timer?.cancel();
      pose.value = DriverMarkerPose(target, toRotation % 360);
      return;
    }

    final meters = GpsFixFilter.distanceMeters(
      from.position.latitude,
      from.position.longitude,
      target.latitude,
      target.longitude,
    );
    if (meters > _teleportMeters || duration <= _frame) {
      _timer?.cancel();
      pose.value = DriverMarkerPose(target, toRotation % 360);
      return;
    }

    final start = from.position;
    final startRotation = from.rotation;
    final turn = GpsFixFilter.angleDelta(startRotation, toRotation);
    final totalMs = duration.inMilliseconds;
    final sw = Stopwatch()..start();

    _timer?.cancel();
    _timer = Timer.periodic(_frame, (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      final f = (sw.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      final lat = start.latitude + (target.latitude - start.latitude) * f;
      final lng = start.longitude + (target.longitude - start.longitude) * f;
      final rot = (startRotation + turn * f) % 360;
      pose.value = DriverMarkerPose(LatLng(lat, lng), rot);
      if (f >= 1.0) t.cancel();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    pose.dispose();
  }
}
