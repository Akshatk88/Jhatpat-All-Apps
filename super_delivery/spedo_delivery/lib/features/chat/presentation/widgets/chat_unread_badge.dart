import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../application/chat_unread_provider.dart';

/// Overlays the unread-customer-message count for [orderId] on [child]
/// (a chat button). Renders [child] alone when there is nothing unread.
class ChatUnreadBadge extends ConsumerWidget {
  const ChatUnreadBadge({super.key, required this.orderId, required this.child});

  final String orderId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(chatUnreadProvider.select((m) => m[orderId] ?? 0));
    if (count <= 0) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: IgnorePointer(
            child: Container(
              constraints: BoxConstraints(minWidth: 18.r, minHeight: 18.r),
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(9.r),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                count > 9 ? '9+' : '$count',
                style: TextStyle(color: Colors.white, fontSize: 10.sp, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
