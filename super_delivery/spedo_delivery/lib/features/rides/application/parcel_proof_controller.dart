import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../data/models/taxi_ride.dart';
import '../data/parcel_proof_repository.dart';

/// Proof photos filed for the parcel job currently in progress.
class ParcelProofState {
  const ParcelProofState({
    this.rideId,
    this.pickup = const [],
    this.delivery = const [],
    this.uploading,
  });

  final String? rideId;
  final List<String> pickup;
  final List<String> delivery;

  /// The stage an upload is running for, or null when idle.
  final ParcelProofStage? uploading;

  ParcelProofState copyWith({
    String? rideId,
    List<String>? pickup,
    List<String>? delivery,
    ParcelProofStage? uploading,
    bool clearUploading = false,
  }) =>
      ParcelProofState(
        rideId: rideId ?? this.rideId,
        pickup: pickup ?? this.pickup,
        delivery: delivery ?? this.delivery,
        uploading: clearUploading ? null : (uploading ?? this.uploading),
      );
}

/// Holds what has been uploaded for the one active parcel job.
///
/// There is only ever one active ride, so this is keyed by ride id rather than
/// being a family: a different ride resets it. The server's own lists (on a
/// restored ride) are merged in by [photosFor], so a relaunch mid-job does not
/// ask for a photo that was already filed.
class ParcelProofController extends Notifier<ParcelProofState> {
  /// The backend keeps at most 6 per stage and takes at most 4 per call.
  static const int maxPerStage = 6;

  @override
  ParcelProofState build() => const ParcelProofState();

  List<String> photosFor(TaxiRide ride, ParcelProofStage stage) {
    final server = stage == ParcelProofStage.pickup
        ? ride.parcelPickupPhotos
        : ride.parcelDeliveryPhotos;
    if (state.rideId != ride.id) return server;
    final local =
        stage == ParcelProofStage.pickup ? state.pickup : state.delivery;
    return {...server, ...local}.toList(growable: false);
  }

  Future<Result<void, AppError>> addPhoto(
    TaxiRide ride,
    ParcelProofStage stage,
    File file,
  ) async {
    if (state.uploading != null) {
      return Result.failure(UnknownError('A photo is still uploading'));
    }
    if (state.rideId != ride.id) {
      state = ParcelProofState(rideId: ride.id);
    }
    state = state.copyWith(uploading: stage);

    final repo = ref.read(parcelProofRepositoryProvider);
    final uploaded = await repo.upload(file);
    final url = uploaded.when(success: (u) => u, failure: (_) => null);
    if (url == null) {
      state = state.copyWith(clearUploading: true);
      return uploaded.when(
        success: (_) => const Result.success(null),
        failure: (e) => Result.failure(e),
      );
    }

    final attached = await repo.attach(ride.id, stage, [url]);
    return attached.when(
      success: (photos) {
        state = stage == ParcelProofStage.pickup
            ? state.copyWith(pickup: photos, clearUploading: true)
            : state.copyWith(delivery: photos, clearUploading: true);
        return const Result.success(null);
      },
      failure: (e) {
        state = state.copyWith(clearUploading: true);
        return Result.failure(e);
      },
    );
  }
}

final parcelProofControllerProvider =
    NotifierProvider<ParcelProofController, ParcelProofState>(
  ParcelProofController.new,
);
