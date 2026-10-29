import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/application/auth_state.dart';
import '../data/work_mode.dart';
import '../data/work_mode_preference_store.dart';
import '../data/work_mode_repository.dart';

/// Owns the Food delivery / Parcel delivery / Rider switch.
///
/// The server is the source of truth for food vs taxi — it holds `workMode`
/// across restarts and enforces it in dispatch — so that half loads from the
/// driver document and reverts on a rejected change. Parcel vs rider is not
/// something the server stores (both are `taxi`), so that half is kept in
/// [WorkModePreferenceStore] and applied on top.
///
/// Every state this controller settles on is also written to
/// [WorkModePreferenceStore], because the native offer alert (Kotlin, running
/// before Flutter on a backgrounded or killed app) filters offers by that
/// stored module. A module only held in memory here would leave the native
/// ring/notification/overlay following whatever was last explicitly picked.
class WorkModeController extends AsyncNotifier<WorkModeStatus> {
  WorkModeRepository get _repository => ref.read(workModeRepositoryProvider);
  WorkModePreferenceStore get _prefs =>
      ref.read(workModePreferenceStoreProvider);

  @override
  Future<WorkModeStatus> build() async {
    // Re-read whenever the login state flips. This provider is first touched
    // at startup (FCM, availability) — often before the rider has logged in —
    // and that unauthenticated read fails into the food-only fallback. Without
    // this it stayed there for the whole session, so a rider approved for
    // Parcel and Rider still saw both locked as "Not registered".
    final loggedIn = ref.watch(
      authControllerProvider.select((s) => s is AuthAuthenticated),
    );
    final preferred = await _prefs.read().timeout(
      const Duration(seconds: 3),
      onTimeout: () => null,
    );
    if (!loggedIn) return WorkModeStatus.offlineFallback(preferred);
    // Hard cap so a stalled request can never hold the selector on a spinner.
    final result = await _repository.fetch().timeout(
      const Duration(seconds: 25),
      onTimeout: () => Result.failure(NetworkError('Work mode request timed out')),
    );
    return result.when(
      success: (status) {
        final resolved = status.resolvedWith(preferred);
        unawaited(_prefs.write(resolved.mode));
        return resolved;
      },
      // A driver who isn't on the unified roster yet still needs a working
      // food app, so this falls back to food — unless the rider already picked
      // Parcel or Rider on this device, which is kept rather than silently
      // putting them back on the food dispatcher over a failed request.
      failure: (_) => WorkModeStatus.offlineFallback(preferred),
    );
  }

  /// The modules switched on. Food while still loading, so the food flow is
  /// never gated behind a network round trip.
  WorkModeSet get mode => state.value?.mode ?? WorkModeSet.food;

  /// True while parcel or passenger jobs are on. The incoming-ride controller
  /// gates on this so a Food-only rider is never shown a ride, even if a stale
  /// dispatch event reaches the socket.
  bool get acceptsRides => mode.acceptsRides;

  bool get acceptsFood => mode.acceptsFood;

  /// Whether a ride-dispatcher offer belongs to a module that is on.
  bool acceptsOffer({required bool isParcel}) =>
      mode.acceptsOffer(isParcel: isParcel);

  /// Sets [status] and mirrors its modules to the native side.
  void _apply(WorkModeStatus status) {
    state = AsyncData(status);
    unawaited(_prefs.write(status.mode));
  }

  /// Turns one module on or off. At least one module must stay on.
  Future<Result<void, AppError>> toggle(WorkMode module) {
    return select(mode.toggled(module));
  }

  /// Switches to exactly [next]. The server is only called when the wire
  /// value changes (food on/off, or rides on/off); parcel ↔ rider is local.
  Future<Result<void, AppError>> select(WorkModeSet next) async {
    if (next.isEmpty) {
      return Result.failure(NetworkError('Keep at least one service on'));
    }
    final previous = state.value;
    if (previous != null && previous.mode == next) {
      return const Result.success(null);
    }

    if (previous != null && previous.serverWire == next.wire) {
      _apply(previous.copyWith(mode: next));
      return const Result.success(null);
    }

    if (previous != null) {
      // Optimistic: the switch should feel instant. Reverted below if refused.
      _apply(previous.copyWith(mode: next));
    }

    final result = await _repository.setMode(next);
    return result.when(
      success: (status) {
        _apply(status.resolvedWith(next));
        return const Result.success(null);
      },
      failure: (error) {
        if (previous != null) _apply(previous);
        return Result.failure(error);
      },
    );
  }

  /// Re-reads capabilities from the server. Returns the fresh status, or null
  /// when the read failed (the current state is then left as it was).
  Future<WorkModeStatus?> refresh() async {
    final result = await _repository.fetch();
    final preferred = state.value?.mode ?? await _prefs.read();
    return result.when(
      success: (status) {
        final resolved = status.resolvedWith(preferred);
        _apply(resolved);
        return resolved;
      },
      failure: (_) => null,
    );
  }
}

final workModeControllerProvider =
    AsyncNotifierProvider<WorkModeController, WorkModeStatus>(
  WorkModeController.new,
);

/// Convenience for widgets and controllers that only care about which
/// modules are on. Food while the status is still loading.
final currentWorkModeProvider = Provider<WorkModeSet>((ref) {
  return ref.watch(workModeControllerProvider).value?.mode ?? WorkModeSet.food;
});
