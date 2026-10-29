import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure-storage wrapper for the restaurant partner's session.
///
/// Everything here is cleared on logout except [hasSeenOnboarding] and
/// [hasSeenBatteryPrompt], which should persist across sessions on the same
/// device.
class TokenStorage {
  TokenStorage(this._storage);

  final FlutterSecureStorage _storage;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _restaurantIdKey = 'restaurant_id';
  static const _restaurantStatusKey = 'restaurant_status';
  static const _hasSeenOnboardingKey = 'has_seen_onboarding';
  static const _hasSeenBatteryPromptKey = 'has_seen_battery_prompt';
  static const _sellerVerticalKey = 'seller_vertical';

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<String?> get accessToken => _storage.read(key: _accessTokenKey);

  Future<String?> get refreshToken => _storage.read(key: _refreshTokenKey);

  Future<void> saveRestaurantSnapshot({
    required String id,
    required String status,
  }) async {
    await _storage.write(key: _restaurantIdKey, value: id);
    await _storage.write(key: _restaurantStatusKey, value: status);
  }

  Future<String?> get restaurantId => _storage.read(key: _restaurantIdKey);

  Future<String?> get restaurantStatus =>
      _storage.read(key: _restaurantStatusKey);

  Future<void> setHasSeenOnboarding() =>
      _storage.write(key: _hasSeenOnboardingKey, value: 'true');

  Future<bool> get hasSeenOnboarding async {
    final value = await _storage.read(key: _hasSeenOnboardingKey);
    return value == 'true';
  }

  Future<void> setHasSeenBatteryPrompt() =>
      _storage.write(key: _hasSeenBatteryPromptKey, value: 'true');

  Future<bool> get hasSeenBatteryPrompt async {
    final value = await _storage.read(key: _hasSeenBatteryPromptKey);
    return value == 'true';
  }

  /// Which seller product this session belongs to (`food` / `quick`).
  ///
  /// Stored as the raw wire value rather than an enum index so a reordering of
  /// the enum cannot silently repoint an existing session at the other backend.
  Future<void> saveSellerVertical(String wire) =>
      _storage.write(key: _sellerVerticalKey, value: wire);

  Future<String?> get sellerVertical => _storage.read(key: _sellerVerticalKey);

  Future<void> clear() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _restaurantIdKey);
    await _storage.delete(key: _restaurantStatusKey);
    // Deliberately cleared with the session: the next sign-in re-chooses the
    // vertical, so a logged-out app never keeps pointing at the backend the
    // previous operator happened to use.
    await _storage.delete(key: _sellerVerticalKey);
  }
}
