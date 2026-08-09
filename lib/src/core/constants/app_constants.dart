import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class LocaleLanguageList {
  final String name;
  final String lang;
  final String? flag;

  const LocaleLanguageList({
    required this.name,
    required this.lang,
    this.flag,
  });
}

/// Central App Constants for Suvio User Application.
class AppConstants {
  const AppConstants._();

  static const String title = 'Suvio';
  static const String appName = 'Suvio';

  /// Merchant name shown on the Razorpay checkout sheet.
  ///
  /// Without this Razorpay falls back to the legal entity registered on the
  /// account ("SWITCHEATS PRIVATE LIMITED"), which is not our consumer brand.
  static const String brandName = 'Suvio';

  /// Public logo URL for the Razorpay sheet. Razorpay fetches this over the
  /// network, so a bundled asset cannot be used — it must be a hosted URL.
  /// Falls back to the backend's configured business logo when set.
  static const String brandLogoUrl = String.fromEnvironment('BRAND_LOGO_URL');
  static const String appVersion = '1.0.0';

  /// Backend REST API host domain.
  static const String hostUrl = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://suvio.appzeto.com',
  );

  /// Backend REST API base URL (all endpoints mounted under `/api/v1`).
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '$hostUrl/api/v1',
  );

  /// Socket.IO server URL.
  static const String socketUrl = String.fromEnvironment(
    'SOCKET_URL',
    defaultValue: hostUrl,
  );

  /// Firebase project configuration for User App (com.fooduser.app).
  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? "AIzaSyC_twLhO7C21HdRBvoZvedceka0jdLCUjc"
      : "ios firebase api key";

  static String get firbaseApiKey => firebaseApiKey;

  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? "1:592916974677:android:5366c1825a27cf201518dc"
      : "ios firebase app id";

  static String firebaseMessagingSenderId =
      (kIsWeb || Platform.isAndroid) ? "592916974677" : "ios firebase sender id";

  static String get firebasemessagingSenderId => firebaseMessagingSenderId;

  static String firebaseProjectId =
      (kIsWeb || Platform.isAndroid) ? "flutterfoodapp-e6742" : "ios firebase project id";

  static String firebaseDatabaseUrl =
      "https://flutterfoodapp-e6742-default-rtdb.firebaseio.com";

  /// Google Maps API key (Maps SDK + Geocoding API).
  static String mapKey = 'AIzaSyCLHQKJg5shpKs0uNiDHiZJTtBUMKl21ak';

  /// Payment Gateway keys.
  static const String stripePublishKey = '';
  static const String stripPublishKey = stripePublishKey;
  static String razorpayKey = '';

  /// Supported App Languages.
  static List<LocaleLanguageList> languageList = const [
    LocaleLanguageList(name: 'English', lang: 'en'),
  ];

  static String packageName = 'com.fooduser.app';
  static String signKey = '';
}
