import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../components/status_badge.dart';

class ReceivingVerificationScreen extends StatefulWidget {
  const ReceivingVerificationScreen({super.key});

  @override
  State<ReceivingVerificationScreen> createState() => _ReceivingVerificationScreenState();
}

class _ReceivingVerificationScreenState extends State<ReceivingVerificationScreen> {
  bool _isConfirmed = false;

  void _confirmBatch() {
    setState(() => _isConfirmed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restock batch verified and updated in store inventory & cloud database!'),
        backgroundColor: AppColors.statusGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receiving Verification & Camera Check'),
        actions: [
          ElevatedButton.icon(
            onPressed: _isConfirmed ? null : _confirmBatch,
            icon: const Icon(Icons.check_circle_rounded, size: 22),
            label: Text(_isConfirmed ? 'Batch Confirmed' : 'Confirm & Update Stock'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Instructions Card
            Card(
              color: context.surfaceColor,
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
                      child: const Icon(Icons.fact_check_rounded, color: AppColors.statusGreen, size: 36),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delivery Verification Comparison',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Verify that the computer vision model detected the expected bottle quantities on the shelf.',
                            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Comparison Items
            _buildVerificationCard(
              context: context,
              product: 'Sauvage Eau de Parfum (100ml)',
              roi: 'Camera 1: Layer A (Top - Slot A) • Code: AA1',
              expected: 5,
              detected: 5,
              statusLabel: 'Verified Match (5/5 Bottles)',
              statusType: StatusBadgeType.synced,
              isMatch: true,
            ),
            const SizedBox(height: 14),
            _buildVerificationCard(
              context: context,
              product: 'Chanel Chance Eau Tendre (50ml)',
              roi: 'Camera 3: Layer C (Bottom - Slot A) • Code: CA2',
              expected: 5,
              detected: 4,
              statusLabel: 'Under Count (-1 Bottle)',
              statusType: StatusBadgeType.lowStock,
              isMatch: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard({
    required BuildContext context,
    required String product,
    required String roi,
    required int expected,
    required int detected,
    required String statusLabel,
    required StatusBadgeType statusType,
    required bool isMatch,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
                StatusBadge(type: statusType, customLabel: statusLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text(roi, style: TextStyle(fontSize: 13, color: context.textSecondaryColor)),
            Divider(height: 24, color: context.borderColor),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Expected on Invoice', style: TextStyle(fontSize: 12, color: context.textMutedColor)),
                      const SizedBox(height: 2),
                      Text(
                        '$expected Bottles',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('YOLO Camera Detection', style: TextStyle(fontSize: 12, color: context.textMutedColor)),
                      const SizedBox(height: 2),
                      Text(
                        '$detected Bottles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isMatch ? AppColors.statusGreen : AppColors.statusRed,
                        ),
                      ),
                    ],
                  ),
                ),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Inspect Camera Crop'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
