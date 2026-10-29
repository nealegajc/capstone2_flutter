import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/auto_lock_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/kiosk_providers.dart';
import 'system_restart_banner.dart';
import 'wifi_connection_dialog.dart';
import 'misplacement_banner.dart';

class KioskShell extends ConsumerStatefulWidget {
  const KioskShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends ConsumerState<KioskShell> {
  int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith(AppRoutePaths.cameraMonitor) ||
        location.startsWith(AppRoutePaths.roiDetail)) {
      return 2;
    }
    if (location.startsWith(AppRoutePaths.productForm) ||
        location.startsWith(AppRoutePaths.productDetail) ||
        location.startsWith(AppRoutePaths.inventory)) {
      return 1;
    }
    if (location.startsWith(AppRoutePaths.dashboard)) return 0;
    if (location.startsWith(AppRoutePaths.alerts)) return 3;
    if (location.startsWith(AppRoutePaths.restock) ||
        location.startsWith(AppRoutePaths.createRestock)) {
      return 4;
    }
    if (location.startsWith(AppRoutePaths.syncStatus) ||
        location.startsWith(AppRoutePaths.syncQueue)) {
      return 5;
    }
    if (location.startsWith(AppRoutePaths.reports)) return 6;
    if (location.startsWith(AppRoutePaths.activityLogs)) return 7;
    if (location.startsWith(AppRoutePaths.settings)) return 8;
    if (location.startsWith(AppRoutePaths.helpGuide)) return 9;
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
        context.go(AppRoutePaths.alerts);
        break;
      case 4:
        context.go(AppRoutePaths.restock);
        break;
      case 5:
        context.go(AppRoutePaths.syncStatus);
        break;
      case 6:
        context.go(AppRoutePaths.reports);
        break;
      case 7:
        context.go(AppRoutePaths.activityLogs);
        break;
      case 8:
        context.go(AppRoutePaths.settings);
        break;
      case 9:
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
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    final remainingMin = autoLockState.remainingSeconds ~/ 60;
    final remainingSec = autoLockState.remainingSeconds % 60;
    final formattedCountdown =
        '$remainingMin:${remainingSec.toString().padLeft(2, '0')}';

