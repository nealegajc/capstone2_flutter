import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/inventory_record_model.dart';
import '../models/sale_record_model.dart';
import 'network_service.dart';

class ReportExportService {
  static final ReportExportService instance = ReportExportService._();
  ReportExportService._();

  HttpServer? _server;
  int _port = 8088;
  String? _localIp;

  bool get isServerRunning => _server != null;
  int get port => _port;
  String? get localIp => _localIp;
  String get serverUrl => 'http://${_localIp ?? "127.0.0.1"}:$_port';

  // ---------------------------------------------------------------------------
  // 1. CLEAN 8-COLUMN CSV GENERATION
  // ---------------------------------------------------------------------------
  String generateShelfStockCsv({
    required List<InventoryRecordModel> items,
    required String branch,
  }) {
    final buffer = StringBuffer();
    // 8 Required Friendly Columns
    buffer.writeln(
      'Fragrance Name,Shelf / Tray Location,In Stock (Bottles),Max Capacity,Stock Status,Unit Price (PHP),Total Shelf Value (PHP),Last Checked',
    );

    int totalBottles = 0;
    const int totalCapacity = 300;
    double totalValuation = 0.0;

    for (final item in items) {
      if (item.status == 'deleted') continue;

      final int inStock = item.isSeasonalOff ? 0 : item.detected;
      const int maxCap = 5;
      final double unitPrice = item.price > 0 ? item.price : 260.0;
      final double totalValue = inStock * unitPrice;

      if (!item.isSeasonalOff) {
        totalBottles += inStock;
        totalValuation += totalValue;
      }

      String stockStatus;
      if (item.isSeasonalOff) {
        stockStatus = 'Seasonal Off (Paused)';
      } else if (item.detected == 0) {
        stockStatus = 'Out of Stock (Refill Needed)';
      } else if (item.detected <= 2) {
        stockStatus = 'Low Stock (${item.detected} Left)';
      } else {
        stockStatus = 'Optimal (${item.detected}/5)';
      }

      final trayCode = item.perfumeCode.length >= 2
          ? item.perfumeCode.substring(0, 2)
          : item.perfumeCode;
      final location = 'Tray $trayCode (${item.shelf}) - Slot ${item.perfumeCode}';
      final lastChecked = DateFormat('yyyy-MM-dd HH:mm:ss').format(item.lastUpdated);

      final row = [
        _escapeCsv(item.name),
        _escapeCsv(location),
        inStock,
        maxCap,
        _escapeCsv(stockStatus),
        unitPrice.toStringAsFixed(2),
        totalValue.toStringAsFixed(2),
        _escapeCsv(lastChecked),
      ];
      buffer.writeln(row.join(','));
    }

    // Friendly Summary Footer
    buffer.writeln();
    buffer.writeln(
      'TOTALS,,$totalBottles,$totalCapacity,,,${totalValuation.toStringAsFixed(2)},',
    );

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // 2. DAILY SALES CSV GENERATION
  // ---------------------------------------------------------------------------
  String generateDailySalesCsv({
    required List<SaleRecordModel> sales,
    required String branch,
    String dateRangeLabel = 'Today',
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Transaction ID,Time,Fragrance Name,Perfume Code,Bottle Size,Quantity Sold,Unit Price (PHP),Total Amount (PHP),Sync Status',
    );

    double totalRev = 0.0;
    int totalUnits = 0;

    for (final s in sales) {
      totalRev += s.totalAmount;
      totalUnits += s.quantitySold;
      final row = [
        s.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(s.soldAt),
        _escapeCsv(s.productName),
        s.perfumeCode,
        s.bottleSize,
        s.quantitySold,
        s.unitPrice.toStringAsFixed(2),
        s.totalAmount.toStringAsFixed(2),
        s.syncStatus,
      ];
      buffer.writeln(row.join(','));
    }

    buffer.writeln();
    buffer.writeln(
      'SUMMARY TOTALS,,,,,$totalUnits,,${totalRev.toStringAsFixed(2)},',
    );
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // 3. BRANDED PDF GENERATOR
  // ---------------------------------------------------------------------------
  Future<Uint8List> generateReportPdfBytes({
    required List<InventoryRecordModel> inventory,
    required List<SaleRecordModel> sales,
    required String branch,
    String dateRangeLabel = 'Today',
  }) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final bool alreadyFiltered = dateRangeLabel != 'Today';
    final targetSales = alreadyFiltered
        ? sales
        : sales.where((s) =>
            s.soldAt.year == now.year &&
            s.soldAt.month == now.month &&
            s.soldAt.day == now.day).toList();

    // Aggregates & Metrics
    final double grossRev = targetSales.where((s) => !s.isRefund).fold(0.0, (sum, s) => sum + s.totalAmount);
    final double totalRefunds = targetSales.where((s) => s.isRefund).fold(0.0, (sum, s) => sum + (-s.totalAmount));
    final double netRev = targetSales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final int totalUnitsSold = targetSales.where((s) => !s.isRefund).fold(0, (sum, s) => sum + s.quantitySold);
    final int onShelf = inventory.where((i) => !i.isSeasonalOff).fold(0, (sum, i) => sum + i.detected);
    final int lowStockCount = inventory.where((i) => !i.isSeasonalOff && i.detected > 0 && i.detected <= 2).length;
    final int outOfStockCount = inventory.where((i) => !i.isSeasonalOff && i.detected == 0).length;
    final int optimalCount = inventory.where((i) => !i.isSeasonalOff && i.detected > 2).length;
    final int activeSlots = inventory.where((i) => !i.isSeasonalOff).length;

    // Top Selling Fragrances aggregation
    final Map<String, ({String name, int units, double rev})> productAggs = {};
    for (final s in targetSales.where((s) => !s.isRefund)) {
      final key = s.perfumeCode;
      final existing = productAggs[key];
      if (existing == null) {
        productAggs[key] = (name: s.productName, units: s.quantitySold, rev: s.totalAmount);
      } else {
        productAggs[key] = (
          name: s.productName,
          units: existing.units + s.quantitySold,
          rev: existing.rev + s.totalAmount,
        );
      }
    }
    final topSellers = productAggs.values.toList()
      ..sort((a, b) => b.units.compareTo(a.units));
    final top5Sellers = topSellers.take(5).toList();
    final maxUnits = top5Sellers.isNotEmpty ? top5Sellers.first.units : 1;

    // OttoScents Dual-Mode Printable Palette
    const goldColor = PdfColor.fromInt(0xFFD97706);
    const darkHeaderBg = PdfColor.fromInt(0xFF0F172A);
    const darkCardBg = PdfColor.fromInt(0xFF1E293B);
    const lightTableBorder = PdfColor.fromInt(0xFFE2E8F0);
    const lightTableHeadBg = PdfColor.fromInt(0xFFF1F5F9);
    const lightTextPrimary = PdfColor.fromInt(0xFF0F172A);
    const lightTextSecondary = PdfColor.fromInt(0xFF475569);
    const greenColor = PdfColor.fromInt(0xFF16A34A);
    const amberColor = PdfColor.fromInt(0xFFD97706);
    const redColor = PdfColor.fromInt(0xFFDC2626);
    const blueColor = PdfColor.fromInt(0xFF2563EB);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (pw.Context context) {
          if (context.pageNumber == 1) return pw.SizedBox();
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 12),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: lightTableBorder, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'OTTO SCENTS • $branch Store Report ($dateRangeLabel)',
                  style: const pw.TextStyle(color: lightTextSecondary, fontSize: 9),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(color: lightTextSecondary, fontSize: 9),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: lightTableBorder, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Generated wirelessly via OttoScents Smart Shelf Local Wi-Fi Gateway',
                  style: const pw.TextStyle(color: lightTextSecondary, fontSize: 8),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(color: lightTextSecondary, fontSize: 8),
                ),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // Dark Header Card (Dual Mode contrast)
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: darkHeaderBg,
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Text(
                            'OTTO SCENTS',
                            style: pw.TextStyle(
                              color: goldColor,
                              fontSize: 22,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: darkCardBg,
                              borderRadius: pw.BorderRadius.circular(4),
                              border: pw.Border.all(color: goldColor, width: 0.5),
                            ),
                            child: pw.Text(
                              dateRangeLabel.toUpperCase(),
                              style: pw.TextStyle(
                                color: goldColor,
                                fontSize: 9,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Smart Shelf Retail & Inventory Performance Report',
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 11),
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Branch: $branch',
                        style: pw.TextStyle(
                          color: goldColor,
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
                        style: const pw.TextStyle(color: PdfColor.fromInt(0xFF94A3B8), fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // 4 KPI Summary Cards (Dark card contrast with vibrant KPI highlights)
            pw.Row(
              children: [
                _buildPdfKpiCard(
                  title: "$dateRangeLabel's Net Revenue",
                  value: 'PHP ${NumberFormat('#,##0.00').format(netRev)}',
                  accentColor: greenColor,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Bottles Sold',
                  value: '$totalUnitsSold Sold',
                  accentColor: blueColor,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Shelf Bottles',
                  value: '$onShelf / 300',
                  accentColor: goldColor,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Low Stock Alerts',
                  value: '$lowStockCount Items Low',
                  accentColor: lowStockCount > 0 ? amberColor : greenColor,
                ),
              ],
            ),
            pw.SizedBox(height: 16),

            // Visual Analytics: Charts Section
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: lightTableHeadBg,
                borderRadius: pw.BorderRadius.circular(6),
                border: pw.Border.all(color: lightTableBorder),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Chart 1: Top 5 Selling Fragrances Horizontal Bar Chart
                  pw.Expanded(
                    flex: 55,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'TOP-SELLING FRAGRANCES (UNITS & REVENUE)',
                          style: pw.TextStyle(
                            color: lightTextPrimary,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        if (top5Sellers.isEmpty)
                          pw.Text(
                            'No sales recorded in this period.',
                            style: const pw.TextStyle(color: lightTextSecondary, fontSize: 8),
                          )
                        else
                          for (final item in top5Sellers) ...[
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Expanded(
                                  child: pw.Text(
                                    item.name,
                                    overflow: pw.TextOverflow.clip,
                                    maxLines: 1,
                                    style: const pw.TextStyle(fontSize: 8, color: lightTextPrimary),
                                  ),
                                ),
                                pw.Text(
                                  '${item.units} units • PHP ${NumberFormat('#,##0.00').format(item.rev)}',
                                  style: pw.TextStyle(
                                    fontSize: 8,
                                    fontWeight: pw.FontWeight.bold,
                                    color: goldColor,
                                  ),
                                ),
                              ],
                            ),
                            pw.SizedBox(height: 2),
                            // Bar
                            pw.Container(
                              height: 6,
                              width: double.infinity,
                              decoration: pw.BoxDecoration(
                                color: const PdfColor.fromInt(0xFFE2E8F0),
                                borderRadius: pw.BorderRadius.circular(3),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(
                                    flex: (item.units * 100 ~/ maxUnits).clamp(5, 100),
                                    child: pw.Container(
                                      decoration: pw.BoxDecoration(
                                        color: goldColor,
                                        borderRadius: pw.BorderRadius.circular(3),
                                      ),
                                    ),
                                  ),
                                  pw.Expanded(
                                    flex: (100 - (item.units * 100 ~/ maxUnits)).clamp(0, 95),
                                    child: pw.SizedBox(),
                                  ),
                                ],
                              ),
                            ),
                            pw.SizedBox(height: 5),
                          ],
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 14),

                  // Chart 2: Shelf Stock Health Distribution Segmented Ratio Bar
                  pw.Expanded(
                    flex: 45,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'SHELF STOCK HEALTH STATUS',
                          style: pw.TextStyle(
                            color: lightTextPrimary,
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 8),
                        // Segmented bar
                        pw.Container(
                          height: 14,
                          decoration: pw.BoxDecoration(
                            borderRadius: pw.BorderRadius.circular(4),
                            color: const PdfColor.fromInt(0xFFE2E8F0),
                          ),
                          child: activeSlots == 0
                              ? pw.SizedBox()
                              : pw.Row(
                                  children: [
                                    if (optimalCount > 0)
                                      pw.Expanded(
                                        flex: optimalCount,
                                        child: pw.Container(color: greenColor),
                                      ),
                                    if (lowStockCount > 0)
                                      pw.Expanded(
                                        flex: lowStockCount,
                                        child: pw.Container(color: amberColor),
                                      ),
                                    if (outOfStockCount > 0)
                                      pw.Expanded(
                                        flex: outOfStockCount,
                                        child: pw.Container(color: redColor),
                                      ),
                                  ],
                                ),
                        ),
                        pw.SizedBox(height: 8),
                        // Legend
                        pw.Row(
                          children: [
                            _buildLegendItem('Optimal (>2)', '$optimalCount', greenColor),
                            pw.SizedBox(width: 8),
                            _buildLegendItem('Low (1-2)', '$lowStockCount', amberColor),
                            pw.SizedBox(width: 8),
                            _buildLegendItem('Empty (0)', '$outOfStockCount', redColor),
                          ],
                        ),
                        pw.SizedBox(height: 6),
                        pw.Text(
                          'Total Capacity: 300 bottles (60 slots × 5 max capacity)',
                          style: const pw.TextStyle(color: lightTextSecondary, fontSize: 7.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Section 1: Sales Transactions Table (Light Printable Theme)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  "Sales Transactions ($dateRangeLabel • ${targetSales.length} records)",
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: lightTextPrimary,
                  ),
                ),
                pw.Text(
                  "Net Revenue: PHP ${NumberFormat('#,##0.00').format(netRev)}",
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: netRev >= 0 ? greenColor : redColor,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            if (targetSales.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: lightTableHeadBg,
                  borderRadius: pw.BorderRadius.circular(4),
                  border: pw.Border.all(color: lightTableBorder),
                ),
                child: pw.Text(
                  'No transactions recorded for this period.',
                  style: const pw.TextStyle(color: lightTextSecondary, fontSize: 9),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: lightTableBorder, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: lightTableHeadBg),
                    children: [
                      _pdfThLight('Time'),
                      _pdfThLight('Type'),
                      _pdfThLight('Fragrance Name'),
                      _pdfThLight('Code'),
                      _pdfThLight('Size'),
                      _pdfThLight('Qty'),
                      _pdfThLight('Unit Price'),
                      _pdfThLight('Total'),
                    ],
                  ),
                  for (final s in targetSales.take(40))
                    pw.TableRow(
                      children: [
                        _pdfTdLight(DateFormat('HH:mm:ss').format(s.soldAt)),
                        _pdfTdLight(
                          s.isRefund ? 'Refund' : 'Sale',
                          color: s.isRefund ? amberColor : greenColor,
                          isBold: true,
                        ),
                        _pdfTdLight(s.productName, isBold: true),
                        _pdfTdLight(s.perfumeCode),
                        _pdfTdLight(s.bottleSize),
                        _pdfTdLight('${s.quantitySold}'),
                        _pdfTdLight('PHP ${s.unitPrice.toStringAsFixed(2)}'),
                        _pdfTdLight(
                          s.isRefund
                              ? '-PHP ${(-s.totalAmount).toStringAsFixed(2)}'
                              : 'PHP ${s.totalAmount.toStringAsFixed(2)}',
                          color: s.isRefund ? redColor : greenColor,
                          isBold: true,
                        ),
                      ],
                    ),
                  // Summary Totals Row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: lightTableHeadBg),
                    children: [
                      _pdfTdLight('TOTAL', isBold: true),
                      _pdfTdLight('${targetSales.length} txns', isBold: true),
                      _pdfTdLight('Gross: PHP ${NumberFormat('#,##0.00').format(grossRev)}', isBold: true),
                      _pdfTdLight('-', isBold: true),
                      _pdfTdLight('-', isBold: true),
                      _pdfTdLight('$totalUnitsSold units', isBold: true),
                      _pdfTdLight(
                        totalRefunds > 0 ? 'Ref: -PHP ${NumberFormat('#,##0.00').format(totalRefunds)}' : 'Ref: 0',
                        isBold: true,
                        color: totalRefunds > 0 ? amberColor : lightTextSecondary,
                      ),
                      _pdfTdLight(
                        'PHP ${NumberFormat('#,##0.00').format(netRev)}',
                        isBold: true,
                        color: netRev >= 0 ? greenColor : redColor,
                      ),
                    ],
                  ),
                ],
              ),
            pw.SizedBox(height: 18),

            // Section 2: Shelf Stock Inventory Table (Light Printable Theme)
            pw.Text(
              'Shelf Stock Inventory (${inventory.length} slots)',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: lightTextPrimary,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: lightTableBorder, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: lightTableHeadBg),
                  children: [
                    _pdfThLight('Slot'),
                    _pdfThLight('Fragrance Name'),
                    _pdfThLight('Shelf / Layer'),
                    _pdfThLight('Stock (Cap 5)'),
                    _pdfThLight('Stock Health'),
                    _pdfThLight('Unit Price'),
                    _pdfThLight('Total Value'),
                  ],
                ),
                for (final item in inventory.where((i) => i.status != 'deleted'))
                  pw.TableRow(
                    children: [
                      _pdfTdLight(item.perfumeCode, isBold: true),
                      _pdfTdLight(item.name),
                      _pdfTdLight(item.shelf),
                      _pdfTdLight(item.isSeasonalOff ? '0 (Off)' : '${item.detected} / 5'),
                      _pdfTdLight(
                        item.isSeasonalOff
                            ? 'Seasonal Off'
                            : (item.detected == 0
                                ? 'Out of Stock'
                                : (item.detected <= 2 ? 'Low Stock' : 'Optimal')),
                        color: item.isSeasonalOff
                            ? lightTextSecondary
                            : (item.detected == 0
                                ? redColor
                                : (item.detected <= 2 ? amberColor : greenColor)),
                        isBold: true,
                      ),
                      _pdfTdLight('PHP ${(item.price > 0 ? item.price : 260.0).toStringAsFixed(2)}'),
                      _pdfTdLight(
                        'PHP ${((item.isSeasonalOff ? 0 : item.detected) * (item.price > 0 ? item.price : 260.0)).toStringAsFixed(2)}',
                      ),
                    ],
                  ),
              ],
            ),
          ];
        },
      ),
    );

    return await pdf.save();
  }

  static pw.Widget _buildLegendItem(String label, String count, PdfColor color) {
    return pw.Row(
      children: [
        pw.Container(
          width: 8,
          height: 8,
          decoration: pw.BoxDecoration(color: color, borderRadius: pw.BorderRadius.circular(2)),
        ),
        pw.SizedBox(width: 4),
        pw.Text(
          '$label: $count',
          style: const pw.TextStyle(fontSize: 7.5, color: PdfColor.fromInt(0xFF475569)),
        ),
      ],
    );
  }

  static pw.Widget _buildPdfKpiCard({
    required String title,
    required String value,
    required PdfColor accentColor,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: const PdfColor.fromInt(0xFF1E293B),
          borderRadius: pw.BorderRadius.circular(6),
          border: pw.Border.all(color: const PdfColor.fromInt(0xFF334155)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              title.toUpperCase(),
              style: const pw.TextStyle(
                color: PdfColor.fromInt(0xFF94A3B8),
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: accentColor,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfThLight(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: const PdfColor.fromInt(0xFF0F172A),
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _pdfTdLight(
    String text, {
    PdfColor color = const PdfColor.fromInt(0xFF1E293B),
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: color,
          fontSize: 7.5,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. LIGHTWEIGHT LOCAL HTTP SERVER (dart:io HttpServer)
  // ---------------------------------------------------------------------------
  List<SaleRecordModel> filterSalesByRange(List<SaleRecordModel> allSales, String? range) {
    final now = DateTime.now();
    switch (range) {
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
      case 'all':
        return allSales;
      case 'today':
      default:
        return allSales.where((s) =>
            s.soldAt.year == now.year &&
            s.soldAt.month == now.month &&
            s.soldAt.day == now.day).toList();
    }
  }

  String getRangeLabel(String? range) {
    switch (range) {
      case 'yesterday': return 'Yesterday';
      case '7days': return 'Last 7 Days';
      case 'month': return 'This Month';
      case 'all': return 'All Time';
      case 'today':
      default: return 'Today';
    }
  }

  Future<String> startServer({
    required List<InventoryRecordModel> inventory,
    required List<SaleRecordModel> sales,
    required String branch,
    int preferredPort = 8088,
    String? localIp,
  }) async {
    if (_server != null) {
      return serverUrl;
    }

    _localIp = (localIp != null && localIp.isNotEmpty && localIp != '127.0.0.1')
        ? localIp
        : await _discoverLocalIp();

    try {
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        preferredPort,
        shared: true,
      );
      _port = _server!.port;
    } catch (_) {
      // Fallback to dynamic port if preferredPort is occupied
      _server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: true,
      );
      _port = _server!.port;
    }

    _server!.listen((HttpRequest request) async {
      final uri = request.uri;
      final path = uri.path;
      final queryRange = uri.queryParameters['range'] ?? 'today';
      final rangeLabel = getRangeLabel(queryRange);
      final filteredSales = filterSalesByRange(sales, queryRange);

      final res = request.response;

      res.headers.add('Access-Control-Allow-Origin', '*');
      res.headers.add('Access-Control-Allow-Methods', 'GET, OPTIONS');

      if (request.method == 'OPTIONS') {
        res.statusCode = HttpStatus.ok;
        await res.close();
        return;
      }

      if (path == '/' || path == '/index.html') {
        final html = _generateMobileLandingHtml(
          branch: branch,
          inventory: inventory,
          sales: sales,
          selectedRange: queryRange,
        );
        res.headers.contentType = ContentType.html;
        res.write(html);
      } else if (path == '/download/csv') {
        final csv = generateShelfStockCsv(items: inventory, branch: branch);
        final date = DateFormat('yyyyMMdd').format(DateTime.now());
        res.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
        res.headers.add(
          'Content-Disposition',
          'attachment; filename="OttoScents_Stock_${branch}_$date.csv"',
        );
        res.write(csv);
      } else if (path == '/download/sales-csv') {
        final csv = generateDailySalesCsv(
          sales: filteredSales,
          branch: branch,
          dateRangeLabel: rangeLabel,
        );
        final date = DateFormat('yyyyMMdd').format(DateTime.now());
        res.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
        res.headers.add(
          'Content-Disposition',
          'attachment; filename="OttoScents_Sales_${branch}_${queryRange}_$date.csv"',
        );
        res.write(csv);
      } else if (path == '/download/pdf') {
        final pdfBytes = await generateReportPdfBytes(
          inventory: inventory,
          sales: filteredSales,
          branch: branch,
          dateRangeLabel: rangeLabel,
        );
        final date = DateFormat('yyyyMMdd').format(DateTime.now());
        res.headers.contentType = ContentType('application', 'pdf');
        res.headers.add(
          'Content-Disposition',
          'attachment; filename="OttoScents_Report_${branch}_${queryRange}_$date.pdf"',
        );
        res.add(pdfBytes);
      } else {
        res.statusCode = HttpStatus.notFound;
        res.write('Not found');
      }

      await res.close();
    });

    return serverUrl;
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ---------------------------------------------------------------------------
  // 5. IP DISCOVERY & RESILIENCE
  // ---------------------------------------------------------------------------
  Future<String> _discoverLocalIp() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      // Filter out virtual, container, and bridge interfaces
      bool isVirtual(String name) {
        final lower = name.toLowerCase();
        return lower.startsWith('docker') ||
            lower.startsWith('virbr') ||
            lower.startsWith('veth') ||
            lower.startsWith('br-') ||
            lower.startsWith('dummy') ||
            lower == 'lo';
      }

      final validIfaces = ifaces.where((iface) => !isVirtual(iface.name)).toList();

      // 1. Prioritize Wi-Fi interfaces (wl*, wlan*, wifi*)
      final wifiRegex = RegExp(r'^(wl|wlan|wifi)', caseSensitive: false);
      for (final iface in validIfaces) {
        if (wifiRegex.hasMatch(iface.name)) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // 2. Prioritize Ethernet interfaces (eth*, en*)
      final ethRegex = RegExp(r'^(eth|en)', caseSensitive: false);
      for (final iface in validIfaces) {
        if (ethRegex.hasMatch(iface.name)) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
              return addr.address;
            }
          }
        }
      }

      // 3. Any remaining non-virtual IPv4
      for (final iface in validIfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.type == InternetAddressType.IPv4) {
            return addr.address;
          }
        }
      }
    } catch (_) {}

    final netIp = NetworkService.instance.status.ipAddress;
    if (netIp != null && netIp.isNotEmpty && netIp != '127.0.0.1') {
      return netIp;
    }

    return '127.0.0.1';
  }

  /// Re-detects the local IP address or applies a preferred IP, updating active state.
  Future<String> updateOrRedetectIp([String? preferredIp]) async {
    if (preferredIp != null && preferredIp.isNotEmpty && preferredIp != '127.0.0.1') {
      _localIp = preferredIp;
      return _localIp!;
    }

    final detected = await _discoverLocalIp();
    _localIp = detected;
    return detected;
  }

  // ---------------------------------------------------------------------------
  // 6. MODERN RESPONSIVE MOBILE LANDING PAGE (HTML5 GLASSMORPHIC)
  // ---------------------------------------------------------------------------
  String _generateMobileLandingHtml({
    required String branch,
    required List<InventoryRecordModel> inventory,
    required List<SaleRecordModel> sales,
    String selectedRange = 'today',
  }) {
    final now = DateTime.now();
    final activeSales = filterSalesByRange(sales, selectedRange);
    final rangeTitle = getRangeLabel(selectedRange);

    final revenue = activeSales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final soldUnits = activeSales.fold<int>(0, (sum, s) => sum + s.quantitySold);
    final onShelf = inventory.where((i) => !i.isSeasonalOff).fold<int>(0, (sum, i) => sum + i.detected);
    final lowStock = inventory.where((i) => !i.isSeasonalOff && (i.detected <= 2)).length;

    // Top 3 Sellers in this range
    final Map<String, ({String name, int units, double rev})> productAggregates = {};
    for (final s in activeSales) {
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
    final topSellers = productAggregates.values.toList()
      ..sort((a, b) => b.units.compareTo(a.units));

    final topSellersHtml = topSellers.isEmpty
        ? '<div style="color:#64748b; font-size:12px; text-align:center; padding:8px;">No sales recorded for this period.</div>'
        : topSellers.take(3).map((item) => '''
          <div style="display:flex; justify-content:space-between; align-items:center; padding:8px 0; border-bottom:1px solid rgba(255,255,255,0.05);">
            <div>
              <span style="color:#f8fafc; font-weight:600; font-size:13px;">${item.name}</span>
              <div style="color:#94a3b8; font-size:11px;">${item.units} bottles sold</div>
            </div>
            <span style="color:#d97706; font-weight:700; font-size:13px;">₱${NumberFormat('#,##0.00').format(item.rev)}</span>
          </div>
        ''').join('');

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <title>OttoScents Reports • $branch</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      background: radial-gradient(circle at top, #1e293b 0%, #0f172a 100%);
      color: #f8fafc;
      min-height: 100vh;
      padding: 16px;
      display: flex;
      flex-direction: column;
      align-items: center;
    }
    .wrapper { width: 100%; max-width: 480px; }
    .card {
      background: rgba(30, 41, 59, 0.7);
      backdrop-filter: blur(12px);
      -webkit-backdrop-filter: blur(12px);
      border-radius: 20px;
      padding: 20px;
      box-shadow: 0 16px 36px rgba(0, 0, 0, 0.4);
      border: 1px solid rgba(255, 255, 255, 0.08);
      margin-bottom: 16px;
    }
    .header { text-align: center; margin-bottom: 18px; }
    .badge {
      display: inline-block;
      background: rgba(217, 119, 6, 0.2);
      color: #fbbf24;
      font-size: 10px;
      font-weight: 800;
      letter-spacing: 0.8px;
      padding: 4px 10px;
      border-radius: 20px;
      text-transform: uppercase;
      border: 1px solid rgba(217, 119, 6, 0.4);
      margin-bottom: 8px;
    }
    .logo { color: #f59e0b; font-size: 22px; font-weight: 900; letter-spacing: -0.5px; }
    .sub { color: #94a3b8; font-size: 12px; margin-top: 4px; }
    
    /* Date Filter Chips */
    .filter-bar {
      display: flex;
      gap: 6px;
      overflow-x: auto;
      padding-bottom: 8px;
      margin-bottom: 16px;
    }
    .chip {
      text-decoration: none;
      padding: 7px 12px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 700;
      white-space: nowrap;
      transition: all 0.2s ease;
      color: #94a3b8;
      background: #0f172a;
      border: 1px solid #334155;
    }
    .chip.active {
      background: #d97706;
      color: #ffffff;
      border-color: #d97706;
      box-shadow: 0 4px 12px rgba(217, 119, 6, 0.35);
    }

    .kpi-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 16px; }
    .kpi {
      background: rgba(15, 23, 42, 0.6);
      padding: 12px;
      border-radius: 14px;
      border: 1px solid rgba(255, 255, 255, 0.05);
    }
    .kpi-title { font-size: 10px; text-transform: uppercase; color: #94a3b8; font-weight: 700; }
    .kpi-val { font-size: 18px; font-weight: 800; color: #38bdf8; margin-top: 4px; }
    .kpi-val.rev { color: #4ade80; }
    .kpi-val.alert { color: #fbbf24; }
    
    /* Top Sellers Card */
    .section-title {
      font-size: 12px;
      font-weight: 800;
      color: #fbbf24;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      margin-bottom: 8px;
    }

    /* Action Buttons */
    .btn {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      width: 100%;
      text-align: center;
      padding: 14px;
      border-radius: 14px;
      font-size: 14px;
      font-weight: 700;
      text-decoration: none;
      margin-bottom: 10px;
      transition: transform 0.15s ease, opacity 0.15s ease;
      border: none;
      cursor: pointer;
    }
    .btn:active { transform: scale(0.98); }
    .btn-pdf {
      background: linear-gradient(135deg, #d97706 0%, #b45309 100%);
      color: #ffffff;
      box-shadow: 0 6px 18px rgba(217, 119, 6, 0.35);
    }
    .btn-csv {
      background: linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%);
      color: #ffffff;
      box-shadow: 0 6px 18px rgba(37, 99, 235, 0.35);
    }
    .btn-sales {
      background: linear-gradient(135deg, #059669 0%, #047857 100%);
      color: #ffffff;
      box-shadow: 0 6px 18px rgba(5, 150, 105, 0.35);
    }
    .footer { text-align: center; font-size: 11px; color: #64748b; margin-top: 16px; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="card">
      <div class="header">
        <div class="badge">Wireless Fast Transfer</div>
        <div class="logo">OTTO SCENTS</div>
        <div class="sub">Smart Shelf Kiosk • Branch: <strong>$branch</strong></div>
        <div class="sub">${DateFormat('MMMM dd, yyyy • hh:mm a').format(now)}</div>
      </div>

      <!-- Quick Range Selector -->
      <div class="filter-bar">
        <a href="/?range=today" class="chip ${selectedRange == 'today' ? 'active' : ''}">Today</a>
        <a href="/?range=yesterday" class="chip ${selectedRange == 'yesterday' ? 'active' : ''}">Yesterday</a>
        <a href="/?range=7days" class="chip ${selectedRange == '7days' ? 'active' : ''}">Last 7 Days</a>
        <a href="/?range=month" class="chip ${selectedRange == 'month' ? 'active' : ''}">This Month</a>
      </div>

      <!-- Live KPI Grid -->
      <div class="kpi-grid">
        <div class="kpi">
          <div class="kpi-title">$rangeTitle Revenue</div>
          <div class="kpi-val rev">₱${NumberFormat('#,##0.00').format(revenue)}</div>
        </div>
        <div class="kpi">
          <div class="kpi-title">Bottles Sold</div>
          <div class="kpi-val">$soldUnits Sold</div>
        </div>
        <div class="kpi">
          <div class="kpi-title">Shelf Bottles</div>
          <div class="kpi-val">$onShelf / 300</div>
        </div>
        <div class="kpi">
          <div class="kpi-title">Low Stock</div>
          <div class="kpi-val alert">$lowStock Alerts</div>
        </div>
      </div>

      <!-- Top Performing Fragrances -->
      <div style="background: rgba(15, 23, 42, 0.4); border-radius: 14px; padding: 12px; margin-bottom: 16px; border: 1px solid rgba(255, 255, 255, 0.05);">
        <div class="section-title">🏆 Top Sellers ($rangeTitle)</div>
        $topSellersHtml
      </div>

      <!-- Instant 1-Tap Wireless Downloads -->
      <a href="/download/pdf?range=$selectedRange" class="btn btn-pdf">
        📄 Download Branded PDF Report
      </a>
      <a href="/download/sales-csv?range=$selectedRange" class="btn btn-sales">
        💳 Download ${selectedRange == 'today' ? "Today's" : rangeTitle} Sales CSV
      </a>
      <a href="/download/csv" class="btn btn-csv">
        📊 Download Shelf Stock CSV (8 Cols)
      </a>

      <div class="footer">
        ⚡ Transferred wirelessly over local store Wi-Fi.<br>
        Direct browser download • No third-party apps required.
      </div>
    </div>
  </div>
</body>
</html>
''';
  }

  String _escapeCsv(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      final escaped = str.replaceAll('"', '""');
      return '"$escaped"';
    }
    return '"$str"';
  }
}
