import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/inventory_record_model.dart';
import '../../../data/models/restock_record_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/scan_workflow_dialog.dart';

class CreateRestockScreen extends ConsumerStatefulWidget {
  const CreateRestockScreen({super.key});

  @override
  ConsumerState<CreateRestockScreen> createState() =>
      _CreateRestockScreenState();
}

class _CreateRestockScreenState extends ConsumerState<CreateRestockScreen> {
  int _currentStep = 0;
  String? _selectedProductCode;
  String? _selectedShelf;
  int _restockQty = 5;
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  int _getCameraIdForShelf(String? shelf, String? code) {
    if (shelf != null) {
      if (shelf.contains('Layer A') || shelf.toLowerCase().contains('top')) return 1;
      if (shelf.contains('Layer B') || shelf.toLowerCase().contains('middle')) return 2;
      if (shelf.contains('Layer C') || shelf.toLowerCase().contains('bottom')) return 3;
    }
    if (code != null && code.isNotEmpty) {
      final prefix = code[0].toUpperCase();
      if (prefix == 'A') return 1;
      if (prefix == 'B') return 2;
      if (prefix == 'C') return 3;
    }
    return 1;
  }

  Future<void> _submitRestock({bool verifiedViaScan = false}) async {
    if (_selectedProductCode == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a perfume product.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final products = await ref.read(masterProductsProvider.future);
      final product = products.firstWhere(
        (p) => p.perfumeCode == _selectedProductCode,
      );

      final now = DateTime.now();
      const targetBranch = 'San Pablo';
      final shelf = _selectedShelf ?? product.shelfLayer;

      // 1. Log Inventory Movement Event
      final event = InventoryEventModel(
        id: 'evt_${now.millisecondsSinceEpoch}',
        eventType: 'RESTOCKED',
        productName: product.name,
        perfumeCode: product.perfumeCode,
        shelfArea: shelf,
        branch: targetBranch,
        quantity: _restockQty,
        timestamp: now,
      );
      await SqliteService.instance.logInventoryEvent(event);

      // 2. Persist Restock Record Model for Restock & In-Transit tracking
      final restockRecord = RestockRecordModel(
        id: 'rst_${now.millisecondsSinceEpoch}',
        productName: product.name,
        perfumeCode: product.perfumeCode,
        quantity: _restockQty,
        fromBranch: 'Main Warehouse',
        toBranch: targetBranch,
        requestedBy: 'Kiosk Store Manager',
        status: verifiedViaScan ? 'verified' : 'received',
        createdAt: now,
      );
      await SqliteService.instance.saveRestockRecord(restockRecord);

      // 3. Immediately increment SQLite inventory_records for this branch & product
      final existing = await SqliteService.instance.getInventoryRecord(
        product.perfumeCode,
        targetBranch,
      );
      if (existing != null) {
        final updated = InventoryRecordModel(
          id: existing.id,
          perfumeCode: existing.perfumeCode,
          name: existing.name,
          category: existing.category,
          branch: existing.branch,
          shelf: existing.shelf,
          recorded: existing.recorded + _restockQty,
          detected: existing.detected + _restockQty,
          status: 'normal',
          misplacementDetails: '',
          lastUpdated: now,
          price: existing.price,
        );
        await SqliteService.instance.upsertInventoryRecord(updated);
      } else {
        final newRecord = InventoryRecordModel(
          id: 'inv_${now.millisecondsSinceEpoch}',
          perfumeCode: product.perfumeCode,
          name: product.name,
          category: product.category,
          branch: targetBranch,
          shelf: shelf,
          recorded: _restockQty,
          detected: _restockQty,
          status: 'normal',
          misplacementDetails: '',
          lastUpdated: now,
          price: product.price,
        );
        await SqliteService.instance.upsertInventoryRecord(newRecord);
      }

      await SqliteService.instance.logActivity(
        type: 'RESTOCK_BATCH',
        description:
            'Restocked $_restockQty bottle(s) of ${product.name} (${product.perfumeCode}) to $shelf.${verifiedViaScan ? " [Verified via OCR]" : ""}',
        branch: targetBranch,
      );

      // Refresh providers
      ref.invalidate(stockMovementLogsProvider(targetBranch));
      ref.invalidate(liveInventoryProvider(targetBranch));
      ref.invalidate(dashboardStatsProvider(targetBranch));
      ref.invalidate(restockRecordsProvider(targetBranch));
      ref.invalidate(systemActivityLogsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Successfully restocked $_restockQty bottle(s) of ${product.name} (${product.perfumeCode}).',
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('[CreateRestockScreen] Failed to save restock: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save restock batch: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(masterProductsProvider);
    final invAsync = ref.watch(liveInventoryProvider('San Pablo'));
    final invRecords = invAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guided Physical Restock'),
        backgroundColor: context.surfaceColor,
        elevation: 0,
      ),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading products: $err')),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No perfumes found in catalog.'));
          }

