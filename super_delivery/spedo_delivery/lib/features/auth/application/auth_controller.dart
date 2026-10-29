import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/network/auth_event_bus.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/services/socket_service.dart';
import '../../../core/storage/token_storage.dart';
import '../data/auth_repository.dart';
import '../data/models/delivery_partner.dart';
import 'auth_state.dart';

class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;
  late final TokenStorage _tokenStorage;
  StreamSubscription<void>? _forceLogoutSub;

  @override
  AuthState build() {
    _repository = ref.read(authRepositoryProvider);
    _tokenStorage = ref.read(tokenStorageProvider);

    _forceLogoutSub = ref.read(authEventBusProvider).onForceLogout.listen((_) {
      ref.read(socketServiceProvider).disconnect();
      state = const AuthUnauthenticated();
    });
    ref.onDispose(() => _forceLogoutSub?.cancel());

    Future.microtask(checkAuthStatus);
    return const AuthInitial();
  }

  Future<void> checkAuthStatus() async {
    final hasToken = await _tokenStorage.hasAccessToken();
    if (!hasToken) {
      state = const AuthUnauthenticated();
      return;
    }
    state = const AuthLoading();
    // Give the offer overlay / native responder the refresh token too.
    unawaited(_tokenStorage.syncNativeMirror());
    final result = await _repository.getMe();
    result.when(
      success: (user) => _applyPartnerStatus(user),
      failure: (_) => state = const AuthUnauthenticated(),
    );
  }

  void _applyPartnerStatus(DeliveryPartner user) {
    if (user.isApproved) {
      state = AuthAuthenticated(user);
      _connectRealtime(user);
    } else {
      state = AuthPendingApproval(
        isRejected: user.isRejected,
        rejectionReason: user.rejectionReason,
        phone: user.phone.isNotEmpty ? user.phone : null,
        partner: user,
      );
    }
  }

  /// The status screen a re-application was started from, so backing out of
  /// the wizard returns to it instead of to a blank login.
  AuthPendingApproval? _reapplyFrom;

  /// A rejected partner chose to fix their application.
  ///
  /// The backend has no per-document re-upload for a partner who holds no
  /// token (none is issued before approval, and `/reverify` requires an
  /// approved account), but `/register` replaces a REJECTED record for the same
  /// phone — so fixing an application is registering again, prefilled.
  bool startReapplication() {
    final current = state;
    if (current is! AuthPendingApproval || !current.isRejected) return false;
    final phone = current.phone ?? current.partner?.phone ?? '';
    if (phone.isEmpty) return false;
    _reapplyFrom = current;
    state = AuthNeedsRegistration(
      phone,
      previousApplication:
          current.partner ??
          DeliveryPartner(
            id: '',
            name: '',
            phone: phone,
            status: 'rejected',
            rejectionReason: current.rejectionReason,
          ),
    );
    return true;
  }

  /// Back out of a re-application to the status screen it started from.
  void cancelReapplication() {
    final from = _reapplyFrom;
    if (from == null || state is! AuthNeedsRegistration) return;
    _reapplyFrom = null;
    state = from;
  }

  Future<void> _connectRealtime(DeliveryPartner user) async {
    final accessToken = await _tokenStorage.getAccessToken();
    if (accessToken == null || accessToken.isEmpty) return;
    ref
        .read(socketServiceProvider)
        .connect(
          accessToken: accessToken,
          partnerId: user.id,
          tokenReader: _tokenStorage.getAccessToken,
        );
    ref.read(fcmServiceProvider).registerToken();
  }

  Future<Result<String, AppError>> requestOtp(String phone) {
    return _repository.requestOtp(phone);
  }

  Future<AuthState> verifyOtp({required String phone, required String otp}) async {
    final fcmToken = await _tokenStorage.getFcmToken();
    final result = await _repository.verifyOtp(
      phone: phone,
      otp: otp,
      fcmToken: fcmToken,
    );
    return result.when(
      success: (verifyResult) {
        if (verifyResult.needsRegistration) {
          state = AuthNeedsRegistration(verifyResult.phone ?? phone);
        } else if (verifyResult.isLoggedIn && verifyResult.user != null) {
          _applyPartnerStatus(verifyResult.user!);
        } else if (verifyResult.pendingApproval) {
          state = AuthPendingApproval(
            isRejected: verifyResult.isRejected,
            rejectionReason: verifyResult.rejectionReason,
            phone: verifyResult.phone ?? phone,
            partner: verifyResult.pendingPartner,
          );
        } else {
          state = const AuthUnauthenticated();
        }
        return state;
      },
      failure: (error) {
        return AuthFailure(error.message);
      },
    );
  }

  Future<Result<void, AppError>> register(FormData formData) async {
    final result = await _repository.register(formData);
    return result.when(
      success: (user) {
        _reapplyFrom = null;
        _applyPartnerStatus(user);
        return const Result.success(null);
      },
      failure: (error) => Result.failure(error),
    );
  }

  void resetToUnauthenticated() {
    ref.read(socketServiceProvider).disconnect();
    state = const AuthUnauthenticated();
  }

  Future<void> logout() async {
    state = const AuthLoading();
    ref.read(socketServiceProvider).disconnect();
    await ref.read(fcmServiceProvider).removeToken();
    await _repository.logout();
    state = const AuthUnauthenticated();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
