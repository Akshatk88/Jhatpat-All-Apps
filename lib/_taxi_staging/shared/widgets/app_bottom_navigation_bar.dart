import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/_taxi_staging/core/theme/app_colors.dart';

class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBgColor = isDark ? TaxiColors.darkCard : Colors.white;

    return Container(
      color: navBgColor,
      child: SafeArea(
        top: false,
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: navBgColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _BottomNavItem(
                icon: currentIndex == 0 ? Icons.home_rounded : Icons.home_outlined,
                label: 'Home',
                isActive: currentIndex == 0,
                onTap: () {
                  if (currentIndex != 0) context.go('/home');
                },
              ),
              _BottomNavItem(
                icon: Icons.navigation_outlined,
                label: 'All Services',
                isActive: currentIndex == 1,
                onTap: () {
                  if (currentIndex != 1) context.go('/home/all-services');
                },
              ),
              _BottomNavItem(
                icon: currentIndex == 2 ? Icons.access_time_rounded : Icons.access_time_outlined,
                label: 'History',
                isActive: currentIndex == 2,
                onTap: () {
                  if (currentIndex != 2) context.go('/rides');
                },
              ),
              _BottomNavItem(
                icon: currentIndex == 3 ? Icons.person_rounded : Icons.person_outline_rounded,
                label: 'Profile',
                isActive: currentIndex == 3,
                onTap: () {
                  if (currentIndex != 3) context.go('/profile');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = TaxiColors.primary; // Brand orange
    final inactiveColor = isDark ? TaxiColors.darkTextSecondary : const Color(0xFF94A3B8);
    final color = isActive ? activeColor : inactiveColor;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
