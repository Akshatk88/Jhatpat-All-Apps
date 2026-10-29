import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:superapp_user/modules/taxi/application/taxi_core_providers.dart';
import 'package:superapp_user/core/audio/taxi_audio_service.dart';
import 'package:superapp_user/core/realtime/taxi_socket_events.dart';
import 'package:superapp_user/core/realtime/taxi_socket_service.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_message_model.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_model.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_providers.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_state.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/modules/taxi/auth/application/auth_providers.dart';
import 'package:superapp_user/core/push/push_providers.dart';

class RideTrackingController extends Notifier<RideTrackingState> {
  RideTrackingController(this.rideId);

  final String rideId;
  late final TaxiSocketService _socket;
  Timer? _pollingTimer;

  /// Riverpod 3 notifiers expose no `mounted`; a poll in flight when the
  /// controller is torn down must not write to a disposed notifier.
  bool _disposed = false;

  /// Removes this controller's reconnect listener on teardown.
  late final void Function() _removeConnectionListener;

  @override
  RideTrackingState build() {
    _socket = ref.read(taxiSocketServiceProvider);
    // Building the auth controller is what opens the ride socket (it connects
    // on session). Nothing else guarantees it has been built by now.
    ref.read(authControllerProvider);
    _registerListeners();

    // Socket.IO rooms are per-connection: a reconnect gets a new socket id and
    // the server drops every room this client had joined. Re-joining here is
    // what stops a rider silently going deaf mid-trip after a network blip.
    _removeConnectionListener = _socket.addConnectionListener(_handleReconnected);
    _socket.joinRide(rideId);

    ref.onDispose(_teardown);

    // One system notification per stage change, whatever delivered it
    // (socket or poll). k9 only pushes `ride_accepted` over FCM, so the
    // later stages would otherwise never reach a rider who left the app.
    listenSelf((previous, next) {
      _notifyStageChange(next.ride);
      _detectDriverDropped(previous?.ride, next.ride);
    });

    // Deferred: build() must return synchronously, and it re-runs on
    // invalidation — firing the fetch inline would issue a duplicate request
    // and re-enter the notifier before it is registered.
    Future.microtask(_loadRide);
    _startPolling();

    return const RideTrackingState();
  }

  /// Stage last seen; null until the first load, which never notifies.
  RideStage? _notifiedStage;

  /// Set when this rider cancels, so they are not notified of their own act.
  bool _cancelledByRider = false;

  void _notifyStageChange(RideModel? ride) {
    if (ride == null) return;
    final stage = ride.stage;
    final previous = _notifiedStage;
    _notifiedStage = stage;
    if (previous == null || previous == stage) return;

    String? title;
    String body = '';
    switch (stage) {
      case RideStage.toPickup:
        // Covered by the backend's own `ride_accepted` push.
        return;
      case RideStage.atPickup:
        title = 'Driver has arrived at pickup'.tr;
        body = ride.otp.isNotEmpty
            ? 'Share OTP {otp} with your driver to start the trip'.trArgs({'otp': ride.otp})
            : 'Your driver is waiting at the pickup point'.tr;
        break;
      case RideStage.onTrip:
        title = 'Trip started'.tr;
        body = 'Enjoy your ride!'.tr;
        break;
      case RideStage.atDrop:
        title = 'Reached destination'.tr;
        body = 'You have reached your drop location'.tr;
        break;
      case RideStage.completed:
        title = 'Ride completed'.tr;
        body = 'Total fare ₹{fare}'.trArgs({'fare': ride.fare.toStringAsFixed(0)});
        break;
      case RideStage.cancelled:
        if (_cancelledByRider) return;
        title = 'Ride cancelled'.tr;
        body = 'Your driver cancelled the ride'.tr;
        break;
      case RideStage.searching:
        return;
    }
    unawaited(ref.read(pushServiceProvider).showLocal(
          id: Object.hash(rideId, stage.name) & 0x7fffffff,
          title: title,
          body: body,
          data: {
            'type': 'ride_status',
            'rideId': rideId,
            'status': stage == RideStage.completed
                ? 'completed'
                : stage == RideStage.cancelled
                    ? 'cancelled'
                    : ride.liveStatus,
          },
        ));
  }

  Timer? _dropTimer;
  DateTime? _lastRaisedAt;

  /// Backup for a missed `rideDriverCancelled`: a ride that had a driver and
  /// is back to searching means the driver cancelled (a rider cancel ends in
  /// `cancelled`, never `searching`). Waits briefly so the event, which
  /// carries the reason, wins when it is on its way.
  void _detectDriverDropped(RideModel? before, RideModel? after) {
    if (before == null || after == null || _cancelledByRider) return;
    final hadDriver =
        before.stage == RideStage.toPickup || before.stage == RideStage.atPickup;
    final raisedJustNow = _lastRaisedAt != null &&
        DateTime.now().difference(_lastRaisedAt!) < const Duration(seconds: 15);
    if (hadDriver && after.stage == RideStage.searching && !raisedJustNow) {
      _dropTimer?.cancel();
      _dropTimer = Timer(const Duration(milliseconds: 1500), () => _raiseDriverCancelled(null));
    }
  }

