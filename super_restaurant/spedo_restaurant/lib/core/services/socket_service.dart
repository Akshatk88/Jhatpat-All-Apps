import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:food_user_application/config/constants/app_constants.dart';
import 'package:food_user_application/core/providers/core_providers.dart';

/// Thin wrapper around the Socket.IO connection used for live restaurant
/// events (`new_order`, `order_status_update`, ...). The server auto-joins
/// the `restaurant:<id>` room on connect based on the JWT role/id — see
/// `Backend/src/config/socket.js`.
class SocketService {
  SocketService(this._ref);

  final Ref _ref;
  io.Socket? _socket;

  Future<void> connect() async {
    if (_socket != null) return;
    final token = await _ref.read(tokenStorageProvider).accessToken;
    if (token == null || token.isEmpty) return;

    _socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .build(),
    );

    // The handshake token is read fresh on every (re)connect. A fixed map kept
    // the login-time access token forever, so once it expired every automatic
    // reconnect was rejected and live `new_order` events silently stopped.
    final storage = _ref.read(tokenStorageProvider);
    _socket?.auth = (void Function(Map data) send) {
      storage.accessToken.then(
        (fresh) => send({'token': fresh ?? token}),
        onError: (_) => send({'token': token}),
      );
    };

    _socket?.connect();

    _socket?.onDisconnect((reason) {
      // Socket.IO reconnects on its own after network drops. Only a server-side
      // kick needs a manual connect — and a deliberate client disconnect (logout
      // / dispose) must not be undone by reconnecting here, which it used to be.
      if (reason == 'io server disconnect') _socket?.connect();
    });
  }

  void on(String event, void Function(dynamic data) handler) {
    _socket?.on(event, handler);
  }

  void off(String event) {
    _socket?.off(event);
  }

  void disconnect() {
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService(ref);
  ref.onDispose(service.disconnect);
  return service;
});
