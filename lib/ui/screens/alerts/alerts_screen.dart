import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/alert_model.dart';
import '../../../data/models/product_model.dart';
import '../../../data/seeds/catalog_seed_data.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';
import '../../components/scan_workflow_dialog.dart';
import '../reports/record_sale_dialog.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  final String? initialFilter;

  const AlertsScreen({super.key, this.initialFilter});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  late String _selectedFilter;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter ?? 'all';
  }

  @override
  void didUpdateWidget(covariant AlertsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != null && widget.initialFilter != oldWidget.initialFilter) {
      _selectedFilter = widget.initialFilter!;
    }
  }

  bool _isOos(AlertModel a) =>
      a.type == 'out_of_stock' ||
      a.type == 'outOfStock' ||
      a.title.toLowerCase().contains('out of stock');

  bool _isLow(AlertModel a) =>
      (a.type == 'low_stock' || a.type == 'lowStock') && !_isOos(a);

  bool _isSystem(AlertModel a) => !_isOos(a) && !_isLow(a);

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';
    final activeAlertsAsync = ref.watch(liveAlertsProvider(branch));
    final historyAlertsAsync = ref.watch(resolvedAlertsHistoryProvider(branch));
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));

    final bool isLoading = _showHistory
        ? (historyAlertsAsync.isLoading && historyAlertsAsync.valueOrNull == null)
        : (activeAlertsAsync.isLoading && activeAlertsAsync.valueOrNull == null);

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final activeAlerts = activeAlertsAsync.valueOrNull ?? [];
    final historyAlerts = historyAlertsAsync.valueOrNull ?? [];
    final inventoryList = inventoryAsync.valueOrNull ?? [];
    final invMap = {for (final item in inventoryList) item.perfumeCode: item};

    final currentAlerts = _showHistory ? historyAlerts : activeAlerts;

    // Deduplicate if a slot has both out_of_stock and low_stock (out_of_stock takes precedence)
    final oosCodes = currentAlerts.where(_isOos).map((a) => a.perfumeCode).toSet();
    final deduplicatedAlerts = currentAlerts.where((a) {
      if (_isLow(a) && a.perfumeCode.isNotEmpty && oosCodes.contains(a.perfumeCode)) {
        return false;
      }
      return true;
    }).toList();

    final oosCount = deduplicatedAlerts.where(_isOos).length;
    final lowStockCount = deduplicatedAlerts.where(_isLow).length;
    final systemCount = deduplicatedAlerts.where(_isSystem).length;

    final filtered = deduplicatedAlerts.where((a) {
      if (_selectedFilter == 'out_of_stock') {
        return _isOos(a);
      } else if (_selectedFilter == 'low_stock') {
        return _isLow(a);
      } else if (_selectedFilter == 'system') {
        return _isSystem(a);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-page command ribbon
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
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (_showHistory ? AppColors.statusGreen : AppColors.statusRed)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _showHistory ? Icons.history_rounded : Icons.warning_amber_rounded,
                    color: _showHistory ? AppColors.statusGreen : AppColors.statusRed,
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
                            _showHistory
                                ? 'Resolved Alerts & Audit History'
                                : 'Shelf Alerts & Incidents Center',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: (_showHistory ? AppColors.statusGreen : AppColors.statusRed)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: (_showHistory ? AppColors.statusGreen : AppColors.statusRed)
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              _showHistory
                                  ? '${historyAlerts.length} RESOLVED'
                                  : '${deduplicatedAlerts.length} ACTIVE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                color: _showHistory
                                    ? AppColors.statusGreen
                                    : AppColors.statusRed,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _showHistory
                            ? 'Historical audit log of acknowledged incidents, verified restocks, and cleared anomalies.'
                            : 'Real-time anomaly detection across camera tiers and fragrance stock levels.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Segmented Toggle for Active Alerts vs Resolved History
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildToggleTab(
                        label: 'Active Alerts',
                        count: deduplicatedAlerts.length,
                        icon: Icons.warning_amber_rounded,
                        isSelected: !_showHistory,
                        activeColor: AppColors.statusRed,
                        onTap: () => setState(() => _showHistory = false),
                      ),
                      const SizedBox(width: 4),
                      _buildToggleTab(
                        label: 'Resolved History',
                        count: historyAlerts.length,
                        icon: Icons.history_rounded,
                        isSelected: _showHistory,
                        activeColor: AppColors.statusGreen,
                        onTap: () => setState(() => _showHistory = true),
                      ),
                    ],
                  ),
                ),
                if (!_showHistory) ...[
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: activeAlerts.isEmpty
                        ? null
                        : () async {
                            await SqliteService.instance.markAllAlertsRead(
                              null,
                              branch,
                            );
                            ref.invalidate(liveAlertsProvider(branch));
                            ref.invalidate(resolvedAlertsHistoryProvider(branch));
                            ref.invalidate(dashboardStatsProvider(branch));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'All active alerts marked as acknowledged.',
                                  ),
                                  backgroundColor: AppColors.statusGreen,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.done_all_rounded, size: 18),
                    label: const Text('Acknowledge All'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      side: BorderSide(color: context.borderColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutePaths.createRestock),
                  icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
                  label: const Text('Log Restock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Filter Chips Bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor.withValues(alpha: 0.5),
              border: Border(
                bottom: BorderSide(color: context.borderColor),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(
                    'all',
                    'All Alerts',
                    deduplicatedAlerts.length,
                    AppColors.brandAccent,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'out_of_stock',
                    'Out of Stock',
                    oosCount,
                    AppColors.statusRed,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'low_stock',
                    'Low Stock',
                    lowStockCount,
                    AppColors.statusOrange,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'system',
                    'System / Camera',
                    systemCount,
                    AppColors.statusBlue,
                  ),
                ],
              ),
            ),
          ),

          // Alerts List
          Expanded(
            child: filtered.isEmpty
                ? _buildAllClearDashboard(context, branch)
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final a = filtered[index];
                      final isOutOfStock = _isOos(a);
                      final isLowStock = _isLow(a);

                      final invItem = a.perfumeCode.isNotEmpty ? invMap[a.perfumeCode] : null;
                      final stockCount = invItem?.detected ?? (isOutOfStock ? 0 : null);

                      final statusType = _showHistory
                          ? StatusBadgeType.synced
                          : (isOutOfStock
                              ? StatusBadgeType.lowStock
                              : (isLowStock
                                  ? StatusBadgeType.lowStock
                                  : StatusBadgeType.good));
                      final statusLabel = _showHistory
                          ? 'Resolved'
                          : (isOutOfStock
                              ? 'Out of Stock'
                              : (isLowStock ? 'Low Stock' : 'System Alert'));

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildAlertCard(
                          context: context,
                          title: a.title,
                          description: a.desc,
                          timestamp: a.formattedTime,
                          statusLabel: statusLabel,
                          statusType: statusType,
                          hasPerfumeCode: a.perfumeCode.trim().isNotEmpty,
                          perfumeCode: a.perfumeCode,
                          stockCount: stockCount,
                          isHistory: _showHistory,
                          onRecordSale: () async {
                            final code = a.perfumeCode.trim();
                            final sqlite = ref.read(sqliteServiceProvider);
                            var product = await sqlite.getProductByCode(
                              code,
                            );
                            if (product == null) {
                              final allProducts =
                                  ref.read(masterProductsProvider).valueOrNull ??
                                  [];
                              product = allProducts
                                  .where((p) => p.perfumeCode.trim() == code)
                                  .firstOrNull;
                            }
                            product ??= CatalogSeedData.products
                                .where((p) => p.perfumeCode.trim() == code)
                                .firstOrNull;
                            product ??= ProductModel(
                              id: 'prod_$code',
                              perfumeCode: code,
                              name: SqliteService.getPerfumeFullName(
                                code,
                              ),
                              bottleSize: code.endsWith('1')
                                  ? '100ml'
                                  : '50ml',
                            );
                            if (context.mounted) {
                              final recorded = await RecordSaleDialog.show(
                                context,
                                initialProduct: product,
                                branch: branch,
                                isLocked: true,
                              );
                              if (recorded == true) {
                                await sqlite.markAlertRead(a.id);
                                ref.invalidate(liveAlertsProvider(branch));
                                ref.invalidate(resolvedAlertsHistoryProvider(branch));
                                ref.invalidate(dashboardStatsProvider(branch));
                                ref.invalidate(liveInventoryProvider(branch));
                              }
                            }
                          },
                          actionLabel: isOutOfStock || isLowStock
                              ? 'Verify Restock'
                              : 'Inspect Camera View',
                          onAction: () async {
                            if (isOutOfStock || isLowStock) {
                              await ScanWorkflowDialog.show(
                                context,
                                isTargetedVerification: true,
                                targetAlert: a,
                              );
                              ref.invalidate(liveAlertsProvider(branch));
                              ref.invalidate(resolvedAlertsHistoryProvider(branch));
                              ref.invalidate(dashboardStatsProvider(branch));
                              ref.invalidate(liveInventoryProvider(branch));
                            } else {
                              context.push(AppRoutePaths.cameraMonitor);
                            }
                          },
                          secondaryActionLabel:
                              (isOutOfStock || isLowStock) ? 'Restock Order' : null,
                          onSecondaryAction: (isOutOfStock || isLowStock)
                              ? () => context.push(AppRoutePaths.createRestock)
                              : null,
                          onDismiss: _showHistory
                              ? null
                              : () async {
                                  await SqliteService.instance.markAlertRead(
                                    a.id,
                                  );
                                  ref.invalidate(liveAlertsProvider(branch));
                                  ref.invalidate(resolvedAlertsHistoryProvider(branch));
                                  ref.invalidate(dashboardStatsProvider(branch));
                                },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTab({
    required String label,
    required int count,
    required IconData icon,
    required bool isSelected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? activeColor.withValues(alpha: 0.4)
                : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? activeColor : context.textSecondaryColor,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? activeColor : context.textSecondaryColor,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : context.surfaceColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? Colors.white : context.textMutedColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(
    String value,
    String label,
    int count,
    Color activeColor,
  ) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : context.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : context.textPrimaryColor,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textSecondaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard({
    required BuildContext context,
    required String title,
    required String description,
    required String timestamp,
    required String statusLabel,
    required StatusBadgeType statusType,
    required bool hasPerfumeCode,
    String perfumeCode = '',
    int? stockCount,
    bool isHistory = false,
    required VoidCallback onRecordSale,
    required String actionLabel,
    required VoidCallback onAction,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    VoidCallback? onDismiss,
  }) {
    Color accentColor;
    if (isHistory) {
      accentColor = AppColors.statusGreen;
    } else {
      switch (statusType) {
        case StatusBadgeType.lowStock:
          accentColor = statusLabel.contains('Out of Stock')
              ? AppColors.statusRed
              : AppColors.statusOrange;
          break;
        case StatusBadgeType.misplaced:
          accentColor = AppColors.statusOrange;
          break;
        default:
          accentColor = AppColors.statusBlue;
          break;
      }
    }

    final String perfumeFullName = (hasPerfumeCode && perfumeCode.trim().isNotEmpty)
        ? SqliteService.getPerfumeFullName(perfumeCode.trim())
        : '';

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored left accent strip
              Container(width: 5, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StatusBadge(
                        type: statusType,
                        customLabel: statusLabel,
                        large: true,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            if (perfumeFullName.isNotEmpty && !title.contains(perfumeFullName)) ...[
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.sanitizer_rounded, size: 14, color: accentColor),
                                    const SizedBox(width: 6),
                                    Text(
                                      perfumeFullName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: accentColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            // Live Stock Capacity Badge
                            if (stockCount != null) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (stockCount == 0
                                              ? AppColors.statusRed
                                              : (stockCount <= 2
                                                  ? AppColors.statusOrange
                                                  : AppColors.statusGreen))
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: (stockCount == 0
                                                ? AppColors.statusRed
                                                : (stockCount <= 2
                                                    ? AppColors.statusOrange
                                                    : AppColors.statusGreen))
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.inventory_2_rounded,
                                          size: 13,
                                          color: stockCount == 0
                                              ? AppColors.statusRed
                                              : (stockCount <= 2
                                                  ? AppColors.statusOrange
                                                  : AppColors.statusGreen),
                                        ),
                                        const SizedBox(width: 5),
                                        Text(
                                          'Stock: $stockCount / 5 Bottles',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: stockCount == 0
                                                ? AppColors.statusRed
                                                : (stockCount <= 2
                                                    ? AppColors.statusOrange
                                                    : AppColors.statusGreen),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondaryColor,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: context.textMutedColor,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$timestamp • Smart Shelf Display',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Action buttons with touch target (min 44-48dp)
                      if (hasPerfumeCode && !isHistory) ...[
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: onRecordSale,
                            icon: const Icon(
                              Icons.point_of_sale_rounded,
                              size: 18,
                            ),
                            label: const Text('Record Sale'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (secondaryActionLabel != null && onSecondaryAction != null && !isHistory) ...[
                        SizedBox(
                          height: 44,
                          child: OutlinedButton(
                            onPressed: onSecondaryAction,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              side: BorderSide(color: context.borderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              secondaryActionLabel,
                              style: TextStyle(
                                color: context.textSecondaryColor,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (onDismiss != null && !isHistory) ...[
                        Tooltip(
                          message: 'Mark as Resolved',
                          child: SizedBox(
                            height: 44,
                            width: 44,
                            child: OutlinedButton(
                              onPressed: onDismiss,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                side: BorderSide(color: context.borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppColors.statusGreen,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (!isHistory) ...[
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: onAction,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: (statusType == StatusBadgeType.misplaced)
                                  ? AppColors.statusOrange
                                  : AppColors.brandAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(actionLabel),
                          ),
                        ),
                      ],
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

  Widget _buildAllClearDashboard(BuildContext context, String branch) {
    if (_showHistory) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.history_rounded,
                size: 64,
                color: context.textMutedColor,
              ),
              const SizedBox(height: 16),
              Text(
                'No Resolved History',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'When active alerts are verified or acknowledged, they will appear here in the resolved history log.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // All Clear Hero Banner
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.statusGreen.withValues(
                alpha: context.isDark ? 0.12 : 0.08,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.statusGreen.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.statusGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.statusGreen,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Shelf Systems Optimal • Zero Active Incidents',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automated computer vision and tray sensors verify that all 60 fragrance SKUs across 3 tiers are correctly placed with normal inventory levels.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutePaths.cameraMonitor),
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Live Camera Inspection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3 Shelf Tiers Health Grid
          Row(
            children: [
              _buildTierDiagnosticCard(
                context,
                title: 'Top Shelf (Men\'s Fragrances)',
                subtitle: 'Slots AA to AK • 10 Scents (50ml & 100ml)',
                cameras: 'Cameras 1A & 1B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.maleBlue,
              ),
              const SizedBox(width: 16),
              _buildTierDiagnosticCard(
                context,
                title: 'Middle Shelf (Mixed Fragrances)',
                subtitle: 'Slots BA to BK • 10 Scents (Left Men, Right Women)',
                cameras: 'Cameras 2A & 2B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.brandAccent,
              ),
              const SizedBox(width: 16),
              _buildTierDiagnosticCard(
                context,
                title: 'Bottom Shelf (Women\'s Fragrances)',
                subtitle: 'Slots CA to CK • 10 Scents (50ml & 100ml)',
                cameras: 'Cameras 3A & 3B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.femalePink,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Telemetry & Diagnostic Strip
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDiagnosticItem(
                  context,
                  Icons.videocam_rounded,
                  '6 / 6 Cameras Active',
                  'All shelf levels calibrated',
                  AppColors.statusGreen,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.radar_rounded,
                  'Bottle Detection Active',
                  'Smart bottle counter ready',
                  AppColors.brandAccent,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.storage_rounded,
                  'Local Database',
                  'Store database verified',
                  AppColors.maleBlue,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.cloud_done_rounded,
                  'Cloud Backup',
                  'Automatic backup ready',
                  AppColors.statusGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierDiagnosticCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String cameras,
    required String status,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shelves, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 6),
            Text(
              cameras,
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.statusGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.statusGreen,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.statusGreen,
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

  Widget _buildDiagnosticItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
          ],
        ),
      ],
    );
  }
}
