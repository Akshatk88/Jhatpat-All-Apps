import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/modules/food/data/models/chat_model.dart';
import 'package:superapp_user/modules/food/presentation/orders/viewmodels/order_conversations_viewmodel.dart';
import 'package:superapp_user/shared/support/application/chat_providers.dart';
import 'package:superapp_user/core/error/failures.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/push/push_providers.dart';
import 'package:superapp_user/modules/food/application/providers/socket_providers.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';

/// Identifies one chat thread.
///
/// Backend contract (`/food/chat`):
/// * customer <-> rider on an order: `conversationId` is the order's Mongo id
///   itself, and sending needs only `{ orderId, text }` (peer resolved from
///   the order's assigned rider);
/// * support (`peerRole: ADMIN`): `{ peerRole: 'ADMIN', orderId?, text }`,
///   threads keyed `<orderId|direct>::ADMIN|USER:<id>`.
///
/// [conversationId] is set when opening a known thread from a list.
typedef ChatTarget = ({String peerRole, String? peerId, String? orderId, String? conversationId});

class ChatState {
  final List<ChatMessage> messages;
  final String? conversationId;
  final bool isLoading;
  final bool isSending;
  final String? error;
  final bool peerTyping;

  const ChatState({
    this.messages = const [],
    this.conversationId,
    this.isLoading = true,
    this.isSending = false,
    this.error,
    this.peerTyping = false,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    String? conversationId,
    bool? isLoading,
    bool? isSending,
    String? error,
    bool? peerTyping,
    bool clearError = false,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      conversationId: conversationId ?? this.conversationId,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      error: clearError ? null : (error ?? this.error),
      peerTyping: peerTyping ?? this.peerTyping,
    );
  }
}

final chatViewModelProvider =
    NotifierProvider.family<ChatViewModel, ChatState, ChatTarget>(ChatViewModel.new);

class ChatViewModel extends Notifier<ChatState> {
  final ChatTarget arg;
  ChatViewModel(this.arg);

  StreamSubscription? _messageSub;
  StreamSubscription? _pushSub;
  StreamSubscription? _typingSub;
  StreamSubscription? _connectedSub;
  Timer? _typingResetTimer;
  bool _disposed = false;

