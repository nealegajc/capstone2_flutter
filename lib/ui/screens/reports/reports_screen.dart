import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/sales_provider.dart';
import 'record_sale_dialog.dart';
import 'report_viewer_dialog.dart';

class ReportsScreen extends ConsumerWidget {
  final VoidCallback? onBack;

  const ReportsScreen({super.key, this.onBack});

  Future<void> _exportInventoryCsv(
    BuildContext context,
    WidgetRef ref,
    String branch,
  ) async {
    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final items = await sqlite.getInventoryRecords(branch);
      final file = await CsvExportService.instance.exportInventorySummaryCsv(
        items,
        branch: branch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Exported ${items.length} inventory records to ${file.path}',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export inventory CSV: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  Future<void> _exportMovementCsv(
    BuildContext context,
    WidgetRef ref,
    String branch,
  ) async {
    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final events = await sqlite.getInventoryEvents(branch);
      final file = await CsvExportService.instance.exportStockMovementCsv(
        events,
        branch: branch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Exported ${events.length} movement audit events to ${file.path}',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export movement CSV: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  Future<void> _exportSyncAuditCsv(
    BuildContext context,
    WidgetRef ref,
    String branch,
  ) async {
    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final queue = await sqlite.getSyncQueue(branch);
      final file = await CsvExportService.instance.exportSyncAuditCsv(
        queue,
        branch: branch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Exported ${queue.length} cloud sync queue items to ${file.path}',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export sync audit CSV: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  Future<void> _exportVisionAccuracyCsv(
    BuildContext context,
    WidgetRef ref,
    String branch,
  ) async {
    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final logs = await sqlite.getImageQualityLogs(branch);
      final visionFile = await CsvExportService.instance.exportVisionQualityCsv(
        logs,
        branch: branch,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ Exported ${logs.length} vision quality records to ${visionFile.path}',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export vision accuracy CSV: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';

    final salesAsync = ref.watch(salesRecordsProvider(branch));
    final dashboardStatsAsync = ref.watch(dashboardStatsProvider(branch));
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));

    final canGoBack = onBack != null || Navigator.of(context).canPop();

    // Calculate Today's Retail Metrics
    final now = DateTime.now();
    final allSales = salesAsync.valueOrNull ?? const [];
    final todaySales = allSales.where((s) =>
        s.soldAt.year == now.year &&
        s.soldAt.month == now.month &&
        s.soldAt.day == now.day).toList();

    final todayRevenue = todaySales.fold<double>(
      0.0,
      (sum, s) => sum + s.totalAmount,
    );
    final bottlesSoldToday = todaySales.fold<int>(
      0,
      (sum, s) => sum + s.quantitySold,
    );

    // Derive Best Seller
    String bestSellerName = 'None yet';
    int bestSellerUnits = 0;
    double bestSellerRevenue = 0.0;
    if (todaySales.isNotEmpty) {
      final Map<String, ({String name, int units, double rev})> productAggregates = {};
      for (final s in todaySales) {
        final key = s.perfumeCode;
        final existing = productAggregates[key];
        if (existing == null) {
          productAggregates[key] = (name: s.productName, units: s.quantitySold, rev: s.totalAmount);
        } else {
          productAggregates[key] = (
            name: s.productName,
            units: existing.units + s.quantitySold,
            rev: existing.rev + s.totalAmount,
          );
        }
      }
      final sorted = productAggregates.values.toList()
        ..sort((a, b) => b.units.compareTo(a.units));
      final top = sorted.first;
      bestSellerName = top.name;
      bestSellerUnits = top.units;
      bestSellerRevenue = top.rev;
    }

    // Derive Low Stock Count
    final stats = dashboardStatsAsync.valueOrNull;
    final lowStockTotal = stats != null
        ? (stats.lowStockCount + stats.outOfStockCount)
        : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-page command ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                if (canGoBack) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    tooltip: 'Back',
                    onPressed: () {
                      if (onBack != null) {
                        onBack!();
                      } else if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.assessment_rounded,
                    color: AppColors.brandGold,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Sales & Reports',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Daily store performance, sales register, and wireless report sharing',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Prominent Action Button: Record New Sale
                ElevatedButton.icon(
                  onPressed: () => RecordSaleDialog.show(context, branch: branch),
                  icon: const Icon(Icons.add_shopping_cart_rounded, size: 22),
                  label: const Text('Record New Sale'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    backgroundColor: AppColors.brandGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable report items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // 1. 4-Card Daily Retail KPI Grid
                Row(
                  children: [
                    // Card 1: Today's Revenue
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: "Today's Revenue",
                        value: '₱${NumberFormat('#,##0.00').format(todayRevenue)}',
                        subtitle: '${todaySales.length} transaction(s)',
                        icon: Icons.payments_rounded,
                        accentColor: AppColors.statusGreen,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Card 2: Bottles Sold Today
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: 'Bottles Sold Today',
                        value: '$bottlesSoldToday Bottles',
                        subtitle: 'Active store volume',
                        icon: Icons.shopping_bag_rounded,
                        accentColor: Colors.blueAccent,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Card 3: Best-Selling Fragrance
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: 'Best-Selling Fragrance',
                        value: bestSellerUnits > 0 ? bestSellerName : 'None yet',
                        subtitle: bestSellerUnits > 0
                            ? '$bestSellerUnits sold • ₱${NumberFormat('#,##0.00').format(bestSellerRevenue)}'
                            : 'No sales recorded today',
                        icon: Icons.star_rounded,
                        accentColor: AppColors.brandGold,
                        isTitleDense: true,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Card 4: Low Stock Alerts
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: 'Low Stock Alerts',
                        value: lowStockTotal > 0 ? '$lowStockTotal Items Low' : 'Optimal (0)',
                        subtitle: lowStockTotal > 0
                            ? 'Requires shelf replenishment'
                            : 'All shelves adequately stocked',
                        icon: Icons.warning_amber_rounded,
                        accentColor: lowStockTotal > 0 ? Colors.orange : AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. Prominent Primary Action Banner: "View & Share Reports"
                _buildReportViewerBanner(context, branch),
                const SizedBox(height: 24),

                // 3. Recent Sales Activity List (Today's Transaction Feed)
                _buildRecentSalesSection(context, branch, todaySales),
                const SizedBox(height: 24),

                // 4. Secondary Accordion / Shortcuts for CSV Exports & Sales Analytics
                _buildSecondaryAccordion(context, ref, branch, inventoryAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // KPI CARD WIDGET
  // ---------------------------------------------------------------------------
  Widget _buildKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    bool isTitleDense = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: context.textSecondaryColor,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: isTitleDense ? 1 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isTitleDense ? 20 : 25,
              fontWeight: FontWeight.w900,
              color: accentColor,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: context.textSecondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROMINENT PRIMARY ACTION BANNER: VIEW & SHARE REPORTS
  // ---------------------------------------------------------------------------
  Widget _buildReportViewerBanner(BuildContext context, String branch) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandGold.withValues(alpha: 0.18),
            AppColors.brandAccent.withValues(alpha: 0.10),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.brandGold.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.brandGold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.qr_code_2_rounded,
              color: AppColors.brandGold,
              size: 38,
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
                      'In-App Report Viewer & Wireless Wi-Fi Transfer',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brandGold,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '1-TAP QR SHARE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Browse real-time shelf stock tables, audit transactions, and scan on-screen QR code with your phone to download PDF & 8-column CSV instantly over local store Wi-Fi.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          ElevatedButton.icon(
            onPressed: () => ReportViewerDialog.show(context, branch: branch),
            icon: const Icon(Icons.open_in_new_rounded, size: 22),
            label: const Text('View & Share Reports'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 62),
              backgroundColor: AppColors.brandGold,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 28,
                vertical: 20,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RECENT SALES ACTIVITY LIST (TODAY'S TRANSACTIONS)
  // ---------------------------------------------------------------------------
  Widget _buildRecentSalesSection(
    BuildContext context,
    String branch,
    List<dynamic> todaySales,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.brandGold,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Today's Sales Register Feed",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: context.surfaceElevatedColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: context.borderColor),
                      ),
                      child: Text(
                        '${todaySales.length} items',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => context.push(AppRoutePaths.sales),
                  icon: const Icon(Icons.insights_rounded, size: 16),
                  label: const Text('Open Full Sales Analytics'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.brandGold,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          if (todaySales.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 40,
                      color: context.textSecondaryColor.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No transactions recorded today.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap "Record New Sale" to register customer fragrance purchases.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: todaySales.take(6).length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final s = todaySales[idx];
                return ListTile(
                  dense: false,
                  minTileHeight: 62.0,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.statusGreen.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.point_of_sale_rounded,
                      color: AppColors.statusGreen,
                      size: 22,
                    ),
                  ),
                  title: Row(
                    children: [
                      Text(
                        s.productName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.surfaceElevatedColor,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Text(
                          '${s.perfumeCode} • ${s.bottleSize}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(
                    'Time: ${DateFormat('hh:mm a').format(s.soldAt)} • Cashier: ${s.soldBy} • Qty: ${s.quantitySold} @ ${s.formattedUnitPrice}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  trailing: Text(
                    s.formattedTotal,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: AppColors.statusGreen,
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECONDARY ACCORDION / SHORTCUTS FOR CSV EXPORTS
  // ---------------------------------------------------------------------------
  Widget _buildSecondaryAccordion(
    BuildContext context,
    WidgetRef ref,
    String branch,
    AsyncValue<dynamic> inventoryAsync,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.file_download_outlined,
            color: AppColors.brandGold,
            size: 20,
          ),
        ),
        title: Text(
          'Direct CSV Downloads & Store Records',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
        subtitle: Text(
          'Direct CSV files saved to Kiosk local storage (~/Downloads/OttoScents_Reports).',
          style: TextStyle(
            fontSize: 11,
            color: context.textSecondaryColor,
          ),
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: _buildExportTile(
                  context: context,
                  title: 'Current Fragrance Stock',
                  subtitle: 'All shelf bottles and pricing',
                  icon: Icons.inventory_2_outlined,
                  onTap: () => _exportInventoryCsv(context, ref, branch),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildExportTile(
                  context: context,
                  title: 'Stock Movements & Restocks',
                  subtitle: 'Historical bottle refills',
                  icon: Icons.trending_up_rounded,
                  onTap: () => _exportMovementCsv(context, ref, branch),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildExportTile(
                  context: context,
                  title: 'Camera Detection Accuracy',
                  subtitle: '6-Camera image logs & scores',
                  icon: Icons.camera_enhance_outlined,
                  onTap: () => _exportVisionAccuracyCsv(context, ref, branch),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildExportTile(
                  context: context,
                  title: 'Cloud Backup & Sync Queue',
                  subtitle: 'Pending cloud payloads',
                  icon: Icons.cloud_done_outlined,
                  onTap: () => _exportSyncAuditCsv(context, ref, branch),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportTile({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor),
      ),
      child: ListTile(
        dense: false,
        minTileHeight: 60.0,
        leading: Icon(icon, color: AppColors.brandGold, size: 22),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
        ),
        trailing: const Icon(Icons.download_rounded, size: 20),
        onTap: onTap,
      ),
    );
  }
}
