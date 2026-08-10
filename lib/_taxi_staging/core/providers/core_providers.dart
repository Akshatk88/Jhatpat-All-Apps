import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/_taxi_staging/core/network/api_client.dart';
import 'package:superapp_user/_taxi_staging/core/services/location_service.dart';
import 'package:superapp_user/_taxi_staging/core/services/razorpay_service.dart';
import 'package:superapp_user/_taxi_staging/core/services/socket_service.dart';
import 'package:superapp_user/_taxi_staging/core/storage/local_storage_service.dart';
import 'package:superapp_user/modules/food/application/providers/network_providers.dart';

/// Hive-backed local storage for the ride-side features: recent searches,
/// saved places, emergency contacts, favourite drivers, settings.
///
/// Overridden in `main.dart` with an instance opened during bootstrap, because
/// several call sites read boxes synchronously.
///
/// Follow-up: only `settings` is genuinely needed before first frame. The other
/// four should open lazily on first module entry (see the tiered bootstrap in
/// docs/superapp Ch. 16) — that requires making those call sites async first.
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('localStorageServiceProvider must be overridden');
});

/// The taxi-shaped facade over the app's single HTTP client.
///
/// Deliberately *not* its own Dio: sharing the one client means the ride side
/// inherits bearer injection, single-flight 401 refresh, envelope unwrapping
/// and the response cache, and a session expiring in one module expires it
/// everywhere — which is the whole point of one account across the super app.
final taxiApiClientProvider = Provider<TaxiApiClient>((ref) {
  return TaxiApiClient(ref.watch(apiClientProvider));
});

final taxiSocketServiceProvider = Provider<TaxiSocketService>((ref) {
  final service = TaxiSocketService();
  ref.onDispose(service.disconnect);
  return service;
});

final taxiLocationServiceProvider = Provider<TaxiLocationService>((ref) {
  return TaxiLocationService();
});

/// Ride-side Razorpay checkout.
///
/// Follow-up: food has its own 272-line `payment_gateway.dart`. Two live
/// Razorpay plugin instances in one binary is a real hazard — the plugin holds
/// native listeners — so these must converge on a single gateway with per-module
/// PaymentIntents before release.
final razorpayServiceProvider = Provider<RazorpayService>((ref) {
  final service = RazorpayService();
  ref.onDispose(service.dispose);
  return service;
});
