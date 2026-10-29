import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:food_user_application/config/theme/app_colors.dart';

/// The new-order request screen's visuals, with no state management of its
/// own: plain data in, callbacks out.
///
/// Shared by the in-app request screen (`IncomingOrderRequestScreen`) and the
/// over-other-apps overlay (`OrderOverlayApp`), which runs in its own engine
/// with no Riverpod — so both draw exactly the same card.

const _accentYellow = Color(0xFFFFC107);
const _okGreen = Color(0xFF1E9E5A);
const _alertRed = Color(0xFFF04438);

/// "Cash" / "Online" for a payment method as the backend stores it, or null
/// when unknown. Shared with the notification text.
String? orderPaymentLabel(String? method) {
  final m = (method ?? '').trim().toLowerCase();
  if (m.isEmpty) return null;
  if (m.contains('cash') || m == 'cod') return 'Cash';
  return 'Online';
}

/// Everything the card shows for one order.
class IncomingOrderCardData {
  const IncomingOrderCardData({
    required this.deadline,
    required this.windowSeconds,
    this.total,
    this.paymentLabel,
    this.itemCount,
    this.displayId,
    this.customerName,
    this.address,
    this.itemsSummary,
    this.loading = false,
  });

  /// From a `new_order` push's data map (every value a String).
  factory IncomingOrderCardData.fromPushData(
    Map<String, dynamic> data, {
    required DateTime deadline,
    required int windowSeconds,
  }) {
    String? str(String key) {
      final v = data[key]?.toString().trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    return IncomingOrderCardData(
      deadline: deadline,
      windowSeconds: windowSeconds,
      total: double.tryParse(str('total') ?? ''),
      paymentLabel: orderPaymentLabel(str('paymentMethod')),
      itemCount: int.tryParse(str('itemCount') ?? ''),
      displayId: str('orderDisplayId'),
      customerName: str('customerName'),
      address: str('address'),
      itemsSummary: str('itemsList'),
    );
  }

  final DateTime deadline;
  final int windowSeconds;
  final double? total;
  final String? paymentLabel;
  final int? itemCount;
  final String? displayId;
  final String? customerName;
  final String? address;
  final String? itemsSummary;

  /// The full order is still being fetched and the push data lacks details.
  final bool loading;
}

/// Asks before rejecting — the same dialog in-app and in the overlay.
Future<bool> confirmRejectOrder(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Reject this order?'),
      content: const Text(
        'The customer will be notified and refunded per policy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Reject', style: TextStyle(color: AppColors.error)),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Full-screen new-order request, laid out like a captain app's offer card:
/// the amount up front, who and what on a two-stop timeline, one big Accept,
/// and the countdown ring doubling as the Reject button.
class IncomingOrderRequestView extends StatelessWidget {
  const IncomingOrderRequestView({
    super.key,
    required this.orderCount,
    required this.card,
    required this.now,
    required this.muted,
    required this.acting,
    required this.onToggleSound,
    required this.onAccept,
    required this.onReject,
    this.compact = false,
    this.cardKey,
  });

  /// Over-other-apps popup: just the card on a transparent window, sized to
  /// its content, instead of the full-screen layout used in the app.
  final bool compact;

  /// Lets the overlay measure the compact card to shrink its window to fit.
  final Key? cardKey;

  final int orderCount;

  /// The order on top of the queue; null draws the empty frame.
  final IncomingOrderCardData? card;

  /// Ticks once a second — only the countdown rings rebuild on it.
  final ValueListenable<DateTime> now;
  final bool muted;

  /// An Accept/Reject is in flight: both buttons are disabled.
  final bool acting;
  final VoidCallback onToggleSound;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF10131A) : const Color(0xFFF2F3F5);
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111111);
    final subText = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);
    final c = card;

    if (compact) {
      return Material(
        type: MaterialType.transparency,
        child: OverflowBox(
          // Unbounded height: the card lays out at its natural size whatever
          // the window currently is, so the overlay can measure it and resize
          // the window to fit (a window left small by the last offer used to
          // squeeze the card into an overflow).
          alignment: Alignment.topCenter,
          minHeight: 0,
          maxHeight: double.infinity,
          child: c == null
              ? const SizedBox.shrink()
              : Container(
                  key: cardKey,
                  margin: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSideRail(c, textColor),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
                          child: _buildCard(c, surface, textColor, subText, isDark),
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(orderCount, surface, textColor),
            Expanded(
              child: c == null
                  ? const SizedBox.shrink()
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSideRail(c, textColor),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(4, 16, 16, 24),
                            child: _buildCard(
                              c,
                              surface,
                              textColor,
                              subText,
                              isDark,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(int count, Color surface, Color textColor) {
    return Container(
      color: surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              count == 1 ? '1 Order' : '$count Orders',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 22,
              ),
            ),
          ),
          // Mutes the ringing only — the request stays up.
          GestureDetector(
            onTap: onToggleSound,
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: muted
                    ? const Color(0xFFB9BEC9)
                    : _accentYellow.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 18,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    muted ? 'OFF' : 'ON',
                    style: TextStyle(
                      color: muted ? Colors.white : const Color(0xFF111111),
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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

  /// Narrow rail on the left: the countdown and the amount at a glance.
  Widget _buildSideRail(IncomingOrderCardData c, Color textColor) {
    final total = c.total;
    return SizedBox(
      width: 72,
      child: Padding(
        padding: const EdgeInsets.only(top: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _countdownRing(c, size: 40, stroke: 3, showSeconds: true),
            const SizedBox(height: 6),
            if (total != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _money(total),
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(
    IncomingOrderCardData c,
    Color surface,
    Color textColor,
    Color subText,
    bool isDark,
  ) {
    final total = c.total;
    final payment = c.paymentLabel;
    final itemCount = c.itemCount;
    final displayId = c.displayId;
    final loading = c.loading;

    final chipParts = <String>[
      ?payment,
      if (itemCount != null) '$itemCount ${itemCount == 1 ? 'item' : 'items'}',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white12 : const Color(0xFFD5D8DE),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (chipParts.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : const Color(0xFFEEF0F3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          payment == 'Cash'
                              ? Icons.payments_outlined
                              : payment == 'Online'
                              ? Icons.credit_card_rounded
                              : Icons.shopping_bag_outlined,
                          size: 18,
                          color: subText,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            chipParts.join('  ·  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Spacer(),
              if (displayId != null)
                Text(
                  '#$displayId',
                  style: TextStyle(
                    color: subText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (total != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _money(total),
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 34,
                  height: 1.1,
                ),
              ),
            )
          else if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          const SizedBox(height: 14),
          _buildStop(
            isFirst: true,
            label: 'DELIVER TO',
            title: c.customerName,
            detail: c.address,
            textColor: textColor,
            subText: subText,
          ),
          _buildStop(
            isFirst: false,
            label: 'ITEMS',
            title: c.itemsSummary ?? (loading ? 'Loading items…' : null),
            detail: null,
            textColor: textColor,
            subText: subText,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // The countdown ring is also the reject button, as on captain
              // apps: the time running out and saying no live in one place.
              Semantics(
                button: true,
                label: 'Reject order',
                child: GestureDetector(
                  onTap: acting ? null : onReject,
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _countdownRing(c, size: 52, stroke: 3.5),
                        Icon(Icons.remove_rounded, size: 26, color: textColor),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: acting ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentYellow,
                      disabledBackgroundColor: _accentYellow.withValues(
                        alpha: 0.6,
                      ),
                      foregroundColor: const Color(0xFF111111),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: acting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF111111),
                            ),
                          )
                        : const Text(
                            'Accept',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// One stop on the timeline: a small label, then the bold line and grey
  /// detail underneath.
  Widget _buildStop({
    required bool isFirst,
    required String label,
    required String? title,
    required String? detail,
    required Color textColor,
    required Color subText,
  }) {
    if (title == null && detail == null) return const SizedBox.shrink();
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18,
            child: Column(
              children: [
                const SizedBox(height: 4),
                isFirst
                    ? Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: textColor,
                          shape: BoxShape.circle,
                        ),
                      )
                    : Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 22,
                        color: textColor,
                      ),
                if (isFirst)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isFirst ? 16 : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: subText,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (title != null)
                    Text(
                      title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  if (detail != null)
                    Text(
                      detail,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subText,
                        fontSize: 14,
                        height: 1.35,
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

  Widget _countdownRing(
    IncomingOrderCardData c, {
    required double size,
    required double stroke,
    bool showSeconds = false,
  }) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: now,
      builder: (context, now, _) {
        final ms = c.deadline.difference(now).inMilliseconds;
        final seconds = ms <= 0 ? 0 : (ms / 1000).ceil();
        final fraction = (seconds / c.windowSeconds).clamp(0.0, 1.0);
        final color = seconds <= 10 ? _alertRed : _okGreen;
        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: size,
                height: size,
                child: CircularProgressIndicator(
                  value: fraction,
                  strokeWidth: stroke,
                  backgroundColor: const Color(0xFFD5D8DE),
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              if (showSeconds)
                Text(
                  '$seconds',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  static String _money(double amount) => amount == amount.roundToDouble()
      ? '₹${amount.toStringAsFixed(0)}'
      : '₹${amount.toStringAsFixed(2)}';
}
