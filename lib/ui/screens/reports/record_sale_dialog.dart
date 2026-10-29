import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/sale_record_model.dart';
import '../../../data/services/toast_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/sales_provider.dart';

class RecordSaleDialog extends ConsumerStatefulWidget {
  final ProductModel? initialProduct;
  final String? branch;

  const RecordSaleDialog({super.key, this.initialProduct, this.branch});

  static Future<bool?> show(
    BuildContext context, {
    ProductModel? initialProduct,
    String? branch,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          RecordSaleDialog(initialProduct: initialProduct, branch: branch),
    );
  }

  @override
  ConsumerState<RecordSaleDialog> createState() => _RecordSaleDialogState();
}

class _RecordSaleDialogState extends ConsumerState<RecordSaleDialog> {
  ProductModel? _selectedProduct;
  int _quantity = 1;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _selectedProduct = widget.initialProduct;
  }

  double get _unitPrice {
    if (_selectedProduct == null) return AppConstants.price100ml;
    return AppConstants.priceFor(_selectedProduct!.bottleSize);
  }

  double get _totalAmount => _unitPrice * _quantity;

  Future<void> _handleConfirmSale() async {
    if (_selectedProduct == null) {
      ToastService.showToast(
        title: 'Select Fragrance',
        message: 'Please choose a perfume bottle to record sale.',
        type: 'warning',
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final effectiveBranch = widget.branch ?? 'San Pablo';
      const currentUser = 'Staff';
      final sqlite = ref.read(sqliteServiceProvider);

      final saleId = 'sale_${DateTime.now().millisecondsSinceEpoch}';
      final saleRecord = SaleRecordModel(
        id: saleId,
        perfumeCode: _selectedProduct!.perfumeCode,
        productName: _selectedProduct!.name,
        bottleSize: _selectedProduct!.bottleSize,
        quantitySold: _quantity,
        unitPrice: _unitPrice,
        totalAmount: _totalAmount,
        branch: effectiveBranch,
        soldBy: currentUser,
        soldAt: DateTime.now(),
        syncStatus: 'synced',
      );

      // 1. Insert into SQLite & Sync Queue
      await sqlite.insertSaleRecord(saleRecord);

      // 2. Log Inventory Event (REMOVED / SOLD)
      final eventId = 'evt_sale_${DateTime.now().millisecondsSinceEpoch}';
      final event = InventoryEventModel(
        id: eventId,
        eventType: 'REMOVED',
        productName: _selectedProduct!.name,
        perfumeCode: _selectedProduct!.perfumeCode,
        shelfArea: _selectedProduct!.shelfLayer,
        branch: effectiveBranch,
        quantity: _quantity,
        timestamp: DateTime.now(),
      );
      await sqlite.logInventoryEvent(event);

      // 3. Update inventory record detection count if exists
      try {
        final records = await sqlite.getInventoryRecords(effectiveBranch);
        final found = records
            .where((r) => r.perfumeCode == _selectedProduct!.perfumeCode)
            .firstOrNull;
        if (found != null) {
          final newDetected = (found.detected - _quantity).clamp(0, 100);
          final newRecorded = (found.recorded - _quantity).clamp(0, 100);
          final updatedInv = found.copyWith(
            detected: newDetected,
            recorded: newRecorded,
            lastUpdated: DateTime.now(),
            status: newDetected == 0
                ? 'out_of_stock'
                : (newDetected <= 2 ? 'low' : 'normal'),
          );
          await sqlite.upsertInventoryRecord(updatedInv);
        }
      } catch (_) {}

      // 4. Invalidate Providers
      ref.invalidate(salesRecordsProvider);
      ref.invalidate(salesAnalyticsProvider);
      ref.invalidate(liveInventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(stockMovementLogsProvider);

      if (mounted) {
        Navigator.of(context).pop(true);
        ToastService.showToast(
          title: 'Sale Recorded Successfully',
          message:
              '$_quantity x ${_selectedProduct!.name} (${_selectedProduct!.bottleSize}) - ₱${_totalAmount.toStringAsFixed(2)}',
          type: 'success',
        );
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      ToastService.showToast(
        title: 'Failed to Record Sale',
        message: e.toString(),
        type: 'error',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(masterProductsProvider);

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 580,
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.point_of_sale_rounded,
                    color: AppColors.brandGold,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Record Fragrance Sale',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Universal Pricing: 100ml = ₱260 • 50ml = ₱180',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Product Selector Dropdown
            Text(
              'Select Product / SKU',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),

            productsAsync.when(
              data: (products) {
                final activeProducts = products
                    .where((p) => p.isActive)
                    .toList();
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<ProductModel>(
                      value: _selectedProduct != null
                          ? activeProducts
                                .where((p) => p.id == _selectedProduct!.id)
                                .firstOrNull
                          : null,
                      hint: Text(
                        'Choose fragrance from catalog...',
                        style: TextStyle(
                          color: context.textMutedColor,
                          fontSize: 14,
                        ),
                      ),
                      isExpanded: true,
                      dropdownColor: context.surfaceColor,
                      items: activeProducts.map((p) {
                        final is100 = p.bottleSize.toLowerCase().contains(
                          '100',
                        );
                        final price = is100
                            ? AppConstants.price100ml
                            : AppConstants.price50ml;
                        return DropdownMenuItem<ProductModel>(
                          value: p,
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (p.category == 'Men'
                                              ? AppColors.maleBlue
                                              : AppColors.femalePink)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.perfumeCode,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: p.category == 'Men'
                                        ? AppColors.maleBlue
                                        : AppColors.femalePink,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: context.textPrimaryColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${p.bottleSize} • ₱${price.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.brandGold,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedProduct = val;
                        });
                      },
                    ),
                  ),
                );
              },
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => Text(
                'Error loading products',
                style: TextStyle(color: AppColors.statusRed),
              ),
            ),
            const SizedBox(height: 20),

            // Pricing & Bottle Size Summary Pill
            if (_selectedProduct != null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceElevatedColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_offer_rounded,
                          size: 18,
                          color: AppColors.brandGold,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Size: ${_selectedProduct!.bottleSize}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '(${_selectedProduct!.shelfLayer})',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '₱${_unitPrice.toStringAsFixed(2)} / bottle',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandGold,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),

            // Quantity Stepper (Optimized for Touch Kiosk)
            Text(
              'Quantity Sold',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuantityButton(
                  icon: Icons.remove_rounded,
                  onTap: _quantity > 1
                      ? () => setState(() => _quantity--)
                      : null,
                ),
                const SizedBox(width: 16),
                Container(
                  width: 80,
                  height: 56,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    '$_quantity',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                _buildQuantityButton(
                  icon: Icons.add_rounded,
                  onTap: _quantity < 50
                      ? () => setState(() => _quantity++)
                      : null,
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total Amount',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    Text(
                      '₱${_totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: context.borderColor),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: context.textPrimaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: (_selectedProduct == null || _isSubmitting)
                        ? null
                        : _handleConfirmSale,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(
                      _isSubmitting
                          ? 'Recording Sale...'
                          : 'Confirm Sale (₱${_totalAmount.toStringAsFixed(2)})',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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

  Widget _buildQuantityButton({required IconData icon, VoidCallback? onTap}) {
    final isEnabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: isEnabled
                ? AppColors.brandAccent.withValues(alpha: 0.15)
                : context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isEnabled ? AppColors.brandAccent : context.borderColor,
            ),
          ),
          child: Icon(
            icon,
            color: isEnabled ? AppColors.brandAccent : context.textMutedColor,
            size: 26,
          ),
        ),
      ),
    );
  }
}
