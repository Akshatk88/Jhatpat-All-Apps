import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/promo/data/models/promo_model.dart';
import 'package:superapp_user/modules/taxi/promo/data/promo_repository.dart';

final promoRepositoryProvider = Provider<PromoRepository>((ref) {
  return PromoRepository(ref.watch(taxiApiClientProvider));
});

/// `GET /taxi/promos/available` 400s without `service_location_id`, so the
/// rider's service location is taken from the tariff rows (each carries one).
/// No known location means no promos rather than an error screen.
final availablePromosProvider = FutureProvider<List<PromoModel>>((ref) async {
  final repo = ref.watch(homeRepositoryProvider);
  final prices = await repo.cachedSetPrices() ?? await repo.getSetPrices();
  final serviceLocationId = prices
      .map((p) => p.serviceLocationId)
      .firstWhere((id) => id != null && id.isNotEmpty, orElse: () => null);
  if (serviceLocationId == null) return const [];
  return ref.watch(promoRepositoryProvider).getAvailablePromos(serviceLocationId: serviceLocationId);
});
