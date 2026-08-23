import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts & Shelf Events'),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.clear_all_rounded, size: 24),
            label: const Text('Acknowledge All'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildAlertItem(
            title: 'Low Stock Alert: Vanilla Musk EDP',
            description: 'Detected count is 2, which is below the minimum threshold of 5.',
            time: '10 mins ago',
            type: StatusBadgeType.lowStock,
          ),
          const SizedBox(height: 12),
          _buildAlertItem(
            title: 'Misplaced Product Detected',
            description: 'Citrus Bloom bottle placed in Oceanic Breeze shelf partition.',
            time: '32 mins ago',
            type: StatusBadgeType.misplaced,
          ),
          const SizedBox(height: 12),
          _buildAlertItem(
            title: 'Camera Scan Completed Successfully',
            description: 'Routine vision check completed across 4 regions with 100% confidence.',
            time: '1 hour ago',
            type: StatusBadgeType.good,
          ),
          const SizedBox(height: 12),
          _buildAlertItem(
            title: 'Camera Frame Occlusion Resolved',
            description: 'Temporary obstruction cleared in Shelf Zone B.',
            time: '3 hours ago',
            type: StatusBadgeType.alert,
          ),
        ],
      ),
    );
  }

  Widget _buildAlertItem({
    required String title,
    required String description,
    required String time,
    required StatusBadgeType type,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge(type: type),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkTextPrimary,
                        ),
                      ),
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.darkTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextSecondary,
                    ),
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
