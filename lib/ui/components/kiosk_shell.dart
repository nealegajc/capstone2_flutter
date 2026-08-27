import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import 'status_badge.dart';

class KioskShell extends ConsumerStatefulWidget {
  const KioskShell({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends ConsumerState<KioskShell> {
  late Timer _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    setState(() {
      _currentTime = DateFormat('hh:mm:ss a • EEE, MMM d').format(DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith(AppRoutePaths.dashboard)) return 0;
    if (location.startsWith(AppRoutePaths.inventory)) return 1;
    if (location.startsWith(AppRoutePaths.cameraMonitor)) return 2;
    if (location.startsWith(AppRoutePaths.productManagement)) return 3;
    if (location.startsWith(AppRoutePaths.alerts)) return 4;
    if (location.startsWith(AppRoutePaths.restock)) return 5;
    if (location.startsWith(AppRoutePaths.syncStatus)) return 6;
    if (location.startsWith(AppRoutePaths.reports)) return 7;
    if (location.startsWith(AppRoutePaths.activityLogs)) return 8;
    if (location.startsWith(AppRoutePaths.settings)) return 9;
    if (location.startsWith(AppRoutePaths.helpGuide)) return 10;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go(AppRoutePaths.dashboard);
        break;
      case 1:
        context.go(AppRoutePaths.inventory);
        break;
      case 2:
        context.go(AppRoutePaths.cameraMonitor);
        break;
      case 3:
        context.go(AppRoutePaths.productManagement);
        break;
      case 4:
        context.go(AppRoutePaths.alerts);
        break;
      case 5:
        context.go(AppRoutePaths.restock);
        break;
      case 6:
        context.go(AppRoutePaths.syncStatus);
        break;
      case 7:
        context.go(AppRoutePaths.reports);
        break;
      case 8:
        context.go(AppRoutePaths.activityLogs);
        break;
      case 9:
        context.go(AppRoutePaths.settings);
        break;
      case 10:
        context.go(AppRoutePaths.helpGuide);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final headerBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final headerBorder = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final sidebarBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: Column(
        children: [
          // Top Kiosk Header Bar
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: headerBg,
              border: Border(
                bottom: BorderSide(color: headerBorder, width: 1.5),
              ),
            ),
            child: Row(
              children: [
                // Store Name & Logo
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shelves, color: AppColors.brandAccent, size: 28),
                ),
                const SizedBox(width: 14),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OTTO SCENTS',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Smart Shelf Kiosk (San Pablo)',
                      style: TextStyle(
                        color: textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Live Clock
                Row(
                  children: [
                    Icon(Icons.access_time, color: textSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _currentTime,
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 20),

                // System Status Badge
                const StatusBadge(type: StatusBadgeType.synced, customLabel: 'System Online'),
                const SizedBox(width: 14),

                // Dark / Light Mode Toggle Button
                Tooltip(
                  message: isDark ? 'Switch to Daylight Light Mode' : 'Switch to Dark Mode',
                  child: InkWell(
                    onTap: () {
                      ref.read(themeModeProvider.notifier).toggleTheme();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: headerBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                            color: isDark ? const Color(0xFFFBBF24) : AppColors.brandPrimary,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isDark ? 'Light' : 'Dark',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),

                // Lock Kiosk Button (Large Touch Target)
                InkWell(
                  onTap: () {
                    ref.read(authNotifierProvider.notifier).logout();
                    context.go(AppRoutePaths.login);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurfaceElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: headerBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lock_outline, color: AppColors.statusOrange, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Lock Kiosk',
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Kiosk Body with Left Navigation Rail
          Expanded(
            child: Row(
              children: [
                // Left Touch Navigation Sidebar (Categorized & Ergonomic)
                Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: sidebarBg,
                    border: Border(
                      right: BorderSide(color: headerBorder, width: 1.5),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    children: [
                      _buildSectionHeader('OPERATIONS', textSecondary),
                      _buildNavItem(0, 'Dashboard', Icons.dashboard_rounded, selectedIndex, isDark),
                      _buildNavItem(1, 'Inventory', Icons.inventory_2_rounded, selectedIndex, isDark),
                      _buildNavItem(2, 'Shelf Camera', Icons.videocam_rounded, selectedIndex, isDark),
                      _buildNavItem(3, 'ROIs & Partitions', Icons.category_rounded, selectedIndex, isDark),
                      _buildNavItem(4, 'Alerts & Events', Icons.notifications_active_rounded, selectedIndex, isDark),
                      _buildNavItem(5, 'Restock Records', Icons.move_to_inbox_rounded, selectedIndex, isDark),

                      const SizedBox(height: 12),
                      _buildSectionHeader('SYSTEM & TOOLS', textSecondary),
                      _buildNavItem(6, 'Cloud & Sync', Icons.cloud_sync_rounded, selectedIndex, isDark),
                      _buildNavItem(7, 'Reports & Audits', Icons.analytics_outlined, selectedIndex, isDark),
                      _buildNavItem(8, 'Activity Logs', Icons.receipt_long_rounded, selectedIndex, isDark),
                      _buildNavItem(9, 'Settings & PIN', Icons.settings_rounded, selectedIndex, isDark),
                      _buildNavItem(10, 'Help / Guide', Icons.help_center_rounded, selectedIndex, isDark),
                    ],
                  ),
                ),

                // Active Screen Content
                Expanded(
                  child: widget.child,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 8, bottom: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, String title, IconData icon, int selectedIndex, bool isDark) {
    final isSelected = index == selectedIndex;
    final activeText = isDark ? Colors.white : AppColors.brandPrimary;
    final inactiveText = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index, context),
          borderRadius: BorderRadius.circular(12),
          splashColor: AppColors.brandAccent.withValues(alpha: 0.2),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandAccent.withValues(alpha: isDark ? 0.15 : 0.12) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: AppColors.brandAccent.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.brandAccent : inactiveText,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? activeText : inactiveText,
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
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
