import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../components/status_badge.dart';

class ImageQualityScreen extends StatelessWidget {
  const ImageQualityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Image Quality & Scanning Status'),
        actions: [
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Real-time image quality evaluation: Brightness: 88%, Sharpness: 95% (Passed).'),
                  backgroundColor: AppColors.statusGreen,
                ),
              );
            },
            icon: const Icon(Icons.refresh_rounded, size: 22),
            label: const Text('Test Camera Quality'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Current Image Quality Status Card
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
                      child: const Icon(Icons.check_circle_rounded, color: AppColors.statusGreen, size: 40),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Image Quality Assessment: Passed (Acceptable)',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Contrast, sharpness, and brightness scores meet YOLO and PaddleOCR requirements.',
                            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                    const StatusBadge(type: StatusBadgeType.good, customLabel: 'Quality Score: 92%', large: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Preprocessing & Retry Metrics Row
            Row(
              children: [
                _buildQualityMetric(
                  context: context,
                  title: 'Brightness / Lighting',
                  score: 'Good (88%)',
                  detail: 'Evenly distributed retail lighting',
                  icon: Icons.brightness_high_rounded,
                  isGood: true,
                ),
                const SizedBox(width: 16),
                _buildQualityMetric(
                  context: context,
                  title: 'Blur & Sharpness Score',
                  score: 'High (95%)',
                  detail: 'Sharp bottle outlines and clear caps',
                  icon: Icons.lens_blur_rounded,
                  isGood: true,
                ),
                const SizedBox(width: 16),
                _buildQualityMetric(
                  context: context,
                  title: 'Preprocessing Retries',
                  score: '0 Retries',
                  detail: 'Maximum allowed retry attempts: 3',
                  icon: Icons.repeat_rounded,
                  isGood: true,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Scanning Safety Protocol Notice
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined, color: AppColors.brandAccent, size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pre-Detection Image Quality Verification Protocol',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Before running YOLOv8 and Cap OCR, frames are validated. If poor lighting or heavy blur is encountered, OpenCV applies CLAHE equalization and re-attempts up to 3 times.',
                          style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                        ),
                      ],
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

  Widget _buildQualityMetric({
    required BuildContext context,
    required String title,
    required String score,
    required String detail,
    required IconData icon,
    required bool isGood,
  }) {
    return Expanded(
      child: Card(
        color: context.surfaceColor,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textSecondaryColor),
                  ),
                  Icon(icon, color: isGood ? AppColors.statusGreen : AppColors.statusOrange, size: 22),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                score,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: isGood ? AppColors.statusGreen : AppColors.statusOrange,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: context.textMutedColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
