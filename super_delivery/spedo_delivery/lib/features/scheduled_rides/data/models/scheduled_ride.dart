/// One row of `GET /taxi/drivers/scheduled-rides`
/// (`serializeDriverScheduledRide` on the server).
class ScheduledRide {
  const ScheduledRide({
    required this.id,
    required this.serviceType,
    required this.liveStatus,
    required this.fare,
    required this.paymentMethod,
    required this.pickupAddress,
    required this.dropAddress,
    required this.scheduledAt,
    required this.distanceMeters,
    required this.isAssignedToMe,
    required this.customerName,
    required this.customerPhone,
  });

  final String id;

  /// ride | parcel.
  final String serviceType;

  /// searching | accepted | arriving.
  final String liveStatus;
  final double fare;
  final String paymentMethod;
  final String pickupAddress;
  final String dropAddress;
  final DateTime? scheduledAt;
  final int distanceMeters;

  /// True for a booking this driver holds — the only kind the driver can
  /// cancel. Others are open requests in their zone.
  final bool isAssignedToMe;
  final String customerName;
  final String customerPhone;

  bool get isParcel => serviceType.toLowerCase() == 'parcel';
  String get kindLabel => isParcel ? 'Parcel' : 'Ride';

  String get statusLabel {
    if (!isAssignedToMe) return 'Open request';
    switch (liveStatus.toLowerCase()) {
      case 'arriving':
        return 'On the way';
      case 'accepted':
        return 'Confirmed';
      default:
        return 'Assigned';
    }
  }

  factory ScheduledRide.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return ScheduledRide(
      id: (json['rideId'] ?? json['_id'] ?? json['id'] ?? '').toString(),
      serviceType: (json['serviceType'] ?? json['type'] ?? 'ride').toString(),
      liveStatus: (json['liveStatus'] ?? json['status'] ?? '').toString(),
      fare: (json['fare'] as num?)?.toDouble() ??
          (json['baseFare'] as num?)?.toDouble() ??
          0,
      paymentMethod: (json['paymentMethod'] ?? 'cash').toString(),
      pickupAddress: (json['pickupAddress'] ?? '').toString(),
      dropAddress: (json['dropAddress'] ?? '').toString(),
      scheduledAt: DateTime.tryParse(json['scheduledAt']?.toString() ?? '')?.toLocal(),
      distanceMeters: (json['estimatedDistanceMeters'] as num?)?.toInt() ?? 0,
      isAssignedToMe: json['isAssignedToCurrentDriver'] == true,
      customerName: user is Map ? (user['name'] ?? '').toString() : '',
      customerPhone: user is Map ? (user['phone'] ?? '').toString() : '',
    );
  }
}
