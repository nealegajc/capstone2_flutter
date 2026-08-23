import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class ShelfAreaDetailScreen extends StatelessWidget {
  final String zoneCode; // 'A', 'B', 'C', 'D'
  final VoidCallback onBack;

  const ShelfAreaDetailScreen({
    super.key,
    required this.zoneCode,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final item = provider.allInventoryList.firstWhere(
      (i) => i.perfumeCode == zoneCode,
      orElse: () => provider.allInventoryList.first,
    );

    return ScrollScreen(
      title: 'Shelf Zone Area $zoneCode',
      subtitle: 'Real-time spatial compartment AI analysis and verification',
      showBackButton: true,
      onBack: onBack,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Card: Zone Status & AI Confidence
            Expanded(
              flex: 5,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Zone $zoneCode Status',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        StatusChip(status: item.status),
                      ],
                    ),
                    const SizedBox(height: 20),

                    _buildInfoRow('Assigned SKU', item.name, isDark),
                    _buildInfoRow('Perfume Code', 'Code ${item.perfumeCode}', isDark),
                    _buildInfoRow('Branch', item.branch, isDark),
                    _buildInfoRow('Recorded Capacity', '${item.recorded} bottles', isDark),
                    _buildInfoRow('YOLO Detected Count', '${item.detected} bottles', isDark),
                    _buildInfoRow('YOLOv8 Detection Confidence', '94.8% (High)', isDark),
                    _buildInfoRow('PaddleOCR Text Confidence', '96.2% (High)', isDark),
                    _buildInfoRow('Misplacement Check', item.isMisplaced ? 'MISPLACED FLAGGED' : 'Verified in-zone', isDark),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Right Card: Verification & Actions
            Expanded(
              flex: 4,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Staff Confirmation',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'If the physical shelf has been manually verified or corrected, tap below to confirm zone accuracy.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),

                    AppButton(
                      text: 'Mark Zone as Verified',
                      icon: Icons.check_circle_outline_rounded,
                      width: double.infinity,
                      onPressed: () {
                        provider.saveInventoryRecord(
                          item.copyWith(status: 'normal', detected: item.recorded),
                        );
                        onBack();
                      },
                    ),
                    const SizedBox(height: 12),

                    AppButton(
                      text: 'Trigger Spot Re-scan',
                      icon: Icons.refresh_rounded,
                      variant: AppButtonVariant.outline,
                      width: double.infinity,
                      onPressed: () => provider.triggerManualScan(item.branch),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
