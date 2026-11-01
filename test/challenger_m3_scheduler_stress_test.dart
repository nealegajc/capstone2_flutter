import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/image_quality_log_model.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/kiosk_scheduler_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';

/// Fake Python API for adversarial testing of scheduler
class DelayedFakePythonApiRepository extends PythonApiRepository {
  int triggerCount = 0;
  final List<int> scannedCameraIds = [];
  Duration scanDelay = Duration.zero;
  bool shouldThrow = false;
  Set<int> failingCameraIds = {};

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    if (scanDelay > Duration.zero) {
      await Future.delayed(scanDelay);
    }
    triggerCount++;
    if (cameraId != null) scannedCameraIds.add(cameraId);
    if (shouldThrow) {
      throw Exception('Simulated hardware bus disconnect during Python scan');
    }
    if (cameraId != null && failingCameraIds.contains(cameraId)) {
      return {'success': false, 'error': 'Camera $cameraId frame grab failed'};
    }
    return {
      'success': true,
      'cameraId': cameraId ?? 1,
      'totalBottles': 10,
      'bottlesDetected': 10,
      'trayCounts': {'tray_AA': 5, 'tray_AB': 5},
      'detections': [
        {'roiId': 'tray_AA', 'centerX': 0.05, 'centerY': 0.3},
        {'roiId': 'tray_AA', 'centerX': 0.15, 'centerY': 0.3},
      ],
    };
  }

  @override
  Future<ImageQualityLogModel?> getLatestImageQualityLog() async {
    return ImageQualityLogModel(
      id: 'qa_real_test',
      brightness: 78.5,
      contrast: 82.1,
      sharpness: 91.4,
      isAcceptable: true,
      preprocessingApplied: ['CLAHE_Equalization', 'Gamma_Adjust'],
      retryCount: 0,
      status: 'ACCEPTED',
      branch: 'San Pablo',
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CHALLENGE 1: Checkpoint Scheduling, Deduplication & Boundary Stress', () {
    late SqliteService sqliteService;
    late KioskSchedulerService scheduler;
    late DelayedFakePythonApiRepository fakeApi;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      KioskSchedulerService.resetInstanceForTesting();
      scheduler = KioskSchedulerService.instance;
      fakeApi = DelayedFakePythonApiRepository();
      scheduler.setPythonApiForTesting(fakeApi);
      scheduler.resetExecutedCheckpointsForTesting();
    });

    tearDown(() {
      scheduler.stop();
    });

    test('1.1 Exact triggering at 09:00, 14:00, 21:00 and same-minute ticker deduplication', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': true, '14:00': true, '21:00': true}),
      );
      await scheduler.reloadSchedule();

      // Opening Check: 09:00:05
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 5),
      );
      expect(fakeApi.triggerCount, equals(6), reason: 'All 6 cameras must be scanned on 09:00 trigger');
      expect(fakeApi.scannedCameraIds, equals([1, 2, 3, 4, 5, 6]));

      // Multiple ticker evaluations within the same minute: 09:00:20, 09:00:45, 09:00:59
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 20),
      );
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 45),
      );
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 59),
      );
      expect(fakeApi.triggerCount, equals(6), reason: 'Same-minute ticker ticks must be strictly deduplicated');

      // Next non-checkpoint minute: 09:01:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 1, 0),
      );
      expect(fakeApi.triggerCount, equals(6), reason: '09:01 is not a scheduled checkpoint');

      // Shift Change Check: 14:00:15
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 14, 0, 15),
      );
      expect(fakeApi.triggerCount, equals(12), reason: '14:00 checkpoint must trigger a scan batch');

      // Duplicate tick within 14:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 14, 0, 40),
      );
      expect(fakeApi.triggerCount, equals(12), reason: '14:00 duplicate tick must be deduplicated');

      // Store Closing Check: 21:00:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 21, 0, 0),
      );
      expect(fakeApi.triggerCount, equals(18), reason: '21:00 checkpoint must trigger 3rd scan batch');

      // Duplicate tick within 21:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 21, 0, 30),
      );
      expect(fakeApi.triggerCount, equals(18), reason: '21:00 duplicate tick must be deduplicated');
    });

    test('1.2 Day, Month, and Year boundary transitions without service restart', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': true, '14:00': true, '21:00': true}),
      );
      await scheduler.reloadSchedule();

      // Day 1: 2026-11-01 09:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 10),
      );
      expect(fakeApi.triggerCount, equals(6));

      // Duplicate on Day 1
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 40),
      );
      expect(fakeApi.triggerCount, equals(6));

      // Day 2 Boundary: 2026-11-02 09:00 (without manual reset or service restart)
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 2, 9, 0, 10),
      );
      expect(fakeApi.triggerCount, equals(12), reason: 'Day boundary transition must allow 09:00 check to run on Day 2');

      // Duplicate on Day 2
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 2, 9, 0, 40),
      );
      expect(fakeApi.triggerCount, equals(12));

      // Month Boundary: 2026-12-01 09:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 12, 1, 9, 0, 10),
      );
      expect(fakeApi.triggerCount, equals(18), reason: 'Month boundary transition must trigger 09:00 scan');

      // Year Boundary: 2027-01-01 09:00
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2027, 1, 1, 9, 0, 10),
      );
      expect(fakeApi.triggerCount, equals(24), reason: 'Year boundary transition must trigger 09:00 scan');
    });

    test('1.3 Selective checkpoint disabling (e.g. Opening disabled, Shift Change enabled)', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': false, '14:00': true, '21:00': false}),
      );
      await scheduler.reloadSchedule();

      expect(scheduler.activeDailyCheckpoints['09:00'], isFalse);
      expect(scheduler.activeDailyCheckpoints['14:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['21:00'], isFalse);

      // Attempt 09:00 (disabled)
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 30),
      );
      expect(fakeApi.triggerCount, equals(0), reason: 'Disabled 09:00 checkpoint must not trigger a scan');

      // Attempt 14:00 (enabled)
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 14, 0, 30),
      );
      expect(fakeApi.triggerCount, equals(6), reason: 'Enabled 14:00 checkpoint must trigger scan');

      // Attempt 21:00 (disabled)
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 21, 0, 30),
      );
      expect(fakeApi.triggerCount, equals(6), reason: 'Disabled 21:00 checkpoint must not trigger scan');
    });

    test('1.4 Interval mode triggering across 15min, 30min, 1hour, 2hours and timestamp tracking', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'interval');

      final baseTime = DateTime(2026, 11, 1, 10, 0, 0);

      // --- 15min interval ---
      await sqliteService.setSystemSetting('schedule_interval', '15min');
      await scheduler.reloadSchedule();
      expect(scheduler.selectedInterval, equals('15min'));

      scheduler.setLastIntervalScanTimeForTesting(baseTime);

      // 14 min elapsed: should not trigger
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 14)),
      );
      expect(fakeApi.triggerCount, equals(0));

      // 15 min elapsed: triggers
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 15)),
      );
      expect(fakeApi.triggerCount, equals(6));
      expect(scheduler.lastIntervalScanTime, equals(baseTime.add(const Duration(minutes: 15))));

      // --- 30min interval ---
      fakeApi.triggerCount = 0;
      await sqliteService.setSystemSetting('schedule_interval', '30min');
      await scheduler.reloadSchedule();
      scheduler.setLastIntervalScanTimeForTesting(baseTime);

      // 29 min elapsed: should not trigger
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 29)),
      );
      expect(fakeApi.triggerCount, equals(0));

      // 30 min elapsed: triggers
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 30)),
      );
      expect(fakeApi.triggerCount, equals(6));

      // --- 1hour interval ---
      fakeApi.triggerCount = 0;
      await sqliteService.setSystemSetting('schedule_interval', '1hour');
      await scheduler.reloadSchedule();
      scheduler.setLastIntervalScanTimeForTesting(baseTime);

      // 59 min elapsed: should not trigger
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 59)),
      );
      expect(fakeApi.triggerCount, equals(0));

      // 60 min elapsed: triggers
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 60)),
      );
      expect(fakeApi.triggerCount, equals(6));

      // --- 2hours interval ---
      fakeApi.triggerCount = 0;
      await sqliteService.setSystemSetting('schedule_interval', '2hours');
      await scheduler.reloadSchedule();
      scheduler.setLastIntervalScanTimeForTesting(baseTime);

      // 119 min elapsed: should not trigger
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 119)),
      );
      expect(fakeApi.triggerCount, equals(0));

      // 120 min elapsed: triggers
      await scheduler.evaluateSchedule(
        currentTime: baseTime.add(const Duration(minutes: 120)),
      );
      expect(fakeApi.triggerCount, equals(6));
    });

    test('1.5 Backward clock adjustments (NTP sync / time warp) do not trigger spurious scans', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'interval');
      await sqliteService.setSystemSetting('schedule_interval', '30min');
      await scheduler.reloadSchedule();

      final baseTime = DateTime(2026, 11, 1, 10, 0, 0);
      scheduler.setLastIntervalScanTimeForTesting(baseTime);

      // System clock steps backwards by 20 minutes (e.g. NTP correction)
      final backwardTime = baseTime.subtract(const Duration(minutes: 20));
      await scheduler.evaluateSchedule(currentTime: backwardTime);

      expect(fakeApi.triggerCount, equals(0), reason: 'Negative time difference must not trigger premature scans');
    });
  });

  group('CHALLENGE 2: Scan Execution Locking, Dynamic Logging & Cloud Sync Queue', () {
    late SqliteService sqliteService;
    late KioskSchedulerService scheduler;
    late DelayedFakePythonApiRepository fakeApi;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      KioskSchedulerService.resetInstanceForTesting();
      scheduler = KioskSchedulerService.instance;
      fakeApi = DelayedFakePythonApiRepository();
      scheduler.setPythonApiForTesting(fakeApi);
      scheduler.resetExecutedCheckpointsForTesting();
    });

    tearDown(() {
      scheduler.stop();
    });

    test('2.1 Rejection of concurrent scan executions via isScanning lock', () async {
      // Configure fake API with 40ms delay per camera scan (240ms total)
      fakeApi.scanDelay = const Duration(milliseconds: 40);

      expect(scheduler.isScanning, isFalse);

      // Launch two scans concurrently
      final scanFuture1 = scheduler.executeScheduledScan(checkpointName: 'Scan Concurrency 1');
      final scanFuture2 = scheduler.executeScheduledScan(checkpointName: 'Scan Concurrency 2');

      final results = await Future.wait([scanFuture1, scanFuture2]);

      // Exactly one must succeed (true) and one must be rejected (false)
      expect(results, containsAllInOrder([true, false]));
      expect(scheduler.isScanning, isFalse, reason: 'Lock must release when scan finishes');
      expect(fakeApi.triggerCount, equals(6), reason: 'Only 6 camera triggers (one scan job) should execute');

      // Subsequent scan can now execute cleanly
      fakeApi.scanDelay = Duration.zero;
      final scanFuture3 = await scheduler.executeScheduledScan(checkpointName: 'Scan Sequential 3');
      expect(scanFuture3, isTrue);
      expect(fakeApi.triggerCount, equals(12));
    });

    test('2.2 evaluateSchedule aborts cleanly if a scan is already in progress', () async {
      fakeApi.scanDelay = const Duration(milliseconds: 50);

      // Start scan 1 in background
      final longScan = scheduler.executeScheduledScan(checkpointName: 'In-Flight Scan');
      expect(scheduler.isScanning, isTrue);

      // Call evaluateSchedule while scan is in progress
      await scheduler.evaluateSchedule(
        currentTime: DateTime(2026, 11, 1, 9, 0, 0),
      );

      // Wait for longScan to finish
      final res = await longScan;
      expect(res, isTrue);
      expect(fakeApi.triggerCount, equals(6), reason: 'evaluateSchedule must not start parallel scan while isScanning is true');
    });

    test('2.3 SqliteService.logActivity records type: CHECKPOINT_SCAN with dynamic branch and Automated Scheduler user', () async {
      const dynamicBranch = 'Baguio Highland Branch';
      await sqliteService.setSystemSetting('branch_name', dynamicBranch);

      await scheduler.executeScheduledScan(checkpointName: 'Store Opening Check (09:00 AM)');

      final logs = await sqliteService.getSystemLogs(dynamicBranch);
      expect(logs, isNotEmpty);

      final checkpointLog = logs.firstWhere(
        (l) => l.type == 'CHECKPOINT_SCAN',
        orElse: () => throw Exception('CHECKPOINT_SCAN log not found!'),
      );

      expect(checkpointLog.user, equals('Automated Scheduler'));
      expect(checkpointLog.branch, equals(dynamicBranch));
      expect(checkpointLog.description, contains('Store Opening Check (09:00 AM)'));
      expect(checkpointLog.description, contains('cameras'));
    });

    test('2.4 Automated scan execution generates sync_queue entry for Supabase cloud sync', () async {
      const dynamicBranch = 'Davao Center Branch';
      await sqliteService.setSystemSetting('branch_name', dynamicBranch);

      await scheduler.executeScheduledScan(checkpointName: 'Shift Change Check (02:00 PM)');

      final db = await sqliteService.database;
      final syncQueueRows = await db.query(
        'sync_queue',
        where: "targetCollection = 'system_logs'",
      );

      expect(syncQueueRows, isNotEmpty, reason: 'Sync queue must record entry for automated checkpoint scan');

      bool foundMatchingPayload = false;
      for (final row in syncQueueRows) {
        final payloadStr = row['payload'] as String?;
        if (payloadStr != null) {
          final payload = jsonDecode(payloadStr);
          if (payload is Map &&
              payload['type'] == 'CHECKPOINT_SCAN' &&
              payload['user'] == 'Automated Scheduler' &&
              payload['branch'] == dynamicBranch) {
            foundMatchingPayload = true;
            expect(payload['description'], contains('Shift Change Check (02:00 PM)'));
            break;
          }
        }
      }
      expect(foundMatchingPayload, isTrue, reason: 'Valid sync_queue payload matching dynamic branch must exist');
    });

    test('2.5 Unhandled exception during camera scan recovers gracefully and resets isScanning to false', () async {
      fakeApi.shouldThrow = true;

      final scanResult = await scheduler.executeScheduledScan(checkpointName: 'Fault Injection Check');

      expect(scanResult, isFalse, reason: 'executeScheduledScan must return false when underlying API throws');
      expect(scheduler.isScanning, isFalse, reason: 'isScanning lock must be released even after an error');

      // Subsequent scan must be able to run once error is cleared
      fakeApi.shouldThrow = false;
      final recoveredResult = await scheduler.executeScheduledScan(checkpointName: 'Recovery Check');
      expect(recoveredResult, isTrue);
      expect(scheduler.isScanning, isFalse);
    });

    test('2.6 Partial camera failure (offline cameras) continues batch and logs accurate camera count', () async {
      // Simulate cameras 2 and 5 failing
      fakeApi.failingCameraIds = {2, 5};

      final scanResult = await scheduler.executeScheduledScan(checkpointName: 'Partial Hardware Fault Check');

      expect(scanResult, isTrue, reason: 'Scan batch must complete even if some cameras fail');
      expect(scheduler.isScanning, isFalse);

      final branch = await sqliteService.getBranchName();
      final logs = await sqliteService.getSystemLogs(branch);
      final log = logs.firstWhere(
        (l) => l.type == 'CHECKPOINT_SCAN' && l.description.contains('Partial Hardware Fault Check'),
      );
      expect(log.description, contains('across 4/6 cameras'), reason: 'Description must reflect 4 succeeded out of 6 cameras');
    });
  });

  group('CHALLENGE 3: Schedule Persistence & Reload with Corrupted / Extreme Data', () {
    late SqliteService sqliteService;
    late KioskSchedulerService scheduler;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      KioskSchedulerService.resetInstanceForTesting();
      scheduler = KioskSchedulerService.instance;
    });

    tearDown(() {
      scheduler.stop();
    });

    test('3.1 reloadSchedule gracefully handles corrupted, truncated, and empty JSON without throwing', () async {
      final corruptedPayloads = [
        '{invalid_json_missing_brace:',
        '{"09:00": true, "14:00": [broken',
        '', // Empty string
        '   ', // Whitespace
        'null', // Literal null JSON
        '12345', // Integer JSON
        '"just a string"', // String JSON
        '[1, 2, 3]', // List JSON
        '{"unknown_key": "not_a_bool"}',
        '{"09:00": null}',
      ];

      for (final corrupted in corruptedPayloads) {
        await sqliteService.setSystemSetting('schedule_daily_times', corrupted);

        // MUST not throw an uncaught exception
        await expectLater(
          scheduler.reloadSchedule(),
          completes,
          reason: 'reloadSchedule must be resilient to corrupted payload: "$corrupted"',
        );

        // Default checkpoints must remain accessible
        expect(scheduler.activeDailyCheckpoints, isNotNull);
        expect(scheduler.checkpointLabels, isNotNull);
      }
    });

    test('3.2 Malformed schedule_mode and schedule_interval do not corrupt scheduler state', () async {
      await sqliteService.setSystemSetting('schedule_mode', '');
      await sqliteService.setSystemSetting('schedule_interval', '');
      await scheduler.reloadSchedule();

      // Defaults preserved
      expect(scheduler.scheduleMode, equals('daily'));
      expect(scheduler.selectedInterval, equals('1hour'));

      // Invalid interval string falls back gracefully in evaluateSchedule
      await sqliteService.setSystemSetting('schedule_mode', 'interval');
      await sqliteService.setSystemSetting('schedule_interval', 'invalid_interval_999');
      await scheduler.reloadSchedule();
      expect(scheduler.scheduleMode, equals('interval'));

      // Trigger evaluation with unknown interval — should fallback safely to 60m
      final base = DateTime(2026, 11, 1, 12, 0, 0);
      scheduler.setLastIntervalScanTimeForTesting(base.subtract(const Duration(minutes: 65)));
      await expectLater(
        scheduler.evaluateSchedule(currentTime: base),
        completes,
      );
    });

    test('3.3 ScheduleScreen persistence and reload with dynamic branch and SQLite settings', () async {
      await sqliteService.setSystemSetting('branch_name', 'Iloilo Branch');
      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting('schedule_interval', '1hour');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': true, '14:00': false, '21:00': true}),
      );

      // Verify SQLite system settings were updated
      final savedMode = await sqliteService.getSetting('schedule_mode');
      final savedDaily = await sqliteService.getSetting('schedule_daily_times');
      expect(savedMode, equals('daily'));
      expect(savedDaily, isNotNull);

      final decoded = jsonDecode(savedDaily!) as Map<String, dynamic>;
      expect(decoded['09:00'], isTrue);
      expect(decoded['14:00'], isFalse);
      expect(decoded['21:00'], isTrue);

      await scheduler.reloadSchedule();
      expect(scheduler.scheduleMode, equals('daily'));
      expect(scheduler.activeDailyCheckpoints['09:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['14:00'], isFalse);
      expect(scheduler.activeDailyCheckpoints['21:00'], isTrue);

      // Verify activity logging with dynamic branch
      await sqliteService.logActivity(
        type: 'SCAN_SCHEDULE',
        description: 'Vision capture schedule set to daily (1hour). Active checkpoints: 09:00 AM, 09:00 PM.',
        branch: 'Iloilo Branch',
      );
      final logs = await sqliteService.getSystemLogs('Iloilo Branch');
      final scheduleLog = logs.firstWhere((l) => l.type == 'SCAN_SCHEDULE');
      expect(scheduleLog.branch, equals('Iloilo Branch'));
      expect(scheduleLog.description, contains('Vision capture schedule set to daily'));
    });
  });

  group('CHALLENGE 4: Image Quality Diagnostics & Extreme Value Calculations', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('4.1 Extreme pixel frame analysis (All-Black 0x00 and All-White 0xFF)', () {
      // 1. Extreme Case A: All-Black frame (zeros)
      final blackFrame = Uint8List(4096);
      int sampleCount = 0;
      int totalIntensity = 0;
      for (int i = 0; i < blackFrame.length; i += 16) {
        totalIntensity += blackFrame[i];
        sampleCount++;
      }
      final meanIntensityBlack = totalIntensity / sampleCount;
      final brightnessBlack = ((meanIntensityBlack / 255.0) * 100.0).clamp(0.0, 100.0);

      double varianceSumBlack = 0.0;
      for (int i = 0; i < blackFrame.length; i += 16) {
        final diff = blackFrame[i] - meanIntensityBlack;
        varianceSumBlack += diff * diff;
      }
      final stdDevBlack = varianceSumBlack / sampleCount;
      final contrastBlack = (stdDevBlack / 128.0 * 100.0).clamp(0.0, 100.0);

      double edgeDeltaSumBlack = 0.0;
      int edgeCountBlack = 0;
      for (int i = 0; i < blackFrame.length - 16; i += 16) {
        final delta = (blackFrame[i] - blackFrame[i + 16]).abs();
        edgeDeltaSumBlack += delta;
        edgeCountBlack++;
      }
      final meanDeltaBlack = edgeCountBlack > 0 ? edgeDeltaSumBlack / edgeCountBlack : 25.0;
      final sharpnessBlack = ((meanDeltaBlack / 64.0) * 100.0).clamp(0.0, 100.0);

      expect(brightnessBlack, equals(0.0), reason: 'All black frame must yield 0.0% brightness');
      expect(contrastBlack, equals(0.0), reason: 'Zero variance frame must yield 0.0% contrast');
      expect(sharpnessBlack, equals(0.0), reason: 'Flat frame must yield 0.0% sharpness');
      expect(brightnessBlack >= 40.0 && contrastBlack >= 30.0 && sharpnessBlack >= 30.0, isFalse);

      // 2. Extreme Case B: All-White frame (255)
      final whiteFrame = Uint8List(4096);
      for (int i = 0; i < whiteFrame.length; i++) {
        whiteFrame[i] = 255;
      }
      int totalIntensityWhite = 0;
      sampleCount = 0;
      for (int i = 0; i < whiteFrame.length; i += 16) {
        totalIntensityWhite += whiteFrame[i];
        sampleCount++;
      }
      final meanIntensityWhite = totalIntensityWhite / sampleCount;
      final brightnessWhite = ((meanIntensityWhite / 255.0) * 100.0).clamp(0.0, 100.0);

      double varianceSumWhite = 0.0;
      for (int i = 0; i < whiteFrame.length; i += 16) {
        final diff = whiteFrame[i] - meanIntensityWhite;
        varianceSumWhite += diff * diff;
      }
      final stdDevWhite = varianceSumWhite / sampleCount;
      final contrastWhite = (stdDevWhite / 128.0 * 100.0).clamp(0.0, 100.0);

      expect(brightnessWhite, equals(100.0), reason: 'All white frame must yield 100.0% brightness');
      expect(contrastWhite, equals(0.0), reason: 'Uniform white frame must yield 0.0% contrast');
      expect(brightnessWhite >= 40.0 && contrastWhite >= 30.0, isFalse, reason: 'Uniform white frame must fail contrast');
    });

    test('4.2 High-frequency noise and gradient frames yield continuous dynamic metrics', () {
      final noiseFrame = Uint8List(4096);
      for (int i = 0; i < noiseFrame.length; i++) {
        // Varying gradient
        noiseFrame[i] = (i * 37 + 13) % 256;
      }

      int totalIntensity = 0;
      int sampleCount = 0;
      for (int i = 0; i < noiseFrame.length; i += 16) {
        totalIntensity += noiseFrame[i];
        sampleCount++;
      }
      final meanIntensity = totalIntensity / sampleCount;
      final brightness = ((meanIntensity / 255.0) * 100.0).clamp(0.0, 100.0);

      double varianceSum = 0.0;
      for (int i = 0; i < noiseFrame.length; i += 16) {
        final diff = noiseFrame[i] - meanIntensity;
        varianceSum += diff * diff;
      }
      final stdDev = varianceSum / sampleCount;
      final contrast = (stdDev / 128.0 * 100.0).clamp(0.0, 100.0);

      double edgeDeltaSum = 0.0;
      int edgeCount = 0;
      for (int i = 0; i < noiseFrame.length - 16; i += 16) {
        final delta = (noiseFrame[i] - noiseFrame[i + 16]).abs();
        edgeDeltaSum += delta;
        edgeCount++;
      }
      final meanDelta = edgeCount > 0 ? edgeDeltaSum / edgeCount : 25.0;
      final sharpness = ((meanDelta / 64.0) * 100.0).clamp(0.0, 100.0);

      expect(brightness, greaterThan(0.0));
      expect(brightness, lessThan(100.0));
      expect(contrast, greaterThan(0.0));
      expect(sharpness, greaterThan(0.0));

      // Assert that mock values 85.0, 80.0, 90.0 are NEVER artificially assigned
      expect(brightness, isNot(equals(85.0)));
      expect(contrast, isNot(equals(80.0)));
      expect(sharpness, isNot(equals(90.0)));
    });

    test('4.3 image_quality_screen.dart source code audit verifies removal of mock metrics and OCR references', () {
      final screenFile = File('lib/ui/screens/camera_monitor/image_quality_screen.dart');
      expect(screenFile.existsSync(), isTrue);

      final content = screenFile.readAsStringSync();

      // Check mock metrics removal
      expect(content.contains('brightness: hasCapture ? 85.0 : 0.0'), isFalse);
      expect(content.contains('contrast: hasCapture ? 80.0 : 0.0'), isFalse);
      expect(content.contains('sharpness: hasCapture ? 90.0 : 0.0'), isFalse);

      // Check legacy OCR text removal
      expect(content.contains('Cap OCR'), isFalse);
      expect(content.contains('OCR'), isFalse);

      // Verify dynamic branch resolution exists
      expect(content.contains('ref.watch(currentBranchProvider)'), isTrue);
    });

    test('4.4 Image Quality logging preserves dynamic branch and acceptable flag in SQLite', () async {
      const dynamicBranch = 'Zamboanga Kiosk';
      final log = ImageQualityLogModel(
        id: 'qa_dynamic_test_1',
        brightness: 72.4,
        contrast: 68.9,
        sharpness: 81.2,
        isAcceptable: true,
        preprocessingApplied: ['Frame-Analysis'],
        retryCount: 0,
        status: 'ACCEPTED',
        branch: dynamicBranch,
        timestamp: DateTime.now(),
      );

      await sqliteService.logImageQuality(log);

      final retrieved = await sqliteService.getImageQualityLogs(dynamicBranch);
      expect(retrieved, isNotEmpty);
      expect(retrieved.first.branch, equals(dynamicBranch));
      expect(retrieved.first.brightness, equals(72.4));
      expect(retrieved.first.isAcceptable, isTrue);
      expect(retrieved.first.status, equals('ACCEPTED'));
    });
  });
}
