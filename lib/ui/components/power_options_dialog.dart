import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/system_power_service.dart';
import '../../providers/system_power_provider.dart';

/// Modal dialog consolidating all terminal power and restart actions:
/// 1. Relaunch Software Process
/// 2. Reboot Kiosk OS
/// 3. Shut Down Kiosk
///
/// All actions are protected by secondary safety confirmation dialogs to prevent
/// accidental triggers on touchscreens.
class PowerOptionsModalDialog extends ConsumerWidget {
  final Future<void> Function()? onRelaunchApp;
  final void Function()? onRestartSystem;
  final void Function()? onShutdownSystem;

  const PowerOptionsModalDialog({
    super.key,
    this.onRelaunchApp,
    this.onRestartSystem,
    this.onShutdownSystem,
  });

  /// Displays the [PowerOptionsModalDialog] as a barrier-dismissible modal.
  static Future<void> show(
    BuildContext context, {
    Future<void> Function()? onRelaunchApp,
    void Function()? onRestartSystem,
    void Function()? onShutdownSystem,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      useRootNavigator: true,
      builder: (_) => PowerOptionsModalDialog(
        onRelaunchApp: onRelaunchApp,
        onRestartSystem: onRestartSystem,
        onShutdownSystem: onShutdownSystem,
      ),
    );
  }

  Future<void> _handleRelaunch(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        key: const Key('dialog_confirm_relaunch'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: context.surfaceColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(
                  alpha: context.isDark ? 0.2 : 0.15,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.restart_alt_rounded,
                color: AppColors.brandAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirm Software Relaunch',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'This will restart the Otto Scents kiosk software process immediately. Any in-progress scans will be finalized.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            key: const Key('btn_cancel_relaunch'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_relaunch'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Relaunch Now',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      if (onRelaunchApp != null) {
        await onRelaunchApp!();
      } else {
        await SystemPowerService.instance.relaunchApp();
      }
    }
  }

  Future<void> _handleReboot(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        key: const Key('dialog_confirm_reboot'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: context.surfaceColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusOrange.withValues(
                  alpha: context.isDark ? 0.2 : 0.15,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.sync_rounded,
                color: AppColors.statusOrange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirm System Reboot',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'This will reboot the physical kiosk hardware. A 15-second cancelable countdown will begin before the Mini PC restarts.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            key: const Key('btn_cancel_reboot'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_reboot'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusOrange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Reboot Kiosk',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      if (onRestartSystem != null) {
        onRestartSystem!();
      } else {
        ref.read(systemRestartProvider.notifier).startCountdown(
          action: SystemPowerAction.restart,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Reboot countdown active. See 15-second banner at top of screen.',
          ),
          backgroundColor: AppColors.statusOrange,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _handleShutdown(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        key: const Key('dialog_confirm_shutdown'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: context.surfaceColor,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withValues(
                  alpha: context.isDark ? 0.2 : 0.15,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.power_settings_new_rounded,
                color: AppColors.statusRed,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Confirm Kiosk Shutdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(
          'This will safely shut down and power off the Mini PC hardware. A 15-second cancelable countdown will begin. Manual power button press is required to turn back on.',
          style: TextStyle(
            fontSize: 14,
            color: context.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        actions: [
          TextButton(
            key: const Key('btn_cancel_shutdown'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: context.textSecondaryColor,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('btn_confirm_shutdown'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Shut Down Kiosk',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      Navigator.of(context).pop();
      if (onShutdownSystem != null) {
        onShutdownSystem!();
      } else {
        ref.read(systemRestartProvider.notifier).startCountdown(
          action: SystemPowerAction.shutdown,
        );
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Shutdown countdown active. See 15-second banner at top of screen.',
          ),
          backgroundColor: AppColors.statusRed,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildActionCard({
    required BuildContext context,
    required Key key,
    required IconData icon,
    required Color iconColor,
    required Color iconBgColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: context.borderColor.withValues(alpha: 0.8),
              width: 1.2,
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: context.textSecondaryColor,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      key: const Key('dialog_power_options'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.statusRed.withValues(
                      alpha: context.isDark ? 0.2 : 0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.power_settings_new_rounded,
                    color: AppColors.statusRed,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Power & Restart Options',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select an action below. All actions require confirmation.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('btn_close_power_dialog'),
                  constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                  iconSize: 28,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.textSecondaryColor,
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Action Card 1: Relaunch Software Process
            _buildActionCard(
              context: context,
              key: const Key('action_card_relaunch_software'),
              icon: Icons.restart_alt_rounded,
              iconColor: AppColors.brandAccent,
              iconBgColor: AppColors.brandAccent.withValues(
                alpha: context.isDark ? 0.2 : 0.1,
              ),
              title: 'Relaunch Software Process',
              subtitle:
                  'Restarts the Flutter kiosk UI process immediately without restarting the OS.',
              onTap: () => _handleRelaunch(context, ref),
            ),
            const SizedBox(height: 12),

            // Action Card 2: Reboot Kiosk OS
            _buildActionCard(
              context: context,
              key: const Key('action_card_reboot_os'),
              icon: Icons.sync_rounded,
              iconColor: AppColors.statusOrange,
              iconBgColor: AppColors.statusOrange.withValues(
                alpha: context.isDark ? 0.2 : 0.1,
              ),
              title: 'Reboot Kiosk OS',
              subtitle:
                  'Safely restarts the Mini PC hardware and re-initializes all USB hubs and cameras.',
              onTap: () => _handleReboot(context, ref),
            ),
            const SizedBox(height: 12),

            // Action Card 3: Shut Down Kiosk
            _buildActionCard(
              context: context,
              key: const Key('action_card_shutdown_kiosk'),
              icon: Icons.power_settings_new_rounded,
              iconColor: AppColors.statusRed,
              iconBgColor: AppColors.statusRed.withValues(
                alpha: context.isDark ? 0.2 : 0.1,
              ),
              title: 'Shut Down Kiosk',
              subtitle:
                  'Safely powers off the Mini PC hardware. Manual power button required to turn on.',
              onTap: () => _handleShutdown(context, ref),
            ),
            const SizedBox(height: 20),

            // Cancel / Dismiss button
            SizedBox(
              width: double.infinity,
              height: 64,
              child: OutlinedButton(
                key: const Key('btn_dismiss_power_dialog'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  side: BorderSide(color: context.borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