    final alertsAsync = ref.watch(liveAlertsProvider('San Pablo'));
    final syncService = ref.watch(syncServiceProvider);
    final activeAlertCount = alertsAsync.valueOrNull?.length ?? 0;
    final pendingSyncCount = syncService.pendingCount;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      onPointerMove: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      onPointerSignal: (_) => ref.read(autoLockProvider.notifier).resetTimer(),
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        body: Column(
          children: [
            const SystemRestartBanner(),
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
                  // Store Name & Logo (with Long Press fullscreen toggle for admin maintenance)
                  InkWell(
                    onLongPress: () async {
                      try {
                        final isFull = await windowManager.isFullScreen();
                        await windowManager.setFullScreen(!isFull);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isFull
                                    ? 'Exited Fullscreen (Maintenance Mode)'
                                    : 'Entered Fullscreen (Kiosk Mode)',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      } catch (_) {}
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.brandAccent.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shelves,
                            color: AppColors.brandAccent,
                            size: 28,
                          ),
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
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              'SMART SHELF SYSTEM',
                              style: TextStyle(
                                color: textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Live Clock Display
                  _KioskLiveClock(
                    textColor: textPrimary,
                    iconColor: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
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
                            color: isDark
                                ? AppColors.darkSurfaceElevated
                                : AppColors.lightSurfaceElevated,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: headerBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                netStatus.isOnline
                                    ? Icons.wifi_rounded
                                    : Icons.wifi_off_rounded,
                                color: netStatus.isOnline
                                    ? AppColors.statusGreen
                                    : AppColors.statusOrange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                netStatus.isOnline
                                    ? (netStatus.currentSsid ?? 'Online')
                                    : 'Saved Offline',
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 15,
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
                          color: isDark
                              ? AppColors.darkSurfaceElevated
                              : AppColors.lightSurfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: headerBorder),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isDark
                                  ? Icons.light_mode_rounded
                                  : Icons.dark_mode_rounded,
                              color: isDark
                                  ? AppColors.brandGold
                                  : AppColors.brandAccent,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isDark ? 'Light' : 'Dark',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Single Unified Lock Screen Button with Integrated Auto-Lock Countdown
                  Tooltip(
                    message: autoLockState.isEnabled
                        ? 'Tap to lock screen • Auto-locks in $formattedCountdown'
                        : 'Tap to lock screen now',
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
                          color: isDark
                              ? AppColors.darkSurfaceElevated
                              : AppColors.lightSurfaceElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: headerBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.lock_outline_rounded,
                              color: AppColors.statusOrange,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Lock Screen',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (autoLockState.isEnabled) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.black38
                                      : Colors.black12,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: autoLockState.remainingSeconds <= 30
                                        ? AppColors.statusRed.withValues(
                                            alpha: 0.6,
                                          )
                                        : headerBorder.withValues(alpha: 0.6),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_outlined,
                                      size: 14,
                                      color:
                                          autoLockState.remainingSeconds <= 30
                                          ? AppColors.statusRed
                                          : AppColors.brandAccent,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      formattedCountdown,
                                      style: TextStyle(
                                        color:
                                            autoLockState.remainingSeconds <= 30
                                            ? AppColors.statusRed
                                            : textSecondary,
                                        fontSize: 12,
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
                    width: 256,
                    decoration: BoxDecoration(
                      color: sidebarBg,
                      border: Border(
                        right: BorderSide(color: headerBorder, width: 1.5),
                      ),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 10,
                            ),
                            children: [
                              _buildSectionHeader(
                                'STORE & SHELF',
                                textSecondary,
                              ),
                              _buildNavItem(
                                0,
                                'Store Overview',
                                Icons.home_filled,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                1,
                                'Fragrance Stock',
                                Icons.inventory_2_rounded,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                2,
                                'Live Shelf & Cameras',
                                Icons.videocam_rounded,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                3,
                                'Alerts & Warnings',
                                Icons.notifications_active_rounded,
                                selectedIndex,
                                isDark,
                                badgeCount: activeAlertCount,
                                badgeColor: AppColors.statusRed,
                              ),
                              _buildNavItem(
                                4,
                                'Restock & Deliveries',
                                Icons.move_to_inbox_rounded,
                                selectedIndex,
                                isDark,
                              ),

                              const SizedBox(height: 12),
                              _buildSectionHeader(
                                'REPORTS & SYSTEM',
                                textSecondary,
                              ),
                              _buildNavItem(
                                5,
                                'Cloud Backup',
                                Icons.cloud_done_rounded,
                                selectedIndex,
                                isDark,
                                badgeCount: pendingSyncCount,
                                badgeColor: AppColors.statusOrange,
                              ),
                              _buildNavItem(
                                6,
                                'Sales & Reports',
                                Icons.insights_rounded,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                7,
                                'Activity History',
                                Icons.history_rounded,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                8,
                                'Settings',
                                Icons.settings_rounded,
                                selectedIndex,
                                isDark,
                              ),
                              _buildNavItem(
                                9,
                                'Staff Handbook',
                                Icons.menu_book_rounded,
                                selectedIndex,
                                isDark,
                              ),
                            ],
                          ),
                        ),
                        _buildSidebarFooter(
                          isDark,
                          textPrimary,
                          textSecondary,
                          headerBorder,
                        ),
                      ],
                    ),
                  ),

                  // Active Screen Content with Persistent Misplacement Banner
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const MisplacementBanner(),
                        Expanded(child: widget.child),
                      ],
                    ),
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
      padding: const EdgeInsets.only(left: 12, top: 12, bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    String title,
    IconData icon,
    int selectedIndex,
    bool isDark, {
    int badgeCount = 0,
    Color badgeColor = AppColors.statusRed,
  }) {
    final isSelected = index == selectedIndex;
    const primaryColor = AppColors.brandAccent;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index, context),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                  size: 24,
                  color: isSelected ? primaryColor : textSecondary,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: isSelected ? textPrimary : textSecondary,
                    ),
                  ),
                ),
                if (badgeCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else if (isSelected)
                  Container(
                    width: 7,
                    height: 7,
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

  Widget _buildSidebarFooter(
    bool isDark,
    Color textPrimary,
    Color textSecondary,
    Color headerBorder,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurfaceElevated.withValues(alpha: 0.6)
            : AppColors.lightSurfaceElevated.withValues(alpha: 0.8),
        border: Border(top: BorderSide(color: headerBorder, width: 1.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.statusGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Branch: San Pablo',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ONLINE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    color: AppColors.statusGreen,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Kiosk Terminal #01',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
              Text(
                'v2.4.0 • Linux',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? AppColors.darkTextMuted
                      : AppColors.lightTextMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _KioskLiveClock extends StatefulWidget {
  final Color textColor;
  final Color iconColor;

  const _KioskLiveClock({required this.textColor, required this.iconColor});

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
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateTime(),
    );
  }

  void _updateTime() {
    final formatted = DateFormat('hh:mm:ss a • EEE, MMM d')
        .format(DateTime.now());
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