  /// Order id, with the empty string the support route passes treated as none.
  String? get _orderId {
    final id = arg.orderId?.trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  String get _peerRole => arg.peerRole.toUpperCase();

  bool get _isRiderThread => _peerRole == 'DELIVERY_PARTNER';

  @override
  ChatState build() {
    ref.onDispose(() {
      _disposed = true;
      _messageSub?.cancel();
      _pushSub?.cancel();
      _typingSub?.cancel();
      _connectedSub?.cancel();
      _typingResetTimer?.cancel();
    });
    _listenSocket();
    _listenPush();
    unawaited(Future.microtask(_init));
    return const ChatState();
  }

  void _listenPush() {
    final pushService = ref.read(pushServiceProvider);
    // The push only carries {type, conversationId, orderId} and a preview —
    // no message id — so building a bubble from it would duplicate the socket
    // copy. Treat it as a nudge to re-sync instead (covers a dead socket).
    _pushSub = pushService.onForeground.listen((msg) {
      final data = msg.data;
      if (data['type']?.toString() != 'chat_message') return;
      final convId = state.conversationId;
      final matches = (convId != null && data['conversationId']?.toString() == convId) ||
          (_orderId != null && data['orderId']?.toString() == _orderId);
      if (matches) unawaited(resumeChat());
    });
  }

  void _listenSocket() {
    final service = ref.read(socketServiceProvider);
    _messageSub = service.chatMessages.listen((msg) {
      final data = msg.data;
      if (!_isForThisThread(data)) return;
      final message = ChatMessage.fromApi(data);
      final added = _merge([message]);
      if (!added) return;
      if (state.conversationId == null && message.conversationId.isNotEmpty) {
        state = state.copyWith(conversationId: message.conversationId);
      }
      if (!message.isFromUser) _markRead();
    });
    _typingSub = service.chatTyping.listen((msg) {
      if (!_isForThisThread(msg.data)) return;
      final typing = msg.data['typing'] as bool? ?? false;
      state = state.copyWith(peerTyping: typing);
    });
    // Anything sent while the socket was down never arrives; re-read.
    _connectedSub = service.onConnected.listen((_) => unawaited(resumeChat()));
  }

  bool _isForThisThread(Map<String, dynamic> data) {
    final convId = state.conversationId;
    final msgConv = data['conversationId']?.toString();
    if (convId != null && msgConv != null && msgConv.isNotEmpty) return msgConv == convId;

    // Thread not known yet (nothing exchanged): same order and same peer kind.
    final msgOrder = data['orderId']?.toString();
    final sameOrder = _orderId == null
        ? (msgOrder == null || msgOrder.isEmpty)
        : msgOrder == _orderId;
    if (!sameOrder) return false;
    final roles = {
      data['senderRole']?.toString().toUpperCase(),
      data['recipientRole']?.toString().toUpperCase(),
    };
    return roles.contains(_peerRole);
  }

  /// Adds [incoming] not already present (by id), keeping time order.
  /// Returns whether anything was added.
  bool _merge(List<ChatMessage> incoming) {
    final existing = state.messages.map((m) => m.id).where((id) => id.isNotEmpty).toSet();
    final fresh = incoming.where((m) => m.id.isEmpty || !existing.contains(m.id)).toList();
    if (fresh.isEmpty) return false;
    final all = [...state.messages, ...fresh]
      ..sort((a, b) => (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now()));
    state = state.copyWith(messages: all);
    return true;
  }

  void _markRead() {
    final convId = state.conversationId;
    if (convId == null || convId.isEmpty) return;
    unawaited(() async {
      try {
        await ref.read(chatRemoteDataSourceProvider).markRead(convId);
        if (_disposed) return;
        final orderId = _orderId;
        if (orderId != null) ref.invalidate(orderConversationsProvider(orderId));
      } catch (_) {
        // Read receipts are best effort.
      }
    }());
  }

  /// Works out which thread this is, then loads its history.
  Future<String?> _resolveConversationId() async {
    final explicit = arg.conversationId;
    if (explicit != null && explicit.isNotEmpty) return explicit;

    // Match on order AND peer kind: an order can also have a support thread,
    // which must not be mistaken for the rider chat (or vice versa).
    List<ChatConversation> conversations = const [];
    try {
      conversations =
          await ref.read(chatRemoteDataSourceProvider).getConversations(orderId: _orderId);
    } catch (_) {
      if (!(_isRiderThread && _orderId != null)) rethrow;
    }
    final match = conversations.where((c) {
      if (c.peerRole.toUpperCase() != _peerRole) return false;
      final cOrder = (c.orderId ?? '').isEmpty ? null : c.orderId;
      return cOrder == _orderId;
    });
    if (match.isNotEmpty) return match.first.conversationId;

    // The customer <-> rider thread is keyed on the order id itself, so even
    // before the first message we know where it will live.
    if (_isRiderThread && _orderId != null) return _orderId;
    return null;
  }

  Future<void> _init() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final conversationId = await _resolveConversationId();
      if (_disposed) return;
      if (conversationId == null) {
        // Nothing exchanged yet — the first send establishes the thread.
        state = state.copyWith(isLoading: false, messages: const []);
        return;
      }
      final result = await ref
          .read(chatRemoteDataSourceProvider)
          .getMessages(conversationId: conversationId, limit: 100);
      if (_disposed) return;
      // Keep anything the socket delivered while this was in flight.
      final byId = {for (final m in state.messages) m.id: m, for (final m in result.messages) m.id: m};
      final all = byId.values.toList()
        ..sort((a, b) => (a.createdAt ?? DateTime.now()).compareTo(b.createdAt ?? DateTime.now()));
      state = state.copyWith(isLoading: false, messages: all, conversationId: conversationId);
      // getMessages already marks incoming as read server-side; refresh the
      // badge on the order screen.
      final orderId = _orderId;
      if (orderId != null) ref.invalidate(orderConversationsProvider(orderId));
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(isLoading: false, error: 'Could not load messages. Pull down to retry.'.tr);
    }
  }

  /// Re-syncs after the app resumes, the socket reconnects or a push lands.
  Future<void> resumeChat() async {
    ref.read(socketServiceProvider).ensureConnected();

    final convId = state.conversationId;
    if (convId == null || convId.isEmpty) {
      if (!state.isLoading) await _init();
      return;
    }
    try {
      final result = await ref.read(chatRemoteDataSourceProvider).getMessages(
            conversationId: convId,
            page: 1,
            limit: 50,
          );
      if (_disposed) return;
      _merge(result.messages);
      final orderId = _orderId;
      if (orderId != null) ref.invalidate(orderConversationsProvider(orderId));
    } catch (_) {
      // Keep existing state if offline
    }
  }

  Future<void> retry() => _init();

  Future<String?> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.length > 2000) return 'Message is too long.'.tr;
    state = state.copyWith(isSending: true, clearError: true);
    try {
      final message = await ref.read(chatRemoteDataSourceProvider).sendMessage(
            peerRole: _peerRole,
            // Order chats resolve the peer from the order server-side; a peer
            // id is only meaningful outside an order.
            peerId: _orderId == null ? arg.peerId : null,
            orderId: _orderId,
            text: trimmed,
          );
      if (_disposed) return null;
      // The socket echo can beat the HTTP response — merge, don't append.
      _merge([message]);
      state = state.copyWith(
        conversationId: state.conversationId ??
            (message.conversationId.isEmpty ? null : message.conversationId),
        isSending: false,
      );
      return null;
    } catch (e) {
      if (_disposed) return null;
      state = state.copyWith(isSending: false);
      final reason = e.toString();
      // Surface the server's reason when it is one the user can act on.
      if (reason.contains('No delivery partner is assigned')) {
        return 'A delivery partner has not been assigned yet.'.tr;
      }
      if (e is ValidationFailure) return e.message;
      return 'Could not send. Check your connection and try again.'.tr;
    }
  }

  /// Debounced typing signal — call on every keystroke; auto-clears after 3s
  /// of inactivity so a forgotten field doesn't show "typing" forever.
  void notifyTyping() {
    final convId = state.conversationId;
    if (convId == null) return;
    ref.read(socketServiceProvider).emitChatTyping(
          toRole: arg.peerRole,
          toId: arg.peerId,
          conversationId: convId,
          typing: true,
        );
    _typingResetTimer?.cancel();
    _typingResetTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed) return;
      ref.read(socketServiceProvider).emitChatTyping(
            toRole: arg.peerRole,
            toId: arg.peerId,
            conversationId: convId,
            typing: false,
          );
    });
  }
}

/// The signed-in user's id, so message bubbles can tell "mine" from "theirs".
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(authViewModelProvider).value?.id;
});
