import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/product_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
  });

  final ProductModel? product;

  bool get isEditMode => product != null;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final TextEditingController _capCodeController;
  late final TextEditingController _brandController;
  late final TextEditingController _slotController;

  String _selectedCategory = 'Men';
  String _selectedBottleSize = '100ml';
  String _selectedLayer = 'Layer A (Top)';

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _capCodeController = TextEditingController(text: p?.perfumeCode ?? '');
    _brandController = TextEditingController(text: p?.brand ?? '');
    _slotController = TextEditingController(text: '${p?.slotPosition ?? 1}');

    if (p != null) {
      _selectedCategory = p.category;
      _selectedBottleSize = p.bottleSize.toLowerCase();
      _selectedLayer = p.shelfLayer;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capCodeController.dispose();
    _brandController.dispose();
    _slotController.dispose();
    super.dispose();
  }

  void _saveProduct() async {
    if (_formKey.currentState?.validate() ?? false) {
      final product = ProductModel(
        id: widget.product?.id ?? 'prod_${DateTime.now().millisecondsSinceEpoch}',
        name: _nameController.text.trim(),
        perfumeCode: _capCodeController.text.trim().toUpperCase(),
        brand: _brandController.text.trim().isEmpty ? 'Otto Scents' : _brandController.text.trim(),
        category: _selectedCategory,
        bottleSize: _selectedBottleSize.toLowerCase(),
        shelfLayer: _selectedLayer,
        slotPosition: int.tryParse(_slotController.text.trim()) ?? 1,
        price: 0.0,
        status: 'active',
      );

      await SqliteService.instance.saveProduct(product);
      ref.invalidate(masterProductsProvider);
      ref.invalidate(liveInventoryProvider('San Pablo'));
      ref.invalidate(dashboardStatsProvider('San Pablo'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Saved ${product.name} with Cap Code ${product.perfumeCode}!'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Product & Cap OCR Code' : 'Register Perfume Product'),
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
                        'Product & OCR Cap Code Information',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Ensure the 3-character cap code (e.g. AA1, BF2) matches the text printed on top of the bottle cap for PaddleOCR camera recognition.',
                        style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                      ),
                      const SizedBox(height: 24),

                      // Product Name Field
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 16, color: context.textPrimaryColor),
                        decoration: const InputDecoration(
                          labelText: 'Fragrance Name',
                          hintText: 'e.g. Sauvage, Cool Water, Chanel Chance',
                          prefixIcon: Icon(Icons.sanitizer_rounded),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter fragrance name' : null,
                      ),
                      const SizedBox(height: 18),

                      // Cap Code & Brand Row
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _capCodeController,
                              style: TextStyle(fontSize: 16, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: '3-Char Cap OCR Code',
                                hintText: 'e.g. AA1, BA2, CK1',
                                prefixIcon: Icon(Icons.qr_code_2_rounded),
                                helperText: 'Format: [Layer A/B/C][Slot A-K][Size 1/2]',
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Please enter 3-character code';
                                if (value.trim().length != 3) return 'Code must be exactly 3 characters';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _brandController,
                              style: TextStyle(fontSize: 16, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: 'Brand / House',
                                hintText: 'e.g. Christian Dior, Bvlgari, Chanel',
                                prefixIcon: Icon(Icons.verified_outlined),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Bottle Size, Shelf Camera Layer & Category Row
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedBottleSize,
                              dropdownColor: context.surfaceElevatedColor,
                              style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: 'Bottle Size',
                                prefixIcon: Icon(Icons.local_drink_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(value: '100ml', child: Text('100ML (Size 1)')),
                                DropdownMenuItem(value: '50ml', child: Text('50ML (Size 2)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedBottleSize = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedLayer,
                              dropdownColor: context.surfaceElevatedColor,
                              style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: 'Shelf Layer & Camera',
                                prefixIcon: Icon(Icons.videocam_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Layer A (Top)', child: Text('📷 Camera 1: Top (Male)')),
                                DropdownMenuItem(value: 'Layer B (Middle)', child: Text('📷 Camera 2: Middle (Mixed)')),
                                DropdownMenuItem(value: 'Layer C (Bottom)', child: Text('📷 Camera 3: Bottom (Female)')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedLayer = val);
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedCategory,
                              dropdownColor: context.surfaceElevatedColor,
                              style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: 'Fragrance Category',
                                prefixIcon: Icon(Icons.category_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Men', child: Text('Men')),
                                DropdownMenuItem(value: 'Women', child: Text('Women')),
                                DropdownMenuItem(value: 'Unisex', child: Text('Unisex')),
                              ],
                              onChanged: (val) {
                                if (val != null) setState(() => _selectedCategory = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Submit Action Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _saveProduct,
                          icon: const Icon(Icons.save_rounded, size: 22),
                          label: Text(
                            widget.isEditMode ? 'Update Product SKU' : 'Save Perfume Product',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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
