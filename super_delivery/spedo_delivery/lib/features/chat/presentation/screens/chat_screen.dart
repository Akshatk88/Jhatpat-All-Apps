import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:food_user_application/core/error/result.dart';
import 'package:food_user_application/core/services/haptic_service.dart';
import 'package:food_user_application/core/services/socket_service.dart';
import 'package:food_user_application/features/chat/application/chat_unread_provider.dart';
import 'package:food_user_application/features/chat/data/chat_repository.dart';
import 'package:food_user_application/features/chat/data/models/chat_message.dart';
import 'package:food_user_application/features/orders/data/models/delivery_order.dart';

/// Rider <-> customer chat for one food order.
///
/// Backend (`/food/chat`): the thread id is the order's Mongo id itself;
/// `POST /messages { orderId, text }` resolves the customer from the order;
/// `GET /messages?conversationId=` returns history oldest-first and marks
/// incoming as read; new messages arrive as `chat:message` on this partner's
/// `delivery:<id>` room (auto-joined on connect), the sender's own included.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.order});

  final DeliveryOrder order;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  String? _conversationId;
  bool _loading = true;
  bool _sending = false;
  bool _peerTyping = false;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _messageSub;
  StreamSubscription<Map<String, dynamic>>? _typingSub;
  StreamSubscription<bool>? _connectionSub;
  Timer? _typingResetTimer;
  late final ChatUnreadNotifier _unread;

  String get _orderId => widget.order.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _unread = ref.read(chatUnreadProvider.notifier);
    if (_orderId.isNotEmpty) _unread.opened(_orderId);
    _load();
    final socket = ref.read(socketServiceProvider);
    _messageSub = socket.onChatMessage.listen(_onSocketMessage);
    _typingSub = socket.onChatTyping.listen(_onSocketTyping);
    // Messages sent while the socket was down never arrive; re-read on reconnect.
    _connectionSub = socket.onConnectionChange.listen((connected) {
      if (connected) _sync();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(socketServiceProvider).ensureConnected();
      _sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_orderId.isNotEmpty) _unread.closed(_orderId);
    _messageSub?.cancel();
    _typingSub?.cancel();
    _connectionSub?.cancel();
    _typingResetTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_orderId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Chat is unavailable for this order.';
      });
      return;
    }
    final repo = ref.read(chatRepositoryProvider);
    final conversationsResult = await repo.getConversations();
    String? conversationId;
    conversationsResult.when(
      success: (conversations) {
        for (final c in conversations) {
          if (c.orderId == _orderId && c.peerRole.toUpperCase() == 'USER') {
            conversationId = c.conversationId;
            break;
          }
        }
      },
      failure: (_) {},
    );
    // The customer <-> rider thread is keyed on the order id itself, so
    // history can be read even if the listing failed or is empty.
    conversationId ??= _orderId;
    _conversationId = conversationId;

    final historyResult = await repo.getMessages(conversationId: conversationId!, limit: 100);
    if (!mounted) return;
    historyResult.when(
      success: (page) => setState(() {
        _mergeAll(page.messages);
        _loading = false;
      }),
      failure: (error) => setState(() {
        _error = error.message;
        _loading = false;
      }),
    );
    _scrollToBottom(animate: false);
  }

  /// Re-reads the latest page and merges anything missed.
  Future<void> _sync() async {
    final convId = _conversationId;
    if (convId == null || _loading || !mounted) return;
    final result = await ref.read(chatRepositoryProvider).getMessages(conversationId: convId, limit: 50);
    if (!mounted) return;
    result.when(
      success: (page) {
        final before = _messages.length;
        setState(() => _mergeAll(page.messages));
        if (_messages.length != before) _scrollToBottom();
      },
      failure: (_) {},
    );
  }

  /// Adds messages not already shown (by id), keeping time order.
  void _mergeAll(Iterable<ChatMessage> incoming) {
    final known = _messages.map((m) => m.id).toSet();
    for (final m in incoming) {
      if (m.id.isEmpty || !known.contains(m.id)) {
        _messages.add(m);
        known.add(m.id);
      }
    }
    _messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Only the customer thread of this order — not a support thread with admin
  /// about the same order.
  bool _isForThisThread(ChatMessage message) {
    if (message.orderId != _orderId) return false;
    final convId = _conversationId;
    if (convId != null && message.conversationId.isNotEmpty) {
      return message.conversationId == convId;
    }
    return message.senderRole.toUpperCase() == 'USER' ||
        message.recipientRole.toUpperCase() == 'USER';
  }

  void _onSocketMessage(Map<String, dynamic> data) {
    final message = ChatMessage.fromJson(data);
    if (!_isForThisThread(message)) return;
    if (_messages.any((m) => m.id == message.id)) return;
    setState(() {
      _conversationId ??= message.conversationId;
      _mergeAll([message]);
      if (!message.isFromDeliveryPartner) _peerTyping = false;
    });
    _scrollToBottom();
    // Seen on screen: clear the server-side unread too.
    final convId = _conversationId;
    if (!message.isFromDeliveryPartner && convId != null) {
      unawaited(ref.read(chatRepositoryProvider).markRead(convId));
    }
  }

  void _onSocketTyping(Map<String, dynamic> data) {
    if (_conversationId == null || data['conversationId'] != _conversationId) return;
    if (data['fromRole'] != 'USER') return;
    setState(() => _peerTyping = data['typing'] as bool? ?? false);
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  void _emitTyping(bool typing) {
    if (widget.order.customerId == null) return;
    ref.read(socketServiceProvider).sendChatTyping(
          toRole: 'USER',
          toId: widget.order.customerId,
          conversationId: _conversationId ?? '',
          typing: typing,
        );
  }

  void _onTextChanged(String value) {
    _typingResetTimer?.cancel();
    _emitTyping(value.isNotEmpty);
    if (value.isNotEmpty) {
      _typingResetTimer = Timer(const Duration(seconds: 2), () => _emitTyping(false));
    }
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _sending || _orderId.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    _textController.clear();
    _typingResetTimer?.cancel();
    _emitTyping(false);

    // With an orderId the server resolves the customer from the order; peerId
    // is ignored, so it is not sent.
    final result = await ref.read(chatRepositoryProvider).sendMessage(
          peerRole: 'USER',
          orderId: _orderId,
          text: text,
        );
    if (!mounted) return;
    result.when(
      success: (message) {
        setState(() {
          _conversationId ??= message.conversationId;
          // The socket echo can beat the HTTP response — merge, don't append.
          _mergeAll([message]);
          _sending = false;
        });
        _scrollToBottom();
      },
      failure: (error) => setState(() {
        _error = error.message;
        _sending = false;
        // Give the text back so it can be retried without retyping.
        if (_textController.text.isEmpty) _textController.text = text;
      }),
    );
  }

  String _stamp(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final time = '$h:${local.minute.toString().padLeft(2, '0')} ${local.hour < 12 ? 'AM' : 'PM'}';
    final sameDay = local.year == now.year && local.month == now.month && local.day == now.day;
    if (sameDay) return time;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${local.day} ${months[local.month - 1]}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final bgColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E1E1E);

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0.5,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            HapticService.light();
            Navigator.of(context).pop();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.order.customerName.isNotEmpty ? widget.order.customerName : 'Customer',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.sp, color: textColor),
            ),
            if (_peerTyping)
              Text('typing…', style: TextStyle(fontSize: 11.sp, color: theme.primaryColor))
            else
              Text(
                'Order #${widget.order.orderCode}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.sp, color: Colors.grey[500]),
              ),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            children: [
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 24.w),
                              child: Text(
                                'No messages yet. Say hello!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[500], fontSize: 13.sp),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) =>
                                _buildBubble(theme, isDarkMode, _messages[index]),
                          ),
              ),
              if (_error != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                  child: Text(
                    _error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          onChanged: _onTextChanged,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          textCapitalization: TextCapitalization.sentences,
                          buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                              null,
                          decoration: InputDecoration(
                            hintText: 'Type a message…',
                            filled: true,
                            fillColor: isDarkMode ? Colors.white10 : Colors.white,
                            contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                            // Every state set explicitly: with only `border`,
                            // Material 3 draws its own outline on enabled/focus.
                            border: _inputBorder(isDarkMode ? Colors.white24 : const Color(0xFFE2E8F0)),
                            enabledBorder: _inputBorder(isDarkMode ? Colors.white24 : const Color(0xFFE2E8F0)),
                            focusedBorder: _inputBorder(theme.primaryColor, width: 1.4),
                            disabledBorder: _inputBorder(isDarkMode ? Colors.white12 : const Color(0xFFF1F5F9)),
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      GestureDetector(
                        onTap: _send,
                        child: Container(
                          width: 44.r,
                          height: 44.r,
                          decoration: BoxDecoration(color: theme.primaryColor, shape: BoxShape.circle),
                          child: _sending
                              ? Padding(
                                  padding: EdgeInsets.all(12.r),
                                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.send_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(ThemeData theme, bool isDarkMode, ChatMessage message) {
    final isMine = message.isFromDeliveryPartner;
    final bubbleColor = isMine ? theme.primaryColor : (isDarkMode ? Colors.white10 : Colors.white);
    final textColor = isMine ? Colors.white : (isDarkMode ? Colors.white : Colors.black87);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: 8.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        constraints: BoxConstraints(maxWidth: 0.75.sw),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16.r),
            topRight: Radius.circular(16.r),
            bottomLeft: Radius.circular(isMine ? 16.r : 4.r),
            bottomRight: Radius.circular(isMine ? 4.r : 16.r),
          ),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message.text, style: TextStyle(color: textColor, fontSize: 14.sp)),
            SizedBox(height: 3.h),
            Text(
              _stamp(message.createdAt),
              style: TextStyle(
                color: isMine ? Colors.white70 : Colors.grey,
                fontSize: 10.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(24.r),
      borderSide: BorderSide(color: color, width: width),
    );
