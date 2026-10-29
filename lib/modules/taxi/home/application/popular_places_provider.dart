import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/taxi_constants.dart';
import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';

/// A well-known place near the rider, shown as a one-tap destination tile on
/// the rides home.
class PopularPlace {
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// Photo URL when the place source has one (Google Places). Empty otherwise;
  /// the tile then draws an icon for [kind].
  final String photoUrl;

  /// Rough category ("railway", "mall", "hospital", "temple", "park", ...)
  /// used only to pick the fallback icon.
  final String kind;

  const PopularPlace({
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    this.photoUrl = '',
    this.kind = '',
  });
}

/// Prominent places around the rider's current location.
///
/// Google Places first (it has photos); when that project has no billing it
/// answers REQUEST_DENIED, so OpenStreetMap (Photon) fills the list instead.
final popularPlacesProvider = FutureProvider<List<PopularPlace>>((ref) async {
  final position = await ref.watch(currentPositionProvider.future);
  if (position == null) return const [];
  final lat = position.latitude;
  final lng = position.longitude;

  // Admin-curated places for the zone the rider is in (Taxi Admin > Zone >
  // Popular places), nearest first. When the zone has any, they are the list;
  // Google/OSM below only fill in for a zone the admin has not set up.
  try {
    final data = await ref.watch(taxiApiClientProvider).get(
      ApiConstants.popularPlaces,
      query: {'lat': lat, 'lng': lng},
    );
    final rows = data is Map ? (data['places'] as List? ?? const []) : const [];
    final adminPlaces = <PopularPlace>[];
    for (final raw in rows) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString().trim();
      final loc = raw['location'] as Map?;
      final pLat = (loc?['lat'] as num?)?.toDouble();
      final pLng = (loc?['lng'] as num?)?.toDouble();
      if (name.isEmpty || pLat == null || pLng == null) continue;
      final address = (raw['address'] ?? '').toString().trim();
      adminPlaces.add(PopularPlace(
        name: name,
        address: address.isNotEmpty ? '$name, $address' : name,
        lat: pLat,
        lng: pLng,
        photoUrl: ApiConfig.resolveMedia((raw['image'] ?? '').toString().trim()),
        kind: name,
      ));
    }
    if (adminPlaces.isNotEmpty) return adminPlaces;
  } catch (e) {
    debugPrint('Popular places (admin zone) error: $e');
  }

  const wanted = 9;
  final dio = Dio();
  final found = <PopularPlace>[];
  final seen = <String>{};

  final key = TaxiConstants.mapKey;
  if (key.isNotEmpty) {
    try {
      final response = await dio.get(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json',
        queryParameters: {
          'location': '$lat,$lng',
          'radius': 8000,
          'key': key,
        },
      );
      final data = response.data;
      if (data != null && data['status'] == 'OK') {
        for (final raw in (data['results'] as List? ?? const [])) {
          final item = raw as Map;
          final types = (item['types'] as List?)?.cast<String>() ?? const [];
          if (types.contains('locality') || types.contains('political')) {
            continue;
          }
          final name = (item['name'] ?? '').toString().trim();
          final loc = (item['geometry'] as Map?)?['location'] as Map?;
          final pLat = (loc?['lat'] as num?)?.toDouble();
          final pLng = (loc?['lng'] as num?)?.toDouble();
          if (name.isEmpty || pLat == null || pLng == null) continue;
          if (!seen.add(name.toLowerCase())) continue;
          final photos = item['photos'] as List?;
          final ref0 = photos != null && photos.isNotEmpty
              ? (photos.first as Map)['photo_reference']?.toString() ?? ''
              : '';
          final vicinity = (item['vicinity'] ?? '').toString().trim();
          found.add(PopularPlace(
            name: name,
            address: vicinity.isNotEmpty ? '$name, $vicinity' : name,
            lat: pLat,
            lng: pLng,
            photoUrl: ref0.isEmpty
                ? ''
                : 'https://maps.googleapis.com/maps/api/place/photo'
                    '?maxwidth=400&photo_reference=$ref0&key=$key',
            kind: types.isNotEmpty ? types.first : '',
          ));
          if (found.length >= wanted) break;
        }
      }
    } catch (e) {
      debugPrint('Popular places (Google) error: $e');
    }
  }

  if (found.length < wanted) {
    try {
      final response = await dio.get(
        'https://photon.komoot.io/reverse',
        queryParameters: {
          'lat': lat,
          'lon': lng,
          'radius': 8,
          'limit': 30,
          'osm_tag': [
            'railway:station',
            'shop:mall',
            'amenity:hospital',
            'amenity:place_of_worship',
            'tourism',
            'leisure:park',
            'amenity:bus_station',
            'amenity:university',
            'amenity:college',
          ],
        },
        options: Options(
          headers: {'User-Agent': 'SuperAppUser/1.0'},
          listFormat: ListFormat.multi,
        ),
      );
      final features = (response.data?['features'] as List?) ?? const [];
      for (final raw in features) {
        final feature = raw as Map;
        final props = (feature['properties'] as Map?) ?? const {};
        final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
        final name = (props['name'] ?? '').toString().trim();
        if (name.isEmpty || coords == null || coords.length < 2) continue;
        if (!seen.add(name.toLowerCase())) continue;
        final detail = [props['street'], props['district'], props['city']]
            .whereType<String>()
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
        found.add(PopularPlace(
          name: name,
          address: detail.isNotEmpty ? '$name, $detail' : name,
          lat: (coords[1] as num).toDouble(),
          lng: (coords[0] as num).toDouble(),
          kind: '${props['osm_key'] ?? ''}:${props['osm_value'] ?? ''}',
        ));
        if (found.length >= wanted) break;
      }
    } catch (e) {
      debugPrint('Popular places (OSM) error: $e');
    }
  }

  return found;
});
