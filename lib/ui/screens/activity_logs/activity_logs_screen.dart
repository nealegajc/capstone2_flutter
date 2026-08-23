import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class ActivityLogsScreen extends StatelessWidget {
  const ActivityLogsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('System Activity Logs & Reports'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.file_download_outlined, size: 28),
            tooltip: 'Export CSV Report',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildLogEntry(
            action: 'Automated Camera Scan Completed',
            details: 'Routine detection cycle finished with 4 active shelf zones verified.',
            timestamp: 'Today, 07:15 AM',
            icon: Icons.radar_rounded,
            color: AppColors.brandAccent,
          ),
          const SizedBox(height: 12),
          _buildLogEntry(
            action: 'Store Owner PIN Authenticated',
            details: 'Successful kiosk unlock at terminal 01.',
            timestamp: 'Today, 07:00 AM',
            icon: Icons.lock_open_rounded,
            color: AppColors.statusGreen,
          ),
          const SizedBox(height: 12),
          _buildLogEntry(
            action: 'Cloud Database Synchronization',
            details: '142 inventory records synced with remote Firestore server.',
            timestamp: 'Yesterday, 10:30 PM',
            icon: Icons.cloud_sync_rounded,
            color: AppColors.statusBlue,
          ),
          const SizedBox(height: 12),
          _buildLogEntry(
            action: 'Stock Movement Logged',
            details: 'Vanilla Musk EDP reduced from 3 to 2 bottles.',
            timestamp: 'Yesterday, 06:12 PM',
            icon: Icons.trending_down_rounded,
            color: AppColors.statusOrange,
          ),
        ],
      ),
    );
  }

  Widget _buildLogEntry({
    required String action,
    required String details,
    required String timestamp,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    action,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    details,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.darkTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              timestamp,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.darkTextMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
