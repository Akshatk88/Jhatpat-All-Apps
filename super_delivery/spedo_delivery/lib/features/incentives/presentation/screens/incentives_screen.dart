import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:food_user_application/core/error/result.dart';

import '../../../wallet/application/ride_wallet_providers.dart';
import '../../../wallet/presentation/widgets/money_ui.dart';
import '../../application/incentives_providers.dart';
import '../../data/incentives_repository.dart';

/// Food order ladder, ride/parcel ladder and claimable ride rewards.
class IncentivesScreen extends ConsumerStatefulWidget {
  const IncentivesScreen({super.key});

  @override
  ConsumerState<IncentivesScreen> createState() => _IncentivesScreenState();
}

class _IncentivesScreenState extends ConsumerState<IncentivesScreen> {
  final Set<String> _claiming = {};

  Future<void> _refresh() async {
    ref.invalidate(incentivesOverviewProvider);
    await ref.read(incentivesOverviewProvider.future).catchError(
          (_) => const IncentivesOverview(),
        );
  }

  Future<void> _claim(TaxiReward reward) async {
    final id = '${reward.rewardType}:${reward.rewardKey}';
    if (_claiming.contains(id)) return;
    setState(() => _claiming.add(id));
    final result = await ref.read(incentivesRepositoryProvider).claim(reward);
    if (!mounted) return;
    setState(() => _claiming.remove(id));
    result.when(
      success: (amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${formatRupees(amount)} added to your ride wallet'),
          ),
        );
        ref.invalidate(incentivesOverviewProvider);
        ref.invalidate(rideWalletSnapshotProvider);
      },
      failure: (e) => ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(incentivesOverviewProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400]! : Colors.grey[600]!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Incentives',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18.sp),
        ),
        centerTitle: false,
      ),
      body: RefreshIndicator(
        color: MoneyColors.yellow,
        onRefresh: _refresh,
        child: async.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(
            child: CircularProgressIndicator(color: MoneyColors.yellow),
          ),
          error: (e, _) => _message(
            icon: Icons.error_outline_rounded,
            text: moneyErrorText(e),
            subText: subText,
            textColor: textColor,
            retry: true,
          ),
          data: (overview) {
            if (overview.isEmpty) {
              return _message(
                icon: overview.errors.isEmpty
                    ? Icons.emoji_events_outlined
                    : Icons.error_outline_rounded,
                text: overview.errors.isEmpty
                    ? 'No incentives are running for you right now.\nCheck back later.'
                    : overview.errors.first,
                subText: subText,
                textColor: textColor,
                retry: overview.errors.isNotEmpty,
              );
            }
            return _content(overview, theme, textColor, subText, isDark);
          },
        ),
      ),
    );
  }

  Widget _message({
    required IconData icon,
    required String text,
    required Color subText,
    required Color textColor,
    required bool retry,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24.r),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 44.sp, color: subText),
                  SizedBox(height: 12.h),
                  Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textColor, fontSize: 13.sp, height: 1.4),
                  ),
                  if (retry) ...[
                    SizedBox(height: 16.h),
                    ElevatedButton(
                      style: MoneyButtons.primary(),
                      onPressed: _refresh,
                      child: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    IncentivesOverview overview,
    ThemeData theme,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 40.h),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final error in overview.errors) ...[
                  _errorBanner(error, isDark),
                  SizedBox(height: 12.h),
                ],
                if (overview.foodLadder != null) ...[
                  _LadderCard(
                    ladder: overview.foodLadder!,
                    label: 'Food delivery',
                    unit: 'orders',
                    icon: Icons.delivery_dining_rounded,
                    textColor: textColor,
                    subText: subText,
                    surface: theme.colorScheme.surface,
                  ),
                  SizedBox(height: 16.h),
                ],
                if (overview.taxiLadder != null) ...[
                  _LadderCard(
                    ladder: overview.taxiLadder!,
                    label: 'Rides & parcel',
                    unit: 'rides',
                    icon: Icons.local_taxi_rounded,
                    textColor: textColor,
                    subText: subText,
                    surface: theme.colorScheme.surface,
                  ),
                  SizedBox(height: 16.h),
                ],
                if (overview.taxiRewards.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(left: 4.w, bottom: 10.h, top: 4.h),
                    child: Text(
                      'Ride rewards',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.sp,
                        color: textColor,
                      ),
                    ),
                  ),
                  for (final reward in overview.taxiRewards) ...[
                    _RewardCard(
                      reward: reward,
                      claiming: _claiming
                          .contains('${reward.rewardType}:${reward.rewardKey}'),
                      onClaim: () => _claim(reward),
                      textColor: textColor,
                      subText: subText,
                      surface: theme.colorScheme.surface,
                    ),
                    SizedBox(height: 12.h),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _errorBanner(String message, bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: MoneyColors.red.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, size: 16.sp, color: MoneyColors.red),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12.sp, color: MoneyColors.red),
            ),
          ),
        ],
      ),
    );
  }
}

class _LadderCard extends StatelessWidget {
  const _LadderCard({
    required this.ladder,
    required this.label,
    required this.unit,
    required this.icon,
    required this.textColor,
    required this.subText,
    required this.surface,
  });

