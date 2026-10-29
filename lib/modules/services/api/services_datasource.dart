import 'package:superapp_user/core/network/api_client.dart';
import 'package:superapp_user/modules/services/api/services_endpoints.dart';
import 'package:superapp_user/modules/services/data/models/sp_booking.dart';
import 'package:superapp_user/modules/services/data/models/sp_catalog_models.dart';
import 'package:superapp_user/modules/services/data/models/sp_profile.dart';

/// HTTP for the services module. Owns request/response shape only — cache
/// policy, pagination and merging belong to the repository above it.
///
/// **Envelope note.** The shared [ApiClient] unwraps `{success, message, data}`
/// and returns `data` directly. SP's *public* controllers do not use that
/// envelope: they return `{success: true, categories: [...]}`,
/// `{success: true, brands: [...]}` and so on. `_unwrap` passes those through
/// whole (there is no `data` key), so those calls are typed as
/// `Map<String, dynamic>` and read their own key. SP's *booking and payment*
/// controllers do use `data`, so those calls receive the inner value directly.
/// Getting this backwards is the easiest way to end up with a null-check crash,
/// hence the per-method comments.
class ServicesDataSource {
  const ServicesDataSource(this._api);

  final ApiClient _api;

  // ─────────────────────────────────────────────────────── catalogue

  /// Categories + promotional content in one round trip.
  ///
  /// Cached: the home screen is the module's entry point and this makes the
  /// second visit paint instantly. Safe to cache — it is admin-authored content
  /// with no per-user or monetary component.
  Future<SpHomeData> homeData({String? cityId, void Function(SpHomeData)? onCache}) async {
    final json = await _api.get<Map<String, dynamic>>(
      ServicesEndpoints.homeData,
      query: {'cityId': cityId},
      auth: false,
      cacheTtl: const Duration(minutes: 10),
      onCache: onCache == null ? null : (cached) => onCache(SpHomeData.fromJson(cached)),
    );
    return SpHomeData.fromJson(json);
  }

