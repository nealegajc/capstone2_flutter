import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/data/services/report_export_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/sales_provider.dart';
import 'package:smart_shelf_linux/ui/screens/reports/report_viewer_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/reports/reports_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Milestone 4 (R4): ReportExportService Tests', () {
    final sampleInventory = [
      InventoryRecordModel(
        id: 'rec_1',
        perfumeCode: 'AA1',
        name: 'Sauvage Dior',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 4,
        status: 'normal',
        price: 260.0,
        lastUpdated: DateTime(2026, 11, 1, 10, 30),
      ),
      InventoryRecordModel(
        id: 'rec_2',
        perfumeCode: 'AA2',
        name: 'Bleu de Chanel',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 2,
        status: 'low',
        price: 180.0,
        lastUpdated: DateTime(2026, 11, 1, 10, 35),
      ),
      InventoryRecordModel(
        id: 'rec_3',
        perfumeCode: 'AB1',
        name: 'Acqua Di Gio',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 0,
        status: 'out_of_stock',
        price: 260.0,
        lastUpdated: DateTime(2026, 11, 1, 10, 40),
      ),
      InventoryRecordModel(
        id: 'rec_4',
        perfumeCode: 'AB2',
        name: 'Vanilla Woods',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 5,
        status: 'seasonal_off',
        price: 180.0,
        lastUpdated: DateTime(2026, 11, 1, 10, 45),
      ),
    ];

    final sampleSales = [
      SaleRecordModel(
        id: 'sale_101',
        perfumeCode: 'AA1',
        productName: 'Sauvage Dior',
        bottleSize: '100ml',
        quantitySold: 2,
        unitPrice: 260.0,
        totalAmount: 520.0,
        branch: 'San Pablo',
        soldBy: 'staff1',
        soldAt: DateTime.now(),
        syncStatus: 'synced',
      ),
      SaleRecordModel(
        id: 'sale_102',
        perfumeCode: 'AA2',
        productName: 'Bleu de Chanel',
        bottleSize: '50ml',
        quantitySold: 1,
        unitPrice: 180.0,
        totalAmount: 180.0,
        branch: 'San Pablo',
        soldBy: 'staff2',
        soldAt: DateTime.now(),
        syncStatus: 'synced',
      ),
    ];

    test('generateShelfStockCsv produces exact 8 friendly headers and summary totals', () {
      final csv = ReportExportService.instance.generateShelfStockCsv(
        items: sampleInventory,
        branch: 'San Pablo',
      );

      // Verify exact 8 columns in header
      expect(
        csv,
        contains(
          'Fragrance Name,Shelf / Tray Location,In Stock (Bottles),Max Capacity,Stock Status,Unit Price (PHP),Total Shelf Value (PHP),Last Checked',
        ),
      );

      // Verify row details
      expect(csv, contains('Sauvage Dior'));
      expect(csv, contains('Optimal (4/5)'));
      expect(csv, contains('Low Stock (2 Left)'));
      expect(csv, contains('Out of Stock (Refill Needed)'));
      expect(csv, contains('Seasonal Off (Paused)'));

      // In stock: 4 + 2 + 0 + (seasonal is 0) = 6 bottles
      // Valuation: (4 * 260) + (2 * 180) + 0 + 0 = 1040 + 360 = 1400.00
      expect(csv, contains('TOTALS,,6,300,,,1400.00,'));
    });

    test('generateDailySalesCsv produces required headers and summary totals', () {
      final csv = ReportExportService.instance.generateDailySalesCsv(
        sales: sampleSales,
        branch: 'San Pablo',
      );

      expect(
        csv,
        contains(
          'Transaction ID,Time,Fragrance Name,Perfume Code,Bottle Size,Quantity Sold,Unit Price (PHP),Total Amount (PHP),Cashier,Sync Status',
        ),
      );

      expect(csv, contains('sale_101'));
      expect(csv, contains('Sauvage Dior'));
      expect(csv, contains('520.00'));
      expect(csv, contains('SUMMARY TOTALS,,,,,3,,700.00,,'));
    });

    test('generateReportPdfBytes produces non-empty branded PDF bytes', () async {
      final bytes = await ReportExportService.instance.generateReportPdfBytes(
        inventory: sampleInventory,
        sales: sampleSales,
        branch: 'San Pablo',
      );

      expect(bytes.isNotEmpty, isTrue);
      final headerStr = String.fromCharCodes(bytes.take(8));
      expect(headerStr, startsWith('%PDF-'));
    });

    test('Local HttpServer lifecycle: startServer, endpoints, and stopServer', () async {
      final url = await ReportExportService.instance.startServer(
        inventory: sampleInventory,
        sales: sampleSales,
        branch: 'San Pablo',
        preferredPort: 9088,
      );

      expect(ReportExportService.instance.isServerRunning, isTrue);
      expect(url, startsWith('http://'));

      final port = ReportExportService.instance.port;

      Future<({int statusCode, String body, Map<String, String> headers})> request(String path) async {
        final socket = await Socket.connect('127.0.0.1', port);
        socket.write('GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n');
        final data = await socket.fold<List<int>>([], (acc, chunk) => acc..addAll(chunk));
        await socket.close();
        final raw = utf8.decode(data, allowMalformed: true);

        final parts = raw.split('\r\n\r\n');
        final headerLines = parts.first.split('\r\n');
        final statusLine = headerLines.first;
        final statusCode = int.tryParse(statusLine.split(' ')[1]) ?? 0;

        final headers = <String, String>{};
        for (final line in headerLines.skip(1)) {
          final idx = line.indexOf(':');
          if (idx != -1) {
            headers[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 1).trim();
          }
        }
        final body = parts.length > 1 ? parts.sublist(1).join('\r\n\r\n') : '';
        return (statusCode: statusCode, body: body, headers: headers);
      }

      // 1. GET / -> Responsive HTML Landing Page
      final homeRes = await request('/');
      expect(homeRes.statusCode, HttpStatus.ok);
      expect(homeRes.headers['content-type'], contains('text/html'));
      expect(homeRes.body, contains('OTTO SCENTS'));
      expect(homeRes.body, contains('Download Branded PDF Report'));
      expect(homeRes.body, contains('Download Shelf Stock CSV (8 Cols)'));
      expect(homeRes.body, contains('Download Today\'s Sales CSV'));

      // 2. GET /download/csv -> 8-Column Shelf Stock CSV
      final csvRes = await request('/download/csv');
      expect(csvRes.statusCode, HttpStatus.ok);
      expect(csvRes.headers['content-type'], contains('text/csv'));
      expect(csvRes.headers['content-disposition'], contains('OttoScents_Stock_San Pablo_'));
      expect(csvRes.body, contains('Fragrance Name,Shelf / Tray Location'));

      // 3. GET /download/sales-csv -> Daily Sales CSV
      final salesRes = await request('/download/sales-csv');
      expect(salesRes.statusCode, HttpStatus.ok);
      expect(salesRes.headers['content-type'], contains('text/csv'));
      expect(salesRes.headers['content-disposition'], contains('OttoScents_Sales_San Pablo_'));
      expect(salesRes.body, contains('Transaction ID,Time,Fragrance Name'));

      // 4. GET /download/pdf -> Branded PDF Bytes
      final pdfRes = await request('/download/pdf');
      expect(pdfRes.statusCode, HttpStatus.ok);
      expect(pdfRes.headers['content-type'], contains('application/pdf'));
      expect(pdfRes.headers['content-disposition'], contains('OttoScents_Report_San Pablo_'));
      expect(pdfRes.body.isNotEmpty, isTrue);

      // 5. GET /unknown -> 404
      final notFoundRes = await request('/unknown-route');
      expect(notFoundRes.statusCode, HttpStatus.notFound);

      // 6. Stop Server
      await ReportExportService.instance.stopServer();
      expect(ReportExportService.instance.isServerRunning, isFalse);
    });
  });

  group('Milestone 3 (R3): ReportsScreen Redesign Widget Tests', () {
    setUp(() async {
      await SqliteService.instance.initDatabase(inMemory: true);
    });

    testWidgets('ReportsScreen displays 4-card Daily Retail KPI grid, Record New Sale, and View & Share Reports', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 280,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 3,
        outOfStockCount: 1,
        restockNeededCount: 4,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final todaySales = [
        SaleRecordModel(
          id: 's1',
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantitySold: 4,
          unitPrice: 260.0,
          totalAmount: 1040.0,
          branch: testBranch,
          soldBy: 'cashier1',
          soldAt: DateTime.now(),
        ),
        SaleRecordModel(
          id: 's2',
          perfumeCode: 'BB2',
          productName: 'Vanilla Woods',
          bottleSize: '50ml',
          quantitySold: 2,
          unitPrice: 180.0,
          totalAmount: 360.0,
          branch: testBranch,
          soldBy: 'cashier2',
          soldAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            salesRecordsProvider(testBranch).overrideWith((ref) => Future.value(todaySales)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Header title and dynamic branch
      expect(find.text('Store Sales & Reports'), findsOneWidget);
      expect(find.textContaining('Branch: San Pablo'), findsOneWidget);

      // 2. Verify Prominent Action Button: "Record New Sale"
      expect(find.text('Record New Sale'), findsOneWidget);

      // 3. Verify 4-Card Daily Retail KPI Grid
      expect(find.text("TODAY'S REVENUE"), findsOneWidget);
      expect(find.text('₱1,400.00'), findsOneWidget);

      expect(find.text('BOTTLES SOLD TODAY'), findsOneWidget);
      expect(find.text('6 Bottles'), findsOneWidget);

      expect(find.text('BEST-SELLING FRAGRANCE'), findsOneWidget);
      expect(find.text('Sauvage Dior'), findsWidgets);

      expect(find.text('LOW STOCK ALERTS'), findsOneWidget);
      expect(find.text('4 Items Low'), findsOneWidget);

      // 4. Verify Prominent Action Banner: "View & Share Reports"
      expect(find.text('In-App Report Viewer & Wireless Wi-Fi Transfer'), findsOneWidget);
      expect(find.text('View & Share Reports'), findsOneWidget);

      // 5. Verify Recent Sales Activity List
      expect(find.text("Today's Sales Register Feed"), findsOneWidget);
      expect(find.textContaining('Sauvage Dior'), findsWidgets);
      expect(find.textContaining('Vanilla Woods'), findsWidgets);
    });

    testWidgets('ReportsScreen renders graceful empty state when no sales exist today', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 300,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 0,
        outOfStockCount: 0,
        restockNeededCount: 0,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            salesRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('₱0.00'), findsOneWidget);
      expect(find.text('0 Bottles'), findsOneWidget);
      expect(find.text('None yet'), findsOneWidget);
      expect(find.text('No sales recorded today'), findsOneWidget);
      expect(find.text('Optimal (0)'), findsOneWidget);
      expect(find.text('No transactions recorded today.'), findsOneWidget);
    });

    testWidgets('Tapping Record New Sale opens RecordSaleDialog and View & Share Reports opens ReportViewerDialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 290,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 0,
        restockNeededCount: 2,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            salesRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap "Record New Sale"
      await tester.tap(find.text('Record New Sale'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(Dialog), findsOneWidget);

      // Close dialog
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();

      // Tap "View & Share Reports"
      await tester.tap(find.text('View & Share Reports'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ReportViewerDialog), findsOneWidget);
    });
  });

  group('Milestone 4 (R4): ReportViewerDialog Widget Tests', () {
    setUp(() async {
      await SqliteService.instance.initDatabase(inMemory: true);
    });

    testWidgets('ReportViewerDialog renders 3 tabs, search field, filter chips, and Wi-Fi QR Share panel', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      final inventory = [
        InventoryRecordModel(
          id: 'item_1',
          perfumeCode: 'AA1',
          name: 'Sauvage Dior',
          category: 'Men',
          branch: testBranch,
          shelf: 'Area A',
          recorded: 5,
          detected: 5,
          status: 'normal',
          price: 260.0,
        ),
        InventoryRecordModel(
          id: 'item_2',
          perfumeCode: 'AB1',
          name: 'Bleu de Chanel',
          category: 'Men',
          branch: testBranch,
          shelf: 'Area A',
          recorded: 5,
          detected: 1,
          status: 'low',
          price: 260.0,
        ),
      ];

      final sales = [
        SaleRecordModel(
          id: 's_v1',
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantitySold: 1,
          unitPrice: 260.0,
          totalAmount: 260.0,
          branch: testBranch,
          soldBy: 'staff',
          soldAt: DateTime.now(),
        ),
      ];

      final List<InventoryEventModel> events = [
        InventoryEventModel(
          id: 'ev_1',
          eventType: 'RESTOCKED',
          productName: 'Sauvage Dior',
          perfumeCode: 'AA1',
          shelfArea: 'Area A',
          branch: testBranch,
          quantity: 5,
          timestamp: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value(inventory)),
            salesRecordsProvider(testBranch).overrideWith((ref) => Future.value(sales)),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value(events)),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(
                isOnline: true,
                currentSsid: 'OttoScents_Store_5G',
                ipAddress: '192.168.1.16',
                connectionType: 'WiFi',
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ReportViewerDialog(branch: testBranch),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Verify Dialog Header
      expect(find.text('OttoScents Report Viewer & Wireless Transfer'), findsOneWidget);

      // 2. Verify Tab headers
      expect(find.text('Shelf Stock (60 Slots)'), findsOneWidget);
      expect(find.text("Today's Sales Log"), findsOneWidget);
      expect(find.text('Restock & Movement Audit'), findsOneWidget);

      // 3. Verify Filter Chips
      expect(find.text('All (60)'), findsOneWidget);
      expect(find.text('Low Stock (≤2)'), findsOneWidget);
      expect(find.text('Layer A'), findsOneWidget);

      // 4. Verify Table content
      expect(find.text('Sauvage Dior'), findsOneWidget);
      expect(find.text('Bleu de Chanel'), findsOneWidget);
      expect(find.text('Optimal'), findsOneWidget);
      expect(find.text('Low (1)'), findsOneWidget);

      // 5. Verify Right-hand Wi-Fi QR Code Share Panel
      expect(find.textContaining('Connected: OttoScents_Store_5G'), findsOneWidget);
      expect(find.text('Mobile 1-Tap Transfer'), findsOneWidget);
      expect(find.text('Save CSV to Kiosk Storage'), findsOneWidget);

      // 6. Test Real-time Search Field
      await tester.enterText(find.byType(TextField), 'Bleu');
      await tester.pump();
      expect(find.text('Bleu de Chanel'), findsOneWidget);
      expect(find.text('Sauvage Dior'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.text('Sauvage Dior'), findsOneWidget);

      // 7. Test Tab switching to "Today's Sales Log"
      await tester.tap(find.text("Today's Sales Log"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('TOTAL TRANSACTIONS: 1'), findsOneWidget);

      // 8. Test Tab switching to "Restock & Movement Audit"
      await tester.tap(find.text('Restock & Movement Audit'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('RESTOCKED • Sauvage Dior (AA1)'), findsOneWidget);
    });
  });
}
