import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/product_model.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class ProductDetailScreen extends ConsumerWidget {
  final ProductModel? product;
  const ProductDetailScreen({super.key, this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(masterProductsProvider);

    return productsAsync.when(
      data: (products) {
        // Resolve target product (either passed via router or fallback to first matching)
        final p = product != null
            ? (products.where((item) => item.id == product!.id || item.perfumeCode == product!.perfumeCode).firstOrNull ?? product!)
            : (products.isNotEmpty ? products.first : null);

        if (p == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Product Details')),
            body: const Center(child: Text('No product data found.')),
          );
        }

        final capCode = p.perfumeCode;
        final isFemale = p.category.toLowerCase().contains('women') ||
            p.category.toLowerCase().contains('female') ||
            p.shelfLayer.contains('Layer C') ||
            (p.shelfLayer.contains('Layer B') && p.slotPosition >= 6);

        final genderColor = isFemale ? AppColors.femalePink : AppColors.maleBlue;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Product Details & Vision Specs'),
            actions: [
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutePaths.productForm, extra: p),
                icon: const Icon(Icons.edit_rounded, size: 18),
                label: const Text('Edit Product'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: SingleChildScrollView(
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
                        // Cap OCR Badge
                        Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isFemale
                                  ? const [Color(0xFFEC4899), Color(0xFFBE185D)]
                                  : const [Color(0xFF0284C7), Color(0xFF0369A1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: genderColor.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  capCode,
                                  style: const TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                Text(
                                  isFemale ? 'WOMEN' : 'MEN',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
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
                              Row(
                                children: [
                                  const StatusBadge(type: StatusBadgeType.good, large: true),
                                  const SizedBox(width: 12),
                                  const StatusBadge(type: StatusBadgeType.synced, customLabel: 'Synced to Supabase'),
                                  const SizedBox(width: 12),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: genderColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: genderColor.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      isFemale ? 'Women\'s Scent' : 'Men\'s Scent',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: genderColor,
                                      ),
                                    ),
                                  ),
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
                              _buildDetailRow(context, 'Cap OCR Code', capCode),
                              _buildDetailRow(context, 'Bottle Size', '${p.bottleSize.toUpperCase()} Bottle'),
                              _buildDetailRow(context, 'Assigned Shelf Layer', p.shelfLayer),
                              _buildDetailRow(context, 'Slot Position', 'Slot ${p.slotPosition}'),
                              _buildDetailRow(context, 'Category', p.category),
                              _buildDetailRow(context, 'Brand / House', p.brand),
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
                                'PaddleOCR & AI Vision Telemetry',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Divider(height: 24, color: context.borderColor),
                              _buildDetailRow(context, 'OCR Recognition Confidence', '99.2% Confirmed'),
                              _buildDetailRow(context, 'Bounding Box ROI Target', 'ROI Sector [Slot ${p.slotPosition}]'),
                              _buildDetailRow(context, 'Slot Capacity', '5 / 5 Bottles Max'),
                              _buildDetailRow(context, 'Physical Alignment', 'Calibrated Grid'),
                              _buildDetailRow(context, 'Vision Pipeline Status', 'Active'),
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
      },
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const Scaffold(body: Center(child: Text('Unable to load product data.'))),
    );
  }

  Widget _buildDetailRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }
}
