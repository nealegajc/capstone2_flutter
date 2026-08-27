import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';

class ActivityLogsScreen extends ConsumerWidget {
  const ActivityLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final logsAsync = ref.watch(systemActivityLogsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('System Activity & Audit Logs'),
        actions: [
          IconButton(
            onPressed: () {
              ref.invalidate(systemActivityLogsProvider(branch));
            },
            icon: const Icon(Icons.refresh_rounded, size: 26),
            tooltip: 'Refresh Logs',
          ),
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Audit logs exported successfully as CSV.'),
                  backgroundColor: AppColors.brandAccent,
                ),
              );
            },
            icon: const Icon(Icons.file_download_outlined, size: 26),
            tooltip: 'Export Audit Log',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.list_alt_rounded, size: 64, color: context.textMutedColor),
                  const SizedBox(height: 16),
                  Text(
                    'No Audit Logs Found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'All user logins, scans, restocks, and system operations will be logged here.',
                    style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final typeUpper = log.type.toUpperCase();

              IconData icon = Icons.info_outline_rounded;
              Color color = AppColors.brandAccent;

              if (typeUpper.contains('LOGIN') || typeUpper.contains('USER_AUTH')) {
                icon = Icons.lock_open_rounded;
                color = AppColors.statusGreen;
              } else if (typeUpper.contains('AUTH_FAILURE') || typeUpper.contains('SECURITY_LOCKOUT')) {
                icon = Icons.gpp_bad_rounded;
                color = AppColors.statusRed;
              } else if (typeUpper.contains('SECURITY') || typeUpper.contains('PIN')) {
                icon = Icons.security_rounded;
                color = AppColors.statusOrange;
              } else if (typeUpper.contains('SCAN') || typeUpper.contains('VISION') || typeUpper.contains('SNAPSHOT')) {
                icon = Icons.radar_rounded;
                color = AppColors.brandGold;
              } else if (typeUpper.contains('STREAM')) {
                icon = Icons.videocam_rounded;
                color = AppColors.brandAccent;
              } else if (typeUpper.contains('SYNC')) {
                icon = Icons.cloud_sync_rounded;
                color = AppColors.statusGreen;
              } else if (typeUpper.contains('PRODUCT')) {
                icon = Icons.inventory_2_rounded;
                color = AppColors.brandAccent;
              } else if (typeUpper.contains('RESTOCK')) {
                icon = Icons.local_shipping_rounded;
                color = AppColors.statusGreen;
              } else if (typeUpper.contains('ALERT')) {
                icon = Icons.warning_amber_rounded;
                color = AppColors.statusOrange;
              } else if (typeUpper.contains('THEME')) {
                icon = Icons.palette_outlined;
                color = AppColors.brandAccent;
              } else if (typeUpper.contains('ROI')) {
                icon = Icons.crop_free_rounded;
                color = AppColors.brandGold;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildActivityLogTile(
                  context: context,
                  activity: log.type.replaceAll('_', ' ').toUpperCase(),
                  detail: log.description,
                  timestamp: log.formattedTimestamp,
                  user: log.user,
                  icon: icon,
                  color: color,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading activity logs: $err')),
      ),
    );
  }

  Widget _buildActivityLogTile({
    required BuildContext context,
    required String activity,
    required String detail,
    required String timestamp,
    required String user,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: context.isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        activity,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        timestamp,
                        style: TextStyle(fontSize: 12, color: context.textMutedColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Initiated by: $user',
                    style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
