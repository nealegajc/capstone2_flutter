import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../components/status_badge.dart';

class ShelfCheckHistoryScreen extends StatelessWidget {
  const ShelfCheckHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Check Monitoring History'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.calendar_month_outlined, size: 28),
            tooltip: 'Filter by Date',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildHistoryCard(
            context: context,
            timestamp: 'Today, 08:15 AM (Manual Trigger)',
            bottlesDetected: 143,
            itemsNeedingReview: 0,
            statusLabel: 'Completed',
            statusType: StatusBadgeType.good,
            summaryText: 'All 3 shelf camera layers scanned. 60/60 SKUs verified via Cap OCR.',
          ),
          const SizedBox(height: 12),
          _buildHistoryCard(
            context: context,
            timestamp: 'Today, 07:15 AM (Routine Scan)',
            bottlesDetected: 143,
            itemsNeedingReview: 0,
            statusLabel: 'Cloud Synced',
            statusType: StatusBadgeType.synced,
            summaryText: 'Scan verified and synchronized with Supabase cloud database.',
          ),
          const SizedBox(height: 12),
          _buildHistoryCard(
            context: context,
            timestamp: 'Today, 06:15 AM (Opening Check)',
            bottlesDetected: 142,
            itemsNeedingReview: 1,
            statusLabel: 'Needs Review',
            statusType: StatusBadgeType.needsVerification,
            summaryText: 'Layer B SKU BA3 required second OCR verification pass.',
          ),
          const SizedBox(height: 12),
          _buildHistoryCard(
            context: context,
            timestamp: 'Yesterday, 06:00 PM (Closing Check)',
            bottlesDetected: 144,
            itemsNeedingReview: 0,
            statusLabel: 'Completed',
            statusType: StatusBadgeType.good,
            summaryText: 'Closing shift inventory verified across 3 camera layers.',
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard({
    required BuildContext context,
    required String timestamp,
    required int bottlesDetected,
    required int itemsNeedingReview,
    required String statusLabel,
    required StatusBadgeType statusType,
    required String summaryText,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.camera_alt_outlined, color: AppColors.brandAccent, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    timestamp,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    summaryText,
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$bottlesDetected Bottles Counted • $itemsNeedingReview Discrepancies',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: itemsNeedingReview > 0 ? AppColors.statusOrange : AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            StatusBadge(type: statusType, customLabel: statusLabel),
          ],
        ),
      ),
    );
  }
}
