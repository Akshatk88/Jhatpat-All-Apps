import 'package:flutter/material.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/core/utils/haptics.dart';
import 'package:superapp_user/app/routing/route_names.dart';

class CustomBottomNav extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final navBg = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFB800);
    final activeColor = Colors.black;
    final unselectedColor = isDark
        ? const Color(0xFF9E9E9E)
        : Colors.black.withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: navBg,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0.w, vertical: 6.0.h),
          // Tablets / desktop: keep the tabs in a phone-sized band, centred.
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // 1. Home (Branch 0)
              _buildNavItem(
                context: context,
                icon: Icons.home_rounded,
                label: 'Home',
                index: 0,
                activeColor: activeColor,
                unselectedColor: unselectedColor,
              ),

              // 2. Orders (Route /food/orders)
              _buildNavItem(
                context: context,
                icon: Icons.receipt_long_outlined,
                label: 'Orders',
                index: 99,
                activeColor: activeColor,
                unselectedColor: unselectedColor,
              ),

              // 3. Ride (Route /taxi)
              _buildNavItem(
                context: context,
                icon: Icons.local_taxi_rounded,
                label: 'Ride',
                index: 98,
                activeColor: activeColor,
                unselectedColor: unselectedColor,
              ),

              // 4. Profile (Branch 3)
              _buildNavItem(
                context: context,
                icon: Icons.person_outline_rounded,
                label: 'Profile',
                index: 3,
                activeColor: activeColor,
                unselectedColor: unselectedColor,
              ),
            ],
          ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required String label,
    required int index,
    required Color activeColor,
    required Color unselectedColor,
  }) {
    final isSelected = currentIndex == index;

    // Flexible: lets the four tabs shrink on a 320dp phone at large text
    // sizes instead of overflowing the row.
    return Flexible(
      child: GestureDetector(
      onTap: () {
        Haptics.light();
        if (index == 99) {
          context.push(RouteNames.orders);
        } else if (index == 98) {
          context.go('/taxi');
        } else {
          onTap(index);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.0.w, vertical: 4.0.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? activeColor : unselectedColor,
              size: 24.sp,
            ),
            SizedBox(height: 3.h),
            Text(
              label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSelected ? activeColor : unselectedColor,
                fontSize: 11.sp,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
