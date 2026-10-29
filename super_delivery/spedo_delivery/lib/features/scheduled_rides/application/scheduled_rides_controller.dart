import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../data/models/scheduled_ride.dart';
import '../data/scheduled_rides_repository.dart';

class ScheduledRidesState {
  const ScheduledRidesState({
    required this.rides,
    required this.page,
    required this.hasNextPage,
    this.loadingMore = false,
  });

  final List<ScheduledRide> rides;
  final int page;
  final bool hasNextPage;
  final bool loadingMore;

  ScheduledRidesState copyWith({
    List<ScheduledRide>? rides,
    int? page,
    bool? hasNextPage,
    bool? loadingMore,
  }) =>
      ScheduledRidesState(
        rides: rides ?? this.rides,
        page: page ?? this.page,
        hasNextPage: hasNextPage ?? this.hasNextPage,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

class ScheduledRidesController extends AsyncNotifier<ScheduledRidesState> {
  static const int _pageSize = 20;

  ScheduledRidesRepository get _repo => ref.read(scheduledRidesRepositoryProvider);

  @override
  Future<ScheduledRidesState> build() async {
    final result = await _repo.list(page: 1, limit: _pageSize);
    return result.when(
      success: (p) => ScheduledRidesState(
        rides: p.rides,
        page: 1,
        hasNextPage: p.hasNextPage,
      ),
      failure: (e) => throw e,
    );
  }

  void reload() => ref.invalidateSelf();

  /// Returns an error message to show, or null.
  Future<String?> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNextPage || current.loadingMore) {
      return null;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    final result = await _repo.list(page: current.page + 1, limit: _pageSize);
    return result.when(
      success: (p) {
        final seen = current.rides.map((r) => r.id).toSet();
        state = AsyncData(
          current.copyWith(
            rides: [...current.rides, ...p.rides.where((r) => !seen.contains(r.id))],
            page: current.page + 1,
            hasNextPage: p.hasNextPage,
            loadingMore: false,
          ),
        );
        return null;
      },
      failure: (e) {
        state = AsyncData(current.copyWith(loadingMore: false));
        return e.message;
      },
    );
  }

  Future<Result<String?, AppError>> cancel(String rideId, {String? reason}) async {
    final result = await _repo.cancel(rideId, reason: reason);
    return result.when(
      success: (message) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(
            current.copyWith(
              rides: current.rides.where((r) => r.id != rideId).toList(growable: false),
            ),
          );
        }
        return Result.success(message);
      },
      failure: (e) => Result.failure(e),
    );
  }
}

final scheduledRidesControllerProvider =
    AsyncNotifierProvider<ScheduledRidesController, ScheduledRidesState>(
  ScheduledRidesController.new,
);
