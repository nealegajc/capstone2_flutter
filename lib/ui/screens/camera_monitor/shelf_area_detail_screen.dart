import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../components/status_badge.dart';

class ShelfAreaDetailScreen extends StatefulWidget {
  const ShelfAreaDetailScreen({super.key});

  @override
  State<ShelfAreaDetailScreen> createState() => _ShelfAreaDetailScreenState();
}

class _ShelfAreaDetailScreenState extends State<ShelfAreaDetailScreen> {
  bool _isReviewed = false;

  void _markReviewed() {
    setState(() => _isReviewed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✓ Shelf Area B - Partition verified & reviewed!'),
        backgroundColor: AppColors.statusGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Area (ROI Partition) Details'),
        actions: [
          ElevatedButton.icon(
            onPressed: _isReviewed ? null : _markReviewed,
            icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
            label: Text(_isReviewed ? 'Status Reviewed' : 'Mark as Reviewed'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section Card
            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.crop_free_rounded, color: AppColors.brandAccent, size: 36),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Camera 2: Shelf Layer B — Partition 2',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Assigned Product: Vanilla Musk EDP (50ml) • Cap OCR Code: BA2',
                            style: TextStyle(
                              fontSize: 15,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const StatusBadge(type: StatusBadgeType.good, large: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ROI Camera Crop vs Quantities Grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Last Captured ROI Crop View
                Expanded(
                  flex: 5,
                  child: Container(
                    height: 280,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Stack(
                      children: [
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.camera_alt_outlined, size: 48, color: Colors.white38),
                              const SizedBox(height: 12),
                              const Text(
                                'Camera 2 (Middle Shelf) Live Crop',
                                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Bounding Box Coordinates: [x: 120, y: 45, w: 200, h: 420]',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.brandAccent),
                            ),
                            child: const Text(
                              'ROI #BA2 (Slot B)',
                              style: TextStyle(color: AppColors.brandAccent, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Right: Quantities & OCR Breakdown
                Expanded(
                  flex: 6,
                  child: Card(
                    color: context.surfaceColor,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detection & Stock Quantities',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          Divider(height: 24, color: context.borderColor),
                          _buildQuantityRow(context, 'Expected Quantity', '5 Bottles'),
                          _buildQuantityRow(context, 'Current Detected Count', '5 Bottles (Full Stock)', isGreen: true),
                          _buildQuantityRow(context, 'Low Stock Threshold', '2 Bottles'),
                          _buildQuantityRow(context, 'Cap Code Match Confidence', '98.5% Top Match'),
                          _buildQuantityRow(context, 'Last Detection Timestamp', 'Live Active Scan'),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => context.push(AppRoutePaths.createRestock),
                                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
                                  label: const Text('Log Restock'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => context.push(AppRoutePaths.cameraMonitor),
                                  icon: const Icon(Icons.videocam_rounded, size: 18),
                                  label: const Text('Camera Feed'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityRow(BuildContext context, String label, String value, {bool isGreen = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondaryColor, fontSize: 13)),
          Text(
            value,
            style: TextStyle(
              color: isGreen ? AppColors.statusGreen : context.textPrimaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
