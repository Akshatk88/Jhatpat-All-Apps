import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';
import 'models/emergency_contact.dart';

/// Driver safety API on the taxi side.
///
/// All routes sit behind the taxi `authenticate` middleware, which accepts this
/// app's delivery-partner token by bridging it to the linked taxi driver
/// (`resolveUnifiedDriverIdentity`: role DELIVERY_PARTNER + approved partner
/// with a `driverId` -> role `driver`). A partner with no linked driver gets a
/// 403 "Insufficient permissions", surfaced as-is.
class SafetyRepository {
  SafetyRepository(this._dio);

  final Dio _dio;

  /// `authenticate(['driver', 'owner'])` -> `triggerDriverSosAlert`.
  static const String _sos = '/taxi/drivers/sos';

  /// `authenticate(['driver'])`: GET list, POST add, DELETE `/:contactId`.
  static const String _contacts = '/taxi/drivers/emergency-contacts';

  /// Raises an SOS with the admin safety desk (`new_sos` to admins).
  ///
  /// Every field is optional server-side. `location` is read as `{lat, lng}`;
  /// without it the server falls back to the ride's pickup point, so the live
  /// position is always sent when there is one. `serviceType` is one of
  /// ride | parcel | general.
  Future<Result<void, AppError>> triggerSos({
    String? rideId,
    String? serviceType,
    double? lat,
    double? lng,
    String? pickupAddress,
    String? dropAddress,
    String? notes,
  }) async {
    try {
      await _dio.post(
        _sos,
        data: {
          if (rideId != null && rideId.isNotEmpty) 'rideId': rideId,
          'serviceType': ?serviceType,
          if (lat != null && lng != null) 'location': {'lat': lat, 'lng': lng},
          if (pickupAddress != null && pickupAddress.isNotEmpty)
            'pickupAddress': pickupAddress,
          if (dropAddress != null && dropAddress.isNotEmpty)
            'dropAddress': dropAddress,
          if (notes != null && notes.isNotEmpty) 'notes': notes,
        },
      );
      return const Result.success(null);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  /// `{ data: { results: [{id, name, phone, source}], limit } }`.
  Future<Result<EmergencyContactList, AppError>> getContacts() async {
    try {
      final res = await _dio.get(_contacts);
      final data = _unwrap(res.data);
      final list = data is Map ? data['results'] : data;
      final limit = data is Map ? (data['limit'] as num?)?.toInt() : null;
      return Result.success(
        EmergencyContactList(
          contacts: (list is List ? list : const [])
              .whereType<Map>()
              .map((e) => EmergencyContact.fromJson(Map<String, dynamic>.from(e)))
              .toList(growable: false),
          limit: limit ?? EmergencyContactList.defaultLimit,
        ),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  /// Body `{ name, phone, source }`. The server keeps the last 10 digits of
  /// [phone], requires letters-only names, rejects duplicates (409) and caps
  /// the list (400) — its messages are passed through.
  Future<Result<EmergencyContact, AppError>> addContact({
    required String name,
    required String phone,
  }) async {
    try {
      final res = await _dio.post(
        _contacts,
        data: {'name': name, 'phone': phone, 'source': 'manual'},
      );
      final data = _unwrap(res.data);
      return Result.success(
        EmergencyContact.fromJson(
          data is Map ? Map<String, dynamic>.from(data) : const {},
        ),
      );
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  Future<Result<void, AppError>> deleteContact(String contactId) async {
    try {
      await _dio.delete('$_contacts/$contactId');
      return const Result.success(null);
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

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return SafetyRepository(ref.read(dioProvider));
});
