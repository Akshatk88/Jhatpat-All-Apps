import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:superapp_user/core/config/app_constants.dart';
import 'package:superapp_user/core/realtime/taxi_socket_events.dart';

/// Wraps the socket.io client for the rider app.
///
/// On connect the server automatically joins this socket to the rider's
/// personal room (`user:<id>`), which is where dispatch events such as
/// `rideAccepted` and `rideCancelled` are delivered. Ride-scoped events
/// (`ride:state`, chat, driver location) require an explicit [joinRide].
class TaxiSocketService {
  io.Socket? _socket;

  /// Every handler registered through [on], replayed on each [connect] — both
  /// for controllers built before the socket exists, and so a logout / login
  /// cycle (which disposes the socket) doesn't leave long-lived listeners
  /// attached to a dead socket.
  final List<MapEntry<String, void Function(dynamic)>> _pendingHandlers = [];

  /// Retained so the socket can be rebuilt without going back through auth.
  String? _token;

  /// Called every time the transport (re)connects.
  ///
  /// Socket.IO rooms are per-connection: a reconnect gets a **new** socket id
  /// and the server drops every room this client had joined. Nothing re-sends
  /// `ride:join` on its own, so without this a rider silently stops receiving
  /// ride-scoped events — including the completion that drives the rating
  /// screen — after any network blip mid-trip.
  ///
  /// A list rather than a single callback: the search and tracking controllers
  /// are both live at times, and a single field would let one clobber the other.
  final List<void Function()> _connectionListeners = [];

  /// Reads the freshest stored access token. Access tokens are short-lived and
  /// refreshed by the REST client, so a reconnect must not replay the token
  /// the socket was first opened with — the server would reject it and the
  /// socket (and with it live ride chat) would stay down for good.
  Future<String?> Function()? _tokenReader;

  /// Pending retry after the server refused the handshake.
  Timer? _authRetry;

  bool get isConnected => _socket?.connected ?? false;

  void connect(String token, {Future<String?> Function()? tokenReader}) {
    if (tokenReader != null) _tokenReader = tokenReader;
    if (_socket != null && _socket!.connected && _token == token) return;

    // A non-null but dead socket still owns its listeners and reconnect timers;
    // replacing it without disposing leaks one per reconnect.
    _authRetry?.cancel();
    _socket?.dispose();

    _token = token;
    final socket = io.io(
      AppConstants.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableReconnection()
          .setAuthFn((callback) => _resolveAuth(callback))
          .build(),
    );
    _socket = socket;
    for (final entry in _pendingHandlers) {
      socket.on(entry.key, entry.value);
    }
    socket.onConnect((_) {
      for (final listener in List<void Function()>.from(_connectionListeners)) {
        listener();
      }
    });
    // A handshake the server refuses (expired token) is not retried by the
    // client on its own. Try again shortly with whatever token is now stored.
    socket.onConnectError((error) {
      final text = '$error';
      if (!text.contains('AUTH') && !text.toLowerCase().contains('token')) return;
      _authRetry?.cancel();
      _authRetry = Timer(const Duration(seconds: 5), () {
        if (identical(_socket, socket) && !socket.connected) socket.connect();
      });
    });
    socket.connect();
  }

  void _resolveAuth(void Function(Map auth) callback) {
    final reader = _tokenReader;
    if (reader == null) {
      callback({'token': _token ?? ''});
      return;
    }
    reader().then((fresh) {
      if (fresh != null && fresh.isNotEmpty) _token = fresh;
      callback({'token': _token ?? ''});
    }).catchError((Object _) {
      callback({'token': _token ?? ''});
    });
  }

  /// Registers [listener] to run on every (re)connect. Returns a disposer.
  void Function() addConnectionListener(void Function() listener) {
    _connectionListeners.add(listener);
    return () => _connectionListeners.remove(listener);
  }

  /// Brings the transport back up if it has dropped. Safe to call repeatedly.
  bool ensureConnected() {
    final token = _token;
    if (token == null || token.isEmpty) return false;
    if (isConnected) return true;
    if (_socket != null) {
      _socket!.connect();
    } else {
      connect(token);
    }
    return true;
  }

  void disconnect() {
    _authRetry?.cancel();
    _tokenReader = null;
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _token = null;
  }

  void joinRide(String rideId) {
    _socket?.emit(SocketEvents.rideJoin, {'rideId': rideId});
  }

  void rejoinCurrentRide() {
    _socket?.emit(SocketEvents.rideRejoinCurrent);
  }

  /// Sends a ride chat message. The server echoes it to the whole ride room
  /// (sender included) as `ride:message:new`; failures come back on
  /// `errorMessage`. Returns false when there is no socket at all (signed
  /// out). While merely disconnected the emit is buffered and flushed on
  /// reconnect.
  bool sendRideMessage(String rideId, String message) {
    final socket = _socket;
    if (socket == null) return false;
    if (!socket.connected) ensureConnected();
    socket.emit(SocketEvents.rideMessageSend, {
      'rideId': rideId,
      'message': message,
    });
    return true;
  }

  void on(String event, void Function(dynamic data) handler) {
    _pendingHandlers.add(MapEntry(event, handler));
    _socket?.on(event, handler);
  }

  /// Removes a single [handler]. Always pass the handler you registered —
  /// omitting it drops *every* listener for [event], which would break other
  /// controllers subscribed to the same event.
  void off(String event, [void Function(dynamic data)? handler]) {
    if (handler == null) {
      _pendingHandlers.removeWhere((entry) => entry.key == event);
      _socket?.off(event);
      return;
    }
    _pendingHandlers.removeWhere(
      (entry) => entry.key == event && entry.value == handler,
    );
    _socket?.off(event, handler);
  }
}
