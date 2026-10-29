import 'package:flutter/material.dart';
import 'package:superapp_user/modules/module_id.dart';

/// Dynamic theme configuration for super app modules.
/// Provides module-specific rich dark top colors, active tab accents, glowing light washes, and soft background tints.
class ModuleThemeConfig {
  final Color darkTop;
  final Color midColor;
  final Color activeTabBg;
  final Color activeTabBorder;
  final Color activeIndicator;
  final Color containerBoxBg;
  final Color containerBoxBorder;
  final Color softTint;
  final Color glowWash;

  const ModuleThemeConfig({
    required this.darkTop,
    required this.midColor,
    required this.activeTabBg,
    required this.activeTabBorder,
    required this.activeIndicator,
    required this.containerBoxBg,
    required this.containerBoxBorder,
    required this.softTint,
    required this.glowWash,
  });

  /// Every module now shares the Jhatpat yellow + black theme. The per-module
  /// palettes below are kept only so a module can be re-accented later in
  /// one place; [of] deliberately ignores [id] today.
  static ModuleThemeConfig of(ModuleId? id) => _brand(ModuleId.food);

  static ModuleThemeConfig _brand(ModuleId? id) {
    switch (id) {
      case ModuleId.food:
        return const ModuleThemeConfig(
          darkTop: Color(0xFFFFB800),       // Vibrant Jhatpat Golden Yellow
          midColor: Color(0xFFFFC72C),
          activeTabBg: Color(0xFF18181B),   // Dark black pill container
          activeTabBorder: Color(0xFF27272A),
          activeIndicator: Color(0xFFFFC700),
          containerBoxBg: Color(0xFFFFC700),
          containerBoxBorder: Color(0xFFE5A600),
          glowWash: Color(0xFFFFF3C4),
          softTint: Color(0xFFFFFBEA),
        );
      case ModuleId.taxi:
        return const ModuleThemeConfig(
          darkTop: Color(0xFF8A2B00),       // Rich dark burnt orange
          midColor: Color(0xFFAA3700),
          activeTabBg: Color(0xFFDB4C04),
          activeTabBorder: Color(0xFFFF5E2B),
          activeIndicator: Color(0xFFFF5E2B),
          containerBoxBg: Color(0xFF9A3100),
          containerBoxBorder: Color(0xFFC04100),
          glowWash: Color(0xFFFFE0D0),
          softTint: Color(0xFFFFF3EC),
        );
      case ModuleId.parcel:
        return const ModuleThemeConfig(
          darkTop: Color(0xFF42105C),       // Rich dark royal violet
          midColor: Color(0xFF5A177D),
          activeTabBg: Color(0xFF7D24A0),
          activeTabBorder: Color(0xFF9533EC),
          activeIndicator: Color(0xFFA855F7),
          containerBoxBg: Color(0xFF4D146A),
          containerBoxBorder: Color(0xFF671B8D),
          glowWash: Color(0xFFE8CEF9),
          softTint: Color(0xFFF9F0FC),
        );
      case ModuleId.services:
        return const ModuleThemeConfig(
          darkTop: Color(0xFF000000),       // Black
          midColor: Color(0xFF121212),      // Dark Gray
          activeTabBg: Color(0xFF1F1F1F),   // Dark Pill Card
          activeTabBorder: Color(0xFF333333),
          activeIndicator: Color(0xFFFF7A00), // Bright Orange active line indicator
          containerBoxBg: Color(0xFF1F1F1F),
          containerBoxBorder: Color(0xFF2E2E2E),
          glowWash: Color(0xFFFFFFFF),      // White background for content
          softTint: Color(0xFFFFFFFF),      // White background for content
        );
      default:
        return const ModuleThemeConfig(
          darkTop: Color(0xFF1E1B4B),       // Rich dark cobalt indigo
          midColor: Color(0xFF312E81),
          activeTabBg: Color(0xFF4338CA),
          activeTabBorder: Color(0xFF6366F1),
          activeIndicator: Color(0xFF818CF8),
          containerBoxBg: Color(0xFF2B2669),
          containerBoxBorder: Color(0xFF3E388E),
          glowWash: Color(0xFFD0D7FE),
          softTint: Color(0xFFEEF2FF),
        );
    }
  }
}
