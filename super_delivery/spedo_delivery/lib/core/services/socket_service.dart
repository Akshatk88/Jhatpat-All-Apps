import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../constants/app_constants.dart';

/// Wraps the Socket.IO connection to the delivery backend and exposes
/// broadcast streams for the events documented in the realtime section
/// of DELIVERY_API_SPEC.md. Polling `/orders/available` remains the
/// required fallback — this is a convenience layer on top, not a
/// replacement for it.
class SocketService {
  io.Socket? _socket;

  final _newOrderController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderClaimedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderDeassignedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderReadyController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _orderStatusUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _locationUpdateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _chatMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _chatTypingController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  // ── Taxi dispatch ─────────────────────────────────────────────────
  // Emitted by the taxi dispatcher into the driver's own room. Unlike the
  // food events these are namespaced camelCase, because they come from the
  // taxi module's socket layer rather than the food one.
  final _rideRequestController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rideRequestClosedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rideStateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rideAcceptedController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _socketErrorController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _rideMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get onNewOrderAvailable =>
      _newOrderController.stream;
  Stream<Map<String, dynamic>> get onOrderClaimed =>
      _orderClaimedController.stream;
  Stream<Map<String, dynamic>> get onOrderDeassigned =>
      _orderDeassignedController.stream;
  Stream<Map<String, dynamic>> get onOrderReady => _orderReadyController.stream;
  Stream<Map<String, dynamic>> get onOrderStatusUpdate =>
      _orderStatusUpdateController.stream;
  Stream<Map<String, dynamic>> get onLocationUpdate =>
      _locationUpdateController.stream;
  Stream<Map<String, dynamic>> get onChatMessage =>
      _chatMessageController.stream;
  Stream<Map<String, dynamic>> get onChatTyping =>
      _chatTypingController.stream;
  Stream<bool> get onConnectionChange => _connectionController.stream;

  /// A ride is being offered to this driver. Carries the full offer — pickup,
  /// drop, fare and the accept window — so the alert can be raised without a
  /// round trip.
  Stream<Map<String, dynamic>> get onRideRequest =>
      _rideRequestController.stream;

  /// The offer is gone: taken by another driver, cancelled by the passenger,
  /// or the accept window expired.
  Stream<Map<String, dynamic>> get onRideRequestClosed =>
      _rideRequestClosedController.stream;

  /// Server-side movement on a ride this driver already holds — chiefly a
  /// passenger cancellation mid-trip.
  Stream<Map<String, dynamic>> get onRideState => _rideStateController.stream;

  /// This driver won the ride. Emitted only to the socket that claimed it.
  Stream<Map<String, dynamic>> get onRideAccepted =>
      _rideAcceptedController.stream;

  /// The taxi module reports every failed socket operation on one channel,
  /// including losing an accept race — there is no per-call ack.
  Stream<Map<String, dynamic>> get onSocketError =>
      _socketErrorController.stream;

  /// A message in a ride chat (`ride:message:new`), from either side. Only
  /// delivered to sockets in the ride room.
  Stream<Map<String, dynamic>> get onRideMessage =>
      _rideMessageController.stream;

  bool get isConnected => _socket?.connected ?? false;

  String? _token;
  Future<String?> Function()? _tokenReader;
  Timer? _authRetry;

