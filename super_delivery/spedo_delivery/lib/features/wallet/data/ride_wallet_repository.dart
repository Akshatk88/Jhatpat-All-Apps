import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';

/// Taxi (ride / parcel) wallet endpoints under `/taxi/drivers`.
///
/// All of them sit behind k9's taxi `authenticate(["driver"])`. The delivery
/// app's food token (role `DELIVERY_PARTNER`) is accepted there through
/// `resolveUnifiedDriverIdentity`, but only for a partner that is linked to a
/// taxi Driver and approved — anyone else gets a 403, which the UI treats as
/// "no ride wallet" rather than an error.
class RideWalletEndpoints {
  RideWalletEndpoints._();

  /// GET → `{ wallet, transactions[50], withdrawalRequests[10], settings, summary }`.
  static const String wallet = '/taxi/drivers/wallet';

  /// POST `{ amount }` (rupees) → `{ keyId, orderId, amount (paise), currency }`.
  static const String razorpayOrder = '/taxi/drivers/wallet/top-up/razorpay/order';

  /// POST `{ razorpay_order_id, razorpay_payment_id, razorpay_signature }`
  /// → `{ wallet, transaction }`. The amount is read from the Razorpay order
  /// server-side, never from the app.
  static const String razorpayVerify = '/taxi/drivers/wallet/top-up/razorpay/verify';

  /// POST `{ amount }` → `{ merchantTransactionId, checkoutUrl, ... }`.
  static const String phonePeOrder = '/taxi/drivers/wallet/top-up/phonepe/order';

  /// GET → `{ status: paid | pending | failed, wallet? }`.
  static String phonePeStatus(String merchantTransactionId) =>
      '/taxi/drivers/wallet/top-up/phonepe/status/'
      '${Uri.encodeComponent(merchantTransactionId)}';

  /// POST `{ amount, payment_method }` → 201 `{ request, wallet }`.
  static const String withdrawals = '/taxi/drivers/wallet/withdrawals';
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

bool _flag(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v == null) return fallback;
  return ['1', 'true', 'yes', 'on'].contains(v.toString().trim().toLowerCase());
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// `serializeDriverWallet` from k9's taxi walletService.
class RideWallet {
  const RideWallet({
    required this.balance,
    required this.rideBalance,
    required this.cashInHand,
    required this.minimumBalanceForOrders,
    required this.isWalletEnabled,
    required this.isTransferEnabled,
    required this.minimumTopUpAmount,
    required this.minimumTransferAmount,
    required this.isBlocked,
    required this.blockReason,
  });

  /// The ONE withdrawable balance across rides and deliveries (k9's
  /// `getRiderFinance.walletBalance`). The Delivery wallet card shows the
  /// same figure as its pocket balance.
  final double balance;

  /// The taxi ledger on its own (`taxiSignedBalance`). Negative when the
  /// driver owes commission on cash rides. This is what ride dispatch checks
  /// against [minimumBalanceForOrders], and what an admin debits when a ride
  /// withdrawal is approved.
  final double rideBalance;

  final double cashInHand;
  final double minimumBalanceForOrders;
  final bool isWalletEnabled;
  final bool isTransferEnabled;
  final double minimumTopUpAmount;
  final double minimumTransferAmount;
  final bool isBlocked;

  /// `wallet_disabled | below_minimum_balance | cash_limit_reached |
  /// blocked_by_admin`, or empty.
  final String blockReason;

  /// How much more the ride balance needs to receive rides again.
  double get shortfall =>
      rideBalance < minimumBalanceForOrders ? minimumBalanceForOrders - rideBalance : 0;

  String? get blockMessage {
    if (!isBlocked) return null;
    switch (blockReason) {
      case 'below_minimum_balance':
        return 'Ride balance is below the minimum. Top up to keep receiving rides.';
      case 'cash_limit_reached':
        return 'Cash in hand has reached the limit. Deposit collected cash to continue.';
      case 'wallet_disabled':
        return 'Your ride wallet is disabled by admin.';
      case 'blocked_by_admin':
        return 'Your ride wallet is blocked by admin.';
      default:
        return 'Your ride wallet cannot accept rides right now.';
    }
  }