  Future<List<SpCity>> cities() async {
    final json = await _api.get<Map<String, dynamic>>(
      ServicesEndpoints.cities,
      auth: false,
      cacheTtl: const Duration(hours: 6),
    );
    // This one is inconsistent even among the public routes — `getActiveCities`
    // returns `data`, unlike its siblings, so accept either key.
    final list = (json['cities'] ?? json['data']) as List? ?? const [];
    return [
      for (final c in list) SpCity.fromJson((c as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<SpCategory>> categories({String? cityId}) async {
    final json = await _api.get<Map<String, dynamic>>(
      ServicesEndpoints.categories,
      query: {'cityId': cityId},
      auth: false,
      cacheTtl: const Duration(minutes: 30),
    );
    return [
      for (final c in (json['categories'] as List? ?? const []))
        SpCategory.fromJson((c as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<SpBrand>> brands({
    String? categoryId,
    String? categorySlug,
    String? cityId,
    String? search,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      ServicesEndpoints.brands,
      query: {
        'categoryId': categoryId,
        'categorySlug': categorySlug,
        'cityId': cityId,
        'search': search,
      },
      auth: false,
      cacheTtl: search == null ? const Duration(minutes: 15) : null,
    );
    return [
      for (final b in (json['brands'] as List? ?? const []))
        SpBrand.fromJson((b as Map).cast<String, dynamic>()),
    ];
  }

  Future<List<SpService>> services({
    String? brandId,
    String? brandSlug,
    String? categoryId,
    String? search,
  }) async {
    final json = await _api.get<Map<String, dynamic>>(
      ServicesEndpoints.services,
      query: {
        'brandId': brandId,
        'brandSlug': brandSlug,
        'categoryId': categoryId,
        'search': search,
      },
      auth: false,
      cacheTtl: search == null ? const Duration(minutes: 15) : null,
    );
    return [
      for (final s in (json['services'] as List? ?? const []))
        SpService.fromJson((s as Map).cast<String, dynamic>()),
    ];
  }

  // ───────────────────────────────────────────────────────── profile

  /// The customer's SP profile.
  ///
  /// Also the module's **auth probe**: it is the first authenticated SP call
  /// the app makes, so it is what exercises the identity bridge and provisions
  /// the `sp_users` record on first use. Everything else in the module assumes
  /// this has succeeded, because everything else needs the SP user id.
  ///
  /// Returns `{success, user: {...}}` — no `data` key, so read `user`.
  Future<SpProfile> profile() async {
    final json = await _api.get<Map<String, dynamic>>(ServicesEndpoints.profile);
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? json;
    return SpProfile.fromJson(user);
  }

  Future<void> updateProfile({String? name, String? email}) => _api.put<dynamic>(
        ServicesEndpoints.profile,
        body: {
          if (name != null && name.isNotEmpty) 'name': name,
          if (email != null && email.isNotEmpty) 'email': email,
        },
      );

  // ──────────────────────────────────────────────────────── bookings

  /// One page of the customer's bookings, newest first.
  ///
  /// The endpoint returns `{data: [...], pagination: {...}}` and [ApiClient]
  /// hands back only `data`, so the pagination block is not reachable from
  /// here. The repository infers "last page" from a short page instead, which
  /// is correct for a stable descending sort.
  Future<List<SpBooking>> bookings({int page = 1, int limit = 20, String? status}) async {
    final list = await _api.get<List<dynamic>>(
      ServicesEndpoints.bookings,
      query: {'page': page, 'limit': limit, 'status': status},
    );
    return [
      for (final b in list) SpBooking.fromJson((b as Map).cast<String, dynamic>()),
    ];
  }

  /// NOT cached, ever. Status, OTPs and the bill are mutable and money-adjacent.
  Future<SpBooking> booking(String id) async {
    final json = await _api.get<Map<String, dynamic>>(ServicesEndpoints.bookingById(id));
    return SpBooking.fromJson(json);
  }

  /// Creates the booking and returns it in the `searching` state.
  ///
  /// The server responds 201 immediately and then runs vendor discovery in a
  /// `setImmediate` block, so the booking that comes back has no vendor yet —
  /// the customer waits on the searching screen and hears about it over the
  /// socket (`booking_accepted`) or the `booking_search_failed` fallback.
  Future<SpBooking> createBooking(Map<String, dynamic> body) async {
    final json = await _api.post<Map<String, dynamic>>(
      ServicesEndpoints.bookings,
      body: body,
    );
    return SpBooking.fromJson(json);
  }

  Future<void> cancelBooking(String id, {String? reason}) => _api.post<dynamic>(
        ServicesEndpoints.cancelBooking(id),
        body: {if (reason != null && reason.isNotEmpty) 'cancellationReason': reason},
      );

  Future<void> rescheduleBooking(
    String id, {
    required DateTime date,
    required String time,
    required String slotStart,
    required String slotEnd,
  }) =>
      _api.put<dynamic>(
        ServicesEndpoints.rescheduleBooking(id),
        body: {
          'scheduledDate': date.toUtc().toIso8601String(),
          'scheduledTime': time,
          'timeSlot': {'start': slotStart, 'end': slotEnd},
        },
      );

  Future<void> review(
    String id, {
    required int rating,
    String? review,
    List<String> images = const [],
  }) =>
      _api.post<dynamic>(
        ServicesEndpoints.reviewBooking(id),
        body: {
          'rating': rating,
          if (review != null && review.isNotEmpty) 'review': review,
          if (images.isNotEmpty) 'reviewImages': images,
        },
      );

  // ──────────────────────────────────────────────────────── payments

  /// Opens a Razorpay order for a booking. Returns `{orderId, amount, currency,
  /// key, bookingId}` — `amount` already converted back to rupees by the server.
  Future<Map<String, dynamic>> createPaymentOrder(String bookingId) =>
      _api.post<Map<String, dynamic>>(
        ServicesEndpoints.paymentCreateOrder,
        body: {'bookingId': bookingId},
      );

  /// Server-side signature verification.
  ///
  /// Always round-trip through this before treating money as received — the
  /// gateway callback alone is client-side and forgeable. The endpoint claims
  /// the booking atomically, so a replayed callback is a no-op rather than a
  /// double credit.
  Future<void> verifyPayment({
    required String orderId,
    required String paymentId,
    required String signature,
  }) =>
      _api.post<dynamic>(
        ServicesEndpoints.paymentVerify,
        body: {
          'razorpay_order_id': orderId,
          'razorpay_payment_id': paymentId,
          'razorpay_signature': signature,
        },
      );

  Future<void> payFromWallet(String bookingId) => _api.post<dynamic>(
        ServicesEndpoints.paymentWallet,
        body: {'bookingId': bookingId},
      );

  Future<void> payAtHome(String bookingId) => _api.post<dynamic>(
        ServicesEndpoints.paymentPayAtHome,
        body: {'bookingId': bookingId},
      );

  // ────────────────────────────────────────────── doorstep collection

  /// What the professional has requested at the door, if anything.
  Future<Map<String, dynamic>> collectionStatus(String bookingId) =>
      _api.get<Map<String, dynamic>>(ServicesEndpoints.collectionStatus(bookingId));

  /// Customer's half of the doorstep handshake.
  Future<void> confirmCollection(String bookingId) => _api.post<dynamic>(
        ServicesEndpoints.collectionCustomerConfirm(bookingId),
        body: const {},
      );

  // ────────────────────────────────────────────────────────── wallet

  /// SP keeps its **own** ledger (`sp_users.wallet`), separate from food's.
  /// It is read and displayed as a services-only balance and never summed with
  /// the food balance — money in one cannot be spent from the other, and
  /// showing a combined figure would be a financial bug.
  Future<int> walletBalancePaise() async {
    final json = await _api.get<Map<String, dynamic>>(ServicesEndpoints.walletBalance);
    final data = (json['data'] as Map?)?.cast<String, dynamic>() ?? json;
    return paiseOf(data['balance'] ?? data['walletBalance']);
  }

  // ────────────────────────────────────────────────────────────── fcm

  /// Registers this device for Service-Provider pushes.
  ///
  /// `platform` decides which array the token lands in server-side:
  /// `android`/`ios`/`mobile` go to `fcmTokenMobile`, anything else to
  /// `fcmTokens` (see `isMobilePlatform` in SP's fcmToken.routes.js). Sending
  /// the wrong one still stores the token, but in the web bucket, and SP's
  /// mobile pushes would skip it.
  Future<void> saveFcmToken(String token, {required String platform}) =>
      _api.post<dynamic>(
        ServicesEndpoints.fcmSave,
        body: {'fcmToken': token, 'platform': platform},
      );

  /// Drops every token for this platform. Used on logout.
  Future<void> removeAllFcmTokens({required String platform}) =>
      _api.delete<dynamic>(
        ServicesEndpoints.fcmRemoveAll,
        body: {'platform': platform},
      );

  // ─────────────────────────────────────────────────────────── cart

  Future<Map<String, dynamic>> cart() =>
      _api.get<Map<String, dynamic>>(ServicesEndpoints.cart);

  Future<void> addToCart(Map<String, dynamic> item) =>
      _api.post<dynamic>(ServicesEndpoints.cart, body: item);

  Future<void> removeCartItem(String itemId) =>
      _api.delete<dynamic>(ServicesEndpoints.cartItem(itemId));

  Future<void> clearCart() => _api.delete<dynamic>(ServicesEndpoints.cart);
}
