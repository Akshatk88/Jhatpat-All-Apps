import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';

/// Which end of a parcel job a proof photo belongs to. The wire values are the
/// only two `addParcelPhotos` accepts (`stage must be pickup or delivery`).
enum ParcelProofStage {
  pickup('pickup'),
  delivery('delivery');

  const ParcelProofStage(this.wire);
  final String wire;
}

/// Captain-side parcel proof photos.
///
/// The backend takes them in two steps, and this mirrors that rather than
/// inventing a multipart call it does not have:
///  1. `POST /taxi/users/parcel-photo { dataUrl }` hosts one image and returns
///     `{ secureUrl, publicId }` (no auth middleware; the same route the
///     customer app uses at booking).
///  2. `POST /taxi/rides/:rideId/parcel-photos { stage, photos: [url] }`
///     (`authenticate(['driver'])`, assigned captain only) appends up to 4 http
///     URLs to `parcel.pickupPhotos` / `parcel.deliveryPhotos` and pushes a
///     `ride:state` to the customer. Photos are appended, never replaced.
///
/// Neither ride status transition checks for these photos server-side.
class ParcelProofRepository {
  ParcelProofRepository(this._dio);

  final Dio _dio;

  static const String _uploadPath = '/taxi/users/parcel-photo';
  static String _attachPath(String rideId) => '/taxi/rides/$rideId/parcel-photos';

  /// Hosts [file] and returns its URL.
  Future<Result<String, AppError>> upload(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final lower = file.path.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
      final res = await _dio.post(
        _uploadPath,
        data: {'dataUrl': 'data:$mime;base64,${base64Encode(bytes)}'},
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
      final data = _unwrap(res.data);
      final url = data is Map ? (data['secureUrl'] ?? data['url'])?.toString() : null;
      if (url == null || url.isEmpty) {
        return Result.failure(UnknownError('Photo upload did not return a link'));
      }
      return Result.success(url);
    } on DioException catch (e) {
      return Result.failure(_mapError(e));
    } on FileSystemException {
      return Result.failure(UnknownError('Could not read the photo. Take it again.'));
    } catch (e) {
      // Unexpected response shape: surface an error state, never a hung spinner.
      return Result.failure(UnknownError('Unexpected response from server'));
    }
  }

  /// Files [urls] against [stage] on the ride and returns the full list the
  /// server now holds for that stage.
  Future<Result<List<String>, AppError>> attach(
    String rideId,
    ParcelProofStage stage,
    List<String> urls,
  ) async {
    try {
      final res = await _dio.post(
        _attachPath(rideId),
        data: {'stage': stage.wire, 'photos': urls},
      );
      final data = _unwrap(res.data);
      final list = data is Map ? data['photos'] : null;
      final photos = list is List
          ? list.map((e) => e.toString()).toList(growable: false)
          : urls;
      return Result.success(photos);
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
    if (e.response?.statusCode == 413) {
      return UnknownError(message ?? 'Photo is too large. Take it again.');
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return NetworkError(message ?? 'No connection. Check your network.');
    }
    return UnknownError(message ?? 'Something went wrong. Please try again.');
  }
}

final parcelProofRepositoryProvider = Provider<ParcelProofRepository>((ref) {
  return ParcelProofRepository(ref.read(dioProvider));
});
