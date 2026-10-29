import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../wallet/presentation/widgets/money_ui.dart';
import '../../application/incentives_providers.dart';
import '../../../work_mode/application/work_mode_controller.dart';
import '../screens/incentives_screen.dart';

/// Pocket-screen entry to [IncentivesScreen]. Shows the most relevant line
/// ("12/20 rides — ₹200 bonus", or rewards ready to claim) and hides itself
/// while loading or when k9 has no incentive for this rider.
class IncentivesEntryCard extends ConsumerWidget {
  const IncentivesEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(incentivesOverviewProvider);
    final preferRides = ref.watch(currentWorkModeProvider).acceptsRides;
    final overview = async.value;
    final failed = async.hasError && overview == null;
    if (!failed && (overview == null || (overview.isEmpty && overview.errors.isEmpty))) {
      return const SizedBox.shrink();
    }

    final subtitle = failed || overview!.isEmpty
        ? 'Tap to view your bonuses'
        : _summary(overview, preferRides: preferRides);
    final claimable = overview?.claimableCount ?? 0;

    return Padding(
      padding: EdgeInsets.only(top: 16.h),
      child: Material(
        color: MoneyColors.black,
        borderRadius: BorderRadius.circular(24.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(24.r),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const IncentivesScreen()),
          ),
          child: Padding(
            padding: EdgeInsets.all(18.r),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(10.r),
                  decoration: const BoxDecoration(
                    color: MoneyColors.yellow,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.emoji_events_rounded,
                    color: MoneyColors.black,
                    size: 20.sp,
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Incentives',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15.sp,
                        ),
                      ),
                      SizedBox(height: 2.h),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: MoneyColors.yellow,
                          fontWeight: FontWeight.w600,
                          fontSize: 12.sp,
                        ),
                      ),
                    ],
                  ),
                ),
                if (claimable > 0) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: MoneyColors.yellow,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Text(
                      '$claimable',
                      style: TextStyle(
                        color: MoneyColors.black,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.sp,
                      ),
                    ),
                  ),
                ],
                SizedBox(width: 4.w),
                Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 22.sp),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _summary(IncentivesOverview o, {required bool preferRides}) {
    if (o.claimableCount > 0) {
      return '${o.claimableCount} reward${o.claimableCount == 1 ? '' : 's'} '
          'ready to claim · ${formatRupeesShort(o.claimableAmount)}';
    }
    final ladder = preferRides
        ? (o.taxiLadder ?? o.foodLadder)
        : (o.foodLadder ?? o.taxiLadder);
    if (ladder != null) {
      final unit = identical(ladder, o.taxiLadder) ? 'rides' : 'orders';
      final next = ladder.nextTier;
      if (next != null) {
        return '${ladder.completed}/${next.toOrders} $unit — '
            '${formatRupeesShort(next.rewardAmount)} bonus';
      }
      return 'All targets reached — ${formatRupeesShort(ladder.earned)} earned';
    }
    final inProgress = o.taxiRewards.where((r) => !r.isClaimed).length;
    return inProgress > 0
        ? '$inProgress ride reward${inProgress == 1 ? '' : 's'} in progress'
        : 'View your bonuses';
  }
}
