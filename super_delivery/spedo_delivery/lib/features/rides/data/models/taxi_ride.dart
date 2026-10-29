import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Server-side ride lifecycle (`RIDE_LIVE_STATUS` in the k9 backend).
///
/// The driver drives the transitions with
/// `PATCH /taxi/rides/:rideId/status { status }`, which accepts only
/// accepted / arriving / arrived / started / completed.
///
/// What each status *means* is fixed by the backend and the passenger app, not
/// by the word:
///  * `accepted`  — driver took the job and is heading to the pickup. The only
///                  status from which the driver may cancel
///                  (`cancelActiveRideByDriver` 409s on anything else).
///  * `arriving`  — driver is **at the pickup**. The passenger app starts its
///                  "driver arrived" clock on it, and the server stamps
///                  `arrivedAt` (the waiting-charge clock) once the driver's
///                  `locationUpdate` is within 500 m of the pickup.
///  * `started`   — OTP verified, passenger / parcel on board.
///  * `arrived`   — reached the drop; the server finalises the fare here.
///  * `completed` — paid and closed; wallet settlement runs.
enum RideStage {
  /// Dispatch is still offering the ride; no driver has taken it.
  searching,

  /// This driver took it and is driving to the pickup.
  accepted,

  /// At the pickup, waiting for the passenger / parcel.
  arriving,

  /// Passenger on board, trip in progress.
  ///
  /// Note the ordering: in k9 `started` is the **pickup** and comes *before*
  /// `arrived`. Entering it requires the passenger's OTP.
  started,

  /// Reached the destination. The trip has run; the fare is not settled yet.
  arrived,

  /// Dropped off and paid.
  completed,

  cancelled;

  static RideStage parse(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'accepted':
        return RideStage.accepted;
      case 'arriving':
        return RideStage.arriving;
      case 'arrived':
        return RideStage.arrived;
      case 'started':
      case 'ongoing':
        return RideStage.started;
      case 'completed':
        return RideStage.completed;
      case 'cancelled':
      case 'canceled':
        return RideStage.cancelled;
      default:
        return RideStage.searching;
    }
  }

  /// Wire value for the status endpoint.
  String get wire => name;

  bool get isActive =>
      this == RideStage.accepted ||
      this == RideStage.arriving ||
      this == RideStage.arrived ||
      this == RideStage.started;

  bool get isFinished =>
      this == RideStage.completed || this == RideStage.cancelled;

  /// True once the passenger is in the car, which is what decides whether the
  /// driver is navigating to the pickup or to the drop.
  bool get isOnBoard => this == RideStage.started || this == RideStage.arrived;

  /// The backend only lets the driver release a ride before reaching the
  /// pickup (`liveStatus === 'accepted'`).
  bool get driverCanCancel => this == RideStage.accepted;

  /// The single transition the driver can make from here, or null at the end
  /// of the flow. Keeping this on the enum stops each screen inventing its own
  /// idea of what "next" means — and this sequence is not the obvious one:
  /// `started` (pickup) precedes `arrived` (reached the destination).
  ///
  /// `searching` maps to nothing: an offer is claimed over the socket, not by
  /// a status transition, because acceptance has to be an atomic first-wins
  /// claim rather than a write to a ride this driver does not yet hold.
  RideStage? get next {
    switch (this) {
      case RideStage.accepted:
        return RideStage.arriving;
      case RideStage.arriving:
        return RideStage.started;
      case RideStage.started:
        return RideStage.arrived;
      case RideStage.arrived:
        return RideStage.completed;
      case RideStage.searching:
      case RideStage.completed:
      case RideStage.cancelled:
        return null;
    }
  }

  /// The backend refuses to start a ride without the OTP the passenger reads
  /// out — that is the only proof the right person got in the car.
  bool get nextNeedsOtp => next == RideStage.started;

  /// The last step settles the fare and cannot be undone from the app.
  bool get nextSettlesFare => next == RideStage.completed;

  /// Label for the primary action button.
  String get actionLabel => actionLabelFor(isParcel: false);

  String actionLabelFor({required bool isParcel}) {
    switch (this) {
      case RideStage.searching:
        return 'Accept ride';
      case RideStage.accepted:
        return isParcel ? 'Arrived at sender' : 'Arrived at pickup';
      case RideStage.arriving:
        return isParcel ? 'Parcel picked up' : 'Start trip';
      case RideStage.started:
        return isParcel ? 'Reached receiver' : 'Reached destination';
      case RideStage.arrived:
        return isParcel ? 'Complete delivery' : 'Complete trip';
      case RideStage.completed:
      case RideStage.cancelled:
        return 'Done';
    }
  }

  String get headline => headlineFor(isParcel: false);

  String headlineFor({required bool isParcel}) {
    switch (this) {
      case RideStage.searching:
        return isParcel ? 'New delivery request' : 'New ride request';
      case RideStage.accepted:
        return isParcel ? 'Head to the sender' : 'Head to pickup';
      case RideStage.arriving:
        return isParcel ? 'At the sender' : 'Waiting at pickup';
      case RideStage.started:
        return isParcel ? 'Delivering parcel' : 'Trip in progress';
      case RideStage.arrived:
        return 'Collect payment';
      case RideStage.completed:
        return isParcel ? 'Delivery completed' : 'Trip completed';
      case RideStage.cancelled:
        return isParcel ? 'Delivery cancelled' : 'Ride cancelled';
    }
  }
}

