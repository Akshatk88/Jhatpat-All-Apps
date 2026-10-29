import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../work_mode/application/work_mode_controller.dart';
import '../data/ride_wallet_repository.dart';

/// True when this rider is approved for rides or parcel (taxi dispatcher),
/// read from `GET /taxi/drivers/me` `serviceCapabilities` via the work-mode
/// controller. False while that is still loading.
final hasRideCapabilityProvider = Provider<bool>((ref) {
  final status = ref.watch(workModeControllerProvider).value;
  if (status == null) return false;
  return status.canDoRides || status.canDoParcel;
});

/// The ride wallet, or null when the account has no taxi driver behind it
/// (food-only partner) — the section is hidden then, not shown as an error.
/// Failures carry the server `message`.
final rideWalletSnapshotProvider = FutureProvider<RideWalletSnapshot?>(
  (ref) async {
    final result = await ref.read(rideWalletRepositoryProvider).getWallet();
    return result.when(
      success: (snapshot) => snapshot,
      failure: (error) {
        if (error is RideWalletUnavailable) return null;
        throw error;
      },
    );
  },
  // The Pocket screen refreshes on pull and on tab focus; a silent
  // background retry would only hide a real error behind a spinner.
  retry: (_, _) => null,
);

/// The server message of a provider error, for error states.
String moneyErrorText(Object error) =>
    error is AppError ? error.message : 'Something went wrong';
