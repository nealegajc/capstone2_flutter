import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/models/inventory_event_model.dart';
import '../../data/models/inventory_record_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/restock_record_model.dart';
import '../../data/models/sale_record_model.dart';
import '../../data/seeds/catalog_seed_data.dart';
import '../../data/services/sqlite_service.dart';
import '../../data/services/toast_service.dart';
import '../../providers/kiosk_providers.dart';
import '../../providers/sales_provider.dart';
import 'manager_pin_dialog.dart';
import 'verification_method_dialog.dart';

enum StockMovementType {
  sale,
  restock,
  customerReturn,
  damagedWriteOff,
}

class StockMovementHubDialog extends ConsumerStatefulWidget {
  final ProductModel? initialProduct;
  final String? initialPerfumeCode;
  final StockMovementType initialType;
  final bool fromDeficitDiscrepancy;
  final int? maxDeficitQty;
  final bool fromSurplusDiscrepancy;
  final int? maxSurplusQty;

  const StockMovementHubDialog({
    super.key,
    this.initialProduct,
    this.initialPerfumeCode,
    this.initialType = StockMovementType.sale,
    this.fromDeficitDiscrepancy = false,
    this.maxDeficitQty,
    this.fromSurplusDiscrepancy = false,
    this.maxSurplusQty,
  });

  static Future<void> show(
    BuildContext context, {
    ProductModel? initialProduct,
    String? initialPerfumeCode,
    StockMovementType initialType = StockMovementType.sale,
    bool fromDeficitDiscrepancy = false,
    int? maxDeficitQty,
    bool fromSurplusDiscrepancy = false,
    int? maxSurplusQty,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => StockMovementHubDialog(
        initialProduct: initialProduct,
        initialPerfumeCode: initialPerfumeCode,
        initialType: initialType,
        fromDeficitDiscrepancy: fromDeficitDiscrepancy,
        maxDeficitQty: maxDeficitQty,
        fromSurplusDiscrepancy: fromSurplusDiscrepancy,
        maxSurplusQty: maxSurplusQty,
      ),
    );
  }

  @override
  ConsumerState<StockMovementHubDialog> createState() =>
      _StockMovementHubDialogState();
}

class _StockMovementHubDialogState extends ConsumerState<StockMovementHubDialog> {
  late StockMovementType _selectedType;
  late bool _isDeficitResolution;
  ProductModel? _selectedProduct;
  List<ProductModel> _allProducts = [];
  InventoryRecordModel? _currentInv;
  bool _isLoading = true;
  bool _isSubmitting = false;

  // Sale & Restock & Return state
  int _quantity = 1;

  // Return specific
  bool _isResellableReturn = true;
  final TextEditingController _returnReasonCtrl = TextEditingController();

