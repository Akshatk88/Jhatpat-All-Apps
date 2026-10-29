import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../wallet/data/ride_wallet_repository.dart' show RideWalletUnavailable;
import '../../work_mode/application/work_mode_controller.dart';
import '../data/incentives_repository.dart';

/// Everything the Incentives screen shows, each part null/empty when k9 has
/// nothing for this rider.
class IncentivesOverview {
  const IncentivesOverview({
    this.foodLadder,
    this.taxiLadder,
    this.taxiRewards = const [],
    this.errors = const [],
  });

  final IncentiveLadder? foodLadder;
  final IncentiveLadder? taxiLadder;
  final List<TaxiReward> taxiRewards;

  /// Server messages of the parts that failed (shown, not swallowed).
  final List<String> errors;

  bool get isEmpty =>
      foodLadder == null && taxiLadder == null && taxiRewards.isEmpty;

  int get claimableCount => taxiRewards.where((r) => r.canClaim).length;

  double get claimableAmount => taxiRewards
      .where((r) => r.canClaim)
      .fold<double>(0, (sum, r) => sum + r.amount);
}

final incentivesOverviewProvider = FutureProvider<IncentivesOverview>(
  (ref) async {
    final status = await ref.watch(workModeControllerProvider.future);
    final repo = ref.read(incentivesRepositoryProvider);
    final taxi = status.canDoRides || status.canDoParcel;

    final results = await Future.wait<Object>([
      repo.foodLadder(),
      if (taxi) repo.taxiLadder(),
      if (taxi) repo.taxiRewards(),
    ]);

    final errors = <String>[];
    T? take<T>(Object r) {
      final result = r as Result<T, AppError>;
      return result.when(
        success: (data) => data,
        failure: (e) {
          if (e is! RideWalletUnavailable) errors.add(e.message);
          return null;
        },
      );
    }

    final food = take<IncentiveLadder?>(results[0]);
    final taxiLadder = taxi ? take<IncentiveLadder?>(results[1]) : null;
    final rewards = taxi ? take<TaxiRewards>(results[2]) : null;

    return IncentivesOverview(
      foodLadder: food,
      taxiLadder: taxiLadder,
      taxiRewards: rewards?.rewards ?? const [],
      errors: errors.toSet().toList(),
    );
  },
  retry: (_, _) => null,
);
