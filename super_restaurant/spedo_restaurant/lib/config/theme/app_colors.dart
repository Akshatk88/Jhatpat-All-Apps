import 'package:flutter/material.dart';

/// Centralized color palette for the app, based on the food app UI design.
class AppColors {
  // ==================== BRAND COLORS ====================
  static const Color primary = Color(0xFFFF7622); // Vibrant Orange
  static const Color primaryLight = Color(0xFFFF9853);
  static const Color primaryDark = Color(0xFFE05F00);

  // ==================== DARK THEME COLORS ====================
  static const Color backgroundDark = Color(0xFF161925); // Deep Navy/Dark Grey
  static const Color surfaceDark = Color(0xFF222638); // Card background
  static const Color surfaceVariantDark = Color(
    0xFF2E3347,
  ); // Lighter surface for chips/inputs

  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFA0A5BA);

  // ==================== LIGHT THEME COLORS ====================
  // Designed to complement the dark theme structure
  static const Color backgroundLight = Color(0xFFF5F5F5);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceVariantLight = Color(0xFFEEEEEE);

  static const Color textPrimaryLight = Color(0xFF1E1E1E);
  static const Color textSecondaryLight = Color(0xFF666666);

  // ==================== STATUS & ACCENT COLORS ====================
  static const Color success = Color(0xFF4ADE80); // Green for time/success
  static const Color rating = Color(0xFFFFB01D); // Yellow/Orange for stars
  static const Color error = Color(0xFFFF6464); // Red/Flame for calories/errors
}
