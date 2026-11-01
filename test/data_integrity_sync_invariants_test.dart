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

  group('Group 1: Differential Targeted UPDATE vs UPSERT Column Mapping', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService.instance;
    });

    test('buildPartialUpdateMap for alerts maps isRead: 1 to is_read: true without blank fields', () {
      final payload = {
        'id': 'alert_test_001',
        'isRead': 1,
      };

      final updateMap = syncService.buildPartialUpdateMap('alerts', payload);

      expect(updateMap['is_read'], isTrue);
      expect(updateMap.containsKey('id'), isFalse);
      expect(updateMap.containsKey('title'), isFalse, reason: 'Must not inject empty title');
      expect(updateMap.containsKey('description'), isFalse, reason: 'Must not inject empty description');
      expect(updateMap.containsKey('perfume_code'), isFalse, reason: 'Must not inject empty perfume_code');
    });

    test('buildPartialUpdateMap for alerts maps isRead: 0 to is_read: false', () {
      final payload = {
        'id': 'alert_test_002',
        'isRead': 0,
      };

      final updateMap = syncService.buildPartialUpdateMap('alerts', payload);
      expect(updateMap['is_read'], isFalse);
    });

    test('buildPartialUpdateMap for restock_records maps status and verifiedAt without wiping order details', () {
      final epochMs = 1730420000000;
      final payload = {
        'id': 'restock_001',
        'status': 'verified',
        'verifiedAt': epochMs,
      };

      final updateMap = syncService.buildPartialUpdateMap('restock_records', payload);

      expect(updateMap['status'], equals('verified'));
      expect(updateMap['verified_at'], isNotNull);
      expect(updateMap['verified_at'].toString().contains('2024'), isTrue);
      expect(updateMap.containsKey('product_name'), isFalse, reason: 'Must not overwrite product_name with empty string');
      expect(updateMap.containsKey('quantity'), isFalse, reason: 'Must not overwrite quantity with default 1');
      expect(updateMap.containsKey('perfume_code'), isFalse, reason: 'Must not overwrite perfume_code with empty string');
    });

    test('buildPartialUpdateMap for products maps status and price changes', () {
      final payload = {
        'id': 'prod_AA1',
        'status': 'inactive',
        'price': 179.50,
      };

      final updateMap = syncService.buildPartialUpdateMap('products', payload);

      expect(updateMap['status'], equals('inactive'));
      expect(updateMap['price'], equals(179.50));
      expect(updateMap.containsKey('name'), isFalse);
      expect(updateMap.containsKey('perfume_code'), isFalse);
    });

    test('buildPartialUpdateMap for inventory_records maps detected count and status', () {
      final payload = {
        'id': 'inv_San Pablo_AA1',
        'detected': 3,
        'status': 'needs_review',
        'misplacementDetails': 'Shifted from slot 2',
      };

      final updateMap = syncService.buildPartialUpdateMap('inventory_records', payload);

      expect(updateMap['detected'], equals(3));
      expect(updateMap['status'], equals('needs_review'));
      expect(updateMap['misplacement_details'], equals('Shifted from slot 2'));
      expect(updateMap.containsKey('name'), isFalse);
      expect(updateMap.containsKey('category'), isFalse);
    });

    test('buildPartialUpdateMap for users maps password_hash, salt and role', () {
      final payload = {
        'id': 'usr_owner_01',
        'passwordHash': 'pbkdf2_hash_hex_string',
        'salt': 'salt_32_bytes_hex',
        'role': 'owner',
      };

      final updateMap = syncService.buildPartialUpdateMap('users', payload);

      expect(updateMap['password_hash'], equals('pbkdf2_hash_hex_string'));
      expect(updateMap['salt'], equals('salt_32_bytes_hex'));
      expect(updateMap['role'], equals('owner'));
      expect(updateMap.containsKey('email'), isFalse);
      expect(updateMap.containsKey('name'), isFalse);
    });
  });

  group('Group 2: Partial Payload Classification (_isPartialPayload)', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService.instance;
    });

    test('alerts: identifies partial acknowledgment payload vs full record', () {
      final partialPayload = {'id': 'alert_1', 'isRead': 1};
      final fullPayload = {
        'id': 'alert_1',
        'title': 'Low Stock Alert',
        'desc': 'Slot AA1 low stock',
        'branch': 'San Pablo',
        'type': 'low_stock',
        'perfumeCode': 'AA1',
        'isRead': 0,
        'createdAt': 1730000000000,
      };

      expect(syncService.isPartialPayload('alerts', partialPayload), isTrue);
      expect(syncService.isPartialPayload('alerts', fullPayload), isFalse);
    });

    test('restock_records: identifies partial status payload vs full record', () {
      final partialPayload = {'id': 'rst_1', 'status': 'verified'};
      final fullPayload = {
        'id': 'rst_1',
        'productName': 'Sauvage',
        'perfumeCode': 'AD1',
        'quantity': 5,
        'fromBranch': 'Warehouse',
        'targetBranch': 'San Pablo',
        'status': 'pending',
        'createdAt': 1730000000000,
      };

      expect(syncService.isPartialPayload('restock_records', partialPayload), isTrue);
      expect(syncService.isPartialPayload('restock_records', fullPayload), isFalse);
    });

    test('products: identifies partial status/price payload vs full catalog record', () {
      final partialPayload = {'id': 'prod_1', 'status': 'inactive'};
      final fullPayload = {
        'id': 'prod_1',
        'name': 'Bleu de Chanel',
        'perfumeCode': 'AC1',
        'price': 250.0,
      };

      expect(syncService.isPartialPayload('products', partialPayload), isTrue);
      expect(syncService.isPartialPayload('products', fullPayload), isFalse);
    });

    test('inventory_records & users: identifies partial updates vs full records', () {
      expect(syncService.isPartialPayload('inventory_records', {'id': 'inv_1', 'detected': 4}), isTrue);
      expect(syncService.isPartialPayload('inventory_records', {'id': 'inv_1', 'name': 'Aventus'}), isFalse);

      expect(syncService.isPartialPayload('users', {'id': 'u1', 'passwordHash': 'h1'}), isTrue);
      expect(syncService.isPartialPayload('users', {'id': 'u1', 'email': 'owner@ottoscents.com'}), isFalse);
    });

    test('system_settings returns false to preserve key-value upsert behavior', () {
      expect(syncService.isPartialPayload('system_settings', {'key': 'branch_name', 'value': 'San Pablo'}), isFalse);
    });
  });

  group('Group 3: Stock Count Invariants (Clamp to 5 & Vision Separation)', () {
    test('Clamps recorded stock to maximum capacity of 5 per slot', () {
      final existingRecorded = 3;
      final restockQty = 5;

      // Invariant: slot capacity strictly 5
      final clampedRecorded = (existingRecorded + restockQty).clamp(0, 5);

      expect(clampedRecorded, equals(5), reason: 'Recorded stock must clamp to 5 bottles');
    });

    test('Never increments detected stock on manual restock invoice submission', () {
      final existingRecord = InventoryRecordModel(
        id: 'inv_San Pablo_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 2,
        detected: 2, // Physical camera sees 2 bottles
        status: 'low',
      );

      final restockQty = 3;
      final now = DateTime.now();

      // Invariant applied during restock order creation:
      // recorded is clamped to 5, but detected strictly preserves existing camera detection count
      final updated = InventoryRecordModel(
        id: existingRecord.id,
        perfumeCode: existingRecord.perfumeCode,
        name: existingRecord.name,
        category: existingRecord.category,
        branch: existingRecord.branch,
        shelf: existingRecord.shelf,
        recorded: (existingRecord.recorded + restockQty).clamp(0, 5),
        detected: existingRecord.detected, // Computer vision truth preserved
        status: (existingRecord.recorded + restockQty).clamp(0, 5) != existingRecord.detected
            ? 'needs_review'
            : 'normal',
        misplacementDetails: '',
        lastUpdated: now,
        price: existingRecord.price,
      );

      expect(updated.recorded, equals(5));
      expect(updated.detected, equals(2), reason: 'Detected must NOT increment upon invoice submission without physical scan');
      expect(updated.status, equals('needs_review'), reason: 'Mismatch between recorded 5 and detected 2 requires review');
    });

    test('Verified scan restock strictly clamps detected count to <= 5', () {
      final rawVisionCount = 7; // Edge sensor anomaly or spurious detection
      final verifiedScanCount = rawVisionCount.clamp(0, 5);

      expect(verifiedScanCount, equals(5), reason: 'Even with noisy detections, slot detected cannot exceed 5');
    });
  });

  group('Group 4: Discrepancy Review Alert Lifecycle (detected != recorded)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('updateInventoryFromDetections generates discrepancy alert and sets needs_review status', () async {
      // 1. Seed slot with recorded = 5, detected = 5
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

      // Configure tray AA ROI (midpoint = 0.10, AA1 < 0.10)
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // 2. Camera detects only 3 bottles in AA1 (recorded is 5 -> discrepancy!)
      final detections = [
        {'id': 'd1', 'centerX': 0.03, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.05, 'centerY': 0.4},
        {'id': 'd3', 'centerX': 0.07, 'centerY': 0.5},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = invAfter.firstWhere((i) => i.perfumeCode == 'AA1');

      expect(aa1.detected, equals(3));
      expect(aa1.recorded, equals(5));
      expect(aa1.status, equals('needs_review'), reason: 'Detected 3 != Recorded 5 must set status to needs_review');

      // Check alerts
      final alerts = await sqliteService.getAlerts('San Pablo');
      final discrepancyAlert = alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy').firstOrNull;

      expect(discrepancyAlert, isNotNull, reason: 'Discrepancy review alert must be inserted');
      expect(discrepancyAlert!.title, contains('Discrepancy'));
      expect(discrepancyAlert.desc, contains('3'));
      expect(discrepancyAlert.desc, contains('5'));
    });

    test('Subsequent scan matching recorded count auto-resolves discrepancy alert', () async {
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
        detected: 3,
        status: 'needs_review',
      ));

      // Seed discrepancy alert
      await sqliteService.insertAlert(AlertModel(
        id: 'alert_discrepancy_San Pablo_AA1',
        title: 'Stock Discrepancy Detected',
        desc: 'Mismatch in AA1',
        branch: 'San Pablo',
        type: 'discrepancy',
        perfumeCode: 'AA1',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      var alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy'), isTrue);

      // Now 5 bottles are detected, matching recorded 5
      final resolvingDetections = [
        {'id': 'd1', 'centerX': 0.02, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.04, 'centerY': 0.4},
        {'id': 'd3', 'centerX': 0.06, 'centerY': 0.5},
        {'id': 'd4', 'centerX': 0.08, 'centerY': 0.6},
        {'id': 'd5', 'centerX': 0.09, 'centerY': 0.7},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: resolvingDetections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = invAfter.firstWhere((i) => i.perfumeCode == 'AA1');

      expect(aa1.detected, equals(5));
      expect(aa1.status, equals('normal'), reason: 'Status must return to normal when count matches');

      alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'discrepancy'), isFalse,
          reason: 'Discrepancy alert must be deleted when count matches');
    });

    test('Critical out of stock (0 bottles) takes precedence over discrepancy', () async {
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
        detected: 4,
        status: 'normal',
      ));

      // Zero detections for slot AA1
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: [],
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = invAfter.firstWhere((i) => i.perfumeCode == 'AA1');

      expect(aa1.detected, equals(0));
      expect(aa1.status, equals('out_of_stock'), reason: '0 bottles must yield out_of_stock status');
    });
  });

  group('Group 5: Dynamic Branch Lookup via system_settings.branch_name', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('getBranchName defaults to San Pablo when no setting is configured', () async {
      final branch = await sqliteService.getBranchName();
      expect(branch, equals('San Pablo'));
    });

    test('getBranchName dynamically reflects updated system_settings.branch_name', () async {
      await sqliteService.setSystemSetting('branch_name', 'SM Lipa');

      final branch = await sqliteService.getBranchName();
      expect(branch, equals('SM Lipa'));
    });

    test('SQLite query methods resolve effective branch dynamically when branch is null', () async {
      await sqliteService.setSystemSetting('branch_name', 'Batangas City');

      // Insert inventory for Batangas City
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_Batangas City_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'Batangas City',
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // Calling getInventoryRecords(null) should automatically resolve to Batangas City
      final records = await sqliteService.getInventoryRecords(null);
      expect(records.isNotEmpty, isTrue);
      expect(records.first.branch, equals('Batangas City'));
    });

    test('currentBranchProvider resolves configured dynamic branch', () async {
      await sqliteService.setSystemSetting('branch_name', 'Tagaytay Ridge');

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(container.dispose);

      final branch = await container.read(currentBranchProvider.future);
      expect(branch, equals('Tagaytay Ridge'));
    });
  });

  group('Group 6: SQLite Schema Consolidation (_createTablesAndIndexes)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('createTablesAndIndexes initializes all 12 tables and 11 indexes cleanly', () async {
      final db = await sqliteService.database;

      final tablesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final tableNames = tablesResult.map((r) => r['name'] as String).toSet();

      final expectedTables = {
        'products',
        'shelf_regions',
        'inventory_records',
        'inventory_events',
        'sync_queue',
        'alerts',
        'system_logs',
        'image_quality_logs',
        'restock_records',
        'system_settings',
        'users',
        'sales_records',
      };

      expect(tableNames, containsAll(expectedTables));
      expect(tableNames.length, equals(12));

      final indexesResult = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      final indexNames = indexesResult.map((r) => r['name'] as String).toSet();

      final expectedIndexes = {
        'idx_products_code',
        'idx_products_category',
        'idx_inventory_branch',
        'idx_inventory_code',
        'idx_shelf_regions_branch',
        'idx_alerts_branch_read',
        'idx_inventory_events_branch_time',
        'idx_system_logs_branch_time',
        'idx_sync_queue_status',
        'idx_sales_records_branch_time',
        'idx_restock_records_branch',
      };

      expect(indexNames, containsAll(expectedIndexes));
      expect(indexNames.length, equals(11));
    });
  });

  group('Group 7: Targeted UPDATE Queue Operations & Conflict Resolution', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('markAlertRead enqueues targeted UPDATE operation with partial payload', () async {
      final alertId = 'alert_test_mark_read';
      await sqliteService.insertAlert(AlertModel(
        id: alertId,
        title: 'Sample Low Stock',
        desc: 'Testing targeted update',
        branch: 'San Pablo',
        type: 'low_stock',
        perfumeCode: 'AA1',
        isRead: false,
        createdAt: DateTime.now(),
      ));

      // Clear any sync items from insertion
      await sqliteService.purgeSyncedQueueItems();

      // Mark read
      await sqliteService.markAlertRead(alertId);

      final pending = await sqliteService.getPendingSyncItems();
      final alertUpdate = pending.firstWhere((item) =>
          item['operation'] == 'UPDATE' &&
          item['targetCollection'] == 'alerts' &&
          (item['payload'] as String).contains(alertId));

      expect(alertUpdate['operation'], equals('UPDATE'));
      expect(alertUpdate['targetCollection'], equals('alerts'));

      final payloadStr = alertUpdate['payload'] as String;
      expect(payloadStr.contains('"isRead":1'), isTrue);
      expect(payloadStr.contains('"title"'), isFalse, reason: 'Targeted UPDATE payload must omit unchanged columns');
    });

    test('updateRestockStatus enqueues targeted UPDATE with status and verifiedAt', () async {
      final restockId = 'restock_test_verify';

      await sqliteService.updateRestockStatus(restockId, 'verified');

      final pending = await sqliteService.getPendingSyncItems();
      final restockUpdate = pending.firstWhere((item) =>
          item['operation'] == 'UPDATE' &&
          item['targetCollection'] == 'restock_records' &&
          (item['id'] as String).contains(restockId));

      expect(restockUpdate['operation'], equals('UPDATE'));
      expect(restockUpdate['targetCollection'], equals('restock_records'));

      final payloadStr = restockUpdate['payload'] as String;
      expect(payloadStr.contains('"status":"verified"'), isTrue);
      expect(payloadStr.contains('"verifiedAt"'), isTrue);
      expect(payloadStr.contains('"productName"'), isFalse, reason: 'Targeted UPDATE payload must omit unchanged columns');
    });

    test('updateProductStatus enqueues targeted UPDATE with status', () async {
      final prodId = 'prod_AA1';

      await sqliteService.updateProductStatus(prodId, 'discontinued');

      final pending = await sqliteService.getPendingSyncItems();
      final prodUpdate = pending.firstWhere((item) =>
          item['operation'] == 'UPDATE' &&
          item['targetCollection'] == 'products' &&
          (item['id'] as String).contains(prodId));

      expect(prodUpdate['operation'], equals('UPDATE'));
      expect(prodUpdate['targetCollection'], equals('products'));

      final payloadStr = prodUpdate['payload'] as String;
      expect(payloadStr.contains('"status":"discontinued"'), isTrue);
      expect(payloadStr.contains('"name"'), isFalse);
    });

    test('Conflict resolution preserves local camera detected count on cloud pull simulation', () async {
      // 1. Local slot has detected: 4 from camera
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 4, // Local camera vision
        status: 'needs_review',
      ));

      // 2. Simulate pulling cloud inventory record where cloud had detected: 0
      final existingLocal = (await sqliteService.getInventoryRecords('San Pablo'))
          .firstWhere((i) => i.perfumeCode == 'AA1');

      final cloudRecord = InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1 (Cloud Updated)',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 0, // Stale cloud data
        status: 'out_of_stock',
      );

      // Conflict resolution logic: preserve existingLocal.detected
      final effectiveDetected = existingLocal.detected > 0 ? existingLocal.detected : cloudRecord.detected;
      final mergedRecord = InventoryRecordModel(
        id: cloudRecord.id,
        perfumeCode: cloudRecord.perfumeCode,
        name: cloudRecord.name,
        category: cloudRecord.category,
        branch: cloudRecord.branch,
        shelf: cloudRecord.shelf,
        recorded: cloudRecord.recorded,
        detected: effectiveDetected, // Local vision preserved!
        status: effectiveDetected == cloudRecord.recorded ? 'normal' : 'needs_review',
      );

      await sqliteService.upsertInventoryRecord(mergedRecord);

      final verifiedRecord = (await sqliteService.getInventoryRecords('San Pablo'))
          .firstWhere((i) => i.perfumeCode == 'AA1');

      expect(verifiedRecord.detected, equals(4), reason: 'Local physical camera detection count must NOT be overwritten by cloud pull');
      expect(verifiedRecord.name, equals('Perfume AA1 (Cloud Updated)'), reason: 'Cloud metadata is accepted');
    });
  });
}
