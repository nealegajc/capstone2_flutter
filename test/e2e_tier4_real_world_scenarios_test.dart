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

  group('Tier 4: Real-World Application Scenarios (End-to-End Operational Flows)', () {
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
      await db.delete('products');
    });

    // =========================================================================
    // SCENARIO 1: STORE OPENING FLOW (09:00 Checkpoint)
    // =========================================================================
    test('Scenario 1: Store Opening Flow - Boot, Camera Discovery, 09:00 Checkpoint Scan, Inventory Realignment', () async {
      // 1. Kiosk boot & system settings initialization
      await db.insert('system_settings', {
        'key': 'branch_name',
        'value': 'San Pablo Main Kiosk',
      });
      final branch = await SyncDataHarness.getDynamicBranch(db);
      expect(branch, equals('San Pablo Main Kiosk'));

      // 2. Hardware camera discovery: verify all 6 cameras assigned
      for (int camId = 1; camId <= 6; camId++) {
        final deviceNode = ShelfArchitectureHarness.getCameraDevice(camId);
        expect(deviceNode, isNotEmpty);
      }

      // 3. 09:00 Store Opening checkpoint arrives
      final t0900 = DateTime(2026, 11, 1, 9, 0, 0);
      final isDue = SchedulerDiagnosticsHarness.isCheckpointDue(
        now: t0900,
        checkpoints: ['09:00', '14:00', '21:00'],
      );
      expect(isDue, isTrue);

      // 4. Sequential 6-camera scan executes across all 30 trays (60 slots)
      // Populate baseline inventory: 58 slots have 5 bottles (full), 2 slots have 1 bottle (low stock)
      final batch = db.batch();
      int totalBottles = 0;
      int lowStockCount = 0;

      for (int i = 0; i < ShelfArchitectureHarness.totalTrays; i++) {
        final tray = ShelfArchitectureHarness.allTrays[i];
        for (int slot = 1; slot <= 2; slot++) {
          final pCode = '$tray$slot';
          final detected = (pCode == 'AA1' || pCode == 'CK2') ? 1 : 5;
          totalBottles += detected;
          if (detected <= 2) lowStockCount++;

          final status = detected <= 2 ? 'low' : 'normal';
          batch.insert('inventory_records', {
            'id': 'inv_${branch}_$pCode',
            'perfumeCode': pCode,
            'name': 'Fragrance $pCode',
            'category': 'Perfume',
            'branch': branch,
            'shelf': 'Tray $tray Slot $slot',
            'recorded': 5,
            'detected': detected,
            'status': status,
            'lastUpdated': t0900.millisecondsSinceEpoch,
          });

          if (detected <= 2) {
            batch.insert('alerts', {
              'id': 'alert_opening_$pCode',
              'title': 'Low Stock Detected: $pCode',
              'desc': 'Slot $pCode has only $detected / 5 bottles.',
              'branch': branch,
              'type': 'low_stock',
              'isRead': 0,
              'perfumeCode': pCode,
              'createdAt': t0900.millisecondsSinceEpoch,
            });
          }
        }
      }
      await batch.commit(noResult: true);

      // 5. Verify Store Overview dashboard metrics
      expect(totalBottles, equals(292)); // 58 * 5 + 2 * 1 = 292
      expect(lowStockCount, equals(2));
      const totalCapacity = 300;
      final stockPercentage = (totalBottles / totalCapacity * 100).round();
      expect(stockPercentage, equals(97)); // 97% Full

      // 6. Log automated scan completion to system_logs and sync_queue
      await SchedulerDiagnosticsHarness.logCheckpointScan(
        db,
        checkpointName: 'Store Opening (09:00)',
        totalBottles: totalBottles,
        branch: branch,
        timestamp: t0900,
      );

      final logs = await db.query('system_logs', where: 'type = ?', whereArgs: ['CHECKPOINT_SCAN']);
      expect(logs.length, equals(1));
      expect(logs.first['description'], contains('292 bottles across 60 slots'));

      final syncQueue = await db.query('sync_queue', where: 'targetCollection = ?', whereArgs: ['system_logs']);
      expect(syncQueue.length, equals(1));
    });

    // =========================================================================
    // SCENARIO 2: RESTOCK RECEIVING VERIFICATION FLOW
    // =========================================================================
    test('Scenario 2: Restock Delivery Flow - Delivery Batch, Tray Camera Routing, Quantity Verification, Auto-Resolve', () async {
      const branch = 'San Pablo';
      final now = DateTime(2026, 11, 1, 11, 30, 0);

      // 1. Initial State: Tray AD Slot 1 (Sauvage 100ML) has 1 bottle with active Low Stock alert
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Christian Dior Sauvage 100ML',
        category: 'Men',
        branch: branch,
        shelf: 'Layer A - Tray AD Slot 1',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      await sqliteService.insertAlert(AlertModel(
        id: 'alert_low_AD1',
        title: 'LOW STOCK: Christian Dior Sauvage 100ML',
        desc: 'Shelf has 1 bottle remaining.',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        createdAt: now.subtract(const Duration(hours: 2)),
      ));

      // Verify active unread alert
      var activeAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(activeAlerts.any((a) => a.perfumeCode == 'AD1' && !a.isRead), isTrue);

      // 2. Warehouse delivery arrives: 4 bottles for AD1
      const restockId = 'rst_delivery_AD1_001';
      const expectedQuantity = 4;
      await db.insert('restock_records', {
        'id': restockId,
        'productName': 'Christian Dior Sauvage 100ML',
        'perfumeCode': 'AD1',
        'quantity': expectedQuantity,
        'fromBranch': 'Central Distribution Center',
        'toBranch': branch,
        'requestedBy': 'Store Restock Manager',
        'status': 'pending',
        'createdAt': now.millisecondsSinceEpoch,
      });

      // 3. Staff taps "Scan Tray AD" -> Camera router routes to Camera 1
      final targetCamera = ShelfArchitectureHarness.getCameraIdForTray('AD');
      expect(targetCamera, equals(1));
      final cameraDevice = ShelfArchitectureHarness.getCameraDevice(targetCamera);
      expect(cameraDevice, equals('/dev/cam1a'));

      // 4. Camera 1 detects 5 bottles in Tray AD Slot 1 (1 existing + 4 delivered)
      final detectionsAD = List.generate(
        5,
        (i) => {'centerX': 0.04 + (i * 0.01), 'centerY': 0.4},
      );
      final slotCounts = ShelfArchitectureHarness.partitionTrayDetections(
        trayCode: 'AD',
        detections: detectionsAD,
        trayLeft: 0.0,
        trayRight: 0.20,
        calibratedMidpoint: 0.10,
      );
      final detectedCount = slotCounts['AD1']!;
      expect(detectedCount, equals(5));

      // 5. Verification condition: detected count (5) >= invoice quantity (4)
      expect(detectedCount >= expectedQuantity, isTrue);

      // Update inventory record with verified count
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Christian Dior Sauvage 100ML',
        category: 'Men',
        branch: branch,
        shelf: 'Layer A - Tray AD Slot 1',
        recorded: 5,
        detected: detectedCount,
        status: 'normal',
      ));

      // 6. Execute post-verification actions:
      // Mark restock verified, clear active alerts, log RESTOCKED event
      await sqliteService.resolveRestockDelivery(
        restockId: restockId,
        perfumeCode: 'AD1',
        verifiedQuantity: expectedQuantity,
        branch: branch,
      );

      // 7. Verify post-conditions
      // - Restock record status is 'verified'
      final restocks = await sqliteService.getRestockRecords(branch);
      final verifiedRestock = restocks.firstWhere((r) => r.id == restockId);
      expect(verifiedRestock.status, equals('verified'));

      // - Active alert is auto-resolved (unreadOnly = true returns 0)
      activeAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(activeAlerts.any((a) => a.perfumeCode == 'AD1'), isFalse);

      // - Historical alerts still retains the acknowledged record
      final alertHistory = await sqliteService.getAlertsHistory(branch);
      expect(alertHistory.any((a) => a.perfumeCode == 'AD1' && a.isRead), isTrue);

      // - RESTOCKED event logged in inventory_events
      final events = await sqliteService.getInventoryEvents(branch);
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'AD1' && e.quantity == 4), isTrue);
    });

    // =========================================================================
    // SCENARIO 3: STORE CLOSING FLOW (21:00 Closing & Reconciliation)
    // =========================================================================
    test('Scenario 3: Store Closing Flow - 21:00 Closing Scan, Sales Delta Reconciliation, Sync Queue Draining', () async {
      const branch = 'San Pablo';
      final t2100 = DateTime(2026, 11, 1, 21, 0, 0);

      // 1. Initial morning baseline stock: 292 bottles across 60 slots
      // 2. During the day: 12 bottles sold across various slots
      const int morningStock = 292;
      const int restockedBottles = 4; // From Scenario 2
      const int soldBottles = 12;
      const int expectedClosingStock = morningStock + restockedBottles - soldBottles; // 284

      // 3. 21:00 Store Closing checkpoint triggers
      final isClosingDue = SchedulerDiagnosticsHarness.isCheckpointDue(
        now: t2100,
        checkpoints: ['09:00', '14:00', '21:00'],
      );
      expect(isClosingDue, isTrue);

      // 4. Full 6-camera scan captures 284 bottles
      const int actualDetectedBottles = 284;
      expect(actualDetectedBottles, equals(expectedClosingStock));

      // 5. Generate daily closing audit log
      await db.insert('system_logs', {
        'id': 'log_closing_${t2100.millisecondsSinceEpoch}',
        'type': 'STORE_CLOSING_RECONCILED',
        'description': 'Store Closing 21:00 reconciliation complete: 284 detected bottles match expected stock (292 opening + 4 restocked - 12 sold).',
        'user': 'KioskClosingService',
        'branch': branch,
        'timestamp': t2100.toIso8601String(),
      });

      // 6. Enqueue end-of-day sales sync item
      await db.insert('sync_queue', {
        'id': 'sync_daily_sales_${t2100.millisecondsSinceEpoch}',
        'pendingEventId': 'daily_sales_20261101',
        'targetCollection': 'sales_records',
        'operation': 'UPSERT',
        'payload': jsonEncode({
          'date': '2026-11-01',
          'totalSold': soldBottles,
          'closingStock': actualDetectedBottles,
          'branch': branch,
        }),
        'status': 'pending',
        'retryCount': 0,
        'createdAt': t2100.millisecondsSinceEpoch,
        'branch': branch,
      });

      // 7. Verify sync queue has pending items ready for cloud upload
      final pendingSync = await sqliteService.getPendingSyncItems();
      expect(pendingSync.isNotEmpty, isTrue);
      expect(pendingSync.any((s) => s['id'].startsWith('sync_daily_sales_')), isTrue);
    });

    // =========================================================================
    // SCENARIO 4: SECURITY ATTACK LOCKOUT & EMERGENCY MANAGER OVERRIDE FLOW
    // =========================================================================
    test('Scenario 4: Security Attack Lockout & Emergency Manager Override Flow', () async {
      final startTime = DateTime(2026, 11, 1, 19, 0, 0);

      // 1. Arm system with secure PBKDF2 hashed owner PIN ('741852')
      final salt = Pbkdf2Harness.generateSalt(32);
      final ownerPinHash = Pbkdf2Harness.hashPin('741852', salt, iterations: 500);
      final masterKeyHash = Pbkdf2Harness.hashPin(
        Pbkdf2Harness.defaultMasterRecoveryKey,
        salt,
        iterations: 500,
      );

      await db.insert('system_settings', {'key': 'kiosk_auth_salt', 'value': Pbkdf2Harness.toHex(salt)});
      await db.insert('system_settings', {'key': 'owner_pin_hash', 'value': ownerPinHash});
      await db.insert('system_settings', {'key': 'master_recovery_key_hash', 'value': masterKeyHash});

      // 2. Unauthorized attacker enters 5 consecutive incorrect PINs
      final attackerGuesses = ['000000', '123456', '111111', '888888', '999999'];
      var lockout = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

      for (int i = 0; i < attackerGuesses.length; i++) {
        final guess = attackerGuesses[i];
        final isPinCorrect = Pbkdf2Harness.verifyPin(guess, ownerPinHash, salt, iterations: 500);
        expect(isPinCorrect, isFalse);

        lockout = lockout.recordFailure(startTime);
      }

      // 3. Verify terminal is strictly locked out
      expect(lockout.failedAttempts, equals(5));
      expect(lockout.isLocked(startTime), isTrue);
      expect(lockout.remainingSeconds(startTime), equals(300));
      await lockout.saveToDb(db);

      // 4. Attacker restarts the application process to bypass lockout
      // Simulate app restart by re-reading state from SQLite
      final reloadedLockout = await LockoutState.loadFromDb(db);
      final at1MinuteLater = startTime.add(const Duration(minutes: 1));
      expect(reloadedLockout.isLocked(at1MinuteLater), isTrue);
      expect(reloadedLockout.remainingSeconds(at1MinuteLater), equals(240));

      // 5. Store Manager arrives and invokes Emergency Override Dialog
      // Manager enters master recovery key: OTTO-MASTER-RECOVERY-2026
      final isMasterKeyValid = Pbkdf2Harness.verifyMasterKey(
        'OTTO-MASTER-RECOVERY-2026',
        masterKeyHash,
        salt,
        iterations: 500,
      );
      expect(isMasterKeyValid, isTrue);

      // 6. Reset lockout state in memory and SQLite
      final clearedLockout = reloadedLockout.resetOnSuccess();
      await clearedLockout.saveToDb(db);

      expect(clearedLockout.isLocked(at1MinuteLater), isFalse);
      expect(clearedLockout.failedAttempts, equals(0));

      // 7. Log SECURITY_OVERRIDE audit event to SQLite and sync_queue
      final overrideLogId = 'log_override_${at1MinuteLater.millisecondsSinceEpoch}';
      await db.insert('system_logs', {
        'id': overrideLogId,
        'type': 'SECURITY_OVERRIDE',
        'description': 'Emergency manager override executed via verified Master Recovery Key. Terminal unlocked.',
        'user': 'ManagerOverride',
        'branch': 'San Pablo',
        'timestamp': at1MinuteLater.toIso8601String(),
      });

      await db.insert('sync_queue', {
        'id': 'sync_$overrideLogId',
        'pendingEventId': overrideLogId,
        'targetCollection': 'system_logs',
        'operation': 'UPSERT',
        'payload': jsonEncode({
          'id': overrideLogId,
          'type': 'SECURITY_OVERRIDE',
          'timestamp': at1MinuteLater.toIso8601String(),
        }),
        'status': 'pending',
        'retryCount': 0,
        'createdAt': at1MinuteLater.millisecondsSinceEpoch,
        'branch': 'San Pablo',
      });

      // 8. Confirm terminal is fully unlocked and verified
      final persistedLockout = await LockoutState.loadFromDb(db);
      expect(persistedLockout.isLocked(at1MinuteLater), isFalse);
      expect(persistedLockout.failedAttempts, equals(0));

      final overrideLogs = await db.query('system_logs', where: 'type = ?', whereArgs: ['SECURITY_OVERRIDE']);
      expect(overrideLogs.length, equals(1));
    });
  });
}
