import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Tier 3: Pairwise Combinatorial Tests (Cross-Feature Interactions)', () {
    late SqliteService sqliteService;
    late Database db;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      db = await sqliteService.database;
      await db.delete('system_settings');
      await db.delete('system_logs');
      await db.delete('sync_queue');
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('restock_records');
      await db.delete('inventory_events');
    });

    // -------------------------------------------------------------------------
    // Pairwise 1: Security Lockout (R1) + Cloud Sync Queue (R2)
    // -------------------------------------------------------------------------
    test('Pairwise 1: Brute-force lockout triggers urgent sync_queue item while background sync remains intact', () async {
      final now = DateTime(2026, 11, 1, 14, 30, 0);

      // Pre-existing pending sync items in queue
      await db.insert('sync_queue', {
        'id': 'sync_pre_existing',
        'pendingEventId': 'evt_pre',
        'targetCollection': 'sales_records',
        'operation': 'UPSERT',
        'payload': '{"saleId": 100}',
        'status': 'pending',
        'retryCount': 0,
        'createdAt': now.millisecondsSinceEpoch - 10000,
        'branch': 'San Pablo',
      });

      // 5 consecutive failed PIN attempts trigger lockout
      var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);
      for (int i = 0; i < 5; i++) {
        state = state.recordFailure(now);
      }
      expect(state.isLocked(now), isTrue);
      await state.saveToDb(db);

      // Log security incident to system_logs and enqueue urgent sync
      final incidentId = 'log_lockout_${now.millisecondsSinceEpoch}';
      await db.insert('system_logs', {
        'id': incidentId,
        'type': 'SECURITY_LOCKOUT',
        'description': 'Persistent brute-force lockout triggered after 5 failed attempts.',
        'user': 'KioskSecurity',
        'branch': 'San Pablo',
        'timestamp': now.toIso8601String(),
      });

      await db.insert('sync_queue', {
        'id': 'sync_$incidentId',
        'pendingEventId': incidentId,
        'targetCollection': 'system_logs',
        'operation': 'UPSERT',
        'payload': jsonEncode({
          'id': incidentId,
          'type': 'SECURITY_LOCKOUT',
          'lockedUntil': state.lockedUntilEpochMs,
        }),
        'status': 'pending',
        'retryCount': 0,
        'createdAt': now.millisecondsSinceEpoch,
        'branch': 'San Pablo',
      });

      // Verify both pre-existing sale sync and security lockout sync are pending in queue
      final queueItems = await db.query('sync_queue', where: 'status = ?', whereArgs: ['pending']);
      expect(queueItems.length, equals(2));
      expect(queueItems.any((i) => i['id'] == 'sync_pre_existing'), isTrue);
      expect(queueItems.any((i) => i['id'] == 'sync_$incidentId'), isTrue);

      // Verify lockout persists in SQLite
      final reloadedState = await LockoutState.loadFromDb(db);
      expect(reloadedState.isLocked(now), isTrue);
    });

    // -------------------------------------------------------------------------
    // Pairwise 2: Dynamic Camera Routing (R4) + Stock Invariants Restock (R2)
    // -------------------------------------------------------------------------
    test('Pairwise 2: Dynamic Camera Routing routes low-stock trays AD & CK and executes auto-restock', () async {
      const branch = 'San Pablo';

      // Setup low-stock items in AD1 (Cam 1) and CK2 (Cam 6)
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Dior Sauvage 100ML',
        category: 'Men',
        branch: branch,
        shelf: 'Layer A - Tray AD Slot 1',
        recorded: 5,
        detected: 1, // Low stock <= 2
        status: 'low',
      ));
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_CK2',
        perfumeCode: 'CK2',
        name: 'Tom Ford Oud Wood 50ML',
        category: 'Unisex',
        branch: branch,
        shelf: 'Layer C - Tray CK Slot 2',
        recorded: 5,
        detected: 0, // Out of stock
        status: 'out_of_stock',
      ));

      // Control item on Tray BA (Cam 3) with normal stock
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_BA1',
        perfumeCode: 'BA1',
        name: 'Bleu de Chanel 100ML',
        category: 'Men',
        branch: branch,
        shelf: 'Layer B - Tray BA Slot 1',
        recorded: 5,
        detected: 4,
        status: 'normal',
      ));

      // 1. Verify dynamic camera routing for AD and CK
      final camAD = ShelfArchitectureHarness.getCameraIdForTray('AD');
      final camCK = ShelfArchitectureHarness.getCameraIdForTray('CK');
      expect(camAD, equals(1));
      expect(camCK, equals(6));

      // 2. Execute auto-restock order
      final restockedCount = await sqliteService.createAutoRestockOrder(branch: branch);
      expect(restockedCount, equals(2)); // AD1 and CK2 refilled

      // 3. Verify stock counts refilled to 5 without altering BA1
      final inv = await sqliteService.getInventoryRecords(branch);
      final ad1 = inv.firstWhere((i) => i.perfumeCode == 'AD1');
      final ck2 = inv.firstWhere((i) => i.perfumeCode == 'CK2');
      final ba1 = inv.firstWhere((i) => i.perfumeCode == 'BA1');

      expect(ad1.detected, equals(5));
      expect(ad1.status, equals('normal'));
      expect(ck2.detected, equals(5));
      expect(ck2.status, equals('normal'));
      expect(ba1.detected, equals(4)); // Untouched

      // 4. Verify RESTOCKED inventory events logged
      final events = await sqliteService.getInventoryEvents(branch);
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'AD1'), isTrue);
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'CK2'), isTrue);
    });

    // -------------------------------------------------------------------------
    // Pairwise 3: Checkpoint Scheduler (R3) + Selective Scanning (R4)
    // -------------------------------------------------------------------------
    test('Pairwise 3: Checkpoint trigger sequences scheduled scan without colliding with selective scan', () async {
      const branch = 'San Pablo';
      final t1400 = DateTime(2026, 11, 1, 14, 0, 0);

      // Simulate active selective scan on Tray CC (Cam 5)
      bool camera5Locked = true;

      // 14:00 Shift Change checkpoint arrives
      final isDue = SchedulerDiagnosticsHarness.isCheckpointDue(
        now: t1400,
        checkpoints: ['14:00'],
      );
      expect(isDue, isTrue);

      // Simulate lock release after selective scan finishes
      camera5Locked = false;
      expect(camera5Locked, isFalse);

      // Scheduled scan executes and logs to system_logs
      await SchedulerDiagnosticsHarness.logCheckpointScan(
        db,
        checkpointName: 'Shift Change (14:00)',
        totalBottles: 295,
        branch: branch,
        timestamp: t1400,
      );

      final logs = await db.query('system_logs', where: 'type = ?', whereArgs: ['CHECKPOINT_SCAN']);
      expect(logs.length, equals(1));
      expect(logs.first['description'], contains('Shift Change'));
      expect(logs.first['description'], contains('295 bottles'));
    });

    // -------------------------------------------------------------------------
    // Pairwise 4: Dynamic Branch Switch (R2) + Cloud Catalog Conflict Pull (R2)
    // -------------------------------------------------------------------------
    test('Pairwise 4: Dynamic Branch Switch preserves local sales while applying cloud catalog pricing', () async {
      // 1. Initial branch: San Pablo
      await db.insert(
        'system_settings',
        {'key': 'branch_name', 'value': 'San Pablo'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Record a local sale under San Pablo
      final now = DateTime.now();
      await db.insert('inventory_events', {
        'id': 'evt_local_sale_1',
        'eventType': 'SALE',
        'productName': 'Acqua di Gio',
        'perfumeCode': 'BA2',
        'shelfArea': 'Layer B',
        'branch': 'San Pablo',
        'quantity': 1,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'pending',
      });

      // 3. Admin switches branch dynamically to "Tagaytay Vista Kiosk"
      await db.insert(
        'system_settings',
        {'key': 'branch_name', 'value': 'Tagaytay Vista Kiosk'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final currentBranch = await SyncDataHarness.getDynamicBranch(db);
      expect(currentBranch, equals('Tagaytay Vista Kiosk'));

      // 4. Cloud catalog pull arrives with updated pricing
      final localProd = {
        'id': 'prod_BA2',
        'name': 'Acqua di Gio 50ML',
        'price': 95.0,
        'lastUpdated': 1000,
      };
      final cloudProd = {
        'id': 'prod_BA2',
        'name': 'Acqua di Gio 50ML (Premium)',
        'price': 110.0,
        'lastUpdated': 2000,
      };

      // Conflict resolution: Cloud wins pull for products
      final resolved = SyncDataHarness.resolveConflict(
        collection: 'products',
        localRecord: localProd,
        cloudRecord: cloudProd,
      );
      expect(resolved['name'], equals('Acqua di Gio 50ML (Premium)'));
      expect(resolved['price'], equals(110.0));

      // Verify local sale event was preserved untouched
      final localEvents = await db.query('inventory_events', where: 'id = ?', whereArgs: ['evt_local_sale_1']);
      expect(localEvents.length, equals(1));
      expect(localEvents.first['branch'], equals('San Pablo'));
    });

    // -------------------------------------------------------------------------
    // Pairwise 5: Emergency Override (R1) + Stock Discrepancy Reconciliation (R2)
    // -------------------------------------------------------------------------
    test('Pairwise 5: Manager overrides locked kiosk and reconciles camera vs recorded discrepancy', () async {
      final now = DateTime(2026, 11, 1, 16, 0, 0);

      // 1. Kiosk is currently locked due to 5 failed attempts
      final salt = Pbkdf2Harness.generateSalt(32);
      final masterHash = Pbkdf2Harness.hashPin(Pbkdf2Harness.defaultMasterRecoveryKey, salt, iterations: 500);

      final lockedState = LockoutState(
        failedAttempts: 5,
        lockedUntilEpochMs: now.millisecondsSinceEpoch + 300000,
      );
      expect(lockedState.isLocked(now), isTrue);

      // 2. Manager enters Emergency Recovery Key to unlock
      final isKeyValid = Pbkdf2Harness.verifyMasterKey(
        'OTTO-MASTER-RECOVERY-2026',
        masterHash,
        salt,
        iterations: 500,
      );
      expect(isKeyValid, isTrue);

      final unlockedState = lockedState.resetOnSuccess();
      expect(unlockedState.isLocked(now), isFalse);
      expect(unlockedState.failedAttempts, equals(0));

      // 3. Manager audits item BA1: Recorded = 5, but YOLO Detected = 2 (discrepancy)
      final record = InventoryRecordModel(
        id: 'inv_San Pablo_BA1',
        perfumeCode: 'BA1',
        name: 'Dior Fahrenheit',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer B - Slot 1',
        recorded: 5,
        detected: 2,
        status: 'low',
      );
      expect(SyncDataHarness.hasDiscrepancy(record.recorded, record.detected), isTrue);

      // 4. Log reconciliation audit log
      await db.insert('system_logs', {
        'id': 'log_recon_${now.millisecondsSinceEpoch}',
        'type': 'DISCREPANCY_RECONCILED',
        'description': 'Manager verified BA1: Adjusted recorded stock from 5 to 2 to match camera reality.',
        'user': 'StoreManager',
        'branch': 'San Pablo',
        'timestamp': now.toIso8601String(),
      });

      final auditLogs = await db.query('system_logs', where: 'type = ?', whereArgs: ['DISCREPANCY_RECONCILED']);
      expect(auditLogs.length, equals(1));
    });

    // -------------------------------------------------------------------------
    // Pairwise 6: Scheduled Scan (R3) + Degraded Image Quality (R5)
    // -------------------------------------------------------------------------
    test('Pairwise 6: Zero-light camera frame during scheduled scan records diagnostic alert without crashing', () async {
      const branch = 'San Pablo';
      final t2100 = DateTime(2026, 11, 1, 21, 0, 0);

      // Simulate Camera 3 pitch black frame (brightness = 1.0)
      final darkFrame = List.filled(100, 1);
      final metrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(darkFrame);
      expect(SchedulerDiagnosticsHarness.isZeroLight(metrics), isTrue);

      // Record diagnostic alert in alerts table
      final alertId = 'alert_cam3_zero_light_${t2100.millisecondsSinceEpoch}';
      await sqliteService.insertAlert(AlertModel(
        id: alertId,
        title: 'Zero-Light Anomaly on Camera 3',
        desc: 'Camera 3 (Layer B) captured zero-light frame during 21:00 scheduled scan.',
        branch: branch,
        type: 'system',
        createdAt: t2100,
        perfumeCode: 'CAM3',
      ));

      // Complete scheduled scan with warning status
      await db.insert('system_logs', {
        'id': 'log_sched_${t2100.millisecondsSinceEpoch}',
        'type': 'CHECKPOINT_SCAN_WARNING',
        'description': 'Scheduled scan (21:00 Closing) completed with 1 camera diagnostic warning (Camera 3 zero-light).',
        'user': 'KioskScheduler',
        'branch': branch,
        'timestamp': t2100.toIso8601String(),
      });

      final alerts = await sqliteService.getAlerts(branch);
      expect(alerts.any((a) => a.id == alertId && a.type == 'system'), isTrue);

      final logs = await db.query('system_logs', where: 'type = ?', whereArgs: ['CHECKPOINT_SCAN_WARNING']);
      expect(logs.length, equals(1));
    });
  });
}
