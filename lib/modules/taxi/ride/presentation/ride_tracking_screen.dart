import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:superapp_user/design_system/components/feedback/cancel_reason_sheet.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/maps/driver_marker_animator.dart';
import 'package:superapp_user/core/maps/geo_math.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';
import 'package:superapp_user/core/maps/app_map_style.dart';
import 'package:superapp_user/core/maps/vehicle_marker_icons.dart';
import 'package:superapp_user/design_system/components/ride/loading_widget.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/ride/application/driver_location_controller.dart';
import 'package:superapp_user/modules/taxi/ride/application/live_route_engine.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_controller.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_state.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';

class RideTrackingScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RideTrackingScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideTrackingScreen> createState() => _RideTrackingScreenState();
}

class _RideTrackingScreenState extends ConsumerState<RideTrackingScreen>
    with SingleTickerProviderStateMixin {
  GoogleMapController? _mapController;
  bool _navigatedToRating = false;
  bool _navigatedAway = false;

  /// Highest driver-cancel notice already shown, so each is shown once.
  int _shownDriverCancelSeq = 0;

  // ── live tracking ────────────────────────────────────────────────────────
  // The map is driven by these notifiers, not by rebuilding this screen: a
  // GPS packet moves the marker and trims the route without touching the
  // bottom sheet, and the per-frame marker glide rebuilds only the GoogleMap.
  late final DriverMarkerAnimator _animator;
  late final LiveRouteEngine _route;
  late final Listenable _mapListenable;
  final ValueNotifier<bool> _follow = ValueNotifier(true);
  final ValueNotifier<EdgeInsets> _mapPadding = ValueNotifier(EdgeInsets.zero);
  final GlobalKey _headerKey = GlobalKey();
  final GlobalKey _sheetKey = GlobalKey();
  ProviderSubscription<DriverFix?>? _fixSub;
  ProviderSubscription<RideTrackingState>? _rideSub;

  DriverFix? _fix;
  bool _cameraPlaced = false;
  DateTime _lastCameraAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRouteTrimAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Camera follow: at most this often, and only on a new fix — never per
  /// packet or per animation frame.
  static const _followEvery = Duration(seconds: 10);

  /// The trimmed route is re-sent to the map at most this often while the
  /// marker glides (every fix still re-trims immediately).
  static const _trimEvery = Duration(milliseconds: 1200);

  // Static markers / polyline are cached so a rebuild re-sends nothing.
  String _staticKey = '';
  Set<Marker> _staticMarkers = const {};
  int _polylineVersion = -1;
  Set<Polyline> _polylines = const {};

  @override
  void initState() {
    super.initState();
    _animator = DriverMarkerAnimator(this);
    _route = LiveRouteEngine();
    _mapListenable = Listenable.merge([_animator.pose, _route.view, _mapPadding]);
    _animator.pose.addListener(_onPoseFrame);

    _rideSub = ref.listenManual(
      rideTrackingControllerProvider(widget.rideId),
      (_, next) => _syncLeg(next.ride),
      fireImmediately: true,
    );
    _fixSub = ref.listenManual(
      driverLocationProvider(widget.rideId),
      (_, next) => _onFix(next),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _fixSub?.close();
    _rideSub?.close();
    _animator.pose.removeListener(_onPoseFrame);
    _animator.dispose();
    _route.dispose();
    _follow.dispose();
    _mapPadding.dispose();
    super.dispose();
  }

  void _syncLeg(RideModel? ride) {
    if (ride == null) return;
    final leg = TrackingLeg.of(ride);
    final previous = _route.leg;
    switch (leg) {
      case TrackingLeg.toPickup:
        _route.setLeg(leg, target: LatLng(ride.pickup.lat, ride.pickup.lng));
        break;
      case TrackingLeg.toDrop:
        _route.setLeg(
          leg,
          target: LatLng(ride.drop.lat, ride.drop.lng),
          waypoints: [
            for (final s in ride.stops)
              if (GeoMath.isValid(s.location.lat, s.location.lng))
                LatLng(s.location.lat, s.location.lng),
          ],
          origin: LatLng(ride.pickup.lat, ride.pickup.lng),
        );
        break;
      case TrackingLeg.atPickup:
      case TrackingLeg.none:
        _route.setLeg(leg);
        break;
    }
    if (leg != previous && _follow.value) _placeCamera();
  }

  void _onFix(DriverFix? fix) {
    if (fix == null || !mounted) return;
    _fix = fix;
    _animator.onFix(fix.position, heading: fix.heading, speed: fix.speed);
    _route.onFix(fix.position, accuracy: fix.accuracy);
    _route.renderFrom(_animator.pose.value?.position ?? fix.position);
    _lastRouteTrimAt = DateTime.now();

    if (!_cameraPlaced) {
      _placeCamera();
    } else if (_follow.value && DateTime.now().difference(_lastCameraAt) >= _followEvery) {
      _placeCamera();
    }
  }

  void _onPoseFrame() {
    final now = DateTime.now();
    if (now.difference(_lastRouteTrimAt) < _trimEvery) return;
    _lastRouteTrimAt = now;
    _route.renderFrom(_animator.pose.value?.position);
  }

  /// Frames the driver and where they are heading (pickup, then drop).
  void _placeCamera() {
    final controller = _mapController;
    if (controller == null) return;
    final ride = ref.read(rideTrackingControllerProvider(widget.rideId)).ride;
    final driver = _animator.pose.value?.position ?? _fix?.position;
    final target = _route.target ??
        (ride != null ? LatLng(ride.pickup.lat, ride.pickup.lng) : null);

    CameraUpdate? update;
    if (driver == null && target != null) {
      update = CameraUpdate.newLatLngZoom(target, 15);
    } else if (driver != null && (target == null || GeoMath.distance(driver, target) < 150)) {
      update = CameraUpdate.newLatLngZoom(driver, 16.5);
    } else if (driver != null && target != null) {
      update = CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(
            math.min(driver.latitude, target.latitude),
            math.min(driver.longitude, target.longitude),
          ),
          northeast: LatLng(
            math.max(driver.latitude, target.latitude),
            math.max(driver.longitude, target.longitude),
          ),
        ),
        56,
      );
    }
    if (update == null) return;
    if (driver != null) _cameraPlaced = true;
    _lastCameraAt = DateTime.now();
    // Bounds can't be applied before the map has a size; a failure is harmless.
    controller.animateCamera(update).catchError((Object _) {});
  }

  void _recenter() {
    _follow.value = true;
    _placeCamera();
  }

  /// Keeps the camera's visible area clear of the header and bottom sheet.
  void _measureOverlays(Duration _) {
    if (!mounted) return;
    final header = _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final sheet = _sheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (header == null || sheet == null || !header.hasSize || !sheet.hasSize) return;
    final top = header.localToGlobal(Offset.zero).dy + header.size.height;
    final bottom = sheet.size.height;
    final current = _mapPadding.value;
    if ((current.top - top).abs() > 4 || (current.bottom - bottom).abs() > 4) {
      _mapPadding.value = EdgeInsets.only(top: top, bottom: bottom);
    }
  }

  Set<Marker> _staticMarkersFor(RideModel ride) {
    final key = '${ride.pickup.lat},${ride.pickup.lng}|${ride.drop.lat},${ride.drop.lng}|'
        '${ride.stops.map((s) => '${s.location.lat},${s.location.lng}').join(';')}|'
        '${ride.pickupAddress}|${ride.dropAddress}';
    if (key == _staticKey) return _staticMarkers;
    _staticKey = key;
    _staticMarkers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(ride.pickup.lat, ride.pickup.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(
          title: 'Pickup Location'.tr,
          snippet: ride.pickupAddress,
        ),
      ),
      Marker(
        markerId: const MarkerId('drop'),
        position: LatLng(ride.drop.lat, ride.drop.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(
          title: 'Drop Location'.tr,
          snippet: ride.dropAddress,
        ),
      ),
      for (int i = 0; i < ride.stops.length; i++)
        Marker(
          markerId: MarkerId('stop_$i'),
          position: LatLng(ride.stops[i].location.lat, ride.stops[i].location.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: 'Stop {n}'.trArgs({'n': i + 1}),
            snippet: ride.stops[i].address,
          ),
        ),
    };
    return _staticMarkers;
  }

  Set<Polyline> _polylinesFor(RouteView view) {
    if (view.version == _polylineVersion) return _polylines;
    _polylineVersion = view.version;
    _polylines = {
      if (view.points.length >= 2)
        Polyline(
          polylineId: const PolylineId('route'),
          points: view.points,
          color: const Color(0xFF1B6FF3), // route blue, same as the driver app
          width: 5,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
          // A straight-line fallback is drawn dashed so it doesn't pass for
          // the road route.
          patterns: view.approximate
              ? [PatternItem.dash(18), PatternItem.gap(10)]
              : const <PatternItem>[],
        ),
    };
    return _polylines;
  }

  /// Only this subtree rebuilds per animation frame / route trim.
  Widget _buildMap(RideModel ride, BitmapDescriptor driverIcon) {
    final initial = CameraPosition(target: LatLng(ride.pickup.lat, ride.pickup.lng), zoom: 15);
    return Listener(
      // Any touch on the map hands the camera to the rider until they tap
      // recenter.
      onPointerDown: (_) => _follow.value = false,
      child: AnimatedBuilder(
        animation: _mapListenable,
        builder: (context, _) {
          final pose = _animator.pose.value;
          return GoogleMap(
            style: AppMapStyle.muted,
            initialCameraPosition: initial,
            onMapCreated: (c) {
              _mapController = c;
              _placeCamera();
            },
            padding: _mapPadding.value,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            polylines: _polylinesFor(_route.view.value),
            markers: {
              ..._staticMarkersFor(ride),
              if (pose != null)
                Marker(
                  markerId: const MarkerId('driver'),
                  position: pose.position,
                  rotation: pose.rotation,
                  icon: driverIcon,
                  anchor: const Offset(0.5, 0.5),
                  flat: true,
                  zIndexInt: 2,
                ),
            },
          );
        },
      ),
    );
  }

  Future<void> _callDriver(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final trackingState = ref.watch(rideTrackingControllerProvider(widget.rideId));
    final controller = ref.read(rideTrackingControllerProvider(widget.rideId).notifier);
    final ride = trackingState.ride;
    final icons = ref.watch(vehicleMarkerIconsProvider).value;

    // The type the rider booked decides the marker (a Bike booking shows a
    // bike). Only when the ride doesn't carry it fall back to the vehicle
    // details, where a driver record saying 'car' used to win for bikes.
    final bookedIcon = ride?.vehicleIconType?.trim() ?? '';
    final family = bookedIcon.isNotEmpty
        ? VehicleMarkerIcons.familyFor(iconType: bookedIcon)
        : VehicleMarkerIcons.familyFor(
            vehicleType: ride?.vehicleType,
            vehicleMake: ride?.driver?.vehicleMake,
            vehicleModel: ride?.driver?.vehicleModel,
            serviceType: ride?.serviceType,
          );
    final driverIcon = icons?[family] ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure);

    ref.listen(rideTrackingControllerProvider(widget.rideId), (previous, next) {
      if (next.driverCancelSeq != (previous?.driverCancelSeq ?? 0) &&
          next.driverCancelSeq > _shownDriverCancelSeq) {
        _shownDriverCancelSeq = next.driverCancelSeq;
        final reason = next.driverCancelReason ?? '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showDriverCancelledDialog(reason);
        });
      }
      final r = next.ride;
      if (r != null && r.isCompleted && !_navigatedToRating) {
        _navigatedToRating = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pushReplacement('/taxi/rides/${widget.rideId}/rate');
        });
      }
      if (r != null && r.isCancelled && !_navigatedAway) {
        _navigatedAway = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.go('/taxi');
        });
      }
      // Camera no longer jumps here on every ride update / location packet:
      // see _onFix (first fix + throttled follow) and the recenter button.
    });

    WidgetsBinding.instance.addPostFrameCallback(_measureOverlays);

    if (trackingState.isLoading || ride == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        body: LoadingWidget(message: 'Loading your ride…'.tr),
      );
    }

    final statusLabel = _getStatusLabel(ride);
    final driver = ride.driver;
    final driverName = (driver?.name.isNotEmpty == true) ? driver!.name : 'Your driver'.tr;
    final vehicleDetails = (driver?.vehicleNumber.isNotEmpty == true)
        ? [driver!.vehicleNumber, if (driver.vehicleMake.isNotEmpty) driver.vehicleMake].join(' • ')
        : (ride.vehicleType?.isNotEmpty == true ? ride.vehicleType! : '');
    final driverRating = driver?.rating ?? 0.0;
    final driverPhone = driver?.phone ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // Google Map Background (Light Silver Muted Theme)
          _buildMap(ride, driverIcon),

          // Top Header Overlay (Light Theme Back Button, Live Pill Bar, SOS)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                key: _headerKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _LightCircleIconButton(
                        icon: Icons.arrow_back,
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _LiveStatusPill(rideId: widget.rideId),
                              const SizedBox(height: 3),
                              Text(
                                ride.pickupAddress.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _LightCircleIconButton(
                        icon: Icons.sos,
                        color: TaxiColors.error,
                        onTap: () => context.push('/taxi/sos?rideId=${widget.rideId}'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Recenter: shown once the rider has moved the map themselves.
          ValueListenableBuilder<EdgeInsets>(
            valueListenable: _mapPadding,
            builder: (context, padding, child) => Positioned(
              right: 16,
              bottom: padding.bottom + 12,
              child: child!,
            ),
            child: ValueListenableBuilder<bool>(
              valueListenable: _follow,
              builder: (context, following, _) => following
                  ? const SizedBox.shrink()
                  : Tooltip(
                      message: 'Recenter'.tr,
                      child: _LightCircleIconButton(
                        icon: Icons.my_location_rounded,
                        onTap: _recenter,
                      ),
                    ),
            ),
          ),

          // Bottom Sheet Panel (Light Theme UI with Driver Details, Call & Chat Options)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              key: _sheetKey,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Title & OTP Badge Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                statusLabel,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 18,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              // Local progress along the route; ~1 Hz, and
                              // only this line rebuilds for it.
                              ValueListenableBuilder<RouteView>(
                                valueListenable: _route.view,
                                builder: (context, view, _) {
                                  final eta = view.etaSeconds;
                                  final meters = view.remainingMeters;
                                  if (eta == null || meters == null || view.approximate) {
                                    return const SizedBox.shrink();
                                  }
                                  final arrival = DateTime.now().add(Duration(seconds: eta.round()));
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '{min} min · {km} km · Arrives {time}'.trArgs({
                                        'min': math.max(1, (eta / 60).ceil()),
                                        'km': (meters / 1000).toStringAsFixed(1),
                                        'time': DateFormat('h:mm a').format(arrival),
                                      }),
                                      style: const TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        // The OTP is only for boarding: hide it once the trip has started.
                        if (ride.otp.isNotEmpty &&
                            (ride.stage == RideStage.toPickup || ride.stage == RideStage.atPickup))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'OTP ',
                                  style: TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  ride.otp,
                                  style: const TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // --- ACCEPTED DRIVER DETAILS CARD WITH CHAT & CALL ---
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      ),
                      child: Row(
                        children: [
                          // Driver Avatar Box
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              image: (driver?.profileImage.isNotEmpty == true)
                                  ? DecorationImage(
                                      image: NetworkImage(driver!.profileImage),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: (driver?.profileImage.isEmpty ?? true)
                                ? const Icon(Icons.person_outline_rounded, color: Color(0xFF0F172A), size: 24)
                                : null,
                          ),
                          const SizedBox(width: 12),

                          // Driver Info Text Column
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driverName.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  vehicleDetails,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                                    const SizedBox(width: 3),
                                    Text(
                                      driverRating > 0 ? driverRating.toStringAsFixed(1) : 'New'.tr,
                                      style: const TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Call & Chat Buttons
                          _LightIconButton(
                            icon: Icons.chat_bubble_outline_rounded,
                            badge: (ride.messages.where((m) => !m.isFromRider).length -
                                    ref.watch(rideChatSeenProvider(widget.rideId)))
                                .clamp(0, 99)
                                .toInt(),
                            onTap: () => context.push('/taxi/rides/${widget.rideId}/chat'),
                          ),
                          const SizedBox(width: 8),
                          _LightIconButton(
                            icon: Icons.call_outlined,
                            onTap: () => _callDriver(driverPhone),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pickup, Drop & Stops Address Timeline Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF00C853),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  ride.pickupAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                height: 12,
                                child: VerticalDivider(color: Color(0xFFCBD5E1), thickness: 1.5),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 14, color: Color(0xFFE5A600)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  ride.dropAddress,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          for (int i = 0; i < ride.stops.length; i++) ...[
                            const Padding(
                              padding: EdgeInsets.only(left: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: SizedBox(
                                  height: 12,
                                  child: VerticalDivider(color: Color(0xFFCBD5E1), thickness: 1.5),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.location_on, size: 14, color: Color(0xFF3B82F6)),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Stop {n}: {address}'.trArgs({'n': i + 1, 'address': ride.stops[i].address}),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFF334155),
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Cancel Ride Button (if ride is cancellable)
                    if (_isCancellable(ride.status))
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: trackingState.isCancelling
                              ? null
                              : () => _confirmCancel(context, controller),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFCA5A5), width: 1.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            trackingState.isCancelling ? 'Cancelling…'.tr : 'Cancel ride'.tr,
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 0.5,
                            ),
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
    );
  }

  String _getStatusLabel(RideModel ride) {
    switch (ride.stage) {
      case RideStage.searching:
        return 'Finding your driver…'.tr;
      case RideStage.toPickup:
        return 'Driver is on the way'.tr;
      case RideStage.atPickup:
        return 'Driver has arrived at pickup'.tr;
      case RideStage.onTrip:
        return 'Trip in progress'.tr;
      case RideStage.atDrop:
        return 'Reached destination'.tr;
      case RideStage.completed:
        return 'Ride completed'.tr;
      case RideStage.cancelled:
        return 'Ride cancelled'.tr;
    }
  }

  Future<void> _showDriverCancelledDialog(String reason) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.cancel_rounded, color: Color(0xFFE53935), size: 40),
        title: Text('Driver cancelled your ride'.tr, textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (reason.isNotEmpty) ...[
              Text('Reason: {reason}'.trArgs({'reason': reason}), textAlign: TextAlign.center),
              const SizedBox(height: 8),
            ],
            Text(
              'We are finding you another driver.'.tr,
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Okay'.tr),
          ),
        ],
      ),
    );
  }

  bool _isCancellable(String status) {
    final s = status.toLowerCase();
    return s == 'requested' || s == 'searching' || s == 'accepted';
  }

  Future<void> _confirmCancel(BuildContext context, RideTrackingController controller) async {
    final reason = await askCancelReason(
      context,
      title: 'Cancel this ride?',
      reasons: CancelReasons.ride,
      confirmLabel: 'Yes, cancel ride',
      keepLabel: 'Keep ride',
    );
    if (reason == null) return;
    final success = await controller.cancelRide(reason: reason);
    if (success && context.mounted) context.go('/taxi');
  }
}

class _LightCircleIconButton extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final VoidCallback onTap;

  const _LightCircleIconButton({
    required this.icon,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(side: BorderSide(color: Color(0xFFE2E8F0), width: 1.2)),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(icon, color: color ?? const Color(0xFF0F172A), size: 20),
        ),
      ),
    );
  }
}