/// The passenger, as far as the driver needs to know.
class RidePassenger {
  const RidePassenger({
    required this.id,
    required this.name,
    required this.phone,
  });

  final String id;
  final String name;
  final String phone;

  factory RidePassenger.fromJson(Map? json) {
    final j = json ?? const {};
    return RidePassenger(
      id: (j['id'] ?? j['_id'] ?? '').toString(),
      name: (j['name'] ?? 'Customer').toString(),
      phone: (j['phone'] ?? '').toString(),
    );
  }
}

/// One message in the ride's in-app chat (`ride:message:new`).
class RideChatMessage {
  const RideChatMessage({
    required this.id,
    required this.senderRole,
    required this.message,
    this.sentAt,
  });

  final String id;

  /// `driver` | `user`.
  final String senderRole;
  final String message;
  final DateTime? sentAt;

  bool get isMine => senderRole == 'driver';

  factory RideChatMessage.fromJson(Map json) => RideChatMessage(
        id: (json['id'] ?? json['_id'] ?? '').toString(),
        senderRole: (json['senderRole'] ?? '').toString(),
        message: (json['message'] ?? '').toString(),
        sentAt: DateTime.tryParse((json['sentAt'] ?? '').toString())?.toLocal(),
      );
}

/// A ride, whether it is being offered or already in progress.
///
/// The dispatch socket payload (`rideRequest`) and the REST ride document use
/// overlapping but not identical shapes, so both are parsed here rather than
/// having two near-duplicate models drift apart.
class TaxiRide {
  const TaxiRide({
    required this.id,
    required this.stage,
    required this.passenger,
    required this.pickupAddress,
    required this.dropAddress,
    this.pickup,
    this.drop,
    this.fare = 0,
    this.distanceMeters = 0,
    this.durationMinutes = 0,
    this.paymentMethod = 'cash',
    this.otp,
    this.vehicleTypeName = '',
    this.serviceType = 'ride',
    this.expiresInSeconds,
    this.isDriveU = false,
    this.driveUVehicleName = '',
    this.driveUTransmission = '',
    this.bonus = 0,
    this.parcelPickupPhotos = const [],
    this.parcelDeliveryPhotos = const [],
    this.senderName = '',
    this.senderPhone = '',
    this.receiverName = '',
    this.receiverPhone = '',
    this.parcelCategory = '',
    this.parcelWeight = '',
    this.arrivedAt,
    this.startedAt,
    this.waitingChargeAmount = 0,
    this.waitingChargePerMinute = 0,
    this.freeWaitingMinutes = 0,
    this.driverCancellationFee = 0,
    this.driverCancellationFeeIsPercent = false,
    this.driverEarnings,
    this.messages = const [],
  });

