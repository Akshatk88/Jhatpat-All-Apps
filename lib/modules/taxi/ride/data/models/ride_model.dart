import 'package:superapp_user/modules/taxi/ride/data/models/ride_message_model.dart';

class LatLngPoint {
  final double lat;
  final double lng;
  const LatLngPoint({required this.lat, required this.lng});

  factory LatLngPoint.fromGeoJson(dynamic geo) {
    if (geo is Map) {
      if (geo['coordinates'] is List && (geo['coordinates'] as List).length >= 2) {
        final coords = geo['coordinates'] as List;
        return LatLngPoint(
          lat: double.tryParse('${coords[1]}') ?? 0,
          lng: double.tryParse('${coords[0]}') ?? 0,
        );
      }
      final lat = double.tryParse('${geo['lat'] ?? geo['latitude'] ?? 0}') ?? 0;
      final lng = double.tryParse('${geo['lng'] ?? geo['longitude'] ?? 0}') ?? 0;
      if (lat != 0 || lng != 0) {
        return LatLngPoint(lat: lat, lng: lng);
      }
    } else if (geo is List && geo.length >= 2) {
      return LatLngPoint(
        lat: double.tryParse('${geo[1]}') ?? 0,
        lng: double.tryParse('${geo[0]}') ?? 0,
      );
    }
    return const LatLngPoint(lat: 0, lng: 0);
  }
}

class RideDriverInfo {
  final String id;
  final String name;
  final String phone;
  final String profileImage;
  final String vehicleNumber;
  final String vehicleModel;
  final String vehicleMake;
  final double rating;

  const RideDriverInfo({
    required this.id,
    required this.name,
    required this.phone,
    required this.profileImage,
    required this.vehicleNumber,
    required this.vehicleModel,
    required this.vehicleMake,
    required this.rating,
  });

  factory RideDriverInfo.fromJson(Map<String, dynamic> json) {
    return RideDriverInfo(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      profileImage: (json['profileImage'] ?? json['profile_image'] ?? '').toString(),
      vehicleNumber: (json['vehicleNumber'] ?? json['vehicle_number'] ?? '').toString(),
      vehicleModel: (json['vehicleModel'] ?? json['vehicle_model'] ?? '').toString(),
      vehicleMake: (json['vehicleMake'] ?? json['vehicle_make'] ?? '').toString(),
      rating: double.tryParse('${json['rating'] ?? 0}') ?? 0,
    );
  }
}

class RideStopPoint {
  final LatLngPoint location;
  final String address;
  const RideStopPoint({required this.location, required this.address});

  factory RideStopPoint.fromJson(Map<String, dynamic> json) {
    double lat = 0;
    double lng = 0;
    if (json['lat'] != null) lat = double.tryParse('${json['lat']}') ?? 0;
    if (json['lng'] != null) lng = double.tryParse('${json['lng']}') ?? 0;
    if (lat == 0 && json['location'] != null) {
      final p = LatLngPoint.fromGeoJson(json['location']);
      lat = p.lat;
      lng = p.lng;
    }
    return RideStopPoint(
      location: LatLngPoint(lat: lat, lng: lng),
      address: (json['address'] ?? json['name'] ?? '').toString(),
    );
  }
}

class RideModel {
  final String rideId;
  final String status;
  final String liveStatus;
  final double fare;
  final double baseFare;
  final double estimatedDistanceMeters;
  final double estimatedDurationMinutes;
  final String? paymentMethod;
  /// Encoded route for the current leg, resolved server-side.
  final String routePolyline;
  final String otp;
  final LatLngPoint pickup;
  final String pickupAddress;
  final LatLngPoint drop;
  final String dropAddress;
  final List<RideStopPoint> stops;
  final DateTime? scheduledAt;
  final DateTime? acceptedAt;
  final DateTime? arrivedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final RideDriverInfo? driver;
  final LatLngPoint? lastDriverLocation;
  final double? lastDriverHeading;

