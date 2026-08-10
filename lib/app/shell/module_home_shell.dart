import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:superapp_user/design_system/components/nav/module_top_nav.dart';
import 'package:superapp_user/design_system/tokens/app_colors.dart';
import 'package:superapp_user/modules/module_id.dart';

/// Wraps a module's **entry** screen with the service switcher.
///
/// Only the entry route is wrapped, never the whole subtree: switching service
/// from inside a checkout or a live ride would silently abandon it. Once the
/// user is in a flow, the way out is back, not sideways.
///
/// The switcher sits above the module content and takes the status-bar inset,
/// so a module home no longer bleeds under the status bar the way food's hero
/// banner used to. That is a deliberate trade — a persistent switcher is worth
/// more than an edge-to-edge banner on the home screen.
class ModuleHomeShell extends ConsumerWidget {
  const ModuleHomeShell({
    super.key,
    required this.moduleId,
    required this.child,
  });

  final ModuleId moduleId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: ModuleTopNav(activeModule: moduleId),
          ),
          // The module keeps its own Scaffold, app bar, refresh indicator and
          // bottom nav — this only donates the strip above it.
          Expanded(child: child),
        ],
      ),
    );
  }
}
