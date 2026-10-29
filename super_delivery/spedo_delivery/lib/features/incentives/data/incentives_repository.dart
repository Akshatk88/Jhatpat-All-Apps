import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/dio_client.dart';
import '../../wallet/data/ride_wallet_repository.dart'
    show RideWalletUnavailable, rideMoneyErrorMessage;

class IncentivesEndpoints {
  IncentivesEndpoints._();

  /// Food order ladder. `authMiddleware + requireFoodDeliveryPartner`
  /// (the app's own token). `data` is null when no ladder is live.
  static const String foodLadder = '/food/delivery/incentives/current';

  /// Same ladder shape for the taxiAndPorter segment. Taxi `authenticate(["driver"])`.
  static const String taxiLadder = '/taxi/drivers/incentives/ladder/current';

  /// Milestone programs + reward features (claimable). Taxi `authenticate(["driver"])`.
  static const String taxiRewards = '/taxi/drivers/incentives';

  /// POST `{ rewardType: milestone | feature, rewardKey }` → credits the
  /// reward to the ride wallet.
  static const String claim = '/taxi/drivers/incentives/claim';
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).round();

/// One rung of an order/ride-count ladder (k9 `buildCurrentIncentive`).
class LadderTier {
  const LadderTier({
    required this.id,
    required this.fromOrders,
    required this.toOrders,
    required this.rewardAmount,
    required this.achieved,
    required this.credited,
  });

  final String id;
  final int fromOrders;
  final int toOrders;
  final double rewardAmount;
  final bool achieved;
  final bool credited;

  factory LadderTier.fromJson(Map<String, dynamic> json) => LadderTier(
        id: json['id']?.toString() ?? '',
        fromOrders: _int(json['fromOrders']),
        toOrders: _int(json['toOrders']),
        rewardAmount: _num(json['rewardAmount']),
        achieved: json['achieved'] == true,
        credited: json['credited'] == true,
      );
}

/// A daily/weekly ladder. Rewards are credited automatically by k9 as each
/// rung is reached — there is nothing to claim.
class IncentiveLadder {
  const IncentiveLadder({
    required this.id,
    required this.title,
    required this.tiers,
    required this.completed,
    required this.target,
    required this.totalReward,
    required this.expiresAt,
  });

  final String id;
  final String title;
  final List<LadderTier> tiers;
  final int completed;
  final int target;
  final double totalReward;
  final DateTime? expiresAt;

  /// The first rung not reached yet, or null when the ladder is complete.
  LadderTier? get nextTier {
    for (final t in tiers) {
      if (!t.achieved) return t;
    }
    return null;
  }

  double get progress => target <= 0 ? 0 : (completed / target).clamp(0.0, 1.0);

  double get earned => tiers
      .where((t) => t.achieved)
      .fold<double>(0, (sum, t) => sum + t.rewardAmount);

  static IncentiveLadder? tryParse(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final rawTiers = json['tiers'];
    final tiers = rawTiers is List
        ? rawTiers
            .whereType<Map<String, dynamic>>()
            .map(LadderTier.fromJson)
            .toList()
        : <LadderTier>[];
    if (tiers.isEmpty) return null;
    return IncentiveLadder(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      tiers: tiers,
      completed: _int(json['completedOrders']),
      target: _int(json['targetOrders']),
      totalReward: _num(json['totalRewardAmount']),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? '')?.toLocal(),
    );
  }
}

/// A claimable taxi reward: a milestone program or a reward feature
/// (k9 `buildDriverIncentiveSnapshot`).
class TaxiReward {
  const TaxiReward({
    required this.rewardType,
    required this.rewardKey,
    required this.title,
    required this.description,
    required this.amount,
    required this.current,
    required this.target,
    required this.unit,
    required this.lowerIsBetter,
    required this.isEligible,
    required this.isClaimed,
  });

  /// `milestone` or `feature` — sent back as `rewardType` when claiming.
  final String rewardType;

  /// Milestone `id` or feature `key` — sent back as `rewardKey`.
  final String rewardKey;
  final String title;
  final String description;
  final double amount;
  final double current;
  final double target;
  final String unit;

  /// `cancellation_guard` is met by staying at or below the target.
  final bool lowerIsBetter;
  final bool isEligible;
  final bool isClaimed;

  bool get canClaim => isEligible && !isClaimed;

  double get progress {
    if (lowerIsBetter) return current <= target ? 1 : 0;
    return target <= 0 ? 1 : (current / target).clamp(0.0, 1.0);
  }

