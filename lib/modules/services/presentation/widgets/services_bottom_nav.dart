import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/core/i18n/tr.dart';
import 'package:superapp_user/modules/services/application/my_bookings_controller.dart';
import 'package:superapp_user/modules/services/presentation/widgets/sp_widgets.dart';
import 'package:superapp_user/modules/services/services_module.dart';

/// Which tab of the services module is showing.
enum ServicesTab { home, bookings, track, profile }

/// Bottom navigation for the services module.
///
/// Owned by the module rather than reusing `AppBottomNavigationBar`, which
/// hardcodes `/taxi` routes — a shared bar would have to learn about every
/// module to be safe, which is the coupling the module contract exists to
/// avoid.
///
/// **Track** is not a static route.** It jumps to whatever the customer
/// actually has in flight: the searching screen while a professional is being
/// found, the tracking screen once one is assigned, and the bookings list when
/// there is nothing live. A tab that always went to a fixed path would land on
/// an empty screen most of the time, which is why booking history and tracking
/// were previously buried behind a button on the home screen.
class ServicesBottomNav extends ConsumerWidget {
  const ServicesBottomNav({super.key, required this.current});

  final ServicesTab current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drives both the Track destination and its live dot.
    final active = ref.watch(spActiveBookingProvider);

    void go(ServicesTab tab) {
      if (tab == current && tab != ServicesTab.track) return;

      switch (tab) {
        case ServicesTab.home:
          context.go(ServicesRoutePaths.home);
        case ServicesTab.bookings:
          context.go(ServicesRoutePaths.bookings);
        case ServicesTab.track:
          if (active == null || active.status.isFinished) {
            // Nothing in flight — the list is the honest destination, and its
            // Active tab is already the default.
            context.go(ServicesRoutePaths.bookings);
          } else if (active.status.isSearching) {
            context.go(ServicesRoutePaths.searchingFor(active.id));
          } else {
            context.go(ServicesRoutePaths.bookingOf(active.id));
          }
        case ServicesTab.profile:
          context.go(AppRoutePaths.profile);
      }
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        // Brand bar: yellow with black items in light mode; dark stays dark.
        color: isDark ? spSurface(context) : spAccent,
        border: isDark ? Border(top: BorderSide(color: spBorder(context))) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _Tab(
                icon: Icons.home_rounded,
                label: 'Home'.tr,
                selected: current == ServicesTab.home,
                onTap: () => go(ServicesTab.home),
              ),
              _Tab(
                icon: Icons.receipt_long_rounded,
                label: 'Bookings'.tr,
                selected: current == ServicesTab.bookings,
                onTap: () => go(ServicesTab.bookings),
              ),
              _Tab(
                icon: Icons.near_me_rounded,
                label: 'Track'.tr,
                selected: current == ServicesTab.track,
                // A quiet dot beats a count: there is only ever one booking
                // worth tracking, and a "1" badge reads as an unread message.
                showDot: active != null && !active.status.isFinished,
                onTap: () => go(ServicesTab.track),
              ),
              _Tab(
                icon: Icons.person_rounded,
                label: 'Profile'.tr,
                selected: current == ServicesTab.profile,
                onTap: () => go(ServicesTab.profile),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showDot = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colour = isDark
        ? (selected ? spAccent : spTextSecondary(context))
        : (selected ? spOnAccent : Colors.black54);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 22, color: colour),
                if (showDot)
                  Positioned(
                    right: -2,
                    top: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isDark ? spAccent : spOnAccent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? spSurface(context) : spAccent,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: colour,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