  /// Opens the socket.
  ///
  /// [tokenReader] is consulted on every handshake. Access tokens are
  /// short-lived and refreshed by the REST client; replaying the token the
  /// socket was first opened with after a network blip gets the handshake
  /// refused, and the socket — with order offers and chat — stays down.
  void connect({
    required String accessToken,
    required String partnerId,
    Future<String?> Function()? tokenReader,
  }) {
    disconnect();
    _token = accessToken;
    _tokenReader = tokenReader;

    _socket = io.io(
      AppConstants.apiHost,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuthFn(_resolveAuth)
          .enableReconnection()
          .disableAutoConnect()
          .build(),
    );

    final socket = _socket!;

    socket.onConnect((_) {
      _connectionController.add(true);
      socket.emit('join-delivery', partnerId);
    });
    socket.onDisconnect((_) => _connectionController.add(false));
    socket.onConnectError((error) {
      _connectionController.add(false);
      // A refused handshake (expired token) is not retried by the client on
      // its own; try again with whatever token is stored by then.
      final text = '$error';
      if (!text.contains('AUTH') && !text.toLowerCase().contains('token')) return;
      _authRetry?.cancel();
      _authRetry = Timer(const Duration(seconds: 5), () {
        if (identical(_socket, socket) && !socket.connected) socket.connect();
      });
    });

    socket.on(
      'new_order_available',
      (data) => _newOrderController.add(_asMap(data)),
    );
    // Primary dispatch broadcasts use 'new_order'; re-offer rounds use
    // 'new_order_available' — both feed the same incoming-order stream.
    socket.on('new_order', (data) => _newOrderController.add(_asMap(data)));
    socket.on('order_claimed', (data) => _orderClaimedController.add(_asMap(data)));
    socket.on(
      'order_deassigned',
      (data) => _orderDeassignedController.add(_asMap(data)),
    );
    socket.on('order_ready', (data) => _orderReadyController.add(_asMap(data)));
    socket.on(
      'order_status_update',
      (data) => _orderStatusUpdateController.add(_asMap(data)),
    );
    socket.on(
      'location-update',
      (data) => _locationUpdateController.add(_asMap(data)),
    );
    socket.on(
      'chat:message',
      (data) => _chatMessageController.add(_asMap(data)),
    );
    socket.on(
      'chat:typing',
      (data) => _chatTypingController.add(_asMap(data)),
    );

    socket.on('rideRequest', (data) => _rideRequestController.add(_asMap(data)));
    socket.on(
      'rideRequestClosed',
      (data) => _rideRequestClosedController.add(_asMap(data)),
    );
    socket.on('ride:state', (data) => _rideStateController.add(_asMap(data)));
    // Status-only acknowledgement sent to the ride room on every transition
    // (and on a driver cancel, with status 'searching'). Same consumer as
    // ride:state, which tells the two apart by whether a full document came.
    socket.on(
      'ride:status:updated',
      (data) => _rideStateController.add(_asMap(data)),
    );
    socket.on(
      'ride:message:new',
      (data) => _rideMessageController.add(_asMap(data)),
    );
    socket.on(
      'rideAccepted',
      (data) => _rideAcceptedController.add(_asMap(data)),
    );
    socket.on(
      'errorMessage',
      (data) => _socketErrorController.add(_asMap(data)),
    );
    socket.on(
      'rideCancelled',
      (data) => _rideStateController.add({..._asMap(data), 'status': 'cancelled'}),
    );

    socket.connect();
  }

  /// Ride-scoped events (`ride:state`, chat) are only delivered to sockets that
  /// have joined the ride room; the driver room alone is not enough.
  ///
  /// Rooms are per-connection, so this has to be re-sent after every reconnect
  /// — see the connection listener in the active-ride controller.
  void joinRide(String rideId) => _socket?.emit('ride:join', {'rideId': rideId});

  /// Sends a chat message to the passenger on [rideId]. The server echoes it
  /// to the whole ride room as `ride:message:new`, sender included.
  ///
  /// Returns false when there is no socket at all (signed out). While merely
  /// disconnected the emit is buffered and flushed on reconnect.
  bool sendRideMessage(String rideId, String message) {
    final socket = _socket;
    if (socket == null) return false;
    if (!socket.connected) socket.connect();
    socket.emit('ride:message:send', {'rideId': rideId, 'message': message});
    return true;
  }