  /// Server time of [lastDriverLocation] (`lastDriverLocation.updatedAt`).
  /// Lets live tracking tell a fresh REST/`ride:state` fix from one that is
  /// older than what the socket already delivered.
  final DateTime? lastDriverLocationAt;
  final List<RideMessageModel> messages;
  final String? serviceType;
  final String? vehicleType;
  /// The catalog's icon family for the assigned driver's vehicle. This is what
  /// the backend actually sends; `vehicleType` is absent from every ride
  /// payload, so relying on it alone always fell through to the car default.
  final String? vehicleIconType;

  const RideModel({
    required this.rideId,
    required this.status,
    required this.liveStatus,
    required this.fare,
    required this.baseFare,
    required this.estimatedDistanceMeters,
    required this.estimatedDurationMinutes,
    required this.paymentMethod,
    this.routePolyline = '',
    required this.otp,
    required this.pickup,
    required this.pickupAddress,
    required this.drop,
    required this.dropAddress,
    this.stops = const [],
    this.scheduledAt,
    this.acceptedAt,
    this.arrivedAt,
    this.startedAt,
    this.completedAt,
    this.driver,
    this.lastDriverLocation,
    this.lastDriverHeading,
    this.lastDriverLocationAt,
    this.messages = const [],
    this.serviceType,
    this.vehicleType,
    this.vehicleIconType,
  });

  factory RideModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

    final pickupGeo = json['pickupLocation'] ?? json['pickup'] ?? json['pickup_location'];
    final dropGeo = json['dropLocation'] ?? json['drop'] ?? json['drop_location'];

