import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:superapp_user/design_system/tokens/app_colors.dart';

/// A preset brand color the user can pick from Profile → App Theme.
///
/// `orange` is the app's shipped default — its [color]/[buttonColor] match
/// [AppColors]' original hardcoded values exactly, so selecting it (or never
/// changing the theme at all) looks pixel-identical to before this feature.
enum AppThemeColor {
  yellow('Yellow', Color(0xFFFFB800), Color(0xFFFFC700), '🟡'),
  orange('Orange', Color(0xFFFF7A00), Color(0xFFFF8A1D), '🟠'),
  green('Green', Color(0xFF2ECC71), Color(0xFF43D881), '🟢'),
  blue('Blue', Color(0xFF3B82F6), Color(0xFF5B95F8), '🔵'),
  red('Red', Color(0xFFE53935), Color(0xFFEB5C58), '🔴'),
  purple('Purple', Color(0xFF8E44AD), Color(0xFFA25FC0), '🟣'),
  pink('Pink', Color(0xFFEC4899), Color(0xFFF06CAA), '🩷');

  const AppThemeColor(this.label, this.color, this.buttonColor, this.emoji);

  final String label;
  final Color color;
  final Color buttonColor;
  final String emoji;
}

/// Persists and applies the selected [AppThemeColor].
///
/// Applying a color means reassigning the mutable [AppColors.primary] /
/// [AppColors.primaryButton] fields, then bumping [state] so every widget
/// watching [themeColorProvider] (currently just the app root, to rebuild
/// `MaterialApp`'s `theme`/`darkTheme`) rebuilds — which in turn makes every
/// `AppColors.primary` read across the app pick up the new value, since nothing
/// caches it.
final themeColorProvider =
    NotifierProvider<ThemeColorNotifier, AppThemeColor>(ThemeColorNotifier.new);

class ThemeColorNotifier extends Notifier<AppThemeColor> {
  static const _key = 'app_theme_color';

  /// The app ships one brand theme: Jhatpat yellow.
  ///
  /// This used to load a user-picked colour from prefs *after* the first frame,
  /// so the app opened yellow and then flipped to e.g. orange a moment later —
  /// and screens built before vs after the flip disagreed (Profile showed both).
  /// The picker is gone; any stale saved choice is cleared and ignored.
  @override
  AppThemeColor build() {
    AppColors.primary = AppThemeColor.yellow.color;
    AppColors.primaryButton = AppThemeColor.yellow.buttonColor;
    unawaited(_clearSavedChoice());
    return AppThemeColor.yellow;
  }

  Future<void> _clearSavedChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }

  /// Kept for API compatibility; the brand colour is fixed.
  Future<void> setColor(AppThemeColor color) async {
    _apply(AppThemeColor.yellow);
  }

  void _apply(AppThemeColor color) {
    AppColors.primary = color.color;
    AppColors.primaryButton = color.buttonColor;
    state = color;
  }
}
