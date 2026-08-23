import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../data/models/inventory_record_model.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class InventoryScreen extends StatelessWidget {
  final ValueChanged<InventoryRecordModel> onSelectProduct;
  final VoidCallback onAddProduct;

  const InventoryScreen({
    super.key,
    required this.onSelectProduct,
    required this.onAddProduct,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final items = provider.inventoryList;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filterOptions = ['All Items', 'Low Stock', 'Out of Stock', 'Misplaced', 'Needs Review'];
    final branchOptions = ['All Branches', 'San Pablo', 'Lipa'];

    return ScrollScreen(
      title: 'Perfume Inventory',
      subtitle: 'Browse and manage real-time inventory records across branches',
      actions: [
        if (user?.isAdmin == true)
          AppButton(
            text: 'Add Product',
            icon: Icons.add_rounded,
            onPressed: onAddProduct,
            height: 48,
            fontSize: 14,
          ),
      ],
      children: [
        // Filter & Search Header Row
        Row(
          children: [
            // Search Input
            Expanded(
              flex: 4,
              child: TextField(
                onChanged: provider.setInventorySearchQuery,
                decoration: InputDecoration(
                  hintText: 'Search perfume name, code, category...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: isDark ? AppColors.darkCardBg : Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Branch Selector
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardBg : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: provider.selectedInventoryBranch,
                  items: branchOptions.map((b) => DropdownMenuItem(value: b, child: Text(b))).toList(),
                  onChanged: (val) {
                    if (val != null) provider.setInventoryBranchFilter(val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 16),

            // View Mode Toggle (List / Grid)
            Container(
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCardBg : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => provider.setInventoryViewMode(InventoryViewMode.list),
                    icon: Icon(
                      Icons.format_list_bulleted_rounded,
                      color: provider.inventoryViewMode == InventoryViewMode.list
                          ? AppColors.accent
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                  ),
                  IconButton(
                    onPressed: () => provider.setInventoryViewMode(InventoryViewMode.grid),
                    icon: Icon(
                      Icons.grid_view_rounded,
                      color: provider.inventoryViewMode == InventoryViewMode.grid
                          ? AppColors.accent
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Status Filter Chips Row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filterOptions.map((filter) {
              final isSelected = provider.selectedInventoryFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 10.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => provider.setInventoryStatusFilter(filter),
                  selectedColor: AppColors.accent.withOpacity(0.2),
                  checkmarkColor: AppColors.accent,
                  labelStyle: TextStyle(
                    color: isSelected
                        ? AppColors.accent
                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  side: BorderSide(
                    color: isSelected ? AppColors.accent : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 24),

        // Inventory Items Display
        if (items.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 64, color: AppColors.gray),
                  const SizedBox(height: 16),
                  const Text(
                    'No Inventory Items Found',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Try adjusting your search query or filter options.',
                    style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
          )
        else if (provider.inventoryViewMode == InventoryViewMode.list)
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildListItem(item, isDark);
            },
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.4,
            ),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildGridItem(item, isDark);
            },
          ),
      ],
    );
  }

  Widget _buildListItem(InventoryRecordModel item, bool isDark) {
    return AppCard(
      onTap: () => onSelectProduct(item),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                item.perfumeCode,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBorder : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.category,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${item.branch} • ${item.shelf} • Price: ₱${item.price.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.detected} / ${item.recorded}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: item.isLowStock
                      ? AppColors.orange
                      : (item.isOutOfStock ? AppColors.red : AppColors.green),
                ),
              ),
              const SizedBox(height: 4),
              StatusChip(status: item.status, fontSize: 11),
            ],
          ),
          const SizedBox(width: 12),
          const Icon(Icons.chevron_right_rounded, color: AppColors.gray),
        ],
      ),
    );
  }

  Widget _buildGridItem(InventoryRecordModel item, bool isDark) {
    return AppCard(
      onTap: () => onSelectProduct(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    item.perfumeCode,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              StatusChip(status: item.status, fontSize: 10),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${item.branch} • ${item.shelf}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₱${item.price.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                'Stock: ${item.detected}/${item.recorded}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: item.isLowStock ? AppColors.orange : AppColors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
