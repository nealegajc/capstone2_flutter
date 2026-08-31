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

  String _selectedCategory = 'Men';
  String _selectedBottleSize = '100ml';
  String _selectedLayer = 'Layer A (Top)';
  int _selectedSlotPosition = 1; // 1 to 10 (Slots A to K)
  bool _createBothSizes = false;
  bool _isSeasonalOff = false;

  final List<String> _slotLetters = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K'];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _capCodeController = TextEditingController(text: p?.perfumeCode ?? 'AA1');
    _brandController = TextEditingController(text: p?.brand ?? 'Otto Scents');

    _capCodeController.addListener(() {
      if (mounted) setState(() {});
    });

    if (p != null) {
      _selectedCategory = p.category;
      _selectedBottleSize = p.bottleSize.toLowerCase();
      _selectedLayer = p.shelfLayer;
      _selectedSlotPosition = p.slotPosition;
      _isSeasonalOff = p.isSeasonalOff;
    } else {
      _autoGenerateCapCode();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _capCodeController.dispose();
    _brandController.dispose();
    super.dispose();
  }

  void _autoGenerateCapCode() {
    String layerLetter = 'A';
    if (_selectedLayer.contains('Layer B')) layerLetter = 'B';
    if (_selectedLayer.contains('Layer C')) layerLetter = 'C';

    final slotIdx = (_selectedSlotPosition - 1).clamp(0, _slotLetters.length - 1);
    final slotLetter = _slotLetters[slotIdx];
    final sizeDigit = _selectedBottleSize == '100ml' ? '1' : '2';

    _capCodeController.text = '$layerLetter$slotLetter$sizeDigit';
  }

  void _selectLayerAndSlot(String layer, int slot) {
    setState(() {
      _selectedLayer = layer;
      _selectedSlotPosition = slot;

      // Auto-set gender based on layer and slot standard layout
      if (layer.contains('Layer A')) {
        _selectedCategory = 'Men';
      } else if (layer.contains('Layer C')) {
        _selectedCategory = 'Women';
      } else if (layer.contains('Layer B')) {
        _selectedCategory = slot <= 5 ? 'Men' : 'Women';
      }

      _autoGenerateCapCode();
    });
  }

  void _confirmDeleteProduct() async {
    if (widget.product == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: AppColors.statusRed, size: 28),
            const SizedBox(width: 12),
            Text('Delete Fragrance SKU', style: TextStyle(color: context.textPrimaryColor, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Are you sure you want to remove "${widget.product!.name}" (${widget.product!.perfumeCode}) from the catalog? This will free up its physical shelf slot.',
          style: TextStyle(color: context.textSecondaryColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusRed, foregroundColor: Colors.white),
            child: const Text('Delete & Free Slot'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await SqliteService.instance.deleteProduct(widget.product!.id);
      ref.invalidate(masterProductsProvider);
      ref.invalidate(liveInventoryProvider('San Pablo'));
      ref.invalidate(dashboardStatsProvider('San Pablo'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed ${widget.product!.name}. Slot freed for new fragrance registration.'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        context.pop();
      }
    }
  }

  void _saveProduct(bool isShelfFull) async {
    if (!widget.isEditMode && isShelfFull) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Shelf is at maximum physical capacity (30/30 slots). No more slots available.'),
          backgroundColor: AppColors.statusRed,
        ),
      );
      return;
    }

    if (_formKey.currentState?.validate() ?? false) {
      final name = _nameController.text.trim();
      final brand = _brandController.text.trim().isEmpty ? 'Otto Scents' : _brandController.text.trim();
      final baseCapCode = _capCodeController.text.trim().toUpperCase();

      String layerLetter = 'A';
      if (_selectedLayer.contains('Layer B')) layerLetter = 'B';
      if (_selectedLayer.contains('Layer C')) layerLetter = 'C';
      final slotIdx = (_selectedSlotPosition - 1).clamp(0, _slotLetters.length - 1);
      final slotLetter = _slotLetters[slotIdx];
      final prefix = '$layerLetter$slotLetter';

      if (_createBothSizes && !widget.isEditMode) {
        // Create Size 1 (100ml)
        final p1 = ProductModel(
          id: 'prod_${prefix}1_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          perfumeCode: '${prefix}1',
          brand: brand,
          category: _selectedCategory,
          bottleSize: '100ml',
          shelfLayer: _selectedLayer,
          slotPosition: _selectedSlotPosition,
          price: 0.0,
          status: _isSeasonalOff ? 'seasonal_off' : 'active',
        );
        // Create Size 2 (50ml)
        final p2 = ProductModel(
          id: 'prod_${prefix}2_${DateTime.now().millisecondsSinceEpoch + 1}',
          name: name,
          perfumeCode: '${prefix}2',
          brand: brand,
          category: _selectedCategory,
          bottleSize: '50ml',
          shelfLayer: _selectedLayer,
          slotPosition: _selectedSlotPosition,
          price: 0.0,
          status: _isSeasonalOff ? 'seasonal_off' : 'active',
        );

        await SqliteService.instance.saveProduct(p1);
        await SqliteService.instance.saveProduct(p2);
      } else {
        final product = ProductModel(
          id: widget.product?.id ?? 'prod_${baseCapCode}_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          perfumeCode: baseCapCode,
          brand: brand,
          category: _selectedCategory,
          bottleSize: _selectedBottleSize.toLowerCase(),
          shelfLayer: _selectedLayer,
          slotPosition: _selectedSlotPosition,
          price: 0.0,
          status: _isSeasonalOff ? 'seasonal_off' : 'active',
        );

        await SqliteService.instance.saveProduct(product);
      }

      ref.invalidate(masterProductsProvider);
      ref.invalidate(liveInventoryProvider('San Pablo'));
      ref.invalidate(dashboardStatsProvider('San Pablo'));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _createBothSizes && !widget.isEditMode
                  ? 'Registered $name (100ML & 50ML • Codes ${prefix}1 & ${prefix}2) successfully.'
                  : '${widget.isEditMode ? "Updated" : "Registered"} $name ($baseCapCode) successfully.',
            ),
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
    final allItems = productsAsync.valueOrNull ?? [];

    final uniqueVariants = allItems
        .map((p) => p.perfumeCode.length >= 2 ? p.perfumeCode.substring(0, 2) : p.name)
        .toSet();
    final variantCount = uniqueVariants.length;
    final isShelfFull = !widget.isEditMode && variantCount >= 30;

    // Map slot assignments to existing products
    final slotToProductMap = <String, ProductModel>{};
    for (final p in allItems) {
      final key = '${p.shelfLayer}_${p.slotPosition}';
      slotToProductMap[key] ??= p;
    }

    final isFemale = _selectedCategory == 'Women';
    final themeGenderColor = isFemale ? AppColors.femalePink : AppColors.maleBlue;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditMode ? 'Edit Fragrance SKU' : 'Register Fragrance Product'),
        actions: [
          if (widget.isEditMode)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.statusRed),
              tooltip: 'Delete & Free Slot',
              onPressed: _confirmDeleteProduct,
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shelf Full Capacity Lock Banner (When adding new product and >= 30 variants)
              if (isShelfFull)
                Container(
                  margin: const EdgeInsets.only(bottom: 20),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.statusRedBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.statusRed.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline_rounded, color: AppColors.statusRed, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Shelf Capacity Reached (30 / 30 Physical Slots Occupied)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: AppColors.statusRed,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'No more slots available on the 3-layer shelf. Adding new products is locked until a slot is freed or an existing fragrance is edited from the inventory list.',
                              style: TextStyle(fontSize: 12, color: context.textPrimaryColor),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // 1. Interactive 3-Layer Physical Shelf Matrix
              Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.shelves, color: AppColors.brandAccent, size: 22),
                              const SizedBox(width: 10),
                              Text(
                                'Physical Shelf Slot Selector (30 Slots)',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: themeGenderColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: themeGenderColor.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              'Selected: $_selectedLayer • Slot ${_slotLetters[_selectedSlotPosition - 1]}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: themeGenderColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tap any slot partition on the shelf to configure position and cap OCR alignment.',
                        style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                      ),
                      Divider(height: 24, color: context.borderColor),

                      // Layer A (Top - Men)
                      _buildShelfLayerRow(
                        context: context,
                        layerTitle: 'Layer A (Top) • Men',
                        layerKey: 'Layer A (Top)',
                        color: AppColors.maleBlue,
                        slotMap: slotToProductMap,
                      ),
                      const SizedBox(height: 12),

                      // Layer B (Middle - Mixed)
                      _buildShelfLayerRow(
                        context: context,
                        layerTitle: 'Layer B (Middle) • Mixed',
                        layerKey: 'Layer B (Middle)',
                        color: AppColors.brandAccent,
                        slotMap: slotToProductMap,
                        isMixed: true,
                      ),
                      const SizedBox(height: 12),

                      // Layer C (Bottom - Women)
                      _buildShelfLayerRow(
                        context: context,
                        layerTitle: 'Layer C (Bottom) • Women',
                        layerKey: 'Layer C (Bottom)',
                        color: AppColors.femalePink,
                        slotMap: slotToProductMap,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 2. Product Specifications Card
              Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header & Live Cap OCR Preview
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.isEditMode ? 'Fragrance Specifications' : 'Fragrance Registration Details',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bottle name, brand, gender category, and PaddleOCR recognition code.',
                                  style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                                ),
                              ],
                            ),
                          ),

                          // Live Cap OCR Preview Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: isFemale
                                    ? const [Color(0xFFEC4899), Color(0xFFBE185D)]
                                    : const [Color(0xFF0284C7), Color(0xFF0369A1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: themeGenderColor.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _capCodeController.text.isEmpty ? 'AA1' : _capCodeController.text.toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                                Text(
                                  isFemale ? 'WOMEN' : 'MEN',
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      Divider(height: 28, color: context.borderColor),

                      // Target Gender
                      Text(
                        'TARGET GENDER',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: context.textSecondaryColor,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = 'Men';
                                  _autoGenerateCapCode();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: !isFemale ? AppColors.maleBlue.withValues(alpha: 0.15) : context.surfaceElevatedColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: !isFemale ? AppColors.maleBlue : context.borderColor,
                                    width: !isFemale ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.male_rounded, color: !isFemale ? AppColors.maleBlue : context.textSecondaryColor, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Men\'s Fragrance',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: !isFemale ? AppColors.maleBlue : context.textPrimaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = 'Women';
                                  _autoGenerateCapCode();
                                });
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: isFemale ? AppColors.femalePink.withValues(alpha: 0.15) : context.surfaceElevatedColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isFemale ? AppColors.femalePink : context.borderColor,
                                    width: isFemale ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.female_rounded, color: isFemale ? AppColors.femalePink : context.textSecondaryColor, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Women\'s Fragrance',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: isFemale ? AppColors.femalePink : context.textPrimaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Fragrance Name
                      TextFormField(
                        controller: _nameController,
                        style: TextStyle(fontSize: 15, color: context.textPrimaryColor, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          labelText: 'Fragrance Name',
                          hintText: 'e.g. Sauvage, Bleu de Chanel, Eclat D\'Arpege',
                          prefixIcon: Icon(Icons.sanitizer_rounded),
                        ),
                        validator: (value) => (value == null || value.trim().isEmpty) ? 'Please enter fragrance name' : null,
                      ),
                      const SizedBox(height: 16),

                      // Brand
                      TextFormField(
                        controller: _brandController,
                        style: TextStyle(fontSize: 15, color: context.textPrimaryColor),
                        decoration: const InputDecoration(
                          labelText: 'Brand / Fragrance House',
                          hintText: 'e.g. Otto Scents, Dior, Chanel, Bvlgari',
                          prefixIcon: Icon(Icons.verified_outlined),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: ['Otto Scents', 'Dior', 'Chanel', 'YSL', 'Tom Ford', 'Creed', 'Bvlgari', 'Jo Malone'].map((b) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: ActionChip(
                                label: Text(b, style: const TextStyle(fontSize: 11)),
                                onPressed: () => setState(() => _brandController.text = b),
                                backgroundColor: context.surfaceElevatedColor,
                                side: BorderSide(color: context.borderColor),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Bottle Size & Dual-Size Option
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _selectedBottleSize,
                              dropdownColor: context.surfaceElevatedColor,
                              style: TextStyle(fontSize: 14, color: context.textPrimaryColor),
                              decoration: const InputDecoration(
                                labelText: 'Bottle Size / SKU',
                                prefixIcon: Icon(Icons.local_drink_rounded),
                              ),
                              items: const [
                                DropdownMenuItem(value: '100ml', child: Text('100ML (Size 1)')),
                                DropdownMenuItem(value: '50ml', child: Text('50ML (Size 2)')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedBottleSize = val;
                                    _autoGenerateCapCode();
                                  });
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextFormField(
                              controller: _capCodeController,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: themeGenderColor,
                                letterSpacing: 1.5,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Cap OCR Code',
                                hintText: 'e.g. AA1',
                                prefixIcon: const Icon(Icons.qr_code_2_rounded),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                                  tooltip: 'Auto-Generate',
                                  onPressed: () => setState(() => _autoGenerateCapCode()),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Enter 3-character code';
                                if (value.trim().length != 3) return 'Must be 3 chars';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      if (!widget.isEditMode) ...[
                        const SizedBox(height: 12),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Register both 100ML (Size 1) and 50ML (Size 2) for this slot',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Generates both SKUs for this fragrance slot partition automatically.',
                            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                          ),
                          value: _createBothSizes,
                          activeColor: AppColors.brandAccent,
                          onChanged: (val) => setState(() => _createBothSizes = val ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],

                      const SizedBox(height: 14),

                      // Seasonal Fragrance Rotation Switch
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isSeasonalOff
                              ? (context.isDark ? const Color(0xFF1F1A14) : const Color(0xFFFFFBEB))
                              : context.surfaceElevatedColor,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _isSeasonalOff ? AppColors.statusOrange.withValues(alpha: 0.6) : context.borderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: (_isSeasonalOff ? AppColors.statusOrange : AppColors.statusGreen).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _isSeasonalOff ? Icons.wb_sunny_outlined : Icons.check_circle_outline_rounded,
                                color: _isSeasonalOff ? AppColors.statusOrange : AppColors.statusGreen,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isSeasonalOff ? 'Seasonal Scent (Turned Off)' : 'Active On Shelf',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  Text(
                                    _isSeasonalOff
                                        ? 'Paused from active shelf inventory scans.'
                                        : 'Actively stocked and monitored on the kiosk shelf.',
                                    style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Switch(
                              value: !_isSeasonalOff,
                              activeColor: AppColors.statusGreen,
                              inactiveThumbColor: AppColors.statusOrange,
                              onChanged: (active) => setState(() => _isSeasonalOff = !active),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Submit Action Button (Locked if shelf full and adding new)
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton.icon(
                          onPressed: isShelfFull ? null : () => _saveProduct(isShelfFull),
                          icon: Icon(widget.isEditMode ? Icons.save_rounded : (isShelfFull ? Icons.lock_outline_rounded : Icons.add_circle_outline_rounded), size: 20),
                          label: Text(
                            widget.isEditMode
                                ? 'Update Fragrance SKU'
                                : (isShelfFull ? 'Shelf Full (30/30 Slots Occupied)' : 'Save Fragrance Product'),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isShelfFull ? Colors.grey : AppColors.brandAccent,
                            foregroundColor: Colors.white,
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

  Widget _buildShelfLayerRow({
    required BuildContext context,
    required String layerTitle,
    required String layerKey,
    required Color color,
    required Map<String, ProductModel> slotMap,
    bool isMixed = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              layerTitle,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: context.textPrimaryColor),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(10, (idx) {
            final slotNum = idx + 1;
            final slotLetter = _slotLetters[idx];
            final isSelected = _selectedLayer == layerKey && _selectedSlotPosition == slotNum;
            final key = '${layerKey}_$slotNum';
            final occupiedProduct = slotMap[key];

            Color slotColor = color;
            if (isMixed) {
              slotColor = slotNum <= 5 ? AppColors.maleBlue : AppColors.femalePink;
            }

            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () => _selectLayerAndSlot(layerKey, slotNum),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? slotColor
                          : (occupiedProduct != null
                              ? slotColor.withValues(alpha: context.isDark ? 0.25 : 0.15)
                              : context.surfaceElevatedColor),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? Colors.white
                            : (occupiedProduct != null ? slotColor.withValues(alpha: 0.5) : context.borderColor),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          slotLetter,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: isSelected ? Colors.white : context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          occupiedProduct != null
                              ? occupiedProduct.perfumeCode
                              : 'Empty',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: isSelected
                                ? Colors.white70
                                : (occupiedProduct != null ? slotColor : context.textMutedColor),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}
