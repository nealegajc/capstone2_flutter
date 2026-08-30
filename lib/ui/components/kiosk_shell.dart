import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_lock_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/kiosk_providers.dart';
import 'status_badge.dart';
import 'wifi_connection_dialog.dart';

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
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location == AppRoutePaths.roiDetail || location.startsWith(AppRoutePaths.roiDetail)) return 3;
    if (location.startsWith(AppRoutePaths.cameraMonitor)) return 2;
    if (location.startsWith(AppRoutePaths.productForm) || location.startsWith(AppRoutePaths.productDetail)) return 1;
    if (location.startsWith(AppRoutePaths.inventory)) return 1;
    if (location.startsWith(AppRoutePaths.dashboard)) return 0;
    if (location.startsWith(AppRoutePaths.alerts)) return 4;
    if (location.startsWith(AppRoutePaths.restock)) return 5;
    if (location.startsWith(AppRoutePaths.syncStatus) || location.startsWith(AppRoutePaths.syncQueue)) return 6;
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
        context.go(AppRoutePaths.roiDetail);
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
    final autoLockState = ref.watch(autoLockProvider);

    final headerBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final headerBorder = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final sidebarBg = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final remainingMin = autoLockState.remainingSeconds ~/ 60;
    final remainingSec = autoLockState.remainingSeconds % 60;
    final formattedCountdown = '${remainingMin}:${remainingSec.toString().padLeft(2, '0')}';

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      onPointerMove: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      onPointerSignal: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      child: Scaffold(
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'OTTO SCENTS',
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        'SMART SHELF SYSTEM',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // Live Clock Display
                  _KioskLiveClock(
                    textColor: textPrimary,
                    iconColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  const SizedBox(width: 20),

                  // Wi-Fi / Connectivity Status Action Badge
                  Consumer(
                    builder: (context, ref, _) {
                      final netStatus = ref.watch(networkStatusProvider);
                      return InkWell(
                        onTap: () => WifiConnectionDialog.show(context),
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
                            children: [
                              Icon(
                                netStatus.isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                                color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusOrange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                netStatus.isOnline
                                    ? (netStatus.currentSsid ?? 'Online')
                                    : 'Offline Buffer',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 14),

                  // Theme Toggle Button
                  Tooltip(
                    message: 'Toggle Dark / Light Mode',
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
                          children: [
                            Icon(
                              isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                              color: isDark ? AppColors.brandGold : AppColors.brandAccent,
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

                  // Single Unified Lock Kiosk Button with Integrated Auto-Lock Countdown
                  Tooltip(
                    message: autoLockState.isEnabled
                        ? 'Tap to lock immediately • Auto-lock in $formattedCountdown'
                        : 'Tap to lock kiosk terminal immediately',
                    child: InkWell(
                      onTap: () {
                        ref.read(authNotifierProvider.notifier).logout();
                        context.go(AppRoutePaths.login);
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
                            const Icon(Icons.lock_outline_rounded, color: AppColors.statusOrange, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Lock Kiosk',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (autoLockState.isEnabled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.black38 : Colors.black12,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: autoLockState.remainingSeconds <= 30
                                        ? AppColors.statusRed.withValues(alpha: 0.6)
                                        : headerBorder.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 13,
                                      color: autoLockState.remainingSeconds <= 30
                                          ? AppColors.statusRed
                                          : AppColors.brandAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      formattedCountdown,
                                      style: TextStyle(
                                        color: autoLockState.remainingSeconds <= 30
                                            ? AppColors.statusRed
                                            : textSecondary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
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
    const primaryColor = AppColors.brandAccent;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
    final textSecondary = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index, context),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? primaryColor.withValues(alpha: isDark ? 0.6 : 0.4)
                    : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: isSelected ? primaryColor : textSecondary,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: isSelected ? textPrimary : textSecondary,
                    ),
                  ),
                ),
                if (isSelected)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: primaryColor,
                      shape: BoxShape.circle,
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

class _KioskLiveClock extends StatefulWidget {
  final Color textColor;
  final Color iconColor;

  const _KioskLiveClock({
    required this.textColor,
    required this.iconColor,
  });

  @override
  State<_KioskLiveClock> createState() => _KioskLiveClockState();
}

class _KioskLiveClockState extends State<_KioskLiveClock> {
  late Timer _clockTimer;
  String _currentTime = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final formatted = DateFormat('hh:mm:ss a • EEE, MMM d').format(DateTime.now());
    if (formatted != _currentTime && mounted) {
      setState(() {
        _currentTime = formatted;
      });
    }
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.access_time, color: widget.iconColor, size: 20),
        const SizedBox(width: 8),
        Text(
          _currentTime,
          style: TextStyle(
            color: widget.textColor,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
