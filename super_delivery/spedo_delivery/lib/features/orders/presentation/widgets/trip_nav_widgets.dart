import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:food_user_application/core/utils/route_progress.dart';

/// "10 m", "250 m", "1.2 km": rounded the way a navigation app reads it out.
String formatNavDistance(double meters) {
  if (meters < 100) return '${(meters / 10).round() * 10} m';
  if (meters < 1000) return '${(meters / 50).round() * 50} m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

/// "11:34 AM" without needing the intl package.
String formatClock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}

String formatEtaMinutes(double seconds) {
  final mins = (seconds / 60).ceil();
  if (mins < 1) return '1 min';
  if (mins < 60) return '$mins min';
  final h = mins ~/ 60;
  final m = mins % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}

IconData _iconFor(TurnKind kind) {
  switch (kind) {
    case TurnKind.slightLeft:
      return Icons.turn_slight_left_rounded;
    case TurnKind.left:
      return Icons.turn_left_rounded;
    case TurnKind.sharpLeft:
      return Icons.turn_sharp_left_rounded;
    case TurnKind.slightRight:
      return Icons.turn_slight_right_rounded;
    case TurnKind.right:
      return Icons.turn_right_rounded;
    case TurnKind.sharpRight:
      return Icons.turn_sharp_right_rounded;
    case TurnKind.uTurn:
      return Icons.u_turn_left_rounded;
    case TurnKind.arrive:
      return Icons.flag_rounded;
    case TurnKind.straight:
      return Icons.straight_rounded;
  }
}

String _instructionFor(TurnKind kind, String destinationLabel) {
  switch (kind) {
    case TurnKind.slightLeft:
      return 'Bear left';
    case TurnKind.left:
      return 'Turn left';
    case TurnKind.sharpLeft:
      return 'Sharp left';
    case TurnKind.slightRight:
      return 'Bear right';
    case TurnKind.right:
      return 'Turn right';
    case TurnKind.sharpRight:
      return 'Sharp right';
    case TurnKind.uTurn:
      return 'Make a U-turn';
    case TurnKind.arrive:
      return destinationLabel;
    case TurnKind.straight:
      return 'Continue straight';
  }
}

/// Green turn banner, like the top of a navigation screen: the manoeuvre
/// icon, the distance to it, and the road it is on when known.
class TripNavBanner extends StatelessWidget {
  const TripNavBanner({
    super.key,
    required this.turn,
    this.roadName,
    this.destinationLabel = 'Destination',
  });

  final NextTurn turn;
  final String? roadName;

  /// Shown when the next "turn" is the end of the route ("Pickup", "Drop").
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    final arriving = turn.kind == TurnKind.arrive;
    final title = arriving
        ? destinationLabel
        : (roadName != null && roadName!.isNotEmpty ? roadName! : _instructionFor(turn.kind, destinationLabel));
    final subtitle = arriving || roadName == null || roadName!.isEmpty ? null : _instructionFor(turn.kind, destinationLabel);

    return Material(
      color: const Color(0xFF0B7A3E),
      elevation: 6,
      borderRadius: BorderRadius.circular(16.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_iconFor(turn.kind), color: Colors.white, size: 34.sp),
                Text(
                  formatNavDistance(turn.distanceMeters),
                  style: TextStyle(color: Colors.white, fontSize: 14.sp, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.white70, fontSize: 12.sp, fontWeight: FontWeight.w600),
                    ),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white, fontSize: 19.sp, fontWeight: FontWeight.w800, height: 1.15),
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

/// "7 min · 2.3 km · 11:34 AM" for the bottom card.
String tripEtaSummary({required double etaSeconds, required double remainingMeters, DateTime? now}) {
  final arrival = (now ?? DateTime.now()).add(Duration(seconds: etaSeconds.round()));
  return '${formatEtaMinutes(etaSeconds)} · ${formatNavDistance(remainingMeters)} · ${formatClock(arrival)}';
}
