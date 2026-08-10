import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Single source of truth for every environment-specific value the app needs
/// (backend host, map/Firebase keys, package identity). Update values here
/// only — nothing else in the codebase should hardcode these.
class TaxiConstants {
  TaxiConstants._();

  static const String title = 'UdanX';

  /// Backend REST API base URL (all endpoints are mounted under `/api/v1`).
  static const String baseUrl = 'https://taxi.appzeto.com/api/v1';

  /// Socket.IO server base (same host, root path — see `Backend/socket-server.js`).
  static const String socketUrl = 'https://taxi.appzeto.com';

  static String firebaseApiKey = (kIsWeb || Platform.isAndroid)
      ? 'AIzaSyDz_xEgDp2PE8c67Ij39unxTgBfN0pXdzU'
      : ''; // TODO: fill in once GoogleService-Info.plist is added for iOS
  static String firebaseAppId = (kIsWeb || Platform.isAndroid)
      ? '1:147333377409:android:8ec15b107e38b0bbc78c80'
      : '';
  static String firebaseMessagingSenderId = (kIsWeb || Platform.isAndroid)
      ? '147333377409'
      : '';
  static String firebaseProjectId = (kIsWeb || Platform.isAndroid)
      ? 'appzet-taxi'
      : '';

  /// Google Maps API key (Maps SDK for Android/iOS + Geocoding API enabled).
  static const String mapKey = 'AIzaSyArBbII2fgAuVaycfkEAm1GcuyvKPTSWyc';

  /// Razorpay publishable key — not yet provided.
  static const String stripPublishKey = '';

  static const String packageName = 'com.supertaxi.user';

  /// Release keystore signing key alias/password — not yet provided.
  static const String signKey = '';

  // --- App behaviour constants (unrelated to environment/build config) ---
  static const int otpLength = 4;
  static const int phoneLength = 10;
  static const double defaultZoomLevel = 16;
  static const Duration otpResendCooldown = Duration(seconds: 30);

  // --- Centralized Font Styles (matching Onboarding & App Theme) ---
  static const String fontFamily = 'Roboto';

  static const TextStyle fontStyleHeadline = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    color: Color(0xFF0F172A),
    letterSpacing: -0.5,
  );

  static const TextStyle fontStyleTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: Color(0xFF0F172A),
    letterSpacing: -0.3,
  );

  static const TextStyle fontStyleSubTitle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: Color(0xFF0F172A),
  );

  static const TextStyle fontStyleBody = TextStyle(
    fontSize: 13.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF64748B),
    height: 1.4,
  );

  static const TextStyle fontStyleCaption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: Color(0xFF94A3B8),
  );
}
