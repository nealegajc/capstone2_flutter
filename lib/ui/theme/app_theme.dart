import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart' as core_colors;
import '../../core/theme/app_theme.dart' as core_theme;

export '../../core/theme/app_colors.dart';
export '../../core/theme/app_theme.dart';

class AppColors {
  // Brand
  static const Color primary = core_colors.AppColors.brandPrimary;
  static const Color accent = core_colors.AppColors.brandAccent;
  static const Color accentPurple = Color(0xFF8B5CF6);

  // Light Theme
  static const Color lightBg = core_colors.AppColors.lightBackground;
  static const Color lightCardBg = core_colors.AppColors.lightSurface;
  static const Color lightBorder = core_colors.AppColors.lightBorder;
  static const Color lightTextPrimary = core_colors.AppColors.lightTextPrimary;
  static const Color lightTextSecondary =
      core_colors.AppColors.lightTextSecondary;
  static const Color lightTextMuted = core_colors.AppColors.lightTextMuted;

  // Dark Theme (Kiosk optimized)
  static const Color darkBg = core_colors.AppColors.darkBackground;
  static const Color darkCardBg = core_colors.AppColors.darkSurface;
  static const Color darkBorder = core_colors.AppColors.darkBorder;
  static const Color darkTextPrimary = core_colors.AppColors.darkTextPrimary;
  static const Color darkTextSecondary =
      core_colors.AppColors.darkTextSecondary;
  static const Color darkTextMuted = core_colors.AppColors.darkTextMuted;

  // Status & Semantic Colors
  static const Color green = core_colors.AppColors.statusGreen;
  static const Color greenBg = core_colors.AppColors.statusGreenBg;

  static const Color red = core_colors.AppColors.statusRed;
  static const Color redBg = core_colors.AppColors.statusRedBg;

  static const Color orange = core_colors.AppColors.statusOrange;
  static const Color orangeBg = core_colors.AppColors.statusOrangeBg;

  static const Color blue = core_colors.AppColors.statusBlue;
  static const Color blueBg = core_colors.AppColors.statusBlueBg;

  static const Color purple = core_colors.AppColors.femalePink;
  static const Color purpleBg = core_colors.AppColors.femalePinkBg;

  static const Color gray = Color(0xFF6B7280);
  static const Color grayBg = Color(0x1A6B7280);
}

class AppTheme {
  static ThemeData get lightTheme => core_theme.AppTheme.lightKioskTheme;
  static ThemeData get darkTheme => core_theme.AppTheme.darkKioskTheme;
}
