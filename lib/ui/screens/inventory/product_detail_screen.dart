import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(masterProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Details & Vision Specs'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.productForm),
            icon: const Icon(Icons.edit_rounded, size: 20),
            label: const Text('Edit Product'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: productsAsync.when(
        data: (products) {
          final p = products.isNotEmpty ? products.first : null;
          if (p == null) {
            return const Center(child: Text('No product data found.'));
          }

          final capCode = p.perfumeCode;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Card
                Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.4)),
                          ),
                          child: Center(
                            child: Text(
                              capCode,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.brandAccent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${p.brand} • ${p.category} Fragrance • ${p.bottleSize.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Row(
                                children: [
                                  StatusBadge(type: StatusBadgeType.good, large: true),
                                  SizedBox(width: 12),
                                  StatusBadge(type: StatusBadgeType.synced, customLabel: 'Synced to Supabase'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Product Specifications & OCR Results Grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left Column: Specifications & ROI
                    Expanded(
                      child: Card(
                        color: context.surfaceColor,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Shelf & Inventory Specifications',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Divider(height: 24, color: context.borderColor),
                              _buildDetailRow(context, 'Perfume Cap Code', capCode),
                              _buildDetailRow(context, 'Bottle Size', '${p.bottleSize.toUpperCase()} Bottle'),
                              _buildDetailRow(context, 'Assigned Shelf', '${p.shelfLayer} - Slot ${p.slotPosition}'),
                              _buildDetailRow(context, 'Category', p.category),
                              _buildDetailRow(context, 'Brand', p.brand),
                              _buildDetailRow(context, 'Last Scan Time', 'Live Camera Active'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),

                    // Right Column: Cap OCR & Detection Confidence
                    Expanded(
                      child: Card(
                        color: context.surfaceColor,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Computer Vision & OCR Results',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Divider(height: 24, color: context.borderColor),
                              _buildDetailRow(context, 'Expected Cap Code', capCode),
                              _buildDetailRow(context, 'OCR Match Target', '$capCode (100% Top Match)'),
                              _buildDetailRow(context, 'YOLO Detection Confidence', '95.4% (Verified)'),
                              _buildDetailRow(context, 'Image Quality Status', 'Acceptable (FHD 1080p)'),
                              _buildDetailRow(context, 'Stock Status', 'In Stock (5/5 Bottles)'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Recent Inventory Event History
                Text(
                  'Recent Computer Vision History',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 12),

                Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        _buildHistoryRow(
                          context: context,
                          action: 'VISION_SCAN_VERIFIED',
                          detail: 'Bottle presence and cap text code "$capCode" confirmed by YOLOv8 model.',
                          time: '10 minutes ago',
                          icon: Icons.check_circle_outline_rounded,
                          color: AppColors.statusGreen,
                        ),
                        Divider(height: 20, color: context.borderColor),
                        _buildHistoryRow(
                          context: context,
                          action: 'SCHEDULED_CAPTURE',
                          detail: 'Image quality checked and passed (Brightness: 88%, Sharpness: High).',
                          time: '1 hour ago',
                          icon: Icons.camera_alt_outlined,
                          color: AppColors.brandAccent,
                        ),
                        Divider(height: 20, color: context.borderColor),
                        _buildHistoryRow(
                          context: context,
                          action: 'INITIAL_STOCK_RECORD',
                          detail: 'Seeded into San Pablo kiosk master catalog.',
                          time: 'Today, 06:00 AM',
                          icon: Icons.inventory_2_outlined,
                          color: AppColors.brandGold,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading product: $err')),
      ),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: context.textSecondaryColor)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: context.textPrimaryColor)),
        ],
      ),
    );
  }

  Widget _buildHistoryRow({
    required BuildContext context,
    required String action,
    required String detail,
    required String time,
    required IconData icon,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: context.isDark ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(action, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: context.textPrimaryColor)),
              Text(detail, style: TextStyle(fontSize: 12, color: context.textSecondaryColor)),
            ],
          ),
        ),
        Text(time, style: TextStyle(fontSize: 11, color: context.textMutedColor)),
      ],
    );
  }
}
