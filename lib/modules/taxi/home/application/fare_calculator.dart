import 'package:superapp_user/modules/taxi/home/data/models/set_price_model.dart';

class FareBreakdown {
  final double baseFare;
  final double distanceFare;
  final double timeFare;
  final double serviceTax;
  final double platformFee;
  final double surge;
  final double total;

  /// True when this came from the server quote (exact charge), false for the
  /// on-device estimate shown while the quote loads.
  final bool fromServer;

  const FareBreakdown({
    required this.baseFare,
    required this.distanceFare,
    required this.timeFare,
    required this.serviceTax,
    required this.total,
    this.platformFee = 0,
    this.surge = 0,
    this.fromServer = false,
  });

  static FareBreakdown? fromQuote(Map<String, dynamic> fare) {
    double d(dynamic v) => double.tryParse('${v ?? 0}') ?? 0;
    final total = d(fare['total']);
    if (total <= 0) return null;
    return FareBreakdown(
      baseFare: d(fare['baseFare']),
      distanceFare: d(fare['distanceFare']),
      timeFare: d(fare['timeFare']),
      serviceTax: d(fare['serviceTax']),
      platformFee: d(fare['platformFee']),
      surge: d(fare['surge']),
      total: total,
      fromServer: true,
    );
  }
}

class FareCalculator {
  /// Client-side fare estimate only — the backend recalculates and is
  /// authoritative at ride completion.
  static FareBreakdown estimate({
    required SetPriceModel pricing,
    required double distanceMeters,
    required double durationSeconds,
  }) {
    final distanceKm = distanceMeters / 1000;
    final durationMinutes = durationSeconds / 60;
    final chargeableKm = (distanceKm - pricing.baseDistanceKm).clamp(0, double.infinity);

    final baseFare = pricing.basePrice;
    final distanceFare = chargeableKm * pricing.pricePerDistance;
    // Same as the backend (rideFare.js): a trip inside the base distance
    // pays only the base fare — no distance or time charge.
    final withinBase = pricing.baseDistanceKm > 0 && distanceKm <= pricing.baseDistanceKm;
    final timeFare = withinBase ? 0.0 : durationMinutes * pricing.timePrice;
    final subtotal = baseFare + distanceFare + timeFare;
    final serviceTax = subtotal * (pricing.serviceTaxPercent / 100);
    final total = (subtotal + serviceTax).clamp(pricing.basePrice, double.infinity);

    return FareBreakdown(
      baseFare: baseFare,
      distanceFare: distanceFare,
      timeFare: timeFare,
      serviceTax: serviceTax,
      total: double.parse(total.toStringAsFixed(0)),
    );
  }
}
