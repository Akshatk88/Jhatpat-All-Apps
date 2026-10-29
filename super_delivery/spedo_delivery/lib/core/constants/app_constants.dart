import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:food_user_application/features/language/domain/models/language_listing_model.dart';

class AppConstants {
  static const String title = 'Jhatpat Delivery';
  static const String appFontFamily = 'Latin';

  /// Backend host. REST, Socket.IO and media URLs are all derived from it, so
  /// this is the single value to change when the environment moves.
  ///
  /// Overridable at build time so staging never needs a code change:
  ///   flutter build apk --dart-define=API_HOST=https://staging.example.com
  ///
  /// This must stay in step with the user and restaurant apps: an order placed
  /// against one host is invisible to a rider on the other, and dispatch,
  /// sockets and push all follow the host. Two neighbours are easy to reach for
  /// and wrong — `k9.appzeto.com` is a different machine (145.223.21.188), and
  /// `k9bharat.com` is this box's older port-5000 backend.
  static const String apiHost = String.fromEnvironment(
    'API_HOST',
    defaultValue: 'https://jhatpattaxi.com',
  );

  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '$apiHost/api/v1',
  );

  static String resolveMediaUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('data:')) {
      return v;
    }
    final path = v.startsWith('/') ? v : '/$v';
    return '$apiHost$path';
  }

  /// Firebase credentials for `jhatpat-d0e4f` (client `com.delivery.jhatpat`),
  /// mirroring android/app/google-services.json.
  ///
  /// Nothing reads these: this app calls `Firebase.initializeApp()` with no
  /// arguments, so the config file is the only thing that decides the project.
  /// They are corrected rather than deleted because the values they previously
  /// held (`flutterfoodapp-e6742`, sender 592916974677) were stale, and the
  /// restaurant app was passing exactly those into explicit `FirebaseOptions` —
  /// which override the config file and silently bound it to the wrong project.
  /// Leaving wrong constants lying around invites the same mistake here.
  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? "AIzaSyAAeZjaXyhCUBCtp7_ne-eGxWw7fFzj7Ck"
      : "ios firebase api key";

  static String get firbaseApiKey => firebaseApiKey;

  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? "1:1068476980955:android:dc5b3f71a74b56c2dfb6fe"
      : "ios firebase app id";

  static String firebaseMessagingSenderId = (kIsWeb || Platform.isAndroid)
      ? "1068476980955"
      : "ios firebase sender id";

  static String get firebasemessagingSenderId => firebaseMessagingSenderId;

  static String firebaseProjectId = (kIsWeb || Platform.isAndroid)
      ? "jhatpat-d0e4f"
      : "ios firebase project id";

  static String mapKey = (Platform.isAndroid)
      ? 'AIzaSyBbOTOv3KgTY__MAvPC1A7GZSO_5Wp1N88'
      : 'your ios map key';

  static const String stripPublishKey = '';

  static List<LocaleLanguageList> languageList = [
    LocaleLanguageList(name: 'English', lang: 'en'),
  ];

  static String packageName = 'com.delivery.jhatpat';
  static String signKey = '';

  static const String fontFamily = 'Latin';
}