  void _raiseDriverCancelled(String? reason) {
    if (_disposed || _cancelledByRider) return;
    _dropTimer?.cancel();
    _lastRaisedAt = DateTime.now();
    final text = reason?.trim() ?? '';
    state = state.copyWith(
      driverCancelSeq: state.driverCancelSeq + 1,
      driverCancelReason: text,
    );
    unawaited(ref.read(pushServiceProvider).showLocal(
          id: Object.hash(rideId, 'driver-cancelled', state.driverCancelSeq) & 0x7fffffff,
          title: 'Driver cancelled your ride'.tr,
          body: text.isNotEmpty ? text : 'We are finding you another driver'.tr,
          data: {'type': 'ride_status', 'rideId': rideId, 'status': 'searching'},
        ));
  }

  /// `rideDriverCancelled { rideId, reason }` on the rider's room, emitted by
  /// the backend when the accepted driver cancels; the ride is re-opened.
  void _handleDriverCancelled(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final id = (map['rideId'] ?? '').toString();
    if (id.isNotEmpty && id != rideId) return;
    _raiseDriverCancelled(map['reason']?.toString());
    _loadRideSilently();
  }

  void _handleReconnected() {
    _socket.joinRide(rideId);
    _loadRide();
  }

  /// Last time the ride was confirmed from the server (REST or `ride:state`).
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _pollInFlight = false;

