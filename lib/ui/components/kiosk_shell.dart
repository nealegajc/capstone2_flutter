import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/auth_provider.dart';
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

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Column(
        children: [
          // Top Kiosk Header Bar
          Container(
            height: 72,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: AppColors.darkSurface,
              border: Border(
                bottom: BorderSide(color: AppColors.darkBorder, width: 1.5),
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
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'OTTO SCENTS',
                      style: TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'Smart Shelf Kiosk',
                      style: TextStyle(
                        color: AppColors.darkTextSecondary,
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
                    const Icon(Icons.access_time, color: AppColors.darkTextSecondary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      _currentTime,
                      style: const TextStyle(
                        color: AppColors.darkTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 24),

                // System Status Badge
                const StatusBadge(type: StatusBadgeType.synced, customLabel: 'System Online'),
                const SizedBox(width: 24),

                // Lock Kiosk Button (Large Touch Target)
                InkWell(
                  onTap: () {
                    ref.read(authNotifierProvider.notifier).logout();
                    context.go(AppRoutePaths.login);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    decoration: BoxDecoration(
                      color: AppColors.darkSurfaceElevated,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline, color: AppColors.statusOrange, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Lock Kiosk',
                          style: TextStyle(
                            color: AppColors.darkTextPrimary,
                            fontSize: 15,
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
                // Left Touch Navigation Sidebar (Large touch items)
                Container(
                  width: 240,
                  decoration: const BoxDecoration(
                    color: AppColors.darkSurface,
                    border: Border(
                      right: BorderSide(color: AppColors.darkBorder, width: 1.5),
                    ),
                  ),
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    children: [
                      _buildNavItem(0, 'Dashboard', Icons.dashboard_rounded, selectedIndex),
                      _buildNavItem(1, 'Inventory', Icons.inventory_2_rounded, selectedIndex),
                      _buildNavItem(2, 'Shelf Camera', Icons.videocam_rounded, selectedIndex),
                      _buildNavItem(3, 'Products & ROIs', Icons.category_rounded, selectedIndex),
                      _buildNavItem(4, 'Alerts & Events', Icons.notifications_active_rounded, selectedIndex),
                      _buildNavItem(5, 'Restock Verification', Icons.move_to_inbox_rounded, selectedIndex),
                      _buildNavItem(6, 'Sync Status', Icons.sync_rounded, selectedIndex),
                      _buildNavItem(7, 'Activity Logs', Icons.receipt_long_rounded, selectedIndex),
                      _buildNavItem(8, 'Settings & PIN', Icons.settings_rounded, selectedIndex),
                      _buildNavItem(9, 'Help / Guide', Icons.help_center_rounded, selectedIndex),
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

  Widget _buildNavItem(int index, String title, IconData icon, int selectedIndex) {
    final isSelected = index == selectedIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _onItemTapped(index, context),
          borderRadius: BorderRadius.circular(14),
          splashColor: AppColors.brandAccent.withValues(alpha: 0.2),
          child: Container(
            height: 58,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.brandAccent.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: isSelected
                  ? Border.all(color: AppColors.brandAccent.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isSelected ? AppColors.brandAccent : AppColors.darkTextSecondary,
                  size: 26,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : AppColors.darkTextSecondary,
                      fontSize: 15,
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
