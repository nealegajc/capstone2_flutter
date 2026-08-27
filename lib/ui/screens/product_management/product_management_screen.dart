import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';

class ProductManagementScreen extends StatelessWidget {
  const ProductManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Product & ROI Management'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => context.push(AppRoutePaths.productForm),
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('Add Product SKU'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(160, 48),
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
            Text(
              'Configured Perfume Products & Thresholds',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Set low-stock alert thresholds and map perfume bottles to camera shelf regions across 3 layers.',
              style: TextStyle(
                fontSize: 14,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 20),

            // Form / Card Example
            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Sauvage Eau de Parfum (100ml)',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Text(
                                'Cap Code: AA1 • Category: Men Fragrance • Christian Dior',
                                style: TextStyle(
                                  color: context.textSecondaryColor,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push(AppRoutePaths.productForm),
                          icon: const Icon(Icons.edit_outlined, size: 20),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                    Divider(height: 28, color: context.borderColor),
                    Row(
                      children: [
                        Expanded(
                          child: _buildFormField(
                            context: context,
                            label: 'Assigned ROI Shelf',
                            value: '📷 Camera 1: Layer A (Top - Slot A)',
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildFormField(
                            context: context,
                            label: 'Low Stock Alert Threshold',
                            value: '2 Bottles (Safety Limit)',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textSecondaryColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
        ),
      ],
    );
  }
}
