import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

const kOfferYellow = Color(0xFFFFC107);
const kOfferGreen = Color(0xFF1E9E5A);
const kOfferRed = Color(0xFFF04438);

/// One stop on the offer timeline: distance (and time) on top, then the place
/// name in bold followed by the rest of the address in grey.
class OfferStop {
  const OfferStop({
    required this.name,
    this.detail = '',
    this.distance,
    this.duration,
  });

  /// Splits a plain address at its first comma — the part before it is almost
  /// always the place name.
  factory OfferStop.fromAddress(
    String address, {
    String? distance,
    String? duration,
  }) {
    final comma = address.indexOf(',');
    return OfferStop(
      name: comma > 0 ? address.substring(0, comma).trim() : address,
      detail: comma > 0 ? address.substring(comma + 1).trim() : '',
      distance: distance,
      duration: duration,
    );
  }

  final String name;
  final String detail;

  /// e.g. `2.3 km`; null hides the line and shows a PICKUP/DROP label instead.
  final String? distance;

  /// e.g. `(7 mins)`, shown in grey after [distance].
  final String? duration;
}

/// The captain-style job offer, shared by every surface that raises one: the
/// in-app ride and food offer screens and the over-other-apps overlay.
///
/// Purely presentational. The caller owns the countdown, the ringtone and what
/// Accept / decline actually do, so each surface keeps its own behaviour while
/// all of them look the same.
class OfferRequestView extends StatelessWidget {
  const OfferRequestView({
    super.key,
    required this.secondsLeft,
    required this.totalSeconds,
    required this.fare,
    this.bonus = 0,
    required this.jobLabel,
    required this.jobIcon,
    required this.pickup,
    required this.drop,
    required this.soundOn,
    required this.onToggleSound,
    required this.resolving,
    required this.onAccept,
    required this.onDecline,
    this.title = '1 Order',
    this.banner,
    this.paymentNote,
    this.paymentNoteColor,
    this.compact = false,
    this.cardKey,
  });

  /// Over-other-apps popup: just the card on a transparent window, sized to
  /// its content, instead of the full-screen layout used in the app.
  final bool compact;

  /// Lets the overlay measure the compact card to shrink its window to fit.
  final Key? cardKey;

  final ValueListenable<int> secondsLeft;
  final int totalSeconds;

  /// Null when the offer carries no payout — the amount is hidden rather than
  /// shown as a confident ₹0.
  final double? fare;
  final double bonus;
  final String jobLabel;
  final IconData jobIcon;
  final OfferStop pickup;
  final OfferStop drop;
  final bool soundOn;
  final VoidCallback onToggleSound;
  final bool resolving;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final String title;

  /// Shown above the job chip (e.g. the DriveU warning).
  final Widget? banner;
  final String? paymentNote;
  final Color? paymentNoteColor;

  /// Rough minutes for a distance at city riding speed, for legs the payload
  /// gives no time for.
  static int minsForKm(double km) => (km / 20 * 60).ceil().clamp(1, 999);

