class SetPriceModel {
  final String id;
  final String? vehicleTypeId;
  final String? zoneId;
  final String? serviceLocationId;
  final double basePrice;
  final double baseDistanceKm;
  final double pricePerDistance;
  final double timePrice;
  final double waitingCharge;
  final double serviceTaxPercent;

  /// `active` from the admin (1/0). The server never charges an inactive
  /// row, so the app must not quote from one either.
  final bool active;

  const SetPriceModel({
    required this.id,
    required this.vehicleTypeId,
    required this.zoneId,
    required this.serviceLocationId,
    required this.basePrice,
    required this.baseDistanceKm,
    required this.pricePerDistance,
    required this.timePrice,
    required this.waitingCharge,
    required this.serviceTaxPercent,
    this.active = true,
  });

  /// A row the server can actually charge: active, with a non-zero rate. An
  /// all-zero row makes the server refuse the booking ("not available").
  bool get isBookable =>
      active && (basePrice > 0 || pricePerDistance > 0 || timePrice > 0);

  factory SetPriceModel.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic value) => double.tryParse('${value ?? 0}') ?? 0;
    final rawActive = json['active'];
    return SetPriceModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      vehicleTypeId: json['type_id']?.toString() ?? json['vehicle_type']?.toString(),
      zoneId: json['zone_id']?.toString(),
      serviceLocationId: json['service_location_id']?.toString(),
      basePrice: asDouble(json['base_price']),
      baseDistanceKm: asDouble(json['base_distance']),
      pricePerDistance: asDouble(json['price_per_distance']),
      timePrice: asDouble(json['time_price']),
      waitingCharge: asDouble(json['waiting_charge']),
      serviceTaxPercent: asDouble(json['service_tax']),
      active: rawActive != false && '${rawActive ?? 1}' != '0',
    );
  }
}
