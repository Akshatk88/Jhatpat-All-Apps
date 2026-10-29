import 'package:superapp_user/modules/taxi/api/taxi_endpoints.dart';
import 'package:superapp_user/core/network/taxi_api_client.dart';
import 'package:superapp_user/modules/taxi/promo/data/models/promo_model.dart';

class PromoRepository {
  final TaxiApiClient api;

  PromoRepository(this.api);

  /// `GET /taxi/promos/available?service_location_id=` -> a bare array.
  Future<List<PromoModel>> getAvailablePromos({required String serviceLocationId}) async {
    final data = await api.get(ApiConstants.promoAvailable, query: {
      'service_location_id': serviceLocationId,
      'transport_type': 'taxi',
    });
    final results = (data is Map ? (data['results'] ?? data['promos']) : data) as List? ?? const [];
    return results
        .whereType<Map>()
        .map((e) => PromoModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Map<String, dynamic>> validatePromo({required String code, required double fare}) async {
    final data = await api.post(ApiConstants.promoValidate, data: {'code': code, 'fare': fare});
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}