  /// Safety poll only. Status changes, chat and driver location all arrive on
  /// the socket (`ride:state`, `ride:status:updated`, `ride:message:new`,
  /// `ride:driver-location:updated`), and a reconnect re-joins the room and
  /// refetches at once. The old fixed 3 s poll re-fetched the fully populated
  /// ride ~20×/min per rider and rebuilt the whole tracking screen each time.
  ///
  /// Checked every 4 s: refetch when the socket is down and nothing was heard
  /// for 5 s, or every 12 s while it is up (covers a missed event or a room
  /// that silently was not joined).
  static const _pollTick = Duration(seconds: 4);
  static const _pollWhenConnected = Duration(seconds: 12);
  static const _pollWhenDisconnected = Duration(seconds: 5);

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(_pollTick, (_) {
      final r = state.ride;
      if (r != null && (r.isCompleted || r.isCancelled)) {
        _pollingTimer?.cancel();
        return;
      }
      if (_pollInFlight) return;
      final interval = _socket.isConnected ? _pollWhenConnected : _pollWhenDisconnected;
      if (DateTime.now().difference(_lastSyncAt) < interval) return;
      _loadRideSilently();
    });
  }

  void _checkAudioTrigger(RideModel? ride) {
    if (ride == null) return;
    final status = ride.status.toLowerCase();
    final liveStatus = ride.liveStatus.toLowerCase();

    if (status == 'started' || status == 'ongoing' || liveStatus == 'started') {
      AudioService.playTripStarted();
    } else if (status == 'completed' || liveStatus == 'completed') {
      AudioService.playRideEnded();
    }
  }

  Future<void> _loadRide() async {
    try {
      final ride = await ref.read(rideRepositoryProvider).getRideById(rideId);
      if (_disposed) return;
      _lastSyncAt = DateTime.now();
      state = state.copyWith(ride: _withMergedMessages(ride), isLoading: false);
      _checkAudioTrigger(ride);
    } catch (e) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> _loadRideSilently() async {
    _pollInFlight = true;
    try {
      final ride = await ref.read(rideRepositoryProvider).getRideById(rideId);
      if (!_disposed) {
        _lastSyncAt = DateTime.now();
        state = state.copyWith(ride: _withMergedMessages(ride));
        _checkAudioTrigger(ride);
      }
    } catch (_) {
    } finally {
      _pollInFlight = false;
    }
  }

  /// The ride document only carries the last 30 messages, and a poll issued
  /// before a live `ride:message:new` landed would otherwise wipe that message
  /// until the next poll. Keeps the union, ordered by time, plus any of our
  /// own sends the server has not confirmed yet.
  RideModel _withMergedMessages(RideModel fresh) {
    final current = state.ride?.messages ?? const <RideMessageModel>[];
    if (current.isEmpty) return fresh;
    final merged = _mergeMessages(current, fresh.messages);
    return fresh.copyWith(messages: merged);
  }

  static List<RideMessageModel> _mergeMessages(
    List<RideMessageModel> current,
    List<RideMessageModel> incoming,
  ) {
    final byId = <String, RideMessageModel>{};
    for (final m in current) {
      if (!m.pending && m.id.isNotEmpty) byId[m.id] = m;
    }
    for (final m in incoming) {
      if (m.id.isNotEmpty) byId[m.id] = m;
    }
    final confirmed = byId.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));

    // A pending send is settled by the first newly-arrived rider message with
    // the same text — one server message settles one pending bubble.
    final knownIds = current.where((m) => !m.pending).map((m) => m.id).toSet();
    final arrivals = confirmed
        .where((m) => m.isFromRider && !knownIds.contains(m.id))
        .toList();
    final pending = <RideMessageModel>[];
    for (final p in current.where((m) => m.pending)) {
      final match = arrivals.indexWhere((m) => m.message == p.message);
      if (match >= 0) {
        arrivals.removeAt(match);
      } else {
        pending.add(p);
      }
    }
    return [...confirmed, ...pending];
  }

  /// Each event once. `SocketEvents.rideState` *is* 'ride:state' (and likewise
  /// for status / driver location), so registering both spellings ran every
  /// handler twice per packet — two full-screen rebuilds per event.
  ///
  /// Driver location is not handled here any more: it lives in
  /// `driverLocationProvider`, so a GPS packet every few seconds no longer
  /// copies the whole ride and rebuilds the entire tracking screen.
  void _registerListeners() {
    _socket.on(SocketEvents.rideState, _handleRideState);
    _socket.on(SocketEvents.rideStatusUpdated, _handleStatusUpdated);
    _socket.on('ride_status_updated', _handleStatusUpdated);
    _socket.on('driver_arrived', _handleDriverArrived);
    _socket.on('trip_started', _handleTripStarted);
    _socket.on(SocketEvents.rideMessageNew, _handleNewMessage);
    _socket.on(SocketEvents.rideDriverCancelled, _handleDriverCancelled);
    _socket.on(SocketEvents.error, _handleSocketError);
  }

  void _handleRideState(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final payload = map['ride'] is Map ? Map<String, dynamic>.from(map['ride']) : map;
    if ((payload['rideId'] ?? payload['_id'] ?? payload['id'] ?? '').toString() != rideId) return;
    final ride = RideModel.fromJson(payload);
    _lastSyncAt = DateTime.now();
    state = state.copyWith(ride: _withMergedMessages(ride), isLoading: false);
    _checkAudioTrigger(ride);
  }

  void _handleDriverArrived(dynamic data) {
    final map = _asMap(data);
    if (map != null && (map['rideId'] ?? '').toString() != rideId) return;
    final ride = state.ride;
    if (ride != null) {
      final updated = ride.copyWith(liveStatus: 'arriving'); // k9: arriving = at pickup
      state = state.copyWith(ride: updated);
      _checkAudioTrigger(updated);
    }
    _loadRideSilently();
  }

  void _handleTripStarted(dynamic data) {
    final map = _asMap(data);
    if (map != null && (map['rideId'] ?? '').toString() != rideId) return;
    final ride = state.ride;
    if (ride != null) {
      final updated = ride.copyWith(status: 'started', liveStatus: 'started');
      state = state.copyWith(ride: updated);
      _checkAudioTrigger(updated);
    } else {
      AudioService.playTripStarted();
    }
    _loadRideSilently();
  }

  void _handleStatusUpdated(dynamic data) {
    final map = _asMap(data);
    if (map == null) return;
    final id = (map['rideId'] ?? map['_id'] ?? map['id'] ?? '').toString();
    if (id.isNotEmpty && id != rideId) return;

    final ride = state.ride;
    if (ride == null) {
      _loadRide();
      return;
    }

    DateTime? parseDate(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
    final updated = ride.copyWith(
      status: map['status']?.toString() ?? ride.status,
      liveStatus: map['liveStatus']?.toString() ?? map['status']?.toString() ?? ride.liveStatus,
      acceptedAt: parseDate(map['acceptedAt']) ?? ride.acceptedAt,
      arrivedAt: parseDate(map['arrivedAt']) ?? ride.arrivedAt,
      startedAt: parseDate(map['startedAt']) ?? ride.startedAt,
      completedAt: parseDate(map['completedAt']) ?? ride.completedAt,
      driver: map['driver'] is Map && (map['driver'] as Map).isNotEmpty
          ? RideDriverInfo.fromJson(Map<String, dynamic>.from(map['driver']))
          : ride.driver,
    );
    state = state.copyWith(ride: updated);
    _checkAudioTrigger(updated);
  }

  void _handleNewMessage(dynamic data) {
    final map = _asMap(data);
    final ride = state.ride;
    if (map == null || ride == null) return;
    if ((map['rideId'] ?? '').toString() != rideId) return;

    final message = RideMessageModel.fromJson(map);
    if (message.id.isEmpty) return;
    // Merge rather than append: the same message also arrives with the next
    // poll, and our own echo settles the matching pending bubble.
    final merged = _mergeMessages(ride.messages, [message]);
    state = state.copyWith(ride: ride.copyWith(messages: merged));
    if (!merged.any((m) => m.pending)) _pendingTimer?.cancel();
  }

  void _handleSocketError(dynamic data) {
    final map = _asMap(data);
    final text = map?['message']?.toString() ?? 'Something went wrong'.tr;
    // The taxi socket reports every failed operation on this one event with no
    // correlation id. While a chat send is unconfirmed, treat it as that send
    // failing so the rider is not left looking at a message that never went.
    if (_dropPending()) {
      state = state.copyWith(
        error: text,
        chatError: 'Message not sent. Please try again.'.tr,
        chatErrorSeq: state.chatErrorSeq + 1,
      );
      return;
    }
    state = state.copyWith(error: text);
  }

  Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Timer? _pendingTimer;

  /// Removes unconfirmed sends. Returns whether there were any.
  bool _dropPending() {
    final ride = state.ride;
    if (ride == null || !ride.messages.any((m) => m.pending)) return false;
    _pendingTimer?.cancel();
    state = state.copyWith(
      ride: ride.copyWith(messages: ride.messages.where((m) => !m.pending).toList()),
    );
    return true;
  }

  /// Sends a chat message to the driver over the ride room.
  ///
  /// Shown at once as a pending bubble; the server's `ride:message:new` echo
  /// replaces it. Returns false when it could not be sent at all.
  bool sendMessage(String message) {
    final text = message.trim();
    if (text.isEmpty) return false;
    final ride = state.ride;
    if (ride == null) return false;
    if (!_socket.sendRideMessage(rideId, text)) return false;

    final local = RideMessageModel(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      senderRole: 'user',
      senderId: '',
      message: text,
      sentAt: DateTime.now(),
      pending: true,
    );
    state = state.copyWith(ride: ride.copyWith(messages: [...ride.messages, local]));

    // No echo within this window: the poll would have shown it by now, so the
    // send is lost (dropped connection, server refused it silently).
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 20), () {
      if (_disposed) return;
      if (_dropPending()) {
        state = state.copyWith(
          chatError: 'Message not sent. Please try again.'.tr,
          chatErrorSeq: state.chatErrorSeq + 1,
        );
      }
    });
    return true;
  }

  Future<bool> cancelRide({String? reason}) async {
    _cancelledByRider = true;
    state = state.copyWith(isCancelling: true, clearError: true);
    try {
      await ref.read(rideRepositoryProvider).cancelRide(rideId, reason: reason);
      state = state.copyWith(isCancelling: false);
      return true;
    } catch (e) {
      _cancelledByRider = false;
      state = state.copyWith(isCancelling: false, error: e.toString());
      return false;
    }
  }

  Future<bool> submitReview({required int rating, String? comment, double tipAmount = 0}) async {
    try {
      await ref.read(rideRepositoryProvider).submitReview(
            rideId,
            rating: rating,
            comment: comment,
            tipAmount: tipAmount,
          );
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  void _teardown() {
    _disposed = true;
    _pollingTimer?.cancel();
    _pendingTimer?.cancel();
    _dropTimer?.cancel();
    _socket.off(SocketEvents.rideDriverCancelled, _handleDriverCancelled);
    _socket.off(SocketEvents.rideState, _handleRideState);
    _socket.off(SocketEvents.rideStatusUpdated, _handleStatusUpdated);
    _socket.off('ride_status_updated', _handleStatusUpdated);
    _socket.off('driver_arrived', _handleDriverArrived);
    _socket.off('trip_started', _handleTripStarted);
    _socket.off(SocketEvents.rideMessageNew, _handleNewMessage);
    _socket.off(SocketEvents.error, _handleSocketError);
    _removeConnectionListener();
  }
}

final rideTrackingControllerProvider = NotifierProvider.family<RideTrackingController, RideTrackingState, String>(RideTrackingController.new);

/// How many of the driver's chat messages the rider has already seen, per
/// ride — drives the unread badge on the tracking screen's chat button.
class RideChatSeenController extends Notifier<int> {
  RideChatSeenController(this.rideId);

  final String rideId;

  @override
  int build() => 0;

  void markSeen(int driverMessageCount) {
    if (driverMessageCount > state) state = driverMessageCount;
  }
}

final rideChatSeenProvider =
    NotifierProvider.family<RideChatSeenController, int, String>(RideChatSeenController.new);