  static String money(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF10131A) : const Color(0xFFF2F3F5);
    final surface = isDark ? const Color(0xFF181C25) : Colors.white;
    final textColor = isDark ? Colors.white : const Color(0xFF111111);
    final subText = isDark ? Colors.grey[400]! : const Color(0xFF6B7280);

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
          child: Container(
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
                _buildSideRail(textColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 10, 10),
                    child: _buildOfferCard(surface, textColor, subText, isDark),
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
            _buildTopBar(surface, textColor),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSideRail(textColor),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(4.w, 16.h, 16.w, 24.h),
                      child: _buildOfferCard(surface, textColor, subText, isDark),
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

  Widget _buildTopBar(Color surface, Color textColor) {
    return Container(
      color: surface,
      padding: EdgeInsets.fromLTRB(20.w, 12.h, 16.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: 22.sp,
              ),
            ),
          ),
          // Mutes the ringtone without touching the offer — a captain who has
          // seen it does not need the phone ringing while they read it.
          GestureDetector(
            onTap: onToggleSound,
            child: Container(
              padding: EdgeInsets.fromLTRB(6.w, 6.h, 14.w, 6.h),
              decoration: BoxDecoration(
                color: soundOn ? kOfferYellow.withValues(alpha: 0.25) : const Color(0xFFB9BEC9),
                borderRadius: BorderRadius.circular(30.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 30.w,
                    height: 30.w,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      soundOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      size: 18.sp,
                      color: const Color(0xFF6B7280),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Text(
                    soundOn ? 'ON' : 'OFF',
                    style: TextStyle(
                      color: soundOn ? const Color(0xFF111111) : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15.sp,
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

  /// Narrow rail on the left: the countdown ring and the payout at a glance.
  Widget _buildSideRail(Color textColor) {
    return Container(
      width: 72.w,
      padding: EdgeInsets.only(top: 18.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _countdownRing(size: 34.w, stroke: 3),
          SizedBox(height: 6.h),
          if (fare != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${money(fare!)}',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 16.sp,
                ),
              ),
            ),
          if (bonus > 0)
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '+₹${money(bonus)}',
                style: TextStyle(
                  color: kOfferGreen,
                  fontWeight: FontWeight.w800,
                  fontSize: 15.sp,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOfferCard(Color surface, Color textColor, Color subText, bool isDark) {
    return Container(
      padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 16.h),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: isDark ? Colors.white12 : const Color(0xFFD5D8DE)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?banner,
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFEEF0F3),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(jobIcon, size: 18.sp, color: subText),
                SizedBox(width: 8.w),
                Flexible(
                  child: Text(
                    jobLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 10.h),
          // Fare (+ bonus), shrunk to fit rather than wrapping on long amounts.
          if (fare != null)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '₹${money(fare!)}',
                      style: TextStyle(color: textColor),
                    ),
                    if (bonus > 0)
                      TextSpan(
                        text: ' + ₹${money(bonus)}',
                        style: const TextStyle(color: kOfferGreen),
                      ),
                  ],
                ),
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 34.sp, height: 1.1),
              ),
            ),
          if (paymentNote != null) ...[
            SizedBox(height: 4.h),
            Text(
              paymentNote!,
              style: TextStyle(
                color: paymentNoteColor ?? subText,
                fontWeight: FontWeight.w700,
                fontSize: 12.sp,
              ),
            ),
          ],
          SizedBox(height: 14.h),
          _buildLeg(isPickup: true, stop: pickup, textColor: textColor, subText: subText),
          _buildLeg(isPickup: false, stop: drop, textColor: textColor, subText: subText),
          SizedBox(height: 16.h),
          Row(
            children: [
              // The countdown ring is also the decline button, as on captain
              // apps: the time running out and saying no live in one place.
              GestureDetector(
                onTap: resolving ? null : onDecline,
                child: SizedBox(
                  width: 52.w,
                  height: 52.w,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _countdownRing(size: 52.w, stroke: 3.5),
                      Icon(Icons.remove_rounded, size: 26.sp, color: textColor),
                    ],
                  ),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: SizedBox(
                  height: 52.h,
                  child: ElevatedButton(
                    onPressed: resolving ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kOfferYellow,
                      disabledBackgroundColor: kOfferYellow.withValues(alpha: 0.6),
                      foregroundColor: const Color(0xFF111111),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30.r),
                      ),
                    ),
                    child: resolving
                        ? SizedBox(
                            width: 22.w,
                            height: 22.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF111111),
                            ),
                          )
                        : Text(
                            'Accept',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18.sp),
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

  Widget _buildLeg({
    required bool isPickup,
    required OfferStop stop,
    required Color textColor,
    required Color subText,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 18.w,
            child: Column(
              children: [
                SizedBox(height: 8.h),
                isPickup
                    ? Container(
                        width: 9.w,
                        height: 9.w,
                        decoration: BoxDecoration(color: textColor, shape: BoxShape.circle),
                      )
                    : Icon(Icons.arrow_drop_down_rounded, size: 22.sp, color: textColor),
                if (isPickup)
                  Expanded(
                    child: Container(width: 1.5, color: textColor.withValues(alpha: 0.7)),
                  ),
              ],
            ),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isPickup ? 16.h : 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (stop.distance != null)
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: stop.distance,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 20.sp,
                            ),
                          ),
                          if (stop.duration != null)
                            TextSpan(
                              text: ' ${stop.duration}',
                              style: TextStyle(color: subText, fontSize: 13.sp),
                            ),
                        ],
                      ),
                    )
                  else
                    Text(
                      isPickup ? 'PICKUP' : 'DROP',
                      style: TextStyle(
                        color: subText,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.sp,
                        letterSpacing: 0.8,
                      ),
                    ),
                  SizedBox(height: 2.h),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: stop.name,
                          style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                        ),
                        if (stop.detail.isNotEmpty)
                          TextSpan(
                            text: ' - ${stop.detail}',
                            style: TextStyle(color: subText),
                          ),
                      ],
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.sp, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countdownRing({required double size, required double stroke}) {
    return ValueListenableBuilder<int>(
      valueListenable: secondsLeft,
      builder: (context, seconds, _) {
        final fraction = totalSeconds == 0 ? 0.0 : (seconds / totalSeconds).clamp(0.0, 1.0);
        return SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: fraction,
            strokeWidth: stroke,
            backgroundColor: const Color(0xFFD5D8DE),
            valueColor: AlwaysStoppedAnimation(
              seconds <= 5 ? kOfferRed : kOfferGreen,
            ),
          ),
        );
      },
    );
  }
}
