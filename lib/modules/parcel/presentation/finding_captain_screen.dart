import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/core/i18n/tr.dart';

import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/core/maps/app_map_style.dart';
import 'package:superapp_user/core/speech/hindi_announcer.dart';
import 'package:superapp_user/design_system/components/buttons/announce_button.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_controller.dart';
import 'package:superapp_user/modules/parcel/application/delivery_booking_controller.dart';

/// Step 3: the booking exists and dispatch is notifying nearby captains.
///
/// Reuses the ride tracking controller because a delivery *is* a ride with
/// `serviceType: parcel` — so acceptance, cancellation and live state all
/// arrive on the same socket events rather than a parallel implementation.
class FindingCaptainScreen extends ConsumerStatefulWidget {
  final String rideId;
  const FindingCaptainScreen({super.key, required this.rideId});

  @override
  ConsumerState<FindingCaptainScreen> createState() => _FindingCaptainScreenState();
}

class _FindingCaptainScreenState extends ConsumerState<FindingCaptainScreen> {
  bool _cancelling = false;
  bool _left = false;
  bool _announced = false;

  @override
  void dispose() {
    HindiAnnouncer.instance.stop();
    super.dispose();
  }

  /// The parcel as it stands: server ride when loaded, else what was booked.
  String _announcementText() {
    final ride = ref.read(rideTrackingControllerProvider(widget.rideId)).ride;
    final booking = ref.read(deliveryBookingProvider);
    final pickup = ride?.pickupAddress ?? booking.pickup?.address ?? '';
    final drop = ride?.dropAddress ?? booking.drop?.address ?? '';
    final vehicle = booking.vehicleName.isNotEmpty
        ? booking.vehicleName
        : (booking.quote?.vehicleName ?? '');
    final fare = ride?.fare ?? booking.quote?.total ?? 0;
    final parts = <String>[
      'आपका पार्सल बुक हो गया है।',
      if (pickup.isNotEmpty && drop.isNotEmpty)
        '${HindiAnnouncer.address(pickup)} se ${HindiAnnouncer.address(drop)} तक।',
      if (vehicle.isNotEmpty) '$vehicle से।',
      if (fare > 0) 'किराया ${HindiAnnouncer.rupees(fare)}।',
      'हम आपके लिए कैप्टन ढूंढ रहे हैं।',
    ];
    return parts.join(' ');
  }

  /// Speaks once, the first frame there is a route and a price to read out.
  void _announceOnce() {
    if (_announced || _left || _cancelling || !mounted) return;
    if (!HindiAnnouncer.appInForeground) return;
    final ride = ref.read(rideTrackingControllerProvider(widget.rideId)).ride;
    final booking = ref.read(deliveryBookingProvider);
    final hasRoute = ride != null || (booking.pickup != null && booking.drop != null);
    final hasFare = (ride?.fare ?? booking.quote?.total ?? 0) > 0;
    if (!hasRoute || !hasFare) return;
    _announced = true;
    HindiAnnouncer.instance.speak(_announcementText());
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    final reason = await askCancelReason(
      context,
      title: 'Cancel this delivery?',
      reasons: CancelReasons.parcel,
      confirmLabel: 'Cancel delivery',
      keepLabel: 'Keep searching',
    );
    if (reason == null || !mounted || _cancelling) return;
    setState(() => _cancelling = true);

    final ok = await ref
        .read(rideTrackingControllerProvider(widget.rideId).notifier)
        .cancelRide(reason: reason);

    if (!mounted) return;
    if (ok) {
      ref.read(deliveryBookingProvider.notifier).reset();
      context.go('/taxi');
    } else {
      SnackbarUtils.error(context, 'Could not cancel. Please try again.'.tr);
      setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(rideTrackingControllerProvider(widget.rideId));
    final ride = tracking.ride;
    final booking = ref.watch(deliveryBookingProvider);

    ref.listen(rideTrackingControllerProvider(widget.rideId), (previous, next) {
      final r = next.ride;
      if (r == null || _left) return;

      // A captain accepted — hand over to live tracking.
      if (r.driver != null && r.status.toLowerCase() != 'searching') {
        _left = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.pushReplacement('/taxi/rides/${widget.rideId}/track');
        });
        return;
      }

      // Dispatch gave up, or the parcel was cancelled elsewhere.
      if (r.isCancelled) {
        _left = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) context.go('/taxi');
        });
      }
    });

    if (!_announced) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _announceOnce());
    }

    final pickup = ride != null
        ? LatLng(ride.pickup.lat, ride.pickup.lng)
        : LatLng(booking.pickup?.lat ?? 22.7196, booking.pickup?.lng ?? 75.8577);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GoogleMap(
                    style: AppMapStyle.muted,
                    initialCameraPosition: CameraPosition(target: pickup, zoom: 14),
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: false,
                    markers: {
                      Marker(
                        markerId: const MarkerId('pickup'),
                        position: pickup,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      ),
                      if (ride != null)
                        Marker(
                          markerId: const MarkerId('drop'),
                          position: LatLng(ride.drop.lat, ride.drop.lng),
                          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        ),
                    },
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: const [
                              BoxShadow(color: Color(0x1A000000), blurRadius: 10),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('PARCEL ROUTE'.tr,
                                  style: const TextStyle(
                                    fontSize: 9,
                                    letterSpacing: 0.7,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                  )),
                              Text(
                                ride?.pickupAddress ??
                                    booking.pickup?.address ??
                                    'Pickup location'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, 22, 20, 18 + MediaQuery.of(context).padding.bottom),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            Text(
                              'Finding your delivery captain'.tr,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Booking created. Notifying nearby captains…'.tr,
                              style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF8E1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFFFE9A8)),
                              ),
                              child: Column(
                                children: [
                                  Text('EXPECTED PRICE'.tr,
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        letterSpacing: 0.7,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF121212),
                                      )),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Rs ${(ride?.fare ?? booking.quote?.total ?? 0).toStringAsFixed(0)}',
                                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                                  ),
                                  if (booking.quote != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18),
                                      child: Text(
                                        'Estimated for about {km} km. Includes {taxPercent}% service tax.'.trArgs({
                                          'km': booking.quote!.distanceKm.toStringAsFixed(1),
                                          'taxPercent': booking.quote!.serviceTaxPercentage.toStringAsFixed(2),
                                        }),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            AnnounceButton(text: _announcementText()),
                            const SizedBox(height: 14),
                            const Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 10,
                              runSpacing: 8,
                              children: [
                                _Chip(icon: Icons.bolt, label: 'FAST DISPATCH'),
                                _Chip(icon: Icons.verified_user_outlined, label: 'PARCEL SAFETY'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _cancelling ? null : _cancel,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          backgroundColor: const Color(0xFFFEF2F2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _cancelling
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                'CANCEL SEARCH'.tr,
                                style: const TextStyle(
                                  color: Color(0xFFEF4444),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.4,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: TaxiColors.primary),
          const SizedBox(width: 5),
          Text(label.tr,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: Color(0xFF334155),
              )),
        ],
      ),
    );
  }
}