  static TaxiReward? milestone(Map<String, dynamic> json) {
    if (json['enabled'] == false) return null;
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;
    final p = json['progress'] is Map ? json['progress'] as Map : const {};
    final weeks = _num(json['required_weeks']);
    final hours = _num(json['active_hours_per_day']);
    final trips = _num(json['min_trips_per_week']);
    final parts = <String>[
      if (trips > 0) '${trips.round()} rides/week',
      if (hours > 0) '${_trim(hours)} h online/day',
      if (weeks > 0) 'for ${weeks.round()} week${weeks == 1 ? '' : 's'}',
    ];
    final notes = json['notes']?.toString() ?? '';
    return TaxiReward(
      rewardType: 'milestone',
      rewardKey: id,
      title: json['name']?.toString() ?? 'Milestone',
      description: [parts.join(' '), notes].where((s) => s.isNotEmpty).join('\n'),
      amount: _num(json['payout_amount']),
      current: _num(p['qualifyingDays']),
      target: _num(p['targetDays']),
      unit: 'qualifying days',
      lowerIsBetter: false,
      isEligible: json['isEligible'] == true,
      isClaimed: json['isClaimed'] == true,
    );
  }

  static TaxiReward? feature(Map<String, dynamic> json) {
    if (json['enabled'] == false) return null;
    final key = json['key']?.toString() ?? '';
    if (key.isEmpty) return null;
    return TaxiReward(
      rewardType: 'feature',
      rewardKey: key,
      title: json['label']?.toString() ?? json['name']?.toString() ?? 'Reward',
      description: json['description']?.toString() ?? '',
      amount: _num(json['reward_amount'] ?? json['payout_amount']),
      current: _num(json['currentValue']),
      target: _num(json['targetValue'] ?? json['target_value']),
      unit: json['unit']?.toString() ?? '',
      lowerIsBetter: key == 'cancellation_guard',
      isEligible: json['isEligible'] == true,
      isClaimed: json['isClaimed'] == true,
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);
}

class TaxiRewards {
  const TaxiRewards({required this.rewards});

  final List<TaxiReward> rewards;

  factory TaxiRewards.fromJson(Map<String, dynamic> json) {
    final out = <TaxiReward>[];
    final settings = json['settings'] is Map ? json['settings'] as Map : const {};
    // Milestones only count while the admin has the milestone program on.
    if (settings['milestone_program_enabled'] != false) {
      final ms = json['milestones'];
      if (ms is List) {
        out.addAll(
          ms.whereType<Map<String, dynamic>>().map(TaxiReward.milestone).whereType<TaxiReward>(),
        );
      }
    }
    final fs = json['features'];
    if (fs is List) {
      out.addAll(
        fs.whereType<Map<String, dynamic>>().map(TaxiReward.feature).whereType<TaxiReward>(),
      );
    }
    return TaxiRewards(rewards: out);
  }
}

class IncentivesRepository {
  IncentivesRepository(this._dio);

  final Dio _dio;

  Future<Result<IncentiveLadder?, AppError>> foodLadder() =>
      _ladder(IncentivesEndpoints.foodLadder);

  Future<Result<IncentiveLadder?, AppError>> taxiLadder() =>
      _ladder(IncentivesEndpoints.taxiLadder);

  Future<Result<TaxiRewards, AppError>> taxiRewards() async {
    try {
      final res = await _dio.get(IncentivesEndpoints.taxiRewards);
      final data = res.data is Map<String, dynamic> ? res.data['data'] : null;
      return Result.success(
        data is Map<String, dynamic>
            ? TaxiRewards.fromJson(data)
            : const TaxiRewards(rewards: []),
      );
    } on DioException catch (e) {
      return Result.failure(_error(e));
    }
  }

  /// Returns the credited amount.
  Future<Result<double, AppError>> claim(TaxiReward reward) async {
    try {
      final res = await _dio.post(
        IncentivesEndpoints.claim,
        data: {'rewardType': reward.rewardType, 'rewardKey': reward.rewardKey},
      );
      final data = res.data is Map<String, dynamic> ? res.data['data'] : null;
      final claimed = data is Map ? data['claimedReward'] : null;
      return Result.success(
        claimed is Map ? _num(claimed['amount']) : reward.amount,
      );
    } on DioException catch (e) {
      return Result.failure(NetworkError(rideMoneyErrorMessage(e)));
    }
  }

  Future<Result<IncentiveLadder?, AppError>> _ladder(String path) async {
    try {
      final res = await _dio.get(path);
      final data = res.data is Map<String, dynamic> ? res.data['data'] : null;
      return Result.success(IncentiveLadder.tryParse(data));
    } on DioException catch (e) {
      return Result.failure(_error(e));
    }
  }

  /// 403/404 mean "this account is not on that side" (e.g. a food-only
  /// partner asking the taxi routes) — not an error worth showing.
  AppError _error(DioException e) {
    final code = e.response?.statusCode;
    if (code == 403 || code == 404) {
      return RideWalletUnavailable(rideMoneyErrorMessage(e));
    }
    return NetworkError(rideMoneyErrorMessage(e));
  }
}

final incentivesRepositoryProvider = Provider<IncentivesRepository>((ref) {
  return IncentivesRepository(ref.read(dioProvider));
});
