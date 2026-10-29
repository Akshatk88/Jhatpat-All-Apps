import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/utils/polyline_decoder.dart';

/// A drawn route between two points.
class RideRoute {
  const RideRoute({
    required this.points,
    this.durationMins,
    this.distanceKm,
    this.isApproximate = false,
  });

  final List<LatLng> points;
  final double? durationMins;
  final double? distanceKm;

  /// True for the straight-line fallback: no road router answered, so the line
  /// is only a direction hint and is drawn dashed.
  final bool isApproximate;

  bool get isEmpty => points.isEmpty;
}

/// Road route for the driver's current leg.
///
/// k9 exposes no route endpoint for rides (the taxi module only pushes driver
/// positions to the passenger over `ride:driver-route:updated`), so the route
/// is fetched here, in order of preference:
///  1. Google Directions with the app's Maps key;
///  2. OSRM's public demo router — used when Google refuses the key
///     (`REQUEST_DENIED`: an Android-restricted key, or billing disabled) or
///     returns nothing;
///  3. a straight line, so the map always shows *which way* the target is.
///
/// Once Google refuses the key it is not asked again for this app session:
/// every further call would be refused the same way and only delay the line.
class RideRouteService {
  RideRouteService(this._dio);

  final Dio _dio;
  bool _googleDisabled = false;

  Future<RideRoute> fetch({required LatLng from, required LatLng to}) async {
    if (!_googleDisabled) {
      final google = await _google(from, to);
      if (google != null) return google;
    }
    final osrm = await _osrm(from, to);
    if (osrm != null) return osrm;
    return straightLine(from, to);
  }

  static RideRoute straightLine(LatLng from, LatLng to) {
    final km = distanceMeters(from, to) / 1000.0;
    return RideRoute(
      points: [from, to],
      distanceKm: km,
      // ~25 km/h city average with a 1.3 road-detour factor; only a hint.
      durationMins: km * 1.3 / 25 * 60,
      isApproximate: true,
    );
  }

  Future<RideRoute?> _google(LatLng from, LatLng to) async {
    try {
      final res = await _dio.get(
        'https://maps.googleapis.com/maps/api/directions/json',
        queryParameters: {
          'origin': '${from.latitude},${from.longitude}',
          'destination': '${to.latitude},${to.longitude}',
          'mode': 'driving',
          'key': AppConstants.mapKey,
        },
      );

      final data = res.data;
      if (data is! Map) return null;
      final status = data['status']?.toString();
      if (status != 'OK') {
        if (status == 'REQUEST_DENIED' || status == 'OVER_DAILY_LIMIT') {
          debugPrint('[RideRoute] Google Directions $status — using OSRM');
          _googleDisabled = true;
        }
        return null;
      }

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;

      final route = routes.first as Map;
      final encoded = (route['overview_polyline']?['points'] ?? '').toString();
      if (encoded.isEmpty) return null;

      final legs = route['legs'] as List?;
      final leg = (legs != null && legs.isNotEmpty) ? legs.first as Map : null;

      return RideRoute(
        points: decodePolyline(encoded),
        durationMins: leg == null
            ? null
            : ((leg['duration']?['value'] as num?)?.toDouble() ?? 0) / 60.0,
        distanceKm: leg == null
            ? null
            : ((leg['distance']?['value'] as num?)?.toDouble() ?? 0) / 1000.0,
      );
    } catch (_) {
      return null;
    }
  }

  Future<RideRoute?> _osrm(LatLng from, LatLng to) async {
    try {
      final res = await _dio.get(
        'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        queryParameters: const {
          'overview': 'full',
          'geometries': 'polyline',
        },
      );
      final data = res.data;
      if (data is! Map || data['code'] != 'Ok') return null;
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return null;
      final route = routes.first as Map;
      final encoded = (route['geometry'] ?? '').toString();
      if (encoded.isEmpty) return null;
      return RideRoute(
        points: decodePolyline(encoded),
        durationMins: ((route['duration'] as num?)?.toDouble() ?? 0) / 60.0,
        distanceKm: ((route['distance'] as num?)?.toDouble() ?? 0) / 1000.0,
      );
    } catch (_) {
      return null;
    }
  }

  /// Great-circle distance in metres.
  static double distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLng = rad(b.longitude - a.longitude);
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(a.latitude)) *
            math.cos(rad(b.latitude)) *
            math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h.toDouble()));
  }

  /// Where [p] is relative to [route]: the index of the segment it is closest
  /// to and how far off that segment it is, in metres. Flat-earth projection
  /// around [p] — accurate to well under a metre over a city leg.
  static ({int segment, double offMeters}) locateOnRoute(
    LatLng p,
    List<LatLng> route,
  ) {
    if (route.length < 2) {
      return (
        segment: 0,
        offMeters: route.isEmpty ? double.infinity : distanceMeters(p, route.first),
      );
    }
    const mPerDegLat = 111320.0;
    final mPerDegLng = 111320.0 * math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) => (q.longitude - p.longitude) * mPerDegLng;
    double y(LatLng q) => (q.latitude - p.latitude) * mPerDegLat;

    var best = double.infinity;
    var bestIndex = 0;
    for (var i = 0; i < route.length - 1; i++) {
      final ax = x(route[i]), ay = y(route[i]);
      final bx = x(route[i + 1]), by = y(route[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      var t = len2 == 0 ? 0.0 : -(ax * dx + ay * dy) / len2;
      t = t.clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final d = math.sqrt(cx * cx + cy * cy);
      if (d < best) {
        best = d;
        bestIndex = i;
      }
    }
    return (segment: bestIndex, offMeters: best);
  }
}

final rideRouteServiceProvider = Provider<RideRouteService>((ref) {
  // A bare Dio on purpose: no baseUrl, no auth interceptor (our bearer must
  // never be sent to a third party), no retry policy.
  return RideRouteService(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 10),
      ),
    ),
  );
});
