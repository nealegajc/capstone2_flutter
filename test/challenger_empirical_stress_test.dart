import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/data/services/report_export_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/sales_provider.dart';
import 'package:smart_shelf_linux/ui/components/status_badge.dart';
import 'package:smart_shelf_linux/ui/screens/alerts/alerts_screen.dart';
import 'package:smart_shelf_linux/ui/screens/reports/report_viewer_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/reports/reports_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('CHALLENGER STRESS SUITE: Otto Scents R1-R4 Empirical Verification', () {
    const testBranch = 'San Pablo';
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
    });

    tearDown(() async {
      await sqliteService.close();
    });

    // =========================================================================
    // 1. CASHIER COLUMN ABSENCE STRESS TESTS (CSV, PDF, UI TABLE)
    // =========================================================================
    group('1. Cashier Total Absence Stress Verification', () {
      final adversarialSales = [
        SaleRecordModel(
          id: 'sale_adv_001',
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantitySold: 3,
          unitPrice: 260.0,
          totalAmount: 780.0,
          branch: testBranch,
          soldBy: 'Cashier_Alice', // Adversarial data attempting to inject 'Cashier'
          soldAt: DateTime.now(),
          syncStatus: 'synced',
        ),
        SaleRecordModel(
          id: 'sale_adv_002',
          perfumeCode: 'BB2',
          productName: 'Vanilla Woods',
          bottleSize: '50ml',
          quantitySold: 1,
          unitPrice: 180.0,
          totalAmount: 180.0,
          branch: testBranch,
          soldBy: 'Cashier_Bob',
          soldAt: DateTime.now(),
          syncStatus: 'pending',
        ),
      ];

      test('1.1 Daily Sales CSV: Cashier is completely absent from headers and column values', () {
        final csv = ReportExportService.instance.generateDailySalesCsv(
          sales: adversarialSales,
          branch: testBranch,
        );

        final lines = csv.trim().split('\n');
        final header = lines.first;

        // Verify CSV header columns
        expect(header.toLowerCase().contains('cashier'), isFalse,
            reason: 'CSV header must not contain Cashier');

        final expectedHeaders = [
          'Transaction ID',
          'Time',
          'Fragrance Name',
          'Perfume Code',
          'Bottle Size',
          'Quantity Sold',
          'Unit Price (PHP)',
          'Total Amount (PHP)',
          'Sync Status'
        ];
        expect(header, equals(expectedHeaders.join(',')));

        // Verify rows: none of the CSV columns should be the soldBy cashier string
        for (final rowLine in lines.skip(1)) {
          if (rowLine.startsWith('SUMMARY TOTALS') || rowLine.isEmpty) continue;
          final cols = rowLine.split(',');
          expect(cols.length, equals(9));
          expect(rowLine.contains('Cashier_Alice'), isFalse);
          expect(rowLine.contains('Cashier_Bob'), isFalse);
        }

        // Verify summary totals row
        expect(csv, contains('SUMMARY TOTALS,,,,,4,,960.00,'));
      });

      test('1.2 PDF Report Generator: Cashier is completely absent from PDF table structure', () async {
        final sampleInv = [
          InventoryRecordModel(
            id: 'inv_1',
            perfumeCode: 'AA1',
            name: 'Sauvage Dior',
            branch: testBranch,
            shelf: 'Area A',
            recorded: 5,
            detected: 4,
            price: 260.0,
          ),
        ];

        final pdfBytes = await ReportExportService.instance.generateReportPdfBytes(
          inventory: sampleInv,
          sales: adversarialSales,
          branch: testBranch,
        );

        expect(pdfBytes.isNotEmpty, isTrue);
        final pdfContent = latin1.decode(pdfBytes, allowInvalid: true);

        // Header check
        expect(pdfContent, contains('%PDF-'));
        // Cashier header or data must not be in the PDF stream
        expect(pdfContent.contains('Cashier'), isFalse,
            reason: 'PDF content stream must not contain Cashier');
      });

      testWidgets('1.3 UI Table in ReportViewerDialog: Exactly 6 columns, zero Cashier mentions', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
              liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
              salesRecordsProvider(testBranch).overrideWith((ref) => Future.value(adversarialSales)),
              stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
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

        await tester.pumpAndSettle();

        // Switch to Tab 2: Today's Sales Log
        await tester.tap(find.text("Today's Sales Log"));
        await tester.pumpAndSettle();

        // Verify Table headers
        expect(find.text('Time'), findsOneWidget);
        expect(find.text('Fragrance Name'), findsOneWidget);
        expect(find.text('Size'), findsOneWidget);
        expect(find.text('Qty'), findsOneWidget);
        expect(find.text('Unit Price'), findsOneWidget);
        expect(find.text('Total Amount'), findsOneWidget);

        // Assert 'Cashier' is absent from UI tree
        expect(find.textContaining('Cashier'), findsNothing);
        expect(find.text('Cashier_Alice'), findsNothing);
        expect(find.text('Cashier_Bob'), findsNothing);

        // Verify sales data rendering
        expect(find.textContaining('Sauvage Dior (AA1)'), findsOneWidget);
        expect(find.textContaining('Vanilla Woods (BB2)'), findsOneWidget);
        expect(find.text('TOTAL TRANSACTIONS: 2 (4 Bottles Sold)'), findsOneWidget);
        expect(find.text('TODAY\'S REVENUE: ₱960.00'), findsOneWidget);
      });
    });

    // =========================================================================
    // 2. FINANCIAL SHRINKAGE LOSS CALCULATION (UNITS * UNIT_PRICE)
    // =========================================================================
    group('2. Financial Shrinkage Loss Calculation Stress Verification', () {
      testWidgets('2.1 Tally units * unit_price for 100ml, 50ml, default SKUs and filters non-today/non-damage events', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));

        final movementLogs = [
          // Event 1: Today DAMAGE_WRITEOFF, 100ml SKU (ends with '1') -> unit price ₱260.00
          InventoryEventModel(
            id: 'ev_dmg_1',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Sauvage Dior',
            perfumeCode: 'AA1',
            shelfArea: 'Shelf A',
            branch: testBranch,
            quantity: 3, // 3 * 260 = 780.0
            timestamp: now,
          ),
          // Event 2: Today DAMAGE_WRITEOFF, 50ml SKU (ends with '2') -> unit price ₱180.00
          InventoryEventModel(
            id: 'ev_dmg_2',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Vanilla Woods',
            perfumeCode: 'BB2',
            shelfArea: 'Shelf B',
            branch: testBranch,
            quantity: 2, // 2 * 180 = 360.0
            timestamp: now,
          ),
          // Event 3: Today DAMAGE_WRITEOFF, Non-standard SKU (ends with 'X') -> default unit price ₱180.00
          InventoryEventModel(
            id: 'ev_dmg_3',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Mystery Blend',
            perfumeCode: 'ZZX',
            shelfArea: 'Shelf C',
            branch: testBranch,
            quantity: 1, // 1 * 180 = 180.0
            timestamp: now,
          ),
          // Event 4: Yesterday DAMAGE_WRITEOFF -> MUST NOT be tallied into today's metrics
          InventoryEventModel(
            id: 'ev_dmg_yesterday',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Bleu de Chanel',
            perfumeCode: 'AA2',
            shelfArea: 'Shelf A',
            branch: testBranch,
            quantity: 10, // 10 * 180 = 1800.0 (MUST BE EXCLUDED)
            timestamp: yesterday,
          ),
          // Event 5: Today RESTOCKED -> MUST NOT be counted in damage shrinkage
          InventoryEventModel(
            id: 'ev_restock_today',
            eventType: 'RESTOCKED',
            productName: 'Sauvage Dior',
            perfumeCode: 'AA1',
            shelfArea: 'Shelf A',
            branch: testBranch,
            quantity: 5,
            timestamp: now,
          ),
        ];

        // Total Expected Today:
        // Damaged units = 3 + 2 + 1 = 6 bottles
        // Damaged loss = (3 * 260) + (2 * 180) + (1 * 180) = 780 + 360 + 180 = 1,320.00 PHP

        const stats = DashboardStats(
          totalInStock: 250,
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
              stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value(movementLogs)),
            ],
            child: const MaterialApp(
              home: ReportsScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 1. Verify Card 5: Damage & Shrinkage KPI
        expect(find.text('DAMAGE & SHRINKAGE'), findsOneWidget);
        expect(find.text('-₱1,320.00'), findsOneWidget);
        expect(find.text('6 bottle(s) written off'), findsOneWidget);

        // 2. Verify recent transactions feed shows the 3 write-offs
        expect(find.textContaining('AA1 • Written Off'), findsOneWidget);
        expect(find.textContaining('BB2 • Written Off'), findsOneWidget);
        expect(find.textContaining('ZZX • Written Off'), findsOneWidget);
        expect(find.text('-₱780.00'), findsOneWidget);
        expect(find.text('-₱360.00'), findsOneWidget);
        expect(find.text('-₱180.00'), findsOneWidget);

        // Verify yesterday's 10 bottles write-off is NOT present in the feed
        expect(find.text('-₱1,800.00'), findsNothing);
      });
    });

    // =========================================================================
    // 3. CLEAN SLATE INTEGRITY & ISOLATION STRESS TESTS
    // =========================================================================
    group('3. Clean Slate Audit History Stress Verification', () {
      test('3.1 Clean Slate purges movement & restock logs while safeguarding catalog, sales, and live inventory', () async {
        final db = await sqliteService.database;

        final initialCatalogCount = (await db.query('products')).length;
        final initialSalesCount = (await db.query('sales_records')).length;

        // 1. Add extra products to verify persistence
        await db.insert('products', {
          'id': 'p_test_custom_1',
          'perfumeCode': 'ZZ1',
          'name': 'Custom Scent 1',
          'bottleSize': '100ml',
          'shelfLayer': 'Layer A',
          'category': 'Men',
        });

        // 2. Seed active inventory
        await sqliteService.upsertInventoryRecord(
          InventoryRecordModel(
            id: 'inv_rec_custom_1',
            perfumeCode: 'ZZ1',
            name: 'Custom Scent 1',
            branch: testBranch,
            shelf: 'Shelf A',
            recorded: 5,
            detected: 4,
            status: 'normal',
            lastUpdated: DateTime.now(),
          ),
        );

        // 3. Seed sales records
        await db.insert('sales_records', {
          'id': 'sale_rec_custom_1',
          'perfumeCode': 'ZZ1',
          'productName': 'Custom Scent 1',
          'bottleSize': '100ml',
          'quantitySold': 2,
          'unitPrice': 260.0,
          'totalAmount': 520.0,
          'branch': testBranch,
          'soldBy': 'staff',
          'soldAt': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        });

        // 4. Seed movement logs
        await db.insert('inventory_events', {
          'id': 'evt_1',
          'eventType': 'RESTOCKED',
          'productName': 'Custom Scent 1',
          'perfumeCode': 'ZZ1',
          'shelfArea': 'Shelf A',
          'branch': testBranch,
          'quantity': 5,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        });
        await db.insert('inventory_events', {
          'id': 'evt_2',
          'eventType': 'DAMAGE_WRITEOFF',
          'productName': 'Custom Scent 1',
          'perfumeCode': 'ZZ1',
          'shelfArea': 'Shelf A',
          'branch': testBranch,
          'quantity': 1,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        });

        // 5. Seed restock records
        await db.insert('restock_records', {
          'id': 'rst_1',
          'productName': 'Custom Scent 1',
          'perfumeCode': 'ZZ1',
          'quantity': 5,
          'fromBranch': 'Main Warehouse',
          'toBranch': testBranch,
          'requestedBy': 'Manager',
          'status': 'verified',
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Verify pre-conditions
        expect((await db.query('inventory_events', where: 'branch = ?', whereArgs: [testBranch])).isNotEmpty, isTrue);
        expect((await db.query('restock_records', where: 'toBranch = ?', whereArgs: [testBranch])).isNotEmpty, isTrue);

        // EXECUTE CLEAN SLATE
        await sqliteService.clearMovementAndRestockLogs(testBranch);

        // POST-CONDITIONS:
        // 1. Movement and restock logs purged
        final remainingEvents = await db.query('inventory_events', where: 'branch = ?', whereArgs: [testBranch]);
        final remainingRestocks = await db.query('restock_records', where: 'toBranch = ?', whereArgs: [testBranch]);
        expect(remainingEvents, isEmpty);
        expect(remainingRestocks, isEmpty);

        // 2. Master products catalog STRICTLY SAFEGUARDED
        final productsAfter = await db.query('products');
        expect(productsAfter.length, equals(initialCatalogCount + 1));
        expect(productsAfter.any((p) => p['perfumeCode'] == 'ZZ1'), isTrue);

        // 3. Sales records STRICTLY SAFEGUARDED
        final salesAfter = await db.query('sales_records');
        expect(salesAfter.length, equals(initialSalesCount + 1));
        expect(salesAfter.any((s) => s['id'] == 'sale_rec_custom_1'), isTrue);

        // 4. Live inventory counts STRICTLY SAFEGUARDED
        final inventoryAfter = await sqliteService.getInventoryRecord('ZZ1', testBranch);
        expect(inventoryAfter, isNotNull);
        expect(inventoryAfter!.recorded, equals(5));
        expect(inventoryAfter.detected, equals(4));

        // 5. Clean Slate audit trail entry logged in system_logs
        final auditLogs = await db.query(
          'system_logs',
          where: 'type = ? AND branch = ?',
          whereArgs: ['AUDIT_CLEAN_SLATE', testBranch],
        );
        expect(auditLogs.length, equals(1));
        expect(auditLogs.first['user'], equals('Manager'));
      });

      test('3.2 Cross-branch isolation: Clean slate on Branch A does NOT purge Branch B logs', () async {
        final db = await sqliteService.database;

        // Seed logs for Branch A and Branch B
        await db.insert('inventory_events', {
          'id': 'evt_branch_a',
          'eventType': 'RESTOCKED',
          'productName': 'Sauvage Dior',
          'perfumeCode': 'AA1',
          'shelfArea': 'Shelf A',
          'branch': 'Branch_A',
          'quantity': 2,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        });
        await db.insert('inventory_events', {
          'id': 'evt_branch_b',
          'eventType': 'RESTOCKED',
          'productName': 'Vanilla Woods',
          'perfumeCode': 'BB2',
          'shelfArea': 'Shelf B',
          'branch': 'Branch_B',
          'quantity': 4,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'syncStatus': 'synced',
        });

        // Clean slate on Branch_A only
        await sqliteService.clearMovementAndRestockLogs('Branch_A');

        // Branch_A logs purged
        final aEvents = await db.query('inventory_events', where: 'branch = ?', whereArgs: ['Branch_A']);
        expect(aEvents, isEmpty);

        // Branch_B logs INTACT
        final bEvents = await db.query('inventory_events', where: 'branch = ?', whereArgs: ['Branch_B']);
        expect(bEvents.length, equals(1));
        expect(bEvents.first['perfumeCode'], equals('BB2'));
      });
    });

    // =========================================================================
    // 4. "MANUALLY CHECK RESTOCK" LEDGER SYNC & MULTI-ALERT DISMISSAL
    // =========================================================================
    group('4. Manually Check Restock Synchronization Stress Verification', () {
      test('4.1 confirmSurplusRestock synchronizes recorded to detected, logs RESTOCKED, and auto-dismisses discrepancy + stock alerts', () async {
        // Setup: SKU 'CC1' with recorded=2, detected=5 (surplus of 3 bottles)
        final existing = await sqliteService.getInventoryRecord('CC1', testBranch);
        final recId = existing?.id ?? 'inv_cc1';
        await sqliteService.upsertInventoryRecord(
          InventoryRecordModel(
            id: recId,
            perfumeCode: 'CC1',
            name: 'Acqua Di Gio',
            branch: testBranch,
            shelf: 'Shelf C',
            recorded: 2,
            detected: 5,
            status: 'needs_review',
            lastUpdated: DateTime.now(),
          ),
        );

        // Setup: Multiple active alerts for CC1 (discrepancy, low_stock, out_of_stock) + 1 alert for another SKU
        await sqliteService.saveAlert(AlertModel(
          id: 'alt_cc1_disc',
          title: 'Stock Discrepancy CC1',
          desc: 'Camera detected 5 bottles, but ledger recorded 2',
          branch: testBranch,
          type: 'discrepancy',
          perfumeCode: 'CC1',
          isRead: false,
          createdAt: DateTime.now(),
        ));
        await sqliteService.saveAlert(AlertModel(
          id: 'alt_cc1_low',
          title: 'Low Stock CC1',
          desc: 'Stock level was low',
          branch: testBranch,
          type: 'low_stock',
          perfumeCode: 'CC1',
          isRead: false,
          createdAt: DateTime.now(),
        ));
        await sqliteService.saveAlert(AlertModel(
          id: 'alt_other_sku',
          title: 'Stock Discrepancy DD2',
          desc: 'Other SKU alert',
          branch: testBranch,
          type: 'discrepancy',
          perfumeCode: 'DD2',
          isRead: false,
          createdAt: DateTime.now(),
        ));

        // EXECUTE: Manually Check Restock for CC1
        await sqliteService.confirmSurplusRestock(
          perfumeCode: 'CC1',
          branch: testBranch,
          detectedCount: 5,
        );

        // 1. Verify ledger synchronized
        final invRecord = await sqliteService.getInventoryRecord('CC1', testBranch);
        expect(invRecord, isNotNull);
        expect(invRecord!.recorded, equals(5), reason: 'Recorded ledger must match detected 5');
        expect(invRecord.detected, equals(5));
        expect(invRecord.status, equals('normal'));

        // 2. Verify RESTOCKED movement event logged with surplus delta (5 - 2 = 3)
        final events = await sqliteService.getInventoryEvents(testBranch);
        final restockEvent = events.firstWhere((e) => e.perfumeCode == 'CC1' && e.eventType == 'RESTOCKED');
        expect(restockEvent.quantity, equals(3), reason: 'Restock event quantity should be delta 3');

        // 3. Verify discrepancy and low_stock alerts for CC1 are dismissed (isRead = 1)
        final unreadAlerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
        expect(unreadAlerts.any((a) => a.id == 'alt_cc1_disc'), isFalse);
        expect(unreadAlerts.any((a) => a.id == 'alt_cc1_low'), isFalse);

        // 4. Verify other SKU alert remains unread
        expect(unreadAlerts.any((a) => a.id == 'alt_other_sku'), isTrue);
      });
    });

    // =========================================================================
    // 5. ALERT CONSOLIDATION (1 CARD/SKU), SECONDARY BADGES & RECORD SALE LOCKING
    // =========================================================================
    group('5. Alert Consolidation and Contextual Button Stress Verification', () {
      testWidgets('5.1 Combines discrepancy + low stock into 1 card with secondary [Low Stock] badge and renders Record Sale for deficit', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Deficit: detected 1 < recorded 4
        final discAlert = AlertModel(
          id: 'alt_def_disc',
          title: 'Stock Discrepancy Detected',
          desc: 'Camera detected 1 bottle, but ledger recorded 4',
          branch: testBranch,
          type: 'discrepancy',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        );
        final lowAlert = AlertModel(
          id: 'alt_def_low',
          title: 'Low Stock Alert - AA1',
          desc: '1 bottle remaining',
          branch: testBranch,
          type: 'low_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        );

        final inv = InventoryRecordModel(
          id: 'inv_aa1',
          perfumeCode: 'AA1',
          name: 'Sauvage Dior',
          branch: testBranch,
          shelf: 'Area A',
          recorded: 4,
          detected: 1,
          status: 'low',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sqliteServiceProvider.overrideWithValue(sqliteService),
              liveAlertsProvider(testBranch).overrideWith((ref) => [discAlert, lowAlert]),
              resolvedAlertsHistoryProvider(testBranch).overrideWith((ref) => []),
              liveInventoryProvider(testBranch).overrideWith((ref) => [inv]),
            ],
            child: const MaterialApp(
              home: AlertsScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Must display exactly 1 card in active list
        expect(find.text('1 ACTIVE'), findsOneWidget);
        expect(find.text('Stock Discrepancy Detected'), findsOneWidget);
        expect(find.text('Low Stock Alert - AA1'), findsNothing);

        // Primary badge: Discrepancy
        expect(find.text('Discrepancy'), findsOneWidget);
        // Secondary badge: Low Stock
        expect(find.descendant(of: find.byType(ListView), matching: find.text('Low Stock')), findsOneWidget);

        // Deficit Discrepancy: Take Action button MUST be visible
        expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsOneWidget);
        // Deficit Discrepancy: Manually Check Restock MUST NOT be visible
        expect(find.widgetWithText(ElevatedButton, 'Manually Check Restock'), findsNothing);
      });

      testWidgets('5.2 Pure Low Stock alert: Consolidates duplicate stock alerts, renders NO Record Sale and NO Manually Check Restock', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pure low stock: recorded=2, detected=2 (no discrepancy)
        final lowAlert1 = AlertModel(
          id: 'alt_pure_low_1',
          title: 'Low Stock Alert - BB2',
          desc: 'Shelf has 2 bottles left',
          branch: testBranch,
          type: 'low_stock',
          perfumeCode: 'BB2',
          isRead: false,
          createdAt: DateTime.now(),
        );
        final lowAlert2 = AlertModel(
          id: 'alt_pure_low_2',
          title: 'Second Low Stock Alert - BB2',
          desc: 'Shelf has 2 bottles left',
          branch: testBranch,
          type: 'lowStock',
          perfumeCode: 'BB2',
          isRead: false,
          createdAt: DateTime.now(),
        );

        final inv = InventoryRecordModel(
          id: 'inv_bb2',
          perfumeCode: 'BB2',
          name: 'Vanilla Woods',
          branch: testBranch,
          shelf: 'Area B',
          recorded: 2,
          detected: 2,
          status: 'low',
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sqliteServiceProvider.overrideWithValue(sqliteService),
              liveAlertsProvider(testBranch).overrideWith((ref) => [lowAlert1, lowAlert2]),
              resolvedAlertsHistoryProvider(testBranch).overrideWith((ref) => []),
              liveInventoryProvider(testBranch).overrideWith((ref) => [inv]),
            ],
            child: const MaterialApp(
              home: AlertsScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // Must display exactly 1 card (not 2)
        expect(find.text('1 ACTIVE'), findsOneWidget);
        expect(find.text('Low Stock Alert - BB2'), findsOneWidget);
        expect(find.text('Second Low Stock Alert - BB2'), findsNothing);

        // Status badge: Low Stock on card
        expect(
          find.descendant(of: find.byType(StatusBadge), matching: find.text('Low Stock')),
          findsOneWidget,
        );

        // Pure Low Stock: Record Sale MUST NEVER BE SHOWN
        expect(find.widgetWithText(ElevatedButton, 'Record Sale'), findsNothing);
        // Pure Low Stock: Manually Check Restock MUST NEVER BE SHOWN
        expect(find.widgetWithText(ElevatedButton, 'Manually Check Restock'), findsNothing);

        // Contextual action must be 'Verify Restock' and secondary 'Restock Order'
        expect(find.text('Verify Restock'), findsOneWidget);
        expect(find.text('Restock Order'), findsOneWidget);
      });

      testWidgets('5.3 Multiple SKUs with mixed alerts: Consolidates strictly into 1 card per SKU', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // 3 distinct SKUs, each with 2 alerts = 6 alerts total
        final alerts = [
          AlertModel(
            id: 'alt_1a',
            title: 'Discrepancy SKU1',
            desc: 'detected 1 recorded 3',
            branch: testBranch,
            type: 'discrepancy',
            perfumeCode: 'SKU1',
            createdAt: DateTime.now(),
          ),
          AlertModel(
            id: 'alt_1b',
            title: 'Low Stock SKU1',
            desc: '1 bottle',
            branch: testBranch,
            type: 'low_stock',
            perfumeCode: 'SKU1',
            createdAt: DateTime.now(),
          ),
          AlertModel(
            id: 'alt_2a',
            title: 'Discrepancy SKU2',
            desc: 'detected 4 recorded 2',
            branch: testBranch,
            type: 'discrepancy',
            perfumeCode: 'SKU2',
            createdAt: DateTime.now(),
          ),
          AlertModel(
            id: 'alt_2b',
            title: 'Surplus SKU2',
            desc: 'detected 4 recorded 2',
            branch: testBranch,
            type: 'discrepancy',
            perfumeCode: 'SKU2',
            createdAt: DateTime.now(),
          ),
          AlertModel(
            id: 'alt_3a',
            title: 'Low Stock SKU3',
            desc: '1 bottle left',
            branch: testBranch,
            type: 'low_stock',
            perfumeCode: 'SKU3',
            createdAt: DateTime.now(),
          ),
          AlertModel(
            id: 'alt_3b',
            title: 'Out of Stock SKU3',
            desc: '0 bottles',
            branch: testBranch,
            type: 'out_of_stock',
            perfumeCode: 'SKU3',
            createdAt: DateTime.now(),
          ),
        ];

        final inv = [
          InventoryRecordModel(id: 'i1', perfumeCode: 'SKU1', name: 'Perfume 1', branch: testBranch, shelf: 'A', recorded: 3, detected: 1),
          InventoryRecordModel(id: 'i2', perfumeCode: 'SKU2', name: 'Perfume 2', branch: testBranch, shelf: 'B', recorded: 2, detected: 4),
          InventoryRecordModel(id: 'i3', perfumeCode: 'SKU3', name: 'Perfume 3', branch: testBranch, shelf: 'C', recorded: 1, detected: 1),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sqliteServiceProvider.overrideWithValue(sqliteService),
              liveAlertsProvider(testBranch).overrideWith((ref) => alerts),
              resolvedAlertsHistoryProvider(testBranch).overrideWith((ref) => []),
              liveInventoryProvider(testBranch).overrideWith((ref) => inv),
            ],
            child: const MaterialApp(
              home: AlertsScreen(),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 6 alerts across 3 SKUs -> exactly 3 consolidated cards
        expect(find.text('3 ACTIVE'), findsOneWidget);

        // SKU1 (deficit): Take Action is present
        expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsNWidgets(2));

        // Old redundant buttons must not exist
        expect(find.widgetWithText(ElevatedButton, 'Record Sale'), findsNothing);
        expect(find.widgetWithText(ElevatedButton, 'Manually Check Restock'), findsNothing);
      });
    });
  });
}
