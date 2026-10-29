import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class SyncStatusScreen extends ConsumerStatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  ConsumerState<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends ConsumerState<SyncStatusScreen> {
  bool _isManualSyncing = false;

  void _triggerSync() async {
    setState(() => _isManualSyncing = true);
    try {
      final syncService = ref.read(syncServiceProvider);
      final stats = await syncService.forceSyncNow('San Pablo');
      ref.invalidate(liveInventoryProvider('San Pablo'));
      ref.invalidate(dashboardStatsProvider('San Pablo'));
      ref.invalidate(syncQueueListProvider('San Pablo'));
      ref.invalidate(systemActivityLogsProvider('San Pablo'));

      if (mounted) {
        final total = stats.values.fold<int>(0, (sum, count) => sum + count);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Full cloud backup complete! Uploaded $total records (${stats['products'] ?? 0} products, ${stats['inventory_records'] ?? 0} inventory items, ${stats['sales_records'] ?? 0} sales).',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✗ Cloud backup failed: $errMsg'),
            backgroundColor: AppColors.statusRed,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Details',
              textColor: Colors.white,
              onPressed: () => _showErrorDialog(errMsg),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isManualSyncing = false);
    }
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: AppColors.statusRed,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Supabase Cloud Backup Issue',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.statusRedBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.statusRed.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  error,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.statusRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Troubleshooting Steps:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              _buildBullet(
                '1. Supabase Free Tier Auto-Pause: Free projects are paused after 7 days of inactivity. Go to supabase.com/dashboard and click "Restore project" / "Unpause".',
              ),
              const SizedBox(height: 6),
              _buildBullet(
                '2. Internet Connectivity: Ensure this kiosk is connected to Wi-Fi or Ethernet.',
              ),
              const SizedBox(height: 6),
              _buildBullet(
                '3. Offline Safety: All local products, sales, and inventory remain 100% safe in SQLite and will sync as soon as cloud connectivity is restored.',
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncService = ref.watch(syncServiceProvider);
    final isSyncing = _isManualSyncing || syncService.isSyncing;
    final pendingCount = syncService.pendingCount;
    final isCloudUp = syncService.isOnline && syncService.lastError == null;

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
                    color: AppColors.statusGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.cloud_sync_rounded,
                    color: AppColors.statusGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cloud Backup & Sync',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Safely backs up all sales, stock scans, and restock records to the secure cloud.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutePaths.syncQueue),
                  icon: const Icon(Icons.cloud_upload_outlined, size: 18),
                  label: Text('Pending Uploads ($pendingCount)'),
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
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: isSyncing ? null : _triggerSync,
                  icon: isSyncing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.sync_rounded, size: 20),
                  label: Text(isSyncing ? 'Backing Up...' : 'Back Up Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Sync Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Connection Banner
                  Container(
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isCloudUp
                            ? AppColors.statusGreen.withValues(alpha: 0.3)
                            : AppColors.statusRed.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: isCloudUp
                                  ? AppColors.statusGreenBg
                                  : AppColors.statusRedBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isCloudUp
                                  ? Icons.cloud_done_rounded
                                  : Icons.cloud_off_rounded,
                              color: isCloudUp
                                  ? AppColors.statusGreen
                                  : AppColors.statusRed,
                              size: 40,
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isCloudUp
                                      ? 'Connected to Secure Cloud Storage'
                                      : 'Supabase Cloud Unreachable / Paused',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isCloudUp
                                      ? 'Your store inventory and activity logs are continuously backed up in real time with offline protection.'
                                      : (syncService.lastError ??
                                            'Cannot establish connection to Supabase Cloud. Verify network or unpause project in dashboard.'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: isCloudUp
                                        ? context.textSecondaryColor
                                        : AppColors.statusRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          StatusBadge(
                            type: isCloudUp
                                ? StatusBadgeType.synced
                                : StatusBadgeType.alert,
                            customLabel: isCloudUp
                                ? 'Status: Online'
                                : 'Status: Offline / Paused',
                            large: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sync Information Grid
                  Row(
                    children: [
                      _buildMetricCard(
                        context: context,
                        title: 'Last Successful Backup',
                        value: syncService.lastSyncTime != null
                            ? DateFormat('hh:mm a')
                                  .format(syncService.lastSyncTime!)
                            : 'No Backup Recorded',
                        detail: syncService.lastSyncTime != null
                            ? DateFormat('MMM dd, yyyy')
                                  .format(syncService.lastSyncTime!)
                            : 'Tap "Back Up Now" to synchronize',
                        icon: Icons.access_time_rounded,
                      ),
                      const SizedBox(width: 16),
                      _buildMetricCard(
                        context: context,
                        title: 'Pending Cloud Uploads',
                        value: '$pendingCount Items',
                        detail: pendingCount == 0
                            ? 'All store data is up-to-date'
                            : 'Queued for automatic background push',
                        icon: Icons.playlist_add_check_circle_rounded,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Consumer(
                          builder: (context, ref, _) {
                            final prodsAsync = ref.watch(
                              masterProductsProvider,
                            );
                            final regionsAsync = ref.watch(
                              shelfRegionsProvider('San Pablo'),
                            );
                            final prodCount =
                                prodsAsync.valueOrNull?.length ?? 0;
                            final regionCount =
                                regionsAsync.valueOrNull?.length ?? 0;
                            return Container(
                              decoration: BoxDecoration(
                                color: context.surfaceColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Local SQLite Store',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: context.textSecondaryColor,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.all(6),
                                          decoration: BoxDecoration(
                                            color: AppColors.brandAccent
                                                .withValues(
                                                  alpha: context.isDark
                                                      ? 0.15
                                                      : 0.1,
                                                ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.storage_rounded,
                                            color: AppColors.brandAccent,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      prodCount > 0
                                          ? '$prodCount SKUs Cached'
                                          : 'Offline Cache Ready',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      regionCount > 0
                                          ? '$regionCount shelf slots configured'
                                          : 'Local SQLite database active',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.textMutedColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Recent Synchronization History
                  Text(
                    'Recent Cloud Sync Events',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Consumer(
                    builder: (context, ref, _) {
                      final logsAsync = ref.watch(
                        systemActivityLogsProvider('San Pablo'),
                      );
                      return Container(
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: logsAsync.when(
                            data: (logs) {
                              final syncLogs = logs
                                  .where(
                                    (l) =>
                                        l.type.contains('SYNC') ||
                                        l.type.contains('BACKUP') ||
                                        l.type.contains('CLOUD') ||
                                        l.type.contains('STARTUP'),
                                  )
                                  .take(5)
                                  .toList();

                              if (syncLogs.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'No cloud backup events recorded yet. Press "Back Up Now" above to sync all records.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              return Column(
                                children: [
                                  for (int i = 0; i < syncLogs.length; i++) ...[
                                    if (i > 0)
                                      Divider(
                                        height: 20,
                                        color: context.borderColor,
                                      ),
                                    _buildSyncHistoryRow(
                                      context: context,
                                      operation: syncLogs[i].type,
                                      target: syncLogs[i].description,
                                      status:
                                          syncLogs[i].type.contains('FAILED')
                                          ? 'FAILED'
                                          : 'COMPLETED',
                                      timestamp: syncLogs[i].formattedTimestamp,
                                    ),
                                  ],
                                ],
                              );
                            },
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            error: (_, _) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Unable to load sync history',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: context.textMutedColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required String detail,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.brandAccent.withValues(
                        alpha: context.isDark ? 0.15 : 0.1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: AppColors.brandAccent, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncHistoryRow({
    required BuildContext context,
    required String operation,
    required String target,
    required String status,
    required String timestamp,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(
              Icons.sync_alt_rounded,
              color: AppColors.brandAccent,
              size: 20,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operation,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: context.textPrimaryColor,
                  ),
                ),
                Text(
                  target,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            StatusBadge(
              type: status == 'FAILED'
                  ? StatusBadgeType.alert
                  : (status == 'PENDING'
                        ? StatusBadgeType.pendingSync
                        : StatusBadgeType.synced),
              customLabel: status == 'FAILED'
                  ? 'Failed'
                  : (status == 'PENDING' ? 'Pending' : 'Synced'),
            ),
            const SizedBox(height: 4),
            Text(
              timestamp,
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
          ],
        ),
      ],
    );
  }
}
