import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';

class CreateRestockScreen extends ConsumerStatefulWidget {
  const CreateRestockScreen({super.key});

  @override
  ConsumerState<CreateRestockScreen> createState() => _CreateRestockScreenState();
}

class _CreateRestockScreenState extends ConsumerState<CreateRestockScreen> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedProductCode;
  String? _selectedShelf;
  int _expectedQty = 5;
  final TextEditingController _notesController = TextEditingController();

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _submitRestock() async {
    if (_formKey.currentState?.validate() ?? false) {
      if (_selectedProductCode == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a perfume product.')),
        );
        return;
      }

      final products = await ref.read(masterProductsProvider.future);
      final product = products.firstWhere((p) => p.perfumeCode == _selectedProductCode);

      final event = InventoryEventModel(
        id: 'evt_${DateTime.now().millisecondsSinceEpoch}',
        eventType: 'RESTOCKED',
        productName: product.name,
        perfumeCode: product.perfumeCode,
        shelfArea: _selectedShelf ?? product.shelfLayer,
        branch: 'San Pablo',
        quantity: _expectedQty,
        timestamp: DateTime.now(),
      );

      await SqliteService.instance.logInventoryEvent(event);
      ref.invalidate(stockMovementLogsProvider('San Pablo'));
      ref.invalidate(liveInventoryProvider('San Pablo'));
      ref.invalidate(dashboardStatsProvider('San Pablo'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restocked $_expectedQty bottles of ${product.name} (${product.perfumeCode}).'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(masterProductsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Incoming Restock Delivery'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Incoming Delivery Details',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Log the expected quantity from your supplier invoice before stocking the physical shelves.',
                        style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                      ),
                      const SizedBox(height: 24),

                      // Dynamic Product Selector
                      productsAsync.when(
                        data: (products) {
                          if (products.isEmpty) {
                            return const Text('No products available.');
                          }
                          _selectedProductCode ??= products.first.perfumeCode;
                          return DropdownButtonFormField<String>(
                            initialValue: _selectedProductCode,
                            dropdownColor: context.surfaceElevatedColor,
                            style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                            decoration: const InputDecoration(
                              labelText: 'Select Perfume Product',
                              prefixIcon: Icon(Icons.sanitizer_rounded),
                            ),
                            items: products.map((p) {
                              return DropdownMenuItem(
                                value: p.perfumeCode,
                                child: Text('[${p.perfumeCode}] ${p.name} (${p.bottleSize.toUpperCase()})'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                final p = products.firstWhere((item) => item.perfumeCode == val);
                                setState(() {
                                  _selectedProductCode = val;
                                  _selectedShelf = p.shelfLayer;
                                });
                              }
                            },
                          );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (err, _) => Text('Error loading products: $err'),
                      ),
                      const SizedBox(height: 18),

                      // Target Shelf Layer Selector (3 Fixed Cameras)
                      DropdownButtonFormField<String>(
                        initialValue: _selectedShelf ?? 'Layer A (Top)',
                        dropdownColor: context.surfaceElevatedColor,
                        style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                        decoration: const InputDecoration(
                          labelText: 'Target Shelf Layer (Camera)',
                          prefixIcon: Icon(Icons.videocam_rounded),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Layer A (Top)', child: Text('Camera 1: Layer A (Top Shelf - Male)')),
                          DropdownMenuItem(value: 'Layer B (Middle)', child: Text('Camera 2: Layer B (Middle Shelf - Mixed)')),
                          DropdownMenuItem(value: 'Layer C (Bottom)', child: Text('Camera 3: Layer C (Bottom Shelf - Female)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedShelf = val);
                        },
                      ),
                      const SizedBox(height: 24),

                      // Expected Quantity Stepper
                      Text(
                        'Expected Delivery Quantity (Bottles)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: context.surfaceElevatedColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$_expectedQty Bottles',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppColors.brandAccent,
                              ),
                            ),
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  onPressed: () {
                                    if (_expectedQty > 1) {
                                      setState(() => _expectedQty--);
                                    }
                                  },
                                  icon: const Icon(Icons.remove, size: 24),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filledTonal(
                                  onPressed: () {
                                    setState(() => _expectedQty++);
                                  },
                                  icon: const Icon(Icons.add, size: 24),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Notes & Batch Remarks
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                        decoration: const InputDecoration(
                          labelText: 'Batch Notes / Delivery Invoice Ref (Optional)',
                          hintText: 'e.g. PO-2026-08, Fragrance supplier batch #992',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Submit Restock Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _submitRestock,
                          icon: const Icon(Icons.check_circle_outline_rounded, size: 22),
                          label: const Text(
                            'Confirm & Save Restock Batch',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
      ),
    );
  }
}
