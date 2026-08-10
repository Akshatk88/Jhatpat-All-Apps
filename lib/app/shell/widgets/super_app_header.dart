import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:superapp_user/shared/location/application/current_location_provider.dart';
import 'package:superapp_user/shared/notifications/presentation/viewmodels/notification_inbox_viewmodel.dart';

/// Location, notifications and profile — shared across every module home.
///
/// It lives in the shell rather than inside each module so the address is
/// resolved once and rendered identically whichever service is open. The
/// location itself comes from [currentLocationProvider], which fetches a single
/// time for the app's lifetime; switching Food → Rides re-reads a cached value
/// instead of re-acquiring GPS.
class SuperAppHeader extends ConsumerWidget {
  const SuperAppHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = ref.watch(currentLocationLabelProvider);
    final addressLine = ref.watch(currentAddressLineProvider);
    final user = ref.watch(authViewModelProvider).value;
    final unread = ref.watch(unreadNotificationCountProvider);

    final primaryText =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final secondaryText =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isDark ? AppColors.cardDark : AppColors.textPrimaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              // Tapping the address opens the address book rather than silently
              // re-locating — a stale pin is usually a wrong saved address, not
              // a stale GPS fix.
              onTap: () => context.push(AppRoutePaths.addresses),
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                            color: primaryText,
                          ),
                        ),
                      ),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 19, color: primaryText),
                    ],
                  ),
                  Text(
                    addressLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.2,
                      color: secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _HeaderIconButton(
            icon: Icons.notifications_none_rounded,
            badgeCount: unread,
            isDark: isDark,
            onTap: () => context.push(AppRoutePaths.notifications),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => context.push(AppRoutePaths.profile),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  width: 1.5,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: (user?.avatarUrl?.isNotEmpty ?? false)
                  ? SmartImage(
                      url: user!.avatarUrl!,
                      category: ImageCategory.brand,
                      width: 38,
                      height: 38,
                    )
                  : Icon(Icons.person_rounded, size: 21, color: secondaryText),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
    this.badgeCount = 0,
  });

  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? AppColors.cardDark : AppColors.surfaceLight,
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color:
                  isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isDark
                        ? AppColors.backgroundDark
                        : AppColors.backgroundLight,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9.5,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