  final String id;
  final RideStage stage;
  final RidePassenger passenger;
  final String pickupAddress;
  final String dropAddress;
  final LatLng? pickup;
  final LatLng? drop;
  final double fare;

  /// Extra on top of [fare] (incentive / bonus / tip), shown as "+₹X" on an
  /// offer. 0 when the payload carries none.
  final double bonus;
  final int distanceMeters;
  final int durationMinutes;
  final String paymentMethod;

  /// Start OTP, when the payload carries one.
  ///
  /// Never shown to the driver: the passenger reads it out and the driver types
  /// it in, which is what makes it proof the right person got in the car.
  /// Displaying it here would reduce it to a formality.
  final String? otp;

  final String vehicleTypeName;

  /// `ride` or `parcel` — dispatch uses one channel for all.
  final String serviceType;

  /// Only present on an offer: how long the driver has to accept.
  final int? expiresInSeconds;

  /// DriveU: the driver drives the passenger's own car and brings none of their
  /// own.
  ///
  /// This changes what the driver is agreeing to, not just how the job is
  /// priced — they arrive on their own transport and take the wheel of someone
  /// else's vehicle. A ride that does not say so is an ordinary one.
  final bool isDriveU;

  /// The passenger's car, on a DriveU job — what they typed when booking.
  /// Empty on rides booked before the app collected it, so the UI has to treat
  /// blank as "not stated" rather than showing an empty label.
  final String driveUVehicleName;

  /// `manual` | `automatic` | ''. A hard constraint: a driver who cannot drive
  /// a manual should decline rather than discover it at the pickup.
  final String driveUTransmission;

  /// Proof photos the captain already filed for this parcel (hosted URLs), from
  /// `parcel.pickupPhotos` / `parcel.deliveryPhotos` on the ride document.
  /// Empty on passenger rides and offers.
  final List<String> parcelPickupPhotos;
  final List<String> parcelDeliveryPhotos;

  /// Parcel contacts (`parcel.senderName/senderMobile/receiverName/
  /// receiverMobile`). The booking user is often neither, so the call button
  /// rings these on a parcel job.
  final String senderName;
  final String senderPhone;
  final String receiverName;
  final String receiverPhone;
  final String parcelCategory;
  final String parcelWeight;

  /// Server-stamped when the driver was actually within 500 m of the pickup
  /// in `arriving` — the start of the waiting clock. Null until then.
  final DateTime? arrivedAt;
  final DateTime? startedAt;

  /// Waiting charge as the server computed it (set on `started`, re-checked on
  /// `arrived` / `completed`).
  final double waitingChargeAmount;

  /// `pricingSnapshot.waiting_charge` (₹ per minute) and
  /// `pricingSnapshot.free_waiting_before` (free minutes at the pickup).
  final double waitingChargePerMinute;
  final double freeWaitingMinutes;

  /// `pricingSnapshot.driver_cancellation_fee` (+ `_type`), for the warning in
  /// the cancel sheet.
  final double driverCancellationFee;
  final bool driverCancellationFeeIsPercent;

  /// Set by the server on completion (settlement).
  final double? driverEarnings;

  /// The last messages of the ride chat, as the ride document carries them.
  final List<RideChatMessage> messages;

  bool get isCash => paymentMethod.toLowerCase() == 'cash';

  /// A parcel job rather than a passenger. k9 stores `serviceType: 'parcel'`
  /// (Ride.js enum `ride | parcel`); `delivery` is accepted too
  /// since older payloads used it.
  bool get isParcel {
    final t = serviceType.trim().toLowerCase();
    return t == 'parcel' || t == 'delivery';
  }

  double get distanceKm => distanceMeters / 1000.0;

  /// Who the driver should be able to reach right now: on a parcel job the
  /// sender until pickup and the receiver after; otherwise the passenger.
  String get contactName {
    if (isParcel) {
      final n = stage.isOnBoard ? receiverName : senderName;
      if (n.trim().isNotEmpty) return n;
    }
    return passenger.name;
  }

