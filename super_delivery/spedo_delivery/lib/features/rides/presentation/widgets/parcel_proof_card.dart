import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/features/rides/application/parcel_proof_controller.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';
import 'package:food_user_application/features/rides/data/parcel_proof_repository.dart';

const _jhatpatYellow = Color(0xFFFFB800);
const _proofRed = Color(0xFFF04438);

/// Which proof photo the parcel job is collecting right now, or null.
///
/// Pickup: while the captain is at / heading into the pickup (`arriving`, the
/// step before `started`). Delivery: once they have reached the drop
/// (`arrived`, the step before `completed`). Passenger rides never collect any.
ParcelProofStage? parcelProofStageOf(TaxiRide ride) {
  if (!ride.isParcel) return null;
  switch (ride.stage) {
    case RideStage.arriving:
      return ParcelProofStage.pickup;
    case RideStage.arrived:
      return ParcelProofStage.delivery;
    default:
      return null;
  }
}

/// Opens the camera, uploads the shot and files it on the ride.
///
/// Returns true when a photo was filed. Failures are reported here (with the
/// server's message) so callers only need the outcome.
Future<bool> captureParcelProof(
  BuildContext context,
  WidgetRef ref,
  TaxiRide ride,
  ParcelProofStage stage,
) async {
  final messenger = ScaffoldMessenger.of(context);
  XFile? shot;
  try {
    shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
      maxWidth: 1280,
      maxHeight: 1280,
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Camera unavailable. Allow camera access in Settings.'),
        backgroundColor: _proofRed,
      ),
    );
    return false;
  }
  if (shot == null) return false;

  HapticService.light();
  final result = await ref
      .read(parcelProofControllerProvider.notifier)
      .addPhoto(ride, stage, File(shot.path));
  return result.when(
    success: (_) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            stage == ParcelProofStage.pickup
                ? 'Pickup photo saved'
                : 'Delivery photo saved',
          ),
        ),
      );
      return true;
    },
    failure: (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: _proofRed),
      );
      return false;
    },
  );
}

/// Asks for a proof photo before the parcel changes hands, when none has been
/// filed for [stage] yet.
///
/// The backend does not require the photo to advance, so this asks rather than
/// blocks — but it is the moment the photo matters, so it asks every time.
/// Returns false when the captain backed out and the stage should not move.
Future<bool> ensureParcelProof(
  BuildContext context,
  WidgetRef ref,
  TaxiRide ride,
) async {
  final stage = parcelProofStageOf(ride);
  if (stage == null) return true;
  final existing =
      ref.read(parcelProofControllerProvider.notifier).photosFor(ride, stage);
  if (existing.isNotEmpty) return true;

  final choice = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        stage == ParcelProofStage.pickup
            ? 'Photo of the parcel?'
            : 'Photo of the delivered parcel?',
      ),
      content: Text(
        stage == ParcelProofStage.pickup
            ? 'A photo at pickup records the parcel\'s condition and protects '
                'you if the sender disputes it later.'
            : 'A photo at the drop shows the parcel was handed over intact.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop('skip'),
          child: const Text('Continue without'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _jhatpatYellow,
            foregroundColor: Colors.black,
          ),
          onPressed: () => Navigator.of(ctx).pop('photo'),
          child: const Text('Take photo'),
        ),
      ],
    ),
  );
  if (choice == 'skip') return true;
  if (choice != 'photo' || !context.mounted) return false;
  return captureParcelProof(context, ref, ride, stage);
}

/// The proof-photo strip shown on a parcel job at pickup and at the drop.
class ParcelProofCard extends ConsumerWidget {
  const ParcelProofCard({super.key, required this.ride});

  final TaxiRide ride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = parcelProofStageOf(ride);
    if (stage == null) return const SizedBox.shrink();

    final proof = ref.watch(parcelProofControllerProvider);
    final photos =
        ref.read(parcelProofControllerProvider.notifier).photosFor(ride, stage);
    final uploading = proof.rideId == ride.id && proof.uploading == stage;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final canAdd =
        !uploading && photos.length < ParcelProofController.maxPerStage;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: _jhatpatYellow.withValues(alpha: isDark ? 0.14 : 0.12),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: _jhatpatYellow.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.photo_camera_rounded, size: 18.sp, color: textColor),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  stage == ParcelProofStage.pickup
                      ? 'Parcel photo at pickup'
                      : 'Parcel photo at drop',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.sp,
                  ),
                ),
              ),
              if (photos.isNotEmpty)
                Icon(Icons.check_circle_rounded,
                    size: 18.sp, color: const Color(0xFF1EBE5D)),
            ],
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final url in photos)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10.r),
                  child: CachedNetworkImage(
                    imageUrl: url,
                    width: 52.r,
                    height: 52.r,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(
                      width: 52.r,
                      height: 52.r,
                      color: Colors.black12,
                      child: Icon(Icons.broken_image_outlined, size: 18.sp),
                    ),
                  ),
                ),
              if (uploading)
                SizedBox(
                  width: 52.r,
                  height: 52.r,
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              if (canAdd)
                OutlinedButton.icon(
                  onPressed: () => captureParcelProof(context, ref, ride, stage),
                  icon: Icon(Icons.add_a_photo_outlined, size: 16.sp),
                  label: Text(
                    photos.isEmpty ? 'Take photo' : 'Add another',
                    style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: _jhatpatYellow,
                    foregroundColor: Colors.black,
                    side: BorderSide.none,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