  // Damaged Write-Off specific
  String _damageReason = 'Broken Bottle';
  static const List<String> _allowedDamageReasons = [
    'Broken Bottle',
    'Leaking / Evaporated',
    'Defective Atomizer / Cap',
  ];

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
    _isDeficitResolution = widget.fromDeficitDiscrepancy;
    if (widget.maxDeficitQty != null && widget.maxDeficitQty! > 0) {
      _quantity = widget.maxDeficitQty!.clamp(1, 5);
    } else if (widget.maxSurplusQty != null && widget.maxSurplusQty! > 0) {
      _quantity = widget.maxSurplusQty!.clamp(1, 5);
    }
    _selectedProduct = widget.initialProduct;
    _initData();
  }

  @override
  void dispose() {
    _returnReasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    setState(() => _isLoading = true);

    try {
      final products = await SqliteService.instance.getProducts();
      _allProducts = products.isNotEmpty ? products : CatalogSeedData.products;

      if (_selectedProduct == null && widget.initialPerfumeCode != null) {
        _selectedProduct = _allProducts
            .where((p) => p.perfumeCode == widget.initialPerfumeCode)
            .firstOrNull;
        _selectedProduct ??= await SqliteService.instance.getProductByCode(
          widget.initialPerfumeCode!,
        );
      }

      _selectedProduct ??= _allProducts.firstOrNull;

      if (_selectedProduct != null) {
        await _loadInventoryForProduct(_selectedProduct!.perfumeCode);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _isSurplusResolution {
    if (widget.fromSurplusDiscrepancy) return true;
    if (_currentInv != null) {
      return _currentInv!.detected > _currentInv!.recorded;
    }
    return false;
  }

  int get _surplusLimit {
    if (widget.maxSurplusQty != null && widget.maxSurplusQty! > 0) {
      return widget.maxSurplusQty!.clamp(1, 5);
    }
    if (_currentInv != null && _currentInv!.detected > _currentInv!.recorded) {
      return (_currentInv!.detected - _currentInv!.recorded).clamp(1, 5);
    }
    return 5;
  }

  int get _deficitLimit {
    if (widget.maxDeficitQty != null && widget.maxDeficitQty! > 0) {
      return widget.maxDeficitQty!.clamp(1, 5);
    }
    if (_isDeficitResolution && _currentInv != null) {
      final diff = _currentInv!.recorded - _currentInv!.detected;
      if (diff > 0) return diff.clamp(1, 5);
    }
    return 5;
  }

  Future<void> _loadInventoryForProduct(String perfumeCode) async {
    final branch = await SqliteService.instance.getBranchName();
    final inv = await SqliteService.instance.getInventoryRecord(
      perfumeCode,
      branch,
    );
    if (mounted) {
      setState(() {
        _currentInv = inv;
        // Auto-detect deficit resolution if not explicitly set
        if (!widget.fromDeficitDiscrepancy && inv != null && inv.recorded > inv.detected) {
          _isDeficitResolution = true;
        }
        // Adjust default quantity if deficit or surplus
        if (_isDeficitResolution) {
          final limit = _deficitLimit;
          _quantity = _quantity.clamp(1, limit);
        } else if (_isSurplusResolution && _selectedType == StockMovementType.restock) {
          _quantity = _surplusLimit;
        }
      });
    }
  }

  double get _unitPrice {
    if (_selectedProduct == null) return 260.0;
    return AppConstants.priceFor(_selectedProduct!.bottleSize);
  }

  double get _totalAmount => _unitPrice * _quantity;

  String get _trayCode {
    if (_selectedProduct == null) return 'AA';
    final code = _selectedProduct!.perfumeCode;
    if (code.length >= 2) {
      return code.substring(0, 2).toUpperCase();
    }
    return 'AA';
  }

  Future<bool> _ensureManagerAuth(String actionTitle, String description) async {
    return await ManagerPinDialog.show(
      context,
      actionTitle: actionTitle,
      actionDescription: description,
      targetSku: _selectedProduct?.perfumeCode,
    );
  }

  Future<void> _submitMovement() async {
    if (_isSubmitting || _selectedProduct == null) return;
    final product = _selectedProduct!;
    final branch = await SqliteService.instance.getBranchName();

    switch (_selectedType) {
      case StockMovementType.sale:
        if (!mounted) return;
        final choice = await VerificationMethodDialog.show(
          context,
          actionTitle: 'Record Sale',
          productName: product.name,
          perfumeCode: product.perfumeCode,
          quantity: _quantity,
        );
        if (choice == null || !mounted) return;

        if (choice == StockVerificationChoice.manualRecord) {
          final auth = await _ensureManagerAuth(
            'Authorize Manual Sale Record',
            'Manager PIN authorization required to record manual sale of $_quantity x ${product.name} (₱${_totalAmount.toStringAsFixed(2)})',
          );
          if (!auth || !mounted) return;
        } else {
          // Computer Vision Verification
          setState(() => _isSubmitting = true);
          try {
            final camId = SqliteService.getCameraIdForTray(_trayCode);
            final scanResult = await ref.read(pythonApiRepositoryProvider).triggerManualScan(
              branch,
              cameraId: camId,
              targetTray: _trayCode,
            );
            final rawDets = scanResult['detections'];
            final detectionsList = (rawDets is List)
                ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
                : <Map<String, dynamic>>[];
            if (detectionsList.isNotEmpty || scanResult['success'] == true) {
              await SqliteService.instance.updateTrayInventoryFromDetections(
                cameraId: camId,
                trayCode: _trayCode,
                detections: detectionsList,
                branch: branch,
              );
            }
          } catch (_) {}
        }

        setState(() => _isSubmitting = true);
        try {
          final saleRecord = SaleRecordModel(
            id: 'sale_${DateTime.now().millisecondsSinceEpoch}',
            perfumeCode: product.perfumeCode,
            productName: product.name,
            bottleSize: product.bottleSize,
            quantitySold: _quantity,
            unitPrice: _unitPrice,
            totalAmount: _totalAmount,
            branch: branch,
            soldBy: 'Staff',
            soldAt: DateTime.now(),
            syncStatus: 'synced',
          );
          final event = InventoryEventModel(
            id: 'evt_sale_${DateTime.now().millisecondsSinceEpoch}',
            eventType: 'REMOVED',
            productName: product.name,
            perfumeCode: product.perfumeCode,
            shelfArea: product.shelfLayer,
            branch: branch,
            quantity: _quantity,
            timestamp: DateTime.now(),
          );

          await SqliteService.instance.recordSaleWithInventoryDeduction(
            saleRecord: saleRecord,
            event: event,
            branch: branch,
            isDeficitResolution: _isDeficitResolution,
          );

          _onSuccess('Sale of $_quantity bottle(s) recorded (₱${_totalAmount.toStringAsFixed(2)})');
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        break;

      case StockMovementType.restock:
        if (!mounted) return;
        final choice = await VerificationMethodDialog.show(
          context,
          actionTitle: 'Commit Restock',
          productName: product.name,
          perfumeCode: product.perfumeCode,
          quantity: _quantity,
        );
        if (choice == null || !mounted) return;

        if (choice == StockVerificationChoice.manualRecord) {
          final auth = await _ensureManagerAuth(
            'Authorize Manual Restock',
            'Manager PIN authorization required to commit manual restock of +$_quantity bottle(s) for ${product.name}',
          );
          if (!auth || !mounted) return;
        } else {
          // Computer Vision Verification
          setState(() => _isSubmitting = true);
          try {
            final camId = SqliteService.getCameraIdForTray(_trayCode);
            final scanResult = await ref.read(pythonApiRepositoryProvider).triggerManualScan(
              branch,
              cameraId: camId,
              targetTray: _trayCode,
            );
            final rawDets = scanResult['detections'];
            final detectionsList = (rawDets is List)
                ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
                : <Map<String, dynamic>>[];
            if (detectionsList.isNotEmpty || scanResult['success'] == true) {
              await SqliteService.instance.updateTrayInventoryFromDetections(
                cameraId: camId,
                trayCode: _trayCode,
                detections: detectionsList,
                branch: branch,
              );
            }
          } catch (_) {}
        }

        setState(() => _isSubmitting = true);
        try {
          final now = DateTime.now();
          final event = InventoryEventModel(
            id: 'evt_restock_${now.millisecondsSinceEpoch}',
            eventType: 'RESTOCKED',
            productName: product.name,
            perfumeCode: product.perfumeCode,
            shelfArea: product.shelfLayer,
            branch: branch,
            quantity: _quantity,
            timestamp: now,
          );
          await SqliteService.instance.logInventoryEvent(event);

          final restockRecord = RestockRecordModel(
            id: 'rst_${now.millisecondsSinceEpoch}',
            productName: product.name,
            perfumeCode: product.perfumeCode,
            quantity: _quantity,
            fromBranch: 'Main Warehouse',
            toBranch: branch,
            requestedBy: 'Kiosk Store Manager',
            status: 'received',
            createdAt: now,
          );
          await SqliteService.instance.saveRestockRecord(restockRecord);

          final existing = await SqliteService.instance.getInventoryRecord(
            product.perfumeCode,
            branch,
          );
          final currentRec = existing?.recorded ?? 0;
          final newRecorded = (currentRec + _quantity).clamp(0, 5);
          final updated = InventoryRecordModel(
            id: existing?.id ?? 'inv_${now.millisecondsSinceEpoch}',
            perfumeCode: product.perfumeCode,
            name: product.name,
            category: product.category,
            branch: branch,
            shelf: product.shelfLayer,
            recorded: newRecorded,
            detected: newRecorded, // sync detected to avoid false discrepancy
            status: 'normal',
            misplacementDetails: existing?.misplacementDetails ?? '',
            lastUpdated: now,
            price: product.price,
          );
          await SqliteService.instance.upsertInventoryRecord(updated);
          await SqliteService.instance.markStockAlertsReadForPerfume(
            product.perfumeCode,
            branch: branch,
          );

          _onSuccess('Restock of $_quantity bottle(s) saved for ${product.name}');
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        break;

      case StockMovementType.customerReturn:
        final auth = await _ensureManagerAuth(
          'Authorize Customer Return & Refund',
          'Authorization required for customer return and revenue refund: $_quantity x ${product.name} (-₱${_totalAmount.toStringAsFixed(2)})',
        );
        if (!auth) return;

        setState(() => _isSubmitting = true);
        try {
          await SqliteService.instance.recordCustomerReturnRefund(
            perfumeCode: product.perfumeCode,
            productName: product.name,
            bottleSize: product.bottleSize,
            quantity: _quantity,
            unitPrice: _unitPrice,
            isResellable: _isResellableReturn,
            authorizedBy: 'Store Manager',
            branch: branch,
          );

          _onSuccess(
            'Customer refund processed: -₱${_totalAmount.toStringAsFixed(2)} (${_isResellableReturn ? "Resellable - Shelf Restocked" : "Damaged Write-Off"})',
          );
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        break;

      case StockMovementType.damagedWriteOff:
        final auth = await _ensureManagerAuth(
          'Authorize Damaged Write-Off',
          'Authorization required to write off defective/damaged fragrance: $_quantity x ${product.name} (Loss: -₱${_totalAmount.toStringAsFixed(2)})',
        );
        if (!auth) return;

        setState(() => _isSubmitting = true);
        try {
          await SqliteService.instance.recordDamagedWriteOff(
            perfumeCode: product.perfumeCode,
            productName: product.name,
            bottleSize: product.bottleSize,
            quantity: _quantity,
            reasonCategory: _damageReason,
            authorizedBy: 'Store Manager',
            isDeficitResolution: _isDeficitResolution,
            branch: branch,
          );

          _onSuccess(
            'Damaged fragrance written off: $_quantity x ${product.name} [$_damageReason]',
          );
        } finally {
          if (mounted) setState(() => _isSubmitting = false);
        }
        break;
    }
  }

  void _onSuccess(String message) {
    ref.invalidate(liveInventoryProvider);
    ref.invalidate(liveAlertsProvider);
    ref.invalidate(dashboardStatsProvider);
    ref.invalidate(salesRecordsProvider);
    ref.invalidate(stockMovementLogsProvider);
    ref.invalidate(resolvedAlertsHistoryProvider);

    if (mounted) {
      Navigator.of(context).pop();
      ToastService.showToast(
        title: 'Stock Movement Recorded',
        message: message,
        type: 'success',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.borderColor, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const Divider(height: 1),
                  _buildMovementTypeTabs(context),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProductSelector(context),
                          const SizedBox(height: 20),
                          _buildActionForm(context),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _buildBottomBar(context),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.brandGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unified Stock Movement Hub',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Record sales, restocks, returns, damage write-offs, and visual audits',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.textSecondaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  bool _isTabEnabled(StockMovementType type) {
    if (_isDeficitResolution) {
      // Deficit: Sale (deduct ledger), Write-Off (damage loss), or Restock (shelf returned to stock)
      return type == StockMovementType.sale ||
          type == StockMovementType.damagedWriteOff ||
          type == StockMovementType.restock;
    }
    if (_isSurplusResolution) {
      // Surplus: only Restock (received extra) is applicable
      return type == StockMovementType.restock;
    }
    return true;
  }

  Widget _buildMovementTypeTabs(BuildContext context) {
    final tabs = [
      (StockMovementType.sale, 'Sale', Icons.point_of_sale_rounded),
      (StockMovementType.restock, 'Restock', Icons.add_business_rounded),
      (StockMovementType.customerReturn, 'Return/Refund', Icons.keyboard_return_rounded),
      (StockMovementType.damagedWriteOff, 'Write-Off', Icons.delete_sweep_rounded),
    ];

    return Container(
      color: context.surfaceElevatedColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: tabs.map((t) {
            final isSelected = _selectedType == t.$1;
            final isEnabled = _isTabEnabled(t.$1);
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Opacity(
                opacity: isEnabled ? 1.0 : 0.4,
                child: ChoiceChip(
                  selected: isSelected,
                  avatar: Icon(
                    t.$3,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : (isEnabled ? context.textSecondaryColor : context.textSecondaryColor.withValues(alpha: 0.5)),
                  ),
                  label: Text(
                    t.$2,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                      color: isSelected
                          ? Colors.white
                          : (isEnabled ? context.textPrimaryColor : context.textSecondaryColor),
                    ),
                  ),
                  selectedColor: AppColors.brandAccent,
                  onSelected: isEnabled
                      ? (val) {
                          if (val) {
                            setState(() {
                              _selectedType = t.$1;
                              if (_selectedType == StockMovementType.restock) {
                                if (_isSurplusResolution) {
                                  _quantity = _surplusLimit;
                                } else if (_currentInv != null) {
                                  final deficit = (5 - _currentInv!.recorded).clamp(0, 5);
                                  _quantity = deficit > 0 ? deficit : 1;
                                } else {
                                  _quantity = 1;
                                }
                              } else if (_isDeficitResolution) {
                                _quantity = _quantity.clamp(1, _deficitLimit);
                              }
                            });
                          }
                        }
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildProductSelector(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELECTED FRAGRANCE PRODUCT',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: context.textSecondaryColor,
                  letterSpacing: 0.5,
                ),
              ),
              if (_currentInv != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _currentInv!.recorded != _currentInv!.detected
                        ? AppColors.statusOrange.withValues(alpha: 0.15)
                        : AppColors.statusGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Recorded: ${_currentInv!.recorded} • Detected: ${_currentInv!.detected}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: _currentInv!.recorded != _currentInv!.detected
                          ? AppColors.statusOrange
                          : AppColors.statusGreen,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.brandAccent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedProduct?.name ?? 'Unknown Fragrance',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SKU: ${_selectedProduct?.perfumeCode ?? "---"} • Size: ${_selectedProduct?.bottleSize.toUpperCase() ?? "---"} • Location: ${_selectedProduct?.shelfLayer ?? "---"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionForm(BuildContext context) {
    switch (_selectedType) {
      case StockMovementType.sale:
        return _buildSaleForm(context);
      case StockMovementType.restock:
        return _buildRestockForm(context);
      case StockMovementType.customerReturn:
        return _buildReturnForm(context);
      case StockMovementType.damagedWriteOff:
        return _buildDamageForm(context);
    }
  }

  Widget _buildSaleForm(BuildContext context) {
    final effectiveMax = _isDeficitResolution ? _deficitLimit : 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuantityRow(
          'Sale Quantity',
          maxQty: effectiveMax,
          helperNote: _isDeficitResolution
              ? '(Capped to $effectiveMax missing bottle${effectiveMax > 1 ? "s" : ""})'
              : null,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Sale Amount (${_quantity}x @ ₱${_unitPrice.toStringAsFixed(2)}):',
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.textSecondaryColor,
                ),
              ),
              Text(
                '₱${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusGreen,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRestockForm(BuildContext context) {
    final isSurplus = _isSurplusResolution;
    final effectiveMax = isSurplus ? _surplusLimit : 5;
    final deficit = _currentInv != null
        ? (5 - _currentInv!.recorded).clamp(0, 5)
        : 5;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuantityRow(
          'Restock Quantity Received',
          maxQty: effectiveMax,
          helperNote: isSurplus
              ? '(Capped to $effectiveMax added bottle${effectiveMax > 1 ? "s" : ""})'
              : null,
        ),
        const SizedBox(height: 12),
        if (!isSurplus && deficit > 0)
          OutlinedButton.icon(
            onPressed: () => setState(() => _quantity = deficit),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: Text('Fill Entire Tray (+$deficit Bottles)'),
          ),
      ],
    );
  }

  Widget _buildReturnForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuantityRow('Quantity Returned', maxQty: 5),
        const SizedBox(height: 16),
        Text(
          'RETURN CONDITION',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: context.textSecondaryColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ChoiceChip(
                selected: _isResellableReturn,
                avatar: const Icon(Icons.check_circle_outline_rounded, size: 16),
                label: const Text('Resellable (Shelf +1)'),
                onSelected: (val) => setState(() => _isResellableReturn = true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ChoiceChip(
                selected: !_isResellableReturn,
                avatar: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Damaged (Write-Off)'),
                onSelected: (val) => setState(() => _isResellableReturn = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Customer Refund Amount:',
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.textSecondaryColor,
                ),
              ),
              Text(
                '-₱${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusOrange,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDamageForm(BuildContext context) {
    final effectiveMax = _isDeficitResolution ? _deficitLimit : 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildQuantityRow(
          'Damaged Quantity',
          maxQty: effectiveMax,
          helperNote: _isDeficitResolution
              ? '(Capped to $effectiveMax missing bottle${effectiveMax > 1 ? "s" : ""})'
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          'DAMAGE CAUSE CATEGORY',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: context.textSecondaryColor,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('damage_reason_$_damageReason'),
          initialValue: _damageReason,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          items: _allowedDamageReasons.map((r) {
            return DropdownMenuItem<String>(value: r, child: Text(r));
          }).toList(),
          onChanged: (val) {
            if (val != null) setState(() => _damageReason = val);
          },
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Shrinkage Financial Loss:',
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.textSecondaryColor,
                ),
              ),
              Text(
                '-₱${_totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusRed,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityRow(
    String label, {
    int maxQty = 5,
    String? helperNote,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
            ),
            if (helperNote != null) ...[
              const SizedBox(height: 2),
              Text(
                helperNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.statusOrange,
                ),
              ),
            ],
          ],
        ),
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            Container(
              width: 50,
              alignment: Alignment.center,
              child: Text(
                '$_quantity',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed:
                  _quantity < maxQty ? () => setState(() => _quantity++) : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    String submitLabel;
    Color buttonColor;
    switch (_selectedType) {
      case StockMovementType.sale:
        submitLabel = 'Record Sale (₱${_totalAmount.toStringAsFixed(2)})';
        buttonColor = AppColors.statusGreen;
        break;
      case StockMovementType.restock:
        submitLabel = 'Commit Restock (+$_quantity Bottles)';
        buttonColor = AppColors.brandAccent;
        break;
      case StockMovementType.customerReturn:
        submitLabel = 'Authorize Refund (-₱${_totalAmount.toStringAsFixed(2)})';
        buttonColor = AppColors.statusOrange;
        break;
      case StockMovementType.damagedWriteOff:
        submitLabel = 'Authorize Write-Off (-₱${_totalAmount.toStringAsFixed(2)})';
        buttonColor = AppColors.statusRed;
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            key: const ValueKey('submit_stock_movement_button'),
            onPressed: _isSubmitting ? null : _submitMovement,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    submitLabel,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }
}
