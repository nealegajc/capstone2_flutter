import 'package:flutter/material.dart';
import 'app_colors.dart';

extension ThemeContextExtension on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get surfaceColor => isDark ? AppColors.darkSurface : AppColors.lightSurface;
  Color get surfaceElevatedColor => isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated;
  Color get backgroundColor => isDark ? AppColors.darkBackground : AppColors.lightBackground;
  Color get borderColor => isDark ? AppColors.darkBorder : AppColors.lightBorder;
  Color get textPrimaryColor => isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondaryColor => isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
  Color get textMutedColor => isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;

  // Gradients for banners & hero sections
  List<Color> get heroGradient => isDark
      ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
      : [const Color(0xFFE0F2FE), const Color(0xFFF0F9FF)];

  Color get heroBannerBorder => isDark ? AppColors.darkBorder : const Color(0xFFBAE6FD);
  Color get heroBannerTextPrimary => isDark ? AppColors.darkTextPrimary : const Color(0xFF0369A1);
  Color get heroBannerTextSecondary => isDark ? AppColors.darkTextSecondary : const Color(0xFF0284C7);
}
