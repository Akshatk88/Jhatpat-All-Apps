import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'gps_fix_filter.dart';

/// Streams GPS positions while the partner is online. On Android this runs
/// as a foreground service with a persistent notification (via geolocator's
/// `foregroundNotificationConfig`) so pings keep flowing when the app is
/// backgrounded; on iOS it relies on the `location` background mode.
class LocationService {
  StreamSubscription<Position>? _positionSubscription;
  final _positionController = StreamController<Position>.broadcast();
  Position? lastPosition;

  Stream<Position> get positionStream => _positionController.stream;
  bool get isTracking => _positionSubscription != null;

  Future<bool> ensurePermissions() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    if (Platform.isAndroid) {
      final backgroundStatus = await Permission.locationAlways.status;
      if (!backgroundStatus.isGranted) {
        await Permission.locationAlways.request();
      }
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        await Permission.notification.request();
      }
    }
    return true;
  }

  /// Drops unusable fixes (bad coords, poor accuracy, out-of-order, impossible
  /// jumps) before any consumer — map marker, ride feed, dispatch ping — sees
  /// them. See [GpsFixFilter].
  final GpsFixFilter _filter = GpsFixFilter();

  /// True while a ride is being driven: the stream runs at a finer cadence
  /// (2 s / 5 m instead of 5 s / 15 m) so the passenger's marker moves
  /// smoothly. Online-but-idle keeps the battery-friendly setting.
  bool _rideMode = false;
  bool get rideMode => _rideMode;

  /// Switches the stream cadence for an active ride. Restarts the stream only
  /// when it is running and the mode actually changes.
  void setRideMode(bool enabled) {
    if (_rideMode == enabled) return;
    _rideMode = enabled;
    if (!isTracking) return;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    startTracking();
  }

  void startTracking() {
    if (isTracking) return;

    final distanceFilter = _rideMode ? 5 : 15;
    final locationSettings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilter,
            intervalDuration: Duration(seconds: _rideMode ? 2 : 5),
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'You are online',
              notificationText: 'Sharing your live location for deliveries',
              enableWakeLock: true,
              notificationIcon: AndroidResource(name: 'ic_stat_jhatpat', defType: 'drawable'),
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilter,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    late final StreamSubscription<Position> sub;
    sub = _positionSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen(
              (pos) {
                if (!_filter.accept(pos)) return;
                lastPosition = pos;
                _positionController.add(pos);
              },
              // A provider error (GPS switched off, permission revoked) must
              // not kill the subscription silently with an unhandled error.
              onError: (Object _) {},
              // The platform closed the stream (location turned off): let the
              // next startTracking() open a fresh one instead of believing a
              // dead subscription is still tracking.
              onDone: () {
                if (identical(_positionSubscription, sub)) {
                  _positionSubscription = null;
                }
              },
            );
  }

  void stopTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _filter.reset();
  }

  void dispose() {
    stopTracking();
    _positionController.close();
  }
}

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = LocationService();
  ref.onDispose(service.dispose);
  return service;
});
