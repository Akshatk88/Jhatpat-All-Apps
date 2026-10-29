import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../../../core/services/socket_service.dart';
import '../data/chat_repository.dart';

/// Unread customer messages per order id, for the badge on the chat buttons.
///
/// Seeded from `GET /food/chat/conversations` (server-side unread counts) and
/// bumped live by `chat:message` pushes from the customer. The open chat
/// screen registers its order through [opened]/[closed] so messages read
/// on screen never count.
class ChatUnreadNotifier extends Notifier<Map<String, int>> {
  StreamSubscription<Map<String, dynamic>>? _sub;
  String? _openOrderId;

  @override
  Map<String, int> build() {
    _sub = ref.read(socketServiceProvider).onChatMessage.listen(_onMessage);
    ref.onDispose(() => _sub?.cancel());
    unawaited(Future.microtask(refresh));
    return const {};
  }

  void _onMessage(Map<String, dynamic> data) {
    if ((data['senderRole'] ?? '').toString().toUpperCase() != 'USER') return;
    final orderId = data['orderId']?.toString();
    if (orderId == null || orderId.isEmpty || orderId == _openOrderId) return;
    state = {...state, orderId: (state[orderId] ?? 0) + 1};
  }

  /// Re-reads the server's unread counts.
  Future<void> refresh() async {
    final result = await ref.read(chatRepositoryProvider).getConversations();
    result.when(
      success: (conversations) {
        final next = <String, int>{};
        for (final c in conversations) {
          final orderId = c.orderId;
          if (orderId == null || orderId.isEmpty) continue;
          if (c.peerRole.toUpperCase() != 'USER') continue;
          if (orderId == _openOrderId) continue;
          next[orderId] = (next[orderId] ?? 0) + c.unread;
        }
        state = next;
      },
      failure: (_) {},
    );
  }

  void opened(String orderId) {
    _openOrderId = orderId;
    if ((state[orderId] ?? 0) == 0) return;
    state = {...state}..remove(orderId);
  }

  void closed(String orderId) {
    if (_openOrderId == orderId) _openOrderId = null;
  }
}

final chatUnreadProvider =
    NotifierProvider<ChatUnreadNotifier, Map<String, int>>(ChatUnreadNotifier.new);
