import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/app/super_app.dart';
import 'package:superapp_user/core/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[APP] App Started');

  final firebaseOk = await ensureFirebaseInitialized();
  if (firebaseOk) {
    debugPrint('[APP] Firebase Initialized');
  }

  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    debugPrint('[FCM] Background Handler Registered');
  } catch (e) {
    debugPrint('[FCM] Background Handler Registration failed: $e');
  }

  runApp(const ProviderScope(child: SuperApp()));
}
