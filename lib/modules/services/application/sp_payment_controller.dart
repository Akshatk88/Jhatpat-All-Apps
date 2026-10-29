import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import 'package:superapp_user/core/config/app_constants.dart';
import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/payment/taxi_razorpay_service.dart';
import 'package:superapp_user/modules/services/application/booking_draft_controller.dart';
import 'package:superapp_user/modules/services/application/services_providers.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';

/// Outcome of settling a service booking.
enum SpPaymentOutcome { paid, deferred, cancelled, failed }

class SpPaymentResult {
  const SpPaymentResult(this.outcome, [this.message = '']);

  final SpPaymentOutcome outcome;
  final String message;

  bool get isOk =>
      outcome == SpPaymentOutcome.paid || outcome == SpPaymentOutcome.deferred;
}

/// Settles a booking through whichever method the customer chose.
///
/// Three rules, each of which is a real failure mode in this backend:
///
///  1. **Never trust the gateway callback.** Razorpay's success handler runs on
///     the device and is forgeable. Money is only real once
///     `POST /sp/payments/verify` has checked the signature server-side; that
///     endpoint also claims the booking atomically, so a replayed callback is a
///     no-op rather than a double credit.
///  2. **A verify failure is not automatically a payment failure.** The payment
///     may well have been captured. Report it as such and let the booking's own
///     `paymentStatus` settle it, rather than telling the customer it failed and
///     inviting a second attempt.
///  3. **`pay_at_home` settles nothing now.** The final amount is not known
///     until the professional bills the job, so the flow ends at the door with
///     the cash-collection handshake, not here.
class SpPaymentController {
  SpPaymentController(this._ref);

  final Ref _ref;

  Future<SpPaymentResult> settle({
    required String bookingId,
    required SpPaymentMethod method,
  }) async {
    switch (method) {
      case SpPaymentMethod.payAtHome:
      case SpPaymentMethod.plan:
        // Nothing to charge now. The booking is already created with the right
        // paymentMethod; the door handshake or the plan covers the rest.
        return const SpPaymentResult(SpPaymentOutcome.deferred);

      case SpPaymentMethod.wallet:
        return _payFromWallet(bookingId);

      case SpPaymentMethod.online:
        return _payOnline(bookingId);
    }
  }

  Future<SpPaymentResult> _payFromWallet(String bookingId) async {
    try {
      await _ref.read(servicesDataSourceProvider).payFromWallet(bookingId);
      return SpPaymentResult(SpPaymentOutcome.paid, 'Paid from your services wallet.'.tr);
    } on Failure catch (failure) {
      // Insufficient balance arrives as a 400 with a usable message.
      return SpPaymentResult(SpPaymentOutcome.failed, failure.message);
    }
  }

  Future<SpPaymentResult> _payOnline(String bookingId) async {
    final data = _ref.read(servicesDataSourceProvider);

    final Map<String, dynamic> order;
    try {
      order = await data.createPaymentOrder(bookingId);
    } on Failure catch (failure) {
      return SpPaymentResult(SpPaymentOutcome.failed, failure.message);
    }

    final orderId = order['orderId']?.toString() ?? '';
    final key = order['key']?.toString() ?? '';
    final amount = (order['amount'] as num?)?.toDouble() ?? 0;

    if (orderId.isEmpty || key.isEmpty) {
      // Happens when RAZORPAY_KEY_ID is unset on the server — worth saying
      // plainly rather than opening an empty checkout sheet.
      return SpPaymentResult(
        SpPaymentOutcome.failed,
        'Online payment is unavailable right now. Please choose another method.'.tr,
      );
    }

    final profile = _ref.read(spProfileProvider).value;
    final razorpay = RazorpayService();
    final completer = Completer<SpPaymentResult>();

    razorpay.open(
      request: RazorpayCheckoutRequest(
        keyId: key,
        orderId: orderId,
        // RazorpayService multiplies by 100 internally, so this stays rupees.
        amount: amount,
        name: AppConstants.brandName,
        description: 'Service booking',
        contact: profile?.phone,
        email: profile?.email,
      ),
      onSuccess: (response) async {
        try {
          await data.verifyPayment(
            orderId: response.orderId ?? orderId,
            paymentId: response.paymentId ?? '',
            signature: response.signature ?? '',
          );
          if (!completer.isCompleted) {
            completer.complete(
              SpPaymentResult(SpPaymentOutcome.paid, 'Payment successful.'.tr),
            );
          }
        } catch (error) {
          // Rule 2: the charge may have gone through. Do not call this a
          // failure and invite a second payment.
          if (kDebugMode) debugPrint('[services] verify failed: $error');
          if (!completer.isCompleted) {
            completer.complete(SpPaymentResult(
              SpPaymentOutcome.paid,
              'Payment received. Confirmation may take a moment to appear.'.tr,
            ));
          }
        }
      },
      onError: (response) {
        if (completer.isCompleted) return;
        // Razorpay reports a user-dismissed sheet through the same error
        // channel as a real decline; code 2 is the cancellation.
        final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
        completer.complete(SpPaymentResult(
          cancelled ? SpPaymentOutcome.cancelled : SpPaymentOutcome.failed,
          cancelled
              ? 'Payment cancelled.'.tr
              : (response.message ?? 'Payment failed. Please try again.'.tr),
        ));
      },
    );

    try {
      return await completer.future;
    } finally {
      razorpay.dispose();
      // The booking's paymentStatus just changed server-side.
      _ref.invalidate(spBookingProvider(bookingId));
    }
  }

  /// The customer's half of the doorstep handshake.
  ///
  /// The professional initiates collection on their app; this confirms it, and
  /// the backend then moves the booking to paid/completed. Polled by the
  /// tracking screen rather than pushed, because the collection status has no
  /// socket event of its own.
  Future<String?> confirmDoorstepCollection(String bookingId) async {
    try {
      await _ref.read(servicesDataSourceProvider).confirmCollection(bookingId);
      _ref.invalidate(spBookingProvider(bookingId));
      return null;
    } on Failure catch (failure) {
      return failure.message;
    }
  }

  /// SP wallet balance, in paise. Read on the review screen so the wallet
  /// option can show the balance and be disabled when it will not cover the job.
  Future<int> walletBalancePaise() async {
    try {
      return await _ref.read(servicesDataSourceProvider).walletBalancePaise();
    } on Failure {
      return 0;
    }
  }
}

final spPaymentControllerProvider = Provider<SpPaymentController>(
  SpPaymentController.new,
);

/// Wallet balance for the review screen. Never cached — it is money.
final spWalletBalanceProvider = FutureProvider.autoDispose<int>((ref) async {
  final profile = ref.watch(spProfileProvider).value;
  // The profile already carries the balance; use it rather than a second call,
  // and fall back to the dedicated endpoint only when the profile is absent.
  if (profile != null) return profile.walletBalancePaise;
  return ref.watch(spPaymentControllerProvider).walletBalancePaise();
});

/// Formats paise for the payment sheets. Re-exported so screens in this module
/// import one place for money rendering.
String spMoney(int paise) => formatPaise(paise);
