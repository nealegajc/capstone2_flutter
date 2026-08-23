import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class ImageQualityScreen extends StatelessWidget {
  final VoidCallback onBack;

  const ImageQualityScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final qLog = provider.imageQualityLog;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final brightness = qLog?.brightness ?? 78.5;
    final contrast = qLog?.contrast ?? 82.1;
    final sharpness = qLog?.sharpness ?? 90.4;
    final isAcceptable = qLog?.isAcceptable ?? true;
    final preproc = qLog?.preprocessingApplied ?? ['CLAHE Histogram', 'Bilateral Noise Reduction', 'Unsharp Mask'];
    final status = qLog?.status ?? 'ACCEPTED';
    final retries = qLog?.retryCount ?? 0;

    return ScrollScreen(
      title: 'Image Quality Assessment & AI Logs',
      subtitle: 'Computer-vision frame evaluation, adaptive preprocessing, and retry limits',
      showBackButton: true,
      onBack: onBack,
      actions: [
        StatusChip(
          status: isAcceptable ? 'normal' : 'critical',
          customLabel: status,
        ),
      ],
      children: [
        // Top Assessment Summary
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quality Metrics Gauges Card
            Expanded(
              flex: 5,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Candidate Frame Visual Quality Metrics',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    _buildMetricBar('Illumination & Brightness', brightness, 100, '%', isDark),
                    const SizedBox(height: 16),
                    _buildMetricBar('Contrast Ratio Level', contrast, 100, '%', isDark),
                    const SizedBox(height: 16),
                    _buildMetricBar('Edge Acutance / Sharpness', sharpness, 100, '%', isDark),
                    const SizedBox(height: 20),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Assessment Status: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          isAcceptable
                              ? 'PASSED (Frame meets YOLO/OCR criteria)'
                              : 'FAILED (Exceeded max retry threshold)',
                          style: TextStyle(
                            color: isAcceptable ? AppColors.green : AppColors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Preprocessing & Retry Rules Card
            Expanded(
              flex: 4,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Adaptive Preprocessing Pipeline',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'OpenCV adaptive filters automatically applied when candidate frames have low contrast or glare:',
                      style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                    const SizedBox(height: 16),

                    ...preproc.map((step) => Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.check_circle_rounded, color: AppColors.green, size: 18),
                              const SizedBox(width: 10),
                              Text(step, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            ],
                          ),
                        )),
                    const Divider(height: 24),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Retry Count for current cycle:', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text('$retries / 3 attempts', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    AppButton(
                      text: 'Trigger Frame Quality Test',
                      icon: Icons.refresh_rounded,
                      width: double.infinity,
                      onPressed: () => provider.triggerManualScan(provider.currentUser?.branch ?? 'San Pablo'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Recent Detection & OCR Match Results
        const Text(
          'Latest Detection & PaddleOCR Code Results',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: provider.lastDetections.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final det = provider.lastDetections[index];
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        det.recognizedCode,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Zone ${det.roiId.replaceAll('roi_', '')} • YOLO Bottle Tag: ${det.detectedObject}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          'YOLO Conf: ${(det.yoloConfidence * 100).toStringAsFixed(1)}% • PaddleOCR Conf: ${(det.ocrConfidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  StatusChip(status: det.matchResult),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricBar(String label, double value, double max, String unit, bool isDark) {
    final pct = (value / max).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('${value.toStringAsFixed(1)}$unit', style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 10,
            backgroundColor: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(
              value < 40 ? AppColors.red : (value < 65 ? AppColors.orange : AppColors.green),
            ),
          ),
        ),
      ],
    );
  }
}
