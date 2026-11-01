import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/restock_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/restock/receiving_verification_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Challenger 2 Empirical Tests: R3 Quantity Guard', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      final db = await sqliteService.database;
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('restock_records');
      await db.delete('inventory_events');
      await db.delete('system_logs');
    });

    testWidgets('Guard 1: detectedQty == 0 and invoiceQty == 5 triggers discrepancy dialog with shortfall = 5', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final restock = RestockRecordModel(
        id: 'batch_guard_0_5',
        productName: 'Tom Ford Oud Wood (100ML)',
        perfumeCode: 'AA1',
        quantity: 5,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff Q',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [restock]),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_AA1',
                perfumeCode: 'AA1',
                name: 'Tom Ford Oud Wood (100ML)',
                branch: branch,
                shelf: 'Tray AA',
                recorded: 5,
                detected: 0, // detectedQty == 0
                status: 'out_of_stock',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Assert count display
      expect(find.text('5 Bottles'), findsOneWidget); // Expected
      expect(find.text('0 Bottles'), findsOneWidget); // Detected

      // Assert Confirm Stock is NOT available
      expect(find.text('Confirm Stock'), findsNothing);

      // Assert Discrepancy Details is present
      final discrepancyBtn = find.text('Discrepancy Details');
      expect(discrepancyBtn, findsOneWidget);

      // Tap Discrepancy Details
      await tester.tap(discrepancyBtn);
      await tester.pumpAndSettle();

      // Assert discrepancy modal content
      expect(find.text('Stock Verification Discrepancy'), findsOneWidget);
      expect(find.text('Cannot confirm delivery batch #batch_guard_0_5 due to an inventory shortfall.'), findsOneWidget);
      expect(find.text('-5 Bottles'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      // Dialog dismissed, restock record in SQLite must still be 'received' (NOT verified)
      final records = await sqliteService.getRestockRecords(branch);
      expect(records.firstWhere((r) => r.id == 'batch_guard_0_5').status, 'received');
    });

    testWidgets('Guard 2: detectedQty == 4 and invoiceQty == 5 triggers discrepancy dialog with shortfall = 1', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final restock = RestockRecordModel(
        id: 'batch_guard_4_5',
        productName: 'Tom Ford Oud Wood (100ML)',
        perfumeCode: 'AA1',
        quantity: 5,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff Q',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [restock]),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_AA1',
                perfumeCode: 'AA1',
                name: 'Tom Ford Oud Wood (100ML)',
                branch: branch,
                shelf: 'Tray AA',
                recorded: 5,
                detected: 4, // detectedQty == 4
                status: 'normal',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('5 Bottles'), findsOneWidget); // Expected
      expect(find.text('4 Bottles'), findsOneWidget); // Detected
      expect(find.text('Confirm Stock'), findsNothing);

      final discrepancyBtn = find.text('Discrepancy Details');
      expect(discrepancyBtn, findsOneWidget);

      await tester.tap(discrepancyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Stock Verification Discrepancy'), findsOneWidget);
      expect(find.text('-1 Bottles'), findsOneWidget);

      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();

      final records = await sqliteService.getRestockRecords(branch);
      expect(records.firstWhere((r) => r.id == 'batch_guard_4_5').status, 'received');
    });

    testWidgets('Guard 3: detectedQty == 5 and invoiceQty == 5 enables Confirm Stock and proceeds cleanly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final restock = RestockRecordModel(
        id: 'batch_guard_5_5',
        productName: 'Bleu de Chanel (100ML)',
        perfumeCode: 'AB1',
        quantity: 5,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff R',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [restock]),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_AB1',
                perfumeCode: 'AB1',
                name: 'Bleu de Chanel (100ML)',
                branch: branch,
                shelf: 'Tray AB',
                recorded: 5,
                detected: 5, // detectedQty == 5
                status: 'normal',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Discrepancy Details'), findsNothing);
      final confirmBtn = find.text('Confirm Stock');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Verified'), findsWidgets);
      final records = await sqliteService.getRestockRecords(branch);
      expect(records.firstWhere((r) => r.id == 'batch_guard_5_5').status, 'verified');
    });

    testWidgets('Guard 4: detectedQty == 6 and invoiceQty == 5 (surplus) proceeds cleanly', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final restock = RestockRecordModel(
        id: 'batch_guard_6_5_surplus',
        productName: 'Sauvage Dior (100ML)',
        perfumeCode: 'AC1',
        quantity: 5,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff S',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [restock]),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_AC1',
                perfumeCode: 'AC1',
                name: 'Sauvage Dior (100ML)',
                branch: branch,
                shelf: 'Tray AC',
                recorded: 5,
                detected: 6, // detectedQty == 6 (surplus)
                status: 'normal',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Discrepancy Details'), findsNothing);
      final confirmBtn = find.text('Confirm Stock');
      expect(confirmBtn, findsOneWidget);

      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Verified'), findsWidgets);
      final records = await sqliteService.getRestockRecords(branch);
      expect(records.firstWhere((r) => r.id == 'batch_guard_6_5_surplus').status, 'verified');

      // Verify RESTOCKED event has quantity 6 (detected)
      final events = await sqliteService.getInventoryEvents(branch);
      final restockEvent = events.firstWhere((e) => e.perfumeCode == 'AC1');
      expect(restockEvent.quantity, 6);
    });

    testWidgets('Guard 5: missing live inventory record defaults detected to 0 and blocks confirmation', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final restock = RestockRecordModel(
        id: 'batch_missing_inv',
        productName: 'Acqua Di Gio (100ML)',
        perfumeCode: 'AD1',
        quantity: 3,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff T',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [restock]),
            // Empty inventory map - slot AD1 is missing
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('0 Bottles'), findsOneWidget);
      expect(find.text('Discrepancy Details'), findsOneWidget);
      expect(find.text('Confirm Stock'), findsNothing);
    });
  });

  group('Challenger 2 Empirical Tests: R4 Post-Verification Side Effects & Invalidation', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      final db = await sqliteService.database;
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('restock_records');
      await db.delete('inventory_events');
      await db.delete('system_logs');
    });

    test('Post-Verification Side Effects: Comprehensive Alert & Event Auditing', () async {
      const branch = 'San Pablo';
      const restockId = 'restock_batch_side_effects_999';
      const targetPerfume = 'BA1';

      // 1. Seed restock record
      final restock = RestockRecordModel(
        id: restockId,
        productName: 'Chanel No 5 (100ML)',
        perfumeCode: targetPerfume,
        quantity: 5,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Auditor X',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock, enqueueSync: false);

      // 2. Seed diverse alert types:
      // a. low_stock alert for BA1 (should be marked read)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_ba1_low',
        title: 'Low Stock BA1',
        desc: 'BA1 low',
        branch: branch,
        type: 'low_stock',
        perfumeCode: targetPerfume,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // b. out_of_stock alert for BA1 (should be marked read)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_ba1_oos',
        title: 'OOS BA1',
        desc: 'BA1 oos',
        branch: branch,
        type: 'out_of_stock',
        perfumeCode: targetPerfume,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // c. lowStock (camelCase variation) alert for BA1 (should be marked read)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_ba1_camel',
        title: 'Low Stock Camel BA1',
        desc: 'BA1 lowStock',
        branch: branch,
        type: 'lowStock',
        perfumeCode: targetPerfume,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // d. system alert for BA1 (should NOT be marked read!)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_ba1_sys',
        title: 'System alert BA1',
        desc: 'Camera disconnected',
        branch: branch,
        type: 'system',
        perfumeCode: targetPerfume,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // e. low_stock alert for a DIFFERENT perfume (BB1, should NOT be marked read!)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_bb1_low',
        title: 'Low Stock BB1',
        desc: 'BB1 low',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'BB1',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // f. low_stock alert for a DIFFERENT branch ('Manila', should NOT be marked read!)
      await sqliteService.saveAlert(AlertModel(
        id: 'alt_ba1_manila',
        title: 'Low Stock BA1 Manila',
        desc: 'BA1 Manila branch',
        branch: 'Manila',
        type: 'low_stock',
        perfumeCode: targetPerfume,
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // Check pre-state
      final unreadSanPabloBefore = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadSanPabloBefore.length, 5); // 3 stock + 1 sys + 1 diff perfume

      // 3. Execute resolveRestockDelivery
      await sqliteService.resolveRestockDelivery(
        restockId: restockId,
        perfumeCode: targetPerfume,
        verifiedQuantity: 5,
        branch: branch,
        enqueueSync: false,
      );

      // 4. Verify Restock status is 'verified'
      final restocks = await sqliteService.getRestockRecords(branch);
      expect(restocks.firstWhere((r) => r.id == restockId).status, 'verified');

      // 5. Verify alerts auditing:
      final unreadSanPabloAfter = await sqliteService.getAlerts(branch, unreadOnly: true);
      // System alert for BA1 and low_stock alert for BB1 must STILL be unread!
      expect(unreadSanPabloAfter.length, 2);
      final unreadIds = unreadSanPabloAfter.map((a) => a.id).toSet();
      expect(unreadIds.contains('alt_ba1_sys'), isTrue);
      expect(unreadIds.contains('alt_bb1_low'), isTrue);

      // Stock alerts for BA1 must NOT be deleted from SQLite - they must be isRead = 1 (history)
      // When unreadOnly: false is passed, it queries isRead = 1 (resolved alerts history)
      final resolvedHistoryAlerts = await sqliteService.getAlerts(branch, unreadOnly: false);
      expect(resolvedHistoryAlerts.length, 3);
      final ba1Low = resolvedHistoryAlerts.firstWhere((a) => a.id == 'alt_ba1_low');
      final ba1Oos = resolvedHistoryAlerts.firstWhere((a) => a.id == 'alt_ba1_oos');
      final ba1Camel = resolvedHistoryAlerts.firstWhere((a) => a.id == 'alt_ba1_camel');
      expect(ba1Low.isRead, isTrue);
      expect(ba1Oos.isRead, isTrue);
      expect(ba1Camel.isRead, isTrue);

      // Total alerts in SQLite for San Pablo (both isRead = 0 and isRead = 1) must be 5 (none deleted!)
      final totalSanPabloAlerts = await sqliteService.getAlerts(branch); // unreadOnly: null
      expect(totalSanPabloAlerts.length, 5);

      // Alert for Manila branch must remain completely untouched
      final unreadManila = await sqliteService.getAlerts('Manila', unreadOnly: true);
      expect(unreadManila.length, 1);
      expect(unreadManila.first.id, 'alt_ba1_manila');
      expect(unreadManila.first.isRead, isFalse);

      // 6. Verify inventory_events logging
      final events = await sqliteService.getInventoryEvents(branch);
      expect(events.length, 1);
      final ev = events.first;
      expect(ev.eventType, 'RESTOCKED');
      expect(ev.perfumeCode, targetPerfume);
      expect(ev.quantity, 5);
      expect(ev.shelfArea, 'Tray BA');
      expect(ev.syncStatus, 'synced');

      // 7. Verify system_logs activity
      final logs = await sqliteService.getSystemLogs(branch);
      expect(logs.isNotEmpty, isTrue);
      final restockLog = logs.firstWhere((l) => l.type == 'RESTOCK_VERIFIED');
      expect(restockLog.description, contains('Restock verified for BA1'));
      expect(restockLog.description, contains('+5 bottles verified onto Tray BA'));
    });

    testWidgets('Provider Invalidation: Confirming restock invalidates all 6 kiosk providers', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      const restockId = 'batch_invalidation_test';
      final record = RestockRecordModel(
        id: restockId,
        productName: 'Tom Ford Black Orchid (100ML)',
        perfumeCode: 'BC1',
        quantity: 3,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff V',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(record, enqueueSync: false);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Track invalidations
      int liveInventoryReads = 0;
      int liveAlertsReads = 0;
      int resolvedHistoryReads = 0;
      int dashboardStatsReads = 0;
      int restockRecordsReads = 0;
      int stockMovementLogsReads = 0;

      container.listen(liveInventoryProvider(branch), (prev, next) => liveInventoryReads++);
      container.listen(liveAlertsProvider(branch), (prev, next) => liveAlertsReads++);
      container.listen(resolvedAlertsHistoryProvider(branch), (prev, next) => resolvedHistoryReads++);
      container.listen(dashboardStatsProvider(branch), (prev, next) => dashboardStatsReads++);
      container.listen(restockRecordsProvider(branch), (prev, next) => restockRecordsReads++);
      container.listen(stockMovementLogsProvider(branch), (prev, next) => stockMovementLogsReads++);

      // Pump UI with UncontrolledProviderScope using our container
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Seed inventory with detected count 3 (match)
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_BC1',
        perfumeCode: 'BC1',
        name: 'Tom Ford Black Orchid (100ML)',
        branch: branch,
        shelf: 'Tray BC',
        recorded: 5,
        detected: 3,
        status: 'normal',
      ), enqueueSync: false);

      // Re-pump so the screen sees the inventory
      container.invalidate(liveInventoryProvider(branch));
      await tester.pumpAndSettle();

      final confirmBtn = find.text('Confirm Stock');
      expect(confirmBtn, findsOneWidget);

      final preLiveInvReads = liveInventoryReads;
      final preAlertsReads = liveAlertsReads;
      final preHistoryReads = resolvedHistoryReads;
      final preStatsReads = dashboardStatsReads;
      final preRestocksReads = restockRecordsReads;
      final preLogsReads = stockMovementLogsReads;

      // Tap Confirm Stock
      await tester.tap(confirmBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // After confirmation, all 6 providers should have been invalidated and triggered updates
      expect(liveInventoryReads, greaterThan(preLiveInvReads));
      expect(liveAlertsReads, greaterThan(preAlertsReads));
      expect(resolvedHistoryReads, greaterThan(preHistoryReads));
      expect(dashboardStatsReads, greaterThan(preStatsReads));
      expect(restockRecordsReads, greaterThan(preRestocksReads));
      expect(stockMovementLogsReads, greaterThan(preLogsReads));
    });
  });
}
