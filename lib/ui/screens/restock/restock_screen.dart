import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/inventory_record_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/models/restock_record_model.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../providers/kiosk_providers.dart';

class RestockScreen extends ConsumerWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';
    final statsAsync = ref.watch(dashboardStatsProvider(branch));
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final productsAsync = ref.watch(masterProductsProvider);
    final restockRecordsAsync = ref.watch(restockRecordsProvider(branch));
    final movementLogsAsync = ref.watch(stockMovementLogsProvider(branch));

    final productsMap = <String, ProductModel>{};
    for (final p in productsAsync.valueOrNull ?? <ProductModel>[]) {
      productsMap[p.perfumeCode] = p;
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-Page Command Ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.brandAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Restock & Deliveries Management',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Monitor shelf replenishment health, resolve low-stock fragrance trays, and audit delivery history.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Export CSV Action
                OutlinedButton.icon(
                  onPressed: () => _exportRestockCsv(
                    context,
                    branch: branch,
                    events: movementLogsAsync.valueOrNull ?? [],
                    records: restockRecordsAsync.valueOrNull ?? [],
                  ),
                  icon: const Icon(Icons.download_rounded, size: 22),
                  label: const Text(
                    'Export Restock CSV',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    foregroundColor: context.textPrimaryColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Primary Log New Restock Action
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutePaths.createRestock),
                  icon: const Icon(Icons.add_rounded, size: 24),
                  label: const Text(
                    'Log New Restock',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Screen Body with 3 Retail Cards
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CARD 1: Shelf Capacity Health
                  statsAsync.when(
                    data: (stats) => _buildShelfCapacityHealthCard(
                      context,
                      stats: stats,
                    ),
                    loading: () => _buildCardLoadingState(
                      context,
                      title: 'Shelf Capacity Health',
                    ),
                    error: (err, _) => _buildErrorCard(
                      context,
                      title: 'Shelf Capacity Health',
                      error: err.toString(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // CARD 2: Trays Needing Restock
                  inventoryAsync.when(
                    data: (inventory) {
                      final needingRestock = inventory
                          .where((item) => !item.isSeasonalOff && item.detected <= 2)
                          .toList()
                        ..sort((a, b) {
                          final stockCompare = a.detected.compareTo(b.detected);
                          if (stockCompare != 0) return stockCompare;
                          return a.perfumeCode.compareTo(b.perfumeCode);
                        });

                      return _buildTraysNeedingRestockCard(
                        context,
                        items: needingRestock,
                        productsMap: productsMap,
                      );
                    },
                    loading: () => _buildCardLoadingState(
                      context,
                      title: 'Trays Needing Restock',
                    ),
                    error: (err, _) => _buildErrorCard(
                      context,
                      title: 'Trays Needing Restock',
                      error: err.toString(),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // CARD 3: Recent Restock Activity
                  _buildRecentRestockActivityCard(
                    context,
                    branch: branch,
                    restockRecordsAsync: restockRecordsAsync,
                    movementLogsAsync: movementLogsAsync,
                    productsMap: productsMap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CARD 1: Shelf Capacity Health
  // ===========================================================================
  Widget _buildShelfCapacityHealthCard(
    BuildContext context, {
    required DashboardStats stats,
  }) {
    final totalInStock = stats.totalInStock;
    final totalCapacity = stats.totalCapacity > 0 ? stats.totalCapacity : 300;
    final percentage = (totalInStock / totalCapacity * 100).clamp(0.0, 100.0);
    final deficit = (totalCapacity - totalInStock).clamp(0, totalCapacity);

    // Health badge determination:
    // OPTIMAL (>=90%), NORMAL (75-89%), RESTOCK RECOMMENDED (<75%), CRITICAL (<50%)
    final String healthLabel;
    final Color healthColor;
    final Color healthBgColor;
    final IconData healthIcon;

    if (percentage >= 90.0) {
      healthLabel = 'OPTIMAL';
      healthColor = AppColors.statusGreen;
      healthBgColor = AppColors.statusGreenBg;
      healthIcon = Icons.check_circle_rounded;
    } else if (percentage >= 75.0) {
      healthLabel = 'NORMAL';
      healthColor = AppColors.statusBlue;
      healthBgColor = AppColors.statusBlueBg;
      healthIcon = Icons.info_outline_rounded;
    } else if (percentage >= 50.0) {
      healthLabel = 'RESTOCK RECOMMENDED';
      healthColor = AppColors.statusOrange;
      healthBgColor = AppColors.statusOrangeBg;
      healthIcon = Icons.warning_amber_rounded;
    } else {
      healthLabel = 'CRITICAL';
      healthColor = AppColors.statusRed;
      healthBgColor = AppColors.statusRedBg;
      healthIcon = Icons.error_outline_rounded;
    }

    return Card(
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
            // Card Header: Title & Health Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: healthColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.analytics_outlined,
                        color: healthColor,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shelf Capacity Health',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Text(
                          'Real-time physical bottle count vs active shelf capacity',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: healthBgColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: healthColor.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(healthIcon, color: healthColor, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        healthLabel,
                        style: TextStyle(
                          color: healthColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Big Numbers & Percentage Gauge
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '$totalInStock / $totalCapacity',
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: context.textPrimaryColor,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Bottles on Shelf',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.textSecondaryColor,
                  ),
                ),
                const Spacer(),
                Text(
                  '${percentage.toStringAsFixed(1)}% Capacity Filled',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: healthColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Visual Progress Gauge
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 14,
                child: LinearProgressIndicator(
                  value: (percentage / 100.0).clamp(0.0, 1.0),
                  backgroundColor: context.surfaceElevatedColor,
                  valueColor: AlwaysStoppedAnimation<Color>(healthColor),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // Sub-metrics Strip: Active Slots Count & Empty Bottle Deficit
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSubMetricItem(
                      context,
                      icon: Icons.view_module_rounded,
                      label: 'Active Slots Count',
                      value: '${stats.activeItemCount} Slots',
                      subtitle: 'Active SKUs on shelf',
                      accentColor: AppColors.brandAccent,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 38,
                    color: context.borderColor,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Expanded(
                    child: _buildSubMetricItem(
                      context,
                      icon: Icons.battery_alert_rounded,
                      label: 'Empty Bottle Deficit',
                      value: '$deficit Bottles',
                      subtitle: deficit == 0
                          ? 'Zero deficit (100% full)'
                          : 'Needs +$deficit bottles to fill',
                      accentColor: deficit > 0
                          ? AppColors.statusOrange
                          : AppColors.statusGreen,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 38,
                    color: context.borderColor,
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  Expanded(
                    child: _buildSubMetricItem(
                      context,
                      icon: Icons.warning_rounded,
                      label: 'Low / Out of Stock',
                      value: '${stats.lowStockCount + stats.outOfStockCount} Slots',
                      subtitle: 'Items requiring restock (≤2)',
                      accentColor: (stats.lowStockCount + stats.outOfStockCount) > 0
                          ? AppColors.statusRed
                          : AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubMetricItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required Color accentColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: accentColor, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.textMutedColor,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondaryColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // CARD 2: Trays Needing Restock
  // ===========================================================================
  Widget _buildTraysNeedingRestockCard(
    BuildContext context, {
    required List<InventoryRecordModel> items,
    required Map<String, ProductModel> productsMap,
  }) {
    return Card(
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
            // Card Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: items.isEmpty
                            ? AppColors.statusGreen.withValues(alpha: 0.12)
                            : AppColors.statusOrange.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        items.isEmpty
                            ? Icons.verified_rounded
                            : Icons.add_shopping_cart_rounded,
                        color: items.isEmpty
                            ? AppColors.statusGreen
                            : AppColors.statusOrange,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trays Needing Restock',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Text(
                          'Active fragrance slots detected with ≤ 2 bottles',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: items.isEmpty
                        ? AppColors.statusGreenBg
                        : AppColors.statusOrangeBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: items.isEmpty
                          ? AppColors.statusGreen.withValues(alpha: 0.3)
                          : AppColors.statusOrange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    items.isEmpty
                        ? 'All Trays Stocked'
                        : '${items.length} ${items.length == 1 ? "Tray" : "Trays"} Require Refill',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: items.isEmpty
                          ? AppColors.statusGreen
                          : AppColors.statusOrange,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Content: Empty celebratory state vs list of fragrance cards
            if (items.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                decoration: BoxDecoration(
                  color: AppColors.statusGreenBg.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.statusGreen.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.statusGreen,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Shelf Stock Optimal: 0 Trays Require Replenishment',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'All active perfume slots currently hold 3 or more bottles. No immediate replenishment required.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;
                  final crossAxisCount = isWide ? 2 : 1;

                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      mainAxisExtent: 150,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final product = productsMap[item.perfumeCode];
                      return _buildLowStockFragranceCard(
                        context,
                        item: item,
                        product: product,
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLowStockFragranceCard(
    BuildContext context, {
    required InventoryRecordModel item,
    ProductModel? product,
  }) {
    final code = item.perfumeCode;
    final trayCode = code.length >= 2 ? code.substring(0, 2).toUpperCase() : code;
    final layerName = product?.shelfLayer ??
        (code.startsWith('A')
            ? 'Layer A'
            : (code.startsWith('B') ? 'Layer B' : 'Layer C'));
    final size = product?.bottleSize.toUpperCase() ??
        (code.endsWith('1') ? '100ML' : '50ML');
    final detected = item.detected;
    final deficit = (5 - detected).clamp(1, 5);
    final isCritical = detected == 0;

    final badgeColor = isCritical ? AppColors.statusRed : AppColors.statusOrange;
    final badgeBg = isCritical ? AppColors.statusRedBg : AppColors.statusOrangeBg;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCritical
              ? AppColors.statusRed.withValues(alpha: 0.35)
              : context.borderColor,
          width: isCritical ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Cap Code Badge & Bottle Visual
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: item.category.toLowerCase() == 'women'
                    ? [const Color(0xFF9D174D), const Color(0xFFEC4899)]
                    : [const Color(0xFF1E3A8A), const Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  code,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  size,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Fragrance Info & Stock Level
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Tray $trayCode - $layerName • $size',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Stock badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBg,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: badgeColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        '$detected / 5 Bottles',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Needs +$deficit bottles to fill',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // Direct Restock Now Button
          ElevatedButton(
            onPressed: () {
              context.push(AppRoutePaths.createRestock, extra: item.perfumeCode);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Restock Now',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // CARD 3: Recent Restock Activity
  // ===========================================================================
  Widget _buildRecentRestockActivityCard(
    BuildContext context, {
    required String branch,
    required AsyncValue<List<RestockRecordModel>> restockRecordsAsync,
    required AsyncValue<List<InventoryEventModel>> movementLogsAsync,
    required Map<String, ProductModel> productsMap,
  }) {
    return Card(
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
            // Card Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: AppColors.brandAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Restock Activity',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Text(
                          'Recorded delivery batches and physical replenishment history',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                // Export CSV quick button
                OutlinedButton.icon(
                  onPressed: () => _exportRestockCsv(
                    context,
                    branch: branch,
                    events: movementLogsAsync.valueOrNull ?? [],
                    records: restockRecordsAsync.valueOrNull ?? [],
                  ),
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text(
                    'Export Restock CSV',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.textPrimaryColor,
                    side: BorderSide(color: context.borderColor),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Activity Records List
            restockRecordsAsync.when(
              data: (records) {
                if (records.isNotEmpty) {
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: records.take(15).length,
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = records[index];
                      final product = productsMap[r.perfumeCode];
                      return _buildRestockRecordTile(
                        context,
                        record: r,
                        product: product,
                      );
                    },
                  );
                }

                // Fallback to movementLogs if records empty
                final events = (movementLogsAsync.valueOrNull ?? [])
                    .where(
                      (e) =>
                          e.eventType == 'RESTOCKED' || e.eventType == 'ADDED',
                    )
                    .toList();

                if (events.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 36,
                      horizontal: 24,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceElevatedColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: context.borderColor),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: context.textMutedColor,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No Restock Deliveries Logged Yet',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'When shipments arrive at $branch kiosk, tap "Log New Restock" to record the delivery.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: events.take(15).length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final e = events[index];
                    return _buildEventTile(context, event: e);
                  },
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Center(
                child: Text('Error loading restock records: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRestockRecordTile(
    BuildContext context, {
    required RestockRecordModel record,
    ProductModel? product,
  }) {
    final isVerified = record.status.toLowerCase() == 'verified';
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(record.createdAt);
    final code = record.perfumeCode;
    final trayCode = code.length >= 2 ? code.substring(0, 2).toUpperCase() : code;
    final layer = product?.shelfLayer ??
        (code.startsWith('A')
            ? 'Layer A'
            : (code.startsWith('B') ? 'Layer B' : 'Layer C'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isVerified
                  ? AppColors.statusGreen.withValues(alpha: 0.12)
                  : AppColors.brandAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isVerified ? Icons.verified_rounded : Icons.move_to_inbox_rounded,
              color: isVerified ? AppColors.statusGreen : AppColors.brandAccent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      record.productName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        record.perfumeCode,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Batch ID: ${record.id} • Tray $trayCode ($layer) • $dateStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${record.quantity} Bottles',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusGreen,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isVerified
                      ? AppColors.statusGreenBg
                      : AppColors.statusBlueBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isVerified
                        ? AppColors.statusGreen.withValues(alpha: 0.3)
                        : AppColors.statusBlue.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  isVerified ? 'Verified' : 'Received',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isVerified
                        ? AppColors.statusGreen
                        : AppColors.statusBlue,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEventTile(
    BuildContext context, {
    required InventoryEventModel event,
  }) {
    final dateStr = DateFormat('MMM dd, yyyy • hh:mm a').format(event.timestamp);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.statusGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              color: AppColors.statusGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      event.productName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        event.perfumeCode,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandAccent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'Batch ID: ${event.id} • Shelf: ${event.shelfArea} • $dateStr',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${event.quantity} Bottles',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.statusGreen,
                ),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.statusGreenBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.statusGreen.withValues(alpha: 0.3),
                  ),
                ),
                child: const Text(
                  'Verified',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.statusGreen,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Helpers & CSV Export
  // ===========================================================================
  Widget _buildCardLoadingState(BuildContext context, {required String title}) {
    return Card(
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                'Loading $title...',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorCard(
    BuildContext context, {
    required String title,
    required String error,
  }) {
    return Card(
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.statusRed.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          'Error loading $title: $error',
          style: const TextStyle(color: AppColors.statusRed),
        ),
      ),
    );
  }

  Future<void> _exportRestockCsv(
    BuildContext context, {
    required String branch,
    required List<InventoryEventModel> events,
    required List<RestockRecordModel> records,
  }) async {
    try {
      final file = await CsvExportService.instance.exportStockMovementCsv(
        events,
        branch: branch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restock CSV exported to: ${file.path}'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export CSV: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }
}
