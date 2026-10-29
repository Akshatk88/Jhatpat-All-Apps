import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';
import 'ride_wallet_repository.dart';

/// Driver-raised UPI QR for collecting a ride fare (k9 `createDriverPaymentQr`
/// / `getDriverPaymentQrStatus`, both `authenticate(["driver"])`).
class RidePaymentQrEndpoints {
  RidePaymentQrEndpoints._();

  /// POST `{ rideId, amount }` (rupees, ≤ ₹5,00,000) →
  /// `{ id, status, imageUrl, linkUrl, amount, currency, closeBy, providerMode }`.
  /// `imageUrl` is a Razorpay-hosted PNG, or a `data:image/png;base64,…` URL
  /// when k9 fell back to a payment-link QR.
  static const String create = '/taxi/drivers/payments/qr';

  /// GET `?rideId=` → `{ status, paid, amount, currency, linkUrl, paidAt }`.
  /// Each call re-reads Razorpay and, once paid, credits the ride earnings.
  static const String status = '/taxi/drivers/payments/qr/status';
}

class RideQrPayment {
  const RideQrPayment({
    required this.id,
    required this.imageUrl,
    required this.linkUrl,
    required this.amount,
    required this.status,
    required this.closeBy,
  });

  final String id;
  final String imageUrl;
  final String linkUrl;
  final double amount;
  final String status;

  /// When Razorpay closes the QR (30 minutes after creation).
  final DateTime? closeBy;

  factory RideQrPayment.fromJson(Map<String, dynamic> json) {
    final close = json['closeBy'];
    return RideQrPayment(
      id: json['id']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      linkUrl: json['linkUrl']?.toString() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'active',
      closeBy: close is num
          ? DateTime.fromMillisecondsSinceEpoch(close.toInt() * 1000)
          : null,
    );
  }
}

class RideQrStatus {
  const RideQrStatus({required this.status, required this.paid});

  /// `active | paid | closed | cancelled | expired | failed | pending`.
  final String status;
  final bool paid;

  bool get isDead =>
      const {'closed', 'cancelled', 'expired', 'failed'}.contains(status);
}

class RidePaymentQrRepository {
  RidePaymentQrRepository(this._dio);

  final Dio _dio;

  Future<Result<RideQrPayment, AppError>> create({
    required String rideId,
    required double amount,
  }) async {
    try {
      final res = await _dio.post(
        RidePaymentQrEndpoints.create,
        data: {'rideId': rideId, 'amount': amount},
      );
      final data = res.data is Map<String, dynamic> ? res.data['data'] : null;
      if (data is! Map<String, dynamic> ||
          (data['imageUrl']?.toString() ?? '').isEmpty) {
        return Result.failure(NetworkError('Could not create a payment QR'));
      }
      return Result.success(RideQrPayment.fromJson(data));
    } on DioException catch (e) {
      return Result.failure(NetworkError(rideMoneyErrorMessage(e)));
    }
  }

  Future<Result<RideQrStatus, AppError>> status(String rideId) async {
    try {
      final res = await _dio.get(
        RidePaymentQrEndpoints.status,
        queryParameters: {'rideId': rideId},
      );
      final data = res.data is Map<String, dynamic> ? res.data['data'] : null;
      if (data is! Map<String, dynamic>) {
        return const Result.success(RideQrStatus(status: 'pending', paid: false));
      }
      final status = data['status']?.toString() ?? 'pending';
      return Result.success(
        RideQrStatus(status: status, paid: data['paid'] == true || status == 'paid'),
      );
    } on DioException catch (e) {
      return Result.failure(NetworkError(rideMoneyErrorMessage(e)));
    }
  }
}

final ridePaymentQrRepositoryProvider = Provider<RidePaymentQrRepository>((ref) {
  return RidePaymentQrRepository(ref.read(dioProvider));
});
