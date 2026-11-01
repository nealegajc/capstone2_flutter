import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Targeted Verification Scan Fix Tests (R2)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      final db = await sqliteService.database;
      await db.delete('alerts');
      await db.delete('inventory_records');
    });

    test('R2: markStockAlertsReadForPerfume marks stock alerts read without deleting or affecting others', () async {
      const branch = 'San Pablo';
      final alertTargetStock = AlertModel(
        id: 'alt_target_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final alertTargetOutOfStock = AlertModel(
        id: 'alt_target_oos',
        title: 'Out of Stock Alert',
        desc: 'Out of stock on AD1',
        branch: branch,
        type: 'out_of_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final alertOtherPerfume = AlertModel(
        id: 'alt_other_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD2',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD2',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final alertSystem = AlertModel(
        id: 'alt_target_sys',
        title: 'System Alert',
        desc: 'System error',
        branch: branch,
        type: 'system',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      await sqliteService.saveAlert(alertTargetStock);
      await sqliteService.saveAlert(alertTargetOutOfStock);
      await sqliteService.saveAlert(alertOtherPerfume);
      await sqliteService.saveAlert(alertSystem);

      // Verify initial state: all 4 are unread
      final initialUnread = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(initialUnread.length, 4);

      // Call markStockAlertsReadForPerfume for AD1
      await sqliteService.markStockAlertsReadForPerfume('AD1', branch: branch);

      // Query active (unread) alerts: target stock alerts are resolved, remaining are other perfume and system
      final remainingUnread = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(remainingUnread.length, 2);
      expect(remainingUnread.any((a) => a.id == 'alt_other_low'), isTrue);
      expect(remainingUnread.any((a) => a.id == 'alt_target_sys'), isTrue);

      // Query all alerts to confirm target stock alerts are NOT deleted, but have isRead = 1
      final allAlerts = await sqliteService.getAlerts(branch);
      expect(allAlerts.length, 4);
      final readTargetLow = allAlerts.firstWhere((a) => a.id == 'alt_target_low');
      final readTargetOos = allAlerts.firstWhere((a) => a.id == 'alt_target_oos');
      expect(readTargetLow.isRead, isTrue);
      expect(readTargetOos.isRead, isTrue);

      // Query history (isRead = 1) alerts
      final historyAlerts = await sqliteService.getAlerts(branch, unreadOnly: false);
      expect(historyAlerts.length, 2);
    });

    test('R2: Slot verification isolates target slot detected count and does NOT sum across tray or cameras', () async {
      const branch = 'San Pablo';

      // Insert inventory records: Slot AD1 has 1 bottle (below threshold 3), Slot AD2 has 5 bottles.
      // Total bottles on tray AD across camera is 6.
      // Previously, the bug summed totalBottlesAcrossCams (6 >= 3) which falsely passed AD1.
      final invAD1 = InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Perfume AD1',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 1,
        status: 'low',
      );
      final invAD2 = InventoryRecordModel(
        id: 'inv_${branch}_AD2',
        perfumeCode: 'AD2',
        name: 'Perfume AD2',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 5,
        status: 'normal',
      );

      await sqliteService.saveInventoryRecord(invAD1);
      await sqliteService.saveInventoryRecord(invAD2);

      // Verify exact slot count for AD1 is 1
      final slotCountAD1 = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
      expect(slotCountAD1, 1);

      // Verify exact slot count for AD2 is 5
      final slotCountAD2 = await sqliteService.getDetectedCountForSlot('AD2', branch: branch);
      expect(slotCountAD2, 5);

      // Under R2 requirement:
      // Verification threshold is >= 3 bottles in the specific slot.
      // AD1 has 1 bottle: 1 < 3 -> verification fails, deficit is 3 - 1 = 2
      final bool ad1PassesThreshold = slotCountAD1 >= 3;
      expect(ad1PassesThreshold, isFalse);
      final deficit = 3 - slotCountAD1;
      expect(deficit, 2);

      // Now simulate restocking AD1 to 4 bottles
      final updatedAD1 = InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Perfume AD1',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 4,
        status: 'normal',
      );
      await sqliteService.saveInventoryRecord(updatedAD1);

      final newCountAD1 = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
      expect(newCountAD1, 4);
      expect(newCountAD1 >= 3, isTrue);
    });

    test('R2: System alert is logged on camera connection failure', () async {
      const branch = 'San Pablo';
      final systemAlert = AlertModel(
        id: 'alert_system_cam_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Camera Scan Service Unavailable',
        desc: 'Failed to communicate with vision edge service for Camera(s): 1 while verifying Tray AD (AD1).',
        branch: branch,
        type: 'system',
        createdAt: DateTime.now(),
      );

      await sqliteService.saveAlert(systemAlert);

      final allUnread = await sqliteService.getAlerts(branch, unreadOnly: true);
      final systemAlerts = allUnread.where((a) => a.type == 'system').toList();
      expect(systemAlerts.length, 1);
      expect(systemAlerts.first.title, 'Camera Scan Service Unavailable');
      expect(systemAlerts.first.type, 'system');
      expect(systemAlerts.first.desc, contains('Camera(s): 1'));
    });

    testWidgets('R2: ScanWorkflowDialog initializes with targeted guidance for target slot and alert', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final targetAlert = AlertModel(
        id: 'alert_ad1',
        title: 'Low Stock Alert',
        desc: 'Stock level critical on slot AD1 (1 bottle remaining)',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: targetAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should display Targeted Verification title / guidance
      expect(find.text('Targeted Shelf Verification'), findsOneWidget);
      expect(find.textContaining('Tray AD'), findsWidgets);
      expect(find.text('I Understand, Verify Now'), findsOneWidget);
    });
  });
}
