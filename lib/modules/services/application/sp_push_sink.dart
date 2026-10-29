import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/core/network/network_providers.dart';
import 'package:superapp_user/core/push/push_token_sink.dart';
import 'package:superapp_user/modules/services/api/services_datasource.dart';

/// Mirrors the device's FCM token into the Service-Provider module's own token
/// list, so SP pushes actually reach this customer.
///
/// Why this exists at all: SP was ported whole from a standalone app and kept
/// its own `fcmTokens` / `fcmTokenMobile` arrays on `sp_users`. Its
/// `sendNotificationToUser` reads only those. The super app's existing
/// registration writes to the shared `users` document via
/// `/api/v1/fcm-tokens/mobile/save`, which SP never looks at — so before this,
/// a customer could book a service and be told about it over the socket while
/// the app was open, and hear nothing once it was backgrounded or killed.
///
/// Registering also depends on the identity bridge: the call is authenticated
/// with the app's one master-issued token, and SP's middleware resolves it to
/// the matching `sp_users` document (provisioning on first contact). So this
/// doubles as the thing that creates the customer's SP record at login rather
/// than at first booking.
class SpPushTokenSink extends PushTokenSink {
  const SpPushTokenSink(this._data);

  final ServicesDataSource _data;

  @override
  String get debugLabel => 'service-provider';

  /// The backend buckets tokens by platform, and only the mobile bucket is
  /// used by SP's mobile pushes.
  static String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'mobile';
  }

  @override
  Future<void> saveToken(String token) =>
      _data.saveFcmToken(token, platform: _platform);

  @override
  Future<void> clearToken(String token) =>
      // remove-all rather than remove: the token may have rotated since it was
      // registered, and dropping only the one we still remember would leave the
      // previous one live — meaning the next person to use this device could
      // receive the last customer's booking notifications.
      _data.removeAllFcmTokens(platform: _platform);

  /// Value equality so `addTokenSink` de-duplicates across rebuilds — the set
  /// in PushService would otherwise accumulate one instance per registration.
  @override
  bool operator ==(Object other) => other is SpPushTokenSink;

  @override
  int get hashCode => (SpPushTokenSink).hashCode;
}

/// The sink, built against the root-scoped API client.
///
/// Deliberately **not** inside the module's own provider scope: it has to
/// outlive the module so that logging out clears the SP token even when the
/// customer never opened the Services tab in that session.
final spPushTokenSinkProvider = Provider<SpPushTokenSink>((ref) {
  return SpPushTokenSink(ServicesDataSource(ref.watch(apiClientProvider)));
});
