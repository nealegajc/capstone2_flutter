import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';

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
      expect(products.length, equals(4));
      expect(products.map((p) => p.perfumeCode).toList(), containsAll(['A', 'B', 'C', 'D']));
    });

    test('Initial seeding populates branch shelf regions', () async {
      final spRegions = await sqliteService.getShelfRegions('San Pablo');
      expect(spRegions.length, equals(4));
      expect(spRegions.first.code, equals('A'));
      expect(spRegions.first.left, equals(0.0));
      expect(spRegions.first.right, equals(0.25));

      final lipaRegions = await sqliteService.getShelfRegions('Lipa');
      expect(lipaRegions.length, equals(4));
    });

    test('Inventory CRUD operations work properly', () async {
      final initialInv = await sqliteService.getInventoryRecords('San Pablo');
      expect(initialInv.length, equals(4));

      // Upsert modified record
      final updatedItem = InventoryRecordModel(
        id: 'inv_sp_A',
        perfumeCode: 'A',
        name: 'Otto Scents Ocean Breeze Updated',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 3,
        status: 'normal',
        price: 280.0,
      );

      await sqliteService.upsertInventoryRecord(updatedItem);

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final fetched = invAfter.firstWhere((i) => i.id == 'inv_sp_A');
      expect(fetched.name, equals('Otto Scents Ocean Breeze Updated'));
      expect(fetched.detected, equals(3));
      expect(fetched.price, equals(280.0));
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
      expect(adminCreds['passwordHash'], equals(SqliteService.hashPassword('password123')));

      // 2. Wrong password verification fails
      final wrongPasswordHash = SqliteService.hashPassword('wrongpassword');
      expect(adminCreds['passwordHash'] == wrongPasswordHash, isFalse);

      // 3. Correct password verification succeeds
      final correctPasswordHash = SqliteService.hashPassword('password123');
      expect(adminCreds['passwordHash'] == correctPasswordHash, isTrue);
    });
  });
}