  /// Brings a dropped socket back up (e.g. on app resume). Safe to repeat.
  void ensureConnected() {
    final socket = _socket;
    if (socket == null || socket.connected) return;
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

  /// Claims an offered ride.
  ///
  /// Socket-only by design on the backend: acceptance is a first-wins
  /// transaction against a ride this driver does not yet hold, so there is no
  /// REST equivalent — `PATCH /rides/:id/status` looks the ride up by
  /// `{_id, driverId}` and 404s until the claim has already succeeded.
  ///
  /// Success arrives on [onRideAccepted], loss on [onSocketError].
  void acceptRide(String rideId) => _socket?.emit('acceptRide', {'rideId': rideId});

  /// Declines an offer so dispatch can move to the next driver immediately
  /// rather than waiting out the accept window.
  void rejectRide(String rideId) => _socket?.emit('rejectRide', {'rideId': rideId});

  /// Keeps this driver's position current in the taxi matching index, which is
  /// what decides whether they are inside the dispatch radius at all. Send it
  /// whenever online, ride or no ride.
  ///
  /// Coordinates are GeoJSON order — `[lng, lat]`. The server rejects the pair
  /// outright if it is the wrong way round only when it falls outside valid
  /// ranges, so most of India would be silently accepted and mislocated.
  void sendDriverLocation({required double lat, required double lng}) {
    _socket?.emit('locationUpdate', {
      'coordinates': [lng, lat],
    });
  }

  /// Live position *within a ride*, which is what moves the marker on the
  /// passenger's map. The server authorises by ride ownership, not room
  /// membership, but [joinRide] is still needed to *receive* ride events.
  ///
  /// Returns false (and sends nothing) while the socket is down: socket.io
  /// buffers emits made while disconnected and flushes them all on reconnect,
  /// which replays a burst of stale positions on the passenger's map. A
  /// position is only worth sending live; the caller pushes a fresh one on
  /// reconnect instead.
  ///
  /// `accuracy` (m) and `timestamp` (fix time, epoch ms) are extra fields the
  /// current backend ignores (it destructures rideId/coordinates/heading/
  /// speed only); they are sent so a server that starts honouring them can
  /// drop out-of-order fixes without an app release.
  bool sendRideDriverLocation({
    required String rideId,
    required double lat,
    required double lng,
    double? heading,
    double? speed,
    double? accuracy,
    int? timestamp,
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    socket.emit('ride:driver-location:update', {
      'rideId': rideId,
      'coordinates': [lng, lat],
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      if (timestamp != null) 'timestamp': timestamp,
    });
    return true;
  }

  void joinTracking(String orderId) => _socket?.emit('join-tracking', orderId);

  void leaveTracking(String orderId) =>
      _socket?.emit('leave-tracking', orderId);

  void sendLocationUpdate({
    required String orderId,
    required double lat,
    required double lng,
    String? userId,
    String? restaurantId,
    double? heading,
    double? speed,
    double? accuracy,
  }) {
    _socket?.emit('update-location', {
      'orderId': orderId,
      'lat': lat,
      'lng': lng,
      if (userId != null) 'userId': userId,
      if (restaurantId != null) 'restaurantId': restaurantId,
      if (heading != null) 'heading': heading,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
    });
  }

  void sendChatTyping({
    required String toRole,
    String? toId,
    required String conversationId,
    required bool typing,
  }) {
    _socket?.emit('chat:typing', {
      'toRole': toRole,
      if (toId != null) 'toId': toId,
      'conversationId': conversationId,
      'typing': typing,
    });
  }

  void disconnect() {
    _authRetry?.cancel();
    _socket?.dispose();
    _socket = null;
  }

  void dispose() {
    disconnect();
    _newOrderController.close();
    _orderClaimedController.close();
    _orderDeassignedController.close();
    _orderReadyController.close();
    _orderStatusUpdateController.close();
    _locationUpdateController.close();
    _chatMessageController.close();
    _chatTypingController.close();
    _connectionController.close();
    _rideRequestController.close();
    _rideRequestClosedController.close();
    _rideStateController.close();
    _rideAcceptedController.close();
    _socketErrorController.close();
    _rideMessageController.close();
  }

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return <String, dynamic>{};
  }
}

final socketServiceProvider = Provider<SocketService>((ref) {
  final service = SocketService();
  ref.onDispose(service.dispose);
  return service;
});
