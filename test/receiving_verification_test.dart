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

  group('Receiving Verification & Strict Validation Tests (R3 & R4)', () {
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

    test('R4: resolveRestockDelivery marks delivery verified, resolves alerts, and logs RESTOCKED event', () async {
      const branch = 'San Pablo';
      const restockId = 'restock_batch_101';
      const perfumeCode = 'AA1';

      // 1. Seed pending restock record
      final restock = RestockRecordModel(
        id: restockId,
        productName: 'Bvlgari Extreme (100ML)',
        perfumeCode: perfumeCode,
        quantity: 4,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff A',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(restock);

      // 2. Seed active stock alert for AA1
      final activeAlert = AlertModel(
        id: 'alt_aa1_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on slot AA1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: perfumeCode,
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      // Verify alert is unread
      final unreadBefore = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadBefore.length, 1);

      // 3. Execute resolveRestockDelivery with verifiedQuantity = 5
      await sqliteService.resolveRestockDelivery(
        restockId: restockId,
        perfumeCode: perfumeCode,
        verifiedQuantity: 5,
        branch: branch,
      );

      // 4. Assert restock status is updated to 'verified'
      final restocks = await sqliteService.getRestockRecords(branch);
      final updatedRestock = restocks.firstWhere((r) => r.id == restockId);
      expect(updatedRestock.status, 'verified');

      // 5. Assert stock alert is marked read (isRead = 1, moves to resolved history)
      final unreadAfter = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAfter.isEmpty, isTrue);

      final historyAfter = await sqliteService.getAlerts(branch, unreadOnly: false);
      expect(historyAfter.length, 1);
      expect(historyAfter.first.isRead, isTrue);

      // 6. Assert RESTOCKED event is logged in inventory_events
      final events = await sqliteService.getInventoryEvents(branch);
      expect(events.isNotEmpty, isTrue);
      final restockedEvent = events.firstWhere((e) => e.eventType == 'RESTOCKED');
      expect(restockedEvent.perfumeCode, perfumeCode);
      expect(restockedEvent.quantity, 5);

      // 7. Assert RESTOCK_VERIFIED activity is logged in system_logs
      final logs = await sqliteService.getSystemLogs(branch);
      final restockLog = logs.firstWhere((l) => l.type == 'RESTOCK_VERIFIED');
      expect(restockLog.description, contains('Restock verified for AA1'));
    });

    testWidgets('R3: ReceivingVerificationScreen renders Scan All Shelves and in-place Scan Tray actions', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final testRestocks = [
        RestockRecordModel(
          id: 'batch_201',
          productName: 'Bvlgari Extreme (100ML)',
          perfumeCode: 'AA1',
          quantity: 3,
          fromBranch: 'Main Warehouse',
          toBranch: branch,
          requestedBy: 'Staff A',
          status: 'received',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => testRestocks),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_${branch}_AA1',
                perfumeCode: 'AA1',
                name: 'Bvlgari Extreme (100ML)',
                branch: branch,
                shelf: 'Tray AA',
                recorded: 5,
                detected: 3,
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

      // Verify top header actions
      expect(find.text('Scan All Shelves'), findsOneWidget);
      expect(find.text('New Delivery Batch'), findsOneWidget);

      // Verify card content and in-place Scan Tray button
      expect(find.text('Bvlgari Extreme (100ML) (AA1)'), findsOneWidget);
      expect(find.text('Scan Tray'), findsOneWidget);
      expect(find.text('Confirm Stock'), findsOneWidget);
    });

    testWidgets('R3: Strict verification blocks confirmation on inventory shortfall and displays discrepancy dialog', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final testRestocks = [
        RestockRecordModel(
          id: 'batch_shortfall',
          productName: 'Clinique Happy (100ML)',
          perfumeCode: 'AC1',
          quantity: 4, // Expected 4 on invoice
          fromBranch: 'Main Warehouse',
          toBranch: branch,
          requestedBy: 'Staff B',
          status: 'received',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => testRestocks),
            // Only 2 bottles detected on shelf (shortfall of 2)
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_${branch}_AC1',
                perfumeCode: 'AC1',
                name: 'Clinique Happy (100ML)',
                branch: branch,
                shelf: 'Tray AC',
                recorded: 5,
                detected: 2,
                status: 'low',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should show red vision count
      expect(find.text('2 Bottles'), findsOneWidget);
      expect(find.text('4 Bottles'), findsOneWidget);

      // Button should say 'Discrepancy Details' because detectedQty (2) < expected (4)
      expect(find.text('Discrepancy Details'), findsOneWidget);
      expect(find.text('Confirm Stock'), findsNothing);

      // Tap Discrepancy Details button
      await tester.tap(find.text('Discrepancy Details'));
      await tester.pumpAndSettle();

      // Discrepancy dialog must appear with exact shortfall
      expect(find.text('Stock Verification Discrepancy'), findsOneWidget);
      expect(find.text('Cannot confirm delivery batch #batch_shortfall due to an inventory shortfall.'), findsOneWidget);
      expect(find.text('-2 Bottles'), findsOneWidget);
      expect(find.text('Scan Tray Now'), findsOneWidget);
    });

    testWidgets('R3 & R4: Successful confirmation executes resolveRestockDelivery and updates state to Verified', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final record = RestockRecordModel(
        id: 'batch_success_301',
        productName: 'Ralph Lauren Polo (100ML)',
        perfumeCode: 'AE1',
        quantity: 3,
        fromBranch: 'Main Warehouse',
        toBranch: branch,
        requestedBy: 'Staff C',
        status: 'received',
      );
      await sqliteService.saveRestockRecord(record, enqueueSync: false);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            restockRecordsProvider(branch).overrideWith((ref) => [record]),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(
                id: 'inv_${branch}_AE1',
                perfumeCode: 'AE1',
                name: 'Ralph Lauren Polo (100ML)',
                branch: branch,
                shelf: 'Tray AE',
                recorded: 5,
                detected: 4, // 4 >= 3, match succeeds
                status: 'normal',
              ),
            ]),
          ],
          child: const MaterialApp(
            home: ReceivingVerificationScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Should show 'Confirm Stock' button
      final confirmBtn = find.text('Confirm Stock');
      expect(confirmBtn, findsOneWidget);
      await tester.ensureVisible(confirmBtn);

      // Tap Confirm Stock
      await tester.tap(confirmBtn);
      await tester.pump(); // Dispatches tap event and enters _confirmBatch
      await tester.pump(const Duration(milliseconds: 100));

      // Should show 'Verified' button state and SnackBar
      expect(find.text('Verified'), findsWidgets);
      expect(find.textContaining('confirmed and marked as verified'), findsOneWidget);

      // Verify in SQLite that the restock record was resolved
      final restocks = await sqliteService.getRestockRecords(branch);
      final verifiedRecord = restocks.firstWhere((r) => r.id == 'batch_success_301');
      expect(verifiedRecord.status, 'verified');
    });
  });
}