    return RideModel(
      rideId: (json['rideId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      liveStatus: (json['liveStatus'] ?? json['status'] ?? '').toString(),
      fare: double.tryParse('${json['fare'] ?? json['totalFare'] ?? json['total_fare'] ?? json['amount'] ?? json['cost'] ?? 0}') ?? 0,
      baseFare: double.tryParse('${json['baseFare'] ?? json['base_fare'] ?? json['fare'] ?? 0}') ?? 0,
      estimatedDistanceMeters:
          double.tryParse('${json['estimatedDistanceMeters'] ?? json['estimated_distance_meters'] ?? json['distance'] ?? 0}') ?? 0,
      estimatedDurationMinutes:
          double.tryParse('${json['estimatedDurationMinutes'] ?? json['estimated_duration_minutes'] ?? json['duration'] ?? 0}') ?? 0,
      paymentMethod: (json['paymentMethod'] ?? json['payment_method'] ?? 'cash').toString(),
      routePolyline: ((json['route'] is Map
              ? ((json['route'] as Map)['polyline'] ?? (json['route'] as Map)['encodedPolyline'])
              : null) ??
          json['polyline'] ??
          json['encodedPolyline'] ??
          json['routePolyline'] ??
          (json['route'] is String ? json['route'] : '') ??
          '').toString(),
      otp: (json['otp'] ?? '').toString(),
      pickup: LatLngPoint.fromGeoJson(pickupGeo),
      pickupAddress: (json['pickupAddress'] ?? json['pickup_address'] ?? json['pickupAddressName'] ?? '').toString(),
      drop: LatLngPoint.fromGeoJson(dropGeo),
      dropAddress: (json['dropAddress'] ?? json['drop_address'] ?? json['dropAddressName'] ?? '').toString(),
      stops: ((json['stops'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => RideStopPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      scheduledAt: parseDate(json['scheduledAt'] ?? json['scheduled_at']),
      acceptedAt: parseDate(json['acceptedAt'] ?? json['accepted_at']),
      arrivedAt: parseDate(json['arrivedAt'] ?? json['arrived_at']),
      startedAt: parseDate(json['startedAt'] ?? json['started_at']),
      completedAt: parseDate(json['completedAt'] ?? json['completed_at'] ?? json['createdAt'] ?? json['created_at']),
      driver: json['driver'] is Map && (json['driver'] as Map).isNotEmpty
          ? RideDriverInfo.fromJson(Map<String, dynamic>.from(json['driver']))
          : null,
      lastDriverLocation: json['lastDriverLocation'] != null
          ? LatLngPoint.fromGeoJson(json['lastDriverLocation'])
          : null,
      lastDriverHeading: json['lastDriverLocation'] is Map
          ? double.tryParse('${json['lastDriverLocation']['heading'] ?? ''}')
          : null,
      lastDriverLocationAt: json['lastDriverLocation'] is Map
          ? parseDate(json['lastDriverLocation']['updatedAt'])
          : null,
      messages: ((json['messages'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => RideMessageModel.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      serviceType: (json['serviceType'] ?? json['service_type'])?.toString(),
      vehicleType: (json['vehicleType'] ?? json['vehicle_type'] ?? json['vehicleTypeName'])?.toString(),
      vehicleIconType: (json['vehicleIconType'] ?? json['vehicle_icon_type'])?.toString(),
    );
  }

  RideModel copyWith({
    String? status,
    String? liveStatus,
    RideDriverInfo? driver,
    LatLngPoint? lastDriverLocation,
    double? lastDriverHeading,
    List<RideMessageModel>? messages,
    DateTime? acceptedAt,
    DateTime? arrivedAt,
    DateTime? startedAt,
    DateTime? completedAt,
  }) {
    return RideModel(
      rideId: rideId,
      status: status ?? this.status,
      liveStatus: liveStatus ?? this.liveStatus,
      fare: fare,
      baseFare: baseFare,
      estimatedDistanceMeters: estimatedDistanceMeters,
      estimatedDurationMinutes: estimatedDurationMinutes,
      paymentMethod: paymentMethod,
      routePolyline: routePolyline,
      otp: otp,
      pickup: pickup,
      pickupAddress: pickupAddress,
      drop: drop,
      dropAddress: dropAddress,
      stops: stops,
      scheduledAt: scheduledAt,
      acceptedAt: acceptedAt ?? this.acceptedAt,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      driver: driver ?? this.driver,
      lastDriverLocation: lastDriverLocation ?? this.lastDriverLocation,
      lastDriverHeading: lastDriverHeading ?? this.lastDriverHeading,
      lastDriverLocationAt: lastDriverLocationAt,
      messages: messages ?? this.messages,
      // Previously omitted, so every copyWith silently reset these to null —
      // which reset the map's vehicle marker back to the default on the first
      // status or location update.
      serviceType: serviceType,
      vehicleType: vehicleType,
      vehicleIconType: vehicleIconType,
    );
  }

  /// True once the trip is finished, by either status axis.
  ///
  /// The server carries two: `status` (searching/accepted/ongoing/completed)
  /// and `liveStatus` (which adds arriving/arrived/started). Reading only one
  /// means a payload that advances the other is missed.
  bool get isCompleted =>
      status.toLowerCase() == 'completed' || liveStatus.toLowerCase() == 'completed';

  bool get isCancelled =>
      status.toLowerCase() == 'cancelled' || liveStatus.toLowerCase() == 'cancelled';

  /// Where the trip is, reading both status axes.
  ///
  /// k9 naming is not the obvious one: `arriving` means the driver is **at the
  /// pickup**, `started` is the pickup (OTP verified), and `arrived` means the
  /// trip **reached the drop**. `status` only says searching/accepted/ongoing/
  /// completed, so `liveStatus` wins whenever it is more specific.
  RideStage get stage {
    if (isCancelled) return RideStage.cancelled;
    if (isCompleted) return RideStage.completed;
    final ls = liveStatus.toLowerCase();
    final s = status.toLowerCase();
    if (ls == 'arrived') return RideStage.atDrop;
    if (ls == 'started' || s == 'ongoing' || s == 'started' || s == 'in_progress') {
      return RideStage.onTrip;
    }
    if (ls == 'arriving' || s == 'arriving' || s == 'driver_arrived') {
      return RideStage.atPickup;
    }
    if (ls == 'accepted' || s == 'accepted') return RideStage.toPickup;
    return RideStage.searching;
  }
}

/// Passenger-facing ride stage; see [RideModel.stage].
enum RideStage { searching, toPickup, atPickup, onTrip, atDrop, completed, cancelled }
