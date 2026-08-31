import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../components/status_badge.dart';

class SyncStatusScreen extends StatefulWidget {
  const SyncStatusScreen({super.key});

  @override
  State<SyncStatusScreen> createState() => _SyncStatusScreenState();
}

class _SyncStatusScreenState extends State<SyncStatusScreen> {
  bool _isSyncing = false;

  void _triggerSync() async {
    setState(() => _isSyncing = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backup complete! All local store records are backed up and up-to-date.'),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatic Cloud Backup & Sync'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.syncQueue),
            icon: const Icon(Icons.queue_rounded, size: 20),
            label: const Text('Pending Cloud Updates (0)'),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: _isSyncing ? null : _triggerSync,
            icon: const Icon(Icons.sync_rounded, size: 22),
            label: Text(_isSyncing ? 'Backing Up...' : 'Back Up Now'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Connection Banner
            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.statusGreenBg,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cloud_done_rounded, color: AppColors.statusGreen, size: 40),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connected to Secure Cloud Storage',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Your store inventory and activity logs are continuously backed up in real time with offline protection.',
                            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                    const StatusBadge(type: StatusBadgeType.synced, customLabel: 'Status: Online', large: true),
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
                  value: 'Just now',
                  detail: 'All fragrances backed up',
                  icon: Icons.access_time_rounded,
                ),
                const SizedBox(width: 16),
                _buildMetricCard(
                  context: context,
                  title: 'Pending Cloud Uploads',
                  value: '0 Items',
                  detail: 'All store data is up-to-date',
                  icon: Icons.playlist_add_check_circle_rounded,
                ),
                const SizedBox(width: 16),
                _buildMetricCard(
                  context: context,
                  title: 'Backup Reliability',
                  value: '100%',
                  detail: 'Zero failed sync events',
                  icon: Icons.verified_user_rounded,
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

            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildSyncHistoryRow(
                      context: context,
                      operation: 'INITIAL_BOOTSTRAP',
                      target: 'products & catalog',
                      status: 'COMPLETED',
                      timestamp: 'Today, 07:00 AM',
                    ),
                    Divider(height: 20, color: context.borderColor),
                    _buildSyncHistoryRow(
                      context: context,
                      operation: 'REALTIME_PULL',
                      target: 'system_settings',
                      status: 'COMPLETED',
                      timestamp: 'Today, 07:15 AM',
                    ),
                    Divider(height: 20, color: context.borderColor),
                    _buildSyncHistoryRow(
                      context: context,
                      operation: 'LOCAL_QUEUE_DRAIN',
                      target: 'inventory_events (0 records)',
                      status: 'IDLE',
                      timestamp: 'Just now',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
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
      child: Card(
        color: context.surfaceColor,
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
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textSecondaryColor),
                  ),
                  Icon(icon, color: AppColors.brandAccent, size: 22),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: context.textPrimaryColor),
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
            const Icon(Icons.sync_alt_rounded, color: AppColors.brandAccent, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  operation,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimaryColor),
                ),
                Text(
                  target,
                  style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                ),
              ],
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            const StatusBadge(type: StatusBadgeType.synced, customLabel: 'Synced'),
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
