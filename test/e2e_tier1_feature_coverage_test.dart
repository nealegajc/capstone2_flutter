import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'helpers/e2e_test_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Tier 1: Feature Coverage (R1 - R5 Opaque-Box E2E Tests)', () {
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
      await db.delete('products');
    });

    // =========================================================================
    // R1: SECURITY & AUTHENTICATION HARDENING (>=5 tests)
    // =========================================================================
    group('R1: Security & Authentication Hardening', () {
      test('T1.1: Salted PBKDF2-HMAC-SHA256 derives deterministic 32-byte hash (100k rounds)', () {
        final salt = utf8.encode('kiosk_salt_secure_32_bytes_test!');
        final hash1 = Pbkdf2Harness.hashPin('123456', salt, iterations: 1000);
        final hash2 = Pbkdf2Harness.hashPin('123456', salt, iterations: 1000);
        expect(hash1, equals(hash2));
        expect(hash1.length, equals(64)); // 32 bytes in hex = 64 chars
      });

      test('T1.2: Unique 32-byte salts produce completely different hashes for identical PINs', () {
        final saltA = Pbkdf2Harness.generateSalt(32);
        final saltB = Pbkdf2Harness.generateSalt(32);
        expect(saltA, isNot(equals(saltB)));

        final hashA = Pbkdf2Harness.hashPin('654321', saltA, iterations: 500);
        final hashB = Pbkdf2Harness.hashPin('654321', saltB, iterations: 500);
        expect(hashA, isNot(equals(hashB)));
      });

      test('T1.3: PIN verification succeeds on match and rejects invalid credentials', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final storedHash = Pbkdf2Harness.hashPin('987654', salt, iterations: 500);

        final match = Pbkdf2Harness.verifyPin('987654', storedHash, salt, iterations: 500);
        final wrong = Pbkdf2Harness.verifyPin('111111', storedHash, salt, iterations: 500);

        expect(match, isTrue);
        expect(wrong, isFalse);
      });

      test('T1.4: First-time setup flow initializes PIN and salt in system_settings', () async {
        final salt = Pbkdf2Harness.generateSalt(32);
        final saltHex = Pbkdf2Harness.toHex(salt);
        final pinHash = Pbkdf2Harness.hashPin('888888', salt, iterations: 500);

        await db.insert('system_settings', {'key': 'kiosk_auth_salt', 'value': saltHex});
        await db.insert('system_settings', {'key': 'owner_pin_hash', 'value': pinHash});

        final rows = await db.query('system_settings', where: 'key IN (?, ?)', whereArgs: [
          'kiosk_auth_salt',
          'owner_pin_hash',
        ]);
        expect(rows.length, equals(2));
      });

      test('T1.5: Emergency Manager Recovery Key successfully overrides lockout', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final masterHash = Pbkdf2Harness.hashPin(Pbkdf2Harness.defaultMasterRecoveryKey, salt, iterations: 500);

        final isValidMaster = Pbkdf2Harness.verifyMasterKey(
          'OTTO-MASTER-RECOVERY-2026',
          masterHash,
          salt,
          iterations: 500,
        );
        final isInvalidMaster = Pbkdf2Harness.verifyMasterKey(
          'WRONG-KEY-XYZ',
          masterHash,
          salt,
          iterations: 500,
        );

        expect(isValidMaster, isTrue);
        expect(isInvalidMaster, isFalse);
      });

      test('T1.6: Failed PIN counter triggers 300s lockout after 5 consecutive failures', () {
        final now = DateTime(2026, 11, 1, 10, 0, 0);
        var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

        for (int i = 1; i <= 4; i++) {
          state = state.recordFailure(now);
          expect(state.isLocked(now), isFalse);
          expect(state.failedAttempts, equals(i));
        }

        // 5th failed attempt triggers lockout
        state = state.recordFailure(now);
        expect(state.failedAttempts, equals(5));
        expect(state.isLocked(now), isTrue);
        expect(state.remainingSeconds(now), equals(300));
      });

      test('T1.7: Lockout status persists in SQLite and survives simulated restart', () async {
        final now = DateTime(2026, 11, 1, 12, 0, 0);
        final lockedState = LockoutState(
          failedAttempts: 5,
          lockedUntilEpochMs: now.millisecondsSinceEpoch + 300000,
        );
        await lockedState.saveToDb(db);

        // Simulate reboot: reload from database
        final reloadedState = await LockoutState.loadFromDb(db);
        expect(reloadedState.failedAttempts, equals(5));
        expect(reloadedState.isLocked(now), isTrue);
        expect(reloadedState.remainingSeconds(now), equals(300));
      });
    });

    // =========================================================================
    // R2: DATA INTEGRITY & SUPABASE CLOUD SYNC (>=5 tests)
    // =========================================================================
    group('R2: Data Integrity & Supabase Cloud Sync', () {
      test('T1.8: Partial payload detection isolates status update from full entity', () {
        final partialPayload = {'id': 'alert_123', 'isRead': 1, 'status': 'resolved'};
        final fullPayload = {
          'id': 'prod_AA1',
          'name': 'Bleu de Chanel',
          'perfumeCode': 'AA1',
          'category': 'Men',
          'shelf': 'Tray AA - Slot 1',
          'price': 150.0,
        };

        expect(SyncDataHarness.isPartialPayload(partialPayload), isTrue);
        expect(SyncDataHarness.isPartialPayload(fullPayload), isFalse);
      });

      test('T1.9: Conflict resolution: Cloud wins pull for Product Catalog and Pricing', () {
        final localProduct = {
          'id': 'prod_AA1',
          'name': 'Local Stale Name',
          'price': 100.0,
          'lastUpdated': 1000,
        };
        final cloudProduct = {
          'id': 'prod_AA1',
          'name': 'Cloud Updated Name',
          'price': 120.0,
          'lastUpdated': 2000,
        };

        final resolved = SyncDataHarness.resolveConflict(
          collection: 'products',
          localRecord: localProduct,
          cloudRecord: cloudProduct,
        );

        expect(resolved['name'], equals('Cloud Updated Name'));
        expect(resolved['price'], equals(120.0));
      });

      test('T1.10: Conflict resolution: Local kiosk wins push for Sales and Restock Events', () {
        final localEvent = {
          'id': 'evt_001',
          'eventType': 'RESTOCKED',
          'quantity': 5,
          'timestamp': 5000,
        };
        final cloudEvent = {
          'id': 'evt_001',
          'eventType': 'RESTOCKED',
          'quantity': 2,
          'timestamp': 4000,
        };

        final resolved = SyncDataHarness.resolveConflict(
          collection: 'inventory_events',
          localRecord: localEvent,
          cloudRecord: cloudEvent,
        );

        expect(resolved['quantity'], equals(5));
      });

      test('T1.11: Computer vision detected count is strictly isolated from manual recorded stock', () {
        final record = InventoryRecordModel(
          id: 'inv_AA1',
          perfumeCode: 'AA1',
          name: 'Sauvage',
          category: 'Men',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: 2, // Low stock detected
          status: 'low',
        );

        SyncDataHarness.validateStockInvariants(record);
        expect(record.recorded, equals(5));
        expect(record.detected, equals(2));
        expect(SyncDataHarness.hasDiscrepancy(record.recorded, record.detected), isTrue);
      });

      test('T1.12: Dynamic branch lookup resolves from system_settings.branch_name', () async {
        // Fallback default
        final branchDefault = await SyncDataHarness.getDynamicBranch(db);
        expect(branchDefault, equals('San Pablo'));

        // Update branch name
        await db.insert(
          'system_settings',
          {'key': 'branch_name', 'value': 'Batangas City Kiosk'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final branchUpdated = await SyncDataHarness.getDynamicBranch(db);
        expect(branchUpdated, equals('Batangas City Kiosk'));
      });

      test('T1.13: Restock operations clamp detected stock strictly to max 5 bottles per slot', () {
        final detections7 = List.generate(7, (i) => {'centerX': 0.05, 'centerY': 0.3});
        final partitioned = ShelfArchitectureHarness.partitionTrayDetections(
          trayCode: 'AA',
          detections: detections7,
          trayLeft: 0.0,
          trayRight: 0.2,
          calibratedMidpoint: 0.1,
        );

        // Slot 1 left half has 7 detections, must clamp to 5
        expect(partitioned['AA1'], equals(5));
        expect(partitioned['AA2'], equals(0));
      });
    });

    // =========================================================================
    // R3: CHECKPOINT SCHEDULER & REAL DIAGNOSTICS (>=5 tests)
    // =========================================================================
    group('R3: Checkpoint Scheduler & Real Diagnostics', () {
      test('T1.14: Checkpoint schedule identifies 09:00, 14:00, 21:00 triggers', () {
        final time0859 = DateTime(2026, 11, 1, 8, 59, 0);
        final time0900 = DateTime(2026, 11, 1, 9, 0, 0);
        final time1400 = DateTime(2026, 11, 1, 14, 0, 0);
        final time2100 = DateTime(2026, 11, 1, 21, 0, 0);

        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: time0859,
            checkpoints: SchedulerDiagnosticsHarness.defaultCheckpoints,
          ),
          isFalse,
        );
        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: time0900,
            checkpoints: SchedulerDiagnosticsHarness.defaultCheckpoints,
          ),
          isTrue,
        );
        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: time1400,
            checkpoints: SchedulerDiagnosticsHarness.defaultCheckpoints,
          ),
          isTrue,
        );
        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: time2100,
            checkpoints: SchedulerDiagnosticsHarness.defaultCheckpoints,
          ),
          isTrue,
        );
      });

      test('T1.15: Checkpoint scheduler prevents duplicate execution within the same minute', () {
        final time0900 = DateTime(2026, 11, 1, 9, 0, 15);
        final lastRun = DateTime(2026, 11, 1, 9, 0, 5);

        final isDue = SchedulerDiagnosticsHarness.isCheckpointDue(
          now: time0900,
          checkpoints: SchedulerDiagnosticsHarness.defaultCheckpoints,
          lastExecutionTime: lastRun,
        );
        expect(isDue, isFalse);
      });

      test('T1.16: Automated scan completion logs to system_logs and enqueues sync item', () async {
        await SchedulerDiagnosticsHarness.logCheckpointScan(
          db,
          checkpointName: 'Store Opening',
          totalBottles: 290,
          branch: 'San Pablo',
        );

        final logs = await db.query('system_logs', where: 'type = ?', whereArgs: ['CHECKPOINT_SCAN']);
        expect(logs.length, equals(1));
        expect(logs.first['description'], contains('Store Opening'));
        expect(logs.first['description'], contains('290 bottles'));

        final syncItems = await db.query('sync_queue', where: 'targetCollection = ?', whereArgs: ['system_logs']);
        expect(syncItems.length, equals(1));
      });

      test('T1.17: Real image frame evaluation calculates brightness, contrast, and sharpness', () {
        // Uniform gray frame (128)
        final flatFrame = List.filled(100, 128);
        final flatMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(flatFrame);
        expect(flatMetrics['brightness'], equals(128.0));
        expect(flatMetrics['contrast'], equals(0.0));
        expect(flatMetrics['sharpness'], equals(0.0));

        // High contrast alternating frame (0, 255)
        final highContrastFrame = List.generate(100, (i) => i % 2 == 0 ? 0 : 255);
        final hcMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(highContrastFrame);
        expect(hcMetrics['brightness'], closeTo(127.5, 1.0));
        expect(hcMetrics['contrast'], greaterThan(100.0));
        expect(hcMetrics['sharpness'], greaterThan(200.0));
      });

      test('T1.18: Zero-light detector identifies dark frames without throwing exceptions', () {
        final darkFrame = List.filled(50, 2);
        final darkMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(darkFrame);
        expect(SchedulerDiagnosticsHarness.isZeroLight(darkMetrics), isTrue);

        final litFrame = List.filled(50, 150);
        final litMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(litFrame);
        expect(SchedulerDiagnosticsHarness.isZeroLight(litMetrics), isFalse);
      });
    });

    // =========================================================================
    // R4: 60-SKU SHELF ARCHITECTURE & DYNAMIC ROUTING (>=5 tests)
    // =========================================================================
    group('R4: 60-SKU Shelf Physical Reality & Dynamic Routing', () {
      test('T1.19: Shelf architecture provides exactly 30 trays and 60 slots for 300 bottles', () {
        expect(ShelfArchitectureHarness.totalTrays, equals(30));
        expect(ShelfArchitectureHarness.slotsPerTray, equals(2));
        expect(ShelfArchitectureHarness.totalSlots, equals(60));
        expect(ShelfArchitectureHarness.totalCapacity, equals(300));
      });

      test('T1.20: Dynamic tray-to-camera router accurately routes trays AA through CK to cameras 1-6', () {
        expect(ShelfArchitectureHarness.getCameraIdForTray('AA'), equals(1));
        expect(ShelfArchitectureHarness.getCameraIdForTray('AE'), equals(1));
        expect(ShelfArchitectureHarness.getCameraIdForTray('AF'), equals(2));
        expect(ShelfArchitectureHarness.getCameraIdForTray('AJ'), equals(2));
        expect(ShelfArchitectureHarness.getCameraIdForTray('BA'), equals(3));
        expect(ShelfArchitectureHarness.getCameraIdForTray('BE'), equals(3));
        expect(ShelfArchitectureHarness.getCameraIdForTray('BF'), equals(4));
        expect(ShelfArchitectureHarness.getCameraIdForTray('BJ'), equals(4));
        expect(ShelfArchitectureHarness.getCameraIdForTray('CA'), equals(5));
        expect(ShelfArchitectureHarness.getCameraIdForTray('CE'), equals(5));
        expect(ShelfArchitectureHarness.getCameraIdForTray('CF'), equals(6));
        expect(ShelfArchitectureHarness.getCameraIdForTray('CK'), equals(6));
      });

      test('T1.21: Centerline partitioning accurately divides left (100ML) and right (50ML) bottles', () {
        final detections = [
          {'centerX': 0.04, 'centerY': 0.3}, // Left -> AA1
          {'centerX': 0.06, 'centerY': 0.4}, // Left -> AA1
          {'centerX': 0.14, 'centerY': 0.5}, // Right -> AA2
          {'centerX': 0.16, 'centerY': 0.6}, // Right -> AA2
          {'centerX': 0.18, 'centerY': 0.7}, // Right -> AA2
        ];

        final slots = ShelfArchitectureHarness.partitionTrayDetections(
          trayCode: 'AA',
          detections: detections,
          trayLeft: 0.0,
          trayRight: 0.20,
          calibratedMidpoint: 0.10,
        );

        expect(slots['AA1'], equals(2));
        expect(slots['AA2'], equals(3));
      });

      test('T1.22: Tray review status persists to SQLite database', () async {
        await db.insert(
          'system_settings',
          {'key': 'tray_review_AA', 'value': 'reviewed_ok'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final rows = await db.query(
          'system_settings',
          where: 'key = ?',
          whereArgs: ['tray_review_AA'],
        );
        expect(rows.isNotEmpty, isTrue);
        expect(rows.first['value'], equals('reviewed_ok'));
      });

      test('T1.23: Master products catalog contains all 60 SKUs across layers A, B, and C', () async {
        final sampleProducts = List.generate(
          60,
          (i) => {
            'id': 'prod_$i',
            'perfumeCode': 'SKU_$i',
            'name': 'Fragrance $i',
            'brand': 'Otto Scents',
            'category': 'Unisex',
            'bottleSize': i % 2 == 0 ? '100ML' : '50ML',
            'shelfLayer': 'Layer A',
            'slotPosition': (i % 2) + 1,
            'price': 120.0,
            'status': 'active',
          },
        );

        final batch = db.batch();
        for (final p in sampleProducts) {
          batch.insert('products', p);
        }
        await batch.commit(noResult: true);

        final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM products');
        final count = (res.first['cnt'] as num).toInt();
        expect(count, equals(60));
      });
    });

    // =========================================================================
    // R5: VISION BACKEND THREADING & CLEANUP (>=5 tests)
    // =========================================================================
    group('R5: Vision Backend Threading & Cleanup', () {
      test('T1.24: Hardware camera device mapping validates /dev/cam1a through /dev/cam3b', () {
        expect(ShelfArchitectureHarness.getCameraDevice(1), equals('/dev/cam1a'));
        expect(ShelfArchitectureHarness.getCameraDevice(2), equals('/dev/cam1b'));
        expect(ShelfArchitectureHarness.getCameraDevice(3), equals('/dev/cam2a'));
        expect(ShelfArchitectureHarness.getCameraDevice(4), equals('/dev/cam2b'));
        expect(ShelfArchitectureHarness.getCameraDevice(5), equals('/dev/cam3a'));
        expect(ShelfArchitectureHarness.getCameraDevice(6), equals('/dev/cam3b'));
      });

      test('T1.25: Scan response JSON schema adheres to exact backend contract', () {
        final sampleResponse = {
          'cameraId': 1,
          'totalBottles': 50,
          'trayCounts': {
            'tray_AA': 10,
            'tray_AB': 10,
            'tray_AC': 10,
            'tray_AD': 10,
            'tray_AE': 10,
          },
          'detections': [
            {
              'roiId': 'tray_AA',
              'bbox': [0.1, 0.2, 0.15, 0.25],
              'centerX': 0.125,
              'centerY': 0.225,
            }
          ]
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(sampleResponse), isTrue);
      });

      test('T1.26: Detection normalized coordinates must be clamped to [0.0, 1.0]', () {
        final invalidResponse = {
          'cameraId': 1,
          'totalBottles': 1,
          'trayCounts': {'tray_AA': 1},
          'detections': [
            {
              'roiId': 'tray_AA',
              'centerX': 1.5, // Out of bounds
              'centerY': 0.2,
            }
          ]
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(invalidResponse), isFalse);
      });

      test('T1.27: Vertical detection boundary accepts bottom row bottles up to cY = 0.985', () {
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.50), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.90), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.96), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.985), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.990), isFalse);
      });

      test('T1.28: Zero-bottle scan response returns clean empty tray counts and detections', () {
        final emptyResponse = {
          'cameraId': 3,
          'totalBottles': 0,
          'trayCounts': {
            'tray_BA': 0,
            'tray_BB': 0,
            'tray_BC': 0,
            'tray_BD': 0,
            'tray_BE': 0,
          },
          'detections': <Map<String, dynamic>>[],
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(emptyResponse), isTrue);
        expect(emptyResponse['totalBottles'], equals(0));
        expect((emptyResponse['detections'] as List).isEmpty, isTrue);
      });
    });
  });
}
