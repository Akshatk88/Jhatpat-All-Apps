import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';
import 'onboarding_models.dart';

/// Public onboarding reads — callable before the partner has an account,
/// exactly like `/food/delivery/register` itself.
///
/// Paths are kept here rather than in `ApiEndpoints` on purpose: this feature
/// owns them, and the shared catalogue is edited by other work streams.
class OnboardingRepository {
  OnboardingRepository(this._dio);

  final Dio _dio;

  static const String optionsPath = '/food/delivery/onboarding/options';
  static const String requirementsPath =
      '/food/delivery/onboarding/requirements';
  static const String serviceLocationsPath = '/taxi/drivers/service-locations';
  static String checkVehiclePath(String number) =>
      '/food/delivery/check-vehicle/${Uri.encodeComponent(number)}';

  /// `GET /food/delivery/onboarding/options` → `data.classes[]`.
  Future<Result<List<OnboardingClass>, AppError>> getOptions() async {
    try {
      final res = await _dio.get(optionsPath);
      final data = _data(res.data);
      final raw = data['classes'];
      final classes = raw is List
          ? raw
                .whereType<Map>()
                .map((e) => OnboardingClass.fromJson(Map<String, dynamic>.from(e)))
                .where((c) => c.key.isNotEmpty)
                .toList()
          : <OnboardingClass>[];
      return Result.success(classes);
    } on DioException catch (e) {
      return Result.failure(mapDioError(e));
    } on FormatException catch (e) {
      return Result.failure(UnknownError(e.message));
    }
  }

  /// `GET /food/delivery/onboarding/requirements?driverClass=&intents=a,b`.
  Future<Result<OnboardingRequirements, AppError>> getRequirements(
    RequirementsQuery query,
  ) async {
    try {
      final res = await _dio.get(
        requirementsPath,
        queryParameters: {
          'driverClass': query.driverClass,
          if (query.intentsCsv.isNotEmpty) 'intents': query.intentsCsv,
        },
      );
      return Result.success(OnboardingRequirements.fromJson(_data(res.data)));
    } on DioException catch (e) {
      return Result.failure(mapDioError(e));
    } on FormatException catch (e) {
      return Result.failure(UnknownError(e.message));
    }
  }

  /// `GET /food/delivery/check-vehicle/:number` → `{ isAvailable, message }`.
  ///
  /// Not wrapped in `data` — the route answers at the top level.
  Future<Result<VehicleAvailability, AppError>> checkVehicle(
    String number,
  ) async {
    try {
      final res = await _dio.get(checkVehiclePath(number));
      final body = res.data;
      if (body is! Map) {
        return Result.failure(UnknownError('Unexpected response'));
      }
      return Result.success(
        VehicleAvailability(
          isAvailable: body['isAvailable'] != false,
          message: (body['message'] as String?) ?? '',
        ),
      );
    } on DioException catch (e) {
      return Result.failure(mapDioError(e));
    }
  }

  /// `GET /taxi/drivers/service-locations` → `data.results[]`: the operating
  /// cities the admin has switched on. Public, like the other reads here.
  /// Only the names are used — `/food/delivery/register` takes `city` as text.
  Future<Result<List<String>, AppError>> getOperatingCities() async {
    try {
      final res = await _dio.get(serviceLocationsPath);
      final raw = _data(res.data)['results'];
      final seen = <String>{};
      final names = <String>[];
      if (raw is List) {
        for (final e in raw.whereType<Map>()) {
          final name = _cityName(e);
          if (name.isNotEmpty && seen.add(name.toLowerCase())) names.add(name);
        }
      }
      names.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return Result.success(names);
    } on DioException catch (e) {
      return Result.failure(mapDioError(e));
    } on FormatException catch (e) {
      return Result.failure(UnknownError(e.message));
    }
  }

  static String _cityName(Map e) {
    for (final k in const ['service_location_name', 'name']) {
      final v = e[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return '';
  }

  Map<String, dynamic> _data(Object? body) {
    if (body is Map && body['data'] is Map) {
      return Map<String, dynamic>.from(body['data'] as Map);
    }
    throw const FormatException('Unexpected response from server');
  }
}

class VehicleAvailability {
  const VehicleAvailability({required this.isAvailable, required this.message});
  final bool isAvailable;
  final String message;
}

/// The server's own `message` when there is one, else Dio's.
AppError mapDioError(DioException e) {
  final body = e.response?.data;
  String? message;
  if (body is Map) {
    final m = body['message'] ?? body['error'];
    if (m is String && m.trim().isNotEmpty) message = m;
  }
  if (message == null) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        message = 'The connection timed out. Please try again.';
      case DioExceptionType.connectionError:
        message = 'No internet connection. Please check your network.';
      default:
        message = e.message ?? 'Something went wrong';
    }
  }
  return NetworkError(message);
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(ref.read(dioProvider));
});
