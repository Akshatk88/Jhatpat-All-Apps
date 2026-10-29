import 'dart:async';
import 'package:dio/dio.dart';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:geolocator/geolocator.dart';
import 'package:superapp_user/core/config/app_constants.dart';
import 'package:superapp_user/core/i18n/tr.dart';

/// Result wrapper for GPS location detection and reverse geocoding.
/// One search hit in the address picker.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.description,
    required this.latitude,
    required this.longitude,
  });

  final String description;
  final double latitude;
  final double longitude;
}

class UserLocationResult {
  final double? latitude;
  final double? longitude;
  final String building;
  final String street;
  final String area;
  final String landmark;
  final String city;
  final String state;
  final String pincode;
  final String fullAddress;
  final String? error;

  final bool isPermissionDenied;
  final bool isPermanentlyDenied;
  final bool isServiceDisabled;

  const UserLocationResult({
    this.latitude,
    this.longitude,
    this.building = '',
    this.street = '',
    this.area = '',
    this.landmark = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.fullAddress = '',
    this.error,
    this.isPermissionDenied = false,
    this.isPermanentlyDenied = false,
    this.isServiceDisabled = false,
  });

  bool get isSuccess => latitude != null && longitude != null && error == null;
}

/// Service for requesting location permissions, fetching GPS coordinates,
/// and reverse geocoding coordinates into structured address fields.
class LocationService {
  final Dio _dio;

  LocationService([Dio? dio]) : _dio = dio ?? Dio();

