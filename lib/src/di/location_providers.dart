import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/src/platform/location/location_service.dart';

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});
