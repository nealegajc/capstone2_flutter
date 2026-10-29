import 'dart:io';

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
      final file = await CsvExportService.instance.exportInventorySummaryCsv(
        [],
        branch: branch,
      );
      final visionFile = File(
        file.path.replaceAll('Inventory_Summary', 'Vision_Quality'),
      );
      final buffer = StringBuffer();
      buffer.writeln(
        'Log ID,Brightness,Contrast,Sharpness,Is Acceptable,Preprocessing Applied,Retry Count,Status,Branch,Timestamp',
      );
      for (final l in logs) {
        buffer.writeln(
          '"${l.id}",${l.brightness},${l.contrast},${l.sharpness},${l.isAcceptable},"${l.preprocessingApplied.join('; ')}",${l.retryCount},"${l.status}","${l.branch}","${DateFormat('yyyy-MM-dd HH:mm:ss').format(l.timestamp)}"',
        );
      }
      await visionFile.writeAsString(buffer.toString());
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
    const branch = 'San Pablo';

    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final eventsAsync = ref.watch(stockMovementLogsProvider(branch));
    final salesAnalyticsAsync = ref.watch(salesAnalyticsProvider(branch));

    final canGoBack = onBack != null || context.canPop();

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
                      } else if (context.canPop()) {
                        context.pop();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.assessment_outlined,
                    color: AppColors.brandAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store Reports & Analytics',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Performance auditing, fragrance sales metrics, and CSV reporting exports.',
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
                  onPressed: () =>
                      RecordSaleDialog.show(context, branch: branch),
                  icon: const Icon(Icons.point_of_sale_rounded, size: 18),
                  label: const Text('Record Sale'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brandGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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
                // 0. Sales & Revenue Analytics (Featured Primary Card)
                salesAnalyticsAsync.when(
                  data: (analytics) {
                    return _buildFeaturedActionCard(
                      context: context,
                      title: 'Sales Tracking & Revenue Analytics',
                      description: 'Real-time sales breakdown (100ml @ ₱260, 50ml @ ₱180), 7-day revenue trend chart, top sellers, and transaction log.',
                      icon: Icons.payments_rounded,
                      accentColor: AppColors.statusGreen,
                      badgeText:
                          '₱${NumberFormat('#,##0.00').format(analytics.totalRevenue)} Gross Revenue • ${analytics.totalUnitsSold} Sold',
                      actionLabel: 'View Analytics',
                      actionIcon: Icons.insights_rounded,
                      onAction: () => context.push(AppRoutePaths.sales),
                    );
                  },
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => _buildFeaturedActionCard(
                    context: context,
                    title: 'Sales Tracking & Revenue Analytics',
                    description: 'Real-time sales breakdown (100ml @ ₱260, 50ml @ ₱180), 7-day revenue chart, and transaction log.',
                    icon: Icons.payments_rounded,
                    accentColor: AppColors.statusGreen,
                    badgeText: 'Pricing: 100ml = ₱260 • 50ml = ₱180',
                    actionLabel: 'View Analytics',
                    actionIcon: Icons.insights_rounded,
                    onAction: () => context.push(AppRoutePaths.sales),
                  ),
                ),
                const SizedBox(height: 18),

                // 2-Column Reports Grid (Row 1)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Inventory Summary Report
                    Expanded(
                      child: inventoryAsync.when(
                        data: (items) {
                          final totalBottles = items.fold<int>(
                            0,
                            (sum, i) => sum + i.detected,
                          );
                          return _buildReportCard(
                            context: context,
                            title: 'Current Fragrance Stock Report',
                            description: 'Complete list of all perfumes and counted bottles across all 3 shelf levels.',
                            icon: Icons.inventory_2_rounded,
                            recordsCount:
                                '${items.length} Fragrances • $totalBottles Bottles on Shelf',
                            onExport: () =>
                                _exportInventoryCsv(context, ref, branch),
                          );
                        },
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) => const SizedBox(),
                      ),
                    ),
                    const SizedBox(width: 18),

                    // 2. Inventory Events & Movement Report
                    Expanded(
                      child: eventsAsync.when(
                        data: (events) {
                          return _buildReportCard(
                            context: context,
                            title: 'Stock Movements & Restock History',
                            description: 'Record of bottles taken by customers, restocked deliveries, and shelf count adjustments.',
                            icon: Icons.trending_up_rounded,
                            recordsCount: '${events.length} Recorded Events',
                            onExport: () =>
                                _exportMovementCsv(context, ref, branch),
                          );
                        },
                        loading: () => const SizedBox(),
                        error: (_, _) => const SizedBox(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 2-Column Reports Grid (Row 2)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 3. Vision Detection & Bottle Count Report
                    Expanded(
                      child: _buildReportCard(
                        context: context,
                        title: 'Camera Detection & Scan Accuracy Report',
                        description: 'Accuracy records and picture clarity scores from all 6 shelf cameras.',
                        icon: Icons.camera_enhance_rounded,
                        recordsCount: '6 Shelf Cameras (All Levels)',
                        onExport: () =>
                            _exportVisionAccuracyCsv(context, ref, branch),
                      ),
                    ),
                    const SizedBox(width: 18),

                    // 4. Cloud Synchronization Audit Report
                    Expanded(
                      child: _buildReportCard(
                        context: context,
                        title: 'Cloud Backup History Report',
                        description: 'Summary of internet connection history and timestamps of backups uploaded to the cloud.',
                        icon: Icons.cloud_done_rounded,
                        recordsCount: 'Cloud Connected',
                        onExport: () =>
                            _exportSyncAuditCsv(context, ref, branch),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedActionCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required Color accentColor,
    required String badgeText,
    required String actionLabel,
    required IconData actionIcon,
    required VoidCallback onAction,
  }) {
    return Card(
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accentColor, size: 34),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
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
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'FEATURED',
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 10),
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
                      badgeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            ElevatedButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon, size: 18),
              label: Text(
                actionLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required String recordsCount,
    required VoidCallback onExport,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(
                  alpha: context.isDark ? 0.15 : 0.1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.brandAccent, size: 28),
            ),
            const SizedBox(width: 18),
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
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scope: $recordsCount',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                onPressed: onExport,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Export CSV'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
