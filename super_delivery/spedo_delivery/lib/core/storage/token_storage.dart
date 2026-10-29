import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:food_user_application/core/constants/app_constants.dart';

/// Wraps [FlutterSecureStorage] for persisting auth tokens across app restarts.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _fcmTokenKey = 'fcm_token';

  /// Keys the Android side reads. Must match `RiderCredentials.kt`.
  static const _nativeTokenKey = 'native_access_token';
  static const _nativeHostKey = 'native_api_base_url';
  static const _nativeRefreshKey = 'native_refresh_token';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
    await _mirrorForNative(accessToken, refreshToken: refreshToken);
  }

  Future<String?> getAccessToken() => _storage.read(key: _accessTokenKey);

  Future<String?> getRefreshToken() => _storage.read(key: _refreshTokenKey);

  Future<void> saveFcmToken(String token) =>
      _storage.write(key: _fcmTokenKey, value: token);

  Future<String?> getFcmToken() => _storage.read(key: _fcmTokenKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _mirrorForNative(null);
  }

  Future<bool> hasAccessToken() async =>
      (await getAccessToken())?.isNotEmpty ?? false;

  /// Re-copies the stored tokens for the native side. Called on app start so
  /// installs from before the refresh token was mirrored get it at once.
  Future<void> syncNativeMirror() async {
    final access = await getAccessToken();
    if (access == null || access.isEmpty) return;
    await _mirrorForNative(access, refreshToken: await getRefreshToken());
  }

  /// Copies the access token where the Android code can read it.
  ///
  /// The lock-screen offer card answers the offer itself — Reject in particular
  /// must not open the app — so the Kotlin side has to be able to call the API
  /// on its own. It cannot read [FlutterSecureStorage]: that is backed by
  /// EncryptedSharedPreferences with keys held by the plugin.
  ///
  /// Done here rather than at each call site because this class is the single
  /// point every login, silent refresh and logout already passes through, so the
  /// copy cannot drift out of step with the real token.
  ///
  /// The trade is that this copy sits in ordinary app-private preferences rather
  /// than encrypted ones. It is unreadable by other apps on an unrooted device,
  /// and it is cleared on logout with everything else.
  ///
  /// The refresh token is mirrored too: the access token lives 15 minutes, and
  /// an offer that arrives while the app is closed must be able to renew it —
  /// otherwise the overlay card loads nothing and Accept/Reject fail with 401.
  /// (The server returns the same refresh token on refresh, so renewing from
  /// the overlay never invalidates the app's own copy.)
  Future<void> _mirrorForNative(String? accessToken, {String? refreshToken}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (accessToken == null || accessToken.isEmpty) {
        await prefs.remove(_nativeTokenKey);
        await prefs.remove(_nativeRefreshKey);
      } else {
        await prefs.setString(_nativeTokenKey, accessToken);
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await prefs.setString(_nativeRefreshKey, refreshToken);
        }
        // The host is build-time configurable, so the native side is told
        // rather than left to hardcode a guess that staging would break.
        await prefs.setString(_nativeHostKey, AppConstants.baseUrl);
      }
    } catch (_) {
      // Worst case the card falls back to answering the offer once the app is
      // open; losing the mirror must never break signing in.
    }
  }
}

final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());
