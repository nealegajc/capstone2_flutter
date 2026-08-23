import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Owner Guide & FAQs'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          _buildFaqItem(
            question: 'How does the Smart Shelf count my perfume bottles?',
            answer:
                'The camera above each shelf captures snapshots at scheduled intervals. Our AI computer vision model detects the perfume bottles within their designated shelf partitions (ROIs) and automatically updates your counts.',
            icon: Icons.camera_enhance_rounded,
          ),
          const SizedBox(height: 12),
          _buildFaqItem(
            question: 'What do the color badges mean?',
            answer:
                '• Green (Normal / Synced): Stock count is healthy and cloud data is up to date.\n• Red (Low Stock / Alert): Quantity is below your safety threshold or a scan requires attention.\n• Orange (Pending / Misplaced): A bottle is in the wrong region, or awaiting synchronization.',
            icon: Icons.palette_rounded,
          ),
          const SizedBox(height: 12),
          _buildFaqItem(
            question: 'What should I do when receiving a new restock delivery?',
            answer:
                'Go to the "Restock Verification" screen on the left menu. Place the incoming bottles on the shelf and verify that the detected count matches your packing slip before tapping "Confirm Restock Batch".',
            icon: Icons.move_to_inbox_rounded,
          ),
          const SizedBox(height: 12),
          _buildFaqItem(
            question: 'What happens if the internet goes down?',
            answer:
                'The kiosk runs 100% locally on this terminal. It continues monitoring, counting, and alerting you without internet. All data will automatically sync to the cloud once connectivity resumes.',
            icon: Icons.wifi_off_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFaqItem({
    required String question,
    required String answer,
    required IconData icon,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.brandAccent, size: 26),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.darkTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    answer,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextSecondary,
                      height: 1.5,
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
