import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Overview'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.refresh_rounded, size: 28),
            tooltip: 'Refresh Data',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Welcome & Quick Summary Banner
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: const Row(
                children: [
                  Icon(Icons.storefront_rounded, color: AppColors.brandAccent, size: 48),
                  SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Otto Scents Shelf Monitoring',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkTextPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Automated computer vision is actively scanning your perfume shelves.',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.darkTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(type: StatusBadgeType.scanning, large: true),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 4 Big Metric Summary Cards (Kiosk-friendly)
            Row(
              children: [
                _buildSummaryCard(
                  title: 'Total In Stock',
                  count: '142',
                  subtitle: 'Across all 4 shelves',
                  color: AppColors.statusGreen,
                  bgColor: AppColors.statusGreenBg,
                  icon: Icons.check_circle_outline_rounded,
                ),
                const SizedBox(width: 16),
                _buildSummaryCard(
                  title: 'Low Stock Items',
                  count: '3',
                  subtitle: 'Needs restocking soon',
                  color: AppColors.statusRed,
                  bgColor: AppColors.statusRedBg,
                  icon: Icons.warning_amber_rounded,
                ),
                const SizedBox(width: 16),
                _buildSummaryCard(
                  title: 'Misplaced Items',
                  count: '2',
                  subtitle: 'Wrong shelf position',
                  color: AppColors.statusOrange,
                  bgColor: AppColors.statusOrangeBg,
                  icon: Icons.move_up_rounded,
                ),
                const SizedBox(width: 16),
                _buildSummaryCard(
                  title: 'Pending Sync',
                  count: '0',
                  subtitle: 'Cloud database is up to date',
                  color: AppColors.brandAccent,
                  bgColor: const Color(0x2638BDF8),
                  icon: Icons.cloud_done_outlined,
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Urgent Attention Section
            const Text(
              'Shelf Status & Recent Alerts',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 14),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    _buildAlertRow(
                      product: 'Vanilla Musk EDP (50ml)',
                      location: 'Shelf B - Region 2',
                      issue: 'Low Stock: Only 2 bottles detected (Threshold: 5)',
                      badgeType: StatusBadgeType.lowStock,
                    ),
                    const Divider(height: 24),
                    _buildAlertRow(
                      product: 'Citrus Bloom EDT (100ml)',
                      location: 'Shelf A - Region 1',
                      issue: 'Misplaced: Found in Oceanic Breeze area',
                      badgeType: StatusBadgeType.misplaced,
                    ),
                    const Divider(height: 24),
                    _buildAlertRow(
                      product: 'Amber Wood EDP (75ml)',
                      location: 'Shelf C - Region 3',
                      issue: 'Stock verified and optimal (12 bottles)',
                      badgeType: StatusBadgeType.good,
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

  static Widget _buildSummaryCard({
    required String title,
    required String count,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.darkTextSecondary,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            Text(
              count,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.darkTextMuted,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildAlertRow({
    required String product,
    required String location,
    required String issue,
    required StatusBadgeType badgeType,
  }) {
    return Row(
      children: [
        StatusBadge(type: badgeType),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$location • $issue',
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.darkTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
