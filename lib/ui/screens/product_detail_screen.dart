import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../data/models/inventory_record_model.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class ProductDetailScreen extends StatelessWidget {
  final InventoryRecordModel item;
  final VoidCallback onBack;
  final VoidCallback onEdit;

  const ProductDetailScreen({
    super.key,
    required this.item,
    required this.onBack,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Filter movements for this product
    final skuMovements = provider.movementLogs
        .where((m) => m.perfumeCode == item.perfumeCode && m.branch == item.branch)
        .toList();

    return ScrollScreen(
      title: item.name,
      subtitle: '${item.branch} Branch • ${item.shelf} • Code ${item.perfumeCode}',
      showBackButton: true,
      onBack: onBack,
      actions: [
        if (user?.isAdmin == true) ...[
          AppButton(
            text: 'Edit Product',
            icon: Icons.edit_rounded,
            variant: AppButtonVariant.outline,
            onPressed: onEdit,
            height: 48,
            fontSize: 14,
          ),
          const SizedBox(width: 12),
          AppButton(
            text: 'Delete',
            icon: Icons.delete_outline_rounded,
            variant: AppButtonVariant.danger,
            onPressed: () => _confirmDelete(context, provider),
            height: 48,
            fontSize: 14,
          ),
        ],
      ],
      children: [
        // Main Info & Stock Level Row
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left Card: Product Info & Stock Count
            Expanded(
              flex: 5,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Center(
                            child: Text(
                              item.perfumeCode,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppColors.accent,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.name,
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.category} Fragrance • 50ml Eau de Parfum',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        StatusChip(status: item.status),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // Stock Progress Bar
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Shelf Capacity & Detection Level',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '${item.detected} / ${item.recorded} Bottles Present',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        value: (item.detected / (item.recorded == 0 ? 1 : item.recorded)).clamp(0.0, 1.0),
                        minHeight: 14,
                        backgroundColor: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          item.isLowStock
                              ? AppColors.orange
                              : (item.isOutOfStock ? AppColors.red : AppColors.green),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Pricing & Detail Badges
                    Row(
                      children: [
                        _buildDetailStat('Retail Price', item.price.toPhp(), Icons.payments_outlined, isDark),
                        const SizedBox(width: 16),
                        _buildDetailStat('Total Value', (item.detected * item.price).toPhp(), Icons.account_balance_wallet_outlined, isDark),
                        const SizedBox(width: 16),
                        _buildDetailStat('Assigned Shelf', item.shelf, Icons.shelves, isDark),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),

            // Right Card: Restock & Verification Actions
            Expanded(
              flex: 4,
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Kiosk Shelf Verification',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'AI Camera continuously tracks the assigned ROI zone. Tap below to submit a restock transfer request or verify physical count.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    AppButton(
                      text: 'Request Branch Restock',
                      icon: Icons.local_shipping_outlined,
                      variant: AppButtonVariant.primary,
                      width: double.infinity,
                      onPressed: () => _showRestockDialog(context, provider),
                    ),
                    const SizedBox(height: 12),

                    AppButton(
                      text: 'Manual Verify Stock',
                      icon: Icons.check_circle_outline_rounded,
                      variant: AppButtonVariant.outline,
                      width: double.infinity,
                      onPressed: () {
                        provider.saveInventoryRecord(
                          item.copyWith(status: 'normal', detected: item.recorded),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        // Section: Movement History for this SKU
        const Text(
          'Movement & Detection Audit History',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        if (skuMovements.isEmpty)
          AppCard(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Text(
                  'No recent stock events recorded for ${item.name}.',
                  style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                ),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: skuMovements.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final evt = skuMovements[index];
              return AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Icon(
                      evt.eventType == 'REMOVED'
                          ? Icons.remove_circle_outline_rounded
                          : Icons.add_circle_outline_rounded,
                      color: evt.eventType == 'REMOVED' ? AppColors.red : AppColors.green,
                      size: 24,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${evt.eventType} • ${evt.quantity} Bottle(s)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            evt.timestamp.formatFullDate(),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(status: evt.syncStatus, fontSize: 10),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildDetailStat(String label, String value, IconData icon, bool isDark) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBg : AppColors.lightBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.accent),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, AppProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text('Are you sure you want to remove ${item.name} from the inventory?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
            onPressed: () {
              Navigator.pop(ctx);
              provider.deleteInventoryRecord(item.id);
              onBack();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRestockDialog(BuildContext context, AppProvider provider) {
    int qty = 5;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Request Restock for ${item.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Request additional bottles from other branch:'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: qty > 1 ? () => setState(() => qty--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$qty Bottles', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(
                    onPressed: () => setState(() => qty++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                provider.createRestockRequest(
                  productName: item.name,
                  perfumeCode: item.perfumeCode,
                  quantity: qty,
                  fromBranch: item.branch == 'San Pablo' ? 'Lipa' : 'San Pablo',
                  toBranch: item.branch,
                );
              },
              child: const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