class _LightIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  /// Unread count shown as a dot on the corner; hidden at 0.
  final int badge;

  const _LightIconButton({required this.icon, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF0F172A), size: 20),
        ),
      ),
    );
    if (badge <= 0) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          top: -4,
          right: -4,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              alignment: Alignment.center,
              child: Text(
                badge > 9 ? '9+' : '$badge',
                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// LIVE / stale indicator for the header.
///
/// Rebuilds only itself — on each accepted fix, and once a second to keep
/// "Last updated Xs ago" honest while the feed is quiet.
class _LiveStatusPill extends ConsumerStatefulWidget {
  final String rideId;
  const _LiveStatusPill({required this.rideId});

  @override
  ConsumerState<_LiveStatusPill> createState() => _LiveStatusPillState();
}

class _LiveStatusPillState extends ConsumerState<_LiveStatusPill> {
  /// No fix for this long and the position is shown as stale.
  static const _staleAfter = Duration(seconds: 15);

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fix = ref.watch(driverLocationProvider(widget.rideId));

    final String label;
    final Color color;
    final IconData icon;
    if (fix == null) {
      label = 'Locating driver…'.tr;
      color = const Color(0xFF64748B);
      icon = Icons.sensors;
    } else if (fix.age < _staleAfter) {
      label = 'LIVE TRACKING'.tr;
      color = const Color(0xFF00C853);
      icon = Icons.sensors;
    } else {
      final age = fix.age;
      label = age.inMinutes >= 1
          ? 'Last updated {m} min ago'.trArgs({'m': age.inMinutes})
          : 'Last updated {s}s ago'.trArgs({'s': age.inSeconds});
      color = const Color(0xFFB45309);
      icon = Icons.sensors_off;
    }

    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}
