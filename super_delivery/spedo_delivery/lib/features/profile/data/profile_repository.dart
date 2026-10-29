import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/network/dio_client.dart';
import '../../auth/data/models/delivery_partner.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  Future<Result<DeliveryPartner, AppError>> updateProfile(
    Map<String, dynamic> fields,
  ) => _patch(ApiEndpoints.profile, fields);

  Future<Result<DeliveryPartner, AppError>> updateProfileDetails(
    Map<String, dynamic> fields,
  ) => _patch(ApiEndpoints.profileDetails, fields);

  Future<Result<DeliveryPartner, AppError>> updateBankDetails({
    required String accountHolderName,
    required String accountNumber,
    required String ifscCode,
    required String bankName,
    String? upiId,
  }) => _patch(ApiEndpoints.profileBankDetails, {
    // The validator and service read `documents.bankDetails.*` only; flat
    // `bankAccountNumber`-style keys were stripped and nothing was saved.
    'documents': {
      'bankDetails': {
        'accountHolderName': accountHolderName,
        'accountNumber': accountNumber,
        'ifscCode': ifscCode,
        'bankName': bankName,
        'upiId': ?upiId,
      },
    },
  });

  Future<Result<DeliveryPartner, AppError>> uploadProfilePhotoBase64(
    String base64Image,
  ) =>
      // Backend: POST (not PATCH) with `{ base64, mimeType }`, answers `{ partner }`.
      _send(
        ApiEndpoints.profilePhotoBase64,
        {'base64': base64Image, 'mimeType': 'image/jpeg'},
        post: true,
      );

  Future<Result<DeliveryPartner, AppError>> updateAvailability(
    bool isOnline, {
    double? lat,
    double? lng,
  }) => _patch(ApiEndpoints.availability, {
    'status': isOnline ? 'online' : 'offline',
    // Backend reads `latitude`/`longitude` (DELIVERY_API_SPEC.md §3) — `lat`/`lng`
    // are silently ignored, leaving lastLat/lastLng unset and the partner
    // invisible to dispatch's nearby-partner radius search.
    if (lat != null) 'latitude': lat,
    if (lng != null) 'longitude': lng,
  });

  Future<Result<void, AppError>> deleteAccount() async {
    try {
      await _dio.delete(ApiEndpoints.deleteAccount);
      return const Result.success(null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  /// `POST /food/delivery/reverify` (approved partners only). The backend
  /// answers `{ success, message }` with no `data`, so the reply is the
  /// message — reading `data` as a partner threw on every call.
  Future<Result<String, AppError>> reverify(FormData formData) async {
    try {
      final res = await _dio.post(ApiEndpoints.reverify, data: formData);
      final body = res.data;
      final message = body is Map ? body['message'] as String? : null;
      return Result.success(message ?? 'Submitted');
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  Future<Result<DeliveryPartner, AppError>> _patch(
    String path,
    Map<String, dynamic> data,
  ) => _send(path, data);

  Future<Result<DeliveryPartner, AppError>> _send(
    String path,
    Map<String, dynamic> data, {
    bool post = false,
  }) async {
    try {
      final res = post
          ? await _dio.post(path, data: data)
          : await _dio.patch(path, data: data);
      final body = ApiEnvelope.map(res.data);
      // Profile endpoints answer `{ user }` or `{ partner }` depending on route.
      final user = body['user'] ?? body['partner'] ?? body;
      return Result.success(DeliveryPartner.fromJson(user as Map<String, dynamic>));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
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

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.read(dioProvider));
});
