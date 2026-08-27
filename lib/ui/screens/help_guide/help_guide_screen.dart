import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';

class HelpGuideScreen extends StatelessWidget {
  const HelpGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Owner Help & Troubleshooting Guide'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Beginner-Friendly Kiosk Guide',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Simple explanations for operating your Otto Scents 3-Camera Smart Shelf system.',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 20),

          // 1. Stopped Scan Safeguard
          _buildFaqCard(
            context: context,
            question: 'Why did the inventory scan stop (Insufficient Image Quality)?',
            answer:
                'If there is strong glare, sudden dark shadows, or if a customer’s hand blocks the camera during capture, the AI safety check halts the scan. It retries up to 3 times. Check that the shelf lights are on and nothing is obstructing the camera, then tap "Scan Shelf Now" on the Dashboard.',
            icon: Icons.high_quality_rounded,
          ),
          const SizedBox(height: 12),

          // 2. Misplaced Product Alert
          _buildFaqCard(
            context: context,
            question: 'What is a "Misplaced" product alert?',
            answer:
                'Each perfume SKU is assigned to a specific shelf layer and slot (e.g. AA1 on Layer A Top). If a customer picks up a bottle and returns it into the wrong layer, the camera detects the cap code in the wrong spot and displays an orange "Misplaced" badge. Move the bottle back to its assigned shelf section to clear the alert.',
            icon: Icons.move_up_rounded,
          ),
          const SizedBox(height: 12),

          // 3. Low Stock Alert
          _buildFaqCard(
            context: context,
            question: 'When is a "Low Stock" alert triggered?',
            answer:
                'Whenever the computer vision detected bottle count on a shelf drops at or below your safety threshold (2 bottles), a red "Low Stock" alert appears. You can log an incoming delivery via "Restock Management".',
            icon: Icons.warning_amber_rounded,
          ),
          const SizedBox(height: 12),

          // 4. Offline Operation
          _buildFaqCard(
            context: context,
            question: 'What happens when the retail store loses internet connection?',
            answer:
                'The kiosk runs completely offline! It stores all inventory detections, movement logs, and scans in a secure local database (SQLite). You can continue using all kiosk features normally.',
            icon: Icons.wifi_off_rounded,
          ),
          const SizedBox(height: 12),

          // 5. Pending Synchronization & Restoration
          _buildFaqCard(
            context: context,
            question: 'How does cloud synchronization restore when internet returns?',
            answer:
                'As soon as internet connection is detected, the kiosk automatically uploads all buffered events from local SQLite to your Supabase cloud database. The status badge will switch back to green "Synced".',
            icon: Icons.cloud_sync_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFaqCard({
    required BuildContext context,
    required String question,
    required String answer,
    required IconData icon,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.brandAccent, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    question,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    answer,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondaryColor,
                      height: 1.4,
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
