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
            const Icon(Icons.lock_outline_rounded, color: AppColors.statusOrange, size: 28),
            const SizedBox(width: 12),
            Text(
              'Shelf Full ($variantCount/30 Slots)',
              style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimaryColor, fontSize: 18),
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
            _buildCapacityInfoRow(context, 'Layer A (Top)', '10 Men Slots (Slots A to K)', AppColors.maleBlue),
            _buildCapacityInfoRow(context, 'Layer B (Middle)', '5 Men + 5 Women Slots', AppColors.brandAccent),
            _buildCapacityInfoRow(context, 'Layer C (Bottom)', '10 Women Slots (Slots A to K)', AppColors.femalePink),
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
                  const Icon(Icons.lightbulb_outline_rounded, color: AppColors.brandGold, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'To introduce a new scent, tap the Edit icon on an existing fragrance to update or replace it, or delete an obsolete variant to free up a slot.',
                      style: TextStyle(color: context.textPrimaryColor, fontSize: 12, fontWeight: FontWeight.w600),
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

  static Widget _buildCapacityInfoRow(BuildContext context, String layer, String desc, Color color) {
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
          Text(layer, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimaryColor)),
          const SizedBox(width: 8),
          Text('• $desc', style: TextStyle(fontSize: 12, color: context.textSecondaryColor)),
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
      appBar: AppBar(
        title: const Text('Inventory Catalog & Cap OCR Codes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Inventory',
            onPressed: () {
              ref.invalidate(masterProductsProvider);
              ref.invalidate(liveInventoryProvider(branch));
            },
          ),
          const SizedBox(width: 8),

          // Add / Shelf Full Capacity Action
          productsAsync.when(
            data: (allItems) {
              final uniqueVariants = allItems
                  .map((p) => p.perfumeCode.length >= 2 ? p.perfumeCode.substring(0, 2) : p.name)
                  .toSet();
              final variantCount = uniqueVariants.length;
              final isShelfFull = variantCount >= 30;

              if (isShelfFull) {
                return Tooltip(
                  message: 'Shelf is at full capacity (30/30 slots occupied). No more physical slots available.',
                  child: OutlinedButton.icon(
                    onPressed: () => _showShelfFullModal(context, variantCount),
                    icon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.statusOrange),
                    label: Text(
                      'Shelf Full ($variantCount/30)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.statusOrange.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                );
              }

              return ElevatedButton.icon(
                onPressed: () => context.push(AppRoutePaths.productForm),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text('Add Fragrance (${30 - variantCount} Slots Left)'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              );
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: productsAsync.when(
        data: (allItems) {
          final uniqueVariants = allItems
              .map((p) => p.perfumeCode.length >= 2 ? p.perfumeCode.substring(0, 2) : p.name)
              .toSet();
          final variantCount = uniqueVariants.length;
          final isShelfFull = variantCount >= 30;

          final filtered = allItems.where((p) {
            final isFemale = p.category.toLowerCase().contains('women') ||
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
            if (_selectedFilter == 'layerA' && !p.shelfLayer.contains('Layer A')) return false;
            if (_selectedFilter == 'layerB' && !p.shelfLayer.contains('Layer B')) return false;
            if (_selectedFilter == 'layerC' && !p.shelfLayer.contains('Layer C')) return false;

            if (_selectedSize == '100ml' && p.bottleSize.toLowerCase() != '100ml') return false;
            if (_selectedSize == '50ml' && p.bottleSize.toLowerCase() != '50ml') return false;

            return true;
          }).toList();

          final invMap = <String, int>{};
          inventoryAsync.whenData((list) {
            for (final item in list) {
              invMap[item.perfumeCode] = item.detected;
            }
          });

          return Column(
            children: [
              // Top Search & Filter Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border(bottom: BorderSide(color: context.borderColor)),
                ),
                child: Column(
                  children: [
                    // Search Bar & Capacity Badge
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (val) => setState(() => _searchQuery = val.trim()),
                            style: TextStyle(color: context.textPrimaryColor),
                            decoration: InputDecoration(
                              hintText: 'Search perfume name, cap OCR code (e.g. AA1, BK2), or brand...',
                              prefixIcon: const Icon(Icons.search_rounded, color: AppColors.brandAccent),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    )
                                  : null,
                              filled: true,
                              fillColor: context.surfaceElevatedColor,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: context.borderColor),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Capacity Status Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isShelfFull
                                ? AppColors.statusGreen.withValues(alpha: 0.12)
                                : context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isShelfFull
                                  ? AppColors.statusGreen.withValues(alpha: 0.5)
                                  : context.borderColor,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isShelfFull ? Icons.inventory_2_rounded : Icons.shelves,
                                size: 18,
                                color: isShelfFull ? AppColors.statusGreen : AppColors.brandAccent,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isShelfFull
                                    ? 'Shelf Full (30/30 Slots • ${allItems.length} SKUs)'
                                    : '$variantCount / 30 Slots Occupied',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: isShelfFull ? AppColors.statusGreen : context.textPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter Chips Row (Gender & Layer Filters)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All Fragrances (${allItems.length})'),
                          const SizedBox(width: 8),
                          _buildGenderFilterChip('men', 'Men\'s Fragrances (30)', AppColors.maleBlue),
                          const SizedBox(width: 8),
                          _buildGenderFilterChip('women', 'Women\'s Fragrances (30)', AppColors.femalePink),
                          const SizedBox(width: 14),
                          Container(width: 1.5, height: 24, color: context.borderColor),
                          const SizedBox(width: 14),
                          _buildFilterChip('layerA', 'Layer A / Top (Male)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('layerB', 'Layer B / Middle (Mixed)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('layerC', 'Layer C / Bottom (Female)'),
                          const SizedBox(width: 14),
                          Container(width: 1.5, height: 24, color: context.borderColor),
                          const SizedBox(width: 14),
                          _buildSizeChip('all', 'All Sizes'),
                          const SizedBox(width: 8),
                          _buildSizeChip('100ml', '100ML (Size 1)'),
                          const SizedBox(width: 8),
                          _buildSizeChip('50ml', '50ML (Size 2)'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Product List Items
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off_rounded, size: 48, color: context.textMutedColor),
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
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final isFemale = p.category.toLowerCase().contains('women') ||
                              p.category.toLowerCase().contains('female') ||
                              p.shelfLayer.contains('Layer C') ||
                              (p.shelfLayer.contains('Layer B') && p.slotPosition >= 6);

                          final detectedQty = invMap[p.perfumeCode] ?? 5;
                          final status = (detectedQty <= 2) ? StatusBadgeType.lowStock : StatusBadgeType.good;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
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
                              onTap: () => context.push(AppRoutePaths.productDetail, extra: p),
                              onEdit: () => context.push(AppRoutePaths.productForm, extra: p),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Unable to load inventory catalog.')),
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
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandAccent : context.borderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : genderColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? genderColor : genderColor.withValues(alpha: 0.35),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildSizeChip(String value, String label) {
    final isSelected = _selectedSize == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedSize = value),
      selectedColor: AppColors.brandAccent,
      backgroundColor: context.surfaceElevatedColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandAccent : context.borderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
    final themeGenderColor = isFemale ? AppColors.femalePink : AppColors.maleBlue;

    return Card(
      color: context.surfaceColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: themeGenderColor.withValues(alpha: context.isDark ? 0.18 : 0.25),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              // Alphanumeric Cap OCR Badge (Blue for Male, Pink for Female)
              Container(
                width: 54,
                height: 54,
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
                child: Center(
                  child: Text(
                    code,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Product Info & Gender / Size Badges
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Gender Tag Pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: themeGenderColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: themeGenderColor.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isFemale ? Icons.female_rounded : Icons.male_rounded,
                                size: 12,
                                color: themeGenderColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isFemale ? 'Women' : 'Men',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: themeGenderColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),

                        // Bottle Size Tag (100ML / 50ML)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            size,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$brand • $layer • $slot',
                      style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                    ),
                  ],
                ),
              ),

              // Stock Status Indicator
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$currentQty',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: isLow ? AppColors.statusRed : AppColors.statusGreen,
                        ),
                      ),
                      Text(
                        ' / 5 Bottles',
                        style: TextStyle(fontSize: 13, color: context.textMutedColor, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  StatusBadge(type: status),
                ],
              ),
              const SizedBox(width: 12),

              // Edit Shortcut Button
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Edit Fragrance SKU',
                onPressed: onEdit,
              ),
              Icon(Icons.chevron_right_rounded, color: context.textMutedColor, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