          _selectedProductCode ??= products.first.perfumeCode;
          final selectedProduct = products.firstWhere(
            (p) => p.perfumeCode == _selectedProductCode,
            orElse: () => products.first,
          );
          _selectedShelf ??= selectedProduct.shelfLayer;

          final existingInv = invRecords.cast<InventoryRecordModel?>().firstWhere(
            (i) => i?.perfumeCode == selectedProduct.perfumeCode,
            orElse: () => null,
          );

          final currentStock = existingInv?.detected ?? existingInv?.recorded ?? 0;
          const maxTrayCapacity = 10;
          final willExceed = (currentStock + _restockQty) > maxTrayCapacity;
          final targetCamId = _getCameraIdForShelf(_selectedShelf, selectedProduct.perfumeCode);

          return Stepper(
            currentStep: _currentStep,
            type: StepperType.horizontal,
            elevation: 1,
            onStepTapped: (step) => setState(() => _currentStep = step),
            controlsBuilder: (context, details) => const SizedBox.shrink(),
            steps: [
              // Step 1: Select Scent & Quantity
              Step(
                title: const Text('1. Scent & Qty'),
                isActive: _currentStep >= 0,
                state: _currentStep > 0 ? StepState.complete : StepState.indexed,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: context.surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: context.borderColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Step 1: Select Fragrance & Delivery Batch',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Choose the fragrance variant and bottle size being placed on the shelf.',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondaryColor,
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Product Dropdown
                            DropdownButtonFormField<String>(
                              initialValue: selectedProduct.perfumeCode,
                              dropdownColor: context.surfaceElevatedColor,
                              style: TextStyle(
                                fontSize: 15,
                                color: context.textPrimaryColor,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Select Perfume Variant',
                                prefixIcon: const Icon(Icons.sanitizer_rounded),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: products.map((p) {
                                return DropdownMenuItem(
                                  value: p.perfumeCode,
                                  child: Text(
                                    '[${p.perfumeCode}] ${p.name} • ${p.bottleSize.toUpperCase()} (${p.category})',
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final p = products.firstWhere(
                                    (item) => item.perfumeCode == val,
                                  );
                                  setState(() {
                                    _selectedProductCode = val;
                                    _selectedShelf = p.shelfLayer;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: 20),

                            // Current Shelf Inventory Status Pill
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: context.surfaceElevatedColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.inventory_2_outlined,
                                    color: AppColors.brandAccent,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Current Shelf Stock: $currentStock / $maxTrayCapacity Bottles',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          'Assigned Tray Layer: ${selectedProduct.shelfLayer} • Slot Code: ${selectedProduct.perfumeCode}',
                                          style: TextStyle(
                                            color: context.textSecondaryColor,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Restock Quantity Stepper
                            Text(
                              'Bottles Being Added To Shelf',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                                      Text(
                                        '$_restockQty',
                                        style: const TextStyle(
                                          fontSize: 24,
                                          fontWeight: FontWeight.w900,
                                          color: AppColors.brandAccent,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Text(
                                        'Bottles',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      IconButton.filledTonal(
                                        onPressed: _restockQty > 1
                                            ? () => setState(() => _restockQty--)
                                            : null,
                                        icon: const Icon(Icons.remove, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton.filledTonal(
                                        onPressed: _restockQty < 20
                                            ? () => setState(() => _restockQty++)
                                            : null,
                                        icon: const Icon(Icons.add, size: 20),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (willExceed) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.statusOrange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppColors.statusOrange.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: AppColors.statusOrange, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Adding $_restockQty bottles will bring total stock to ${currentStock + _restockQty}, exceeding standard tray capacity ($maxTrayCapacity). Ensure physical space allows.',
                                        style: const TextStyle(fontSize: 12, color: AppColors.statusOrange),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),

                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                onPressed: () => setState(() => _currentStep = 1),
                                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                                label: const Text('Proceed to Placement Guide'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Step 2: Shelf Placement Guide
              Step(
                title: const Text('2. Shelf Guide'),
                isActive: _currentStep >= 1,
                state: _currentStep > 1 ? StepState.complete : StepState.indexed,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: context.surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: context.borderColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Step 2: Physical Shelf Placement Guide',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Take the $_restockQty bottle(s) and physically place them into the assigned shelf tray.',
                              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                            ),
                            const SizedBox(height: 20),

                            // Visual Target Shelf Banner
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.brandAccent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppColors.brandAccent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'CAM $targetCamId',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Target: ${selectedProduct.shelfLayer}',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: AppColors.brandAccent,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Tray Designation: Slot ${selectedProduct.perfumeCode} (${selectedProduct.bottleSize}) • Category: ${selectedProduct.category}',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: context.textPrimaryColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Physical Placement Rules Card
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.surfaceElevatedColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '📋 Physical Placement Requirements:',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                                  ),
                                  const SizedBox(height: 10),
                                  _buildGuideItem(
                                    Icons.arrow_upward_rounded,
                                    'Upright Placement: Bottles must stand vertically within the tray boundary.',
                                  ),
                                  _buildGuideItem(
                                    Icons.visibility_rounded,
                                    'Cap Label Visibility: Ensure printed OCR code cap is upright and unblocked.',
                                  ),
                                  _buildGuideItem(
                                    Icons.do_not_disturb_on_rounded,
                                    'No Foreign Items: Do not place testers, paper, or other scent bottles in this tray.',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton.icon(
                                  onPressed: () => setState(() => _currentStep = 0),
                                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                                  label: const Text('Back'),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () => setState(() => _currentStep = 2),
                                  icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
                                  label: const Text('Bottles Placed - Proceed to Verification'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.statusGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

              // Step 3: Verification & Save
              Step(
                title: const Text('3. Verify & Save'),
                isActive: _currentStep >= 2,
                state: StepState.indexed,
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      color: context.surfaceColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: context.borderColor),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Step 3: Verify Restock on Shelf',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'You can run a quick shelf camera scan to verify OCR bottle counts, or immediately confirm this delivery.',
                              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                            ),
                            const SizedBox(height: 20),

                            // Summary Box
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: context.surfaceElevatedColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Column(
                                children: [
                                  _buildSummaryRow(context, 'Fragrance', selectedProduct.name),
                                  const Divider(height: 16),
                                  _buildSummaryRow(context, 'Cap Code / Size', '${selectedProduct.perfumeCode} • ${selectedProduct.bottleSize}'),
                                  const Divider(height: 16),
                                  _buildSummaryRow(context, 'Target Shelf', '${selectedProduct.shelfLayer} (Camera $targetCamId)'),
                                  const Divider(height: 16),
                                  _buildSummaryRow(context, 'Restock Quantity', '+$_restockQty Bottles', valueColor: AppColors.statusGreen),
                                ],
                              ),
                            ),
                            const SizedBox(height: 18),

                            // Delivery Notes
                            TextFormField(
                              controller: _notesController,
                              maxLines: 2,
                              style: TextStyle(fontSize: 14, color: context.textPrimaryColor),
                              decoration: InputDecoration(
                                labelText: 'Batch Notes / Delivery Ref (Optional)',
                                hintText: 'e.g. Supplier invoice #8812, Restock batch A',
                                prefixIcon: const Icon(Icons.note_alt_outlined),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Verification Scan Button
                            SizedBox(
                              width: double.infinity,
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _isSaving
                                    ? null
                                    : () async {
                                        await ScanWorkflowDialog.show(
                                          context,
                                          initialCameraId: targetCamId,
                                        );
                                      },
                                icon: const Icon(Icons.radar_rounded, size: 22, color: AppColors.brandAccent),
                                label: Text(
                                  'Quick Tray Verification Scan (Camera $targetCamId)',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: AppColors.brandAccent, width: 1.5),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Confirm & Save
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : () => _submitRestock(verifiedViaScan: false),
                                icon: _isSaving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.check_circle_rounded, size: 22),
                                label: Text(
                                  _isSaving ? 'Saving Restock Batch...' : 'Confirm & Log Restock Batch',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brandAccent,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildGuideItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.brandAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSummaryRow(BuildContext context, String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: context.textSecondaryColor, fontSize: 13)),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: valueColor ?? context.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}
