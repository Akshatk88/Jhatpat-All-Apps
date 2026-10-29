import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:superapp_user/core/config/app_constants.dart';

/// Server -> client events on the `/sp` namespace.
///
/// Names are taken verbatim from the emit sites in
/// `Backend/src/modules/serviceProvider/controllers/**`. Anything not listed
/// here is addressed to vendors, workers or admins and is deliberately ignored
/// by the customer app.
class SpSocketEvents {
  const SpSocketEvents._();

  /// A vendor (or worker) took the job. Ends the searching screen.
  static const String bookingAccepted = 'booking_accepted';

  /// Any subsequent status change — assigned, on the way, work done, …
  static const String bookingUpdated = 'booking_updated';

  /// The wave scheduler exhausted every nearby partner. Terminal.
  static const String searchFailed = 'booking_search_failed';

  /// Payment captured server-side.
  static const String paymentSuccess = 'payment_success';

  /// Position of whoever is en route, ~1 every 2s (server-side rate limited).
  static const String liveLocation = 'live_location_update';

  /// Generic in-app notification push.
  static const String notification = 'notification';
}

/// One `live_location_update` frame.
@immutable
class SpLiveLocation {
  const SpLiveLocation({required this.lat, required this.lng, required this.heading});

  final double lat;
  final double lng;
  final double heading;

