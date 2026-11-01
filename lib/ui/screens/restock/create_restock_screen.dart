import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/inventory_record_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/restock_record_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/scan_workflow_dialog.dart';

class CreateRestockScreen extends ConsumerStatefulWidget {
  final String? initialPerfumeCode;

  const CreateRestockScreen({super.key, this.initialPerfumeCode});

  @override
  ConsumerState<CreateRestockScreen> createState() =>
      _CreateRestockScreenState();
}

class _CreateRestockScreenState extends ConsumerState<CreateRestockScreen> {
  int _currentStep = 0; // 0: Pick Perfume, 1: Select Quantity & Confirm
  String? _selectedProductCode;
  String? _selectedShelf;
  int _restockQty = 5;
  bool _qtyInitializedForSelection = false;

  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedLayerFilter = 'All'; // 'All', 'Layer A', 'Layer B', 'Layer C', 'Low Stock <=2'

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPerfumeCode != null &&
        widget.initialPerfumeCode!.isNotEmpty) {
      _selectedProductCode = widget.initialPerfumeCode;
      _currentStep = 1; // Proceed directly to quantity selection for pre-selected fragrance
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_selectedProductCode == null) {
      try {
        final extra = GoRouterState.of(context).extra;
        if (extra is String && extra.isNotEmpty) {
          setState(() {
            _selectedProductCode = extra;
            _currentStep = 1;
          });
        } else if (extra is Map && extra['perfumeCode'] is String) {
          setState(() {
            _selectedProductCode = extra['perfumeCode'] as String;
            _currentStep = 1;
          });
        }
      } catch (_) {
        // No GoRouter in context (e.g. standalone widget tests)
      }
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _getTrayCode(String perfumeCode) {
    if (perfumeCode.length >= 2) {
      return perfumeCode.substring(0, 2).toUpperCase();
    }
    return perfumeCode.toUpperCase();
  }

  int _getCameraIdForShelf(String? shelf, String? code) {
    if (code != null && code.isNotEmpty) {
      final tray = _getTrayCode(code);
      return SqliteService.getCameraIdForTray(tray);
    }
    if (shelf != null && shelf.isNotEmpty) {
      final match = RegExp(r'\b([A-C][A-K])\b', caseSensitive: false).firstMatch(shelf);
      if (match != null) {
        return SqliteService.getCameraIdForTray(match.group(1)!.toUpperCase());
      }
      if (shelf.contains('Layer A') || shelf.toLowerCase().contains('top')) return 1;
      if (shelf.contains('Layer B') || shelf.toLowerCase().contains('middle')) return 3;
      if (shelf.contains('Layer C') || shelf.toLowerCase().contains('bottom')) return 5;
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
      final products = ref.read(masterProductsProvider).valueOrNull ??
          await SqliteService.instance.getProducts();
      final product = products.firstWhere(
        (p) => p.perfumeCode == _selectedProductCode,
        orElse: () => ProductModel(
          id: 'prod_$_selectedProductCode',
          perfumeCode: _selectedProductCode!,
          name: SqliteService.getPerfumeFullName(_selectedProductCode!),
        ),
      );

      final now = DateTime.now();
      final targetBranch = ref.read(currentBranchProvider).valueOrNull ??
          await SqliteService.instance.getBranchName();
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
      // Invariant: Recorded stock per slot MUST NEVER exceed max physical capacity (clamp to 5).
      // Invariant: Detected stock MUST NEVER increment on invoice creation (only updated by camera feed).
      final existing = await SqliteService.instance.getInventoryRecord(
        product.perfumeCode,
        targetBranch,
      );
      if (existing != null) {
        final newRecorded = (existing.recorded + _restockQty).clamp(0, 5);
        final currentDetected = existing.detected.clamp(0, 5);
        final hasDiscrepancy = currentDetected != newRecorded;
        final updated = InventoryRecordModel(
          id: existing.id,
          perfumeCode: existing.perfumeCode,
          name: existing.name,
          category: existing.category,
          branch: targetBranch,
          shelf: existing.shelf,
          recorded: newRecorded,
          detected: currentDetected,
          status: hasDiscrepancy ? 'needs_review' : 'normal',
          misplacementDetails: existing.misplacementDetails,
          lastUpdated: now,
          price: existing.price,
        );
        await SqliteService.instance.upsertInventoryRecord(updated);
      } else {
        final newRecorded = _restockQty.clamp(0, 5);
        const currentDetected = 0;
        final hasDiscrepancy = currentDetected != newRecorded;
        final newRecord = InventoryRecordModel(
          id: 'inv_${now.millisecondsSinceEpoch}',
          perfumeCode: product.perfumeCode,
          name: product.name,
          category: product.category,
          branch: targetBranch,
          shelf: shelf,
          recorded: newRecorded,
          detected: currentDetected,
          status: hasDiscrepancy ? 'needs_review' : 'normal',
          misplacementDetails: '',
          lastUpdated: now,
          price: product.price,
        );
        await SqliteService.instance.upsertInventoryRecord(newRecord);
      }

      // 4. Clear active low stock / out of stock alerts for this perfume
      await SqliteService.instance.markStockAlertsReadForPerfume(
        product.perfumeCode,
        branch: targetBranch,
      );

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
      ref.invalidate(liveAlertsProvider(targetBranch));
      ref.invalidate(resolvedAlertsHistoryProvider(targetBranch));
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
        try {
          context.pop();
        } catch (_) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
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
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';
    final invAsync = ref.watch(liveInventoryProvider(branch));
    final invRecords = invAsync.valueOrNull ?? <InventoryRecordModel>[];

    final invMap = <String, InventoryRecordModel>{};
    for (final inv in invRecords) {
      invMap[inv.perfumeCode] = inv;
    }

    return Scaffold(
      backgroundColor: context.surfaceElevatedColor,
      appBar: AppBar(
        title: const Text(
          'Replenish Shelf Stock',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: context.surfaceColor,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                _buildStepTab(
                  index: 0,
                  title: '1. Pick Perfume / Tray',
                  subtitle: 'Select from visual shelf cards',
                  icon: Icons.grid_view_rounded,
                ),
                const SizedBox(width: 20),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: context.textMutedColor,
                ),
                const SizedBox(width: 20),
                _buildStepTab(
                  index: 1,
                  title: '2. Select Quantity & Verify',
                  subtitle: 'Quick tap buttons & confirmation',
                  icon: Icons.tune_rounded,
                ),
              ],
            ),
          ),
        ),
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

          final existingInv = invMap[selectedProduct.perfumeCode];
          final currentStock = existingInv?.detected ?? existingInv?.recorded ?? 0;
          final deficit = (5 - currentStock).clamp(1, 5);

          // Auto-initialize restockQty to deficit once per selected product
          if (!_qtyInitializedForSelection) {
            _restockQty = deficit;
            _qtyInitializedForSelection = true;
          }

          final targetCamId = _getCameraIdForShelf(
            _selectedShelf,
            selectedProduct.perfumeCode,
          );
          final trayCode = _getTrayCode(selectedProduct.perfumeCode);

          return _currentStep == 0
              ? _buildStep1PickPerfume(
                  context,
                  products: products,
                  invMap: invMap,
                  selectedProduct: selectedProduct,
                )
              : _buildStep2SelectQuantity(
                  context,
                  product: selectedProduct,
                  currentStock: currentStock,
                  deficit: deficit,
                  targetCamId: targetCamId,
                  trayCode: trayCode,
                  branch: branch,
                );
        },
      ),
    );
  }

  Widget _buildStepTab({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isActive = _currentStep == index;
    final isDone = _currentStep > index;

    final color = isActive
        ? AppColors.brandAccent
        : (isDone ? AppColors.statusGreen : context.textMutedColor);

    return InkWell(
      onTap: () => setState(() => _currentStep = index),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? AppColors.brandAccent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                isDone ? Icons.check_circle_rounded : icon,
                color: color,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w900 : FontWeight.w700,
                    color: isActive ? context.textPrimaryColor : context.textSecondaryColor,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMutedColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP 1: Pick Perfume / Tray from Visual Cards
  // ===========================================================================
  Widget _buildStep1PickPerfume(
    BuildContext context, {
    required List<ProductModel> products,
    required Map<String, InventoryRecordModel> invMap,
    required ProductModel selectedProduct,
  }) {
    final query = _searchQuery.trim().toLowerCase();

    final filteredProducts = products.where((p) {
      // Search filter
      if (query.isNotEmpty) {
        final matchesName = p.name.toLowerCase().contains(query);
        final matchesCode = p.perfumeCode.toLowerCase().contains(query);
        if (!matchesName && !matchesCode) return false;
      }

      // Layer / Stock filter chip
      final currentStock = invMap[p.perfumeCode]?.detected ?? invMap[p.perfumeCode]?.recorded ?? 0;
      switch (_selectedLayerFilter) {
        case 'Layer A':
          return p.shelfLayer.contains('Layer A') ||
              p.shelfLayer.toLowerCase().contains('top') ||
              p.perfumeCode.startsWith('A');
        case 'Layer B':
          return p.shelfLayer.contains('Layer B') ||
              p.shelfLayer.toLowerCase().contains('middle') ||
              p.perfumeCode.startsWith('B');
        case 'Layer C':
          return p.shelfLayer.contains('Layer C') ||
              p.shelfLayer.toLowerCase().contains('bottom') ||
              p.perfumeCode.startsWith('C');
        case 'Low Stock <=2':
          return currentStock <= 2;
        default:
          return true;
      }
    }).toList();

    return Column(
      children: [
        // Search bar & Layer filter chips bar
        Container(
          color: context.surfaceColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val),
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textPrimaryColor,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Search perfume by name or cap code (e.g. Sauvage, AD1)...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: context.textMutedColor,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 22),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.brandAccent,
                            width: 1.5,
                          ),
                        ),
                        filled: true,
                        fillColor: context.surfaceElevatedColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Layer filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('All'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Layer A'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Layer B'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Layer C'),
                    const SizedBox(width: 8),
                    _buildFilterChip('Low Stock <=2'),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Visual Cards Grid
        Expanded(
          child: filteredProducts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 56,
                        color: context.textMutedColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No perfumes match your filter.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Try clearing search query or selecting "All" layers.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: 154,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: filteredProducts.length,
                  itemBuilder: (context, index) {
                    final product = filteredProducts[index];
                    final isSelected = product.perfumeCode == _selectedProductCode;
                    final inv = invMap[product.perfumeCode];
                    final currentStock = inv?.detected ?? inv?.recorded ?? 0;

                    return _buildPerfumeVisualCard(
                      context,
                      product: product,
                      currentStock: currentStock,
                      isSelected: isSelected,
                      onTap: () {
                        setState(() {
                          _selectedProductCode = product.perfumeCode;
                          _selectedShelf = product.shelfLayer;
                          _qtyInitializedForSelection = false;
                        });
                      },
                    );
                  },
                ),
        ),

        // Bottom Proceed Command Strip
        Container(
          color: context.surfaceColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Selected: [${selectedProduct.perfumeCode}] ${selectedProduct.name}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Shelf: ${selectedProduct.shelfLayer} • ${selectedProduct.bottleSize.toUpperCase()} • Live Stock: ${invMap[selectedProduct.perfumeCode]?.detected ?? 0} / 5',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => setState(() => _currentStep = 1),
                icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                label: const Text(
                  'Continue to Step 2 (Select Quantity)',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedLayerFilter == label;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedLayerFilter = label),
      selectedColor: AppColors.brandAccent.withValues(alpha: 0.15),
      checkmarkColor: AppColors.brandAccent,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        color: isSelected ? AppColors.brandAccent : context.textPrimaryColor,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandAccent : context.borderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      backgroundColor: context.surfaceElevatedColor,
    );
  }

  Widget _buildPerfumeVisualCard(
    BuildContext context, {
    required ProductModel product,
    required int currentStock,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    // Brand color gradients: Blue for Men, Pink for Women, Amber for Seasonal
    final List<Color> gradientColors;
    if (product.category.toLowerCase() == 'women') {
      gradientColors = const [Color(0xFF831843), Color(0xFFDB2777)]; // Pink
    } else if (product.isSeasonalOff ||
        product.status.toLowerCase().contains('seasonal') ||
        product.category.toLowerCase().contains('seasonal')) {
      gradientColors = const [Color(0xFF78350F), Color(0xFFD97706)]; // Amber
    } else {
      gradientColors = const [Color(0xFF1E3A8A), Color(0xFF2563EB)]; // Blue
    }

    final code = product.perfumeCode;
    final trayCode = _getTrayCode(code);
    final size = product.bottleSize.toUpperCase();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandAccent.withValues(alpha: 0.08)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brandAccent : context.borderColor,
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandAccent.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Bottle visual / graphic with branded color gradient
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 68,
                  height: 98,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: gradientColors,
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.science_outlined,
                        color: Colors.white70,
                        size: 20,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        size,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.brandAccent,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 14),

            // Card details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Tray $trayCode • ${product.shelfLayer}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.textSecondaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Live Shelf Stock: currentStock / 5 Bottles with visual indicators
                  Row(
                    children: [
                      Text(
                        '$currentStock / 5 Bottles',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: currentStock <= 1
                              ? AppColors.statusRed
                              : (currentStock == 2
                                  ? AppColors.statusOrange
                                  : AppColors.statusGreen),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 5 visual bottle dots
                      Row(
                        children: List.generate(5, (dotIndex) {
                          final isFilled = dotIndex < currentStock;
                          final dotColor = currentStock <= 1
                              ? AppColors.statusRed
                              : (currentStock == 2
                                  ? AppColors.statusOrange
                                  : AppColors.statusGreen);

                          return Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isFilled ? dotColor : Colors.transparent,
                              border: Border.all(
                                color: isFilled
                                    ? dotColor
                                    : context.borderColor,
                                width: 1.5,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // STEP 2: Select Quantity with Quick Tap Buttons & Confirmation
  // ===========================================================================
  Widget _buildStep2SelectQuantity(
    BuildContext context, {
    required ProductModel product,
    required int currentStock,
    required int deficit,
    required int targetCamId,
    required String trayCode,
    required String branch,
  }) {
    final willExceed = (currentStock + _restockQty) > 5;

    // Gradient for summary banner
    final List<Color> gradientColors;
    if (product.category.toLowerCase() == 'women') {
      gradientColors = const [Color(0xFF831843), Color(0xFFDB2777)];
    } else if (product.isSeasonalOff ||
        product.status.toLowerCase().contains('seasonal') ||
        product.category.toLowerCase().contains('seasonal')) {
      gradientColors = const [Color(0xFF78350F), Color(0xFFD97706)];
    } else {
      gradientColors = const [Color(0xFF1E3A8A), Color(0xFF2563EB)];
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Selected Fragrance Summary Banner
          Card(
            color: context.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: gradientColors,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      product.perfumeCode,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                product.name,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Shelf Tray: $trayCode • ${product.shelfLayer} • Slot Code: ${product.perfumeCode} (${product.bottleSize.toUpperCase()})',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandAccent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Camera $targetCamId',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.brandAccent,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Current Stock: $currentStock / 5 Bottles (Deficit: +$deficit)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: currentStock <= 2
                                    ? AppColors.statusOrange
                                    : AppColors.statusGreen,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _currentStep = 0),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text('Change'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.textPrimaryColor,
                      side: BorderSide(color: context.borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // 2. Quantity Selector Card
          Card(
            color: context.surfaceColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: context.borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Replenishment Quantity',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use quick tap buttons or fine-tune with stepper buttons.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Quick Tap Buttons: +1, +5, and Fill Tray ($deficit)
                  Row(
                    children: [
                      // +1 Quick Button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _restockQty = 1),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _restockQty == 1
                                ? AppColors.brandAccent.withValues(alpha: 0.12)
                                : context.surfaceElevatedColor,
                            side: BorderSide(
                              color: _restockQty == 1
                                  ? AppColors.brandAccent
                                  : context.borderColor,
                              width: _restockQty == 1 ? 2.0 : 1.0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '+1',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _restockQty == 1
                                  ? AppColors.brandAccent
                                  : context.textPrimaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // +5 Quick Button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setState(() => _restockQty = 5),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _restockQty == 5
                                ? AppColors.brandAccent.withValues(alpha: 0.12)
                                : context.surfaceElevatedColor,
                            side: BorderSide(
                              color: _restockQty == 5
                                  ? AppColors.brandAccent
                                  : context.borderColor,
                              width: _restockQty == 5 ? 2.0 : 1.0,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            '+5',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _restockQty == 5
                                  ? AppColors.brandAccent
                                  : context.textPrimaryColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Fill Tray ($deficit) Quick Button
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: () => setState(() => _restockQty = deficit),
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 20),
                          label: Text(
                            'Fill Tray ($deficit)',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _restockQty == deficit
                                ? AppColors.brandAccent
                                : AppColors.brandAccent.withValues(alpha: 0.8),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: _restockQty == deficit ? 2 : 0,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Manual Stepper Control
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: AppColors.brandAccent,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _restockQty == 1 ? 'Bottle Added' : 'Bottles Added',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimaryColor,
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
                              icon: const Icon(Icons.remove_rounded, size: 22),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            IconButton.filledTonal(
                              onPressed: _restockQty < 10
                                  ? () => setState(() => _restockQty++)
                                  : null,
                              icon: const Icon(Icons.add_rounded, size: 22),
                              style: IconButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Capacity Guard Warning
                  if (willExceed) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.statusOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.statusOrange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.statusOrange,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Capacity Warning: Adding $_restockQty bottles will bring total stock to ${currentStock + _restockQty}, exceeding standard tray capacity (5 Bottles). Ensure physical shelf space accommodates extra bottles.',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.statusOrange,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Batch Notes / Invoice Reference Field
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textPrimaryColor,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Batch Notes / Invoice Reference (Optional)',
                      hintText: 'e.g. Supplier invoice #8812, Batch A replenishment',
                      prefixIcon: const Icon(Icons.note_alt_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: context.borderColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 3. Action Buttons Row: Confirm Restock (Primary) & Verify with Camera (Secondary)
          Row(
            children: [
              // Secondary CTA: Verify with Camera
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () async {
                            await ScanWorkflowDialog.show(
                              context,
                              initialCameraId: targetCamId,
                              isTargetedVerification: true,
                              targetSlotCodes: [product.perfumeCode],
                              targetTrayCodes: [trayCode],
                              targetCameraIds: [targetCamId],
                            );
                          },
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      size: 22,
                      color: AppColors.brandAccent,
                    ),
                    label: Text(
                      'Verify with Camera (Camera $targetCamId)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                        color: AppColors.brandAccent,
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // Primary CTA: Confirm Restock
              Expanded(
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving
                        ? null
                        : () => _submitRestock(verifiedViaScan: false),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_rounded, size: 22),
                    label: Text(
                      _isSaving ? 'Saving Restock...' : 'Confirm Restock',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.statusGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Return back link
          Center(
            child: TextButton.icon(
              onPressed: () => setState(() => _currentStep = 0),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Fragrance Selection'),
            ),
          ),
        ],
      ),
    );
  }
}
