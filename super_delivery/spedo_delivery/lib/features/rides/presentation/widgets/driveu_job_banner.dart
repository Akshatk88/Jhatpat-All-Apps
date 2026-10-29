import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';

/// Tells the driver this job is DriveU before they accept it.
///
/// On a DriveU trip the driver brings no vehicle: they travel to the pickup on
/// their own transport and then drive the passenger's car. Until this existed
/// the offer looked like any other ride, so a driver could accept one and
/// arrive expecting to drive their own — which is a cancelled trip at best, and
/// at worst someone taking the wheel of a car they cannot drive.
///
/// Renders nothing for an ordinary ride, so it can sit unconditionally in the
/// offer and active-ride layouts.
class DriveUJobBanner extends StatelessWidget {
  const DriveUJobBanner({super.key, required this.ride, this.compact = false});

  final TaxiRide ride;

  /// Tighter spacing for the active-ride screen, where the banner is a reminder
  /// rather than the headline.
  final bool compact;

  static const _navy = Color(0xFF0B2545);
  static const _accent = Color(0xFF1B6DF3);

  @override
  Widget build(BuildContext context) {
    if (!ride.isDriveU) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasCar = ride.driveUVehicleName.trim().isNotEmpty;
    final transmission = _transmissionLabel(ride.driveUTransmission);

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: compact ? 10.h : 14.h),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: isDark ? _navy : _accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: _accent.withValues(alpha: isDark ? 0.5 : 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30.w,
            height: 30.w,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9.r),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.drive_eta_rounded, size: 17.sp, color: _accent),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DriveU — you drive their car',
                  style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _navy,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  // Said plainly, because it is the thing most likely to be
                  // misread: no vehicle of the driver's own is used.
                  'Travel to the pickup yourself. You will drive the '
                  "passenger's own vehicle to the drop.",
                  style: TextStyle(
                    fontSize: 11.sp,
                    height: 1.35,
                    color: isDark ? Colors.white70 : Colors.grey[700],
                  ),
                ),
                if (hasCar || transmission != null) ...[
                  SizedBox(height: 8.h),
                  Wrap(
                    spacing: 6.w,
                    runSpacing: 6.h,
                    children: [
                      if (hasCar)
                        _Chip(
                          icon: Icons.directions_car_filled_rounded,
                          label: ride.driveUVehicleName,
                          isDark: isDark,
                        ),
                      if (transmission != null)
                        _Chip(
                          icon: Icons.settings_rounded,
                          label: transmission,
                          isDark: isDark,
                        ),
                    ],
                  ),
                ] else ...[
                  SizedBox(height: 6.h),
                  Text(
                    // Booked before the app asked for these. Better to say so
                    // than to leave a blank the driver reads as "no car".
                    'Vehicle details not provided — confirm with the passenger.',
                    style: TextStyle(
                      fontSize: 10.5.sp,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white54 : Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _transmissionLabel(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'manual':
        return 'Manual';
      case 'automatic':
        return 'Automatic';
      default:
        return null;
    }
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.isDark});

  final IconData icon;
  final String label;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white,
        borderRadius: BorderRadius.circular(7.r),
        border: Border.all(
          color: isDark ? Colors.white24 : const Color(0xFFD8E0EC),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon,
              size: 12.sp,
              color: isDark ? Colors.white70 : const Color(0xFF41506B)),
          SizedBox(width: 4.w),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1F2937),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
