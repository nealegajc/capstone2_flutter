import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class RestockScreen extends StatelessWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Restock Management & Receiving'),
        actions: [
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.check, size: 22),
            label: const Text('Confirm Restock Batch'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(180, 48),
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
            const Text(
              'Delivery & Restock Verification',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Compare expected incoming batch quantities against camera computer vision detections.',
              style: TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
            ),
            const SizedBox(height: 20),

            _buildRestockCard(
              product: 'Vanilla Musk EDP (50ml)',
              expected: 10,
              detected: 10,
              match: true,
            ),
            const SizedBox(height: 12),
            _buildRestockCard(
              product: 'Citrus Bloom EDT (100ml)',
              expected: 6,
              detected: 5,
              match: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestockCard({
    required String product,
    required int expected,
    required int detected,
    required bool match,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: match ? AppColors.statusGreenBg : AppColors.statusOrangeBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                match ? Icons.verified_rounded : Icons.pending_actions_rounded,
                color: match ? AppColors.statusGreen : AppColors.statusOrange,
                size: 30,
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Expected Delivery: $expected units • Computer Vision Count: $detected units',
                    style: const TextStyle(
                      color: AppColors.darkTextSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            StatusBadge(
              type: match ? StatusBadgeType.synced : StatusBadgeType.needsVerification,
              customLabel: match ? 'Verified Match' : 'Discrepancy (1 Missing)',
            ),
          ],
        ),
      ),
    );
  }
}
