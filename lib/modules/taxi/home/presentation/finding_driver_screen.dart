import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/maps/app_map_style.dart';
import 'package:superapp_user/core/speech/hindi_announcer.dart';
import 'package:superapp_user/design_system/components/buttons/announce_button.dart';
import 'package:superapp_user/design_system/components/feedback/taxi_snackbar_utils.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_controller.dart';
import 'package:superapp_user/modules/taxi/home/application/booking_state.dart';
import 'package:superapp_user/modules/taxi/home/application/vehicle_image.dart';
import 'package:superapp_user/modules/taxi/home/application/ride_search_controller.dart';
import 'package:superapp_user/modules/taxi/home/application/ride_search_state.dart';
import 'package:superapp_user/modules/taxi/home/presentation/nearby_driver_markers.dart';

const _fallbackLatLng = LatLng(22.7196, 75.8577);

class FindingDriverScreen extends ConsumerStatefulWidget {
  const FindingDriverScreen({super.key});

  @override
  ConsumerState<FindingDriverScreen> createState() => _FindingDriverScreenState();
}

class _FindingDriverScreenState extends ConsumerState<FindingDriverScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _leaving = false;
  bool _announced = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkInitialState();
    });
  }

  Future<void> _checkInitialState() async {
    final search = ref.read(rideSearchControllerProvider);
    if (search.phase == RideSearchPhase.accepted && search.rideId != null) {
      _handlePhase(search);
      return;
    }
    _announceOnce(search);
    try {
      final activeRide = await ref.read(rideRepositoryProvider).getMyActiveRide();
      if (activeRide != null && !_leaving && mounted) {
        final s = activeRide.status.toLowerCase();
        if (s == 'accepted' || s == 'arriving' || s == 'started' || s == 'arrived') {
          _leaving = true;
          context.pushReplacement('/taxi/rides/${activeRide.rideId}/track');
        }
      }
    } catch (_) {}
  }


  @override
  void dispose() {
    _pulseController.dispose();
    HindiAnnouncer.instance.stop();
    super.dispose();
  }

  /// Speaks the booking once the server has created the ride (phase
  /// `searching`) — not while it is still being created, so a failed booking
  /// is never announced as booked.
  void _announceOnce(RideSearchState search) {
    if (_announced || _leaving || !mounted) return;
    if (search.phase != RideSearchPhase.searching) return;
    if (!HindiAnnouncer.appInForeground) return;
    final booking = ref.read(bookingControllerProvider);
    if (booking.pickup == null || booking.drop == null) return;
    _announced = true;
    HindiAnnouncer.instance.speak(_announcementText(booking));
  }

  String _announcementText(BookingState booking) {
    final vehicle = booking.selectedVehicle;
    final fare = (vehicle != null
            ? ref.read(bookingControllerProvider.notifier).fareForVehicle(vehicle)?.total
            : null) ??
        booking.fareBreakdown?.total;
    final distance = booking.distanceMeters;
    final parts = <String>[
      vehicle != null && vehicle.name.isNotEmpty
          ? 'आपकी ${vehicle.name} राइड बुक हो गई है।'
          : 'आपकी राइड बुक हो गई है।',
      if (booking.pickup != null && booking.drop != null)
        '${HindiAnnouncer.address(booking.pickup!.address)} से '
            '${HindiAnnouncer.address(booking.drop!.address)} तक।',
      if (distance != null && distance > 0)
        'दूरी लगभग ${HindiAnnouncer.kilometers(distance / 1000)}।',
      if (fare != null && fare > 0)
        'किराया ${HindiAnnouncer.rupees(fare)}, भुगतान '
            '${booking.paymentMethod == 'cash' ? 'कैश में' : booking.paymentMethod == 'wallet' ? 'वॉलेट से' : 'ऑनलाइन'}।',
      'हम आपके लिए ड्राइवर ढूंढ रहे हैं।',
    ];
    return parts.join(' ');
  }

  /// The search phase is decided entirely by the server: `rideSearchUpdate`
  /// keeps us here, `rideAccepted` moves to tracking, and `rideCancelled`
  /// (reasonCode `no_drivers`) sends us to the retry screen. There is no
  /// client-side timer — the backend owns the dispatch budget.
  void _handlePhase(RideSearchState next) {
    if (_leaving || !mounted) return;

    switch (next.phase) {
      case RideSearchPhase.accepted:
        final rideId = next.rideId;
        if (rideId == null || rideId.isEmpty) return;
        _leaving = true;
        context.pushReplacement('/taxi/rides/$rideId/track');
        break;
      case RideSearchPhase.noDrivers:
        _leaving = true;
        context.pushReplacement('/taxi/no-driver');
        break;
      case RideSearchPhase.failed:
        _leaving = true;
        SnackbarUtils.error(context, next.message ?? 'Could not create your booking'.tr);
        context.pushReplacement('/taxi/no-driver');
        break;
      case RideSearchPhase.cancelled:
        _leaving = true;
        context.go('/taxi');
        break;
      case RideSearchPhase.idle:
      case RideSearchPhase.creating:
      case RideSearchPhase.searching:
        break;
    }
  }

  Future<void> _cancelSearch() async {
    if (_leaving) return;
    final reason = await askCancelReason(
      context,
      title: 'Cancel this ride?',
      reasons: CancelReasons.ride,
      confirmLabel: 'Cancel ride',
      keepLabel: 'Keep searching',
    );
    if (reason == null || !mounted || _leaving) return;
    // Claim the exit up front so the phase listener doesn't also navigate when
    // cancelSearch flips the state to `cancelled`.
    _leaving = true;

    final ok = await ref.read(rideSearchControllerProvider.notifier).cancelSearch(
          reason: reason,
        );
    if (!mounted) return;
    if (!ok) {
      _leaving = false;
      SnackbarUtils.error(context, 'Could not cancel the ride. Please try again.'.tr);
      return;
    }
    ref.read(bookingControllerProvider.notifier).reset();
    if (mounted) context.go('/taxi');
  }

  String _assetForVehicle(String iconType, String name) {
    final lower = (iconType + name).toLowerCase();
    if (lower.contains('bike')) return 'assets/images/taxi/bike.png';
    if (lower.contains('parcel')) return 'assets/images/taxi/parcel.png';
    if (lower.contains('all') || lower.contains('cab')) return 'assets/images/taxi/allservice.png';
    return 'assets/images/taxi/booknow.png';
  }

  Widget _radarRing(double t) {
    final size = 40 + t * 140;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.5;
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
      ),
    );
  }

  Widget _addressRow({
    required IconData icon,
    required Color iconColor,
    required double iconSize,
    required String text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(icon, size: iconSize, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0F172A)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final booking = ref.watch(bookingControllerProvider);
    final search = ref.watch(rideSearchControllerProvider);
    final pickup = booking.pickup;
    final drop = booking.drop;
    final vehicle = booking.selectedVehicle;
    final pickupLatLng = pickup != null ? LatLng(pickup.lat, pickup.lng) : _fallbackLatLng;

    ref.listen(rideSearchControllerProvider, (previous, next) {
      _handlePhase(next);
      _announceOnce(next);
    });

    // Progress reflects the server's real dispatch attempts, so the bar can
    // only reach the end when the backend has genuinely run out of drivers.
    final progress = search.maxAttempts > 0
        ? (search.attempt / search.maxAttempts).clamp(0.0, 1.0)
        : null;
    final searchLabel = search.radiusMeters > 0
        ? 'Searching {km} km around you'.trArgs({'km': (search.radiusMeters / 1000).toStringAsFixed(1)})
        : 'Contacting nearby drivers…'.tr;
    final paymentLabel =
        booking.paymentMethod == 'cash' ? 'Cash'.tr : booking.paymentMethod.toUpperCase();

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Column(
          children: [
            // ==================== MAP WITH RADAR PULSE ====================
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GoogleMap(
                    style: AppMapStyle.muted,
                    initialCameraPosition: CameraPosition(target: pickupLatLng, zoom: 15),
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    // Keep the live fleet visible while searching — the radar
                    // pulse over an empty map reads as "no drivers here".
                    markers: buildNearbyDriverMarkers(ref),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              for (final delay in [0.0, 0.33, 0.66])
                                _radarRing((_pulseController.value + delay) % 1.0),
                              const Icon(Icons.location_on, size: 44, color: Color(0xFF334155)),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ==================== BOTTOM DETAILS PANEL ====================
            Expanded(
              flex: 6,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 18, offset: Offset(0, -6))],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE2E8F0),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const CircleAvatar(
                            radius: 18,
                            backgroundColor: Color(0xFFF1F5F9),
                            child: Icon(Icons.person, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Discover your Driver'.tr,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 6,
                          backgroundColor: const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation(Color(0xFFFFB800)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        searchLabel,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                      ),
                      if (search.totalNotifiedDrivers > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '{count} driver(s) notified'.trArgs({'count': search.totalNotifiedDrivers}),
                            style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(child: Text('Booking Details'.tr, style: _sectionTitleStyle)),
                          AnnounceButton(text: _announcementText(booking)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: _cardDecoration,
                        child: Column(
                          children: [
                            _addressRow(
                              icon: Icons.circle,
                              iconColor: const Color(0xFF10B981),
                              iconSize: 12,
                              text: pickup?.address ?? '—',
                            ),
                            const Divider(height: 1, color: Color(0xFFF1F5F9)),
                            _addressRow(
                              icon: Icons.location_on,
                              iconColor: const Color(0xFFE5A600),
                              iconSize: 18,
                              text: drop?.address ?? '—',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Ride details'.tr, style: _sectionTitleStyle),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: _cardDecoration,
                        child: Row(
                          children: [
                            _VehicleThumb(
                              imageUrl: adminVehicleImage(vehicle),
                              asset: _assetForVehicle(vehicle?.iconType ?? '', vehicle?.name ?? ''),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Text(
                                vehicle?.name ?? 'Ride'.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Payment'.tr, style: _sectionTitleStyle),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: _cardDecoration,
                        child: Row(
                          children: [
                            const Icon(Icons.payments_outlined, size: 20, color: Color(0xFF0F172A)),
                            const SizedBox(width: 10),
                            Text(
                              paymentLabel,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: Color(0xFF0F172A)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Manage Ride'.tr, style: _sectionTitleStyle),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                          ),
                          onPressed: _cancelSearch,
                          icon: const Icon(Icons.cancel_outlined),
                          label: Text(
                            'Cancel Ride'.tr,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _sectionTitleStyle = TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F172A));

const _cardDecoration = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.all(Radius.circular(12)),
  border: Border.fromBorderSide(BorderSide(color: Color(0xFFF1F5F9))),
);

/// Admin vehicle picture, with the bundled art while loading or on failure.
class _VehicleThumb extends StatelessWidget {
  const _VehicleThumb({required this.imageUrl, required this.asset});

  final String imageUrl;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final bundled = Image.asset(asset, width: 28, height: 28, fit: BoxFit.contain);
    if (imageUrl.isEmpty) return bundled;
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: 28,
      height: 28,
      fit: BoxFit.contain,
      placeholder: (_, _) => bundled,
      errorWidget: (_, _, _) => bundled,
    );
  }
}
