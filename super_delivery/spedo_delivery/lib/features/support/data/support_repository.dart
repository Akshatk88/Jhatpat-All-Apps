import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/api_envelope.dart';
import '../../../core/network/dio_client.dart';

class SupportRepository {
  SupportRepository(this._dio);

  final Dio _dio;

  Future<Result<Map<String, dynamic>, AppError>> createSupportTicket({
    required String subject,
    required String description,
    String? category,
    String? orderId,
  }) => _post(ApiEndpoints.supportTickets, {
    'subject': subject,
    'description': description,
    if (category != null) 'category': category,
    if (orderId != null) 'orderId': orderId,
  });

  Future<Result<List<Map<String, dynamic>>, AppError>>
  getSupportTickets() => _getList(ApiEndpoints.supportTickets);

  Future<Result<Map<String, dynamic>, AppError>> getSupportTicketDetails(
    String id,
  ) => _get(ApiEndpoints.supportTicketDetails(id));

  Future<Result<Map<String, dynamic>, AppError>> createEmergencyRequest({
    required String orderId,
    required String reason,
    String? notes,
  }) => _post(ApiEndpoints.emergencyRequests, {
    'orderId': orderId,
    'reason': reason,
    if (notes != null) 'notes': notes,
  });

  Future<Result<List<Map<String, dynamic>>, AppError>>
  getEmergencyRequests() => _getList(ApiEndpoints.emergencyRequests);

  Future<Result<Map<String, dynamic>, AppError>> getEmergencyRequestDetails(
    String id,
  ) => _get(ApiEndpoints.emergencyRequestDetails(id));

  Future<Result<Map<String, dynamic>, AppError>> getEmergencyHelp() =>
      _get(ApiEndpoints.emergencyHelp);

  Future<Result<Map<String, dynamic>, AppError>> _get(String path) async {
    try {
      final res = await _dio.get(path);
      return Result.success(ApiEnvelope.map(res.data));
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  Future<Result<List<Map<String, dynamic>>, AppError>> _getList(
    String path,
  ) async {
    try {
      final res = await _dio.get(path);
      // List endpoints nest the array under a named key:
      // support-tickets -> data.tickets, order-emergency-requests -> data.requests.
      return Result.success(
        ApiEnvelope.list(res.data, keys: const ['tickets', 'requests']),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  Future<Result<Map<String, dynamic>, AppError>> _post(
    String path,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _dio.post(path, data: data);
      return Result.success(ApiEnvelope.map(res.data));
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

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.read(dioProvider));
});
