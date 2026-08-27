import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class SyncStatusScreen extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onOpenSyncQueue;

  const SyncStatusScreen({
    super.key,
    required this.onBack,
    required this.onOpenSyncQueue,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = provider.syncQueue;
    final pendingCount = queue.where((q) => q.status == 'pending').length;

    return ScrollScreen(
      title: 'Cloud Synchronization & Offline Queue',
      subtitle: 'Multi-branch synchronization state between local SQLite and Supabase',
      showBackButton: true,
      onBack: onBack,
      actions: [
        AppButton(
          text: 'Force Cloud Sync Now',
          icon: Icons.cloud_sync_rounded,
          onPressed: provider.forceCloudSync,
          height: 48,
          fontSize: 14,
        ),
      ],
      children: [
        // Sync Health Cards Grid
        Row(
          children: [
            _buildSyncMetricCard(
              'Connection Mode',
              'Online / Synchronized',
              Icons.wifi_rounded,
              AppColors.green,
              isDark,
            ),
            const SizedBox(width: 16),
            _buildSyncMetricCard(
              'Last Cloud Sync Time',
              provider.lastSyncTime != null ? provider.lastSyncTime!.formatTimeAgo() : '5 mins ago',
              Icons.access_time_rounded,
              AppColors.blue,
              isDark,
            ),
            const SizedBox(width: 16),
            _buildSyncMetricCard(
              'Local SQLite Queue',
              '$pendingCount Pending Events',
              Icons.pending_actions_rounded,
              pendingCount > 0 ? AppColors.orange : AppColors.green,
              isDark,
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Branch Synchronization Status Cards
        const Text(
          'Branch Synchronization Status',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        Row(
          children: [
            // San Pablo Status
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('San Pablo (Main Branch)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const StatusChip(status: 'synced', customLabel: 'ONLINE'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRowItem('Local Database Engine', 'SQLite 3 (Embedded)', isDark),
                    _buildRowItem('Cloud Sync Target', 'Supabase (Cloud PostgreSQL)', isDark),
                    _buildRowItem('Heartbeat Latency', '42 ms', isDark),
                    _buildRowItem('Sync Conflict Policy', 'Timestamp-Ordered Audit Log', isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Lipa Status
            Expanded(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Lipa (Secondary Branch)', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        const StatusChip(status: 'synced', customLabel: 'ONLINE'),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRowItem('Local Database Engine', 'SQLite 3 (Embedded)', isDark),
                    _buildRowItem('Cloud Sync Target', 'Supabase (Cloud PostgreSQL)', isDark),
                    _buildRowItem('Heartbeat Latency', '68 ms', isDark),
                    _buildRowItem('Sync Conflict Policy', 'Timestamp-Ordered Audit Log', isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Link to Full Sync Queue
        AppCard(
          onTap: onOpenSyncQueue,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.list_alt_rounded, color: AppColors.accent, size: 28),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inspect SQLite Pending Synchronization Queue',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'View individual event IDs, target collections, retry counts, and sync payloads',
                      style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSyncMetricCard(String title, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: AppCard(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                  const SizedBox(height: 4),
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowItem(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
