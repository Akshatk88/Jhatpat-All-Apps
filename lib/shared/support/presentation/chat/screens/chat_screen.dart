import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/components/feedback/app_snackbar.dart';
import 'package:superapp_user/design_system/components/skeletons/skeleton_loading.dart';
import 'package:superapp_user/modules/food/data/models/chat_model.dart';
import 'package:superapp_user/shared/support/presentation/chat/viewmodels/chat_viewmodel.dart';

/// Everything the chat screen needs to identify the thread and label the
/// app bar — passed via `go_router`'s `extra` (no path params needed).
class ChatArgs {
  final String orderId;
  final String? peerId;
  final String peerName;
  final String peerRole;

  /// Set when opening a known thread (e.g. from an order's thread list) so the
  /// exact conversation loads instead of being looked up by order + peer.
  final String? conversationId;

  const ChatArgs({
    required this.orderId,
    this.peerId,
    required this.peerName,
    this.peerRole = 'DELIVERY_PARTNER',
    this.conversationId,
  });
}

class ChatScreen extends ConsumerStatefulWidget {
  final ChatArgs args;
  const ChatScreen({super.key, required this.args});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showNewMessagesIndicator = false;

  ChatTarget get _target => (
        peerRole: widget.args.peerRole,
        peerId: widget.args.peerId,
        orderId: widget.args.orderId,
        conversationId: widget.args.conversationId,
      );

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    return maxScroll - currentScroll <= 120.0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    if (_isNearBottom && _showNewMessagesIndicator) {
      setState(() {
        _showNewMessagesIndicator = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(chatViewModelProvider(_target).notifier).resumeChat();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    // Checked inside the callback: on first load the list does not exist yet
    // (the skeleton is showing) and only attaches on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _onNewMessagesTap() {
    _scrollToBottom();
    setState(() {
      _showNewMessagesIndicator = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    if (ref.read(chatViewModelProvider(_target)).isSending) return;
    _controller.clear();
    Haptics.light();
    final error = await ref.read(chatViewModelProvider(_target).notifier).sendMessage(text);
    if (!mounted) return;
    if (error != null) {
      // Give the text back so the user can retry without retyping it.
      if (_controller.text.isEmpty) _controller.text = text;
      AppSnackbar.error(context, error);
    } else {
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : AppColors.textPrimaryLight;
    final secondary = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;
    final myId = ref.watch(currentUserIdProvider) ?? '';
    final state = ref.watch(chatViewModelProvider(_target));

    ref.listen(chatViewModelProvider(_target), (previous, next) {
      if (previous == null || next.messages.length == previous.messages.length) return;

      final isLastMessageMine = next.messages.isNotEmpty && _isMine(next.messages.last, myId);

      // First page of history: always land on the newest message.
      if (previous.messages.isEmpty || isLastMessageMine || _isNearBottom) {
        _scrollToBottom();
        setState(() {
          _showNewMessagesIndicator = false;
        });
      } else {
        setState(() {
          _showNewMessagesIndicator = true;
        });
      }
    });

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.surfaceDark : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: textColor),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.args.peerName, maxLines: 1, overflow: TextOverflow.ellipsis, style:TextStyle(color: textColor, fontSize: 16, fontWeight: FontWeight.w600)),
            if (state.peerTyping)
              Text('typing…'.tr, style: TextStyle(color: const Color(0xFFE5A600), fontSize: 11.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(child: _buildBody(state, myId, isDark, textColor, secondary)),
                _buildComposer(isDark, textColor, state.isSending),
              ],
            ),
            if (_showNewMessagesIndicator)
              Positioned(
                bottom: 80,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _onNewMessagesTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.arrow_downward_rounded, color: Colors.black, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'New Messages'.tr,
                            style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ChatState state, String myId, bool isDark, Color textColor, Color secondary) {
    if (state.isLoading) {
      return const SkeletonChatList();
    }
    if (state.error != null && state.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: secondary),
            const SizedBox(height: 12),
            Text(state.error!, style: TextStyle(color: secondary), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref.read(chatViewModelProvider(_target).notifier).retry(),
              child: Text('Retry'.tr),
            ),
          ],
        ),
      );
    }
    if (state.messages.isEmpty) {
      return Center(
        child: Text('Say hello 👋'.tr, style: TextStyle(color: secondary, fontSize: 14)),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(16),
      itemCount: state.messages.length,
      itemBuilder: (context, index) {
        final message = state.messages[index];
        final mine = _isMine(message, myId);
        final sentAt = message.createdAt;
        return Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            decoration: BoxDecoration(
              color: mine ? AppColors.primary : (isDark ? AppColors.cardDark : Colors.white),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(mine ? 16 : 4),
                bottomRight: Radius.circular(mine ? 4 : 16),
              ),
              boxShadow: mine || isDark ? null : [BoxShadow(color: AppColors.shadow1, blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.text,
                  style: TextStyle(color: mine ? Colors.black : textColor, fontSize: 14),
                ),
                if (sentAt != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    _stamp(sentAt),
                    style: TextStyle(
                      color: mine ? Colors.black54 : secondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Every thread this app opens has the customer on one side, so the
  /// customer's messages are "mine". The id check covers a missing role.
  bool _isMine(ChatMessage message, String myId) =>
      message.isFromUser || (myId.isNotEmpty && message.senderId == myId);

  /// `h:mm a` today, otherwise prefixed with the date.
  String _stamp(DateTime at) {
    final now = DateTime.now();
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    return sameDay ? DateFormat('h:mm a').format(at) : DateFormat('d MMM, h:mm a').format(at);
  }

  Widget _buildComposer(bool isDark, Color textColor, bool isSending) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(top: BorderSide(color: isDark ? AppColors.borderDark : AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: TextStyle(color: textColor),
              minLines: 1,
              maxLines: 4,
              // The server rejects anything over 2000 characters.
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.send,
              onChanged: (_) => ref.read(chatViewModelProvider(_target).notifier).notifyTyping(),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Message...'.tr,
                counterText: '',
                filled: true,
                fillColor: isDark ? AppColors.cardDark : AppColors.secondarySurfaceLight,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: isSending ? null : _send,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: isSending
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.black, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
