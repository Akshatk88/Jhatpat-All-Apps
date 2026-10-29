import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

class AppConstants {
  static const String title = 'Jhatpat Restaurant';

  /// Backend REST API base URL (all endpoints are mounted under `/api/v1`).
  static const String baseUrl = 'https://jhatpattaxi.com/api/v1';

  /// Socket.IO server base (same host, root path — see `Backend/socket-server.js`).
  static const String socketUrl = 'https://jhatpattaxi.com';

  /// Firebase fallback credentials for `jhatpat-d0e4f` (client `com.restaurant.jhatpat`) — the project the
  /// master backend sends through.
  ///
  /// These are a FALLBACK ONLY. `Firebase.initializeApp()` is called with no
  /// arguments first, so the values in `android/app/google-services.json` win;
  /// these exist for the case where the platform config cannot be read (a
  /// stripped build, or iOS, which has no GoogleService-Info.plist yet).
  ///
  /// They previously named `flutterfoodapp-e6742` (sender 592916974677) and
  /// were passed as explicit `FirebaseOptions`, which OVERRIDE the config file.
  /// The app therefore registered its FCM tokens against the old project while
  /// the backend sent through the new one, so pushes were accepted and never
  /// delivered. Keep these in sync with `google-services.json`.
  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? "AIzaSyAAeZjaXyhCUBCtp7_ne-eGxWw7fFzj7Ck"
      : "ios firebase api key";

  static String get firbaseApiKey => firebaseApiKey;

  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? "1:1068476980955:android:9f214668a5797b00dfb6fe"
      : "ios firebase app id"; 

  static String firebaseMessagingSenderId = (kIsWeb || Platform.isAndroid)
      ? "1068476980955"
      : "ios firebase sender id";

  static String get firebasemessagingSenderId => firebaseMessagingSenderId;

  static String firebaseProjectId = (kIsWeb || Platform.isAndroid)
      ? "jhatpat-d0e4f"
      : "ios firebase project id";

  /// Google Maps API key (Maps SDK for Android/iOS + Geocoding API enabled).
  static String mapKey = 'AIzaSyBbOTOv3KgTY__MAvPC1A7GZSO_5Wp1N88';

  static const String stripPublishKey = '';

  static String packageName = 'com.restaurant.jhatpat';
  static String signKey = '';
}
