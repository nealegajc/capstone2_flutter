import 'package:flutter/material.dart';

class AppColors {
  // Brand
  static const Color brandPrimary = Color(0xFF0F172A); // Deep Slate Navy
  static const Color brandAccent = Color(0xFF38BDF8); // Electric Sky Blue
  static const Color brandGold = Color(0xFFFBBF24); // Warm Gold Accent

  // High-Contrast Dark Theme (Retail Kiosk Optimized)
  static const Color darkBackground = Color(0xFF090D16);
  static const Color darkSurface = Color(0xFF131C2E);
  static const Color darkSurfaceElevated = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF334155);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextMuted = Color(0xFF64748B);

  // Status & Semantic Badges
  // Green = Synced / In Stock / Normal
  static const Color statusGreen = Color(0xFF10B981);
  static const Color statusGreenBg = Color(0x2610B981);

  // Red = Alert / Low Stock / Scan Error
  static const Color statusRed = Color(0xFFEF4444);
  static const Color statusRedBg = Color(0x26EF4444);

  // Orange = Pending Sync / Misplaced / Needs Verification
  static const Color statusOrange = Color(0xFFF59E0B);
  static const Color statusOrangeBg = Color(0x26F59E0B);

  // Blue = Info / Active Scanning
  static const Color statusBlue = Color(0xFF3B82F6);
  static const Color statusBlueBg = Color(0x263B82F6);

  // Numpad Touch Keys
  static const Color numpadKeyBg = Color(0xFF1E293B);
  static const Color numpadKeyPressed = Color(0xFF334155);
  static const Color numpadActionBg = Color(0xFF0F172A);
  static const Color numpadActionClear = Color(0x33EF4444);
  static const Color numpadActionDelete = Color(0x33F59E0B);
}
