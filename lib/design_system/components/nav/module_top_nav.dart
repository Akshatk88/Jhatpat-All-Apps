import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/app_module.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/module_registry.dart';

/// The service switcher shown at the top of every module home.
///
/// Tabs come from [ModuleRegistry.enabled], so a newly registered module
/// appears here without this file changing, and a module gated off by
/// `isEnabled` (rental, until k9 serves its routes) is simply absent rather
/// than leading somewhere broken.
class ModuleTopNav extends ConsumerWidget {
  const ModuleTopNav({super.key, required this.activeModule});

  final ModuleId activeModule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modules = ref.watch(moduleRegistryProvider).enabled;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // One service is no choice — don't spend the vertical space on it.
    if (modules.length < 2) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.cardDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
        ),
        boxShadow: isDark
            ? null
            : const [
                BoxShadow(
                  color: AppColors.shadow2,
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          for (final module in modules)
            Expanded(
              child: _ModuleTab(
                module: module,
                isActive: module.id == activeModule,
                isDark: isDark,
                onTap: module.id == activeModule
                    ? null
                    : () => context.go(module.entryRoute),
              ),
            ),
        ],
      ),
    );
  }
}

class _ModuleTab extends StatelessWidget {
  const _ModuleTab({
    required this.module,
    required this.isActive,
    required this.isDark,
    required this.onTap,
  });

  final AppModule module;
  final bool isActive;
  final bool isDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = module.accent.primary;
    final activeFg = Colors.white;
    final inactiveFg =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
    final inactiveSub =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Semantics(
      button: true,
      selected: isActive,
      label: '${module.label}. ${module.tagline}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white.withValues(alpha: 0.22)
                      : accent.withValues(alpha: isDark ? 0.22 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  module.icon,
                  size: 17,
                  color: isActive ? activeFg : accent,
                ),
              ),
              const SizedBox(width: 7),
              // Flexible, not fixed: "Parcel / Send anything" is the longest
              // pair and must ellipsize rather than overflow on a 360dp screen.
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                        color: isActive ? activeFg : inactiveFg,
                      ),
                    ),
                    Text(
                      module.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                        color: isActive
                            ? activeFg.withValues(alpha: 0.85)
                            : inactiveSub,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
