import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class LocaleLanguageList {
  final String name;
  final String lang;
  final String? flag;

  const LocaleLanguageList({required this.name, required this.lang, this.flag});
}

/// Central App Constants for JhatPat User Application.
class AppConstants {
  const AppConstants._();

  static const String title = 'JhatPat';
  static const String appName = 'JhatPat';

  /// Merchant name shown on the Razorpay checkout sheet.
  ///
  /// Without this Razorpay falls back to the legal entity registered on the
  /// account ("SWITCHEATS PRIVATE LIMITED"), which is not our consumer brand.
  static const String brandName = 'Food+taxi';

  /// Public logo URL for the Razorpay sheet. Razorpay fetches this over the
  /// network, so a bundled asset cannot be used — it must be a hosted URL.
  /// Falls back to the backend's configured business logo when set.
  static const String brandLogoUrl = String.fromEnvironment('BRAND_LOGO_URL');
  static const String appVersion = '1.0.0';

  /// Backend REST API host domain.
  ///
  /// The merged master deployment (`/opt/master`, pm2 `master-api`, port 5007)
  /// behind nginx. One host serves every module — `/api/v1/food/*`,
  /// `/api/v1/taxi/*` and `/api/v1/sp/*` — plus the Socket.IO endpoint, so
  /// there is exactly one origin to change when the environment moves.
  static const String hostUrl = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://jhatpattaxi.com',
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

  /// Firebase project configuration for the super app (com.user.jhatpat).
  ///
  /// Project `jhatpat-d0e4f`.
  /// These values must stay in sync with `android/app/google-services.json`;
  /// they are only used as a fallback when the default `Firebase.initializeApp()`
  /// fails to read the platform config (see `ensureFirebaseInitialized`).
  ///
  /// iOS is not configured yet — there is no GoogleService-Info.plist for this
  /// project, so iOS builds will fall through to the failure branch.
  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? "AIzaSyAAeZjaXyhCUBCtp7_ne-eGxWw7fFzj7Ck"
      : "ios firebase api key";

  static String get firbaseApiKey => firebaseApiKey;

  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? "1:1068476980955:android:8b05a954e6d3e3d8dfb6fe"
      : "ios firebase app id";

  static String firebaseMessagingSenderId = (kIsWeb || Platform.isAndroid)
      ? "1068476980955"
      : "ios firebase sender id";

  static String get firebasemessagingSenderId => firebaseMessagingSenderId;

  static String firebaseProjectId = (kIsWeb || Platform.isAndroid)
      ? "jhatpat-d0e4f"
      : "ios firebase project id";

  /// Deliberately still the k9 backend's database (project k9rides-529a8),
  /// not jhatpat-d0e4f: live order tracking reads what the backend writes
  /// there. Move it only together with the backend.
  ///
  /// Regional RTDB instance — note this is NOT the default `.firebaseio.com`
  /// domain, so it must always be passed explicitly to
  /// `FirebaseDatabase.instanceFor(app:, databaseURL:)`.
  static String firebaseDatabaseUrl =
      "https://k9rides-529a8-default-rtdb.asia-southeast1.firebasedatabase.app";

  static const String firebaseStorageBucket =
      "jhatpat-d0e4f.firebasestorage.app";

  /// Google Maps API key (Maps SDK + Geocoding API).
  static String mapKey = 'AIzaSyBbOTOv3KgTY__MAvPC1A7GZSO_5Wp1N88';

  /// Payment Gateway keys.
  static const String stripePublishKey = '';
  static const String stripPublishKey = stripePublishKey;
  static String razorpayKey = '';

  /// Supported App Languages.
  static List<LocaleLanguageList> languageList = const [
    LocaleLanguageList(name: 'English', lang: 'en'),
  ];

  static String packageName = 'com.user.jhatpat';
  static String signKey = '';
}
