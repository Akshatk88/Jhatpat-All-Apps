/// A place the device's FCM token has to be mirrored to.
///
/// The super app talks to several route trees that each keep their **own**
/// token list. Food/taxi tokens live on the shared `users` document and are
/// written by `POST /api/v1/fcm-tokens/mobile/save`; the Service-Provider
/// module keeps a separate `fcmTokens` / `fcmTokenMobile` pair on `sp_users`
/// and only reads that one when it pushes. Registering with one does not
/// register with the other, so a customer with a service booking would simply
/// never be notified about it.
///
/// Rather than teach `core/push` which backends exist — it may not import a
/// module — each owner supplies a sink and [PushService] fans out to all of
/// them. Adding a sixth module later is one more registration, not an edit
/// here.
///
/// Implementations must be **quiet on failure**: a sink that throws must not
/// stop the others from being written, and must never surface an error to a
/// user who was only trying to log in.
abstract class PushTokenSink {
  const PushTokenSink();

  /// Short name, for logs only.
  String get debugLabel;

  /// Register [token] for the signed-in account.
  Future<void> saveToken(String token);

  /// Stop targeting this device. Called on logout, before the Firebase token
  /// itself is deleted.
  ///
  /// [token] is the outgoing token; a sink whose backend supports clearing
  /// every token for the account should prefer that, since a device whose
  /// token rotated while logged out would otherwise be left registered.
  Future<void> clearToken(String token);
}
