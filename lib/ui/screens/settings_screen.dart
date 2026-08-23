import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/form_widgets.dart';
import '../components/scroll_screen.dart';

class SettingsScreen extends StatelessWidget {
  final VoidCallback onOpenReports;
  final VoidCallback onOpenSystemLogs;
  final VoidCallback onOpenMovementLogs;
  final VoidCallback onOpenSyncStatus;
  final VoidCallback onOpenImageQuality;
  final VoidCallback onOpenHelp;
  final VoidCallback onOpenSchedule;

  const SettingsScreen({
    super.key,
    required this.onOpenReports,
    required this.onOpenSystemLogs,
    required this.onOpenMovementLogs,
    required this.onOpenSyncStatus,
    required this.onOpenImageQuality,
    required this.onOpenHelp,
    required this.onOpenSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScrollScreen(
      title: 'Settings & Profile',
      subtitle: 'System configuration, display options, and administrative utilities',
      children: [
        // User Profile Card
        AppCard(
          backgroundColor: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: user?.isAdmin == true ? AppColors.redBg : AppColors.blueBg,
                child: Icon(
                  user?.isAdmin == true ? Icons.admin_panel_settings_rounded : Icons.person_rounded,
                  color: user?.isAdmin == true ? AppColors.red : AppColors.blue,
                  size: 32,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.email ?? 'User',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Role: ${(user?.role ?? 'Staff').toUpperCase()} • Assigned Branch: ${user?.branch ?? 'San Pablo'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                text: 'Sign Out',
                variant: AppButtonVariant.outline,
                icon: Icons.logout_rounded,
                onPressed: provider.logout,
                height: 48,
                fontSize: 13,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Preferences & Appearance
        const Text('Preferences', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dark Mode (AMOLED Kiosk)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Optimizes contrast and readability for touchscreen panels', style: TextStyle(fontSize: 13, color: AppColors.gray)),
                    ],
                  ),
                  Switch(
                    value: provider.isDarkMode,
                    onChanged: (_) => provider.toggleDarkMode(),
                    activeColor: AppColors.accent,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // System & AI Configuration
        const Text('AI & Monitoring Parameters', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              StepperSettingRow(
                title: 'Low Stock Threshold Warning',
                description: 'Triggers a system notification when inventory count drops to or below this value',
                value: provider.lowStockThreshold,
                min: 1,
                max: 10,
                suffix: ' bottles',
                onChanged: provider.setLowStockThreshold,
              ),
              const Divider(height: 32),

              _buildNavigationRow(
                'Camera AI Capture Schedule',
                'Currently: ${provider.captureSchedule}',
                Icons.schedule_rounded,
                onOpenSchedule,
                isDark,
              ),
              const Divider(height: 32),

              _buildNavigationRow(
                'Image Quality & Preprocessing Logs',
                'Inspect brightness, contrast, and retry status per scan',
                Icons.tune_rounded,
                onOpenImageQuality,
                isDark,
              ),
              const Divider(height: 32),

              _buildNavigationRow(
                'Cloud Sync & Offline Queue Status',
                'View pending synchronization queue and connection state',
                Icons.sync_rounded,
                onOpenSyncStatus,
                isDark,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Logs & Analytics
        const Text('Logs & Analytics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              if (user?.isAdmin == true) ...[
                _buildNavigationRow(
                  'Financial & Sales Reports',
                  'View revenue trends, top sellers, and inventory value',
                  Icons.insights_rounded,
                  onOpenReports,
                  isDark,
                ),
                const Divider(height: 32),
                _buildNavigationRow(
                  'System Activity Audit Trail',
                  'Admin audit log of user logins, calibrations, and edits',
                  Icons.receipt_long_rounded,
                  onOpenSystemLogs,
                  isDark,
                ),
                const Divider(height: 32),
              ],
              _buildNavigationRow(
                'Stock Movement History',
                'Log of all bottle removals, returns, and restocks',
                Icons.history_rounded,
                onOpenMovementLogs,
                isDark,
              ),
              const Divider(height: 32),
              _buildNavigationRow(
                'Help & User Documentation Guide',
                'Browse 11 guides on shelf alignment, AI scan, and kiosk use',
                Icons.help_outline_rounded,
                onOpenHelp,
                isDark,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationRow(String title, String subtitle, IconData icon, VoidCallback onTap, bool isDark) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.accent, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.gray),
          ],
        ),
      ),
    );
  }
}