  /// Gets current GPS position and reverse geocodes it to a full address.
  Future<UserLocationResult> getCurrentLocationAndAddress() async {
    // 1. Check if location services (GPS) are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return UserLocationResult(
        isServiceDisabled: true,
        error: 'Location services (GPS) are turned off. Please turn on location services and try again.'.tr,
      );
    }

    // 2. Check and request location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return UserLocationResult(
          isPermissionDenied: true,
          error: 'Location permission was denied.'.tr,
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return UserLocationResult(
        isPermanentlyDenied: true,
        error: 'Location permission is permanently denied. Please enable it in app settings.'.tr,
      );
    }

    // 3. Fetch current GPS position
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
    } catch (_) {
      // Fallback to last known position if current fix times out
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        position = lastKnown;
      } else {
        return UserLocationResult(
          error: 'Could not obtain current location. Please make sure GPS is active.'.tr,
        );
      }
    }

    // 4. Reverse geocode coordinates to structured address
    return reverseGeocode(position.latitude, position.longitude);
  }

  /// Free-text place search for the address picker.
  ///
  /// Uses the Geocoding API rather than Places Autocomplete deliberately: this key
  /// is already proven against Geocoding (reverse lookup drives the pin), whereas
  /// Places is a separately-enabled product and would fail silently if it is not
  /// switched on. Geocoding accepts free text and returns several ranked matches,
  /// which is enough to find and jump to a place.
  Future<List<PlaceSuggestion>> searchPlaces(
    String query, {
    double? nearLat,
    double? nearLng,
  }) async {
    final text = query.trim();
    if (text.length < 3) return const [];

    final google = await _searchPlacesGoogle(text);
    if (google.isNotEmpty) return google;
    // Google refuses while the Cloud project has no billing (REQUEST_DENIED),
    // which left this search with no suggestions at all.
    return _searchPlacesOsm(text, nearLat: nearLat, nearLng: nearLng);
  }

  /// Place search over OpenStreetMap (Photon), limited to India and biased
  /// towards [nearLat]/[nearLng] when given.
  Future<List<PlaceSuggestion>> _searchPlacesOsm(
    String text, {
    double? nearLat,
    double? nearLng,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://photon.komoot.io/api/',
        queryParameters: {
          'q': text,
          'limit': 25,
          // India's bounding box, so results are Indian places rather than the
          // worldwide matches Photon ranks first (countrycode is still checked).
          'bbox': '68.1,6.5,97.5,35.7',
          if (nearLat != null && nearLng != null) ...{
            'lat': nearLat,
            'lon': nearLng,
          },
        },
        options: Options(headers: {'User-Agent': 'SuperAppUser/1.0'}),
      );
      final features = (response.data?['features'] as List?) ?? const [];
      final seen = <String>{};
      final results = <PlaceSuggestion>[];
      for (final raw in features) {
        final feature = raw as Map;
        final props = (feature['properties'] as Map?) ?? const {};
        if ((props['countrycode'] ?? '').toString().toUpperCase() != 'IN') {
          continue;
        }
        final coords = (feature['geometry'] as Map?)?['coordinates'] as List?;
        if (coords == null || coords.length < 2) continue;
        final description = [
          props['name'],
          props['street'],
          props['district'],
          props['city'],
          props['state'],
          props['postcode'],
        ]
            .whereType<Object>()
            .map((p) => p.toString().trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .join(', ');
        if (description.isEmpty || !seen.add(description.toLowerCase())) {
          continue;
        }
        results.add(PlaceSuggestion(
          description: description,
          latitude: (coords[1] as num).toDouble(),
          longitude: (coords[0] as num).toDouble(),
        ));
        if (results.length >= 8) break;
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  Future<List<PlaceSuggestion>> _searchPlacesGoogle(String text) async {
    final key = AppConstants.mapKey;
    if (key.isEmpty) return const [];

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {
          'address': text,
          'key': key,
          // Bias toward India so a bare locality name resolves somewhere sensible.
          'region': 'in',
        },
      );
      final data = response.data;
      if (data == null || data['status'] != 'OK') return const [];

      final results = (data['results'] as List?) ?? const [];
      return results.take(5).map((raw) {
        final item = raw as Map;
        final loc = (item['geometry'] as Map?)?['location'] as Map?;
        return PlaceSuggestion(
          description: (item['formatted_address'] ?? '').toString(),
          latitude: (loc?['lat'] as num?)?.toDouble() ?? 0,
          longitude: (loc?['lng'] as num?)?.toDouble() ?? 0,
        );
      }).where((p) => p.description.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Forward-geocodes a typed address into coordinates.
  ///
  /// Returns null when the address cannot be resolved, so the caller can decide
  /// what to fall back to rather than being handed a silently wrong point.
  Future<({double latitude, double longitude})?> geocodeAddress(String address) async {
    final query = address.trim();
    final key = AppConstants.mapKey;
    if (query.isEmpty || key.isEmpty) return null;

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://maps.googleapis.com/maps/api/geocode/json',
        queryParameters: {'address': query, 'key': key},
      );
      final data = response.data;
      if (data == null || data['status'] != 'OK') return null;

      final results = (data['results'] as List?) ?? const [];
      if (results.isEmpty) return null;

      final location = ((results.first as Map)['geometry'] as Map?)?['location'] as Map?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return (latitude: lat, longitude: lng);
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocodes [lat], [lng] into structured address components (Area, City, State)
  /// using Google Geocoding API, native device Geocoder, or OpenStreetMap Nominatim.
  Future<UserLocationResult> reverseGeocode(double lat, double lng) async {
    // 1. Try Google Maps Geocoding API if key is available
    final key = AppConstants.mapKey;
    if (key.isNotEmpty) {
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          'https://maps.googleapis.com/maps/api/geocode/json',
          queryParameters: {
            'latlng': '$lat,$lng',
            'key': key,
          },
        );

        final data = response.data;
        if (data != null && data['status'] == 'OK' && !(data['results'] as List?).isNullOrEmpty) {
          final results = data['results'] as List;
          final firstResult = results.first as Map<String, dynamic>;
          final formattedAddress = (firstResult['formatted_address'] ?? '').toString();
          final components = (firstResult['address_components'] as List?) ?? [];

          String buildingNumber = '';
          String route = '';
          String sublocality = '';
          String locality = '';
          String stateName = '';
          String postalCode = '';
          String landmarkName = '';

          for (final item in components) {
            if (item is Map) {
              final types = (item['types'] as List?)?.cast<String>() ?? [];
              final longName = (item['long_name'] ?? '').toString();

              if (types.contains('street_number') || types.contains('premise') || types.contains('subpremise')) {
                buildingNumber = longName;
              } else if (types.contains('route')) {
                route = longName;
              } else if (types.contains('sublocality') || types.contains('sublocality_level_1') || types.contains('neighborhood')) {
                if (sublocality.isEmpty) sublocality = longName;
              } else if (types.contains('locality') || types.contains('administrative_area_level_2')) {
                if (locality.isEmpty) locality = longName;
              } else if (types.contains('administrative_area_level_1')) {
                stateName = longName;
              } else if (types.contains('postal_code')) {
                postalCode = longName;
              } else if (types.contains('point_of_interest') || types.contains('establishment')) {
                landmarkName = longName;
              }
            }
          }

          final streetCombined = [buildingNumber, route].where((s) => s.isNotEmpty).join(' ');
          final areaName = sublocality.isNotEmpty
              ? sublocality
              : (locality.isNotEmpty ? locality : stateName);

          final fullParts = [
            if (sublocality.isNotEmpty) sublocality,
            if (locality.isNotEmpty && locality != sublocality) locality,
            if (stateName.isNotEmpty) stateName,
          ];
          final fullAddr = formattedAddress.isNotEmpty ? formattedAddress : fullParts.join(', ');

          return UserLocationResult(
            latitude: lat,
            longitude: lng,
            building: buildingNumber.isNotEmpty ? buildingNumber : (route.isNotEmpty ? route : 'Building'),
            street: route.isNotEmpty ? route : streetCombined,
            area: areaName,
            landmark: landmarkName,
            city: locality,
            state: stateName,
            pincode: postalCode,
            fullAddress: fullAddr,
          );
        }
      } catch (_) {}
    }

    // 2. Fallback to Flutter native geocoding (CLGeocoder / Android Geocoder)
    try {
      final placemarks = await geo.placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final sublocality = (place.subLocality ?? place.name ?? place.subAdministrativeArea ?? '').trim();
        final locality = (place.locality ?? place.subAdministrativeArea ?? '').trim();
        final stateName = (place.administrativeArea ?? '').trim();
        final postalCode = (place.postalCode ?? '').trim();
        final street = (place.thoroughfare ?? place.street ?? '').trim();

        final areaName = sublocality.isNotEmpty
            ? sublocality
            : (locality.isNotEmpty ? locality : stateName);

        final fullParts = [
          if (sublocality.isNotEmpty) sublocality,
          if (locality.isNotEmpty && locality != sublocality) locality,
          if (stateName.isNotEmpty) stateName,
        ];
        final fullAddr = fullParts.join(', ');

        if (areaName.isNotEmpty || locality.isNotEmpty) {
          return UserLocationResult(
            latitude: lat,
            longitude: lng,
            building: place.name ?? street,
            street: street,
            area: areaName,
            city: locality,
            state: stateName,
            pincode: postalCode,
            fullAddress: fullAddr.isNotEmpty ? fullAddr : '$areaName, $locality',
          );
        }
      }
    } catch (_) {}

    // 3. Fallback to OpenStreetMap Nominatim reverse geocoding API
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'json',
          'lat': lat,
          'lon': lng,
          'zoom': 18,
          'addressdetails': 1,
        },
        options: Options(headers: {'User-Agent': 'SuperAppUser/1.0'}),
      );

      final data = response.data;
      if (data != null && data['address'] != null) {
        final address = data['address'] as Map<String, dynamic>;
        final sublocality = (address['suburb'] ?? address['neighbourhood'] ?? address['residential'] ?? address['road'] ?? '').toString();
        final locality = (address['city'] ?? address['town'] ?? address['village'] ?? address['county'] ?? '').toString();
        final stateName = (address['state'] ?? '').toString();
        final postalCode = (address['postcode'] ?? '').toString();

        final areaName = sublocality.isNotEmpty
            ? sublocality
            : (locality.isNotEmpty ? locality : stateName);

        final fullParts = [
          if (sublocality.isNotEmpty) sublocality,
          if (locality.isNotEmpty && locality != sublocality) locality,
          if (stateName.isNotEmpty) stateName,
        ];
        final fullAddr = (data['display_name'] ?? fullParts.join(', ')).toString();

        return UserLocationResult(
          latitude: lat,
          longitude: lng,
          building: sublocality,
          street: (address['road'] ?? '').toString(),
          area: areaName,
          city: locality,
          state: stateName,
          pincode: postalCode,
          fullAddress: fullAddr,
        );
      }
    } catch (_) {}

    return UserLocationResult(
      latitude: lat,
      longitude: lng,
      fullAddress: 'Lat: ${lat.toStringAsFixed(4)}, Lng: ${lng.toStringAsFixed(4)}',
    );
  }
}

extension _ListExt on List? {
  bool get isNullOrEmpty => this == null || this!.isEmpty;
}