  factory RideWallet.fromJson(Map<String, dynamic> json) {
    final breakdown = json['breakdown'];
    final taxi = breakdown is Map ? breakdown['taxi'] : null;
    final signed = json['taxiSignedBalance'] ??
        (taxi is Map ? taxi['signedBalance'] : null) ??
        json['balance'];
    return RideWallet(
      balance: _num(json['balance']),
      rideBalance: _num(signed),
      cashInHand: _num(json['cashInHand']),
      minimumBalanceForOrders: _num(json['minimumBalanceForOrders']),
      isWalletEnabled: _flag(json['isWalletEnabled'], fallback: true),
      isTransferEnabled: _flag(json['isTransferEnabled'], fallback: true),
      minimumTopUpAmount: _num(json['minimumTopUpAmount']),
      minimumTransferAmount: _num(json['minimumTransferAmount']),
      isBlocked: _flag(json['isBlocked']),
      blockReason: json['blockReason']?.toString() ?? '',
    );
  }
}

/// A row of k9's taxi `WalletTransaction` (signed amount).
class RideWalletTransaction {
  const RideWalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    required this.createdAt,
    required this.balanceAfter,
  });

  final String id;

  /// `ride_earning | commission_deduction | top_up | adjustment`.
  final String type;
  final double amount;
  final String description;
  final DateTime? createdAt;
  final double balanceAfter;

  bool get isCredit => amount >= 0;

  String get title {
    if (description.trim().isNotEmpty) return description.trim();
    switch (type) {
      case 'ride_earning':
        return 'Ride earning';
      case 'commission_deduction':
        return 'Commission on cash ride';
      case 'top_up':
        return 'Wallet top-up';
      default:
        return 'Wallet adjustment';
    }
  }

  factory RideWalletTransaction.fromJson(Map<String, dynamic> json) =>
      RideWalletTransaction(
        id: (json['_id'] ?? json['id'] ?? '').toString(),
        type: json['type']?.toString() ?? '',
        amount: _num(json['amount']),
        description: json['description']?.toString() ?? '',
        createdAt: _date(json['createdAt']),
        balanceAfter: _num(json['balanceAfter']),
      );
}

