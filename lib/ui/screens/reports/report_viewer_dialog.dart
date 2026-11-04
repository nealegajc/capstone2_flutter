import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/inventory_event_model.dart';
import '../../../data/models/inventory_record_model.dart';
import '../../../data/models/sale_record_model.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../data/services/report_export_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/sales_provider.dart';
import '../../components/wifi_connection_dialog.dart';

class ReportViewerDialog extends ConsumerStatefulWidget {
  final String branch;

  const ReportViewerDialog({super.key, this.branch = 'San Pablo'});

  static Future<void> show(BuildContext context, {String branch = 'San Pablo'}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => ReportViewerDialog(branch: branch),
    );
  }

  @override
  ConsumerState<ReportViewerDialog> createState() => _ReportViewerDialogState();
}

class _ReportViewerDialogState extends ConsumerState<ReportViewerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedFilterChip = 'All'; // 'All', 'Low Stock', 'Layer A', 'Layer B', 'Layer C'
  String _selectedSalesRange = 'today'; // 'today', 'yesterday', '7days', 'month'

  String? _serverUrl;
  bool _isServerStarting = true;
  String? _serverError;
  bool _isSavingLocally = false;
  Timer? _ipRetryTimer;
  int _ipRetryCount = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
    _startServer();
  }

  Future<void> _startServer() async {
    setState(() {
      _isServerStarting = true;
      _serverError = null;
    });

    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final inventory = await sqlite.getInventoryRecords(widget.branch);
      final sales = await sqlite.getSalesRecords(widget.branch);

      final netIp = ref.read(networkStatusProvider).ipAddress;
      final url = await ReportExportService.instance.startServer(
        inventory: inventory,
        sales: sales,
        branch: widget.branch,
        localIp: netIp,
      );

      if (mounted) {
        setState(() {
          _serverUrl = url;
          _isServerStarting = false;
        });

        // If local IP resolved to 127.0.0.1, poll in the background for late DHCP acquisition
        if (url.contains('127.0.0.1')) {
          _startIpRetryPolling();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _serverError = e.toString();
          _isServerStarting = false;
        });
      }
    }
  }

  void _startIpRetryPolling() {
    _ipRetryTimer?.cancel();
    _ipRetryCount = 0;
    _ipRetryTimer = Timer.periodic(const Duration(milliseconds: 2500), (timer) async {
      _ipRetryCount++;
      if (_ipRetryCount > 8) {
        timer.cancel();
        return;
      }
      final newIp = await ReportExportService.instance.updateOrRedetectIp();
      if (newIp != '127.0.0.1' && mounted) {
        timer.cancel();
        setState(() {
          _serverUrl = ReportExportService.instance.serverUrl;
        });
      }
    });
  }

  Future<void> _handleRedetectIp() async {
    final newIp = await ReportExportService.instance.updateOrRedetectIp();
    if (mounted) {
      setState(() {
        _serverUrl = ReportExportService.instance.serverUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newIp != '127.0.0.1'
                ? 'Network IP detected: $newIp'
                : 'Still offline / using localhost ($newIp)',
          ),
          backgroundColor: newIp != '127.0.0.1' ? AppColors.statusGreen : Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _ipRetryTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    ReportExportService.instance.stopServer();
    super.dispose();
  }

  Future<void> _handleSaveLocally() async {
    setState(() => _isSavingLocally = true);
    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final items = await sqlite.getInventoryRecords(widget.branch);
      final file = await CsvExportService.instance.exportInventorySummaryCsv(
        items,
        branch: widget.branch,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Saved report to ${file.path}'),
            backgroundColor: AppColors.statusGreen,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save report: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingLocally = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.92).clamp(900.0, 1400.0);
    final dialogHeight = (screenSize.height * 0.88).clamp(600.0, 850.0);

    final inventoryAsync = ref.watch(liveInventoryProvider(widget.branch));
    final salesAsync = ref.watch(salesRecordsProvider(widget.branch));
    final eventsAsync = ref.watch(stockMovementLogsProvider(widget.branch));
    final networkStatus = ref.watch(networkStatusProvider);

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.borderColor, width: 1.5),
      ),
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            // Top Navigation & Action Header
            _buildDialogHeader(context),

            // Main Body: 65% Interactive Table / 35% QR Code Panel
            Expanded(
              child: Row(
                children: [
                  // Left side (65%): Searchable interactive table with 3 tabs
                  Expanded(
                    flex: 65,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: context.borderColor),
                        ),
                      ),
                      child: Column(
                        children: [
                          // Tab Bar
                          Container(
                            color: context.surfaceElevatedColor,
                            child: TabBar(
                              controller: _tabController,
                              indicatorColor: AppColors.brandGold,
                              indicatorWeight: 3,
                              labelColor: AppColors.brandGold,
                              unselectedLabelColor: context.textSecondaryColor,
                              labelStyle: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                              tabs: const [
                                Tab(
                                  icon: Icon(Icons.inventory_2_rounded, size: 18),
                                  text: 'Shelf Stock (60 Slots)',
                                ),
                                Tab(
                                  icon: Icon(Icons.receipt_long_rounded, size: 18),
                                  text: "Today's Sales Log",
                                ),
                                Tab(
                                  icon: Icon(Icons.history_rounded, size: 18),
                                  text: 'Restock & Movement Audit',
                                ),
                              ],
                            ),
                          ),

                          // Tab Views
                          Expanded(
                            child: TabBarView(
                              controller: _tabController,
                              children: [
                                // Tab 1: Shelf Stock
                                _buildShelfStockTab(context, inventoryAsync),
                                // Tab 2: Sales Log
                                _buildSalesLogTab(context, salesAsync),
                                // Tab 3: Restock & Movement Audit
                                _buildMovementAuditTab(context, eventsAsync),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Right side (35%): Wi-Fi QR Code Transfer Panel
                  Expanded(
                    flex: 35,
                    child: _buildQrSharePanel(context, networkStatus),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(bottom: BorderSide(color: context.borderColor)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brandGold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.preview_rounded,
              color: AppColors.brandGold,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OttoScents Report Viewer & Wireless Transfer',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Interactive shelf stock table & 1-tap phone download via local store Wi-Fi',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Close Viewer',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 1: CURRENT SHELF STOCK (60 SLOTS)
  // ---------------------------------------------------------------------------
  Widget _buildShelfStockTab(
    BuildContext context,
    AsyncValue<List<InventoryRecordModel>> inventoryAsync,
  ) {
    return inventoryAsync.when(
      data: (items) {
        // Filter by chip
        var filtered = items.where((i) {
          if (i.status == 'deleted') return false;
          if (_selectedFilterChip == 'Low Stock') {
            return !i.isSeasonalOff && (i.detected <= 2);
          } else if (_selectedFilterChip == 'Layer A') {
            return i.shelf.contains('A') || i.perfumeCode.startsWith('A');
          } else if (_selectedFilterChip == 'Layer B') {
            return i.shelf.contains('B') || i.perfumeCode.startsWith('B');
          } else if (_selectedFilterChip == 'Layer C') {
            return i.shelf.contains('C') || i.perfumeCode.startsWith('C');
          }
          return true;
        }).toList();

        // Filter by search query
        if (_searchQuery.isNotEmpty) {
          filtered = filtered.where((i) {
            return i.name.toLowerCase().contains(_searchQuery) ||
                i.perfumeCode.toLowerCase().contains(_searchQuery) ||
                i.shelf.toLowerCase().contains(_searchQuery);
          }).toList();
        }

        // Totals calculation
        final totalBottles = items
            .where((i) => !i.isSeasonalOff && i.status != 'deleted')
            .fold<int>(0, (sum, i) => sum + i.detected);
        final totalValuation = items
            .where((i) => !i.isSeasonalOff && i.status != 'deleted')
            .fold<double>(
              0.0,
              (sum, i) =>
                  sum + (i.detected * (i.price > 0 ? i.price : 260.0)),
            );

        return Column(
          children: [
            // Search & Filter Toolbar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search fragrance name or slot (e.g. Sauvage, AA1)...',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () => _searchController.clear(),
                              )
                            : null,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                          horizontal: 12,
                        ),
                        filled: true,
                        fillColor: context.surfaceElevatedColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: context.borderColor),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Filter Chips
                  _buildFilterChip('All', 'All (60)'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Low Stock', 'Low Stock (≤2)'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Layer A', 'Layer A'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Layer B', 'Layer B'),
                  const SizedBox(width: 6),
                  _buildFilterChip('Layer C', 'Layer C'),
                ],
              ),
            ),

            // Interactive Table
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text(
                        'No fragrances found matching "$_searchQuery".',
                        style: TextStyle(color: context.textSecondaryColor),
                      ),
                    )
                  : Scrollbar(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Table(
                          columnWidths: const {
                            0: FlexColumnWidth(1.2), // Slot / Tray
                            1: FlexColumnWidth(2.6), // Fragrance Name
                            2: FlexColumnWidth(1.3), // In Stock
                            3: FlexColumnWidth(1.8), // Status
                            4: FlexColumnWidth(1.4), // Unit Price
                            5: FlexColumnWidth(1.5), // Total Value
                          },
                          border: TableBorder(
                            horizontalInside: BorderSide(
                              color: context.borderColor.withValues(alpha: 0.5),
                              width: 0.8,
                            ),
                          ),
                          children: [
                            // Header Row
                            TableRow(
                              decoration: BoxDecoration(
                                color: context.surfaceElevatedColor,
                              ),
                              children: [
                                _tableTh(context, 'Slot'),
                                _tableTh(context, 'Fragrance Name'),
                                _tableTh(context, 'Stock (Cap 5)'),
                                _tableTh(context, 'Status'),
                                _tableTh(context, 'Unit Price'),
                                _tableTh(context, 'Shelf Value'),
                              ],
                            ),
                            // Data Rows
                            for (final item in filtered)
                              TableRow(
                                children: [
                                  _tableTd(
                                    context,
                                    item.perfumeCode,
                                    isBold: true,
                                    color: AppColors.brandGold,
                                  ),
                                  _tableTd(context, item.name),
                                  _tableTd(
                                    context,
                                    item.isSeasonalOff
                                        ? '0 (Paused)'
                                        : '${item.detected} / 5',
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                      horizontal: 6,
                                    ),
                                    child: _buildStockStatusBadge(context, item),
                                  ),
                                  _tableTd(
                                    context,
                                    '₱${(item.price > 0 ? item.price : 260.0).toStringAsFixed(2)}',
                                  ),
                                  _tableTd(
                                    context,
                                    '₱${((item.isSeasonalOff ? 0 : item.detected) * (item.price > 0 ? item.price : 260.0)).toStringAsFixed(2)}',
                                    isBold: true,
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
            ),

            // Summary Totals Footer Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL ON SHELF: $totalBottles / 300 Bottles',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.brandGold,
                    ),
                  ),
                  Text(
                    'TOTAL SHELF VALUATION: ₱${NumberFormat('#,##0.00').format(totalValuation)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading inventory: $e')),
    );
  }

  Widget _buildFilterChip(String key, String label) {
    final isSelected = _selectedFilterChip == key;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      selectedColor: AppColors.brandGold.withValues(alpha: 0.25),
      side: BorderSide(
        color: isSelected ? AppColors.brandGold : context.borderColor,
      ),
      onSelected: (_) {
        setState(() {
          _selectedFilterChip = key;
        });
      },
    );
  }

  Widget _buildStockStatusBadge(BuildContext context, InventoryRecordModel item) {
    if (item.isSeasonalOff) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Seasonal Off',
          style: TextStyle(
            color: Colors.amber,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (item.detected == 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.statusRed.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Out of Stock',
          style: TextStyle(
            color: AppColors.statusRed,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (item.detected <= 2) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Low (${item.detected})',
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.statusGreen.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'Optimal',
          style: TextStyle(
            color: AppColors.statusGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 2: TODAY'S SALES LOG
  // ---------------------------------------------------------------------------
  Widget _buildSalesLogTab(
    BuildContext context,
    AsyncValue<List<SaleRecordModel>> salesAsync,
  ) {
    return salesAsync.when(
      data: (allSales) {
        final now = DateTime.now();
        List<SaleRecordModel> activeSales;
        String rangeTitle;
        switch (_selectedSalesRange) {
          case 'yesterday':
            final yesterday = now.subtract(const Duration(days: 1));
            activeSales = allSales.where((s) =>
                s.soldAt.year == yesterday.year &&
                s.soldAt.month == yesterday.month &&
                s.soldAt.day == yesterday.day).toList();
            rangeTitle = 'YESTERDAY\'S REVENUE';
            break;
          case '7days':
            final cutoff = now.subtract(const Duration(days: 7));
            activeSales = allSales.where((s) => s.soldAt.isAfter(cutoff)).toList();
            rangeTitle = '7-DAY REVENUE';
            break;
          case 'month':
            activeSales = allSales.where((s) =>
                s.soldAt.year == now.year &&
                s.soldAt.month == now.month).toList();
            rangeTitle = 'THIS MONTH\'S REVENUE';
            break;
          case 'today':
          default:
            activeSales = allSales.where((s) =>
                s.soldAt.year == now.year &&
                s.soldAt.month == now.month &&
                s.soldAt.day == now.day).toList();
            rangeTitle = 'TODAY\'S REVENUE';
            break;
        }

        final totalRevenue = activeSales.fold<double>(
          0.0,
          (sum, s) => sum + s.totalAmount,
        );
        final totalUnits = activeSales.fold<int>(
          0,
          (sum, s) => sum + s.quantitySold,
        );

        return Column(
          children: [
            // Quick Period Filter Chips for Sales
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: context.surfaceElevatedColor,
              child: Row(
                children: [
                  const Icon(Icons.date_range_rounded, size: 16, color: AppColors.brandGold),
                  const SizedBox(width: 8),
                  Text(
                    'Period:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildSalesFilterChip('today', 'Today'),
                  const SizedBox(width: 6),
                  _buildSalesFilterChip('yesterday', 'Yesterday'),
                  const SizedBox(width: 6),
                  _buildSalesFilterChip('7days', 'Last 7 Days'),
                  const SizedBox(width: 6),
                  _buildSalesFilterChip('month', 'This Month'),
                ],
              ),
            ),
            const Divider(height: 1),

            if (activeSales.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.receipt_long_outlined,
                        size: 48,
                        color: context.textSecondaryColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No transactions recorded for this period.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sales recorded via "Record New Sale" will appear here in real time.',
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
              Expanded(
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(1.3), // Time
                        1: FlexColumnWidth(3.2), // Fragrance Name
                        2: FlexColumnWidth(1.0), // Size
                        3: FlexColumnWidth(0.8), // Qty
                        4: FlexColumnWidth(1.3), // Price
                        5: FlexColumnWidth(1.5), // Total
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(
                          color: context.borderColor.withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: context.surfaceElevatedColor,
                          ),
                          children: [
                            _tableTh(context, 'Time'),
                            _tableTh(context, 'Fragrance Name'),
                            _tableTh(context, 'Size'),
                            _tableTh(context, 'Qty'),
                            _tableTh(context, 'Unit Price'),
                            _tableTh(context, 'Total Amount'),
                          ],
                        ),
                        for (final s in activeSales)
                          TableRow(
                            children: [
                              _tableTd(
                                context,
                                DateFormat('hh:mm a').format(s.soldAt),
                              ),
                              _tableTd(
                                context,
                                s.isRefund
                                    ? '[REFUND] ${s.productName} (${s.perfumeCode})'
                                    : '${s.productName} (${s.perfumeCode})',
                                isBold: true,
                                color: s.isRefund ? const Color(0xFFD97706) : null,
                              ),
                              _tableTd(context, s.bottleSize),
                              _tableTd(context, '${s.quantitySold}'),
                              _tableTd(
                                context,
                                '₱${s.unitPrice.toStringAsFixed(2)}',
                              ),
                              _tableTd(
                                context,
                                s.isRefund
                                    ? '-₱${(-s.totalAmount).toStringAsFixed(2)}'
                                    : '₱${s.totalAmount.toStringAsFixed(2)}',
                                isBold: true,
                                color: s.isRefund
                                    ? const Color(0xFFD97706)
                                    : AppColors.statusGreen,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Footer summary
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                border: Border(top: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'TOTAL TRANSACTIONS: ${activeSales.length} ($totalUnits Bottles Sold)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.brandGold,
                    ),
                  ),
                  Text(
                    '$rangeTitle: ₱${NumberFormat('#,##0.00').format(totalRevenue)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading sales log: $e')),
    );
  }

  Widget _buildSalesFilterChip(String key, String label) {
    final isSelected = _selectedSalesRange == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.brandGold : context.textSecondaryColor,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.brandGold.withValues(alpha: 0.2),
      backgroundColor: context.surfaceColor,
      side: BorderSide(
        color: isSelected ? AppColors.brandGold : context.borderColor,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      visualDensity: VisualDensity.compact,
      onSelected: (_) {
        setState(() {
          _selectedSalesRange = key;
        });
      },
    );
  }

  // ---------------------------------------------------------------------------
  // TAB 3: RESTOCK & MOVEMENT AUDIT
  // ---------------------------------------------------------------------------
  Future<void> _confirmCleanSlateHistory(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.statusRed, size: 28),
            const SizedBox(width: 10),
            Text(
              'Clean Slate Movement History?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to clear historical stock movement & restock logs for ${widget.branch}?\n\n'
          '• Active shelf inventory and product catalogs will be strictly safeguarded.\n'
          '• Sales transaction records will NOT be deleted.',
          style: TextStyle(color: context.textSecondaryColor, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: context.textSecondaryColor)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clean Slate History'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sqliteServiceProvider).clearMovementAndRestockLogs(widget.branch);
      ref.invalidate(stockMovementLogsProvider(widget.branch));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Restock & movement history cleared. Inventory & catalog safeguarded.'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    }
  }

  Widget _buildMovementAuditTab(
    BuildContext context,
    AsyncValue<List<InventoryEventModel>> eventsAsync,
  ) {
    return eventsAsync.when(
      data: (events) {
        final eventList = events.reversed.take(40).toList();
        if (eventList.isEmpty) {
          return Center(
            child: Text(
              'No restock or stock movement events recorded yet.',
              style: TextStyle(color: context.textSecondaryColor),
            ),
          );
        }

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                border: Border(bottom: BorderSide(color: context.borderColor)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Audit Event History (${eventList.length} recent)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _confirmCleanSlateHistory(context),
                    icon: const Icon(
                      Icons.cleaning_services_rounded,
                      size: 16,
                      color: AppColors.statusRed,
                    ),
                    label: const Text(
                      'Clean Slate',
                      style: TextStyle(color: AppColors.statusRed, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      side: BorderSide(color: AppColors.statusRed.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Scrollbar(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: eventList.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final ev = eventList[idx];
                    final eventType = ev.eventType;
                    final perfumeCode = ev.perfumeCode;
                    final productName = ev.productName;
                    final qty = ev.quantity;
                    final timestamp = ev.timestamp;

                    final isDamage = eventType == 'DAMAGE_WRITEOFF';
                    final isRestock = eventType == 'RESTOCKED';
                    final isReturn = eventType == 'RETURN_RESTOCKED';
                    final isAudit = eventType == 'AUDIT_VISUAL_COUNT';

                    Color iconBg;
                    Color iconColor;
                    IconData iconData;
                    if (isRestock) {
                      iconBg = AppColors.statusGreen.withValues(alpha: 0.15);
                      iconColor = AppColors.statusGreen;
                      iconData = Icons.add_business_rounded;
                    } else if (isDamage) {
                      iconBg = AppColors.statusRed.withValues(alpha: 0.15);
                      iconColor = AppColors.statusRed;
                      iconData = Icons.delete_sweep_rounded;
                    } else if (isReturn) {
                      iconBg = const Color(0xFFD97706).withValues(alpha: 0.15);
                      iconColor = const Color(0xFFD97706);
                      iconData = Icons.keyboard_return_rounded;
                    } else if (isAudit) {
                      iconBg = AppColors.brandGold.withValues(alpha: 0.15);
                      iconColor = AppColors.brandGold;
                      iconData = Icons.pin_rounded;
                    } else {
                      iconBg = Colors.blue.withValues(alpha: 0.15);
                      iconColor = Colors.blue;
                      iconData = Icons.sync_alt_rounded;
                    }

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          iconData,
                          color: iconColor,
                          size: 18,
                        ),
                      ),
                      title: Text(
                        '$eventType • $productName ($perfumeCode)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      subtitle: Text(
                        'Shelf: ${ev.shelfArea} • Quantity: $qty bottle(s)${ev.reason.isNotEmpty ? " • Reason: ${ev.reason}" : ""}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      trailing: Text(
                        DateFormat('yyyy-MM-dd HH:mm').format(timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error loading events: $e')),
    );
  }

  // ---------------------------------------------------------------------------
  // RIGHT SIDE (35%): WI-FI QR CODE TRANSFER PANEL
  // ---------------------------------------------------------------------------
  Widget _buildQrSharePanel(BuildContext context, dynamic networkStatus) {
    final ssid = networkStatus.currentSsid ?? 'Store Wi-Fi';
    final isOnline = networkStatus.isOnline ?? false;
    final serverUrl = _serverUrl ?? 'http://127.0.0.1:8088';

    return Container(
      color: context.surfaceElevatedColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Wi-Fi Connection Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isOnline
                  ? AppColors.statusGreen.withValues(alpha: 0.15)
                  : Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isOnline ? AppColors.statusGreen : Colors.amber,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isOnline ? Icons.wifi : Icons.wifi_off,
                  color: isOnline ? AppColors.statusGreen : Colors.amber,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  isOnline
                      ? 'Connected: $ssid'
                      : 'Wi-Fi Disconnected',
                  style: TextStyle(
                    color: isOnline ? AppColors.statusGreen : Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // QR Code Display Container
          Expanded(
            child: Center(
              child: _isServerStarting
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Starting Wi-Fi Transfer Server...'),
                      ],
                    )
                  : _serverError != null
                      ? Text(
                          'Server error: $_serverError',
                          style: const TextStyle(color: AppColors.statusRed),
                        )
                      : Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: QrImageView(
                            data: serverUrl,
                            version: QrVersions.auto,
                            size: 180,
                            gapless: false,
                          ),
                        ),
            ),
          ),
          const SizedBox(height: 12),

          // Server Address Badge & Re-detect Network IP Button
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  serverUrl,
                  style: const TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: AppColors.brandGold,
                  ),
                ),
              ),
              InkWell(
                onTap: _handleRedetectIp,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh_rounded, size: 14, color: AppColors.brandGold),
                      SizedBox(width: 4),
                      Text(
                        'Re-detect Network IP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandGold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Instructions for Staff
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.phone_iphone_rounded,
                      size: 16,
                      color: AppColors.brandGold,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Mobile 1-Tap Transfer',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '1. Connect phone to same Wi-Fi ($ssid).\n'
                  '2. Scan QR code with Camera.\n'
                  '3. Download Branded PDF or 8-col CSV directly.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Offline fallback / Save to Kiosk button
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: _isSavingLocally ? null : _handleSaveLocally,
              icon: _isSavingLocally
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded, size: 18),
              label: const Text('Save CSV to Kiosk Storage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.surfaceColor,
                foregroundColor: context.textPrimaryColor,
                side: BorderSide(color: context.borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),

          if (!isOnline) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: TextButton.icon(
                onPressed: () => WifiConnectionDialog.show(context),
                icon: const Icon(Icons.wifi_find_rounded, size: 16),
                label: const Text('Configure Store Wi-Fi'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.brandGold,
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TABLE CELL HELPERS
  // ---------------------------------------------------------------------------
  Widget _tableTh(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: context.textPrimaryColor,
        ),
      ),
    );
  }

  Widget _tableTd(
    BuildContext context,
    String text, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color ?? context.textPrimaryColor,
        ),
      ),
    );
  }
}
