import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';

class ActivityLogsScreen extends ConsumerStatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  ConsumerState<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends ConsumerState<ActivityLogsScreen> {
  static const _categories = [
    'All',
    'Sales',
    'Inventory',
    'Vision & Scans',
    'Security & Auth',
    'System & Sync',
  ];

  String _selectedCategory = 'All';

  Future<void> _confirmClearLogs(BuildContext context, String branch) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: AppColors.statusRed,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              'Clear All Logs?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all activity logs for $branch? This will remove local records and propagate the deletion to Supabase.',
          style: TextStyle(color: context.textSecondaryColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.textSecondaryColor),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All Logs'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await SqliteService.instance.clearAllSystemLogs(branch);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All system activity logs cleared.'),
            backgroundColor: AppColors.statusRed,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final logsAsync = ref.watch(systemActivityLogsProvider(branch));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-page command ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.history_edu_rounded,
                    color: AppColors.brandAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Activity History',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Record of staff logins, bottle scans, stock restocks, and daily sales.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () async {
                    await ref
                        .read(syncServiceProvider)
                        .pullLatestSystemLogs(limit: 200);
                    ref.invalidate(systemActivityLogsProvider(branch));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 22),
                  tooltip: 'Sync and Refresh Logs',
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final logs = logsAsync.valueOrNull;
                    if (logs == null || logs.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No activity logs available to export.',
                          ),
                          backgroundColor: AppColors.statusOrange,
                        ),
                      );
                      return;
                    }
                    try {
                      final file = await CsvExportService.instance
                          .exportSystemLogsCsv(logs, branch: branch);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Exported ${logs.length} logs to ${file.path}',
                            ),
                            backgroundColor: AppColors.brandAccent,
                            duration: const Duration(seconds: 4),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Failed to export CSV: $e'),
                            backgroundColor: AppColors.statusRed,
                          ),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('Export CSV'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    side: BorderSide(color: context.borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: (logsAsync.valueOrNull?.isNotEmpty ?? false)
                      ? () => _confirmClearLogs(context, branch)
                      : null,
                  icon: const Icon(
                    Icons.delete_sweep_rounded,
                    size: 18,
                    color: AppColors.statusRed,
                  ),
                  label: const Text(
                    'Clear Logs',
                    style: TextStyle(color: AppColors.statusRed),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    side: BorderSide(
                      color: AppColors.statusRed.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Category Filter Bar
          logsAsync.when(
            data: (allLogs) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceColor.withValues(alpha: 0.7),
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected = _selectedCategory == cat;
                    final count = cat == 'All'
                        ? allLogs.length
                        : allLogs.where((l) => l.category == cat).length;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        selected: isSelected,
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(cat),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : context.borderColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : context.textSecondaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        selectedColor: AppColors.brandAccent,
                        backgroundColor: context.surfaceColor,
                        labelStyle: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : context.textPrimaryColor,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.brandAccent
                                : context.borderColor,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _selectedCategory = cat;
                          });
                        },
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),

          // Log List View
          Expanded(
            child: logsAsync.when(
              data: (allLogs) {
                if (allLogs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.list_alt_rounded,
                          size: 64,
                          color: context.textMutedColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Audit Logs Found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'All user logins, scans, restocks, and system operations will be logged here.',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final filteredLogs = _selectedCategory == 'All'
                    ? allLogs
                    : allLogs
                          .where((l) => l.category == _selectedCategory)
                          .toList();

                if (filteredLogs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.filter_alt_off_rounded,
                          size: 48,
                          color: context.textMutedColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No "$_selectedCategory" Logs Found',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Select another category to view related activity records.',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(24),
                  itemCount: filteredLogs.length,
                  itemBuilder: (context, index) {
                    final log = filteredLogs[index];
                    final typeUpper = log.type.toUpperCase();

                    IconData icon = Icons.info_outline_rounded;
                    Color color = AppColors.brandAccent;

                    if (typeUpper.contains('LOGIN') ||
                        typeUpper.contains('USER_AUTH')) {
                      icon = Icons.lock_open_rounded;
                      color = AppColors.statusGreen;
                    } else if (typeUpper.contains('AUTH_FAILURE') ||
                        typeUpper.contains('SECURITY_LOCKOUT')) {
                      icon = Icons.gpp_bad_rounded;
                      color = AppColors.statusRed;
                    } else if (typeUpper.contains('SECURITY') ||
                        typeUpper.contains('PIN')) {
                      icon = Icons.security_rounded;
                      color = AppColors.statusOrange;
                    } else if (typeUpper.contains('SCAN') ||
                        typeUpper.contains('VISION') ||
                        typeUpper.contains('SNAPSHOT')) {
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
                    } else if (typeUpper.contains('SALE')) {
                      icon = Icons.point_of_sale_rounded;
                      color = const Color(0xFF10B981);
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
                      child: Dismissible(
                        key: Key(log.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          decoration: BoxDecoration(
                            color: AppColors.statusRed,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Swipe to Delete',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                        onDismissed: (_) async {
                          await SqliteService.instance.deleteSystemLog(
                            log.id,
                            enqueueSync: true,
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Deleted log: ${log.description.isNotEmpty ? log.description : log.type}',
                                ),
                                backgroundColor: AppColors.brandAccent,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        child: _buildActivityLogTile(
                          context: context,
                          activity: log.type.replaceAll('_', ' ').toUpperCase(),
                          detail: log.description,
                          timestamp: log.formattedTimestamp,
                          user: log.user,
                          icon: icon,
                          color: color,
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading activity logs: $err')),
            ),
          ),
        ],
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
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
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
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          activity,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: color,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: context.textMutedColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            timestamp,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textMutedColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 14,
                        color: context.textSecondaryColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Initiated by: $user',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
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
