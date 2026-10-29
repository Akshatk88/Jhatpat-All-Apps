import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';
import 'models/scheduled_ride.dart';

class ScheduledRidesPage {
  const ScheduledRidesPage({required this.rides, required this.hasNextPage});

  final List<ScheduledRide> rides;
  final bool hasNextPage;
}

/// Upcoming scheduled taxi/parcel bookings for this driver.
///
/// Both routes are `authenticate(['driver'])`; this app's delivery-partner
/// token is accepted through the unified driver bridge when the partner is
/// linked to a taxi driver.
class ScheduledRidesRepository {
  ScheduledRidesRepository(this._dio);

  final Dio _dio;

  /// `GET ?page&limit` (limit capped at 100 server-side). Returns rides with
  /// `scheduledAt` in the future that are either open in the driver's zone and
  /// vehicle type, or already assigned to this driver.
  static const String _list = '/taxi/drivers/scheduled-rides';

  /// `POST`, no body. Only rides assigned to this driver and still in the
  /// future; the server may apply a driver cancellation fee.
  static String _cancel(String rideId) =>
      '/taxi/drivers/scheduled-rides/$rideId/cancel';

  Future<Result<ScheduledRidesPage, AppError>> list({
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final res = await _dio.get(
        _list,
        queryParameters: {'page': page, 'limit': limit},
      );
      final data = _unwrap(res.data);
      final results = data is Map ? data['results'] : data;
      final pagination = data is Map ? data['pagination'] : null;
      return Result.success(
        ScheduledRidesPage(
          rides: (results is List ? results : const [])
              .whereType<Map>()
              .map((e) => ScheduledRide.fromJson(Map<String, dynamic>.from(e)))
              .where((r) => r.id.isNotEmpty)
              .toList(growable: false),
          hasNextPage: pagination is Map && pagination['hasNextPage'] == true,
        ),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  /// Returns the server's confirmation message when it sends one.
  Future<Result<String?, AppError>> cancel(String rideId, {String? reason}) async {
    try {
      final res = await _dio.post(
        _cancel(rideId),
        data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
      );
      final body = res.data;
      return Result.success(body is Map ? body['message']?.toString() : null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  static dynamic _unwrap(dynamic body) {
    if (body is Map<String, dynamic> && body.containsKey('data')) {
      return body['data'];
    }
    return body;
  }

  AppError _mapError(DioException e) {
    final data = e.response?.data;
    final message = data is Map
        ? (data['message'] ?? data['error'])?.toString()
        : null;
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return NetworkError(message ?? 'No connection. Check your network.');
    }
    return UnknownError(message ?? 'Something went wrong. Please try again.');
  }
}

final scheduledRidesRepositoryProvider = Provider<ScheduledRidesRepository>((ref) {
  return ScheduledRidesRepository(ref.read(dioProvider));
});
