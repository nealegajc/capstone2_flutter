import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/sale_record_model.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/sales_provider.dart';
import 'report_viewer_dialog.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onBack;

  const ReportsScreen({super.key, this.onBack});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}
class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String _selectedRange = 'today'; // 'today', 'yesterday', '7days', 'month', 'custom'
  DateTimeRange? _customDateRange;

  List<SaleRecordModel> _filterSales(List<SaleRecordModel> allSales) {
    final now = DateTime.now();
    switch (_selectedRange) {
      case 'yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        return allSales.where((s) =>
            s.soldAt.year == yesterday.year &&
            s.soldAt.month == yesterday.month &&
            s.soldAt.day == yesterday.day).toList();
      case '7days':
        final cutoff = now.subtract(const Duration(days: 7));
        return allSales.where((s) => s.soldAt.isAfter(cutoff)).toList();
      case 'month':
        return allSales.where((s) =>
            s.soldAt.year == now.year &&
            s.soldAt.month == now.month).toList();
      case 'custom':
        if (_customDateRange == null) return allSales;
        return allSales.where((s) =>
            !s.soldAt.isBefore(_customDateRange!.start) &&
            !s.soldAt.isAfter(_customDateRange!.end.add(const Duration(days: 1)))).toList();
      case 'today':
      default:
        return allSales.where((s) =>
            s.soldAt.year == now.year &&
            s.soldAt.month == now.month &&
            s.soldAt.day == now.day).toList();
    }
  }

  List<InventoryEventModel> _filterDamageEvents(List<InventoryEventModel> allMovements) {
    final now = DateTime.now();
    final damages = allMovements.where((e) => e.eventType == 'DAMAGE_WRITEOFF');
    switch (_selectedRange) {
      case 'yesterday':
        final yesterday = now.subtract(const Duration(days: 1));
        return damages.where((e) =>
            e.timestamp.year == yesterday.year &&
            e.timestamp.month == yesterday.month &&
            e.timestamp.day == yesterday.day).toList();
      case '7days':
        final cutoff = now.subtract(const Duration(days: 7));
        return damages.where((e) => e.timestamp.isAfter(cutoff)).toList();
      case 'month':
        return damages.where((e) =>
            e.timestamp.year == now.year &&
            e.timestamp.month == now.month).toList();
      case 'custom':
        if (_customDateRange == null) return damages.toList();
        return damages.where((e) =>
            !e.timestamp.isBefore(_customDateRange!.start) &&
            !e.timestamp.isAfter(_customDateRange!.end.add(const Duration(days: 1)))).toList();
      case 'today':
      default:
        return damages.where((e) =>
            e.timestamp.year == now.year &&
            e.timestamp.month == now.month &&
            e.timestamp.day == now.day).toList();
    }
  }

  String _getRangeLabel() {
    switch (_selectedRange) {
      case 'yesterday': return 'Yesterday';
      case '7days': return 'Last 7 Days';
      case 'month': return 'This Month';
      case 'custom':
        if (_customDateRange != null) {
          return '${DateFormat('MMM d').format(_customDateRange!.start)} - ${DateFormat('MMM d').format(_customDateRange!.end)}';
        }
        return 'Custom';
      case 'today':
      default: return 'Today';
    }
  }

  Future<void> _pickCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      initialDateRange: _customDateRange ?? DateTimeRange(
        start: now.subtract(const Duration(days: 7)),
        end: now,
      ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: AppColors.brandGold,
              onPrimary: Colors.white,
              surface: context.surfaceColor,
              onSurface: context.textPrimaryColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedRange = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';

    final salesAsync = ref.watch(salesRecordsProvider(branch));
    final dashboardStatsAsync = ref.watch(dashboardStatsProvider(branch));
    final movementLogsAsync = ref.watch(stockMovementLogsProvider(branch));

    final canGoBack = widget.onBack != null || Navigator.of(context).canPop();

    // Calculate Filtered Retail Metrics
    final allSales = salesAsync.valueOrNull ?? const [];
    final activeSales = _filterSales(allSales);

    // Calculate Filtered Damage Write-Off & Shrinkage Loss
    final allMovements = movementLogsAsync.valueOrNull ?? const [];
    final activeDamageEvents = _filterDamageEvents(allMovements);

    final activeDamageUnits = activeDamageEvents.fold<int>(
      0,
      (sum, e) => sum + e.quantity,
    );
    final activeDamageLoss = activeDamageEvents.fold<double>(
      0.0,
      (sum, e) {
        final unitPrice = e.perfumeCode.endsWith('2')
            ? AppConstants.price50ml
            : (e.perfumeCode.endsWith('1')
                ? AppConstants.price100ml
                : AppConstants.priceFor(''));
        return sum + (e.quantity * unitPrice);
      },
    );

    final activeRevenue = activeSales.fold<double>(
      0.0,
      (sum, s) => sum + s.totalAmount,
    );
    final bottlesSoldActive = activeSales.fold<int>(
      0,
      (sum, s) => sum + s.quantitySold,
    );

    // Derive Top Sellers Aggregation
    final Map<String, ({String name, String code, int units, double rev})> productAggregates = {};
    for (final s in activeSales) {
      final key = s.perfumeCode;
      final existing = productAggregates[key];
      if (existing == null) {
        productAggregates[key] = (name: s.productName, code: s.perfumeCode, units: s.quantitySold, rev: s.totalAmount);
      } else {
        productAggregates[key] = (
          name: s.productName,
          code: s.perfumeCode,
          units: existing.units + s.quantitySold,
          rev: existing.rev + s.totalAmount,
        );
      }
    }
    final sortedTopSellers = productAggregates.values.toList()
      ..sort((a, b) => b.units.compareTo(a.units));

    final bestSellerName = sortedTopSellers.isNotEmpty ? sortedTopSellers.first.name : 'None yet';
    final bestSellerUnits = sortedTopSellers.isNotEmpty ? sortedTopSellers.first.units : 0;
    final bestSellerRevenue = sortedTopSellers.isNotEmpty ? sortedTopSellers.first.rev : 0.0;

    // Derive Low Stock Count
    final stats = dashboardStatsAsync.valueOrNull;
    final lowStockTotal = stats != null
        ? (stats.lowStockCount + stats.outOfStockCount)
        : 0;

    final rangeLabel = _getRangeLabel();

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
                    icon: const Icon(Icons.arrow_back_rounded, size: 24),
                    tooltip: 'Back',
                    onPressed: () {
                      if (widget.onBack != null) {
                        widget.onBack!();
                      } else if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                ],
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.brandGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.analytics_rounded,
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
              ],
            ),
          ),

          // Scrollable report items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // Date Range Filter Bar
                _buildDateFilterBar(context),
                const SizedBox(height: 16),

                // 1. 5-Card Daily/Periodic Retail KPI Grid
                Row(
                  children: [
                    // Card 1: Revenue
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: _selectedRange == 'today' ? "Today's Revenue" : "$rangeLabel Revenue",
                        value: '₱${NumberFormat('#,##0.00').format(activeRevenue)}',
                        subtitle: '${activeSales.length} transaction(s)',
                        icon: Icons.payments_rounded,
                        accentColor: AppColors.statusGreen,
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Card 2: Bottles Sold
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: _selectedRange == 'today' ? 'Bottles Sold Today' : 'Bottles Sold ($rangeLabel)',
                        value: '$bottlesSoldActive Bottles',
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
                        title: _selectedRange == 'today' ? 'Best-Selling Fragrance' : 'Top Seller ($rangeLabel)',
                        value: bestSellerUnits > 0 ? bestSellerName : 'None yet',
                        subtitle: bestSellerUnits > 0
                            ? '$bestSellerUnits sold • ₱${NumberFormat('#,##0.00').format(bestSellerRevenue)}'
                            : (_selectedRange == 'today' ? 'No sales recorded today' : 'No sales recorded in period'),
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
                    const SizedBox(width: 14),
                    // Card 5: Damage & Shrinkage
                    Expanded(
                      child: _buildKpiCard(
                        context: context,
                        title: 'Damage & Shrinkage',
                        value: activeDamageLoss > 0
                            ? '-₱${NumberFormat('#,##0.00').format(activeDamageLoss)}'
                            : '₱0.00',
                        subtitle: activeDamageUnits > 0
                            ? '$activeDamageUnits bottle(s) written off'
                            : 'Optimal (0 write-offs)',
                        icon: Icons.delete_sweep_rounded,
                        accentColor: activeDamageUnits > 0 ? AppColors.statusRed : AppColors.statusGreen,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 2. Prominent Primary Action Banner: "View & Share Reports"
                _buildReportViewerBanner(context, branch),
                const SizedBox(height: 24),

                // 3. Clean Performance Analytics: Top-Selling Fragrances Ranking
                if (sortedTopSellers.isNotEmpty) ...[
                  _buildTopSellersRankingCard(context, sortedTopSellers, rangeLabel),
                  const SizedBox(height: 24),
                ],

                // 4. Recent Sales Activity List (Transaction Feed)
                _buildRecentSalesSection(context, branch, activeSales, activeDamageEvents, rangeLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.borderColor),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.brandGold),
          const SizedBox(width: 8),
          Text(
            'Filter Period:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(width: 12),
          _buildFilterChip('today', 'Today'),
          const SizedBox(width: 6),
          _buildFilterChip('yesterday', 'Yesterday'),
          const SizedBox(width: 6),
          _buildFilterChip('7days', 'Last 7 Days'),
          const SizedBox(width: 6),
          _buildFilterChip('month', 'This Month'),
          const SizedBox(width: 6),
          _buildFilterChip('custom', _selectedRange == 'custom' && _customDateRange != null
              ? '${DateFormat('MMM d').format(_customDateRange!.start)} - ${DateFormat('MMM d').format(_customDateRange!.end)}'
              : 'Custom Range...'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedRange == key;
    return InkWell(
      onTap: () {
        if (key == 'custom') {
          _pickCustomDateRange();
        } else {
          setState(() {
            _selectedRange = key;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandGold
              : context.surfaceElevatedColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.brandGold : context.borderColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? Colors.white : context.textPrimaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildTopSellersRankingCard(
    BuildContext context,
    List<({String code, String name, double rev, int units})> topSellers,
    String rangeLabel,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.leaderboard_rounded, color: AppColors.brandGold, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'Top-Selling Fragrances ($rangeLabel)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              Text(
                '${topSellers.length} fragrance(s) sold',
                style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: topSellers.take(4).toList().asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final item = entry.value;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: entry.key < 3 ? 12 : 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: rank == 1 ? AppColors.brandGold.withValues(alpha: 0.6) : context.borderColor,
                      width: rank == 1 ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: rank == 1
                                  ? AppColors.brandGold
                                  : (rank == 2 ? Colors.blueGrey : (rank == 3 ? Colors.brown : context.surfaceColor)),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$rank',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Text(
                            item.code,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${item.units} bottle(s)',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.blueAccent,
                            ),
                          ),
                          Text(
                            '₱${NumberFormat('#,##0.00').format(item.rev)}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: AppColors.statusGreen,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
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
    List<dynamic> todaySales, [
    List<InventoryEventModel> todayDamageEvents = const [],
    String rangeLabel = 'Today',
  ]) {
    final combined = <dynamic>[
      ...todaySales,
      ...todayDamageEvents,
    ]..sort((a, b) {
        final DateTime timeA = a is SaleRecordModel ? a.soldAt : (a as InventoryEventModel).timestamp;
        final DateTime timeB = b is SaleRecordModel ? b.soldAt : (b as InventoryEventModel).timestamp;
        return timeB.compareTo(timeA);
      });

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
                      "$rangeLabel's Sales Register Feed",
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
                        '${combined.length} items',
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

          if (combined.isEmpty)
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
                      _selectedRange == 'today'
                          ? 'No transactions recorded today.'
                          : 'No transactions recorded for $rangeLabel.',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Transactions will automatically populate as customer purchases are registered.',
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
              itemCount: combined.take(6).length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final item = combined[idx];
                if (item is SaleRecordModel) {
                  final isRefund = item.isRefund;
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
                        color: isRefund
                            ? const Color(0xFFD97706).withValues(alpha: 0.12)
                            : AppColors.statusGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isRefund
                            ? Icons.keyboard_return_rounded
                            : Icons.point_of_sale_rounded,
                        color: isRefund
                            ? const Color(0xFFD97706)
                            : AppColors.statusGreen,
                        size: 22,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          isRefund
                              ? '[REFUND] ${item.productName}'
                              : item.productName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isRefund ? const Color(0xFFD97706) : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isRefund
                                ? const Color(0xFFD97706).withValues(alpha: 0.12)
                                : context.surfaceElevatedColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isRefund
                                  ? const Color(0xFFD97706).withValues(alpha: 0.4)
                                  : context.borderColor,
                            ),
                          ),
                          child: Text(
                            isRefund
                                ? 'REFUND • ${item.perfumeCode}'
                                : '${item.perfumeCode} • ${item.bottleSize}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isRefund
                                  ? const Color(0xFFD97706)
                                  : context.textSecondaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Time: ${DateFormat('hh:mm a').format(item.soldAt)} • ${isRefund ? "Returned" : "Qty"}: ${item.quantitySold.abs()} @ ${item.formattedUnitPrice}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Text(
                      isRefund
                          ? '-₱${NumberFormat('#,##0.00').format(item.totalAmount.abs())}'
                          : '+₱${NumberFormat('#,##0.00').format(item.totalAmount)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: isRefund
                            ? const Color(0xFFD97706)
                            : AppColors.statusGreen,
                      ),
                    ),
                  );
                } else {
                  final e = item as InventoryEventModel;
                  final unitPrice = e.perfumeCode.endsWith('2')
                      ? AppConstants.price50ml
                      : (e.perfumeCode.endsWith('1')
                          ? AppConstants.price100ml
                          : AppConstants.priceFor(''));
                  final loss = e.quantity * unitPrice;
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
                        color: AppColors.statusRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.delete_sweep_rounded,
                        color: AppColors.statusRed,
                        size: 22,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(
                          e.productName.isNotEmpty ? e.productName : e.perfumeCode,
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
                            color: AppColors.statusRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: AppColors.statusRed.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${e.perfumeCode} • Written Off',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.statusRed,
                            ),
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Time: ${DateFormat('hh:mm a').format(e.timestamp)} • Written Off: ${e.quantity} bottle(s) • Shelf ${e.shelfArea}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    trailing: Text(
                      '-₱${NumberFormat('#,##0.00').format(loss)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.statusRed,
                      ),
                    ),
                  );
                }
              },
            ),
        ],
      ),
    );
  }
}

