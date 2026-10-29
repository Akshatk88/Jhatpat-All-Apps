import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:food_user_application/app.dart';
import 'package:food_user_application/core/services/fcm_service.dart';
import 'package:food_user_application/features/orders/presentation/views/order_overlay_app.dart';
import 'config/constants/app_constants.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Surface framework-caught errors (widget build/layout/paint) instead of
    // letting them silently die, without taking the app down.
    FlutterError.onError = FlutterError.presentError;
    // Catches everything else (async errors outside a caught Future) so a
    // stray exception can't reach the platform embedder as a fatal crash.
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) debugPrint('Uncaught error: $error\n$stack');
      return true;
    };

    try {
      // No-argument init reads `android/app/google-services.json`, which is the
      // single source of truth for which Firebase project this app belongs to
      // (`jhatpat-d0e4f` — the Jhatpat Firebase project).
      //
      // This used to pass explicit `FirebaseOptions`. Those OVERRIDE the config
      // file, and they named the old `flutterfoodapp-e6742` project, so the app
      // registered FCM tokens with one project while the backend pushed from
      // another — tokens saved fine and no notification ever arrived. Only fall
      // back to explicit options if the platform config cannot be read.
      try {
        await Firebase.initializeApp();
      } on Exception {
        await Firebase.initializeApp(
          options: FirebaseOptions(
            apiKey: AppConstants.firbaseApiKey,
            appId: AppConstants.firebaseAppId,
            messagingSenderId: AppConstants.firebasemessagingSenderId,
            projectId: AppConstants.firebaseProjectId,
          ),
        );
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (e, s) {
      // On devices with missing/outdated Google Play Services (common on
      // budget phones) this used to throw here, before runApp — killing the
      // app on launch with no UI shown at all. Push notifications simply
      // won't work if this fails; that beats a crash on every open.
      if (kDebugMode) debugPrint('Firebase init failed: $e\n$s');
    }

    runApp(const ProviderScope(child: FoodUserApplication()));
  }, (error, stack) {
    if (kDebugMode) debugPrint('Uncaught zone error: $error\n$stack');
  });
}

/// Entry point of the overlay plugin's own Flutter engine — the new-order
/// request drawn over other apps (see [OrderOverlayApp]). Must stay top-level
/// in this file with this exact name: the plugin starts "overlayMain" from the
/// app's default entrypoint library.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Plugins (audio, prefs, secure storage, notifications) in this engine.
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  runApp(const OrderOverlayApp());
}
