/// Every path the services module talks to, relative to `ApiConfig.baseUrl`
/// (`https://k9.appzeto.com/api/v1`).
///
/// The Service-Provider module is mounted on master at `/v1/sp` — see
/// `Backend/src/routes/index.js` and `modules/serviceProvider/routes/index.js`.
/// The legacy un-prefixed aliases (`/users/...`, `/bookings/...`) also answer,
/// but they exist only so already-shipped SP builds keep working. New clients
/// use the canonical prefix; the aliases are registered last and can be
/// retired without touching us.
///
/// Endpoint constants live in the module, not in `core/config` — which URL
/// serves service bookings is module knowledge. `core/config` only knows hosts.
class ServicesEndpoints {
  const ServicesEndpoints._();

  static const String _sp = '/sp';

  // ── Public catalogue (no auth) ──────────────────────────────────────
  static const String cities = '$_sp/public/cities';
  static const String config = '$_sp/public/config';
  static const String categories = '$_sp/public/categories';
  static const String brands = '$_sp/public/brands';
  static const String services = '$_sp/public/services';
  static const String homeData = '$_sp/public/home-data';
  static const String homeContent = '$_sp/public/home-content';
  static const String plans = '$_sp/public/plans';

  static String brandBySlug(String slug) => '$_sp/public/brands/slug/$slug';

  // ── Customer profile ────────────────────────────────────────────────
  //
  // These resolve through the identity bridge in SP's authMiddleware: the app
  // sends its ONE master-issued token and the backend maps it to the matching
  // `sp_users` document (provisioning on first contact). No second login.
  static const String profile = '$_sp/users/profile';
  static const String checkoutData = '$_sp/users/checkout-data';

  // ── Cart ────────────────────────────────────────────────────────────
  static const String cart = '$_sp/users/cart';
  static String cartItem(String itemId) => '$cart/$itemId';
  static String cartCategory(String category) => '$cart/category/$category';

  // ── Bookings ────────────────────────────────────────────────────────
  static const String bookings = '$_sp/users/bookings';
  static const String ratings = '$_sp/users/bookings/ratings';

  static String bookingById(String id) => '$bookings/$id';
  static String cancelBooking(String id) => '$bookings/$id/cancel';
  static String rescheduleBooking(String id) => '$bookings/$id/reschedule';
  static String reviewBooking(String id) => '$bookings/$id/review';

  // ── Payments ────────────────────────────────────────────────────────
  static const String paymentCreateOrder = '$_sp/payments/create-order';
  static const String paymentVerify = '$_sp/payments/verify';
  static const String paymentWallet = '$_sp/payments/wallet';
  static const String paymentPayAtHome = '$_sp/payments/pay-at-home';
  static const String paymentHistory = '$_sp/payments/history';

  // ── Cash / online collection at the door ────────────────────────────
  //
  // Driven by the vendor or worker on their side; the customer app reads the
  // status and confirms.
  static String collectionStatus(String bookingId) => '$_sp/bookings/cash/$bookingId/status';
  static String collectionCustomerConfirm(String bookingId) =>
      '$_sp/bookings/cash/$bookingId/customer-confirm';

  // ── Wallet (SP's own ledger, separate from food's) ──────────────────
  static const String walletBalance = '$_sp/user/wallet/balance';
  static const String walletTransactions = '$_sp/user/wallet/transactions';
  static const String walletAddMoney = '$_sp/user/wallet/add-money';
  static const String walletVerifyTopup = '$_sp/user/wallet/verify-topup';

  // ── Notifications ───────────────────────────────────────────────────
  static const String notifications = '$_sp/notifications/user';
  static String notificationRead(String id) => '$_sp/notifications/$id/read';

  // ── Scrap pickup ────────────────────────────────────────────────────
  static const String scrap = '$_sp/scrap';
  static const String myScrap = '$_sp/scrap/my';

  // ── FCM ─────────────────────────────────────────────────────────────
  //
  // SP keeps its own `fcmTokens` / `fcmTokenMobile` arrays on `sp_users` and
  // pushes only to those. Registering with the shared `/api/v1/fcm-tokens`
  // route does NOT register here, so without these a customer is never
  // notified about a service booking.
  static const String fcmSave = '$_sp/users/fcm-tokens/save';
  static const String fcmRemove = '$_sp/users/fcm-tokens/remove';

  /// Clears every token for this platform. Used on logout, because the token
  /// may have rotated since it was registered and removing only the one we
  /// still remember would leave the device targeted.
  static const String fcmRemoveAll = '$_sp/users/fcm-tokens/remove-all';
}
