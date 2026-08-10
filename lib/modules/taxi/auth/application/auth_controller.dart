import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/modules/taxi/taxi_navigator_key.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/core/network/network_providers.dart';
import 'package:superapp_user/modules/taxi/home/application/ride_search_controller.dart';
import 'package:superapp_user/modules/taxi/auth/data/auth_repository.dart';
import 'package:superapp_user/modules/taxi/auth/data/models/user_model.dart';
import 'package:superapp_user/modules/taxi/auth/application/auth_providers.dart';
import 'package:superapp_user/modules/taxi/auth/application/auth_state.dart';

class AuthController extends Notifier<AuthState> {
  /// Guarded so repeated auth events cannot stack duplicate listeners.
  StreamSubscription<String>? _fcmRefreshSub;


  @override
  AuthState build() {
    // The 401-refresh-failed signal now comes from the shared ApiClient via
    // sessionExpiredProvider, rather than taxi owning its own Dio and setting
    // an onUnauthorized callback on it. One client, one session, one signal.
    ref.listen(sessionExpiredProvider, (_, __) => _handleUnauthorized());
    ref.onDispose(() => _fcmRefreshSub?.cancel());
    return const AuthState.unknown();
  }

  TaxiAuthRepository get _repo => ref.read(taxiAuthRepositoryProvider);

  Future<void> bootstrap() async {
    final token = await ref.read(tokenStorageProvider).accessToken;
    if (token == null || token.isEmpty) {
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return;
    }
    try {
      final user = await _repo.getCurrentUser();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      ref.read(taxiSocketServiceProvider).connect(token);
      // Arm dispatch listeners now, not when the search screen mounts —
      // `rideAccepted` can land within a second of the ride being created.
      ref.read(rideSearchControllerProvider);
      unawaited(_registerFcmToken());
    } catch (_) {
      await ref.read(tokenStorageProvider).clear();
      state = state.copyWith(status: AuthStatus.unauthenticated);
    }
  }

  /// Registers this device's push token with the backend so it can receive
  /// ride/notification pushes. Best-effort: Firebase may not be configured
  /// yet in every build, and this should never block sign-in.
  Future<void> _registerFcmToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await _uploadFcmToken(token);
    } catch (_) {
      // No Firebase project configured, or token fetch/upload failed.
    }

    // FCM rotates tokens (reinstall, restore, app-data clear). Without
    // re-registering, the server keeps a dead token and every ride push stops
    // arriving with no visible symptom. Guarded so repeated auth events
    // (bootstrap, then login) cannot stack duplicate subscriptions.
    _fcmRefreshSub ??= FirebaseMessaging.instance.onTokenRefresh.listen(_uploadFcmToken);
  }

  Future<void> _uploadFcmToken(String token) async {
    if (token.isEmpty) return;
    try {
      final platform = defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
      await _repo.saveFcmToken(token, platform: platform);
    } catch (_) {
      // Best-effort; a failed upload must never block sign-in.
    }
  }

  Future<OtpSendResult> sendOtp(String phone) {
    return _repo.sendOtp(phone);
  }

  Future<OtpVerifyResult> verifyOtp({required String phone, required String otp}) async {
    final result = await _repo.verifyOtp(phone: phone, otp: otp);
    if (result.exists && result.token != null && result.user != null) {
      await _persistSession(token: result.token!, user: result.user!);
    }
    return result;
  }

  Future<void> completeSignup({
    required String phone,
    required String name,
    String? email,
    String? gender,
    String? referralCode,
  }) async {
    final session = await _repo.signup(
      phone: phone,
      name: name,
      email: email,
      gender: gender,
      referralCode: referralCode,
    );
    await _persistSession(token: session.token, user: session.user);
  }

  Future<void> _persistSession({required String token, required TaxiUserModel user}) async {
    await ref.read(tokenStorageProvider).saveAccessToken(token);
    state = AuthState(status: AuthStatus.authenticated, user: user);
    ref.read(taxiSocketServiceProvider).connect(token);
    ref.read(rideSearchControllerProvider);
    unawaited(_registerFcmToken());
  }

  void updateUser(TaxiUserModel user) {
    state = state.copyWith(user: user);
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    ref.read(taxiSocketServiceProvider).disconnect();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _handleUnauthorized() async {
    final wasAuthenticated = state.status == AuthStatus.authenticated;
    await logout();
    if (!wasAuthenticated) return;
    final context = taxiRootNavigatorKey.currentContext;
    if (context != null) {
      GoRouter.of(context).go('/system/session-expired');
    }
  }
}