  String get contactPhone {
    if (isParcel) {
      final p = stage.isOnBoard ? receiverPhone : senderPhone;
      if (p.trim().isNotEmpty) return p;
    }
    return passenger.phone;
  }

  TaxiRide copyWith({
    RideStage? stage,
    String? otp,
    DateTime? arrivedAt,
    List<RideChatMessage>? messages,
  }) =>
      TaxiRide(
        id: id,
        stage: stage ?? this.stage,
        passenger: passenger,
        pickupAddress: pickupAddress,
        dropAddress: dropAddress,
        pickup: pickup,
        drop: drop,
        fare: fare,
        distanceMeters: distanceMeters,
        durationMinutes: durationMinutes,
        paymentMethod: paymentMethod,
        otp: otp ?? this.otp,
        vehicleTypeName: vehicleTypeName,
        serviceType: serviceType,
        expiresInSeconds: expiresInSeconds,
        isDriveU: isDriveU,
        driveUVehicleName: driveUVehicleName,
        driveUTransmission: driveUTransmission,
        bonus: bonus,
        parcelPickupPhotos: parcelPickupPhotos,
        parcelDeliveryPhotos: parcelDeliveryPhotos,
        senderName: senderName,
        senderPhone: senderPhone,
        receiverName: receiverName,
        receiverPhone: receiverPhone,
        parcelCategory: parcelCategory,
        parcelWeight: parcelWeight,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        startedAt: startedAt,
        waitingChargeAmount: waitingChargeAmount,
        waitingChargePerMinute: waitingChargePerMinute,
        freeWaitingMinutes: freeWaitingMinutes,
        driverCancellationFee: driverCancellationFee,
        driverCancellationFeeIsPercent: driverCancellationFeeIsPercent,
        driverEarnings: driverEarnings,
        messages: messages ?? this.messages,
      );

  /// Reads a DriveU detail from whichever shape the payload uses: [offerKey]
  /// off the dispatch offer's flat `driveU` block, [rideKey] off the nested
  /// `safeRide.customerVehicle` on a ride document.
  static String _driveUField(
    Map ride,
    String offerKey,
    String rideKey,
  ) {
    final offer = ride['driveU'];
    if (offer is Map && offer[offerKey] != null) {
      return offer[offerKey].toString();
    }
    final safeRide = ride['safeRide'];
    if (safeRide is Map && safeRide['customerVehicle'] is Map) {
      return (safeRide['customerVehicle'][rideKey] ?? '').toString();
    }
    return '';
  }

