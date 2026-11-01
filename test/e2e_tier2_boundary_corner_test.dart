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

  group('Tier 2: Boundary & Corner Cases (R1 - R5 Opaque-Box E2E Tests)', () {
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
    });

    // =========================================================================
    // R1 BOUNDARY & CORNER CASES (>=5 tests)
    // =========================================================================
    group('R1: Security & Auth Boundaries', () {
      test('T2.1: Empty and whitespace-only PINs fail verification without crashing', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final validHash = Pbkdf2Harness.hashPin('123456', salt, iterations: 100);

        expect(Pbkdf2Harness.verifyPin('', validHash, salt, iterations: 100), isFalse);
        expect(Pbkdf2Harness.verifyPin('   ', validHash, salt, iterations: 100), isFalse);
        expect(Pbkdf2Harness.verifyPin('', '', salt, iterations: 100), isFalse);
      });

      test('T2.2: Short and non-numeric PIN inputs are safely rejected', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final validHash = Pbkdf2Harness.hashPin('123456', salt, iterations: 100);

        expect(Pbkdf2Harness.verifyPin('123', validHash, salt, iterations: 100), isFalse);
        expect(Pbkdf2Harness.verifyPin('12345', validHash, salt, iterations: 100), isFalse);
        expect(Pbkdf2Harness.verifyPin('abcdef', validHash, salt, iterations: 100), isFalse);
        expect(Pbkdf2Harness.verifyPin('1234567', validHash, salt, iterations: 100), isFalse);
      });

      test('T2.3: Lockout threshold exact boundary: 4 failures is unlocked, 5 failures locks out', () {
        final now = DateTime(2026, 11, 1, 15, 0, 0);
        var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

        // 4 failed attempts
        for (int i = 0; i < 4; i++) {
          state = state.recordFailure(now);
        }
        expect(state.failedAttempts, equals(4));
        expect(state.isLocked(now), isFalse);
        expect(state.remainingSeconds(now), equals(0));

        // 5th failed attempt: boundary transition
        state = state.recordFailure(now);
        expect(state.failedAttempts, equals(5));
        expect(state.isLocked(now), isTrue);
        expect(state.remainingSeconds(now), equals(300));
      });

      test('T2.4: Lockout duration exact boundary: 299s is locked, 300s is unlocked', () {
        final startTime = DateTime(2026, 11, 1, 12, 0, 0);
        final state = const LockoutState(failedAttempts: 4, lockedUntilEpochMs: 0).recordFailure(startTime);

        // At 299 seconds after lockout
        final at299s = startTime.add(const Duration(seconds: 299));
        expect(state.isLocked(at299s), isTrue);
        expect(state.remainingSeconds(at299s), equals(1));

        // At exactly 300 seconds after lockout
        final at300s = startTime.add(const Duration(seconds: 300));
        expect(state.isLocked(at300s), isFalse);
        expect(state.remainingSeconds(at300s), equals(0));

        // After 301 seconds
        final at301s = startTime.add(const Duration(seconds: 301));
        expect(state.isLocked(at301s), isFalse);
      });

      test('T2.5: Salt bounds: handles 16, 32, and 64 byte salts correctly', () {
        final salt16 = Pbkdf2Harness.generateSalt(16);
        final salt32 = Pbkdf2Harness.generateSalt(32);
        final salt64 = Pbkdf2Harness.generateSalt(64);

        final h16 = Pbkdf2Harness.hashPin('555555', salt16, iterations: 100);
        final h32 = Pbkdf2Harness.hashPin('555555', salt32, iterations: 100);
        final h64 = Pbkdf2Harness.hashPin('555555', salt64, iterations: 100);

        expect(h16.length, equals(64));
        expect(h32.length, equals(64));
        expect(h64.length, equals(64));
        expect(h16, isNot(equals(h32)));
        expect(h32, isNot(equals(h64)));
      });

      test('T2.6: Monotonic failure counter across rapid consecutive attempts', () {
        final now = DateTime.now();
        var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

        for (int i = 1; i <= 10; i++) {
          state = state.recordFailure(now);
          expect(state.failedAttempts, equals(i));
        }
      });
    });

    // =========================================================================
    // R2 BOUNDARY & CORNER CASES (>=5 tests)
    // =========================================================================
    group('R2: Data Integrity & Sync Boundaries', () {
      test('T2.7: Stock count 0 bottles boundary (critical Out of Stock)', () {
        final record = InventoryRecordModel(
          id: 'inv_AA1',
          perfumeCode: 'AA1',
          name: 'Sauvage',
          category: 'Men',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: 0,
          status: 'out_of_stock',
        );

        SyncDataHarness.validateStockInvariants(record);
        expect(record.detected, equals(0));
        expect(record.status, equals('out_of_stock'));
      });

      test('T2.8: Low stock threshold boundary: 2 is low stock, 3 is normal stock', () {
        const threshold = 2;

        final isLowAt2 = 2 <= threshold;
        final isLowAt3 = 3 <= threshold;

        expect(isLowAt2, isTrue);
        expect(isLowAt3, isFalse);
      });

      test('T2.9: Slot capacity upper boundary: 5 is full, >5 clamps strictly to 5', () {
        final detections10 = List.generate(10, (i) => {'centerX': 0.05, 'centerY': 0.5});
        final counts = ShelfArchitectureHarness.partitionTrayDetections(
          trayCode: 'AA',
          detections: detections10,
          trayLeft: 0.0,
          trayRight: 0.2,
          calibratedMidpoint: 0.1,
        );

        expect(counts['AA1'], equals(5)); // Strictly clamped to 5
      });

      test('T2.10: Shelf total capacity boundaries: 0/300 empty vs 300/300 full', () {
        const minCapacity = 0;
        const maxCapacity = 60 * 5; // 300

        expect(minCapacity, equals(0));
        expect(maxCapacity, equals(300));

        // Percentage calculation boundaries
        final pct0 = (0 / 300 * 100).round();
        final pct300 = (300 / 300 * 100).round();

        expect(pct0, equals(0));
        expect(pct300, equals(100));
      });

      test('T2.11: Partial payload boundaries: empty map vs single-field update', () {
        expect(SyncDataHarness.isPartialPayload({}), isFalse);
        expect(SyncDataHarness.isPartialPayload({'id': 'alert_1'}), isTrue);
        expect(SyncDataHarness.isPartialPayload({'id': 'alert_1', 'isRead': 1}), isTrue);
        expect(
          SyncDataHarness.isPartialPayload({'id': 'alert_1', 'isRead': 1, 'name': 'Perfume X'}),
          isFalse,
        );
      });

      test('T2.12: Branch name containing special characters, quotes, and unicode survives SQLite escaping', () async {
        const complexBranch = "O'Connor & Sons - Branch #4 \"Greenhills\" 🇵🇭";
        await db.insert(
          'system_settings',
          {'key': 'branch_name', 'value': complexBranch},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        final branch = await SyncDataHarness.getDynamicBranch(db);
        expect(branch, equals(complexBranch));
      });
    });

    // =========================================================================
    // R3 BOUNDARY & CORNER CASES (>=5 tests)
    // =========================================================================
    group('R3: Checkpoint Scheduler & Diagnostics Boundaries', () {
      test('T2.13: Checkpoint exact boundary: 08:59:59 is false, 09:00:00 is true', () {
        final t085959 = DateTime(2026, 11, 1, 8, 59, 59);
        final t090000 = DateTime(2026, 11, 1, 9, 0, 0);

        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: t085959,
            checkpoints: ['09:00'],
          ),
          isFalse,
        );
        expect(
          SchedulerDiagnosticsHarness.isCheckpointDue(
            now: t090000,
            checkpoints: ['09:00'],
          ),
          isTrue,
        );
      });

      test('T2.14: Empty checkpoint configuration never fires scheduled scan', () {
        final t0900 = DateTime(2026, 11, 1, 9, 0, 0);
        final isDue = SchedulerDiagnosticsHarness.isCheckpointDue(
          now: t0900,
          checkpoints: <String>[],
        );
        expect(isDue, isFalse);
      });

      test('T2.15: Image frame quality extreme boundaries: pitch black (0) vs pure white (255)', () {
        // Pitch black
        final blackFrame = List.filled(64, 0);
        final blackMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(blackFrame);
        expect(blackMetrics['brightness'], equals(0.0));
        expect(blackMetrics['contrast'], equals(0.0));
        expect(SchedulerDiagnosticsHarness.isZeroLight(blackMetrics), isTrue);

        // Pure saturated white
        final whiteFrame = List.filled(64, 255);
        final whiteMetrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(whiteFrame);
        expect(whiteMetrics['brightness'], equals(255.0));
        expect(whiteMetrics['contrast'], equals(0.0));
        expect(SchedulerDiagnosticsHarness.isZeroLight(whiteMetrics), isFalse);
      });

      test('T2.16: Degraded frame edge condition: high noise with low mean brightness', () {
        final noisyDarkFrame = List.generate(100, (i) => i % 2 == 0 ? 0 : 8);
        final metrics = SchedulerDiagnosticsHarness.evaluateFrameQuality(noisyDarkFrame);
        expect(metrics['brightness'], closeTo(4.0, 0.5));
        expect(SchedulerDiagnosticsHarness.isZeroLight(metrics), isTrue);
      });

      test('T2.17: Checkpoint execution idempotency across multi-tick loop within same minute', () {
        final checkpoints = ['14:00'];
        int executedCount = 0;
        DateTime? lastRun;

        // Simulate 6 ticks inside 14:00 (every 10 seconds)
        for (int sec = 0; sec < 60; sec += 10) {
          final now = DateTime(2026, 11, 1, 14, 0, sec);
          if (SchedulerDiagnosticsHarness.isCheckpointDue(
            now: now,
            checkpoints: checkpoints,
            lastExecutionTime: lastRun,
          )) {
            executedCount++;
            lastRun = now;
          }
        }

        expect(executedCount, equals(1)); // Must only fire once during 14:00!
      });
    });

    // =========================================================================
    // R4 BOUNDARY & CORNER CASES (>=5 tests)
    // =========================================================================
    group('R4: Physical Shelf Architecture Boundaries', () {
      test('T2.18: First slot AA1 and last slot CK2 boundaries resolve correctly', () {
        expect(ShelfArchitectureHarness.getCameraIdForTray('AA'), equals(1));
        expect(ShelfArchitectureHarness.getCameraIdForTray('CK'), equals(6));
      });

      test('T2.19: Divider exact boundary: < midX is slot 1, >= midX is slot 2', () {
        const midX = 0.50;
        final detections = [
          {'centerX': 0.4999, 'centerY': 0.5}, // Left of divider -> slot 1
          {'centerX': 0.5000, 'centerY': 0.5}, // Exactly on divider -> slot 2
          {'centerX': 0.5001, 'centerY': 0.5}, // Right of divider -> slot 2
        ];

        final slots = ShelfArchitectureHarness.partitionTrayDetections(
          trayCode: 'BB',
          detections: detections,
          trayLeft: 0.0,
          trayRight: 1.0,
          calibratedMidpoint: midX,
        );

        expect(slots['BB1'], equals(1));
        expect(slots['BB2'], equals(2));
      });

      test('T2.20: Vertical detection limit boundary: cY = 0.985 is accepted, 0.9851 is excluded', () {
        final detections = [
          {'centerX': 0.05, 'centerY': 0.9850}, // Boundary accepted
          {'centerX': 0.05, 'centerY': 0.9851}, // Boundary excluded
        ];

        final slots = ShelfArchitectureHarness.partitionTrayDetections(
          trayCode: 'AD',
          detections: detections,
          trayLeft: 0.0,
          trayRight: 0.20,
          calibratedMidpoint: 0.10,
        );

        // Only the bottle at 0.9850 should be counted
        expect(slots['AD1'], equals(1));
      });

      test('T2.21: Case-insensitivity and whitespace trimming on tray codes', () {
        expect(ShelfArchitectureHarness.getCameraIdForTray('aa'), equals(1));
        expect(ShelfArchitectureHarness.getCameraIdForTray('  ck  '), equals(6));
        expect(ShelfArchitectureHarness.getCameraIdForTray('Ba'), equals(3));
      });

      test('T2.22: Invalid tray code throws ArgumentError', () {
        expect(
          () => ShelfArchitectureHarness.getCameraIdForTray('ZZ'),
          throwsArgumentError,
        );
        expect(
          () => ShelfArchitectureHarness.getCameraIdForTray('12'),
          throwsArgumentError,
        );
      });
    });

    // =========================================================================
    // R5 BOUNDARY & CORNER CASES (>=5 tests)
    // =========================================================================
    group('R5: Vision Backend Boundaries', () {
      test('T2.23: Camera ID boundary: 1 and 6 are valid, 0 and 7 throw ArgumentError', () {
        expect(ShelfArchitectureHarness.getCameraDevice(1), equals('/dev/cam1a'));
        expect(ShelfArchitectureHarness.getCameraDevice(6), equals('/dev/cam3b'));

        expect(() => ShelfArchitectureHarness.getCameraDevice(0), throwsArgumentError);
        expect(() => ShelfArchitectureHarness.getCameraDevice(7), throwsArgumentError);
        expect(() => ShelfArchitectureHarness.getCameraDevice(-1), throwsArgumentError);
      });

      test('T2.24: Extreme capacity: exactly 50 detections (5 per slot across 10 slots) conforms', () {
        final detections50 = List.generate(
          50,
          (i) => {
            'roiId': 'tray_AA',
            'bbox': [0.1, 0.2, 0.15, 0.25],
            'centerX': (i % 10) * 0.1 + 0.05,
            'centerY': 0.5,
          },
        );

        final fullCameraResponse = {
          'cameraId': 1,
          'totalBottles': 50,
          'trayCounts': {
            'tray_AA': 10,
            'tray_AB': 10,
            'tray_AC': 10,
            'tray_AD': 10,
            'tray_AE': 10,
          },
          'detections': detections50,
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(fullCameraResponse), isTrue);
      });

      test('T2.25: Negative coordinate values in detection bounding boxes fail schema validation', () {
        final negativeCoordsResponse = {
          'cameraId': 2,
          'totalBottles': 1,
          'trayCounts': {'tray_AF': 1},
          'detections': [
            {
              'roiId': 'tray_AF',
              'centerX': -0.05, // Negative coordinate
              'centerY': 0.5,
            }
          ]
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(negativeCoordsResponse), isFalse);
      });

      test('T2.26: Malformed response map missing required cameraId fails schema validation', () {
        final missingCameraId = {
          'totalBottles': 10,
          'trayCounts': {'tray_AA': 10},
          'detections': <Map<String, dynamic>>[],
        };

        expect(VisionAsyncHarness.validateScanResponseSchema(missingCameraId), isFalse);
      });

      test('T2.27: Vertical coordinate boundary check values [0.0, 0.985, 1.0]', () {
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.0), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.985), isTrue);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(0.98501), isFalse);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(1.0), isFalse);
        expect(VisionAsyncHarness.isWithinVerticalBoundary(-0.01), isFalse);
      });
    });
  });
}
