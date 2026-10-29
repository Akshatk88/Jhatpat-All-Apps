import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:food_user_application/core/error/result.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../auth/application/auth_controller.dart';
import '../../../auth/application/auth_state.dart';
import '../../application/ride_wallet_providers.dart';
import '../../data/ride_wallet_repository.dart';
import 'money_ui.dart';

/// "Ride wallet" card on the Pocket screen, for riders approved for rides or
/// parcel. Balance and history from `GET /taxi/drivers/wallet`, top-up through
/// Razorpay (or PhonePe), and withdrawal requests.
///
/// Renders nothing for a food-only rider, or when k9 says the account has no
/// taxi driver behind it.
class RideWalletSection extends ConsumerStatefulWidget {
  const RideWalletSection({super.key});

  @override
  ConsumerState<RideWalletSection> createState() => _RideWalletSectionState();
}

enum _Gateway { razorpay, phonePe }

class _RideWalletSectionState extends ConsumerState<RideWalletSection> {
  static const _previewCount = 5;

  late final Razorpay _razorpay;
  bool _busy = false;
  bool _showAllTransactions = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  RideWalletRepository get _repo => ref.read(rideWalletRepositoryProvider);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _reload() => ref.invalidate(rideWalletSnapshotProvider);

  // ---------------------------------------------------------------- top-up

  Future<void> _startTopUp(RideWallet wallet) async {
    final gateway = await _pickGateway();
    if (gateway == null || !mounted) return;

    final min = wallet.minimumTopUpAmount;
    final suggested = wallet.shortfall > 0 ? wallet.shortfall.ceilToDouble() : 0.0;
    final quick = <double>{
      if (suggested >= min && suggested > 0) suggested,
      if (min > 0) min,
      for (final a in const [500.0, 1000.0, 2000.0])
        if (a >= min) a,
    }.take(4).toList();

    final amount = await showAmountDialog(
      context,
      title: 'Top up ride wallet',
      actionLabel: 'Pay',
      helper: [
        if (min > 0) 'Minimum ${formatRupeesShort(min)}',
        if (wallet.shortfall > 0)
          'Add ${formatRupees(wallet.shortfall)} to keep receiving rides',
      ].join(' · ').ifEmpty(null),
      min: min,
      quickAmounts: quick,
    );
    if (amount == null || !mounted) return;

    switch (gateway) {
      case _Gateway.razorpay:
        await _topUpRazorpay(amount);
      case _Gateway.phonePe:
        await _topUpPhonePe(amount);
    }
  }

