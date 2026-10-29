import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/network/network_providers.dart';
import 'package:superapp_user/core/realtime/sp_socket_service.dart';
import 'package:superapp_user/modules/services/api/services_datasource.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/data/models/sp_profile.dart';

/// DI for the services module.
///
/// Everything here is created lazily, so nothing in this file runs for a user
/// who never opens the Services tab — which matters, because one of these
/// opens a second Socket.IO connection.

final servicesDataSourceProvider = Provider<ServicesDataSource>((ref) {
  return ServicesDataSource(ref.watch(apiClientProvider));
});

/// The customer's SP profile, and the module's auth probe.
///
/// Kept alive rather than auto-disposed: the SP user id it carries is what the
/// socket connection and every tracking room key off, and re-fetching it on
/// each screen entry would churn the socket.
final spProfileProvider = FutureProvider<SpProfile>((ref) async {
  return ref.watch(servicesDataSourceProvider).profile();
});

/// The `/sp` namespace connection.
///
/// Deliberately **not** opened at app boot. It connects the first time
/// something watches [spRealtimeProvider], which happens on entry to the
/// module, and it is torn down with the provider scope on exit.
final spSocketServiceProvider = Provider<SpSocketService>((ref) {
  final service = SpSocketService();
  ref.onDispose(service.dispose);
  return service;
});

/// Connects the socket once the profile (and therefore the SP user id) is known.
///
/// Watch this from any screen that needs realtime; it is a no-op after the
/// first watcher. Returns null while the profile is still loading or if the
/// customer is not signed in — callers must keep polling regardless, since the
/// socket is an accelerator and never the contract.
final spRealtimeProvider = Provider<SpSocketService?>((ref) {
  final profile = ref.watch(spProfileProvider).value;
  if (profile == null || profile.id.isEmpty) return null;

  final socket = ref.watch(spSocketServiceProvider);

  // The token is read asynchronously, so connection happens just after this
  // returns. Callers get the service immediately and simply see no events until
  // the handshake completes — which is the same as any pre-connection window.
  ref.watch(tokenStorageProvider).accessToken.then((token) {
    if (token == null || token.isEmpty) return;
    socket.connect(accessToken: token, spUserId: profile.id);
  });

  return socket;
});

/// Serviceable cities. Drives the city filter on the catalogue calls.
final spCitiesProvider = FutureProvider<List<SpCity>>((ref) {
  return ref.watch(servicesDataSourceProvider).cities();
});

/// The city the catalogue is scoped to, or null for "everything".
///
/// Left null by default: the backend treats a missing `cityId` as unfiltered,
/// which is the right first-run behaviour — showing an empty catalogue because
/// we guessed the wrong city is worse than showing slightly too much.
final spSelectedCityProvider = NotifierProvider<SpSelectedCity, String?>(
  SpSelectedCity.new,
);

class SpSelectedCity extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? cityId) => state = cityId;
}

/// Home screen content, scoped to the selected city.
final spHomeDataProvider = FutureProvider<SpHomeData>((ref) {
  final cityId = ref.watch(spSelectedCityProvider);
  return ref.watch(servicesDataSourceProvider).homeData(cityId: cityId);
});

/// Brands inside one category.
final spBrandsProvider =
    FutureProvider.family<List<SpBrand>, String>((ref, categoryId) {
  final cityId = ref.watch(spSelectedCityProvider);
  return ref
      .watch(servicesDataSourceProvider)
      .brands(categoryId: categoryId, cityId: cityId);
});

/// Bookable services, keyed by brand **or** category.
///
/// `autoDispose` because the customer browses several of these per session and
/// each holds a list that goes stale as soon as they leave.
final spServicesProvider = FutureProvider.autoDispose
    .family<List<SpService>, SpServiceQuery>((ref, query) {
  return ref.watch(servicesDataSourceProvider).services(
        brandId: query.brandId,
        categoryId: query.categoryId,
        search: query.search,
      );
});

/// Key for [spServicesProvider]. Value equality matters — a `family` with an
/// identity-compared key would refetch on every rebuild.
class SpServiceQuery {
  const SpServiceQuery({this.brandId, this.categoryId, this.search});

  final String? brandId;
  final String? categoryId;
  final String? search;

  @override
  bool operator ==(Object other) =>
      other is SpServiceQuery &&
      other.brandId == brandId &&
      other.categoryId == categoryId &&
      other.search == search;

  @override
  int get hashCode => Object.hash(brandId, categoryId, search);
}

/// A single booking, refetched on demand.
///
/// The tracking screen watches this and invalidates it whenever a socket event
/// lands, rather than patching state from the event payload — the REST document
/// is the contract, the socket only says "something changed, look again".
final spBookingProvider =
    FutureProvider.autoDispose.family<SpBooking, String>((ref, bookingId) {
  return ref.watch(servicesDataSourceProvider).booking(bookingId);
});
