import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class SyncStatusScreen extends StatelessWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Synchronization Status'),
        actions: [
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.sync_rounded, size: 22),
            label: const Text('Sync Now'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(140, 48),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Status Banner
            Card(
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
                      child: const Icon(Icons.cloud_done_rounded, color: AppColors.statusGreen, size: 36),
                    ),
                    const SizedBox(width: 20),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Connected to Cloud Services',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkTextPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Local kiosk database is actively synced with remote store inventory.',
                            style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    const StatusBadge(type: StatusBadgeType.synced, large: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Sync Queue & Details
            Row(
              children: [
                _buildSyncMetric('Last Cloud Sync', '2 minutes ago', Icons.schedule_rounded),
                const SizedBox(width: 16),
                _buildSyncMetric('Pending Sync Queue', '0 items', Icons.playlist_add_check_circle_rounded),
                const SizedBox(width: 16),
                _buildSyncMetric('Sync Interval', 'Every 5 mins', Icons.repeat_rounded),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncMetric(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.brandAccent, size: 24),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
