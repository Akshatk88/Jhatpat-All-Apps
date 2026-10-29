import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/modules/food/application/providers/socket_providers.dart';
import 'package:superapp_user/modules/food/data/models/chat_model.dart';
import 'package:superapp_user/shared/support/application/chat_providers.dart';

/// Chat threads for one order (rider chat + support threads), with unread
/// counts.
///
/// Family-keyed by order id so each Order Details screen holds its own list and
/// two orders open in a back stack cannot overwrite each other's state.
///
/// Re-fetches itself when a `chat:message` for this order arrives, so unread
/// badges appear live; the chat screen invalidates it after reading.
///
/// Returns an empty list rather than an error when the fetch fails: this is a
/// supplementary section, and a support outage should not put an error box on an
/// otherwise healthy order screen. The section simply stays hidden.
final orderConversationsProvider =
    FutureProvider.family<List<ChatConversation>, String>((ref, orderId) async {
  if (orderId.isEmpty) return const [];

  final sub = ref.read(socketServiceProvider).chatMessages.listen((msg) {
    if (msg.data['orderId']?.toString() == orderId) ref.invalidateSelf();
  });
  ref.onDispose(sub.cancel);

  try {
    return await ref
        .read(chatRemoteDataSourceProvider)
        .getConversations(orderId: orderId);
  } catch (_) {
    return const [];
  }
});

/// Unread messages from the delivery partner on [orderId], for the chat button.
int riderUnreadCount(List<ChatConversation> conversations) => conversations
    .where((c) => c.peerRole.toUpperCase() == 'DELIVERY_PARTNER')
    .fold<int>(0, (sum, c) => sum + c.unread);
