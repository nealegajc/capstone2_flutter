import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/system_log_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/core/constants/app_constants.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SQLite Service Database Tests', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('Initial seeding populates master products catalog', () async {
      final products = await sqliteService.getProducts();
      expect(products.length, equals(60));
      expect(
        products.map((p) => p.perfumeCode).toList(),
        containsAll(['AA1', 'AA2', 'BA1', 'CK2']),
      );
    });

    test(
      'Initial seeding populates branch shelf regions for 6 cameras (100ML + 50ML zones)',
      () async {
        final spRegions = await sqliteService.getShelfRegions('San Pablo');
        expect(spRegions.length, equals(12));
        final cameraIds = spRegions.map((r) => r.cameraId).toSet();
        expect(cameraIds, equals({1, 2, 3, 4, 5, 6}));
        for (final id in cameraIds) {
          final zones = spRegions.where((r) => r.cameraId == id).toList();
          expect(zones.length, equals(2));
          expect(zones.any((r) => r.code.endsWith('100ML')), isTrue);
          expect(zones.any((r) => r.code.endsWith('50ML')), isTrue);
        }
      },
    );

    test('Inventory CRUD operations work properly', () async {
      final initialInv = await sqliteService.getInventoryRecords('San Pablo');
      expect(initialInv.length, equals(60));

      // Upsert modified record
      final updatedItem = InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Bvlgari Extreme 100ML Updated',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A (Top) - Slot 1',
        recorded: 5,
        detected: 3,
        status: 'normal',
      );

      await sqliteService.upsertInventoryRecord(updatedItem);

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final fetched = invAfter.firstWhere((i) => i.id == 'inv_San Pablo_AA1');
      expect(fetched.name, equals('Bvlgari Extreme 100ML Updated'));
      expect(fetched.detected, equals(3));
    });

    test('Alert lifecycle operations in SQLite', () async {
      final newAlert = AlertModel(
        id: 'alert_unit_test',
        title: 'Shelf Discrepancy',
        desc: 'Zone C detected mismatch',
        branch: 'San Pablo',
        type: 'misplaced',
        perfumeCode: 'C',
      );

      await sqliteService.insertAlert(newAlert);
      var alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.id == 'alert_unit_test'), isTrue);

      await sqliteService.markAlertRead('alert_unit_test');
      alerts = await sqliteService.getAlerts('San Pablo');
      final readAlert = alerts.firstWhere((a) => a.id == 'alert_unit_test');
      expect(readAlert.isRead, isTrue);

      await sqliteService.deleteAlert('alert_unit_test');
      alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.id == 'alert_unit_test'), isFalse);
    });

    test('Offline Sync Queue transitions properly', () async {
      await sqliteService.enqueueSyncItem(
        id: 'sync_item_1',
        pendingEventId: 'evt_101',
        targetCollection: 'inventory_events',
        operation: 'UPSERT',
        payload: {'eventType': 'REMOVED', 'quantity': 1},
        branch: 'San Pablo',
      );

      var pending = await sqliteService.getPendingSyncItems();
      expect(pending.any((i) => i['id'] == 'sync_item_1'), isTrue);

      await sqliteService.markSyncItemStatus('sync_item_1', 'synced');
      pending = await sqliteService.getPendingSyncItems();
      expect(pending.any((i) => i['id'] == 'sync_item_1'), isFalse);

      final allQueue = await sqliteService.getSyncQueue(
        'San Pablo',
        pendingOnly: false,
      );
      final syncedItem = allQueue.firstWhere((i) => i.id == 'sync_item_1');
      expect(syncedItem.status, equals('synced'));
    });

    test('System Settings persistence in SQLite', () async {
      await sqliteService.setSystemSetting(
        'captureSchedule',
        'Every 30 minutes',
      );
      await sqliteService.setSystemSetting('lowStockThreshold', '3');

      final settings = await sqliteService.getSystemSettings();
      expect(settings['captureSchedule'], equals('Every 30 minutes'));
      expect(settings['lowStockThreshold'], equals('3'));
    });

    test(
      'Offline User Authentication and Password Verification in SQLite',
      () async {
        // 1. Initial seeded users exist
        final adminCreds = await sqliteService.getUserWithCredentials(
          'admin@ottoscents.com',
        );
        expect(adminCreds, isNotNull);
        expect(adminCreds!['user'].role, equals('admin'));
        expect(
          adminCreds['passwordHash'],
          equals(SqliteService.hashPassword(AppConstants.defaultOwnerPin)),
        );

        // 2. Wrong password verification fails
        final wrongPasswordHash = SqliteService.hashPassword('wrongpassword');
        expect(adminCreds['passwordHash'] == wrongPasswordHash, isFalse);

        // 3. Correct password verification succeeds
        final correctPasswordHash = SqliteService.hashPassword(
          AppConstants.defaultOwnerPin,
        );
        expect(adminCreds['passwordHash'] == correctPasswordHash, isTrue);
      },
    );

    test('Store Owner PIN update strictly invalidates old PIN', () async {
      // 1. Initial default PIN is valid
      final initialValid = await sqliteService.verifyOwnerPin('123456');
      expect(initialValid, isTrue);

      // 2. Update PIN to new 6-digit code
      final updated = await sqliteService.updateOwnerPin(
        oldPin: '123456',
        newPin: '852963',
      );
      expect(updated, isTrue);

      // 3. New PIN works
      final newPinValid = await sqliteService.verifyOwnerPin('852963');
      expect(newPinValid, isTrue);

      // 4. Old PIN is strictly rejected
      final oldPinValid = await sqliteService.verifyOwnerPin('123456');
      expect(oldPinValid, isFalse);

      // 5. Arbitrary PIN is rejected
      final wrongPinValid = await sqliteService.verifyOwnerPin('000000');
      expect(wrongPinValid, isFalse);
    });

    test(
      'System Activity Logs uniqueness, batch upsert, and deletion',
      () async {
        // 1. Rapid consecutive logs have distinct IDs due to microsecond resolution + sequence counter
        await sqliteService.logActivity(
          type: 'TEST_OP',
          description: 'Log A',
          enqueueSync: false,
        );
        await sqliteService.logActivity(
          type: 'TEST_OP',
          description: 'Log B',
          enqueueSync: false,
        );

        final logs = await sqliteService.getSystemLogs('San Pablo');
        expect(logs.length, greaterThanOrEqualTo(2));
        final ids = logs.map((l) => l.id).toSet();
        expect(ids.length, equals(logs.length));

        // 2. Batch upsert from cloud
        final cloudLogs = [
          SystemLogModel(
            id: 'cloud_log_1',
            type: 'SALE_TRANSACTION',
            description: 'Cloud Sale 1',
            user: 'CloudUser',
            branch: 'San Pablo',
            timestamp: DateTime.now(),
          ),
          SystemLogModel(
            id: 'cloud_log_2',
            type: 'PRODUCT_CATALOG',
            description: 'Cloud Product 2',
            user: 'CloudUser',
            branch: 'San Pablo',
            timestamp: DateTime.now(),
          ),
        ];
        await sqliteService.upsertSystemLogsFromCloud(cloudLogs);

        final logsAfterBatch = await sqliteService.getSystemLogs('San Pablo');
        expect(logsAfterBatch.any((l) => l.id == 'cloud_log_1'), isTrue);
        expect(logsAfterBatch.any((l) => l.id == 'cloud_log_2'), isTrue);

        // 3. Delete single log
        await sqliteService.deleteSystemLog('cloud_log_1', enqueueSync: false);
        final logsAfterDel = await sqliteService.getSystemLogs('San Pablo');
        expect(logsAfterDel.any((l) => l.id == 'cloud_log_1'), isFalse);

        // 4. Clear all logs
        await sqliteService.clearAllSystemLogs('San Pablo', enqueueSync: false);
        final logsAfterClear = await sqliteService.getSystemLogs('San Pablo');
        expect(logsAfterClear.isEmpty, isTrue);
      },
    );

    test('SystemLogModel UTC and Local timestamp formatting and category categorization', () {
      final utcStr = '2026-10-28T11:29:07.000Z';
      final model = SystemLogModel.fromMap({
        'id': 'test_ts_log',
        'type': 'SALE_TRANSACTION',
        'description': 'Sale item',
        'timestamp': utcStr,
      });

      expect(model.timestamp.isUtc, isFalse); // Enforces .toLocal()
      expect(model.toSupabaseMap()['timestamp'], endsWith('Z'));
      expect(model.category, equals('Sales'));

      final invModel = SystemLogModel(
        id: 'test_inv',
        type: 'PRODUCT_CATALOG',
        description: 'Product updated',
        user: 'Admin',
        branch: 'San Pablo',
      );
      expect(invModel.category, equals('Inventory'));
    });

    test('recordSaleWithInventoryDeduction atomically updates sale, event, inventory, and sync_queue', () async {
      final initialInv = await sqliteService.getInventoryRecords('San Pablo');
      final targetItem = initialInv.firstWhere((i) => i.perfumeCode == 'AA1');
      final originalDetected = targetItem.detected;

      final saleId = 'test_atomic_sale_${DateTime.now().millisecondsSinceEpoch}';
      final sale = SaleRecordModel(
        id: saleId,
        perfumeCode: 'AA1',
        productName: 'Bvlgari Extreme',
        bottleSize: '100ml',
        quantitySold: 2,
        unitPrice: 350.0,
        totalAmount: 700.0,
        branch: 'San Pablo',
        soldBy: 'Tester',
        soldAt: DateTime.now(),
      );

      final event = InventoryEventModel(
        id: 'test_evt_${DateTime.now().millisecondsSinceEpoch}',
        eventType: 'REMOVED',
        productName: 'Bvlgari Extreme',
        perfumeCode: 'AA1',
        shelfArea: 'Layer A',
        branch: 'San Pablo',
        quantity: 2,
        timestamp: DateTime.now(),
      );

      await sqliteService.recordSaleWithInventoryDeduction(
        saleRecord: sale,
        event: event,
        branch: 'San Pablo',
      );

      // Verify sales record inserted
      final sales = await sqliteService.getSalesRecords('San Pablo');
      expect(sales.any((s) => s.id == saleId), isTrue);

      // Verify inventory count deducted
      final updatedInv = await sqliteService.getInventoryRecords('San Pablo');
      final updatedItem = updatedInv.firstWhere((i) => i.perfumeCode == 'AA1');
      expect(updatedItem.detected, equals(originalDetected - 2));

      // Verify sync queue entries created
      final pendingQueue = await sqliteService.getPendingSyncItems(applyBackoff: false);
      expect(pendingQueue.any((q) => q['id'] == 'sync_sale_$saleId'), isTrue);
    });

    test('getPendingSyncItems filters out items currently in backoff delay', () async {
      await sqliteService.enqueueSyncItem(
        id: 'test_backoff_item',
        pendingEventId: 'doc_1',
        targetCollection: 'products',
        operation: 'UPSERT',
        payload: {'id': 'doc_1'},
        branch: 'San Pablo',
      );

      // Initially no retries: should be included
      var pending = await sqliteService.getPendingSyncItems(applyBackoff: true);
      expect(pending.any((p) => p['id'] == 'test_backoff_item'), isTrue);

      // Increment retry to 2 (backoff = 20s) and simulate last attempt just now
      await sqliteService.incrementSyncRetry('test_backoff_item', 'Simulated Network Error');

      // With applyBackoff = true, recently failed item should be skipped
      pending = await sqliteService.getPendingSyncItems(applyBackoff: true);
      expect(pending.any((p) => p['id'] == 'test_backoff_item'), isFalse);

      // With applyBackoff = false, all pending items should be returned
      pending = await sqliteService.getPendingSyncItems(applyBackoff: false);
      expect(pending.any((p) => p['id'] == 'test_backoff_item'), isTrue);
    });

    test('updateInventoryFromDetections detects misplacements, updates inventory status, and inserts alerts', () async {
      // Configure 5 tray ROIs for Camera 1: AA, AB, AC, AD, AE
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.05,"top":0.2,"right":0.20,"bottom":0.8},'
        '"AB":{"left":0.22,"top":0.2,"right":0.38,"bottom":0.8},'
        '"AC":{"left":0.40,"top":0.2,"right":0.58,"bottom":0.8},'
        '"AD":{"left":0.60,"top":0.2,"right":0.78,"bottom":0.8},'
        '"AE":{"left":0.80,"top":0.2,"right":0.95,"bottom":0.8}}',
      );

      // Detections:
      // 1. Correct bottle in AA (100ml side): AA1 at x=0.08
      // 2. Misplaced bottle: AB1 physically sitting in Tray AC at x=0.45!
      final detections = [
        {
          'id': 'det_1',
          'boundingBox': [0.08, 0.35, 0.05, 0.1],
          'recognizedCode': 'AA1',
        },
        {
          'id': 'det_2',
          'boundingBox': [0.45, 0.35, 0.05, 0.1],
          'recognizedCode': 'AB1', // AB1 placed in Tray AC!
        },
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1', 'AA2', 'AB1', 'AB2', 'AC1', 'AC2', 'AD1', 'AD2', 'AE1', 'AE2'],
      );

      // Verify det_2 marked as misplaced
      expect(detections[1]['matchResult'], equals('misplaced'));

      // Verify inventory records: AB1 should be marked 'misplaced'
      final invList = await sqliteService.getInventoryRecords('San Pablo');
      final ab1 = invList.firstWhere((i) => i.perfumeCode == 'AB1');
      expect(ab1.status, equals('misplaced'));
      expect(ab1.misplacementDetails, contains('Tray AC'));

      // Verify alert was inserted into alerts table
      final alerts = await sqliteService.getAlerts('San Pablo');
      final misplacedAlerts = alerts.where((a) => a.type == 'misplaced').toList();
      expect(misplacedAlerts.length, greaterThanOrEqualTo(1));
      expect(misplacedAlerts.any((a) => a.perfumeCode == 'AB1'), isTrue);
      expect(misplacedAlerts.first.desc, contains('Tray AC'));

      // Verify movement event was logged in inventory_events
      final events = await sqliteService.getInventoryEvents('San Pablo');
      expect(events.any((e) => e.eventType == 'MISPLACED' && e.perfumeCode == 'AB1'), isTrue);
    });
  });
}