  final IncentiveLadder ladder;
  final String label;
  final String unit;
  final IconData icon;
  final Color textColor;
  final Color subText;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final next = ladder.nextTier;
    final expires = ladder.expiresAt;
    final headline = next != null
        ? '${ladder.completed}/${next.toOrders} $unit — ${formatRupeesShort(next.rewardAmount)} bonus'
        : 'All targets reached — ${formatRupeesShort(ladder.earned)} earned';

    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: MoneyColors.black,
        borderRadius: BorderRadius.circular(24.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: MoneyColors.yellow, size: 18.sp),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: MoneyColors.yellow,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.sp,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
              if (expires != null)
                Flexible(
                  child: Text(
                    _endsIn(expires),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white70, fontSize: 11.sp),
                  ),
                ),
            ],
          ),
          if (ladder.title.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(
              ladder.title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15.sp,
              ),
            ),
          ],
          SizedBox(height: 12.h),
          Text(
            headline,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18.sp,
            ),
          ),
          SizedBox(height: 10.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: ladder.progress,
              minHeight: 8.h,
              backgroundColor: Colors.white12,
              color: MoneyColors.yellow,
            ),
          ),
          SizedBox(height: 14.h),
          for (final tier in ladder.tiers) _tierRow(tier),
          if (ladder.earned > 0) ...[
            SizedBox(height: 6.h),
            Text(
              '${formatRupeesShort(ladder.earned)} of ${formatRupeesShort(ladder.totalReward)} earned · credited automatically',
              style: TextStyle(color: Colors.white70, fontSize: 11.sp),
            ),
          ] else ...[
            SizedBox(height: 6.h),
            Text(
              'Up to ${formatRupeesShort(ladder.totalReward)} · credited automatically',
              style: TextStyle(color: Colors.white70, fontSize: 11.sp),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tierRow(LadderTier tier) {
    final done = tier.achieved;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            size: 16.sp,
            color: done ? MoneyColors.yellow : Colors.white38,
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(
              '${tier.toOrders} $unit',
              style: TextStyle(
                color: done ? Colors.white : Colors.white70,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            formatRupeesShort(tier.rewardAmount),
            style: TextStyle(
              color: done ? MoneyColors.yellow : Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.sp,
            ),
          ),
          if (tier.credited) ...[
            SizedBox(width: 6.w),
            Text(
              'Paid',
              style: TextStyle(color: MoneyColors.green, fontSize: 10.sp, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  String _endsIn(DateTime end) {
    final left = end.difference(DateTime.now());
    if (left.isNegative) return 'Ended';
    if (left.inDays >= 1) return 'Ends in ${left.inDays}d ${left.inHours % 24}h';
    if (left.inHours >= 1) return 'Ends in ${left.inHours}h ${left.inMinutes % 60}m';
    return 'Ends in ${left.inMinutes}m';
  }
}

class _RewardCard extends StatelessWidget {
  const _RewardCard({
    required this.reward,
    required this.claiming,
    required this.onClaim,
    required this.textColor,
    required this.subText,
    required this.surface,
  });

  final TaxiReward reward;
  final bool claiming;
  final VoidCallback onClaim;
  final Color textColor;
  final Color subText;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final current = _fmt(reward.current);
    final target = _fmt(reward.target);
    final unit = reward.unit.isEmpty ? '' : ' ${reward.unit}';
    final progressText = reward.lowerIsBetter
        ? 'Now $current$unit · keep at or below $target$unit'
        : '$current/$target$unit';

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20.r),
        border: reward.canClaim
            ? Border.all(color: MoneyColors.yellow, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  reward.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14.sp,
                    color: textColor,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              if (reward.amount > 0)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: MoneyColors.yellow,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Text(
                    formatRupeesShort(reward.amount),
                    style: TextStyle(
                      color: MoneyColors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.sp,
                    ),
                  ),
                ),
            ],
          ),
          if (reward.description.isNotEmpty) ...[
            SizedBox(height: 4.h),
            Text(
              reward.description,
              style: TextStyle(fontSize: 12.sp, color: subText, height: 1.35),
            ),
          ],
          SizedBox(height: 12.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(6.r),
            child: LinearProgressIndicator(
              value: reward.isClaimed ? 1 : reward.progress,
              minHeight: 6.h,
              backgroundColor: subText.withValues(alpha: 0.2),
              color: reward.isClaimed ? MoneyColors.green : MoneyColors.yellow,
            ),
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: Text(
                  progressText,
                  style: TextStyle(fontSize: 11.sp, color: subText),
                ),
              ),
              SizedBox(width: 8.w),
              if (reward.isClaimed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14.sp, color: MoneyColors.green),
                    SizedBox(width: 4.w),
                    Text(
                      'Claimed',
                      style: TextStyle(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: MoneyColors.green,
                      ),
                    ),
                  ],
                )
              else if (reward.canClaim)
                ElevatedButton(
                  style: MoneyButtons.dark(),
                  onPressed: claiming ? null : onClaim,
                  child: claiming
                      ? SizedBox(
                          width: 16.r,
                          height: 16.r,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: MoneyColors.yellow,
                          ),
                        )
                      : const Text('Claim'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}
