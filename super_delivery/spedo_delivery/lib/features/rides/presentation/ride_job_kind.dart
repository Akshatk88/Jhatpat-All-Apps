import 'package:flutter/material.dart';

import '../data/models/taxi_ride.dart';

/// What a ride-dispatcher job is, as the driver should read it: "Parcel" with
/// a box for parcel jobs, the vehicle name (or "Ride") for passengers. Shared
/// by the offer card and the active-trip screen so both say the same thing.
class RideJobKind {
  RideJobKind._();

  static String labelOf(TaxiRide ride) {
    if (ride.isParcel) return 'Parcel';
    final vehicle = ride.vehicleTypeName.trim();
    return vehicle.isEmpty ? 'Ride' : _titleCase(vehicle);
  }

  static IconData iconOf(TaxiRide ride) {
    if (ride.isParcel) return Icons.inventory_2_rounded;
    final n = ride.vehicleTypeName.toLowerCase();
    if (n.contains('bike') || n.contains('moto') || n.contains('scooty')) {
      return Icons.two_wheeler_rounded;
    }
    if (n.contains('auto')) return Icons.electric_rickshaw_rounded;
    return Icons.directions_car_rounded;
  }

  static String _titleCase(String s) => s
      .split(RegExp(r'[\s_]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}
