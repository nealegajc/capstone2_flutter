import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class ShelfScreen extends StatefulWidget {
  final ValueChanged<String> onOpenShelfAreaDetail;

  const ShelfScreen({
    super.key,
    required this.onOpenShelfAreaDetail,
  });

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  int? _activeDraggingHandle; // 1, 2, 3 for vertical dividers; 10 for top; 20 for bottom
  int _selectedBoundaryIndex = 1;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScrollScreen(
      title: 'Shelf & ROI Tester',
      subtitle: 'Camera calibration, spatial region alignment, and AI inventory checks',
      actions: [
        StatusChip(
          status: provider.isEdgeConnected ? 'active' : 'offline',
          customLabel: provider.isEdgeConnected ? 'Camera Connected' : 'Camera Offline',
        ),
        const SizedBox(width: 12),
        AppButton(
          text: provider.isLiveCalibrationActive ? 'Stop Calibration' : 'Start Live Calibration',
          icon: provider.isLiveCalibrationActive ? Icons.videocam_off_rounded : Icons.videocam_rounded,
          variant: provider.isLiveCalibrationActive ? AppButtonVariant.danger : AppButtonVariant.outline,
          onPressed: provider.toggleLiveCalibration,
          height: 48,
          fontSize: 14,
        ),
      ],
      children: [
        // Camera Viewport & ROI Canvas
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Camera Viewport with CustomPainter ROI Canvas
            Expanded(
              flex: 6,
              child: AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Column(
                    children: [
                      Container(
                        height: 480,
                        color: Colors.black,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final w = constraints.maxWidth;
                            final h = constraints.maxHeight;

                            return GestureDetector(
                              onPanDown: (details) {
                                final localPos = details.localPosition;

                                // Check hit on vertical boundaries (1, 2, 3)
                                for (int i = 1; i < provider.roiBoundaries.length - 1; i++) {
                                  final bx = provider.roiBoundaries[i] * w;
                                  if ((localPos.dx - bx).abs() < 30.0) {
                                    setState(() {
                                      _activeDraggingHandle = i;
                                      _selectedBoundaryIndex = i;
                                    });
                                    return;
                                  }
                                }

                                // Check hit on top or bottom
                                if ((localPos.dy - provider.roiTop * h).abs() < 24.0) {
                                  setState(() => _activeDraggingHandle = 10);
                                } else if ((localPos.dy - provider.roiBottom * h).abs() < 24.0) {
                                  setState(() => _activeDraggingHandle = 20);
                                }
                              },
                              onPanUpdate: (details) {
                                if (_activeDraggingHandle == null) return;
                                final localPos = details.localPosition;
                                final normX = (localPos.dx / w).clamp(0.0, 1.0);
                                final normY = (localPos.dy / h).clamp(0.0, 1.0);

                                if (_activeDraggingHandle! >= 1 && _activeDraggingHandle! <= 3) {
                                  final updated = List<double>.from(provider.roiBoundaries);
                                  final idx = _activeDraggingHandle!;
                                  final minX = updated[idx - 1] + 0.04;
                                  final maxX = updated[idx + 1] - 0.04;
                                  updated[idx] = normX.clamp(minX, maxX);
                                  provider.updateRoiBoundaries(
                                    boundaries: updated,
                                    top: provider.roiTop,
                                    bottom: provider.roiBottom,
                                  );
                                } else if (_activeDraggingHandle == 10) {
                                  final newTop = normY.clamp(0.05, provider.roiBottom - 0.10);
                                  provider.updateRoiBoundaries(
                                    boundaries: provider.roiBoundaries,
                                    top: newTop,
                                    bottom: provider.roiBottom,
                                  );
                                } else if (_activeDraggingHandle == 20) {
                                  final newBottom = normY.clamp(provider.roiTop + 0.10, 0.95);
                                  provider.updateRoiBoundaries(
                                    boundaries: provider.roiBoundaries,
                                    top: provider.roiTop,
                                    bottom: newBottom,
                                  );
                                }
                              },
                              onPanEnd: (_) => setState(() => _activeDraggingHandle = null),
                              child: CustomPaint(
                                size: Size(w, h),
                                painter: _RoiOverlayPainter(
                                  boundaries: provider.roiBoundaries,
                                  top: provider.roiTop,
                                  bottom: provider.roiBottom,
                                  calibrationFrame: provider.calibrationFrame,
                                  detections: provider.lastDetections,
                                  selectedBoundary: _selectedBoundaryIndex,
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Stream Info Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        color: isDark ? AppColors.darkCardBg : const Color(0xFFF8FAFC),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              provider.isLiveCalibrationActive
                                  ? '🔴 Live Stream (1080p AI Camera)'
                                  : '📸 Static Shelf View • Tap and drag green lines to calibrate zones',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: provider.isLiveCalibrationActive ? AppColors.red : AppColors.gray,
                              ),
                            ),
                            Text(
                              '4 Zones (A, B, C, D)',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Right: Zone Adjusters & Action Controls
            Expanded(
              flex: 4,
              child: Column(
                children: [
                  // Run AI Check Button Card
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Execute AI Shelf Scan',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Captures current shelf image, executes YOLOv8 model inference, OCR cap tags, and updates Supabase.',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),

                        AppButton(
                          text: 'Run Inventory Check',
                          icon: Icons.camera_enhance_rounded,
                          width: double.infinity,
                          onPressed: () => _showBranchScanDialog(context, provider),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ROI Fine Tuning & Nudge Card
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Fine-Tune Boundary Dividers',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            const Text('Selected Divider: ', style: TextStyle(fontWeight: FontWeight.bold)),
                            DropdownButton<int>(
                              value: _selectedBoundaryIndex,
                              items: const [
                                DropdownMenuItem(value: 1, child: Text('Divider A | B')),
                                DropdownMenuItem(value: 2, child: Text('Divider B | C')),
                                DropdownMenuItem(value: 3, child: Text('Divider C | D')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedBoundaryIndex = val);
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => provider.nudgeRoi(_selectedBoundaryIndex, -0.01),
                                icon: const Icon(Icons.arrow_left_rounded),
                                label: const Text('Nudge Left'),
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => provider.nudgeRoi(_selectedBoundaryIndex, 0.01),
                                icon: const Icon(Icons.arrow_right_rounded),
                                label: const Text('Nudge Right'),
                                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Reset to Default
                        Center(
                          child: TextButton.icon(
                            onPressed: () {
                              provider.updateRoiBoundaries(
                                boundaries: [0.0, 0.25, 0.50, 0.75, 1.0],
                                top: 0.15,
                                bottom: 0.85,
                              );
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 18),
                            label: const Text('Reset ROI to Standard (25% Each)'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Section: Zone Status Cards (Area A, B, C, D)
        const Text(
          'Shelf ROI Compartments Breakdown',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        Row(
          children: ['A', 'B', 'C', 'D'].map((zone) {
            final item = provider.allInventoryList.firstWhere(
              (i) => i.perfumeCode == zone && i.branch == (user?.branch ?? 'San Pablo'),
              orElse: () => provider.allInventoryList.firstWhere((i) => i.perfumeCode == zone),
            );

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: AppCard(
                  onTap: () => widget.onOpenShelfAreaDetail(zone),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.accent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Area $zone',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent),
                            ),
                          ),
                          StatusChip(status: item.status, fontSize: 10),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Detected: ${item.detected} / ${item.recorded} bottles',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showBranchScanDialog(BuildContext context, AppProvider provider) {
    final user = provider.currentUser;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Select Branch for AI Scan'),
        content: const Text('Which branch shelf would you like the computer vision system to check?'),
        actions: [
          if (user?.isAdmin == true)
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                provider.triggerManualScan('San Pablo');
              },
              child: const Text('San Pablo Branch'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              provider.triggerManualScan('Lipa');
            },
            child: const Text('Lipa Branch'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CUSTOM PAINTER FOR ROI AND DETECTION BOUNDING BOXES
// ---------------------------------------------------------------------------
class _RoiOverlayPainter extends CustomPainter {
  final List<double> boundaries;
  final double top;
  final double bottom;
  final dynamic calibrationFrame;
  final List<dynamic> detections;
  final int selectedBoundary;

  _RoiOverlayPainter({
    required this.boundaries,
    required this.top,
    required this.bottom,
    this.calibrationFrame,
    required this.detections,
    required this.selectedBoundary,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Draw Background Grid / Placeholder
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..strokeWidth = 1;
    for (double x = 0; x < w; x += 40) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
    }
    for (double y = 0; y < h; y += 40) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    final topY = top * h;
    final bottomY = bottom * h;

    // Dim area outside top/bottom crop
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.5);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, topY), dimPaint);
    canvas.drawRect(Rect.fromLTWH(0, bottomY, w, h - bottomY), dimPaint);

    // Draw Top & Bottom Crop Lines
    final cropLinePaint = Paint()
      ..color = AppColors.orange
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, topY), Offset(w, topY), cropLinePaint);
    canvas.drawLine(Offset(0, bottomY), Offset(w, bottomY), cropLinePaint);

    // Draw Vertical Dividers & Zones
    final labels = ['A', 'B', 'C', 'D'];
    for (int i = 0; i < boundaries.length - 1; i++) {
      final leftX = boundaries[i] * w;
      final rightX = boundaries[i + 1] * w;

      // Draw Zone Label
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'ZONE ${labels[i]}',
          style: const TextStyle(
            color: AppColors.green,
            fontWeight: FontWeight.w900,
            fontSize: 16,
            letterSpacing: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(leftX + (rightX - leftX - textPainter.width) / 2, topY + 12));

      // Draw vertical divider
      if (i > 0) {
        final isSelected = i == selectedBoundary;
        final dividerPaint = Paint()
          ..color = isSelected ? AppColors.accent : AppColors.green
          ..strokeWidth = isSelected ? 3.0 : 2.0;

        canvas.drawLine(Offset(leftX, topY), Offset(leftX, bottomY), dividerPaint);

        // Draw Handle Circle
        final handlePaint = Paint()..color = isSelected ? AppColors.accent : AppColors.green;
        canvas.drawCircle(Offset(leftX, (topY + bottomY) / 2), 12, handlePaint);
        canvas.drawCircle(Offset(leftX, (topY + bottomY) / 2), 6, Paint()..color = Colors.white);
      }
    }

    // Draw simulated YOLO detection bounding boxes
    final yoloBoxPaint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 4; i++) {
      final leftX = boundaries[i] * w + 20;
      final rightX = boundaries[i + 1] * w - 20;
      final boxW = (rightX - leftX).clamp(40.0, 120.0);
      final boxH = (bottomY - topY) * 0.65;
      final boxY = topY + 50;

      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(leftX + 10, boxY, boxW, boxH), const Radius.circular(8)),
        yoloBoxPaint,
      );

      final tagPainter = TextPainter(
        text: TextSpan(
          text: 'bottle_cap_${labels[i]} (0.94)',
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      );
      tagPainter.layout();
      canvas.drawRect(
        Rect.fromLTWH(leftX + 10, boxY - 14, tagPainter.width + 8, 14),
        Paint()..color = AppColors.accent,
      );
      tagPainter.paint(canvas, Offset(leftX + 14, boxY - 14));
    }
  }

  @override
  bool shouldRepaint(covariant _RoiOverlayPainter oldDelegate) => true;
}
