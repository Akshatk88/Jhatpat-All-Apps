import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/storage/token_storage.dart';
import 'models/auth_verify_result.dart';
import 'models/delivery_partner.dart';

class AuthRepository {
  AuthRepository(this._dio, this._tokenStorage);

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<Result<String, AppError>> requestOtp(String phone) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.requestOtp,
        data: {'phone': phone},
      );
      return Result.success(
        res.data['message'] as String? ?? 'OTP sent successfully',
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<AuthVerifyResult, AppError>> verifyOtp({
    required String phone,
    required String otp,
    String? fcmToken,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.verifyOtp,
        data: {
          'phone': phone,
          'otp': otp,
          if (fcmToken != null && fcmToken.isNotEmpty) 'fcmToken': fcmToken,
          'platform': 'mobile',
        },
      );
      final data = res.data['data'] as Map<String, dynamic>;
      final result = AuthVerifyResult.fromJson(data);
      if (result.isLoggedIn) {
        await _tokenStorage.saveTokens(
          accessToken: result.accessToken!,
          refreshToken: result.refreshToken!,
        );
      }
      return Result.success(result);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryPartner, AppError>> getMe() async {
    try {
      final res = await _dio.get(ApiEndpoints.me);
      final data = res.data['data'] as Map<String, dynamic>;
      final userJson = (data['user'] ?? data) as Map<String, dynamic>;
      return Result.success(DeliveryPartner.fromJson(userJson));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<DeliveryPartner, AppError>> register(
    FormData formData,
  ) async {
    try {
      // A photo per profile + up to two per document, uploaded on a phone
      // connection and then pushed to Cloudinary by the server one by one —
      // the client defaults (30s send / 20s receive) cut that off mid-way.
      final res = await _dio.post(
        ApiEndpoints.register,
        data: formData,
        options: Options(
          sendTimeout: const Duration(minutes: 3),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      final body = res.data;
      final data = body is Map ? body['data'] : null;
      if (data is! Map) {
        return Result.failure(
          NetworkError('Registration was sent but the reply was not understood'),
        );
      }
      return Result.success(
        DeliveryPartner.fromJson(Map<String, dynamic>.from(data)),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<Result<bool, AppError>> checkVehicleAvailable(String number) async {
    try {
      final res = await _dio.get(ApiEndpoints.checkVehicle(number));
      return Result.success(res.data['isAvailable'] as bool? ?? true);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    }
  }

  Future<void> logout() async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    try {
      await _dio.post(
        ApiEndpoints.logout,
        data: {if (refreshToken != null) 'refreshToken': refreshToken},
      );
    } catch (_) {
      // Ignore network errors on logout — tokens are cleared locally regardless.
    }
    await _tokenStorage.clear();
  }

  AppError _mapError(DioException e) {
    final responseData = e.response?.data;
    final message = responseData is Map<String, dynamic>
        ? (responseData['message'] as String? ??
              responseData['error'] as String? ??
              e.message ??
              'Something went wrong')
        : (e.message ?? 'Something went wrong');
    return NetworkError(message);
  }
}

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(dioProvider), ref.read(tokenStorageProvider));
});
