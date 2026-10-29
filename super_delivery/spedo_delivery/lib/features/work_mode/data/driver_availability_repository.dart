import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';

/// The **taxi** side of going online.
///
/// Deliberately separate from `ProfileRepository.updateAvailability`, which
/// writes the food delivery-partner document. Taxi dispatch
/// (`matchingService.js:79`) and ride acceptance (`rideService.js:1739`) both
/// filter on `Driver.isOnline`, a different field on a different collection —
/// so a driver who only calls the food endpoint is online for food orders and
/// permanently invisible to ride dispatch.
class DriverAvailabilityRepository {
  DriverAvailabilityRepository(this._dio);

  final Dio _dio;

  Future<Result<void, AppError>> goOnline({
    required double lat,
    required double lng,
  }) async {
    try {
      await _dio.patch(
        ApiEndpoints.driverOnline,
        data: {
          // GeoJSON order. The server validates the ranges, so a swapped pair
          // is accepted anywhere both values are plausible — which is most of
          // India — and silently mislocates the driver.
          'location': [lng, lat],
        },
      );
      return const Result.success(null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<void, AppError>> goOffline() async {
    try {
      await _dio.patch(ApiEndpoints.driverOffline);
      return const Result.success(null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  AppError _mapError(DioException e) {
    final data = e.response?.data;
    final message = data is Map
        ? (data['message'] ?? data['error'])?.toString()
        : null;
    return NetworkError(message ?? e.message ?? 'Could not update ride status');
  }
}

final driverAvailabilityRepositoryProvider =
    Provider<DriverAvailabilityRepository>((ref) {
  return DriverAvailabilityRepository(ref.read(dioProvider));
});
