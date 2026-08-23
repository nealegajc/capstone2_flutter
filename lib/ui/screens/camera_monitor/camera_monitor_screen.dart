import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../components/status_badge.dart';

class CameraMonitorScreen extends StatelessWidget {
  const CameraMonitorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Camera Monitor'),
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.settings_overscan_rounded, size: 28),
            tooltip: 'Calibrate ROIs',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Video Feed Viewport with Bounding Box overlays
            Expanded(
              flex: 7,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.darkBorder, width: 2),
                ),
                child: Stack(
                  children: [
                    // Camera Placeholder / Stream Area
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.videocam_rounded,
                            size: 64,
                            color: AppColors.darkTextMuted.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Live Computer Vision Feed (1080p)',
                            style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'YOLOv8 Bottle Detection & ROI Classification Active',
                            style: TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Mock ROI Region Overlay 1
                    Positioned(
                      top: 40,
                      left: 40,
                      width: 220,
                      height: 160,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.brandAccent, width: 2),
                          color: AppColors.brandAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'ROI-1: Rose Noir [8/8]',
                            style: TextStyle(
                              color: AppColors.brandAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Mock ROI Region Overlay 2 (Low stock)
                    Positioned(
                      top: 40,
                      right: 40,
                      width: 220,
                      height: 160,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.statusRed, width: 2),
                          color: AppColors.statusRed.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(6),
                        child: const Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                            'ROI-2: Vanilla Musk [2/5] LOW',
                            style: TextStyle(
                              color: AppColors.statusRed,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              backgroundColor: Colors.black54,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Live Badge
                    const Positioned(
                      top: 16,
                      left: 16,
                      child: StatusBadge(
                        type: StatusBadgeType.scanning,
                        customLabel: 'CAMERA 01 • LIVE',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Controls & Scan Details
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Detection Summary',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.darkTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _buildDetailRow('Active Camera', 'ESP32-CAM / USB FHD'),
                          const SizedBox(height: 10),
                          _buildDetailRow('Frame Rate', '15 FPS'),
                          const SizedBox(height: 10),
                          _buildDetailRow('Model', 'YOLOv8 Perfume Detector'),
                          const SizedBox(height: 10),
                          _buildDetailRow('Confidence Threshold', '85%'),
                          const SizedBox(height: 10),
                          _buildDetailRow('Last Full Scan', '1 min ago'),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  // Manual Scan Trigger Button (Min 64px height)
                  ElevatedButton.icon(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 64),
                    ),
                    icon: const Icon(Icons.radar_rounded, size: 26),
                    label: const Text('TRIGGER MANUAL SCAN'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14)),
        Text(value, style: const TextStyle(color: AppColors.darkTextPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }
}
