import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';
import 'package:food_user_application/features/wallet/presentation/widgets/ride_qr_payment_sheet.dart';

const _rideGreen = Color(0xFF1EBE5D);

/// What the driver reports having collected when ending the trip.
class FareSettlement {
  const FareSettlement({
    required this.fare,
    required this.paymentMethod,
    required this.collectedByDriver,
  });

  final double fare;

  /// `cash` or whatever the ride was booked with. Sent back so the server
  /// records how the money actually moved, not how it was expected to.
  final String paymentMethod;

  /// True when the driver physically took the money and now owes it to the
  /// platform — this is what drives the cash-in-hand ledger.
  final bool collectedByDriver;
}

/// Final step of the ride — **drop**. Confirms the amount before the trip is
/// closed, because completion is what settles the fare and cannot be undone
/// from the app.
Future<FareSettlement?> showCollectFareSheet(
  BuildContext context,
  TaxiRide ride,
) {
  return showModalBottomSheet<FareSettlement>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CollectFareSheet(ride: ride),
  );
}

class _CollectFareSheet extends StatelessWidget {
  const _CollectFareSheet({required this.ride});

  final TaxiRide ride;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final subText = isDark ? Colors.grey[400] : Colors.grey[600];

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        // Scrolls rather than overflowing on a short or landscape screen.
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              SizedBox(height: 20.h),
              Text(
                ride.isCash
                    ? (ride.isParcel ? 'Collect from customer' : 'Collect from passenger')
                    : 'Trip total',
                style: TextStyle(
                  color: subText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.sp,
                ),
              ),
              SizedBox(height: 8.h),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '₹${ride.fare.toStringAsFixed(0)}',
                  maxLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 40.sp,
                    height: 1,
                  ),
                ),
              ),
              // The server finalised this amount when the trip reached the
              // drop (agreed fare + waiting + any admin charge / recovered
              // cancellation due); say what is in it so the driver can explain.
              if (ride.waitingChargeAmount > 0) ...[
                SizedBox(height: 8.h),
                Text(
                  'Includes waiting charge ₹${ride.waitingChargeAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: subText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.sp,
                  ),
                ),
              ],
              SizedBox(height: 12.h),
              Text(
                ride.isCash
                    ? 'Take the cash before ending the trip. The amount is '
                        'added to your cash in hand.'
                    : 'Online payment — the customer pays in their app. '
                        'Do not collect cash.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subText, fontSize: 13.sp, height: 1.4),
              ),
              SizedBox(height: 24.h),
              SizedBox(
                height: 54.h,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    HapticService.medium();
                    Navigator.of(context).pop(
                      FareSettlement(
                        fare: ride.fare,
                        paymentMethod: ride.paymentMethod,
                        collectedByDriver: ride.isCash,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _rideGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(27.r),
                    ),
                  ),
                  // Shrink-to-fit like the trip button: the cash label is long
                  // and would otherwise wrap inside a fixed-height button.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      ride.isCash ? 'CASH RECEIVED · END TRIP' : 'END TRIP',
                      maxLines: 1,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.sp,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
              // Cash ride where the passenger prefers to pay by UPI: show a
              // payment QR; once the server confirms it, end the trip as an
              // online payment so no cash is added to the driver's ledger.
              if (ride.isCash) ...[
                SizedBox(height: 10.h),
                SizedBox(
                  height: 50.h,
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      HapticService.light();
                      final paid = await showRideQrPaymentSheet(
                        context,
                        rideId: ride.id,
                        amount: ride.fare,
                      );
                      if (paid == true && context.mounted) {
                        Navigator.of(context).pop(
                          FareSettlement(
                            fare: ride.fare,
                            paymentMethod: 'online',
                            collectedByDriver: false,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text(
                      'COLLECT VIA QR',
                      maxLines: 1,
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textColor,
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25.r),
                      ),
                    ),
                  ),
                ),
              ],
              SizedBox(height: 8.h),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Not yet',
                  style: TextStyle(color: subText, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
