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
  }) async {
    final pdf = pw.Document();

    final now = DateTime.now();
    final todaySales = sales.where((s) =>
        s.soldAt.year == now.year &&
        s.soldAt.month == now.month &&
        s.soldAt.day == now.day).toList();

    final double todayRev = todaySales.fold(0.0, (sum, s) => sum + s.totalAmount);
    final int todayUnits = todaySales.fold(0, (sum, s) => sum + s.quantitySold);
    final int onShelf = inventory.where((i) => !i.isSeasonalOff).fold(0, (sum, i) => sum + i.detected);
    final int lowStockCount = inventory.where((i) => !i.isSeasonalOff && (i.detected <= 2)).length;

    // OttoScents Brand Palette
    const goldColor = PdfColor.fromInt(0xFFD97706);
    const darkBg = PdfColor.fromInt(0xFF0F172A);
    const cardBg = PdfColor.fromInt(0xFF1E293B);
    const borderColor = PdfColor.fromInt(0xFF334155);
    const textMuted = PdfColor.fromInt(0xFF94A3B8);
    const greenText = PdfColor.fromInt(0xFF22C55E);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return [
            // Header
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                color: cardBg,
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: borderColor),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'OTTO SCENTS',
                        style: pw.TextStyle(
                          color: goldColor,
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Smart Shelf Retail & Inventory Report',
                        style: const pw.TextStyle(color: PdfColors.white, fontSize: 12),
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
                        style: const pw.TextStyle(color: textMuted, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // 4 KPI Summary Cards
            pw.Row(
              children: [
                _buildPdfKpiCard(
                  title: "Today's Revenue",
                  value: 'PHP ${todayRev.toStringAsFixed(2)}',
                  accentColor: greenText,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Bottles Sold Today',
                  value: '$todayUnits Bottles',
                  accentColor: PdfColors.blue,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Bottles on Shelf',
                  value: '$onShelf / 300',
                  accentColor: goldColor,
                ),
                pw.SizedBox(width: 8),
                _buildPdfKpiCard(
                  title: 'Low Stock Alerts',
                  value: '$lowStockCount Fragrances',
                  accentColor: lowStockCount > 0 ? PdfColors.red : greenText,
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Today's Sales Section
            pw.Text(
              "Today's Sales Transactions (${todaySales.length} records)",
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: goldColor,
              ),
            ),
            pw.SizedBox(height: 8),
            if (todaySales.isEmpty)
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: darkBg,
                  borderRadius: pw.BorderRadius.circular(6),
                ),
                child: pw.Text(
                  'No transactions recorded today.',
                  style: const pw.TextStyle(color: textMuted, fontSize: 11),
                ),
              )
            else
              pw.Table(
                border: pw.TableBorder.all(color: borderColor, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: darkBg),
                    children: [
                      _pdfTh('Time'),
                      _pdfTh('Fragrance'),
                      _pdfTh('Code'),
                      _pdfTh('Size'),
                      _pdfTh('Qty'),
                      _pdfTh('Price'),
                      _pdfTh('Total'),
                    ],
                  ),
                  for (final s in todaySales.take(20))
                    pw.TableRow(
                      children: [
                        _pdfTd(DateFormat('HH:mm:ss').format(s.soldAt)),
                        _pdfTd(s.productName),
                        _pdfTd(s.perfumeCode),
                        _pdfTd(s.bottleSize),
                        _pdfTd('${s.quantitySold}'),
                        _pdfTd('PHP ${s.unitPrice.toStringAsFixed(2)}'),
                        _pdfTd('PHP ${s.totalAmount.toStringAsFixed(2)}'),
                      ],
                    ),
                ],
              ),
            pw.SizedBox(height: 20),

            // Shelf Stock Summary Section
            pw.Text(
              'Shelf Stock Inventory (${inventory.length} slots)',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: goldColor,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: borderColor, width: 0.5),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: darkBg),
                  children: [
                    _pdfTh('Slot'),
                    _pdfTh('Fragrance Name'),
                    _pdfTh('Shelf / Layer'),
                    _pdfTh('Stock (Cap 5)'),
                    _pdfTh('Status'),
                    _pdfTh('Price'),
                    _pdfTh('Total Value'),
                  ],
                ),
                for (final item in inventory.where((i) => i.status != 'deleted'))
                  pw.TableRow(
                    children: [
                      _pdfTd(item.perfumeCode),
                      _pdfTd(item.name),
                      _pdfTd(item.shelf),
                      _pdfTd(item.isSeasonalOff ? '0 (Off)' : '${item.detected} / 5'),
                      _pdfTd(
                        item.isSeasonalOff
                            ? 'Seasonal Off'
                            : (item.detected == 0
                                ? 'Out of Stock'
                                : (item.detected <= 2 ? 'Low Stock' : 'Optimal')),
                      ),
                      _pdfTd('PHP ${(item.price > 0 ? item.price : 260.0).toStringAsFixed(2)}'),
                      _pdfTd(
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
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: accentColor,
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _pdfTh(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _pdfTd(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text,
        style: const pw.TextStyle(
          color: PdfColor.fromInt(0xFFCBD5E1),
          fontSize: 8,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. LIGHTWEIGHT LOCAL HTTP SERVER (dart:io HttpServer)
  // ---------------------------------------------------------------------------
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
      final path = request.uri.path;
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
        final csv = generateDailySalesCsv(sales: sales, branch: branch);
        final date = DateFormat('yyyyMMdd').format(DateTime.now());
        res.headers.contentType = ContentType('text', 'csv', charset: 'utf-8');
        res.headers.add(
          'Content-Disposition',
          'attachment; filename="OttoScents_Sales_${branch}_$date.csv"',
        );
        res.write(csv);
      } else if (path == '/download/pdf') {
        final pdfBytes = await generateReportPdfBytes(
          inventory: inventory,
          sales: sales,
          branch: branch,
        );
        final date = DateFormat('yyyyMMdd').format(DateTime.now());
        res.headers.contentType = ContentType('application', 'pdf');
        res.headers.add(
          'Content-Disposition',
          'attachment; filename="OttoScents_Report_${branch}_$date.pdf"',
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
  // 6. RESPONSIVE MOBILE LANDING PAGE (HTML5)
  // ---------------------------------------------------------------------------
  String _generateMobileLandingHtml({
    required String branch,
    required List<InventoryRecordModel> inventory,
    required List<SaleRecordModel> sales,
  }) {
    final now = DateTime.now();
    final todaySales = sales.where((s) =>
        s.soldAt.year == now.year &&
        s.soldAt.month == now.month &&
        s.soldAt.day == now.day).toList();

    final revenue = todaySales.fold<double>(0, (sum, s) => sum + s.totalAmount);
    final soldUnits = todaySales.fold<int>(0, (sum, s) => sum + s.quantitySold);
    final onShelf = inventory.where((i) => !i.isSeasonalOff).fold<int>(0, (sum, i) => sum + i.detected);
    final lowStock = inventory.where((i) => !i.isSeasonalOff && (i.detected <= 2)).length;

    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OttoScents Reports - $branch</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; background: #0f172a; color: #f8fafc; margin: 0; padding: 20px; }
    .card { background: #1e293b; border-radius: 16px; padding: 24px; max-width: 500px; margin: 0 auto; box-shadow: 0 10px 25px rgba(0,0,0,0.5); border: 1px solid #334155; }
    .header { text-align: center; margin-bottom: 24px; }
    .logo { color: #d97706; font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
    .sub { color: #94a3b8; font-size: 14px; margin-top: 4px; }
    .kpi-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 24px; }
    .kpi { background: #0f172a; padding: 14px; border-radius: 12px; border: 1px solid #334155; }
    .kpi-title { font-size: 11px; text-transform: uppercase; color: #94a3b8; font-weight: 700; }
    .kpi-val { font-size: 20px; font-weight: 800; color: #38bdf8; margin-top: 4px; }
    .kpi-val.rev { color: #4ade80; }
    .kpi-val.alert { color: #fbbf24; }
    .btn { display: block; width: 100%; box-sizing: border-box; text-align: center; padding: 16px; border-radius: 12px; font-size: 16px; font-weight: 700; text-decoration: none; margin-bottom: 12px; transition: 0.2s; }
    .btn-pdf { background: #d97706; color: #ffffff; }
    .btn-csv { background: #2563eb; color: #ffffff; }
    .btn-sales { background: #10b981; color: #ffffff; }
    .footer { text-align: center; font-size: 11px; color: #64748b; margin-top: 24px; }
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <div class="logo">OTTO SCENTS</div>
      <div class="sub">Smart Shelf Kiosk • Branch: $branch</div>
      <div class="sub">${DateFormat('MMMM dd, yyyy • hh:mm a').format(now)}</div>
    </div>
    <div class="kpi-grid">
      <div class="kpi"><div class="kpi-title">Today's Revenue</div><div class="kpi-val rev">₱${NumberFormat('#,##0.00').format(revenue)}</div></div>
      <div class="kpi"><div class="kpi-title">Bottles Sold</div><div class="kpi-val">$soldUnits Sold</div></div>
      <div class="kpi"><div class="kpi-title">Shelf Bottles</div><div class="kpi-val">$onShelf / 300</div></div>
      <div class="kpi"><div class="kpi-title">Low Stock</div><div class="kpi-val alert">$lowStock Fragrances</div></div>
    </div>
    <a href="/download/pdf" class="btn btn-pdf">📄 Download Branded PDF Report</a>
    <a href="/download/csv" class="btn btn-csv">📊 Download Shelf Stock CSV (8 Cols)</a>
    <a href="/download/sales-csv" class="btn btn-sales">💳 Download Today's Sales CSV</a>
    <div class="footer">Transferred wirelessly over local store Wi-Fi • No apps required</div>
  </div>
</body>
</html>
''';
  }

  String _escapeCsv(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') || str.contains('"') || str.contains('\n') || str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return '"$str"';
  }
}
