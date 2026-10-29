import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/sale_record_model.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../data/services/toast_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/sales_provider.dart';
import 'record_sale_dialog.dart';

class SalesAnalyticsScreen extends ConsumerStatefulWidget {
  const SalesAnalyticsScreen({super.key});

  @override
  ConsumerState<SalesAnalyticsScreen> createState() =>
      _SalesAnalyticsScreenState();
}

class _SalesAnalyticsScreenState extends ConsumerState<SalesAnalyticsScreen> {
  String _selectedBranch = 'All Branches';
  String _selectedTimeFilter = 'All Time'; // 'Today', 'This Week', 'All Time'

  @override
  Widget build(BuildContext context) {
    final effectiveBranch = _selectedBranch == 'All Branches'
        ? null
        : _selectedBranch;

    final salesAsync = ref.watch(salesRecordsProvider(effectiveBranch));

    return salesAsync.when(
      data: (allSales) {
        // Filter by selected time window
        final now = DateTime.now();
        final filteredSales = allSales.where((s) {
          if (_selectedTimeFilter == 'Today') {
            return s.soldAt.year == now.year &&
                s.soldAt.month == now.month &&
                s.soldAt.day == now.day;
          } else if (_selectedTimeFilter == 'This Week') {
            final weekAgo = now.subtract(const Duration(days: 7));
            return s.soldAt.isAfter(weekAgo);
          }
          return true;
        }).toList();

        final analytics = SalesAnalytics.fromSales(filteredSales);

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
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Back to Reports',
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.statusGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.insights_rounded,
                        color: AppColors.statusGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Sales Tracking & Revenue Analytics',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Live gross revenue, volume trends, top performers, and transaction audit.',
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
                      onPressed: () => RecordSaleDialog.show(
                        context,
                        branch: effectiveBranch,
                      ),
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        size: 18,
                      ),
                      label: const Text('Record New Sale'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusGreen,
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

              // Scrollable analytics body
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    // Filter & Store Bar
                    _buildFilterBar(context),
                    const SizedBox(height: 20),

                    // 4 KPI Summary Cards
                    _buildKpiGrid(context, analytics),
                    const SizedBox(height: 24),

                    // Middle Row: 7-Day Revenue Trend Chart & Top Sellers
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: 7-Day Bar Chart
                        Expanded(
                          flex: 3,
                          child: _buildRevenueChartCard(context, analytics),
                        ),
                        const SizedBox(width: 20),

                        // Right: Top 5 Best Sellers
                        Expanded(
                          flex: 2,
                          child: _buildTopSellersCard(context, analytics),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Bottom: Detailed Recent Sales Table
                    _buildSalesTableCard(context, filteredSales),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          'Error loading sales: $e',
          style: const TextStyle(color: AppColors.statusRed),
        ),
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Icon(Icons.analytics_rounded, color: AppColors.brandAccent, size: 24),
          const SizedBox(width: 12),
          Text(
            'Pricing standard: 100ml = ₱${AppConstants.price100ml.toStringAsFixed(0)} • 50ml = ₱${AppConstants.price50ml.toStringAsFixed(0)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
          const Spacer(),

          // Time Period Filter
          Text(
            'Period: ',
            style: TextStyle(
              color: context.textSecondaryColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTimeFilter,
                dropdownColor: context.surfaceColor,
                style: TextStyle(
                  color: context.textPrimaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                items: const [
                  DropdownMenuItem(value: 'All Time', child: Text('All Time')),
                  DropdownMenuItem(
                    value: 'This Week',
                    child: Text('This Week (7d)'),
                  ),
                  DropdownMenuItem(value: 'Today', child: Text('Today Only')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTimeFilter = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Branch Filter
          Text(
            'Branch: ',
            style: TextStyle(
              color: context.textSecondaryColor,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBranch,
                dropdownColor: context.surfaceColor,
                style: TextStyle(
                  color: context.textPrimaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'All Branches',
                    child: Text('All Branches'),
                  ),
                  DropdownMenuItem(
                    value: 'San Pablo',
                    child: Text('San Pablo Kiosk'),
                  ),
                  DropdownMenuItem(value: 'Lipa', child: Text('Lipa Branch')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedBranch = val);
                },
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Refresh Button
          IconButton(
            onPressed: () {
              ref.invalidate(salesRecordsProvider);
              ref.invalidate(salesAnalyticsProvider);
              ToastService.showToast(
                title: 'Analytics Refreshed',
                message: 'Loaded latest sales records.',
                type: 'info',
              );
            },
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh Data',
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(BuildContext context, SalesAnalytics analytics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        final cardCount = isWide ? 4 : 2;
        return GridView.count(
          crossAxisCount: cardCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: isWide ? 2.2 : 1.8,
          children: [
            _buildKpiCard(
              context: context,
              title: 'Total Gross Revenue',
              value:
                  '₱${NumberFormat('#,##0.00').format(analytics.totalRevenue)}',
              subtext: '${analytics.totalUnitsSold} total bottles sold',
              icon: Icons.payments_rounded,
              color: AppColors.statusGreen,
            ),
            _buildKpiCard(
              context: context,
              title: '100ml Fragrance Sales',
              value:
                  '₱${NumberFormat('#,##0.00').format(analytics.revenue100ml)}',
              subtext: '${analytics.units100ml} bottles sold @ ₱260',
              icon: Icons.water_drop_rounded,
              color: AppColors.brandAccent,
            ),
            _buildKpiCard(
              context: context,
              title: '50ml Fragrance Sales',
              value:
                  '₱${NumberFormat('#,##0.00').format(analytics.revenue50ml)}',
              subtext: '${analytics.units50ml} bottles sold @ ₱180',
              icon: Icons.opacity_rounded,
              color: AppColors.femalePink,
            ),
            _buildKpiCard(
              context: context,
              title: 'Average Order Value',
              value: analytics.totalUnitsSold > 0
                  ? '₱${(analytics.totalRevenue / analytics.totalUnitsSold).toStringAsFixed(2)}'
                  : '₱0.00',
              subtext: 'Revenue per bottle sold',
              icon: Icons.trending_up_rounded,
              color: AppColors.brandGold,
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtext,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: context.textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtext,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevenueChartCard(
    BuildContext context,
    SalesAnalytics analytics,
  ) {
    final daily = analytics.last7DaysSales;
    final maxRevenue = daily.fold<double>(
      1000.0,
      (max, d) => d.revenue > max ? d.revenue : max,
    );

    return Container(
      padding: const EdgeInsets.all(22),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '7-Day Revenue Trend',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Daily sales in Philippine Pesos (₱)',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColors.statusGreen.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.statusGreen,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Live Tracking',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Chart
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxRevenue * 1.25,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => context.surfaceElevatedColor,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final item = daily[group.x.toInt()];
                      return BarTooltipItem(
                        '${item.dayLabel} (${item.dateString})\n',
                        TextStyle(
                          color: context.textPrimaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                        children: [
                          TextSpan(
                            text:
                                '₱${NumberFormat('#,##0.00').format(rod.toY)}\n',
                            style: const TextStyle(
                              color: AppColors.statusGreen,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          TextSpan(
                            text: '${item.units} bottles sold',
                            style: TextStyle(
                              color: context.textSecondaryColor,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 54,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox();
                        return Text(
                          '₱${(value / 1000).toStringAsFixed(1)}k',
                          style: TextStyle(
                            color: context.textMutedColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < daily.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              daily[idx].dayLabel,
                              style: TextStyle(
                                color: context.textSecondaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: context.borderColor.withValues(alpha: 0.5),
                    strokeWidth: 1,
                    dashArray: [4, 4],
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: daily.asMap().entries.map((e) {
                  final idx = e.key;
                  final d = e.value;
                  return BarChartGroupData(
                    x: idx,
                    barRods: [
                      BarChartRodData(
                        toY: d.revenue,
                        gradient: LinearGradient(
                          colors: d.revenue > 0
                              ? [AppColors.brandAccent, AppColors.statusGreen]
                              : [context.borderColor, context.borderColor],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSellersCard(BuildContext context, SalesAnalytics analytics) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.brandGold,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'Top 5 Best Sellers',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Ranked by gross revenue',
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 18),

          if (analytics.topSellers.isEmpty)
            Container(
              height: 180,
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 36,
                    color: context.textMutedColor,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No sales recorded yet',
                    style: TextStyle(
                      color: context.textMutedColor,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            )
          else
            ...analytics.topSellers.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final item = entry.value;
              final isTop1 = rank == 1;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isTop1
                      ? AppColors.brandGold.withValues(alpha: 0.1)
                      : context.surfaceElevatedColor,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isTop1
                        ? AppColors.brandGold.withValues(alpha: 0.4)
                        : context.borderColor,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isTop1
                            ? AppColors.brandGold
                            : context.borderColor,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$rank',
                        style: TextStyle(
                          color: isTop1
                              ? Colors.black
                              : context.textPrimaryColor,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.productName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${item.perfumeCode} • ${item.bottleSize} • ${item.unitsSold} units',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₱${NumberFormat('#,##0.00').format(item.totalRevenue)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: isTop1
                            ? AppColors.brandGold
                            : AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSalesTableCard(
    BuildContext context,
    List<SaleRecordModel> sales,
  ) {
    return Container(
      padding: const EdgeInsets.all(22),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Sales Transactions',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${sales.length} transactions logged in SQLite database',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
              OutlinedButton.icon(
                onPressed: sales.isEmpty
                    ? null
                    : () async {
                        try {
                          final file = await CsvExportService.instance
                              .exportSalesRecordsCsv(
                                sales,
                                branch: _selectedBranch == 'All Branches'
                                    ? 'All'
                                    : _selectedBranch,
                              );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '✓ Exported ${sales.length} sales records to ${file.path}',
                                ),
                                backgroundColor: AppColors.statusGreen,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to export sales CSV: $e'),
                                backgroundColor: AppColors.statusRed,
                              ),
                            );
                          }
                        }
                      },
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text(
                  'Export CSV',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandAccent,
                  side: const BorderSide(color: AppColors.brandAccent),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          if (sales.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 48,
                    color: context.textMutedColor,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Sales Transactions Logged',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Record New Sale" to register bottle sales at ₱260 (100ml) or ₱180 (50ml).',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            )
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: context.borderColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(1.8), // Date/Time
                    1: FlexColumnWidth(1.2), // Code
                    2: FlexColumnWidth(3.0), // Product Name
                    3: FlexColumnWidth(1.2), // Size
                    4: FlexColumnWidth(1.2), // Unit Price
                    5: FlexColumnWidth(1.0), // Qty
                    6: FlexColumnWidth(1.8), // Total
                    7: FlexColumnWidth(0.8), // Action
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    // Header
                    TableRow(
                      decoration: BoxDecoration(
                        color: context.surfaceElevatedColor,
                      ),
                      children: [
                        _buildTableHeaderCell('Date / Time'),
                        _buildTableHeaderCell('Code'),
                        _buildTableHeaderCell('Product'),
                        _buildTableHeaderCell('Size'),
                        _buildTableHeaderCell('Unit Price'),
                        _buildTableHeaderCell('Qty'),
                        _buildTableHeaderCell('Total'),
                        _buildTableHeaderCell(''),
                      ],
                    ),
                    // Rows
                    ...sales.map((sale) {
                      return TableRow(
                        decoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: context.borderColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              sale.formattedShortDate,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.brandAccent.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                sale.perfumeCode,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: AppColors.brandAccent,
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              sale.productName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.textPrimaryColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              sale.bottleSize,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              sale.formattedUnitPrice,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              '${sale.quantitySold}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Text(
                              sale.formattedTotal,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.statusGreen,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                                color: AppColors.statusRed,
                              ),
                              tooltip: 'Void / Remove Sale Record',
                              onPressed: () =>
                                  _confirmDeleteSale(context, sale),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: context.textSecondaryColor,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSale(
    BuildContext context,
    SaleRecordModel sale,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Void Sale Record?',
          style: TextStyle(
            color: context.textPrimaryColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Are you sure you want to void sale of ${sale.quantitySold}x ${sale.productName} (${sale.formattedTotal})?',
          style: TextStyle(color: context.textSecondaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Void Record'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final sqlite = ref.read(sqliteServiceProvider);
      await sqlite.deleteSaleRecord(sale.id);
      ref.invalidate(salesRecordsProvider);
      ref.invalidate(salesAnalyticsProvider);
      ToastService.showToast(
        title: 'Sale Voided',
        message: 'Transaction record removed.',
        type: 'info',
      );
    }
  }
}
