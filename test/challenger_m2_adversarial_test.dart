import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/services/sync_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CHALLENGE 1: Targeted Partial UPDATE Payload Transformations & Edge Cases', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService.instance;
    });

    test('1.1 Whitelist isolation: Extraneous or malicious keys are stripped from update map', () {
      final hostileAlertPayload = {
        'id': 'alert_999',
        'isRead': 1,
        'malicious_key': 'DROP TABLE users;',
        'price': 999.99,
        'perfumeCode': 'AA1',
        'detected': 5,
      };

      final updateMap = syncService.buildPartialUpdateMap('alerts', hostileAlertPayload);

      // Only recognized alert fields must survive
      expect(updateMap['is_read'], isTrue);
      expect(updateMap['perfume_code'], equals('AA1'));
      expect(updateMap.containsKey('malicious_key'), isFalse);
      expect(updateMap.containsKey('price'), isFalse);
      expect(updateMap.containsKey('detected'), isFalse);
      expect(updateMap.containsKey('id'), isFalse);
    });

    test('1.2 Null and boolean representation handling in alerts', () {
      // Null isRead
      final nullReadPayload = {
        'id': 'alert_null_read',
        'isRead': null,
      };
      final updateMapNull = syncService.buildPartialUpdateMap('alerts', nullReadPayload);
      expect(updateMapNull['is_read'], isFalse, reason: 'Null isRead must resolve to false without exception');

      // Integer 0 vs 1
      final zeroRead = syncService.buildPartialUpdateMap('alerts', {'isRead': 0});
      expect(zeroRead['is_read'], isFalse);

      final oneRead = syncService.buildPartialUpdateMap('alerts', {'isRead': 1});
      expect(oneRead['is_read'], isTrue);

      // Boolean true vs false
      final boolFalse = syncService.buildPartialUpdateMap('alerts', {'isRead': false});
      expect(boolFalse['is_read'], isFalse);

      final boolTrue = syncService.buildPartialUpdateMap('alerts', {'isRead': true});
      expect(boolTrue['is_read'], isTrue);

      // Snake case key 'is_read'
      final snakeCase = syncService.buildPartialUpdateMap('alerts', {'is_read': 1});
      expect(snakeCase['is_read'], isTrue);
    });

    test('1.3 restock_records timestamp conversion and null tolerance', () {
      // Milliseconds epoch
      final epochMs = 1730421234000;
      final mapEpoch = syncService.buildPartialUpdateMap('restock_records', {
        'status': 'verified',
        'verifiedAt': epochMs,
      });
      expect(mapEpoch['status'], equals('verified'));
      expect(mapEpoch['verified_at'], isNotNull);
      expect(DateTime.tryParse(mapEpoch['verified_at'] as String), isNotNull);

      // Null timestamp
      final mapNullTime = syncService.buildPartialUpdateMap('restock_records', {
        'status': 'cancelled',
        'verifiedAt': null,
      });
      expect(mapNullTime['status'], equals('cancelled'));
      expect(mapNullTime['verified_at'], isNotNull, reason: 'Null verifiedAt should fallback to current UTC timestamp');

      // ISO-8601 string input
      final isoInput = '2026-11-01T08:30:00Z';
      final mapIso = syncService.buildPartialUpdateMap('restock_records', {
        'verifiedAt': isoInput,
      });
      expect(mapIso['verified_at'], equals('2026-11-01T08:30:00.000Z'));
    });

    test('1.4 Empty and unmapped payload returns empty updateMap to prevent no-op cloud calls', () {
      final emptyAlert = syncService.buildPartialUpdateMap('alerts', {'id': 'alert_only'});
      expect(emptyAlert.isEmpty, isTrue, reason: 'Empty partial payload must yield empty update map');

      final emptyRestock = syncService.buildPartialUpdateMap('restock_records', {'id': 'restock_only'});
      expect(emptyRestock.isEmpty, isTrue);

      final emptyProducts = syncService.buildPartialUpdateMap('products', {'id': 'prod_only'});
      expect(emptyProducts.isEmpty, isTrue);
    });

    test('1.5 Partial classification boundary (_isPartialPayload)', () {
      // Alerts: Partial if missing title AND missing perfumeCode
      expect(syncService.isPartialPayload('alerts', {'id': '1', 'isRead': 1}), isTrue);
      expect(syncService.isPartialPayload('alerts', {'id': '1', 'isRead': 1, 'perfumeCode': 'AA1'}), isFalse);
      expect(syncService.isPartialPayload('alerts', {'id': '1', 'title': 'Low Stock'}), isFalse);

      // Restock: Partial if missing productName and product_name
      expect(syncService.isPartialPayload('restock_records', {'id': '1', 'status': 'verified'}), isTrue);
      expect(syncService.isPartialPayload('restock_records', {'id': '1', 'productName': 'Sauvage'}), isFalse);
      expect(syncService.isPartialPayload('restock_records', {'id': '1', 'product_name': 'Sauvage'}), isFalse);

      // Products: Partial if missing name OR missing perfumeCode
      expect(syncService.isPartialPayload('products', {'id': '1', 'status': 'active'}), isTrue);
      expect(syncService.isPartialPayload('products', {'id': '1', 'name': 'Sauvage'}), isTrue);
      expect(syncService.isPartialPayload('products', {'id': '1', 'name': 'Sauvage', 'perfumeCode': 'AD1'}), isFalse);

      // Users: Partial if missing email
      expect(syncService.isPartialPayload('users', {'id': 'u1', 'role': 'owner'}), isTrue);
      expect(syncService.isPartialPayload('users', {'id': 'u1', 'email': 'owner@otto.com'}), isFalse);

      // System Settings: never partial to preserve key-value upsert
      expect(syncService.isPartialPayload('system_settings', {'key': 'k', 'value': 'v'}), isFalse);

      // Unknown table: returns false by default
      expect(syncService.isPartialPayload('unknown_collection', {'foo': 'bar'}), isFalse);
    });
  });

  group('CHALLENGE 2: Stock Count Invariants (Slot Capacity <= 5 Clamping & Vision Separation)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('2.1 Spatial detection clamp: More than 5 bottles detected in a single slot are strictly clamped to 5', () async {
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // 9 detections all on the left side of Tray AA (AA1 < 0.10)
      final overflowDetections = List.generate(9, (index) => {
        'id': 'det_$index',
        'centerX': 0.01 + (index * 0.008),
        'centerY': 0.20 + (index * 0.05),
      });

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: overflowDetections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      expect(counts['AA1'], equals(5), reason: 'Spatial bottle count in slot AA1 must be clamped to max 5');

      final inv = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = inv.firstWhere((r) => r.perfumeCode == 'AA1');
      expect(aa1.detected, equals(5), reason: 'InventoryRecord detected count in DB must never exceed 5');
    });

    test('2.2 Vision separation: Manual restock invoice creation does not inflate detected count', () async {
      // Initial state: recorded = 2, detected = 1 (camera count)
      final initialRecord = InventoryRecordModel(
        id: 'inv_San Pablo_AB1',
        perfumeCode: 'AB1',
        name: 'Perfume AB1',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 2,
        detected: 1,
        status: 'low',
      );
      await sqliteService.upsertInventoryRecord(initialRecord);

      // Simulate restock submission: 4 bottles restocked
      final restockQty = 4;
      final existing = await sqliteService.getInventoryRecord('AB1', 'San Pablo');
      expect(existing, isNotNull);

      // Invariant logic enforced in create_restock_screen.dart
      final newRecorded = (existing!.recorded + restockQty).clamp(0, 5);
      final currentDetected = existing.detected.clamp(0, 5);
      final hasDiscrepancy = currentDetected != newRecorded;

      final updated = InventoryRecordModel(
        id: existing.id,
        perfumeCode: existing.perfumeCode,
        name: existing.name,
        category: existing.category,
        branch: existing.branch,
        shelf: existing.shelf,
        recorded: newRecorded,
        detected: currentDetected,
        status: hasDiscrepancy ? 'needs_review' : 'normal',
        misplacementDetails: existing.misplacementDetails,
        lastUpdated: DateTime.now(),
        price: existing.price,
      );

      await sqliteService.upsertInventoryRecord(updated);

      final postRestock = await sqliteService.getInventoryRecord('AB1', 'San Pablo');
      expect(postRestock!.recorded, equals(5), reason: 'Recorded stock clamped to 5 (2 + 4 -> 5)');
      expect(postRestock.detected, equals(1), reason: 'Detected stock must remain 1 until camera verifies it');
      expect(postRestock.status, equals('needs_review'), reason: 'Mismatch between recorded 5 and detected 1 requires review');
    });

    test('2.3 Extreme coordinate noise and negative coordinates are safely clamped without throwing', () async {
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      final noisyDetections = [
        {'id': 'n1', 'centerX': -0.5, 'centerY': -0.1},
        {'id': 'n2', 'centerX': 99.0, 'centerY': 100.0},
        {'id': 'n3', 'centerX': 0.05, 'centerY': 0.5},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: noisyDetections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      expect(counts['AA1'], isNotNull);
      expect(counts['AA1']! <= 5, isTrue);
      expect(counts['AA1']! >= 0, isTrue);
    });
  });

  group('CHALLENGE 3: Discrepancy Review Alerts when detected != recorded vs States', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);

      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );
    });

    test('3.1 detected < recorded (detected > 2): generates discrepancy alert and sets needs_review', () async {
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // 3 bottles detected (< recorded 5)
      final detections = List.generate(3, (i) => {
        'id': 'd_$i',
        'centerX': 0.02 + (i * 0.02),
        'centerY': 0.3 + (i * 0.1),
      });

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final inv = (await sqliteService.getInventoryRecords('San Pablo')).firstWhere((r) => r.perfumeCode == 'AA1');
      expect(inv.detected, equals(3));
      expect(inv.recorded, equals(5));
      expect(inv.status, equals('needs_review'));

      final alerts = await sqliteService.getAlerts('San Pablo');
      final discAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy').firstOrNull;
      expect(discAlert, isNotNull);
      expect(discAlert!.desc, contains('3'));
      expect(discAlert.desc, contains('5'));

      // Low stock alert must NOT be present
      final lowAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'low_stock').firstOrNull;
      expect(lowAlert, isNull);
    });

    test('3.2 detected > recorded (phantom bottles): generates discrepancy alert and sets needs_review', () async {
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 3,
        detected: 3,
        status: 'normal',
      ));

      // 5 bottles detected (> recorded 3)
      final detections = List.generate(5, (i) => {
        'id': 'd_$i',
        'centerX': 0.01 + (i * 0.015),
        'centerY': 0.2 + (i * 0.1),
      });

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final inv = (await sqliteService.getInventoryRecords('San Pablo')).firstWhere((r) => r.perfumeCode == 'AA1');
      expect(inv.detected, equals(5));
      expect(inv.recorded, equals(3));
      expect(inv.status, equals('needs_review'));

      final alerts = await sqliteService.getAlerts('San Pablo');
      final discAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy').firstOrNull;
      expect(discAlert, isNotNull);
      expect(discAlert!.desc, contains('5'));
      expect(discAlert.desc, contains('3'));
    });

    test('3.3 Low stock threshold priority: detected <= 2 sets status to low while preserving discrepancy alert', () async {
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // 2 bottles detected (<= lowThreshold 2, and != recorded 5)
      final detections = [
        {'id': 'd1', 'centerX': 0.03, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.06, 'centerY': 0.4},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final inv = (await sqliteService.getInventoryRecords('San Pablo')).firstWhere((r) => r.perfumeCode == 'AA1');
      expect(inv.detected, equals(2));
      expect(inv.recorded, equals(5));
      // Actionable low stock takes priority in status for the dashboard
      expect(inv.status, equals('low'), reason: 'Low stock status takes UI priority over needs_review');

      // Both discrepancy and low_stock alerts must exist
      final alerts = await sqliteService.getAlerts('San Pablo');
      final discAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy').firstOrNull;
      final lowAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'low_stock').firstOrNull;

      expect(discAlert, isNotNull, reason: 'Discrepancy alert must be tracked');
      expect(lowAlert, isNotNull, reason: 'Low stock alert must be generated for replenishment');
    });

    test('3.4 Out of stock priority: 0 bottles detected sets status to out_of_stock', () async {
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 3,
        status: 'needs_review',
      ));

      // Zero detections
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: [],
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final inv = (await sqliteService.getInventoryRecords('San Pablo')).firstWhere((r) => r.perfumeCode == 'AA1');
      expect(inv.detected, equals(0));
      expect(inv.status, equals('out_of_stock'), reason: 'Zero bottles detected must yield out_of_stock status');
    });

    test('3.5 Discrepancy auto-resolution upon matching scan', () async {
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 4,
        detected: 2,
        status: 'low',
      ));

      // Insert pre-existing discrepancy alert
      await sqliteService.insertAlert(AlertModel(
        id: 'alert_discrepancy_San Pablo_AA1',
        title: 'Stock Discrepancy Detected',
        desc: 'Slot AA1 mismatch',
        branch: 'San Pablo',
        type: 'discrepancy',
        perfumeCode: 'AA1',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      var alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy'), isTrue);

      // Subsequent scan detects 4 bottles, exactly matching recorded 4
      final matchingDetections = List.generate(4, (i) => {
        'id': 'd_$i',
        'centerX': 0.02 + (i * 0.018),
        'centerY': 0.25 + (i * 0.1),
      });

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: matchingDetections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final inv = (await sqliteService.getInventoryRecords('San Pablo')).firstWhere((r) => r.perfumeCode == 'AA1');
      expect(inv.detected, equals(4));
      expect(inv.recorded, equals(4));
      expect(inv.status, equals('normal'));

      alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy'), isFalse,
          reason: 'Discrepancy alert must be auto-deleted when detected count equals recorded count');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'low_stock'), isFalse,
          reason: 'Low stock alert must be auto-deleted when detected count > 2');
    });
  });

  group('CHALLENGE 4: Dynamic Branch Switching via system_settings.branch_name', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('4.1 Default branch returns San Pablo before any explicit setting', () async {
      final defaultBranch = await sqliteService.getBranchName();
      expect(defaultBranch, equals('San Pablo'));
    });

    test('4.2 Dynamic branch switch immediately updates getBranchName and currentBranchProvider', () async {
      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(currentBranchProvider.future), equals('San Pablo'));

      // Switch branch to Lipa City
      await sqliteService.setSystemSetting('branch_name', 'Lipa City');

      expect(await sqliteService.getBranchName(), equals('Lipa City'));

      // Re-read provider after invalidation
      container.invalidate(currentBranchProvider);
      expect(await container.read(currentBranchProvider.future), equals('Lipa City'));
    });

    test('4.3 Database queries with branch: null resolve to the configured dynamic branch', () async {
      await sqliteService.setSystemSetting('branch_name', 'SM Megamall');

      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_SM Megamall_AC1',
        perfumeCode: 'AC1',
        name: 'Chanel Bleu',
        category: 'Men',
        branch: 'SM Megamall',
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // Query with null branch resolves to SM Megamall
      final records = await sqliteService.getInventoryRecords(null);
      expect(records.length, equals(1));
      expect(records.first.branch, equals('SM Megamall'));

      // Query with explicit branch
      final explicitRecords = await sqliteService.getInventoryRecords('SM Megamall');
      expect(explicitRecords.length, equals(1));

      // Query for an unseeded branch returns empty list
      final unseededBranch = await sqliteService.getInventoryRecords('Cebu IT Park');
      expect(unseededBranch.isEmpty, isTrue);

      // Default San Pablo branch still contains its seeded catalog records
      final sanPabloRecords = await sqliteService.getInventoryRecords('San Pablo');
      expect(sanPabloRecords.isNotEmpty, isTrue);
    });

    test('4.4 updateInventoryFromDetections without explicit branch targets dynamic branch', () async {
      await sqliteService.setSystemSetting('branch_name', 'Glorietta Kiosk');

      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_Glorietta Kiosk_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'Glorietta Kiosk',
        shelf: 'Layer A',
        recorded: 5,
        detected: 0,
        status: 'out_of_stock',
      ));

      final detections = List.generate(4, (i) => {
        'id': 'd_$i',
        'centerX': 0.02 + (i * 0.02),
        'centerY': 0.3 + (i * 0.1),
      });

      // Call without specifying branch
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: null,
        targetSlotCodes: ['AA1'],
      );

      final inv = await sqliteService.getInventoryRecords('Glorietta Kiosk');
      final aa1 = inv.firstWhere((r) => r.perfumeCode == 'AA1');
      expect(aa1.detected, equals(4));
      expect(aa1.branch, equals('Glorietta Kiosk'));
    });

    test('4.5 Sync queue items on markAlertRead enqueues targeted UPDATE with effective branch', () async {
      await sqliteService.setSystemSetting('branch_name', 'Alabang Town Center');

      final alertId = 'alert_atc_001';
      // Insert without enqueuing sync to isolate the markAlertRead operation
      await sqliteService.insertAlert(
        AlertModel(
          id: alertId,
          title: 'ATC Low Stock',
          desc: 'Refill needed',
          branch: 'Alabang Town Center',
          type: 'low_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        enqueueSync: false,
      );

      await sqliteService.markAlertRead(alertId);

      final pending = await sqliteService.getPendingSyncItems();
      final alertItem = pending.firstWhere((item) =>
          item['targetCollection'] == 'alerts' && (item['id'] as String).contains(alertId));

      expect(alertItem['operation'], equals('UPDATE'));
      expect(alertItem['branch'], equals('Alabang Town Center'),
          reason: 'Sync queue item must be tagged with dynamic branch');
      final payload = jsonDecode(alertItem['payload'] as String) as Map<String, dynamic>;
      expect(payload['isRead'], equals(1));
      expect(payload.containsKey('title'), isFalse);
    });

    test('4.6 Residual hardcoded branch analysis: setLowStockThreshold behavior under dynamic branch', () async {
      // Configure dynamic branch to Lipa City
      await sqliteService.setSystemSetting('branch_name', 'Lipa City');

      // Seed Lipa City inventory with a discrepancy slot
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_Lipa City_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'Lipa City',
        shelf: 'Layer A',
        recorded: 5,
        detected: 3,
        status: 'needs_review',
      ));

      // Call setLowStockThreshold
      await sqliteService.setLowStockThreshold(2);

      // Verify whether Lipa City inventory was affected by setLowStockThreshold
      final lipaRecords = await sqliteService.getInventoryRecords('Lipa City');
      final lipaAa1 = lipaRecords.firstWhere((r) => r.perfumeCode == 'AA1');

      // In sqlite_service.dart: setLowStockThreshold now dynamically resolves branch via getBranchName()
      // Lipa City inventory is updated based on threshold (detected=3 > threshold=2 => 'normal')
      expect(lipaAa1.status, equals('normal'),
          reason: 'Lipa City record is updated to normal because setLowStockThreshold respects dynamic branch');
    });
  });
}
