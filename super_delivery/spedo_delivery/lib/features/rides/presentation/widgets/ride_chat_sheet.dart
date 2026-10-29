import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/core/services/socket_service.dart';
import 'package:food_user_application/features/rides/application/active_ride_controller.dart';
import 'package:food_user_application/features/rides/data/models/taxi_ride.dart';

const _rideBlue = Color(0xFF1B6FF3);

/// In-ride chat with the passenger.
///
/// k9 carries it over the ride room: `ride:message:send { rideId, message }`
/// out, `ride:message:new` back to everyone in the room (sender included).
/// The ride document keeps the last 30 messages, which seed the list.
/// Failures come back only as the socket-wide `errorMessage`.
Future<void> showRideChatSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: const _RideChatSheet(),
    ),
  );
}

/// Quick replies a driver can send without typing at the wheel.
const _quickReplies = <String>[
  'I am on the way',
  'I have arrived',
  'Please come to the pickup point',
  'Stuck in traffic, 5 minutes',
];

class _RideChatSheet extends ConsumerStatefulWidget {
  const _RideChatSheet();

  @override
  ConsumerState<_RideChatSheet> createState() => _RideChatSheetState();
}

class _RideChatSheetState extends ConsumerState<_RideChatSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Sent but not yet echoed back by the server, oldest first.
  final List<String> _pending = [];
  Timer? _pendingTimer;
  StreamSubscription<Map<String, dynamic>>? _errorSub;

  @override
  void initState() {
    super.initState();
    // Pick up anything sent before this driver joined the room.
    ref.read(activeRideControllerProvider.notifier).reload();
    _errorSub = ref.read(socketServiceProvider).onSocketError.listen((data) {
      // The server reports every failed socket call on this one event; while
      // a send is unconfirmed, treat it as that send failing.
      if (_pending.isEmpty || !mounted) return;
      _failPending(data['message']?.toString());
    });
    _scrollToBottom(animate: false);
  }

  @override
  void dispose() {
    _pendingTimer?.cancel();
    _errorSub?.cancel();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shown inline above the input — a SnackBar would sit under the sheet.
  String? _error;

  void _failPending([String? reason]) {
    _pendingTimer?.cancel();
    setState(() {
      // Give the last unsent text back if the field is free.
      if (_controller.text.isEmpty && _pending.isNotEmpty) _controller.text = _pending.last;
      _pending.clear();
      _error = reason == null || reason.isEmpty
          ? 'Message not sent. Please try again.'
          : 'Message not sent: $reason';
    });
  }

  void _send(TaxiRide ride, String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    final sent = ref.read(socketServiceProvider).sendRideMessage(ride.id, message);
    if (!sent) {
      setState(() => _error = 'Not connected. Please try again.');
      return;
    }
    _controller.clear();
    setState(() {
      _error = null;
      _pending.add(message);
    });
    _scrollToBottom();
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 20), () {
      if (mounted && _pending.isNotEmpty) _failPending();
    });
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (animate) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scroll.jumpTo(target);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF1E1E1E);
    final ride = ref.watch(activeRideControllerProvider).value;
    final messages = ride?.messages ?? const <RideChatMessage>[];

    ref.listen(activeRideControllerProvider, (prev, next) {
      final before = prev?.value?.messages ?? const <RideChatMessage>[];
      final after = next.value?.messages ?? const <RideChatMessage>[];
      if (after.length <= before.length) return;
      // Our own echo settles the matching pending bubble.
      final known = before.map((m) => m.id).toSet();
      final mineArrived = after.where((m) => m.isMine && !known.contains(m.id));
      if (_pending.isNotEmpty && mineArrived.isNotEmpty) {
        setState(() {
          for (final m in mineArrived) {
            _pending.remove(m.message);
          }
        });
        if (_pending.isEmpty) _pendingTimer?.cancel();
      }
      _scrollToBottom();
    });

    // The sheet sits above the keyboard (see showRideChatSheet), so its height
    // budget is what is left of the screen once the keyboard is up.
    final media = MediaQuery.of(context);
    final available = media.size.height - media.viewInsets.bottom - media.padding.top - 16;
    final maxHeight = (media.size.height * 0.75)
        .clamp(160.0, available < 160 ? 160.0 : available)
        .toDouble();

    final itemCount = messages.length + _pending.length;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 16.h, 8.w, 4.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      ride == null ? 'Chat' : 'Chat with ${ride.passenger.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 17.sp,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: textColor),
                  ),
                ],
              ),
            ),
            Flexible(
              child: itemCount == 0
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 28.h),
                      child: Text(
                        'No messages yet',
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13.sp,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      shrinkWrap: true,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      itemCount: itemCount,
                      itemBuilder: (_, i) => i < messages.length
                          ? _Bubble(message: messages[i], isDark: isDark)
                          : _Bubble(
                              message: RideChatMessage(
                                id: '',
                                senderRole: 'driver',
                                message: _pending[i - messages.length],
                              ),
                              isDark: isDark,
                              pending: true,
                            ),
                    ),
            ),
            SizedBox(
              height: 40.h,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                itemCount: _quickReplies.length,
                separatorBuilder: (_, _) => SizedBox(width: 8.w),
                itemBuilder: (_, i) => ActionChip(
                  label: Text(_quickReplies[i], style: TextStyle(fontSize: 12.sp)),
                  onPressed: ride == null ? null : () => _send(ride, _quickReplies[i]),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 0),
                child: Text(
                  _error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.redAccent, fontSize: 12.sp),
                ),
              ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 8.h, 8.w, 12.h),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      textInputAction: TextInputAction.send,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: ride == null ? null : (t) => _send(ride, t),
                      maxLength: 1000,
                      style: TextStyle(color: textColor, fontSize: 14.sp),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Type a message',
                        filled: true,
                        fillColor:
                            isDark ? const Color(0xFF20242E) : const Color(0xFFF2F4F7),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        // Every state set explicitly: with only `border`,
                        // Material 3 draws its own outline on enabled/focus.
                        border: _inputBorder(isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
                        enabledBorder: _inputBorder(isDark ? Colors.white24 : const Color(0xFFE2E8F0)),
                        focusedBorder: _inputBorder(_rideBlue, width: 1.4),
                        disabledBorder: _inputBorder(isDark ? Colors.white12 : const Color(0xFFF1F5F9)),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: ride == null ? null : () => _send(ride, _controller.text),
                    icon: const Icon(Icons.send_rounded, color: _rideBlue),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.isDark, this.pending = false});

  final RideChatMessage message;
  final bool isDark;

  /// Sent, not yet confirmed by the server.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final time = message.sentAt;
    final metaColor = mine ? Colors.white70 : Colors.grey;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(
        opacity: pending ? 0.7 : 1,
        child: Container(
          margin: EdgeInsets.symmetric(vertical: 3.h),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          constraints: BoxConstraints(maxWidth: 0.72.sw),
          decoration: BoxDecoration(
            color: mine
                ? _rideBlue
                : (isDark ? const Color(0xFF262B36) : const Color(0xFFF0F2F5)),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Column(
            crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message.message,
                style: TextStyle(
                  color: mine ? Colors.white : (isDark ? Colors.white : Colors.black87),
                  fontSize: 14.sp,
                ),
              ),
              if (pending)
                Icon(Icons.schedule_rounded, size: 12.sp, color: metaColor)
              else if (time != null)
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(color: metaColor, fontSize: 10.sp),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

OutlineInputBorder _inputBorder(Color color, {double width = 1}) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(24.r),
      borderSide: BorderSide(color: color, width: width),
    );
