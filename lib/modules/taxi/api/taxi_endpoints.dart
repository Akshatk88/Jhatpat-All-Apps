import 'package:superapp_user/modules/taxi/taxi_constants.dart';

/// Endpoint paths only — host/base URL live in [TaxiConstants] (single source
/// of truth for environment config).
class ApiConstants {
  ApiConstants._();

  static const String baseUrl = TaxiConstants.baseUrl;

  static const String socketUrl = TaxiConstants.socketUrl;

  // Auth
  static const String sendOtp = '/taxi/users/auth/send-otp';
  static const String verifyOtp = '/taxi/users/auth/verify-otp';
  static const String otpLogin = '/taxi/users/otp-login';
  static const String register = '/taxi/users/register';
  static const String signup = '/taxi/users/signup';
  static const String login = '/taxi/users/login';

  // Profile
  static const String me = '/taxi/users/me';
  static const String profileImage = '/taxi/users/profile-image';
  static const String deleteRequest = '/taxi/users/me/delete-request';

  // Bootstrap / catalog
  static const String appModules = '/taxi/users/app-modules';
  static const String goodsTypes = '/taxi/users/goods-types';
  static const String vehicleTypes = '/taxi/users/vehicle-types';
  /// Admin-uploaded promo banners shown on the home screen.
  static const String banners = '/taxi/users/banners';
  static const String setPrices = '/taxi/users/set-prices';
  static const String serviceLocations = '/taxi/users/service-locations';
  static const String popularPlaces = '/taxi/users/popular-places';

  // Notifications
  static const String notifications = '/taxi/users/notifications';

  // Wallet
  static const String wallet = '/taxi/users/wallet';
  static const String walletTopup = '/taxi/users/wallet/topup';
  static const String walletTransfer = '/taxi/users/wallet/transfer';
  static const String walletTransferDriver = '/taxi/users/wallet/transfer/driver';
  static const String walletRazorpayOrder = '/taxi/users/wallet/razorpay/order';
  static const String walletRazorpayVerify = '/taxi/users/wallet/razorpay/verify';
  static const String walletPhonepeOrder = '/taxi/users/wallet/phonepe/order';
  static const String walletPhonepeStatus = '/taxi/users/wallet/phonepe/status'; // + '/$merchantTransactionId'

  // Promo
  static const String promoValidate = '/taxi/promos/validate';
  static const String promoAvailable = '/taxi/promos/available';

  // Rides
  static const String rides = '/taxi/rides';
  static const String activeRide = '/taxi/rides/active/me';
  static const String availableDrivers = '/taxi/rides/available-drivers';
  static const String rideTipSettings = '/taxi/rides/app-settings/tip';

  // Deliveries
  static const String deliveries = '/taxi/deliveries';

  // Sos
  static const String sos = '/taxi/users/sos';

  // Support
  static const String supportTitles = '/taxi/support/titles';
  static const String supportTickets = '/taxi/support/tickets';
  static const String myTickets = '/taxi/support/tickets/my';

  // Common
  static const String uploadImage = '/taxi/common/upload/image';
  static const String paymentGateway = '/taxi/common/payment-gateway';
  static const String referralsTranslation = '/taxi/common/referrals/translation';
  static const String referralsSettings = '/taxi/common/referrals/settings';
}