  Future<_Gateway?> _pickGateway() {
    return showModalBottomSheet<_Gateway>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 8.h),
              child: Text(
                'Pay with',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('UPI, card or net banking'),
              subtitle: const Text('Razorpay'),
              onTap: () => Navigator.of(ctx).pop(_Gateway.razorpay),
            ),
            ListTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: const Text('PhonePe'),
              subtitle: const Text('Opens the PhonePe payment page'),
              onTap: () => Navigator.of(ctx).pop(_Gateway.phonePe),
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
  }

  Future<void> _topUpRazorpay(double amount) async {
    setState(() => _busy = true);
    final result = await _repo.createRazorpayOrder(amount);
    if (!mounted) return;
    result.when(
      success: (order) {
        if (order.isMock) {
          setState(() => _busy = false);
          _snack('Online payment is not available right now. Please try later.');
          return;
        }
        final auth = ref.read(authControllerProvider);
        final user = auth is AuthAuthenticated ? auth.user : null;
        try {
          _razorpay.open({
            'key': order.keyId,
            'order_id': order.orderId,
            'amount': order.amountPaise,
            'currency': order.currency,
            'name': 'Jhatpat Driver',
            'description': 'Ride wallet top-up',
            'theme': {'color': '#FFB800'},
            'prefill': {
              if (user != null && user.name.isNotEmpty) 'name': user.name,
              if (user?.email?.isNotEmpty == true) 'email': user!.email,
              'contact': user?.phone ?? '',
            },
          });
        } catch (_) {
          setState(() => _busy = false);
          _snack('Unable to open payment gateway');
        }
      },
      failure: (e) {
        setState(() => _busy = false);
        _snack(e.message);
      },
    );
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final orderId = response.orderId ?? '';
    final paymentId = response.paymentId ?? '';
    final signature = response.signature ?? '';
    if (orderId.isEmpty || paymentId.isEmpty || signature.isEmpty) {
      if (mounted) setState(() => _busy = false);
      _snack('Payment done, but confirmation was incomplete. '
          'It will reflect once verified.');
      _reload();
      return;
    }
    final result = await _repo.verifyRazorpay(
      orderId: orderId,
      paymentId: paymentId,
      signature: signature,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (_) => _snack('Ride wallet topped up'),
      failure: (e) => _snack(e.message),
    );
    _reload();
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (!mounted) return;
    setState(() => _busy = false);
    final message = response.message;
    _snack(message != null && message.isNotEmpty ? message : 'Payment cancelled');
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _topUpPhonePe(double amount) async {
    setState(() => _busy = true);
    final result = await _repo.createPhonePeOrder(amount);
    if (!mounted) return;
    final order = result.when(
      success: (order) => order,
      failure: (e) {
        _snack(e.message);
        return null;
      },
    );
    if (order == null) {
      setState(() => _busy = false);
      return;
    }

    final uri = Uri.tryParse(order.checkoutUrl);
    final launched = uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (!launched) {
      setState(() => _busy = false);
      _snack('Could not open PhonePe');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PhonePeStatusDialog(
        merchantTransactionId: order.merchantTransactionId,
        repository: _repo,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    _reload();
  }

  // ------------------------------------------------------------- withdraw

  Future<void> _startWithdraw(RideWalletSnapshot snapshot) async {
    final wallet = snapshot.wallet;
    final max = snapshot.maxWithdrawable;
    final min = wallet.minimumTransferAmount;
    if (max <= 0 || (min > 0 && max < min)) {
      _snack(min > 0
          ? 'You need at least ${formatRupeesShort(min)} in your ride balance to withdraw'
          : 'No ride balance available to withdraw');
      return;
    }

    final amount = await showAmountDialog(
      context,
      title: 'Withdraw ride earnings',
      actionLabel: 'Withdraw',
      helper: 'Available: ${formatRupees(max)}'
          '${min > 0 ? ' · Min: ${formatRupeesShort(min)}' : ''}\n'
          'Sent to your bank after admin approval.',
      min: min,
      max: max,
      maxError: 'Amount exceeds available ride balance',
    );
    if (amount == null || !mounted) return;

    setState(() => _busy = true);
    final result = await _repo.requestWithdrawal(amount);
    if (!mounted) return;
    setState(() => _busy = false);
    result.when(
      success: (message) {
        _snack(message);
        _reload();
      },
      failure: (e) => _snack(e.message),
    );
  }

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(hasRideCapabilityProvider)) return const SizedBox.shrink();

    final async = ref.watch(rideWalletSnapshotProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    final Widget content;
    if (async.hasValue && async.value == null) {
      return const SizedBox.shrink();
    } else if (async.hasValue) {
      content = _walletBody(async.value!, textColor, subText, isDark);
    } else if (async.hasError) {
      content = _errorBody(moneyErrorText(async.error!), textColor, subText);
    } else {
      content = Padding(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        child: const Center(
          child: CircularProgressIndicator(color: MoneyColors.yellow),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(20.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: MoneyColors.yellow.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(textColor, subText),
            SizedBox(height: 16.h),
            content,
          ],
        ),
      ),
    );
  }

  Widget _header(Color textColor, Color subText) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8.r),
          decoration: const BoxDecoration(
            color: MoneyColors.yellow,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.local_taxi_rounded, size: 18.sp, color: MoneyColors.black),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ride wallet',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.sp,
                  color: textColor,
                ),
              ),
              Text(
                'Rides & parcel',
                style: TextStyle(fontSize: 11.sp, color: subText),
              ),
            ],
          ),
        ),
        if (_busy)
          SizedBox(
            width: 18.r,
            height: 18.r,
            child: const CircularProgressIndicator(
              strokeWidth: 2,
              color: MoneyColors.yellow,
            ),
          ),
      ],
    );
  }

  Widget _errorBody(String message, Color textColor, Color subText) {
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, color: subText, size: 20.sp),
        SizedBox(width: 8.w),
        Expanded(
          child: Text(
            message,
            style: TextStyle(color: textColor, fontSize: 12.sp),
          ),
        ),
        TextButton(onPressed: _reload, child: const Text('Retry')),
      ],
    );
  }

  Widget _walletBody(
    RideWalletSnapshot snapshot,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    final wallet = snapshot.wallet;
    final negative = wallet.rideBalance < 0;
    final pending = snapshot.pendingWithdrawals;
    final blockMessage = wallet.blockMessage;
    final txns = _showAllTransactions
        ? snapshot.transactions
        : snapshot.transactions.take(_previewCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ride balance',
          style: TextStyle(fontSize: 12.sp, color: subText, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: 4.h),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatRupees(wallet.rideBalance),
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 24.sp,
              color: negative ? MoneyColors.red : textColor,
            ),
          ),
        ),
        if (negative) ...[
          SizedBox(height: 2.h),
          Text(
            'You owe commission on cash rides',
            style: TextStyle(fontSize: 11.sp, color: MoneyColors.red),
          ),
        ],
        if (wallet.minimumBalanceForOrders > 0) ...[
          SizedBox(height: 6.h),
          Text(
            'Minimum to receive rides: ${formatRupees(wallet.minimumBalanceForOrders)}',
            style: TextStyle(fontSize: 11.sp, color: subText),
          ),
        ],
        if (blockMessage != null || wallet.shortfall > 0) ...[
          SizedBox(height: 12.h),
          _banner(
            blockMessage ??
                'Add ${formatRupees(wallet.shortfall)} to keep receiving rides',
            isDark,
          ),
        ],
        SizedBox(height: 16.h),
        Row(
          children: [
            if (wallet.isWalletEnabled)
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : () => _startTopUp(wallet),
                  style: MoneyButtons.primary(),
                  icon: Icon(Icons.add_rounded, size: 18.sp),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Top up', maxLines: 1),
                  ),
                ),
              ),
            if (wallet.isWalletEnabled && wallet.isTransferEnabled)
              SizedBox(width: 12.w),
            if (wallet.isTransferEnabled)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _startWithdraw(snapshot),
                  style: MoneyButtons.outlined(textColor),
                  icon: Icon(Icons.account_balance_outlined, size: 18.sp),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Withdraw', maxLines: 1),
                  ),
                ),
              ),
          ],
        ),
        if (pending > 0) ...[
          SizedBox(height: 10.h),
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 14.sp, color: subText),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  '${formatRupees(pending)} withdrawal pending approval',
                  style: TextStyle(fontSize: 11.sp, color: subText),
                ),
              ),
            ],
          ),
        ],
        if (snapshot.transactions.isNotEmpty) ...[
          SizedBox(height: 18.h),
          Divider(height: 1, color: subText.withValues(alpha: 0.2)),
          SizedBox(height: 14.h),
          Text(
            'Recent ride transactions',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13.sp,
              color: textColor,
            ),
          ),
          SizedBox(height: 8.h),
          for (final t in txns) _transactionRow(t, textColor, subText),
          if (snapshot.transactions.length > _previewCount)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(
                  () => _showAllTransactions = !_showAllTransactions,
                ),
                child: Text(_showAllTransactions ? 'Show less' : 'View all'),
              ),
            ),
        ],
      ],
    );
  }

  Widget _banner(String message, bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: MoneyColors.yellow.withValues(alpha: isDark ? 0.18 : 0.15),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 16.sp,
              color: isDark ? MoneyColors.yellow : MoneyColors.black),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : MoneyColors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _transactionRow(
    RideWalletTransaction t,
    Color textColor,
    Color subText,
  ) {
    final date = t.createdAt;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          Icon(
            t.isCredit ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 16.sp,
            color: t.isCredit ? MoneyColors.green : MoneyColors.red,
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.sp, color: textColor),
                ),
                if (date != null)
                  Text(
                    _formatDate(date),
                    style: TextStyle(fontSize: 10.sp, color: subText),
                  ),
              ],
            ),
          ),
          SizedBox(width: 8.w),
          Text(
            '${t.isCredit ? '+' : '-'}${formatRupees(t.amount.abs())}',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: t.isCredit ? MoneyColors.green : MoneyColors.red,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

extension on String {
  String? ifEmpty(String? fallback) => isEmpty ? fallback : this;
}

/// Waits for the driver to come back from the PhonePe page, then asks k9
/// for the status (k9 credits the wallet when it reads COMPLETED).
class _PhonePeStatusDialog extends StatefulWidget {
  const _PhonePeStatusDialog({
    required this.merchantTransactionId,
    required this.repository,
  });

  final String merchantTransactionId;
  final RideWalletRepository repository;

  @override
  State<_PhonePeStatusDialog> createState() => _PhonePeStatusDialogState();
}

class _PhonePeStatusDialogState extends State<_PhonePeStatusDialog> {
  bool _checking = false;
  String? _message;
  PhonePeStatus? _status;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _message = null;
    });
    final result =
        await widget.repository.getPhonePeStatus(widget.merchantTransactionId);
    if (!mounted) return;
    result.when(
      success: (r) => setState(() {
        _checking = false;
        _status = r.status;
        _message = switch (r.status) {
          PhonePeStatus.paid => 'Payment received. Your ride wallet is updated.',
          PhonePeStatus.pending =>
            r.message ?? 'Payment is still pending. Check again in a moment.',
          PhonePeStatus.failed => r.message ?? 'Payment was not completed.',
        };
      }),
      failure: (e) => setState(() {
        _checking = false;
        _message = e.message;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final done = _status == PhonePeStatus.paid || _status == PhonePeStatus.failed;
    return AlertDialog(
      scrollable: true,
      title: const Text('PhonePe payment'),
      content: Text(
        _message ??
            'Complete the payment on the PhonePe page, then come back and tap '
                'Check status.',
      ),
      actions: [
        if (!done)
          TextButton(
            onPressed: _checking ? null : () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ElevatedButton(
          style: MoneyButtons.primary(),
          onPressed: _checking
              ? null
              : done
                  ? () => Navigator.of(context).pop()
                  : _check,
          child: _checking
              ? SizedBox(
                  width: 16.r,
                  height: 16.r,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    color: MoneyColors.black,
                  ),
                )
              : Text(done ? 'Done' : 'Check status'),
        ),
      ],
    );
  }
}
