import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/product_model.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'all'; // all, men, women, layerA, layerB, layerC
  String _selectedSize = 'all'; // all, 100ml, 50ml
  bool _isGridView = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showShelfFullModal(BuildContext context, int variantCount) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: AppColors.statusOrange,
              size: 28,
            ),
            const SizedBox(width: 12),
            Text(
              'Shelf Full ($variantCount/30 Slots)',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'No more slots available on the physical shelf. All 30 fragrance variant partitions across the 3 layers are currently occupied:',
              style: TextStyle(color: context.textSecondaryColor, fontSize: 14),
            ),
            const SizedBox(height: 14),
            _buildCapacityInfoRow(
              context,
              'Layer A (Top)',
              '10 Men Slots (Slots A to K)',
              AppColors.maleBlue,
            ),
            _buildCapacityInfoRow(
              context,
              'Layer B (Middle)',
              '5 Men + 5 Women Slots',
              AppColors.brandAccent,
            ),
            _buildCapacityInfoRow(
              context,
              'Layer C (Bottom)',
              '10 Women Slots (Slots A to K)',
              AppColors.femalePink,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline_rounded,
                    color: AppColors.brandGold,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'To introduce a new scent, tap the Edit icon on an existing fragrance to update or replace it, or delete an obsolete variant to free up a slot.',
                      style: TextStyle(
                        color: context.textPrimaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  static Widget _buildCapacityInfoRow(
    BuildContext context,
    String layer,
    String desc,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            layer,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '• $desc',
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final productsAsync = ref.watch(masterProductsProvider);
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: productsAsync.when(
        data: (allItems) {
          final uniqueVariants = allItems
              .map(
                (p) => p.perfumeCode.length >= 2
                    ? p.perfumeCode.substring(0, 2)
                    : p.name,
              )
              .toSet();
          final variantCount = uniqueVariants.length;
          final isShelfFull = variantCount >= 30;

          final filtered = allItems.where((p) {
            final isFemale =
                p.category.toLowerCase().contains('women') ||
                p.category.toLowerCase().contains('female') ||
                p.shelfLayer.contains('Layer C') ||
                (p.shelfLayer.contains('Layer B') && p.slotPosition >= 6);

            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              if (!p.name.toLowerCase().contains(q) &&
                  !p.perfumeCode.toLowerCase().contains(q) &&
                  !p.brand.toLowerCase().contains(q)) {
                return false;
              }
            }

            if (_selectedFilter == 'men' && isFemale) return false;
            if (_selectedFilter == 'women' && !isFemale) return false;
            if (_selectedFilter == 'active' && p.isSeasonalOff) return false;
            if (_selectedFilter == 'seasonal_off' && !p.isSeasonalOff) {
              return false;
            }
            if (_selectedFilter == 'layerA' &&
                !p.shelfLayer.contains('Layer A')) {
              return false;
            }
            if (_selectedFilter == 'layerB' &&
                !p.shelfLayer.contains('Layer B')) {
              return false;
            }
            if (_selectedFilter == 'layerC' &&
                !p.shelfLayer.contains('Layer C')) {
              return false;
            }

            if (_selectedSize == '100ml' &&
                p.bottleSize.toLowerCase() != '100ml') {
              return false;
            }
            if (_selectedSize == '50ml' &&
                p.bottleSize.toLowerCase() != '50ml') {
              return false;
            }

            return true;
          }).toList();

          final invMap = <String, int>{};
          inventoryAsync.whenData((list) {
            for (final item in list) {
              invMap[item.perfumeCode] = item.detected;
            }
          });

          final activeCount = allItems.where((p) => p.isActive).length;
          final seasonalOffCount = allItems
              .where((p) => p.isSeasonalOff)
              .length;
          return Column(
            children: [
              // 1. Integrated Page Header Ribbon
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: context.borderColor),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Inventory Catalog',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: context.textPrimaryColor,
                                letterSpacing: -0.3,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandAccent.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.brandAccent.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              child: Text(
                                '${allItems.length} SKUs',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.brandAccent,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Automated computer vision detection & physical bottle partitions (3 Layers • 30 Slots)',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: context.textSecondaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // View Mode Toggle (Grid vs List) - Enlarged Touch Control (48px)
                        Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: context.borderColor,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              InkWell(
                                onTap: () => setState(() => _isGridView = true),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isGridView
                                        ? AppColors.brandAccent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.grid_view_rounded,
                                        size: 20,
                                        color: _isGridView
                                            ? Colors.white
                                            : context.textSecondaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Grid',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: _isGridView
                                              ? Colors.white
                                              : context.textSecondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () =>
                                    setState(() => _isGridView = false),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: !_isGridView
                                        ? AppColors.brandAccent
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.view_list_rounded,
                                        size: 22,
                                        color: !_isGridView
                                            ? Colors.white
                                            : context.textSecondaryColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'List',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w800,
                                          color: !_isGridView
                                              ? Colors.white
                                              : context.textSecondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Refresh Button (48x48)
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.refresh_rounded, size: 24),
                            tooltip: 'Refresh Inventory',
                            onPressed: () {
                              ref.invalidate(masterProductsProvider);
                              ref.invalidate(liveInventoryProvider(branch));
                            },
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Add / Shelf Full Capacity Action
                        if (isShelfFull)
                          Tooltip(
                            message: 'Shelf is at full capacity (30/30 slots occupied).',
                            child: SizedBox(
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _showShelfFullModal(context, variantCount),
                                icon: const Icon(
                                  Icons.lock_outline_rounded,
                                  size: 20,
                                  color: AppColors.statusOrange,
                                ),
                                label: Text(
                                  'Shelf Full ($variantCount/30)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(
                                    color: AppColors.statusOrange.withValues(
                                      alpha: 0.6,
                                    ),
                                    width: 1.5,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 18,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height: 48,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  context.push(AppRoutePaths.productForm),
                              icon: const Icon(Icons.add_rounded, size: 22),
                              label: Text(
                                'Add Fragrance (${30 - variantCount} Slots Left)',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 2. Search & Filter Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: context.borderColor),
                  ),
                ),
                child: Column(
                  children: [
                    // Search Bar & Capacity Badge
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 54,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) =>
                                  setState(() => _searchQuery = val.trim()),
                              style: TextStyle(
                                color: context.textPrimaryColor,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Search perfume name, cap OCR code (e.g. AA1, BK2), or brand...',
                                hintStyle: TextStyle(
                                  color: context.textMutedColor,
                                  fontSize: 16,
                                ),
                                prefixIcon: const Icon(
                                  Icons.search_rounded,
                                  color: AppColors.brandAccent,
                                  size: 24,
                                ),
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(
                                          Icons.clear_rounded,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: context.surfaceElevatedColor,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 16,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide(
                                    color: context.borderColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Capacity Status Pill
                        Container(
                          height: 54,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isShelfFull
                                ? AppColors.statusGreen.withValues(alpha: 0.12)
                                : context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isShelfFull
                                  ? AppColors.statusGreen.withValues(alpha: 0.5)
                                  : context.borderColor,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isShelfFull
                                    ? Icons.inventory_2_rounded
                                    : Icons.shelves,
                                size: 22,
                                color: isShelfFull
                                    ? AppColors.statusGreen
                                    : AppColors.brandAccent,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                isShelfFull
                                    ? 'Shelf Full (30/30 Slots • ${allItems.length} SKUs)'
                                    : '$variantCount / 30 Slots Occupied',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: isShelfFull
                                      ? AppColors.statusGreen
                                      : context.textPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Filter Chips Row (Gender, Availability & Layer Filters)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip(
                            'all',
                            'All Fragrances (${allItems.length})',
                          ),
                          const SizedBox(width: 10),
                          _buildFilterChip(
                            'active',
                            'Active on Shelf ($activeCount)',
                          ),
                          const SizedBox(width: 10),
                          _buildSeasonalFilterChip(
                            'seasonal_off',
                            'Seasonal / Off ($seasonalOffCount)',
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 1.5,
                            height: 28,
                            color: context.borderColor,
                          ),
                          const SizedBox(width: 14),
                          _buildGenderFilterChip(
                            'men',
                            'Men\'s Fragrances (30)',
                            AppColors.maleBlue,
                          ),
                          const SizedBox(width: 10),
                          _buildGenderFilterChip(
                            'women',
                            'Women\'s Fragrances (30)',
                            AppColors.femalePink,
                          ),
                          const SizedBox(width: 14),
                          Container(
                            width: 1.5,
                            height: 28,
                            color: context.borderColor,
                          ),
                          const SizedBox(width: 14),
                          _buildFilterChip('layerA', 'Top Shelf (Men)'),
                          const SizedBox(width: 10),
                          _buildFilterChip('layerB', 'Middle Shelf (Mixed)'),
                          const SizedBox(width: 10),
                          _buildFilterChip('layerC', 'Bottom Shelf (Women)'),
                          const SizedBox(width: 14),
                          Container(
                            width: 1.5,
                            height: 28,
                            color: context.borderColor,
                          ),
                          const SizedBox(width: 14),
                          _buildSizeChip('all', 'All Sizes'),
                          const SizedBox(width: 10),
                          _buildSizeChip('100ml', '100ml Bottles'),
                          const SizedBox(width: 10),
                          _buildSizeChip('50ml', '50ml Bottles'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Product Grid / List Content
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: context.textMutedColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No matching perfume products found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      )
                    : _isGridView
                    ? GridView.builder(
                        padding: const EdgeInsets.all(22),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 420,
                              mainAxisExtent: 268,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final isFemale =
                              p.category.toLowerCase().contains('women') ||
                              p.category.toLowerCase().contains('female') ||
                              p.shelfLayer.contains('Layer C') ||
                              (p.shelfLayer.contains('Layer B') &&
                                  p.slotPosition >= 6);

                          final detectedQty = invMap[p.perfumeCode] ?? 5;
                          final status = (detectedQty <= 2)
                              ? StatusBadgeType.lowStock
                              : StatusBadgeType.good;

                          return _buildGridCard(
                            context: context,
                            product: p,
                            name: p.name,
                            code: p.perfumeCode,
                            brand: p.brand,
                            size: p.bottleSize.toUpperCase(),
                            layer: p.shelfLayer,
                            slot: 'Slot ${p.slotPosition}',
                            isFemale: isFemale,
                            currentQty: detectedQty,
                            status: status,
                            onTap: () => context.push(
                              AppRoutePaths.productDetail,
                              extra: p,
                            ),
                            onEdit: () => context.push(
                              AppRoutePaths.productForm,
                              extra: p,
                            ),
                          );
                        },
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 18,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final isFemale =
                              p.category.toLowerCase().contains('women') ||
                              p.category.toLowerCase().contains('female') ||
                              p.shelfLayer.contains('Layer C') ||
                              (p.shelfLayer.contains('Layer B') &&
                                  p.slotPosition >= 6);

                          final detectedQty = invMap[p.perfumeCode] ?? 5;
                          final status = (detectedQty <= 2)
                              ? StatusBadgeType.lowStock
                              : StatusBadgeType.good;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _buildInventoryCard(
                              context: context,
                              product: p,
                              name: p.name,
                              code: p.perfumeCode,
                              brand: p.brand,
                              size: p.bottleSize.toUpperCase(),
                              layer: p.shelfLayer,
                              slot: 'Slot ${p.slotPosition}',
                              isFemale: isFemale,
                              currentQty: detectedQty,
                              status: status,
                              onTap: () => context.push(
                                AppRoutePaths.productDetail,
                                extra: p,
                              ),
                              onEdit: () => context.push(
                                AppRoutePaths.productForm,
                                extra: p,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Unable to load inventory catalog.')),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      selectedColor: AppColors.brandAccent,
      backgroundColor: context.surfaceElevatedColor,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 14,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandAccent : context.borderColor,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildGenderFilterChip(String value, String label, Color genderColor) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      selectedColor: genderColor,
      backgroundColor: context.surfaceElevatedColor,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : genderColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
        fontSize: 14,
      ),
      side: BorderSide(
        color: isSelected ? genderColor : genderColor.withValues(alpha: 0.45),
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildSeasonalFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      selectedColor: AppColors.statusOrange,
      backgroundColor: context.surfaceElevatedColor,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppColors.statusOrange,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
        fontSize: 14,
      ),
      side: BorderSide(
        color: isSelected
            ? AppColors.statusOrange
            : AppColors.statusOrange.withValues(alpha: 0.45),
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Future<void> _toggleVariant(ProductModel product, bool isActive) async {
    final newStatus = isActive ? 'active' : 'seasonal_off';
    await ref
        .read(sqliteServiceProvider)
        .toggleProductStatus(productId: product.id, newStatus: newStatus);
    ref.invalidate(masterProductsProvider);
    ref.invalidate(liveInventoryProvider('San Pablo'));
    ref.invalidate(dashboardStatsProvider('San Pablo'));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isActive
                ? 'Fragrance "${product.name}" (${product.perfumeCode}) is now ACTIVE on shelf.'
                : 'Fragrance "${product.name}" (${product.perfumeCode}) is now TURNED OFF (Seasonal rotation).',
          ),
          backgroundColor: isActive
              ? AppColors.statusGreen
              : AppColors.statusOrange,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildSizeChip(String value, String label) {
    final isSelected = _selectedSize == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedSize = value),
      selectedColor: AppColors.brandAccent,
      backgroundColor: context.surfaceElevatedColor,
      labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 14,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandAccent : context.borderColor,
        width: 1.5,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildGridCard({
    required BuildContext context,
    required ProductModel product,
    required String name,
    required String code,
    required String brand,
    required String size,
    required String layer,
    required String slot,
    required bool isFemale,
    required int currentQty,
    required StatusBadgeType status,
    required VoidCallback onTap,
    required VoidCallback onEdit,
  }) {
    final isLow = currentQty <= 2;
    final isOff = product.isSeasonalOff;
    final themeGenderColor = isFemale
        ? AppColors.femalePink
        : AppColors.maleBlue;

    return Card(
      color: isOff
          ? (context.isDark ? const Color(0xFF1F1A14) : const Color(0xFFFFFBEB))
          : context.surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isOff
              ? AppColors.statusOrange.withValues(alpha: 0.5)
              : themeGenderColor.withValues(
                  alpha: context.isDark ? 0.25 : 0.35,
                ),
          width: isOff ? 1.5 : 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Cap Code Badge + Gender + Size + Shelf Info + Edit Action
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                    opacity: isOff ? 0.6 : 1.0,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isOff
                              ? const [Color(0xFF6B7280), Color(0xFF4B5563)]
                              : (isFemale
                                    ? const [
                                        Color(0xFFEC4899),
                                        Color(0xFFBE185D),
                                      ]
                                    : const [
                                        Color(0xFF0284C7),
                                        Color(0xFF0369A1),
                                      ]),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: (isOff ? Colors.black26 : themeGenderColor)
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          code,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: themeGenderColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: themeGenderColor.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isFemale
                                        ? Icons.female_rounded
                                        : Icons.male_rounded,
                                    size: 13,
                                    color: themeGenderColor,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    isFemale ? 'Women' : 'Men',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: themeGenderColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: context.surfaceElevatedColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: context.borderColor),
                              ),
                              child: Text(
                                size,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '$layer • $slot',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textMutedColor,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit Fragrance',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: onEdit,
                  ),
                ],
              ),

              // Middle: Fragrance Name & Brand
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: isOff
                            ? context.textSecondaryColor
                            : context.textPrimaryColor,
                        decoration: isOff ? TextDecoration.lineThrough : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      brand,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Bottom Row: Stock Count Bar & Active Switch
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceElevatedColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isLow
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 18,
                          color: isLow
                              ? AppColors.statusRed
                              : AppColors.statusGreen,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$currentQty / 5 in Stock',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: isLow
                                ? AppColors.statusRed
                                : AppColors.statusGreen,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Text(
                          isOff ? 'Off' : 'Active',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isOff
                                ? AppColors.statusOrange
                                : context.textSecondaryColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 28,
                          width: 44,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            child: Switch(
                              value: !isOff,
                              activeThumbColor: AppColors.brandAccent,
                              onChanged: (val) => _toggleVariant(product, val),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryCard({
    required BuildContext context,
    required ProductModel product,
    required String name,
    required String code,
    required String brand,
    required String size,
    required String layer,
    required String slot,
    required bool isFemale,
    required int currentQty,
    required StatusBadgeType status,
    required VoidCallback onTap,
    required VoidCallback onEdit,
  }) {
    final isLow = currentQty <= 2;
    final isOff = product.isSeasonalOff;
    final themeGenderColor = isFemale
        ? AppColors.femalePink
        : AppColors.maleBlue;

    return Card(
      color: isOff
          ? (context.isDark ? const Color(0xFF1F1A14) : const Color(0xFFFFFBEB))
          : context.surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isOff
              ? AppColors.statusOrange.withValues(alpha: 0.5)
              : themeGenderColor.withValues(alpha: context.isDark ? 0.22 : 0.3),
          width: isOff ? 1.5 : 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              // Alphanumeric Cap OCR Badge (Blue for Male, Pink for Female, Dimmed if Off)
              Opacity(
                opacity: isOff ? 0.6 : 1.0,
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isOff
                          ? const [Color(0xFF6B7280), Color(0xFF4B5563)]
                          : (isFemale
                                ? const [Color(0xFFEC4899), Color(0xFFBE185D)]
                                : const [Color(0xFF0284C7), Color(0xFF0369A1)]),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: (isOff ? Colors.black26 : themeGenderColor)
                            .withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      code,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Product Info & Gender / Size / Seasonal Badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              color: isOff
                                  ? context.textSecondaryColor
                                  : context.textPrimaryColor,
                              decoration: isOff
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Gender Tag Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: themeGenderColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: themeGenderColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFemale
                                    ? Icons.female_rounded
                                    : Icons.male_rounded,
                                size: 14,
                                color: themeGenderColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFemale ? 'Women' : 'Men',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: themeGenderColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Bottle Size Tag (100ML / 50ML)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            size,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Seasonal Status Badge
                        if (isOff)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.statusOrange.withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.statusOrange.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.wb_sunny_outlined,
                                  size: 14,
                                  color: AppColors.statusOrange,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Seasonal Off',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.statusOrange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$brand • $layer • $slot',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              // Stock Status Indicator
              if (isOff) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.statusOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Text(
                    'Turned Off',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.statusOrange,
                    ),
                  ),
                ),
              ] else ...[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$currentQty',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: isLow
                                ? AppColors.statusRed
                                : AppColors.statusGreen,
                          ),
                        ),
                        Text(
                          ' / 5 Bottles',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.textMutedColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    StatusBadge(type: status),
                  ],
                ),
              ],
              const SizedBox(width: 20),

              // Seasonal On/Off Quick Switch
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Switch(
                    value: !isOff,
                    activeThumbColor: AppColors.statusGreen,
                    inactiveThumbColor: AppColors.statusOrange,
                    onChanged: (val) => _toggleVariant(product, val),
                  ),
                  Text(
                    isOff ? 'Off' : 'Active',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: isOff
                          ? AppColors.statusOrange
                          : AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Edit Shortcut Button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 22),
                tooltip: 'Edit Fragrance SKU',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: onEdit,
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: context.textMutedColor,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
