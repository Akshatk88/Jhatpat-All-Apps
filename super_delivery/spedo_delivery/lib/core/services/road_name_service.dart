import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../constants/app_constants.dart';

/// Names the road at a point ("Shanti Nagar Rd") for the turn banner, using
/// Google's Geocoding API with the app's map key.
///
/// The route endpoint returns only a polyline, no street names. Results are
/// cached by ~11 m cell, and any failure just returns null: the banner then
/// shows the manoeuvre without a name instead of an error.
class RoadNameService {
  RoadNameService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 6),
              receiveTimeout: const Duration(seconds: 6),
            ));

  final Dio _dio;
  final Map<String, String?> _cache = {};

  Future<String?> nameAt(LatLng point) async {
    final key = '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}';
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'latlng': '${point.latitude},${point.longitude}',
          'result_type': 'route',
          'key': AppConstants.mapKey,
        },
      );
      final results = res.data?['results'];
      String? name;
      if (results is List && results.isNotEmpty) {
        final components = (results.first as Map)['address_components'];
        if (components is List) {
          for (final c in components) {
            final types = (c as Map)['types'];
            if (types is List && types.contains('route')) {
              name = (c['short_name'] ?? c['long_name'])?.toString();
              break;
            }
          }
        }
      }
      _cache[key] = name;
      return name;
    } catch (_) {
      return null; // not cached: a later attempt may succeed
    }
  }
}
