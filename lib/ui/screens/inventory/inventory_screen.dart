import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _selectedFilter = 'all';
  String _selectedSize = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final productsAsync = ref.watch(masterProductsProvider);
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Shelf Inventory (Cap Code OCR Catalog)'),
        actions: [
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.stockMovements),
            icon: const Icon(Icons.history_rounded, size: 20),
            label: const Text('Movement Logs'),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: () => context.push(AppRoutePaths.cameraMonitor),
            icon: const Icon(Icons.videocam_rounded, size: 20),
            label: const Text('Shelf Cameras'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: productsAsync.when(
        data: (allItems) {
          final filtered = allItems.where((p) {
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              if (!p.name.toLowerCase().contains(q) &&
                  !p.perfumeCode.toLowerCase().contains(q) &&
                  !p.brand.toLowerCase().contains(q)) {
                return false;
              }
            }

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
                    // Search Bar
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
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            'Showing ${filtered.length} / ${allItems.length} SKUs',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: context.textPrimaryColor),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('all', 'All Layers (${allItems.length})'),
                          const SizedBox(width: 8),
                          _buildFilterChip('layerA', '📷 Layer A / Top (Male - 20)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('layerB', '📷 Layer B / Middle (Mixed - 20)'),
                          const SizedBox(width: 8),
                          _buildFilterChip('layerC', '📷 Layer C / Bottom (Female - 20)'),
                          const SizedBox(width: 16),
                          Container(width: 1.5, height: 24, color: context.borderColor),
                          const SizedBox(width: 16),
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

              // Product Inventory Grid/List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.search_off_rounded, size: 64, color: context.textMutedColor),
                            const SizedBox(height: 16),
                            Text(
                              'No perfume SKUs found matching "$_searchQuery"',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textSecondaryColor),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final p = filtered[index];
                          final detectedQty = invMap[p.perfumeCode] ?? 5;
                          final status = (detectedQty <= 2) ? StatusBadgeType.lowStock : StatusBadgeType.good;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildInventoryCard(
                              context: context,
                              name: p.name,
                              code: p.perfumeCode,
                              brand: p.brand,
                              size: p.bottleSize.toUpperCase(),
                              layer: p.shelfLayer,
                              slot: 'Slot ${p.slotPosition}',
                              currentQty: detectedQty,
                              status: status,
                              onTap: () => context.push(AppRoutePaths.productDetail),
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

  Widget _buildSizeChip(String value, String label) {
    final isSelected = _selectedSize == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedSize = value),
      selectedColor: AppColors.brandGold,
      backgroundColor: context.surfaceElevatedColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.brandGold : context.borderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildInventoryCard({
    required BuildContext context,
    required String name,
    required String code,
    required String brand,
    required String size,
    required String layer,
    required String slot,
    required int currentQty,
    required StatusBadgeType status,
    required VoidCallback onTap,
  }) {
    final isLow = currentQty <= 2;

    return Card(
      color: context.surfaceColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              // Alphanumeric Cap OCR Badge
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.brandAccent.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    code,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Product Info
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
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Text(
                            size,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.brandAccent,
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
              Icon(Icons.chevron_right_rounded, color: context.textMutedColor, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}
