import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/design_system/tokens/taxi_colors.dart';

/// Bottom bar for the rides side of the app, in the shared Jhatpat theme:
/// yellow strip, outline icons, and the active tab going solid, black and bold.
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  static const int ride = 0;
  static const int services = 1;
  static const int parcel = 2;
  static const int history = 3;
  static const int profile = 4;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBgColor = isDark ? TaxiColors.darkCard : const Color(0xFFFFB800);

    void goTo(int index, String path) {
      if (currentIndex != index) context.go(path);
    }

    return Container(
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          // Five tabs spread across a tablet / desktop width look scattered;
          // keep them in a phone-sized band in the middle.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
            children: [
              _BottomNavItem(
                icon: Icons.near_me_outlined,
                activeIcon: Icons.near_me,
                label: 'Ride',
                isActive: currentIndex == ride,
                onTap: () => goTo(ride, '/taxi'),
              ),
              _BottomNavItem(
                icon: Icons.grid_view_outlined,
                activeIcon: Icons.grid_view_rounded,
                label: 'Services',
                isActive: currentIndex == services,
                onTap: () => goTo(services, '/taxi/services'),
              ),
              _BottomNavItem(
                icon: Icons.inventory_2_outlined,
                activeIcon: Icons.inventory_2,
                label: 'Parcel',
                isActive: currentIndex == parcel,
                onTap: () => goTo(parcel, '/parcel'),
              ),
              _BottomNavItem(
                icon: Icons.access_time_outlined,
                activeIcon: Icons.access_time_filled_rounded,
                label: 'History',
                isActive: currentIndex == history,
                onTap: () => goTo(history, '/taxi/rides'),
              ),
              _BottomNavItem(
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: 'Profile',
                isActive: currentIndex == profile,
                // Pushed, not gone to: profile is a root page, and back should
                // land the user where they were rather than exit the app.
                onTap: () => context.push(AppRoutePaths.profile),
              ),
            ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? Colors.white : Colors.black;
    final inactiveColor = isDark
        ? TaxiColors.darkTextSecondary
        : Colors.black.withValues(alpha: 0.72);
    final color = isActive ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          Haptics.light();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isActive ? activeIcon : icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12.5,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
