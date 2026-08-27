import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
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
      expect(products.map((p) => p.perfumeCode).toList(), containsAll(['AA1', 'AA2', 'BA1', 'CK2']));
    });

    test('Initial seeding populates branch shelf regions for 3 cameras', () async {
      final spRegions = await sqliteService.getShelfRegions('San Pablo');
      expect(spRegions.length, equals(3));
      expect(spRegions.first.code, equals('Layer A'));
      expect(spRegions.first.cameraId, equals(1));
      expect(spRegions[1].cameraId, equals(2));
      expect(spRegions[2].cameraId, equals(3));
    });

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

      final allQueue = await sqliteService.getSyncQueue('San Pablo');
      final syncedItem = allQueue.firstWhere((i) => i.id == 'sync_item_1');
      expect(syncedItem.status, equals('synced'));
    });

    test('System Settings persistence in SQLite', () async {
      await sqliteService.setSystemSetting('captureSchedule', 'Every 30 minutes');
      await sqliteService.setSystemSetting('lowStockThreshold', '3');

      final settings = await sqliteService.getSystemSettings();
      expect(settings['captureSchedule'], equals('Every 30 minutes'));
      expect(settings['lowStockThreshold'], equals('3'));
    });

    test('Offline User Authentication and Password Verification in SQLite', () async {
      // 1. Initial seeded users exist
      final adminCreds = await sqliteService.getUserWithCredentials('admin@ottoscents.com');
      expect(adminCreds, isNotNull);
      expect(adminCreds!['user'].role, equals('admin'));
      expect(adminCreds['passwordHash'], equals(SqliteService.hashPassword(AppConstants.defaultOwnerPin)));

      // 2. Wrong password verification fails
      final wrongPasswordHash = SqliteService.hashPassword('wrongpassword');
      expect(adminCreds['passwordHash'] == wrongPasswordHash, isFalse);

      // 3. Correct password verification succeeds
      final correctPasswordHash = SqliteService.hashPassword(AppConstants.defaultOwnerPin);
      expect(adminCreds['passwordHash'] == correctPasswordHash, isTrue);
    });

    test('Store Owner PIN update strictly invalidates old PIN', () async {
      // 1. Initial default PIN is valid
      final initialValid = await sqliteService.verifyOwnerPin('123456');
      expect(initialValid, isTrue);

      // 2. Update PIN to new 6-digit code
      final updated = await sqliteService.updateOwnerPin(oldPin: '123456', newPin: '852963');
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
  });
}
