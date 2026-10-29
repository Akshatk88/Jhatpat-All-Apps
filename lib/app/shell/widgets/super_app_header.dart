import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:superapp_user/core/i18n/tr.dart';

import 'package:superapp_user/shared/settings/presentation/language_sheet.dart';
import 'package:superapp_user/app/routing/app_route_names.dart';
import 'package:superapp_user/design_system/components/media/smart_image.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:superapp_user/shared/address/presentation/viewmodels/address_viewmodel.dart';
import 'package:superapp_user/shared/location/application/current_location_provider.dart';
import 'package:superapp_user/shared/notifications/presentation/viewmodels/notification_inbox_viewmodel.dart';
import 'package:superapp_user/core/utils/haptics.dart';

import 'package:superapp_user/design_system/tokens/module_theme_config.dart';
import 'package:superapp_user/modules/module_id.dart';

/// Location, notifications and profile — shared across every module home.
class SuperAppHeader extends ConsumerWidget {
  const SuperAppHeader({
    super.key,
    this.themeConfig,
    this.moduleId,
    this.showLocation = true,
  });

  final ModuleThemeConfig? themeConfig;
  final ModuleId? moduleId;

  /// False on screens that show the pickup/delivery location themselves (the
  /// rides map), so the header is just brand + actions.
  final bool showLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = themeConfig ?? ModuleThemeConfig.of(ModuleId.food);
    final label = ref.watch(currentLocationLabelProvider);
    final addressLine = ref.watch(currentAddressLineProvider);
    final user = ref.watch(authViewModelProvider).value;
    final unread = ref.watch(unreadNotificationCountProvider);

    // The header shows the app-wide location (currentLocationProvider): the
    // saved address the user last picked, or their latest "use my current
    // location" fix. It used to prefer the *default* saved address instead,
    // so picking or fetching a location never reached the home screen.
    // The default saved address is only a fallback when there is no usable
    // location at all (GPS off / permission denied, nothing picked yet).
    final location = ref.watch(currentLocationProvider).value;
    final hasLocation =
        location?.latitude != null && location?.longitude != null;
    ref.watch(addressViewModelProvider);
    final saved = hasLocation
        ? null
        : ref.read(addressViewModelProvider.notifier).defaultAddress;

    final displayLabel = saved != null
        ? (saved.title.trim().isNotEmpty ? saved.title.trim() : saved.type)
        : (label.isNotEmpty && label != 'Locating…')
        ? label
        : 'Current Location'.tr;
    final displayAddress =
        (saved != null && saved.fullAddress.trim().isNotEmpty)
        ? saved.fullAddress.trim()
        : addressLine.isNotEmpty
        ? addressLine
        : 'Fetching address…'.tr;

    // One header for every module: the Jhatpat yellow + black design. Only
    // the "Deliver to" prefix is food-specific.
    final locationTitle = moduleId == ModuleId.food
        ? 'Deliver to • {label}'.trArgs({'label': displayLabel})
        : displayLabel;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Brand & Actions
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Icon(
                    Icons.bolt_rounded,
                    color: Color(0xFFFFC700),
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'JHATPAT',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const Spacer(),
              _HeaderIconButton(
                icon: Icons.translate_rounded,
                themeConfig: config,
                iconColor: Colors.black,
                bgColor: Colors.transparent,
                borderColor: Colors.transparent,
                onTap: () {
                  Haptics.light();
                  showLanguageSheet(context);
                },
              ),
              const SizedBox(width: 2),
              _HeaderIconButton(
                icon: Icons.notifications_none_rounded,
                badgeCount: unread,
                themeConfig: config,
                iconColor: Colors.black,
                bgColor: Colors.transparent,
                borderColor: Colors.transparent,
                onTap: () {
                  Haptics.light();
                  ref
                      .read(notificationInboxProvider.notifier)
                      .clearUnreadCount();
                  context.push(AppRoutePaths.notifications);
                },
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  Haptics.light();
                  context.push(AppRoutePaths.profile);
                },
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.black, width: 1.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: (user?.avatarUrl?.isNotEmpty ?? false)
                      ? SmartImage(
                          url: user!.avatarUrl!,
                          category: ImageCategory.brand,
                          width: 36,
                          height: 36,
                        )
                      : const Icon(
                          Icons.person_rounded,
                          size: 22,
                          color: Colors.black,
                        ),
                ),
              ),
            ],
          ),
          if (showLocation) const SizedBox(height: 8),
          // Row 2: Deliver to Card
          if (showLocation)
          InkWell(
            onTap: () {
              Haptics.light();
              context.push(AppRoutePaths.addresses);
            },
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB800),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.location_on, color: Colors.black, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          locationTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayAddress,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.2,
                                  color: Colors.black.withValues(alpha: 0.75),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: Colors.black,
                            ),
                          ],
                        ),
                      ],
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
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.themeConfig,
    required this.onTap,
    this.badgeCount = 0,
    this.iconColor,
    this.bgColor,
    this.borderColor,
  });

  final IconData icon;
  final ModuleThemeConfig themeConfig;
  final VoidCallback onTap;
  final int badgeCount;
  final Color? iconColor;
  final Color? bgColor;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bgColor ?? themeConfig.containerBoxBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: borderColor ?? themeConfig.containerBoxBorder,
                width: 1,
              ),
            ),
            child: Icon(icon, size: 22, color: iconColor ?? Colors.white),
          ),
          if (badgeCount > 0)
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFF032418),
                    width: 1.5,
                  ),
                ),
                child: Text(
                  badgeCount > 9 ? '9+' : '$badgeCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
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
