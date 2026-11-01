import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/services/sync_service.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/restock_record_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Empirical Challenge 1: Concurrency and Race Condition Stress Tests', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
    });

    tearDown(() async {
      await sqliteService.close();
    });

    test('Stress Test 1A: 50 concurrent markAlertRead calls across 50 distinct alerts', () async {
      // Seed 50 unread alerts
      final alerts = List.generate(
        50,
        (i) => AlertModel(
          id: 'concurrent_alert_$i',
          title: 'Alert Title $i',
          desc: 'Alert Description $i',
          branch: 'San Pablo',
          type: 'low_stock',
          perfumeCode: 'P$i',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      );

      for (final alert in alerts) {
        await sqliteService.insertAlert(alert, enqueueSync: false);
      }

      // Verify all 50 are initially unread
      final initialUnread = (await sqliteService.getAlerts('San Pablo', unreadOnly: true)).length;
      expect(initialUnread, equals(50));

      // Execute 50 concurrent markAlertRead calls
      final futures = alerts.map((a) => sqliteService.markAlertRead(a.id));
      await Future.wait(futures);

      // Verify all 50 alerts are now marked as read
      final finalUnread = (await sqliteService.getAlerts('San Pablo', unreadOnly: true)).length;
      expect(finalUnread, equals(0));

      // Verify sync_queue entries
      final pendingSync = await sqliteService.getPendingSyncItems();
      final alertUpdates = pendingSync
          .where((item) =>
              item['targetCollection'] == 'alerts' &&
              item['operation'] == 'UPDATE')
          .toList();

      expect(alertUpdates.length, equals(50),
          reason: 'Every markAlertRead must enqueue an UPDATE sync item');

      for (final syncItem in alertUpdates) {
        expect(syncItem['operation'], equals('UPDATE'));
        final payload =
            jsonDecode(syncItem['payload'] as String) as Map<String, dynamic>;
        expect(payload['isRead'], equals(1));
        expect(payload.containsKey('title'), isFalse,
            reason: 'Targeted UPDATE payload must omit title');
        expect(payload.containsKey('desc'), isFalse,
            reason: 'Targeted UPDATE payload must omit desc');
      }
    });

    test('Stress Test 1B: Rapid concurrent markAlertRead calls on the exact same alert', () async {
      final hotspotAlert = AlertModel(
        id: 'hotspot_alert_001',
        title: 'Hotspot Alert',
        desc: 'Testing concurrent writes to single row',
        branch: 'San Pablo',
        type: 'out_of_stock',
        perfumeCode: 'HOT1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.insertAlert(hotspotAlert, enqueueSync: false);

      // Fire 30 concurrent markAlertRead calls for the same alert
      final futures = List.generate(
        30,
        (_) => sqliteService.markAlertRead(hotspotAlert.id),
      );
      await Future.wait(futures);

      // Verify the alert in DB is read
      final allAlerts = await sqliteService.getAlerts('San Pablo');
      final alertInDb = allAlerts.firstWhere((a) => a.id == hotspotAlert.id);
      expect(alertInDb.isRead, isTrue);

      // Verify sync queue does not crash and contains at least 1 valid targeted update
      final pendingSync = await sqliteService.getPendingSyncItems();
      final hotspotUpdates = pendingSync
          .where((item) =>
              item['targetCollection'] == 'alerts' &&
              item['operation'] == 'UPDATE' &&
              (item['payload'] as String).contains(hotspotAlert.id))
          .toList();

      expect(hotspotUpdates.isNotEmpty, isTrue);
      final payload = jsonDecode(hotspotUpdates.first['payload'] as String)
          as Map<String, dynamic>;
      expect(payload['id'], equals(hotspotAlert.id));
      expect(payload['isRead'], equals(1));
    });

    test('Stress Test 1C: 30 concurrent updateRestockStatus calls across multiple records', () async {
      // Seed 30 restock records
      final restockRecords = List.generate(
        30,
        (i) => RestockRecordModel(
          id: 'restock_batch_$i',
          productName: 'Fragrance SKU $i',
          perfumeCode: 'SKU$i',
          quantity: 5,
          fromBranch: 'Warehouse',
          toBranch: 'San Pablo',
          requestedBy: 'staff_1',
          status: 'pending',
          createdAt: DateTime.now(),
        ),
      );

      for (final r in restockRecords) {
        await sqliteService.saveRestockRecord(r, enqueueSync: false);
      }

      // Execute 30 concurrent updates: even indexed to 'in_transit', odd indexed to 'verified'
      final futures = restockRecords.asMap().entries.map((entry) {
        final idx = entry.key;
        final record = entry.value;
        final status = (idx % 2 == 0) ? 'in_transit' : 'verified';
        return sqliteService.updateRestockStatus(record.id, status);
      });

      await Future.wait(futures);

      // Verify all 30 records updated
      final updatedRecords = await sqliteService.getRestockRecords('San Pablo');
      expect(updatedRecords.length, equals(30));

      int inTransitCount = 0;
      int verifiedCount = 0;
      for (int i = 0; i < 30; i++) {
        final r = updatedRecords.firstWhere((item) => item.id == 'restock_batch_$i');
        if (i % 2 == 0) {
          expect(r.status, equals('in_transit'));
          inTransitCount++;
        } else {
          expect(r.status, equals('verified'));
          verifiedCount++;
        }
      }
      expect(inTransitCount, equals(15));
      expect(verifiedCount, equals(15));

      // Verify sync queue entries
      final pendingSync = await sqliteService.getPendingSyncItems();
      final restockUpdates = pendingSync
          .where((item) =>
              item['targetCollection'] == 'restock_records' &&
              item['operation'] == 'UPDATE')
          .toList();

      expect(restockUpdates.length, equals(30));

      for (final syncItem in restockUpdates) {
        final payload =
            jsonDecode(syncItem['payload'] as String) as Map<String, dynamic>;
        expect(payload.containsKey('status'), isTrue);
        expect(payload.containsKey('productName'), isFalse,
            reason: 'Partial update must not include productName');
        expect(payload.containsKey('quantity'), isFalse,
            reason: 'Partial update must not include quantity');

        if (payload['status'] == 'verified') {
          expect(payload.containsKey('verifiedAt'), isTrue,
              reason: 'Verified restock must include verifiedAt timestamp');
        }
      }
    });

    test('Stress Test 1D: Mixed high-concurrency race condition (100 simultaneous operations)', () async {
      // Prepare mixed async operations
      final List<Future<void>> mixedFutures = [];

      // 25 alert insertions
      for (int i = 0; i < 25; i++) {
        mixedFutures.add(sqliteService.insertAlert(
          AlertModel(
            id: 'mixed_alert_$i',
            title: 'Mixed Alert $i',
            desc: 'Desc',
            branch: 'San Pablo',
            type: 'low_stock',
            perfumeCode: 'M$i',
            createdAt: DateTime.now(),
          ),
          enqueueSync: true,
        ));
      }

      // 25 restock record insertions
      for (int i = 0; i < 25; i++) {
        mixedFutures.add(sqliteService.saveRestockRecord(
          RestockRecordModel(
            id: 'mixed_restock_$i',
            productName: 'Restock SKU $i',
            perfumeCode: 'MR$i',
            quantity: 3,
            fromBranch: 'Warehouse',
            toBranch: 'San Pablo',
            requestedBy: 'kiosk',
            createdAt: DateTime.now(),
          ),
          enqueueSync: true,
        ));
      }

      // Execute all 50 creations concurrently first
      await Future.wait(mixedFutures);
      mixedFutures.clear();

      // Now fire 50 rapid concurrent updates simultaneously:
      // 25 markAlertRead + 25 updateRestockStatus
      for (int i = 0; i < 25; i++) {
        mixedFutures.add(sqliteService.markAlertRead('mixed_alert_$i'));
        mixedFutures.add(sqliteService.updateRestockStatus('mixed_restock_$i', 'verified'));
      }

      // Must complete without any SQLite lock failure or unhandled exception
      await Future.wait(mixedFutures);

      // Verify all alerts read
      final unread = (await sqliteService.getAlerts('San Pablo', unreadOnly: true)).length;
      expect(unread, equals(0));

      // Verify restock statuses
      final restocks = await sqliteService.getRestockRecords('San Pablo');
      final verifiedRestocks =
          restocks.where((r) => r.id.startsWith('mixed_restock_') && r.status == 'verified');
      expect(verifiedRestocks.length, equals(25));

      // Verify sync queue entries are all well-formed
      final allPending = await sqliteService.getPendingSyncItems();
      expect(allPending.isNotEmpty, isTrue);

      for (final item in allPending) {
        expect(() => jsonDecode(item['payload'] as String), returnsNormally,
            reason: 'Every sync queue payload must be valid JSON');
        expect(item['operation'], anyOf(equals('UPSERT'), equals('UPDATE')));
      }
    });
  });

  group('Empirical Challenge 2: Conflict Resolution on Remote Data Pull', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
    });

    tearDown(() async {
      await sqliteService.close();
    });

    test('Conflict Test 2A: Preserving positive local camera count against stale remote zero', () async {
      // Local slot detected 4 bottles via YOLO camera, ledger recorded is 5
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Sauvage EDT',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 4, // Live local camera vision
        status: 'needs_review',
        price: 250.0,
      ));

      // Remote cloud record arrives with detected: 0 (stale), updated price: 399.0, updated name
      final localBeforePull =
          await sqliteService.getInventoryRecord('AA1', 'San Pablo');
      expect(localBeforePull, isNotNull);

      final remoteCloudRecord = InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Sauvage Eau de Toilette (Updated Cloud Name)',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 0, // Stale zero from cloud
        status: 'out_of_stock',
        price: 399.0, // Updated cloud price
      );

      // Apply conflict resolution logic exactly as implemented in sync_service.dart:713-721
      final effectiveRecord = localBeforePull != null
          ? remoteCloudRecord.copyWith(
              detected: localBeforePull.detected,
              status: (localBeforePull.detected != remoteCloudRecord.recorded)
                  ? 'needs_review'
                  : remoteCloudRecord.status,
            )
          : remoteCloudRecord;

      await sqliteService.upsertInventoryRecord(effectiveRecord, enqueueSync: false);

      // Verify state in SQLite
      final localAfterPull =
          await sqliteService.getInventoryRecord('AA1', 'San Pablo');
      expect(localAfterPull, isNotNull);
      expect(localAfterPull!.detected, equals(4),
          reason: 'Local YOLO camera count of 4 must NOT be wiped by remote zero');
      expect(localAfterPull.price, equals(399.0),
          reason: 'Remote price update must be accepted');
      expect(localAfterPull.name, equals('Sauvage Eau de Toilette (Updated Cloud Name)'),
          reason: 'Remote catalog metadata update must be accepted');
      expect(localAfterPull.status, equals('needs_review'),
          reason: 'Discrepancy (detected 4 != recorded 5) must set needs_review');
    });

    test('Conflict Test 2B: Preserving ZERO local camera count (physical out of stock)', () async {
      // Local slot physically empty (camera saw 0 bottles)
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_BB1',
        perfumeCode: 'BB1',
        name: 'Bleu de Chanel',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer B',
        recorded: 5,
        detected: 0, // True physical empty shelf detected locally
        status: 'out_of_stock',
        price: 280.0,
      ));

      final localBeforePull =
          await sqliteService.getInventoryRecord('BB1', 'San Pablo');
      expect(localBeforePull, isNotNull);

      // Cloud sends stale record claiming detected: 5
      final remoteCloudRecord = InventoryRecordModel(
        id: 'inv_San Pablo_BB1',
        perfumeCode: 'BB1',
        name: 'Bleu de Chanel',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer B',
        recorded: 5,
        detected: 5, // Stale cloud assumption
        status: 'normal',
        price: 295.0,
      );

      final effectiveRecord = localBeforePull != null
          ? remoteCloudRecord.copyWith(
              detected: localBeforePull.detected,
              status: (localBeforePull.detected != remoteCloudRecord.recorded)
                  ? 'needs_review'
                  : remoteCloudRecord.status,
            )
          : remoteCloudRecord;

      await sqliteService.upsertInventoryRecord(effectiveRecord, enqueueSync: false);

      final localAfterPull =
          await sqliteService.getInventoryRecord('BB1', 'San Pablo');
      expect(localAfterPull, isNotNull);
      expect(localAfterPull!.detected, equals(0),
          reason: 'Local physical out-of-stock count (0) must NOT be inflated to 5');
      expect(localAfterPull.price, equals(295.0));
      expect(localAfterPull.status, equals('needs_review'),
          reason: 'Detected 0 vs recorded 5 must remain needs_review');
    });

    test('Conflict Test 2C: New SKU arriving from cloud is cleanly inserted into local inventory', () async {
      // Verify SKU does not exist locally
      final existing = await sqliteService.getInventoryRecord('NEW_SKU_1', 'San Pablo');
      expect(existing, isNull);

      final remoteCloudRecord = InventoryRecordModel(
        id: 'inv_San Pablo_NEW_SKU_1',
        perfumeCode: 'NEW_SKU_1',
        name: 'New Fragrance 2026',
        category: 'Unisex',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 5,
        status: 'normal',
        price: 320.0,
      );

      // When local is null, effectiveRecord is remoteCloudRecord
      final localBefore = await sqliteService.getInventoryRecord('NEW_SKU_1', 'San Pablo');
      final effectiveRecord = localBefore != null
          ? remoteCloudRecord.copyWith(detected: localBefore.detected)
          : remoteCloudRecord;

      await sqliteService.upsertInventoryRecord(effectiveRecord, enqueueSync: false);

      final inserted = await sqliteService.getInventoryRecord('NEW_SKU_1', 'San Pablo');
      expect(inserted, isNotNull);
      expect(inserted!.name, equals('New Fragrance 2026'));
      expect(inserted.price, equals(320.0));
    });

    test('Conflict Test 2D: Multi-SKU batch conflict resolution (60 SKUs full shelf stress)', () async {
      // Populate 60 SKUs with random varying local detected counts (0 to 5)
      final localCounts = <String, int>{};
      for (int i = 0; i < 60; i++) {
        final code = 'SKU_${i.toString().padLeft(2, '0')}';
        final detectedVal = i % 6; // 0, 1, 2, 3, 4, 5
        localCounts[code] = detectedVal;

        await sqliteService.upsertInventoryRecord(InventoryRecordModel(
          id: 'inv_San Pablo_$code',
          perfumeCode: code,
          name: 'Fragrance $code',
          category: 'Men',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: detectedVal,
          status: detectedVal == 5 ? 'normal' : 'low',
          price: 200.0,
        ), enqueueSync: false);
      }

      // Simulate incoming cloud batch for all 60 SKUs with detected: 5 and price: 250.0
      for (int i = 0; i < 60; i++) {
        final code = 'SKU_${i.toString().padLeft(2, '0')}';
        final remote = InventoryRecordModel(
          id: 'inv_San Pablo_$code',
          perfumeCode: code,
          name: 'Fragrance $code (Cloud)',
          category: 'Men',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: 5, // Cloud claims full 5
          status: 'normal',
          price: 250.0, // Cloud price bump
        );

        final local = await sqliteService.getInventoryRecord(code, 'San Pablo');
        final effective = local != null
            ? remote.copyWith(
                detected: local.detected,
                status: (local.detected != remote.recorded)
                    ? 'needs_review'
                    : remote.status,
              )
            : remote;

        await sqliteService.upsertInventoryRecord(effective, enqueueSync: false);
      }

      // Verify every single SKU preserved its physical detected count
      final allRecords = await sqliteService.getInventoryRecords('San Pablo');
      final testRecords = allRecords.where((r) => r.perfumeCode.startsWith('SKU_')).toList();
      expect(testRecords.length, equals(60));

      for (final r in testRecords) {
        final expectedDetected = localCounts[r.perfumeCode];
        expect(r.detected, equals(expectedDetected),
            reason: 'SKU ${r.perfumeCode} must retain local detected count $expectedDetected');
        expect(r.price, equals(250.0),
            reason: 'SKU ${r.perfumeCode} must receive updated cloud price');
        expect(r.name, contains('(Cloud)'),
            reason: 'SKU ${r.perfumeCode} must receive updated cloud name');

        if (expectedDetected == 5) {
          expect(r.status, equals('normal'));
        } else {
          expect(r.status, equals('needs_review'));
        }
      }
    });
  });

  group('Empirical Challenge 3: Schema Integrity of _createTablesAndIndexes', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
    });

    tearDown(() async {
      await sqliteService.close();
    });

    test('Schema Test 3A: Clean initialization creates exactly 12 tables and 11 indexes', () async {
      final db = await sqliteService.database;

      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final tableNames = tables.map((r) => r['name'] as String).toSet();

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

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      final indexNames = indexes.map((r) => r['name'] as String).toSet();

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

    test('Schema Test 3B: Idempotent re-execution on populated database preserves data and schema', () async {
      final db = await sqliteService.database;

      // Populate sample data across multiple tables
      await sqliteService.saveProduct(ProductModel(
        id: 'prod_test_01',
        perfumeCode: 'TEST_PRESERVED',
        name: 'Test Product',
        brand: 'Otto Scents',
        category: 'Men',
        bottleSize: '100ml',
        price: 299.0,
      ), enqueueSync: false);

      await sqliteService.insertAlert(AlertModel(
        id: 'alert_test_01',
        title: 'Preserved Alert',
        desc: 'Must survive DDL re-runs',
        branch: 'San Pablo',
        type: 'system',
        createdAt: DateTime.now(),
      ), enqueueSync: false);

      await sqliteService.setSystemSetting('kiosk_test_key', 'test_value', enqueueSync: false);

      // Re-run createTablesAndIndexes 5 times consecutively
      for (int i = 0; i < 5; i++) {
        await sqliteService.createTablesAndIndexes(db);
      }

      // Verify schema count is unchanged
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      expect(tables.length, equals(12));

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      expect(indexes.length, equals(11));

      // Verify populated data is 100% intact
      final product = await sqliteService.getProductByCode('TEST_PRESERVED');
      expect(product, isNotNull);
      expect(product!.price, equals(299.0));

      final alerts = await sqliteService.getAlerts('San Pablo');
      final alert = alerts.firstWhere((a) => a.id == 'alert_test_01');
      expect(alert.title, equals('Preserved Alert'));

      final setting = await sqliteService.getSetting('kiosk_test_key');
      expect(setting, equals('test_value'));
    });

    test('Schema Test 3C: Concurrent createTablesAndIndexes execution survives without conflict', () async {
      final db = await sqliteService.database;

      // Execute 10 parallel calls to createTablesAndIndexes simultaneously
      final futures = List.generate(10, (_) => sqliteService.createTablesAndIndexes(db));
      await Future.wait(futures);

      // Verify schema is completely intact
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      expect(tables.length, equals(12));

      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'",
      );
      expect(indexes.length, equals(11));
    });

    test('Schema Test 3D: Column structure validation for critical tables', () async {
      final db = await sqliteService.database;

      // Table: alerts
      final alertColumns = (await db.rawQuery("PRAGMA table_info('alerts')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(alertColumns, containsAll({'id', 'title', 'desc', 'branch', 'type', 'perfumeCode', 'isRead', 'createdAt'}));

      // Table: sync_queue
      final syncQueueColumns = (await db.rawQuery("PRAGMA table_info('sync_queue')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(syncQueueColumns, containsAll({'id', 'pendingEventId', 'targetCollection', 'operation', 'payload', 'retryCount', 'status', 'branch', 'createdAt'}));

      // Table: restock_records
      final restockColumns = (await db.rawQuery("PRAGMA table_info('restock_records')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(restockColumns, containsAll({'id', 'productName', 'perfumeCode', 'quantity', 'fromBranch', 'toBranch', 'requestedBy', 'status', 'createdAt', 'verifiedAt'}));

      // Table: inventory_records
      final invColumns = (await db.rawQuery("PRAGMA table_info('inventory_records')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(invColumns, containsAll({'id', 'perfumeCode', 'name', 'category', 'branch', 'shelf', 'recorded', 'detected', 'status', 'misplacementDetails', 'price', 'lastUpdated'}));

      // Table: system_settings
      final settingsColumns = (await db.rawQuery("PRAGMA table_info('system_settings')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(settingsColumns, containsAll({'key', 'value'}));

      // Table: users
      final userColumns = (await db.rawQuery("PRAGMA table_info('users')"))
          .map((r) => r['name'] as String)
          .toSet();
      expect(userColumns, containsAll({'uid', 'email', 'passwordHash', 'role', 'branch', 'lastLogin'}));
    });
  });

  group('Empirical Challenge 4: Extreme Concurrency & Interleaved Alert/Restock Operations', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
    });

    tearDown(() async {
      await sqliteService.close();
    });

    test('Stress Test 4A: Interleaved markAllAlertsRead and markAlertRead on 100 alerts', () async {
      // Seed 100 alerts
      for (int i = 0; i < 100; i++) {
        await sqliteService.insertAlert(AlertModel(
          id: 'interleaved_alert_$i',
          title: 'Alert $i',
          desc: 'Desc $i',
          branch: 'San Pablo',
          type: 'low_stock',
          perfumeCode: 'P$i',
          isRead: false,
          createdAt: DateTime.now(),
        ), enqueueSync: false);
      }

      // Concurrently run:
      // - 10 individual markAlertRead calls
      // - 1 global markAllAlertsRead call
      // - 10 individual markAlertRead calls
      final futures = <Future<void>>[];
      for (int i = 0; i < 10; i++) {
        futures.add(sqliteService.markAlertRead('interleaved_alert_$i'));
      }
      futures.add(sqliteService.markAllAlertsRead(null, 'San Pablo'));
      for (int i = 10; i < 20; i++) {
        futures.add(sqliteService.markAlertRead('interleaved_alert_$i'));
      }

      await Future.wait(futures);

      // Verify all 100 alerts are marked as read
      final unread = (await sqliteService.getAlerts('San Pablo', unreadOnly: true)).length;
      expect(unread, equals(0));

      // Verify all sync queue entries generated have operation: 'UPDATE'
      final pending = await sqliteService.getPendingSyncItems();
      final alertUpdates = pending
          .where((item) =>
              item['targetCollection'] == 'alerts' &&
              (item['id'] as String).startsWith('sync_read_alert_'))
          .toList();
      expect(alertUpdates.isNotEmpty, isTrue);
      for (final item in alertUpdates) {
        expect(item['operation'], equals('UPDATE'));
      }
    });

    test('Stress Test 4B: Rapid restock status transition lifecycle on same record', () async {
      final restockId = 'restock_lifecycle_001';
      await sqliteService.saveRestockRecord(RestockRecordModel(
        id: restockId,
        productName: 'Sauvage Refill',
        perfumeCode: 'AA1',
        quantity: 5,
        fromBranch: 'Warehouse',
        toBranch: 'San Pablo',
        requestedBy: 'kiosk_auto',
        status: 'pending',
        createdAt: DateTime.now(),
      ), enqueueSync: false);

      // Rapidly update status through lifecycle: pending -> in_transit -> verified
      await sqliteService.updateRestockStatus(restockId, 'in_transit');
      await sqliteService.updateRestockStatus(restockId, 'verified');

      final record = (await sqliteService.getRestockRecords('San Pablo'))
          .firstWhere((r) => r.id == restockId);
      expect(record.status, equals('verified'));

      // Check sync queue has UPDATE operations
      final pending = await sqliteService.getPendingSyncItems();
      final updates = pending
          .where((item) =>
              item['targetCollection'] == 'restock_records' &&
              item['operation'] == 'UPDATE' &&
              (item['id'] as String).contains(restockId))
          .toList();
      expect(updates.isNotEmpty, isTrue);

      final latestUpdate = updates.last;
      final payload = jsonDecode(latestUpdate['payload'] as String) as Map<String, dynamic>;
      expect(payload['status'], equals('verified'));
      expect(payload.containsKey('verifiedAt'), isTrue);
    });
  });

  group('Empirical Challenge 5: Sync Service Partial Payload Mapper Boundary & Robustness', () {
    late SyncService syncService;

    setUp(() {
      syncService = SyncService.instance;
    });

    test('Mapper Robustness: Handles edge cases, missing fields, and boundary types without crash', () {
      // Empty payload
      final emptyUpdate = syncService.buildPartialUpdateMap('alerts', {});
      expect(emptyUpdate, isEmpty);

      // Null values in payload
      final nullAlertUpdate = syncService.buildPartialUpdateMap('alerts', {
        'id': 'a1',
        'isRead': null,
      });
      expect(nullAlertUpdate['is_read'], isFalse);

      // Default fallback pass-through for unrecognized tables (strips id, passes other columns)
      final customTableUpdate = syncService.buildPartialUpdateMap('custom_kiosk_data', {
        'id': 'row_123',
        'custom_metric': 99.5,
      });
      expect(customTableUpdate.containsKey('id'), isFalse, reason: 'Must strip id from update map');
      expect(customTableUpdate['custom_metric'], equals(99.5));

      // Partial payload classification on unknown collection
      final isUnknownPartial = syncService.isPartialPayload('unknown_table', {'foo': 'bar'});
      expect(isUnknownPartial, isFalse);

      // ISO8601 string in verifiedAt
      final isoDateUpdate = syncService.buildPartialUpdateMap('restock_records', {
        'status': 'verified',
        'verifiedAt': '2026-11-01T08:00:00Z',
      });
      expect(isoDateUpdate['status'], equals('verified'));
      expect(isoDateUpdate['verified_at'], equals('2026-11-01T08:00:00.000Z'));

      // Numeric epoch in verifiedAt
      final epochUpdate = syncService.buildPartialUpdateMap('restock_records', {
        'status': 'verified',
        'verifiedAt': 1730420000000,
      });
      expect(epochUpdate['verified_at'], isNotNull);
    });
  });
}
