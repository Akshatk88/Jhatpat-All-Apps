import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:superapp_user/core/maps/geo_math.dart';
import 'package:superapp_user/core/realtime/taxi_socket_events.dart';
import 'package:superapp_user/core/realtime/taxi_socket_service.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_controller.dart';

/// One accepted driver position.
class DriverFix {
  final LatLng position;

  /// Degrees clockwise from north, or null when the device gave none.
  final double? heading;

  /// As sent by the driver app (m/s from the platform location APIs).
  final double? speed;

  /// Reported GPS accuracy in metres, when the payload carries one.
  final double? accuracy;

  /// Server time the fix was stored (`updatedAt`). Used only for ordering.
  final DateTime? serverTime;

  /// Local time the fix became known — what "last updated Xs ago" and the
  /// stale check are measured against (local clock, so server skew can't
  /// make a live fix look stale).
  final DateTime receivedAt;

  /// Increments with every accepted fix.
  final int seq;

  const DriverFix({
    required this.position,
    required this.receivedAt,
    required this.seq,
    this.heading,
    this.speed,
    this.accuracy,
    this.serverTime,
  });

  Duration get age => DateTime.now().difference(receivedAt);
}

/// Live driver position for one ride, kept apart from the ride itself.
///
/// Before, every `ride:driver-location:updated` packet was copied into the
/// [RideTrackingController] state — a new `RideModel`, and a rebuild of the
/// whole tracking screen (map, sheet, chat badge) per GPS packet. Now only
/// the map listens to this.
///
/// Sources: the socket packet (live) and `lastDriverLocation` on the ride
/// from REST / `ride:state` (seed and resync). Only a fix newer than the
/// current one (by server `updatedAt`) is accepted; invalid coordinates are
/// dropped.
///
/// Auto-disposed: the socket handler is removed as soon as no tracking
/// screen is listening.
class DriverLocationController extends Notifier<DriverFix?> {
  DriverLocationController(this.rideId);

  final String rideId;
  late TaxiSocketService _socket;

  /// Mirror of `state`, readable before the first build has completed.
  DriverFix? _current;

  @override
  DriverFix? build() {
    _socket = ref.read(taxiSocketServiceProvider);
    _socket.on(SocketEvents.rideDriverLocationUpdated, _onPacket);
    ref.onDispose(() => _socket.off(SocketEvents.rideDriverLocationUpdated, _onPacket));

    // A record compares by value, so this fires only when the ride's stored
    // fix actually changes — not on every poll that returns the same one.
    final seed = ref.listen(
      rideTrackingControllerProvider(rideId).select((s) {
        final r = s.ride;
        return (
          r?.lastDriverLocation?.lat,
          r?.lastDriverLocation?.lng,
          r?.lastDriverLocationAt,
          r?.lastDriverHeading,
        );
      }),
      (_, next) => _publish(_snapshotFix(next)),
    );

    _current = _snapshotFix(seed.read());
    return _current;
  }

  DriverFix? _snapshotFix((double?, double?, DateTime?, double?) s) => _evaluate(
        lat: s.$1,
        lng: s.$2,
        serverTime: s.$3,
        heading: s.$4,
        live: false,
      );

  void _publish(DriverFix? fix) {
    if (fix == null) return;
    _current = fix;
    state = fix;
  }

  void _onPacket(dynamic data) {
    if (data is! Map) return;
    final id = (data['rideId'] ?? data['_id'] ?? data['id'] ?? '').toString();
    if (id.isNotEmpty && id != rideId) return;

    double? lat;
    double? lng;
    final coords = data['coordinates'];
    if (coords is List && coords.length >= 2) {
      lng = double.tryParse('${coords[0]}');
      lat = double.tryParse('${coords[1]}');
    } else {
      lat = double.tryParse('${data['lat'] ?? data['latitude'] ?? ''}');
      lng = double.tryParse('${data['lng'] ?? data['longitude'] ?? ''}');
    }
    _publish(_evaluate(
      lat: lat,
      lng: lng,
      heading: double.tryParse('${data['heading'] ?? ''}'),
      speed: double.tryParse('${data['speed'] ?? ''}'),
      accuracy: double.tryParse('${data['accuracy'] ?? ''}'),
      serverTime: DateTime.tryParse('${data['updatedAt'] ?? ''}'),
      live: true,
    ));
  }

  /// The fix these values make, or null when they must be dropped.
  DriverFix? _evaluate({
    required double? lat,
    required double? lng,
    double? heading,
    double? speed,
    double? accuracy,
    DateTime? serverTime,
    required bool live,
  }) {
    if (!GeoMath.isValid(lat, lng)) return null;
    final current = _current;

    if (current != null) {
      // Out-of-order or replayed packet (the server awaits a DB write between
      // stamping and emitting, so two packets can overtake each other), or a
      // poll returning the fix the socket already delivered.
      if (serverTime != null &&
          current.serverTime != null &&
          !serverTime.isAfter(current.serverTime!)) {
        return null;
      }
      // An untimed snapshot can't be ordered: never let it override a fix.
      if (!live && (serverTime == null || current.serverTime == null)) return null;
    }

    final now = DateTime.now();
    var receivedAt = now;
    if (!live && serverTime != null) {
      // A REST / ride:state seed may be minutes old (driver app backgrounded).
      // Age it by server time, but only when clearly old so ordinary clock
      // skew between phone and server doesn't flag a fresh fix as stale.
      final age = now.difference(serverTime.toLocal());
      if (age > const Duration(seconds: 20)) receivedAt = now.subtract(age);
    }

    return DriverFix(
      position: LatLng(lat!, lng!),
      heading: (heading != null && heading.isFinite) ? GeoMath.normalizeAngle(heading) : null,
      speed: (speed != null && speed.isFinite && speed >= 0) ? speed : null,
      accuracy: (accuracy != null && accuracy.isFinite && accuracy > 0) ? accuracy : null,
      serverTime: serverTime,
      receivedAt: receivedAt,
      seq: (current?.seq ?? 0) + 1,
    );
  }
}

final driverLocationProvider =
    NotifierProvider.autoDispose.family<DriverLocationController, DriverFix?, String>(
  DriverLocationController.new,
);
