import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Monitoring'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.filter_list_rounded, size: 28),
            tooltip: 'Filter Products',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildInventoryItem(
            name: 'Rose Noir EDP',
            volume: '50 ml',
            sku: 'SKU-RN-50',
            roi: 'Shelf A - Region 1',
            detectedCount: 8,
            threshold: 4,
            status: StatusBadgeType.good,
          ),
          const SizedBox(height: 12),
          _buildInventoryItem(
            name: 'Vanilla Musk EDP',
            volume: '50 ml',
            sku: 'SKU-VM-50',
            roi: 'Shelf B - Region 2',
            detectedCount: 2,
            threshold: 5,
            status: StatusBadgeType.lowStock,
          ),
          const SizedBox(height: 12),
          _buildInventoryItem(
            name: 'Citrus Bloom EDT',
            volume: '100 ml',
            sku: 'SKU-CB-100',
            roi: 'Shelf A - Region 2',
            detectedCount: 1,
            threshold: 3,
            status: StatusBadgeType.misplaced,
          ),
          const SizedBox(height: 12),
          _buildInventoryItem(
            name: 'Amber Wood EDP',
            volume: '75 ml',
            sku: 'SKU-AW-75',
            roi: 'Shelf C - Region 1',
            detectedCount: 12,
            threshold: 6,
            status: StatusBadgeType.good,
          ),
          const SizedBox(height: 12),
          _buildInventoryItem(
            name: 'Oceanic Breeze Cologne',
            volume: '100 ml',
            sku: 'SKU-OB-100',
            roi: 'Shelf D - Region 1',
            detectedCount: 6,
            threshold: 4,
            status: StatusBadgeType.good,
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryItem({
    required String name,
    required String volume,
    required String sku,
    required String roi,
    required int detectedCount,
    required int threshold,
    required StatusBadgeType status,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkSurfaceElevated,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.sanitizer_rounded, color: AppColors.brandAccent, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.darkTextPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '($volume)',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.darkTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Assigned ROI: $roi • $sku',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.darkTextMuted,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$detectedCount bottles',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: status == StatusBadgeType.lowStock
                        ? AppColors.statusRed
                        : AppColors.darkTextPrimary,
                  ),
                ),
                Text(
                  'Min: $threshold',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.darkTextMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            StatusBadge(type: status),
          ],
        ),
      ),
    );
  }
}
