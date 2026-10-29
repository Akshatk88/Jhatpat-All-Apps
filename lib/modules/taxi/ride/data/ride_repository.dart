import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';
import 'package:superapp_user/core/network/taxi_api_client.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';

class RideRepository {
  final TaxiApiClient api;

  RideRepository(this.api);

  Future<RideModel> createRide({
    required List<double> pickup,
    required List<double> drop,
    required String pickupAddress,
    required String dropAddress,
    List<Map<String, dynamic>> stops = const [],
    required double fare,
    required double estimatedDistanceMeters,
    required double estimatedDurationMinutes,
    required String vehicleTypeId,
    String? vehicleIconType,
    String paymentMethod = 'cash',
    String serviceType = 'ride',
    String? promoCode,
    String? zoneId,
    String? serviceLocationId,
    DateTime? scheduledAt,
  }) async {
    final data = await api.post(ApiConstants.rides, data: {
      'pickup': pickup,
      'drop': drop,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      if (stops.isNotEmpty) 'stops': stops,
      'fare': fare,
      'estimatedDistanceMeters': estimatedDistanceMeters,
      'estimatedDurationMinutes': estimatedDurationMinutes,
      'vehicleTypeId': vehicleTypeId,
      // The booked type's icon family (bike/auto/car). Stored on the ride and
      // used for the driver marker; without it the marker fell back to the
      // driver record's icon, which is often 'car' even for a bike.
      if (vehicleIconType != null && vehicleIconType.isNotEmpty)
        'vehicleIconType': vehicleIconType,
      'paymentMethod': paymentMethod,
      'serviceType': serviceType,
      if (promoCode != null && promoCode.isNotEmpty) 'promo_code': promoCode,
      if (zoneId != null) 'zone_id': zoneId,
      if (serviceLocationId != null) 'service_location_id': serviceLocationId,
      'transport_type': 'taxi',
      if (scheduledAt != null) 'scheduledAt': scheduledAt.toIso8601String(),
    });
    return RideModel.fromJson(Map<String, dynamic>.from(data['ride'] ?? {}));
  }

  Future<RideModel?> getMyActiveRide() async {
    final data = await api.get(ApiConstants.activeRide);
    if (data == null) return null;
    return RideModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<RideModel> getRideById(String rideId) async {
    final data = await api.get('${ApiConstants.rides}/$rideId');
    return RideModel.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> listMyRides({int page = 1, int limit = 20, String? category}) async {
    final data = await api.get(ApiConstants.rides, query: {
      'page': page,
      'limit': limit,
      if (category != null) 'category': category,
    });
    if (data is List) {
      return {'results': data};
    }
    if (data is Map) {
      final mapData = Map<String, dynamic>.from(data);
      if (!mapData.containsKey('results')) {
        final list = mapData['rides'] ?? mapData['data'] ?? mapData['docs'] ?? mapData['items'];
        if (list is List) {
          mapData['results'] = list;
        } else if (mapData['data'] is Map) {
          final inner = Map<String, dynamic>.from(mapData['data']);
          final innerList = inner['results'] ?? inner['rides'] ?? inner['docs'] ?? inner['items'];
          if (innerList is List) {
            mapData['results'] = innerList;
          }
        }
      }
      return mapData;
    }
    return {'results': []};
  }

  Future<void> cancelRide(String rideId, {String? reason}) {
    return api.patch('${ApiConstants.rides}/$rideId/cancel', data: {
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> submitReview(String rideId, {required int rating, String? comment, double tipAmount = 0}) {
    return api.patch('${ApiConstants.rides}/$rideId/feedback', data: {
      'rating': rating,
      if (comment != null) 'comment': comment,
      'tipAmount': tipAmount,
    });
  }

  Future<List<Map<String, dynamic>>> getAvailableDrivers({
    required double lat,
    required double lng,
    required String vehicleTypeId,
    String? vehicleIconType,
  }) async {
    // vehicleTypeId is mandatory server-side; without it every poll was a 400
    // and the home map never showed a single nearby vehicle.
    final data = await api.get(ApiConstants.availableDrivers, query: {
      'lat': lat,
      'lng': lng,
      'vehicleTypeId': vehicleTypeId,
      // The booked type's icon family (bike/auto/car). Stored on the ride and
      // used for the driver marker; without it the marker fell back to the
      // driver record's icon, which is often 'car' even for a bike.
      if (vehicleIconType != null && vehicleIconType.isNotEmpty)
        'vehicleIconType': vehicleIconType,
    });
    // The endpoint returns `{ totalDrivers, drivers: [...] }` — reading
    // `results` here silently yielded an empty list.
    final results = (data is Map ? (data['drivers'] ?? data['results']) : data) as List? ?? [];
    return results.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> createTipOrder(String rideId, double amount) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/tip/razorpay/order', data: {'amount': amount});
    return Map<String, dynamic>.from(data);
  }

  Future<void> verifyTipPayment(String rideId, Map<String, dynamic> payload) {
    return api.post('${ApiConstants.rides}/$rideId/tip/razorpay/verify', data: payload);
  }

  Future<Map<String, dynamic>> createCompletionOrder(String rideId) async {
    final data = await api.post('${ApiConstants.rides}/$rideId/complete-payment/razorpay/order');
    return Map<String, dynamic>.from(data);
  }

  Future<void> verifyCompletionPayment(String rideId, Map<String, dynamic> payload) {
    return api.post('${ApiConstants.rides}/$rideId/complete-payment/razorpay/verify', data: payload);
  }

  Future<void> payCompletionWithWallet(String rideId) {
    return api.post('${ApiConstants.rides}/$rideId/complete-payment/wallet');
  }
}