  /// GeoJSON is `[lng, lat]` — reversing these silently puts every pickup in
  /// the wrong hemisphere, so it is done in exactly one place.
  static LatLng? _point(dynamic value) {
    if (value is Map) {
      final coords = value['coordinates'];
      if (coords is List && coords.length >= 2) {
        final lng = (coords[0] as num?)?.toDouble();
        final lat = (coords[1] as num?)?.toDouble();
        if (lat != null && lng != null) return LatLng(lat, lng);
      }
      final lat = (value['lat'] ?? value['latitude']) as num?;
      final lng = (value['lng'] ?? value['longitude']) as num?;
      if (lat != null && lng != null) {
        return LatLng(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  static List<String> _urls(dynamic parcel, String key) {
    if (parcel is! Map) return const [];
    final list = parcel[key];
    if (list is! List) return const [];
    return list
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.startsWith('http'))
        .toList(growable: false);
  }

  static String _str(dynamic map, String key) =>
      map is Map ? (map[key] ?? '').toString().trim() : '';

  static double _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  static int _int(dynamic v) => _num(v).toInt();

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString())?.toLocal();
  }

  /// The passenger block: `user` on offers and ride documents, a populated
  /// `userId` on some reads. `userId` is a bare id string on an offer, which
  /// must not be cast to a map.
  static Map? _userOf(Map ride) {
    final user = ride['user'];
    if (user is Map) return user;
    final userId = ride['userId'];
    if (userId is Map) return userId;
    return null;
  }

  /// Parses both the `rideRequest` socket payload and a REST ride document.
  factory TaxiRide.fromJson(Map<String, dynamic> json) {
    final Map ride = json['ride'] is Map ? json['ride'] as Map : json;
    final parcel = ride['parcel'];
    final pricing = ride['pricingSnapshot'];
    final messages = ride['messages'];

    return TaxiRide(
      id: (ride['rideId'] ?? ride['_id'] ?? ride['id'] ?? '').toString(),
      // An offer carries no status; it is by definition still searching.
      stage: RideStage.parse(
        (ride['liveStatus'] ?? ride['status'])?.toString(),
      ),
      passenger: RidePassenger.fromJson(_userOf(ride)),
      // Two shapes carry this: the dispatch offer sends a flat `driveU` block,
      // while a ride fetched from the API nests it under `safeRide`. Both are
      // read so an offer and a restored active ride agree.
      isDriveU: ride['isSafeRide'] == true ||
          (ride['driveU'] is Map && ride['driveU']['enabled'] == true) ||
          (ride['safeRide'] is Map && ride['safeRide']['isSafeRide'] == true),
      driveUVehicleName: _driveUField(ride, 'vehicleName', 'name'),
      driveUTransmission: _driveUField(ride, 'transmission', 'transmission'),
      pickupAddress: (ride['pickupAddress'] ?? '').toString(),
      dropAddress: (ride['dropAddress'] ?? '').toString(),
      pickup: _point(ride['pickupLocation']),
      drop: _point(ride['dropLocation']),
      fare: _num(ride['fare'] ?? ride['baseFare']),
      bonus: _num(ride['incentive'] ?? ride['bonus'] ?? ride['tip']),
      distanceMeters: _int(ride['estimatedDistanceMeters']),
      durationMinutes: _int(ride['estimatedDurationMinutes']),
      paymentMethod: (ride['paymentMethod'] ?? 'cash').toString(),
      otp: ride['otp']?.toString(),
      vehicleTypeName: (ride['vehicleTypeName'] ?? ride['vehicleIconType'] ?? '')
          .toString(),
      serviceType: (ride['serviceType'] ?? ride['type'] ?? 'ride').toString(),
      expiresInSeconds: (ride['expiresInSeconds'] as num?)?.toInt(),
      parcelPickupPhotos: _urls(parcel, 'pickupPhotos'),
      parcelDeliveryPhotos: _urls(parcel, 'deliveryPhotos'),
      senderName: _str(parcel, 'senderName'),
      senderPhone: _str(parcel, 'senderMobile'),
      receiverName: _str(parcel, 'receiverName'),
      receiverPhone: _str(parcel, 'receiverMobile'),
      parcelCategory: _str(parcel, 'category'),
      parcelWeight: _str(parcel, 'weight'),
      arrivedAt: _date(ride['arrivedAt']),
      startedAt: _date(ride['startedAt']),
      waitingChargeAmount: _num(ride['waitingChargeAmount']),
      waitingChargePerMinute:
          pricing is Map ? _num(pricing['waiting_charge']) : 0,
      freeWaitingMinutes:
          pricing is Map ? _num(pricing['free_waiting_before']) : 0,
      driverCancellationFee:
          pricing is Map ? _num(pricing['driver_cancellation_fee']) : 0,
      driverCancellationFeeIsPercent: pricing is Map &&
          (pricing['driver_cancellation_fee_type'] ?? 'percentage')
                  .toString()
                  .toLowerCase() ==
              'percentage',
      driverEarnings: ride['driverEarnings'] is num
          ? (ride['driverEarnings'] as num).toDouble()
          : null,
      messages: messages is List
          ? messages
              .whereType<Map>()
              .map(RideChatMessage.fromJson)
              .where((m) => m.message.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  /// True when [json] is a full ride document (as opposed to a status-only
  /// acknowledgement such as `rideAccepted` or `ride:status:updated`).
  static bool isFullDocument(Map json) =>
      json['pickupLocation'] is Map || json['pickupAddress'] != null;
}
