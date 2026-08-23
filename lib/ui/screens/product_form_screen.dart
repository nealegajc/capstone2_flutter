import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../data/models/inventory_record_model.dart';
import '../components/app_button.dart';
import '../components/form_widgets.dart';
import '../components/scroll_screen.dart';

class ProductFormScreen extends StatefulWidget {
  final InventoryRecordModel? initialItem;
  final VoidCallback onBack;

  const ProductFormScreen({
    super.key,
    this.initialItem,
    required this.onBack,
  });

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  String _selectedCode = 'A';
  String _selectedCategory = 'Men';
  String _selectedBranch = 'San Pablo';
  int _recordedQty = 5;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _nameController = TextEditingController(text: item?.name ?? '');
    _priceController = TextEditingController(text: item?.price.toStringAsFixed(0) ?? '250');
    _selectedCode = item?.perfumeCode ?? 'A';
    _selectedCategory = item?.category ?? 'Men';
    _selectedBranch = item?.branch ?? 'San Pablo';
    _recordedQty = item?.recorded ?? 5;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _handleSave() {
    if (_nameController.text.trim().isEmpty) return;

    final provider = context.read<AppProvider>();
    final isEditing = widget.initialItem != null;

    final updated = InventoryRecordModel(
      id: widget.initialItem?.id ?? 'inv_${_selectedBranch.toLowerCase().replaceAll(' ', '_')}_$_selectedCode',
      perfumeCode: _selectedCode,
      name: _nameController.text.trim(),
      category: _selectedCategory,
      branch: _selectedBranch,
      shelf: 'Area $_selectedCode',
      recorded: _recordedQty,
      detected: isEditing ? widget.initialItem!.detected : _recordedQty,
      status: isEditing ? widget.initialItem!.status : 'normal',
      price: double.tryParse(_priceController.text) ?? 250.0,
    );

    provider.saveInventoryRecord(updated);
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialItem != null;

    return ScrollScreen(
      title: isEditing ? 'Edit Product' : 'Register New Product',
      subtitle: isEditing
          ? 'Update SKU details and shelf assignments'
          : 'Add a new perfume variant for YOLO detection and PaddleOCR recognition',
      showBackButton: true,
      onBack: widget.onBack,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Perfume Letter Code Picker (A, B, C, D)
              AppDropdownField<String>(
                label: 'Perfume Letter Code (Cap OCR Tag)',
                value: _selectedCode,
                items: ['A', 'B', 'C', 'D'].map((code) {
                  return DropdownMenuItem(
                    value: code,
                    child: Text('Perfume Code $code (Shelf Area $code)'),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedCode = val);
                },
              ),
              const SizedBox(height: 20),

              AppTextField(
                label: 'Product Name',
                hint: 'e.g. Otto Scents Ocean Breeze',
                controller: _nameController,
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: AppDropdownField<String>(
                      label: 'Category',
                      value: _selectedCategory,
                      items: ['Men', 'Women', 'Unisex'].map((cat) {
                        return DropdownMenuItem(value: cat, child: Text(cat));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedCategory = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: AppDropdownField<String>(
                      label: 'Branch Assignment',
                      value: _selectedBranch,
                      items: ['San Pablo', 'Lipa'].map((b) {
                        return DropdownMenuItem(value: b, child: Text(b));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedBranch = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      label: 'Retail Price (PHP)',
                      hint: '250',
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StepperSettingRow(
                      title: 'Standard Shelf Capacity',
                      description: 'Max bottles per shelf area',
                      value: _recordedQty,
                      min: 1,
                      max: 20,
                      onChanged: (val) => setState(() => _recordedQty = val),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 36),

              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: isEditing ? 'Save Changes' : 'Register Product',
                      icon: Icons.check_circle_outline_rounded,
                      onPressed: _handleSave,
                      height: 56,
                    ),
                  ),
                  const SizedBox(width: 16),
                  AppButton(
                    text: 'Cancel',
                    variant: AppButtonVariant.outline,
                    onPressed: widget.onBack,
                    height: 56,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