/// A taxi `WithdrawalRequest` (`pending | completed | rejected ...`).
class RideWithdrawalRequest {
  const RideWithdrawalRequest({
    required this.id,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final double amount;
  final String status;
  final DateTime? createdAt;

  bool get isPending => status.toLowerCase() == 'pending';

  factory RideWithdrawalRequest.fromJson(Map<String, dynamic> json) =>
      RideWithdrawalRequest(
        id: (json['_id'] ?? json['id'] ?? '').toString(),
        amount: _num(json['amount']),
        status: json['status']?.toString() ?? 'pending',
        createdAt: _date(json['createdAt']),
      );
}

class RideWalletSnapshot {
  const RideWalletSnapshot({
    required this.wallet,
    required this.transactions,
    required this.withdrawalRequests,
  });

  final RideWallet wallet;
  final List<RideWalletTransaction> transactions;
  final List<RideWithdrawalRequest> withdrawalRequests;

  double get pendingWithdrawals => withdrawalRequests
      .where((r) => r.isPending)
      .fold<double>(0, (sum, r) => sum + r.amount);

  /// The most a ride withdrawal can ask for and still be approvable.
  ///
  /// k9 accepts any amount up to the combined [RideWallet.balance] at request
  /// time, but the admin approval debits the taxi ledger alone and refuses
  /// anything above it — so a request is only honoured up to the ride
  /// balance, less what is already pending.
  double get maxWithdrawable {
    final ride = wallet.rideBalance - pendingWithdrawals;
    final cap = ride < wallet.balance ? ride : wallet.balance;
    return cap > 0 ? (cap * 100).floorToDouble() / 100 : 0;
  }
}

/// What the app needs to open Razorpay checkout for a top-up.
class RideTopUpOrder {
  const RideTopUpOrder({
    required this.keyId,
    required this.orderId,
    required this.amountPaise,
    required this.currency,
  });

  final String keyId;
  final String orderId;
  final int amountPaise;
  final String currency;

  /// k9 falls back to a `mock_order_…` id when its Razorpay keys are rejected.
  /// Razorpay checkout cannot pay such an order, so the app must not open it.
  bool get isMock => orderId.startsWith('mock_order_');
}

class PhonePeTopUpOrder {
  const PhonePeTopUpOrder({
    required this.merchantTransactionId,
    required this.checkoutUrl,
  });

  final String merchantTransactionId;
  final String checkoutUrl;
}

enum PhonePeStatus { paid, pending, failed }

class PhonePeStatusResult {
  const PhonePeStatusResult(this.status, this.message);

  final PhonePeStatus status;
  final String? message;
}

/// The account has no (approved, linked) taxi driver behind it, so the ride
/// wallet does not apply. The UI hides the section instead of erroring.
class RideWalletUnavailable extends AppError {
  RideWalletUnavailable(super.message);
}

class RideWalletRepository {
  RideWalletRepository(this._dio);

  final Dio _dio;

  Future<Result<RideWalletSnapshot, AppError>> getWallet() async {
    try {
      final res = await _dio.get(RideWalletEndpoints.wallet);
      final data = _data(res.data);
      final walletJson = data['wallet'];
      if (walletJson is! Map<String, dynamic>) {
        return Result.failure(RideWalletUnavailable('No ride wallet'));
      }
      List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) parse) =>
          raw is List
              ? raw.whereType<Map<String, dynamic>>().map(parse).toList()
              : <T>[];
      return Result.success(
        RideWalletSnapshot(
          wallet: RideWallet.fromJson(walletJson),
          transactions:
              list(data['transactions'], RideWalletTransaction.fromJson),
          withdrawalRequests:
              list(data['withdrawalRequests'], RideWithdrawalRequest.fromJson),
        ),
      );
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      // 403 "Insufficient permissions" / 404 "Driver not found": a food-only
      // partner with no linked taxi driver.
      if (code == 403 || code == 404) {
        return Result.failure(RideWalletUnavailable(_message(e)));
      }
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Future<Result<RideTopUpOrder, AppError>> createRazorpayOrder(
    double amount,
  ) async {
    try {
      final res = await _dio.post(
        RideWalletEndpoints.razorpayOrder,
        data: {'amount': amount},
      );
      final data = _data(res.data);
      final keyId = data['keyId']?.toString() ?? '';
      final orderId = data['orderId']?.toString() ?? '';
      if (keyId.isEmpty || orderId.isEmpty) {
        return Result.failure(
          NetworkError('Payment gateway is not configured. Try again later.'),
        );
      }
      return Result.success(
        RideTopUpOrder(
          keyId: keyId,
          orderId: orderId,
          amountPaise: _num(data['amount']).round(),
          currency: data['currency']?.toString() ?? 'INR',
        ),
      );
    } on DioException catch (e) {
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Future<Result<RideWallet?, AppError>> verifyRazorpay({
    required String orderId,
    required String paymentId,
    required String signature,
  }) async {
    try {
      final res = await _dio.post(
        RideWalletEndpoints.razorpayVerify,
        data: {
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );
      final wallet = _data(res.data)['wallet'];
      return Result.success(
        wallet is Map<String, dynamic> ? RideWallet.fromJson(wallet) : null,
      );
    } on DioException catch (e) {
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Future<Result<PhonePeTopUpOrder, AppError>> createPhonePeOrder(
    double amount,
  ) async {
    try {
      final res = await _dio.post(
        RideWalletEndpoints.phonePeOrder,
        data: {'amount': amount},
      );
      final data = _data(res.data);
      final txnId = data['merchantTransactionId']?.toString() ?? '';
      final url = data['checkoutUrl']?.toString() ?? '';
      if (txnId.isEmpty || url.isEmpty) {
        return Result.failure(NetworkError('PhonePe did not return a payment link'));
      }
      return Result.success(
        PhonePeTopUpOrder(merchantTransactionId: txnId, checkoutUrl: url),
      );
    } on DioException catch (e) {
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Future<Result<PhonePeStatusResult, AppError>> getPhonePeStatus(
    String merchantTransactionId,
  ) async {
    try {
      final res = await _dio.get(
        RideWalletEndpoints.phonePeStatus(merchantTransactionId),
      );
      final body = res.data;
      final data = _data(body);
      final message = body is Map ? body['message']?.toString() : null;
      final status = switch (data['status']?.toString()) {
        'paid' => PhonePeStatus.paid,
        'pending' => PhonePeStatus.pending,
        _ => PhonePeStatus.failed,
      };
      return Result.success(PhonePeStatusResult(status, message));
    } on DioException catch (e) {
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Future<Result<String, AppError>> requestWithdrawal(double amount) async {
    try {
      final res = await _dio.post(
        RideWalletEndpoints.withdrawals,
        data: {'amount': amount, 'payment_method': 'bank_transfer'},
      );
      final body = res.data;
      final message = body is Map ? body['message']?.toString() : null;
      return Result.success(message ?? 'Withdrawal request sent');
    } on DioException catch (e) {
      return Result.failure(NetworkError(_message(e)));
    }
  }

  Map<String, dynamic> _data(dynamic body) {
    if (body is Map<String, dynamic>) {
      final data = body['data'];
      if (data is Map<String, dynamic>) return data;
    }
    return const {};
  }
}

String _message(DioException e) {
  final data = e.response?.data;
  if (data is Map) {
    final msg = data['message'] ?? data['error'];
    if (msg is String && msg.trim().isNotEmpty) return msg;
  }
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout) {
    return 'No internet connection. Please try again.';
  }
  return e.message ?? 'Something went wrong';
}

/// Shared server-message extraction for the money features.
String rideMoneyErrorMessage(DioException e) => _message(e);

final rideWalletRepositoryProvider = Provider<RideWalletRepository>((ref) {
  return RideWalletRepository(ref.read(dioProvider));
});