  static SpLiveLocation? fromJson(Map<String, dynamic> json) {
    final lat = _num(json['lat']);
    final lng = _num(json['lng']);
    if (lat == null || lng == null) return null;
    return SpLiveLocation(lat: lat, lng: lng, heading: _num(json['heading']) ?? 0);
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

/// A booking-scoped event, already tagged with which booking it belongs to.
@immutable
class SpBookingEvent {
  const SpBookingEvent(this.event, this.bookingId, this.data);

  final String event;
  final String bookingId;
  final Map<String, dynamic> data;

  String? get message => data['message']?.toString();
}

/// The customer app's connection to the Service-Provider realtime namespace.
///
/// This is a **second** Socket.IO connection, alongside the food/taxi one, and
/// that is deliberate: SP's handlers are mounted on `io.of('/sp')`
/// (`modules/serviceProvider/sockets/index.js`), its rooms are namespace-scoped
/// (`user_<id>` there cannot collide with food's `user:<id>`), and the two
/// halves of the backend were never merged into one event vocabulary. Socket.IO
/// multiplexes namespaces over one transport where the origin matches, so this
/// is cheap.
///
/// It authenticates with the app's **one** master-issued access token. SP's
/// socket middleware runs the same identity bridge as its REST middleware, so
/// the connection lands in `user_<spUserId>` — which is the room every server
/// emit actually targets. Without that bridge this class would connect happily
/// and receive nothing, which is exactly the failure it is worth knowing about.
///
/// Sockets are an accelerator, never the contract. Every screen driven by these
/// events must also be able to reach the same state by refetching, because a
/// backgrounded socket is paused and misses everything sent meanwhile.
class SpSocketService {
  io.Socket? _socket;
  String? _token;

  /// The customer's **SP** user id (`sp_users._id`), not the master id.
  /// Obtained from `GET /sp/users/profile`.
  String? _userId;

  /// Re-joined on every (re)connect. Socket.IO rooms are per-connection: a
  /// reconnect gets a new socket id and the server has dropped every room, so
  /// without replaying these the app goes silently deaf after a network blip.
  final Set<String> _trackedBookings = {};

  final _bookingController = StreamController<SpBookingEvent>.broadcast();
  final _locationControllers = <String, StreamController<SpLiveLocation>>{};

  /// Booking lifecycle events for every booking this customer owns.
  Stream<SpBookingEvent> get bookingEvents => _bookingController.stream;

  bool get isConnected => _socket?.connected ?? false;

  /// Live position of whoever is en route for [bookingId].
  ///
  /// Only produces frames after [joinTracking] for the same booking; the server
  /// refuses room joins from anyone who is not a party to the booking.
  Stream<SpLiveLocation> locationFor(String bookingId) => _locationControllers
      .putIfAbsent(bookingId, () => StreamController<SpLiveLocation>.broadcast())
      .stream;

  /// Opens the connection, or re-opens it if the token or user changed.
  void connect({required String accessToken, required String spUserId}) {
    if (_socket != null && _token == accessToken && _userId == spUserId) {
      return;
    }

    // A non-null but stale socket still owns its listeners and reconnect
    // timers; replacing without disposing leaks one set per call.
    _socket?.dispose();

    _token = accessToken;
    _userId = spUserId;

    try {
      final socket = io.io(
        // The namespace is part of the URI for socket.io clients.
        '${AppConstants.socketUrl}/sp',
        io.OptionBuilder()
            // Polling first: some mobile networks and corporate proxies block
            // the websocket upgrade handshake outright, and a websocket-only
            // client simply never connects there.
            .setTransports(['polling', 'websocket'])
            .setAuth({'token': accessToken})
            .disableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(1 << 30)
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .build(),
      );

      void rejoinRooms(_) {
        _log('connected');
        // The server joins `user_<id>` automatically from the token, but the
        // explicit event is the documented fallback and is idempotent.
        socket.emit('join_user_room', _userId);
        for (final bookingId in _trackedBookings) {
          socket.emit('join_tracking', bookingId);
        }
      }

      socket.onConnect(rejoinRooms);
      socket.onReconnect(rejoinRooms);

      for (final event in const [
        SpSocketEvents.bookingAccepted,
        SpSocketEvents.bookingUpdated,
        SpSocketEvents.searchFailed,
        SpSocketEvents.paymentSuccess,
      ]) {
        socket.on(event, (payload) => _emitBooking(event, payload));
      }

      socket.on(SpSocketEvents.liveLocation, _emitLocation);

      socket.onConnectError((e) => _log('connect error: $e'));
      socket.onError((e) => _log('error: $e'));

      socket.connect();
      _socket = socket;
    } catch (e) {
      // Polling covers every screen; a socket failure must never surface.
      _log('unavailable: $e');
    }
  }

  /// Watches a booking's live location room.
  ///
  /// The server validates that this customer owns the booking and silently
  /// ignores the join otherwise, so this is safe to call optimistically.
  void joinTracking(String bookingId) {
    if (bookingId.isEmpty) return;
    _trackedBookings.add(bookingId);
    _socket?.emit('join_tracking', bookingId);
  }

  void leaveTracking(String bookingId) {
    _trackedBookings.remove(bookingId);
    _locationControllers.remove(bookingId)?.close();
  }

  void _emitBooking(String event, dynamic payload) {
    if (_bookingController.isClosed) return;
    final data = payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{};
    final bookingId = (data['bookingId'] ?? data['_id'] ?? '').toString();
    _bookingController.add(SpBookingEvent(event, bookingId, data));
  }

  /// `live_location_update` carries no booking id — it is scoped by the room it
  /// was broadcast to. With one tracking room open at a time (the tracking
  /// screen joins on entry and leaves on exit) the frame belongs to that
  /// booking. If several are ever open at once the server would need to start
  /// stamping the payload; until then, fan out to every open room rather than
  /// guessing wrong.
  void _emitLocation(dynamic payload) {
    final data = payload is Map ? payload.cast<String, dynamic>() : <String, dynamic>{};
    final location = SpLiveLocation.fromJson(data);
    if (location == null) return;
    for (final controller in _locationControllers.values) {
      if (!controller.isClosed) controller.add(location);
    }
  }

  /// Closes the connection — on logout, or when the session expires.
  void disconnect() {
    final socket = _socket;
    _socket = null;
    _token = null;
    _userId = null;
    _trackedBookings.clear();
    for (final controller in _locationControllers.values) {
      controller.close();
    }
    _locationControllers.clear();
    try {
      socket?.dispose();
    } catch (_) {
      // Already gone.
    }
  }

  void dispose() {
    disconnect();
    _bookingController.close();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[SP Socket] $message');
  }
}
