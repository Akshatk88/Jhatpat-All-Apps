import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/design_system/tokens/module_theme_config.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/core/i18n/tr.dart';

class NavItem {
  final ModuleId? id;
  final String label;
  final String tagline;
  final String imageAsset;

  /// Icon uploaded in the admin panel. Wins over [imageAsset] when set; the
  /// asset (then [fallbackIcon]) shows while it loads or if it fails.
  final String imageUrl;
  final IconData fallbackIcon;
  final String route;

  const NavItem({
    required this.id,
    required this.label,
    required this.tagline,
    required this.imageAsset,
    this.imageUrl = '',
    required this.fallbackIcon,
    required this.route,
  });
}

/// The service switcher shown at the top of every module home.
///
/// One tab per enabled module. The list is **passed in** rather than built
/// here: `design_system` may not import `modules/**`, so the app layer
/// (`ModuleHomeShell`) derives it from `ModuleRegistry.enabled` and hands it
/// over. That is what makes a new module appear here for free — this used to
/// be a hardcoded three-item list, which is why registering a fourth module
/// changed the hub but not this bar.
class ModuleTopNav extends ConsumerWidget {
  const ModuleTopNav({
    super.key,
    required this.activeModule,
    required this.items,
  });

  final ModuleId activeModule;

  /// Enabled modules, already in display order.
  final List<NavItem> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();

    final activeConfig = ModuleThemeConfig.of(activeModule);

    // Four tabs share the width the design drew for three, so the type and
    // padding step down once the bar gets crowded. Without this the labels
    // ellipsise to "Serv…" and the taglines vanish entirely.
    final isCompact = items.length > 3;
    // Always registry order (Rides, Parcel, Food, ...): the tabs must not
    // reshuffle depending on which module is open.
    final displayItems = items;

    return Container(
      // Tablets / desktop: the switcher stays a phone-sized band, centred,
      // instead of a few tabs stretched across the whole width.
      constraints: const BoxConstraints(maxWidth: 640),
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.only(top: 4, bottom: 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: displayItems.map((item) {
          final isActive = item.id == activeModule;
          final itemConfig = ModuleThemeConfig.of(item.id);

          return Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 1.5 : 3),
              child: _ModuleTab(
                item: item,
                isActive: isActive,
                isCompact: isCompact,
                activeConfig: activeConfig,
                itemConfig: itemConfig,
                onTap: isActive ? null : () => context.go(item.route),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _ModuleTab extends StatelessWidget {
  const _ModuleTab({
    required this.item,
    required this.isActive,
    required this.isCompact,
    required this.activeConfig,
    required this.itemConfig,
    required this.onTap,
  });

  final NavItem item;
  final bool isActive;
  final bool isCompact;
  final ModuleThemeConfig activeConfig;
  final ModuleThemeConfig itemConfig;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (activeConfig.darkTop == const Color(0xFFFFB800)) {
      return Semantics(
        button: true,
        selected: isActive,
        label: '${item.label.tr}. ${item.tagline.tr}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 38,
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF18181B) : const Color(0xFFFFF3C4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? const Color(0xFF27272A) : Colors.black.withValues(alpha: 0.06),
                width: 1,
              ),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: isActive
                  ? Container(
                      margin: EdgeInsets.symmetric(
                        horizontal: isCompact ? 2 : 4,
                        vertical: 3,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 6 : 14,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC700),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      // Fixed-height pill: on narrow phones / large text the
                      // label shrinks instead of wrapping out of the 38dp box.
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label.tr,
                          maxLines: 1,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          item.label.tr,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      selected: isActive,
      label: '${item.label.tr}. ${item.tagline.tr}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: EdgeInsets.only(bottom: isActive ? 0 : 6),
          padding: EdgeInsets.fromLTRB(
            isActive ? (isCompact ? 3 : 5) : 2,
            isActive ? 9 : 6,
            isActive ? (isCompact ? 3 : 5) : 2,
            isActive ? 11 : 6,
          ),
          decoration: BoxDecoration(
            gradient: isActive
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [itemConfig.activeTabBg, itemConfig.darkTop],
                  )
                : null,
            color: isActive ? null : const Color(0x33000000),
            borderRadius: isActive
                ? const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                    bottomLeft: Radius.circular(6),
                    bottomRight: Radius.circular(6),
                  )
                : BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? itemConfig.activeTabBorder
                  : Colors.white.withValues(alpha: 0.12),
              width: isActive ? 1.2 : 1,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: itemConfig.darkTop.withValues(alpha: 0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // A module without artwork renders its icon instead, so a new
                  // module is never blocked on someone drawing a PNG first.
                  _NavIcon(
                    item: item,
                    size: isActive ? (isCompact ? 18 : 20) : 16,
                    iconSize: isActive ? 18 : 15,
                    iconColor: isActive
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.7),
                  ),
                  SizedBox(width: isCompact ? 2 : 3),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact
                                ? (isActive ? 11.5 : 10.5)
                                : (isActive ? 13 : 12),
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: isActive
                                ? Colors.white
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                        Text(
                          item.tagline.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isCompact
                                ? (isActive ? 8 : 7.5)
                                : (isActive ? 9 : 8.5),
                            height: 1.25,
                            fontWeight: FontWeight.w500,
                            color: isActive
                                ? Colors.white.withValues(alpha: 0.85)
                                : const Color(0xFF94A3B8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isActive) ...[
                const SizedBox(height: 4),
                Container(
                  width: 26,
                  height: 3,
                  decoration: BoxDecoration(
                    color: itemConfig.activeIndicator,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                        color: itemConfig.activeIndicator.withValues(alpha: 0.6),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin icon first, then the bundled asset, then the Material icon.
class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.item,
    required this.size,
    required this.iconSize,
    required this.iconColor,
  });

  final NavItem item;
  final double size;
  final double iconSize;
  final Color iconColor;

  Widget _local() {
    final icon = Icon(item.fallbackIcon, size: iconSize, color: iconColor);
    if (item.imageAsset.isEmpty) return icon;
    return Image.asset(
      item.imageAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!item.imageUrl.startsWith('http')) return _local();
    return CachedNetworkImage(
      imageUrl: item.imageUrl,
      width: size,
      height: size,
      fit: BoxFit.contain,
      placeholder: (_, _) => _local(),
      errorWidget: (_, _, _) => _local(),
    );
  }
}
