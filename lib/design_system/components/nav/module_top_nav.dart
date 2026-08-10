import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/module_registry.dart';

/// The always-visible service switcher at the top of every module home.
///
/// Tabs come from [ModuleRegistry.enabled], so a newly registered module shows
/// up here without this file being touched — and a module gated off by
/// `isEnabled` (rental, until k9 serves its routes) disappears rather than
/// leading somewhere broken.
///
/// Each tab is tinted with its own [ModuleAccent], which is what stops the
/// super app feeling like one product wearing four hats.
class ModuleTopNav extends ConsumerWidget {
  const ModuleTopNav({super.key, required this.activeModule});

  final ModuleId activeModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(moduleRegistryProvider).enabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // A single module means no choice to offer — don't waste the vertical space.
    if (modules.length < 2) return const SizedBox.shrink();

    return Container(
      color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      padding: EdgeInsets.only(left: 12, right: 12, bottom: 0, top: 4),
      child: SizedBox(
        height: 74,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          // Four or fewer tabs never scroll; the list exists so a fifth and
          // sixth module (bus and pooling already have k9 endpoints) degrade
          // gracefully instead of overflowing.
          physics: modules.length <= 4
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          itemCount: modules.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final module = modules[index];
            final isActive = module.id == activeModule;
            return _ModuleTab(
              label: module.label,
              icon: module.icon,
              accent: module.accent.primary,
              isActive: isActive,
              isDark: isDark,
              // Fixed width when they all fit, so the row reads as a segmented
              // control rather than ragged chips.
              width: modules.length <= 4
                  ? (MediaQuery.sizeOf(context).width - 24 - (modules.length - 1) * 8) /
                      modules.length
                  : 88,
              onTap: isActive ? null : () => context.go(module.entryRoute),
            );
          },
        ),
      ),
    );
  }
}

class _ModuleTab extends StatelessWidget {
  const _ModuleTab({
    required this.label,
    required this.icon,
    required this.accent,
    required this.isActive,
    required this.isDark,
    required this.width,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final bool isActive;
  final bool isDark;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final inactiveFg =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return SizedBox(
      width: width,
      child: Material(
        color: isActive
            ? accent.withValues(alpha: isDark ? 0.22 : 0.12)
            : (isDark ? AppColors.cardDark : AppColors.surfaceLight),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(18),
          bottom: Radius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
                bottom: Radius.circular(6),
              ),
              border: Border.all(
                color: isActive
                    ? accent.withValues(alpha: 0.55)
                    : (isDark ? AppColors.borderDark : AppColors.borderLight),
                width: isActive ? 1.4 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: isActive ? 25 : 22,
                  color: isActive ? accent : inactiveFg,
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.0,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                    letterSpacing: -0.2,
                    color: isActive
                        ? (isDark
                            ? AppColors.textPrimaryDark
                            : AppColors.textPrimaryLight)
                        : inactiveFg,
                  ),
                ),
                const SizedBox(height: 4),
                // Underline on the active tab — the colour alone is not enough
                // to signal selection for a colour-blind user.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 3,
                  width: isActive ? 26 : 0,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
