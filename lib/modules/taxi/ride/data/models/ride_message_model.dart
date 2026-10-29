/// One ride chat message — `ride.messages[]` (the ride document carries the
/// last 30) and the `ride:message:new` socket push share this shape:
/// `{ id, rideId?, senderRole: 'user' | 'driver', senderId, message, sentAt }`.
class RideMessageModel {
  final String id;
  final String senderRole;
  final String senderId;
  final String message;
  final DateTime sentAt;

  /// True for a message this device has sent but the server has not echoed
  /// back yet. Never comes from the server.
  final bool pending;

  const RideMessageModel({
    required this.id,
    required this.senderRole,
    required this.senderId,
    required this.message,
    required this.sentAt,
    this.pending = false,
  });

  /// The rider's own messages. Anything not from the driver is ours: the
  /// server only stores `user` / `driver`.
  bool get isFromRider => senderRole.toLowerCase() != 'driver';

  factory RideMessageModel.fromJson(Map<String, dynamic> json) {
    return RideMessageModel(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      senderRole: (json['senderRole'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      // The server sends UTC; bubbles show the device's local time.
      sentAt: (DateTime.tryParse('${json['sentAt']}') ?? DateTime.now()).toLocal(),
    );
  }
}
