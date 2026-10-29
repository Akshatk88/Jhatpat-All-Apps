import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

// Result's `when` resolves only where the declaring library is imported.
import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/features/main/presentation/screens/main_screen.dart';
import 'package:food_user_application/features/wallet/data/wallet_repository.dart';

/// Why the server is not offering this rider work, when the wallet is the
/// reason. Null when nothing blocks them.
class WalletBlock {
  const WalletBlock({
    required this.reason,
    required this.cashInHand,
    required this.cashLimit,
  });

  /// `below_minimum_balance` | `cash_limit_reached` | `wallet_disabled` | ''.
  final String reason;
  final double cashInHand;
  final double cashLimit;

  bool get cashLimitFull => cashLimit > 0 && cashInHand >= cashLimit;
}

/// Reads `GET /food/delivery/wallet`. Refreshed every few minutes by the
/// banner; failures read as "not blocked" so a flaky network never shows a
/// false alarm.
final walletBlockProvider = FutureProvider.autoDispose<WalletBlock?>((ref) async {
  final result = await ref.read(walletRepositoryProvider).getWallet();
  return result.when(
    success: (data) {
      final wallet = (data['wallet'] as Map?)?.cast<String, dynamic>() ?? data;
      double num(Object? v) => double.tryParse('${v ?? ''}') ?? 0;
      final cashInHand = num(wallet['cashInHand']);
      final cashLimit = num(wallet['totalCashLimit'] ?? wallet['cashLimit']);
      final blocked = wallet['isBlocked'] == true;
      final reason = (wallet['blockReason'] ?? '').toString();
      final limitFull = cashLimit > 0 && cashInHand >= cashLimit;
      if (!blocked && !limitFull) return null;
      return WalletBlock(
        reason: reason,
        cashInHand: cashInHand,
        cashLimit: cashLimit,
      );
    },
    failure: (_) => null,
  );
});

/// Red strip on the home screen saying the rider will not get some or all
/// requests, and why — instead of an online rider silently waiting forever.
class WalletBlockBanner extends ConsumerStatefulWidget {
  const WalletBlockBanner({super.key});

  @override
  ConsumerState<WalletBlockBanner> createState() => _WalletBlockBannerState();
}

class _WalletBlockBannerState extends ConsumerState<WalletBlockBanner> {
  Timer? _timer;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(minutes: 3),
      (_) => ref.invalidate(walletBlockProvider),
    );
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(walletBlockProvider),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = ref.watch(walletBlockProvider).value;
    if (block == null) return const SizedBox.shrink();

    final String title;
    final String body;
    if (block.cashLimitFull) {
      title = 'Cash limit reached';
      body = 'Cash in hand ₹${block.cashInHand.toStringAsFixed(0)} of '
          '₹${block.cashLimit.toStringAsFixed(0)}. Cash (COD) orders and rides '
          'will not come until you deposit cash.';
    } else if (block.reason == 'below_minimum_balance') {
      title = 'Wallet balance too low';
      body = 'Ride and parcel requests will not come until you add money to '
          'your wallet.';
    } else {
      title = 'Wallet blocked';
      body = 'Some requests will not come. Open Wallet or contact support.';
    }

    return Padding(
      padding: EdgeInsets.only(top: 12.h),
      child: Material(
        color: const Color(0xFFFEF3F2),
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          // The Wallet tab (Pocket) has Deposit and the ride-wallet top-up.
          onTap: () => ref.read(mainTabIndexProvider.notifier).setIndex(1),
          child: Container(
            padding: EdgeInsets.all(12.r),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: const Color(0xFFFDA29B)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.account_balance_wallet_rounded,
                    color: const Color(0xFFD92D20), size: 22.sp),
                SizedBox(width: 10.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFB42318),
                          fontWeight: FontWeight.w800,
                          fontSize: 13.sp,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        body,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFF912018),
                          fontSize: 11.5.sp,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: const Color(0xFFD92D20), size: 20.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
