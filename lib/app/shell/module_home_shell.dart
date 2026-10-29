import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/app/shell/widgets/super_app_header.dart';
import 'package:superapp_user/core/config/api_config.dart';
import 'package:superapp_user/core/i18n/language_provider.dart';
import 'package:superapp_user/shared/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'package:superapp_user/shared/settings/presentation/language_sheet.dart';
import 'package:superapp_user/design_system/components/nav/module_top_nav.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/design_system/tokens/module_theme_config.dart';
import 'package:superapp_user/modules/module_id.dart';
import 'package:superapp_user/modules/module_registry.dart';
import 'package:superapp_user/modules/taxi/home/application/home_providers.dart';
import 'package:superapp_user/modules/taxi/home/data/models/app_module_model.dart';

/// Wraps a module's **entry** screen with the service switcher and dynamic top-to-bottom gradient backdrop.
class ModuleHomeShell extends ConsumerWidget {
  const ModuleHomeShell({
    super.key,
    required this.moduleId,
    required this.child,
    this.bottomNavigationBar,
    this.showHeaderLocation = true,
  });

  /// False when the module home shows the location itself (the rides map has
  /// its own pickup pill), so the header drops its location card.
  final bool showHeaderLocation;

  final ModuleId moduleId;
  final Widget child;

  /// Optional per-module bottom navigation.
  ///
  /// Supplied by the module rather than built here: the existing shared
  /// `AppBottomNavigationBar` hardcodes taxi routes, and a module's own tabs
  /// are module knowledge. A module that passes nothing is laid out exactly as
  /// before.
  final Widget? bottomNavigationBar;

  /// The service-switcher tabs, one per enabled module in hub order.
  ///
  /// Derived here rather than inside [ModuleTopNav] because `design_system`
  /// may not import `modules/**` — the app layer is the tier that is allowed
  /// to know which modules exist. Registering a module in `module_registry`
  /// is therefore the only change needed for it to show up in the bar.
  static List<NavItem> _navItems(WidgetRef ref) {
    // Icons uploaded in the admin's module list. Only taxi and parcel appear
    // there; food/services, and any pending or failed fetch, keep the assets.
    final adminModules =
        ref.watch(appModulesProvider).asData?.value ?? const <AppModuleModel>[];
    String adminIcon(ModuleId id) {
      for (final m in adminModules) {
        final type = '${m.transportType} ${m.serviceType}'.toLowerCase();
        final match = switch (id) {
          ModuleId.taxi => m.transportType.toLowerCase() == 'taxi',
          ModuleId.parcel => type.contains('parcel'),
          _ => false,
        };
        // Uploads often come back as relative paths ('/uploads/...').
        if (match && m.mobileMenuIcon.isNotEmpty) {
          return ApiConfig.resolveMedia(m.mobileMenuIcon);
        }
      }
      return '';
    }

    return [
      for (final module in ref.watch(moduleRegistryProvider).enabled)
        NavItem(
          id: module.id,
          label: module.label,
          tagline: module.tagline,
          imageAsset: module.navIconAsset,
          imageUrl: adminIcon(module.id),
          fallbackIcon: module.icon,
          route: module.entryRoute,
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final config = ModuleThemeConfig.of(moduleId);

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          // Top-to-bottom gradient: Starts DARK at the top, gets lighter going down
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 420,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: isDark
                      ? [
                          config.darkTop,
                          config.darkTop.withValues(alpha: 0.85),
                          config.midColor.withValues(alpha: 0.4),
                          AppColors.backgroundDark,
                        ]
                      : [
                          config.darkTop,                          // 1. Top status bar & Location header: DARK GREEN
                          config.darkTop,                          // 2. Solid brand colour through the module tabs
                          config.midColor,                        // 3. Search Bar area: Medium Green
                          config.glowWash.withValues(alpha: 0.70),// 4. Category row: Light Green Wash
                          config.softTint.withValues(alpha: 0.35),// 5. Below Categories: Soft Tint
                          AppColors.backgroundLight.withValues(alpha: 0.0), // 6. Filter Pills & Feed: White
                        ],
                  stops: isDark
                      ? const [0.0, 0.4, 0.75, 1.0]
                      // Solid down past the tabs (~0.52 of the height): a module home with a
                      // pinned search block (Food) paints the same solid colour right
                      // below them, and a fade here showed up as a visible seam.
                      : const [0.0, 0.6, 0.68, 0.8, 0.9, 1.0],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Container(
                // A map body starts right under the tabs, so give the header a
                // solid backing and a bit of room below the tabs; otherwise
                // they look cut off against the map.
                color: showHeaderLocation ? null : config.darkTop,
                padding: EdgeInsets.only(bottom: showHeaderLocation ? 0 : 10),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SuperAppHeader(
                        themeConfig: config,
                        moduleId: moduleId,
                        showLocation: showHeaderLocation,
                      ),
                      ModuleTopNav(
                        activeModule: moduleId,
                        items: _navItems(ref),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(child: _FirstRunLanguagePrompt(child: child)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Asks once, right after the first login, which language to use. Lives in
/// the module shell because every login lands on a module home.
class _FirstRunLanguagePrompt extends ConsumerStatefulWidget {
  const _FirstRunLanguagePrompt({required this.child});

  final Widget child;

  @override
  ConsumerState<_FirstRunLanguagePrompt> createState() =>
      _FirstRunLanguagePromptState();
}

class _FirstRunLanguagePromptState
    extends ConsumerState<_FirstRunLanguagePrompt> {
  static bool _shownThisRun = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _shownThisRun) return;
      final loggedIn = ref.read(authViewModelProvider).value != null;
      final notifier = ref.read(localeProvider.notifier);
      if (!loggedIn || notifier.hasChosen) return;
      _shownThisRun = true;
      await showLanguageSheet(context, firstTime: true);
      notifier.markChosen();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
