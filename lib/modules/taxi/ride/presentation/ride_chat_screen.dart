import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/core/utils/taxi_formatters.dart';
import 'package:superapp_user/modules/taxi/ride/application/ride_tracking_controller.dart';
import 'package:superapp_user/modules/taxi/ride/data/models/ride_message_model.dart';

/// Rider <-> driver chat for one ride.
///
/// Carried over the ride's socket room: `ride:message:send { rideId, message }`
/// out, `ride:message:new` back to everyone in the room (sender included).
/// History is the ride document's last 30 messages, which the tracking
/// controller loads and polls; this screen only renders that state.
class RideChatScreen extends ConsumerStatefulWidget {
  final String rideId;
  const RideChatScreen({super.key, required this.rideId});

  @override
  ConsumerState<RideChatScreen> createState() => _RideChatScreenState();
}

class _RideChatScreenState extends ConsumerState<RideChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _didInitialScroll = false;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final controller = ref.read(rideTrackingControllerProvider(widget.rideId).notifier);
    if (controller.sendMessage(text)) {
      _messageController.clear();
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Message not sent. Please try again.'.tr)),
      );
    }
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

  void _markSeen(List<RideMessageModel> messages) {
    final fromDriver = messages.where((m) => !m.isFromRider).length;
    if (fromDriver <= ref.read(rideChatSeenProvider(widget.rideId))) return;
    // Not during build: updating another provider mid-build is not allowed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(rideChatSeenProvider(widget.rideId).notifier).markSeen(fromDriver);
    });
  }

  Future<void> _callDriver(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(day.year, day.month, day.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today'.tr;
    if (diff == 1) return 'Yesterday'.tr;
    return DateFormat('d MMM yyyy').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final tracking = ref.watch(rideTrackingControllerProvider(widget.rideId));
    final ride = tracking.ride;

    ref.listen(rideTrackingControllerProvider(widget.rideId), (prev, next) {
      final before = prev?.ride?.messages.length ?? 0;
      final after = next.ride?.messages.length ?? 0;
      if (after > before) _scrollToBottom();
      if (next.chatError != null && next.chatErrorSeq != (prev?.chatErrorSeq ?? 0)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.chatError!)));
      }
    });

    final driver = ride?.driver;
    final driverName = (driver?.name.isNotEmpty == true) ? driver!.name : 'Your driver'.tr;
    final vehicleNo = driver?.vehicleNumber ?? '';
    final vehicleType = (driver?.vehicleMake.isNotEmpty == true)
        ? driver!.vehicleMake
        : (ride?.vehicleType?.isNotEmpty == true ? ride!.vehicleType! : '');
    final vehicleLine = [vehicleNo, vehicleType].where((s) => s.isNotEmpty).join(' • ');
    final driverRating = (driver != null && driver.rating > 0) ? driver.rating.toStringAsFixed(1) : '';
    final driverPhone = driver?.phone ?? '';

    final messages = ride?.messages ?? const <RideMessageModel>[];
    if (messages.isNotEmpty) {
      _markSeen(messages);
      if (!_didInitialScroll) {
        _didInitialScroll = true;
        _scrollToBottom(animate: false);
      }
    }

    // Day separators between messages from different days.
    final children = <Widget>[];
    DateTime? lastDay;
    for (final m in messages) {
      final day = DateTime(m.sentAt.year, m.sentAt.month, m.sentAt.day);
      if (lastDay == null || day != lastDay) {
        if (lastDay != null) children.add(const SizedBox(height: 8));
        children.add(_dayChip(_dayLabel(day)));
        children.add(const SizedBox(height: 16));
        lastDay = day;
      }
      final timeStr = Formatters.time(m.sentAt);
      children.add(m.isFromRider
          ? _buildOutgoingBubble(m.message, timeStr, pending: m.pending)
          : _buildIncomingBubble(m.message, timeStr));
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.pop(),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          ),
        ),
        title: Text(
          'Chat with Driver'.tr,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (driverPhone.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: CircleAvatar(
                radius: 20,
                backgroundColor: const Color(0xFFF1F5F9),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _callDriver(driverPhone),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.call_outlined, color: Color(0xFF0F172A), size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // --- DRIVER INFO BANNER ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: (driver != null && driver.profileImage.isNotEmpty)
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: driver.profileImage,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) =>
                                const Icon(Icons.person, color: Color(0xFF0F172A), size: 24),
                          ),
                        )
                      : const Icon(Icons.person, color: Color(0xFF0F172A), size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (vehicleLine.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          vehicleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                      if (driverRating.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFB800)),
                            const SizedBox(width: 3),
                            Text(
                              driverRating,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.two_wheeler_rounded,
                  size: 40,
                  color: Color(0xFF0F172A),
                ),
              ],
            ),
          ),

          // --- CHAT MESSAGES CANVAS ---
          Expanded(
            child: ListView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              children: [
                if (tracking.isLoading && ride == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (messages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded, size: 36, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 10),
                        Text(
                          'No messages yet. Say hello to your driver.'.tr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  ...children,

                const SizedBox(height: 24),

                // --- SAFETY PRIORITY BANNER ---
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFFE9A8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE9A8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.verified_user_outlined,
                          size: 22,
                          color: Color(0xFF121212),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your safety is our priority'.tr,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Never share personal or payment details in chat.'.tr,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // --- BOTTOM MESSAGE INPUT BAR ---
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _messageController,
                        minLines: 1,
                        maxLines: 4,
                        // The ride stores at most 1000 characters per message.
                        maxLength: 1000,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.send,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Type a message...'.tr,
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF94A3B8),
                          ),
                          counterText: '',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFFFFB800),
                    shape: const CircleBorder(),
                    elevation: 2,
                    shadowColor: const Color(0x40FFB800),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: ride == null ? null : _send,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(
                          Icons.near_me_rounded,
                          color: Color(0xFF121212),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayChip(String label) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildIncomingBubble(String message, String timeStr) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              timeStr,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF94A3B8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOutgoingBubble(String message, String timeStr, {bool pending = false}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Opacity(
        opacity: pending ? 0.7 : 1,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
          decoration: const BoxDecoration(
            color: Color(0xFFFFB800),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(4),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x33FFB800),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF121212),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    pending ? Icons.schedule_rounded : Icons.done_all_rounded,
                    size: 14,
                    color: const Color(0xFF121212),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
