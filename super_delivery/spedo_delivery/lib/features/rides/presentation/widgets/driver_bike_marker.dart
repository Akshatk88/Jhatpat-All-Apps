import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// The driver's own position on the ride and delivery maps: the same top-down
/// bike the passenger app shows for a Bike ride (`assets/markers/markerbike.png`
/// there, copied here as `assets/image/marker_bike.png`).
///
/// Top-down art, so callers rotate it with the heading (`flat: true`).
/// Built once and cached.
class DriverBikeMarker {
  DriverBikeMarker._();

  static Future<BitmapDescriptor>? _cached;

  /// On-map width in logical pixels — the same size the passenger app uses
  /// for vehicle markers.
  static const double width = 34;

  static Future<BitmapDescriptor> icon() => _cached ??= _load();

  static Future<BitmapDescriptor> _load() async {
    try {
      final data = await rootBundle.load('assets/image/marker_bike.png');
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 96, // decoded small: the source is 1024px wide
      );
      final frame = await codec.getNextFrame();
      final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw StateError('marker decode failed');
      return BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: width);
    } catch (_) {
      _cached = null; // try again next time
      return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
    }
  }
}
