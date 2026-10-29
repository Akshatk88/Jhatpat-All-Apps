import 'package:superapp_user/core/i18n/tr.dart';

/// One row of `GET /food/chat/conversations`.
class ChatConversation {
  final String conversationId;
  final String? orderId;

  /// `"DELIVERY_PARTNER:<id>"` or `"ADMIN"` — parsed apart by [peerRole]/[peerId].
  final String peerToken;
  final String lastMessage;
  final DateTime? lastAt;
  final int unread;

  /// Subject the user chose when opening a support thread, e.g.
  /// "I want to cancel my order". Empty for plain order chats, which have no
  /// subject — the UI falls back to the peer's name for those.
  final String title;

  /// `open` | `in_progress` | `closed`. Threads predating support tracking have
  /// no stored status and the server reports them as `open`.
  final String status;

  final DateTime? createdAt;

  /// Only set once the thread is closed.
  final DateTime? closedAt;

  const ChatConversation({
    required this.conversationId,
    this.orderId,
    this.peerToken = '',
    this.lastMessage = '',
    this.lastAt,
    this.unread = 0,
    this.title = '',
    this.status = 'open',
    this.createdAt,
    this.closedAt,
  });

  String get peerRole => peerToken.contains(':') ? peerToken.split(':').first : peerToken;
  String? get peerId => peerToken.contains(':') ? peerToken.split(':').last : null;

  bool get isClosed => status == 'closed';

  /// Human label for [status], for a badge.
  String get statusLabel {
    switch (status) {
      case 'closed':
        return 'Closed'.tr;
      case 'in_progress':
        return 'In Progress'.tr;
      default:
        return 'Open'.tr;
    }
  }

  static DateTime? _date(Object? value) {
    final raw = value?.toString();
    return (raw == null || raw.isEmpty) ? null : DateTime.tryParse(raw);
  }

  factory ChatConversation.fromApi(Map<String, dynamic> json) {
    return ChatConversation(
      conversationId: (json['conversationId'] ?? '').toString(),
      orderId: json['orderId']?.toString(),
      peerToken: (json['peerToken'] ?? '').toString(),
      lastMessage: (json['lastMessage'] ?? '').toString(),
      lastAt: _date(json['lastAt']),
      unread: num.tryParse('${json['unread']}')?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: _date(json['createdAt']),
      closedAt: _date(json['closedAt']),
    );
  }
}

/// One row of `GET /food/chat/messages` and the `POST` response / socket push.
class ChatMessage {
  final String id;
  final String conversationId;
  final String? orderId;
  final String senderRole;
  final String senderId;
  final String recipientRole;
  final String recipientId;
  final String text;
  final DateTime? readAt;
  final DateTime? createdAt;

  const ChatMessage({
    required this.id,
    this.conversationId = '',
    this.orderId,
    this.senderRole = '',
    this.senderId = '',
    this.recipientRole = '',
    this.recipientId = '',
    required this.text,
    this.readAt,
    this.createdAt,
  });

  bool isMine(String myUserId) => senderId == myUserId;

  /// Sent by the customer — i.e. by this app's user. Every thread this app
  /// can open has the customer on one side, so this is "mine".
  bool get isFromUser => senderRole.toUpperCase() == 'USER';

  /// True when either side of the message is [role] (`DELIVERY_PARTNER`, `ADMIN`…).
  bool involves(String role) {
    final r = role.toUpperCase();
    return senderRole.toUpperCase() == r || recipientRole.toUpperCase() == r;
  }

  factory ChatMessage.fromApi(Map<String, dynamic> json) {
    final read = json['readAt']?.toString();
    final created = json['createdAt']?.toString();
    return ChatMessage(
      id: (json['id'] ?? json['_id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? '').toString(),
      orderId: json['orderId']?.toString(),
      senderRole: (json['senderRole'] ?? '').toString(),
      senderId: (json['senderId'] ?? '').toString(),
      recipientRole: (json['recipientRole'] ?? '').toString(),
      recipientId: (json['recipientId'] ?? '').toString(),
      text: (json['text'] ?? '').toString(),
      readAt: read == null ? null : DateTime.tryParse(read)?.toLocal(),
      createdAt: created == null ? null : DateTime.tryParse(created)?.toLocal(),
    );
  }
}
