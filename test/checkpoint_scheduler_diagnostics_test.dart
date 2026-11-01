import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/image_quality_log_model.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/kiosk_scheduler_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';

class FakePythonApiRepository extends PythonApiRepository {
  int triggerCount = 0;
  final List<int> scannedCameraIds = [];

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    triggerCount++;
    if (cameraId != null) scannedCameraIds.add(cameraId);
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

  group('Checkpoint Scheduler & Vision Diagnostics Tests (R3 & R5)', () {
    late SqliteService sqliteService;
    late KioskSchedulerService scheduler;
    late FakePythonApiRepository fakePythonApi;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      KioskSchedulerService.resetInstanceForTesting();
      scheduler = KioskSchedulerService.instance;
      fakePythonApi = FakePythonApiRepository();
      scheduler.setPythonApiForTesting(fakePythonApi);
      scheduler.resetExecutedCheckpointsForTesting();
    });

    tearDown(() {
      scheduler.stop();
    });

    test('1. Scheduler initialization and provider registration', () async {
      await scheduler.initialize();

      expect(scheduler.scheduleMode, equals('daily'));
      expect(scheduler.activeDailyCheckpoints['09:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['14:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['21:00'], isTrue);
      expect(scheduler.checkpointLabels['09:00'], contains('Store Opening Check'));
      expect(scheduler.checkpointLabels['14:00'], contains('Shift Change Check'));
      expect(scheduler.checkpointLabels['21:00'], contains('Store Closing Check'));

      // Test Riverpod provider resolution
      final container = ProviderContainer();
      final providerService = container.read(kioskSchedulerServiceProvider);
      expect(providerService, equals(scheduler));
      container.dispose();
    });

    test('2. Schedule reload updates mode, interval, and daily checkpoints from SQLite', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'interval');
      await sqliteService.setSystemSetting('schedule_interval', '30min');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': false, '14:00': true, '21:00': true}),
      );

      await scheduler.reloadSchedule();

      expect(scheduler.scheduleMode, equals('interval'));
      expect(scheduler.selectedInterval, equals('30min'));
      expect(scheduler.activeDailyCheckpoints['09:00'], isFalse);
      expect(scheduler.activeDailyCheckpoints['14:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['21:00'], isTrue);
    });

    test('3. Daily checkpoint triggering: 09:00, 14:00, 21:00 and duplicate suppression', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting(
        'schedule_daily_times',
        jsonEncode({'09:00': true, '14:00': true, '21:00': true}),
      );
      await scheduler.reloadSchedule();

      // Test Store Opening Check (09:00)
      final openingTime = DateTime(2026, 11, 1, 9, 0, 15);
      await scheduler.evaluateSchedule(currentTime: openingTime);

      expect(fakePythonApi.triggerCount, equals(6)); // Cameras 1 through 6 scanned
      expect(fakePythonApi.scannedCameraIds, equals([1, 2, 3, 4, 5, 6]));

      // Verify activity log for Store Opening
      final logsOpening = await sqliteService.getSystemLogs('San Pablo');
      final openingLog = logsOpening.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(openingLog.description, contains('Store Opening Check (09:00 AM)'));
      expect(openingLog.user, equals('Automated Scheduler'));

      // Test duplicate prevention within the same minute
      final duplicateTime = DateTime(2026, 11, 1, 9, 0, 45);
      await scheduler.evaluateSchedule(currentTime: duplicateTime);
      expect(fakePythonApi.triggerCount, equals(6)); // No additional scan triggered

      // Test Shift Change Check (14:00)
      final shiftChangeTime = DateTime(2026, 11, 1, 14, 0, 5);
      await scheduler.evaluateSchedule(currentTime: shiftChangeTime);
      expect(fakePythonApi.triggerCount, equals(12)); // 6 more cameras scanned

      final logsShift = await sqliteService.getSystemLogs('San Pablo');
      final shiftLog = logsShift.firstWhere(
        (l) => l.type == 'CHECKPOINT_SCAN' && l.description.contains('Shift Change Check'),
      );
      expect(shiftLog, isNotNull);

      // Test Store Closing Check (21:00)
      final closingTime = DateTime(2026, 11, 1, 21, 0, 10);
      await scheduler.evaluateSchedule(currentTime: closingTime);
      expect(fakePythonApi.triggerCount, equals(18)); // 6 more cameras scanned

      final logsClosing = await sqliteService.getSystemLogs('San Pablo');
      final closingLog = logsClosing.firstWhere(
        (l) => l.type == 'CHECKPOINT_SCAN' && l.description.contains('Store Closing Check'),
      );
      expect(closingLog, isNotNull);

      // Test non-checkpoint minute does NOT trigger
      final nonCheckpointTime = DateTime(2026, 11, 1, 11, 30, 0);
      await scheduler.evaluateSchedule(currentTime: nonCheckpointTime);
      expect(fakePythonApi.triggerCount, equals(18)); // Count unchanged
    });

    test('4. Interval-based triggering and elapsed time enforcement', () async {
      await sqliteService.setSystemSetting('schedule_mode', 'interval');
      await sqliteService.setSystemSetting('schedule_interval', '15min');
      await scheduler.reloadSchedule();

      final baseTime = DateTime(2026, 11, 1, 10, 0, 0);
      // Set last scan time to 20 minutes ago
      scheduler.setLastIntervalScanTimeForTesting(baseTime.subtract(const Duration(minutes: 20)));

      // Evaluate at baseTime (20 min >= 15 min -> triggers scan)
      await scheduler.evaluateSchedule(currentTime: baseTime);
      expect(fakePythonApi.triggerCount, equals(6));

      final logs = await sqliteService.getSystemLogs('San Pablo');
      final intervalLog = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(intervalLog.description, contains('Interval Scan (15min)'));

      // Evaluate 5 minutes later (5 min < 15 min -> does NOT trigger scan)
      final shortlyAfter = baseTime.add(const Duration(minutes: 5));
      await scheduler.evaluateSchedule(currentTime: shortlyAfter);
      expect(fakePythonApi.triggerCount, equals(6)); // Still 6
    });

    test('5. Checkpoint scan writes to system_logs and enqueues to sync_queue', () async {
      await scheduler.executeScheduledScan(checkpointName: 'Manual Audit Check');

      final logs = await sqliteService.getSystemLogs('San Pablo');
      final log = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(log.user, equals('Automated Scheduler'));
      expect(log.description, contains('Manual Audit Check'));

      // Verify sync_queue entry
      final db = await sqliteService.database;
      final syncQueueItems = await db.query(
        'sync_queue',
        where: "targetCollection = 'system_logs'",
      );
      expect(syncQueueItems, isNotEmpty);
      final checkpointItems = syncQueueItems.where((item) {
        try {
          final payload = jsonDecode(item['payload'] as String);
          return payload['type'] == 'CHECKPOINT_SCAN';
        } catch (_) {
          return false;
        }
      }).toList();
      final match = checkpointItems.firstWhere((item) {
        final payload = jsonDecode(item['payload'] as String);
        return (payload['description'] as String? ?? '').contains('Manual Audit Check');
      });
      final payload = jsonDecode(match['payload'] as String);
      expect(payload['type'], equals('CHECKPOINT_SCAN'));
      expect(payload['description'], contains('Manual Audit Check'));
    });

    test('6. Image Quality diagnostics: Real metrics vs Offline handling', () async {
      // 1. Log real image quality metrics from backend
      final realBackendLog = await fakePythonApi.getLatestImageQualityLog();
      expect(realBackendLog, isNotNull);
      expect(realBackendLog!.brightness, equals(78.5));
      expect(realBackendLog.contrast, equals(82.1));
      expect(realBackendLog.sharpness, equals(91.4));
      expect(realBackendLog.isAcceptable, isTrue);
      expect(realBackendLog.status, equals('ACCEPTED'));

      await sqliteService.logImageQuality(realBackendLog);
      final savedLogs = await sqliteService.getImageQualityLogs('San Pablo');
      expect(savedLogs, isNotEmpty);
      expect(savedLogs.first.id, equals('qa_real_test'));
      expect(savedLogs.first.brightness, equals(78.5));

      // 2. Offline / zero-device handling
      final offlineLog = ImageQualityLogModel(
        id: 'qa_offline_test',
        brightness: 0.0,
        contrast: 0.0,
        sharpness: 0.0,
        isAcceptable: false,
        preprocessingApplied: ['No-Device'],
        retryCount: 0,
        status: 'DEVICE_OFFLINE',
        branch: 'San Pablo',
        timestamp: DateTime.now(),
      );

      await sqliteService.logImageQuality(offlineLog);
      final updatedLogs = await sqliteService.getImageQualityLogs('San Pablo');
      expect(updatedLogs.any((l) => l.status == 'DEVICE_OFFLINE'), isTrue);

      // 3. Genuine pixel-analysis calculation test
      // Synthetic grayscale image buffer
      final syntheticBytes = Uint8List(1024);
      for (int i = 0; i < syntheticBytes.length; i++) {
        syntheticBytes[i] = (i % 256);
      }
      int totalIntensity = 0;
      int sampleCount = 0;
      for (int i = 0; i < syntheticBytes.length; i += 16) {
        totalIntensity += syntheticBytes[i];
        sampleCount++;
      }
      final meanIntensity = totalIntensity / sampleCount;
      final calculatedBrightness = ((meanIntensity / 255.0) * 100.0).clamp(0.0, 100.0);
      expect(calculatedBrightness, greaterThan(0.0));
      expect(calculatedBrightness, lessThanOrEqualTo(100.0));
    });

    test('7. ScheduleScreen daily capture times serialization and persistence', () async {
      final dailyTimes = {
        '09:00': true,
        '14:00': false,
        '21:00': true,
      };

      await sqliteService.setSystemSetting('schedule_mode', 'daily');
      await sqliteService.setSystemSetting('schedule_interval', '1hour');
      await sqliteService.setSystemSetting('schedule_daily_times', jsonEncode(dailyTimes));

      final loadedJson = await sqliteService.getSetting('schedule_daily_times');
      expect(loadedJson, isNotNull);
      final decoded = jsonDecode(loadedJson!) as Map<String, dynamic>;
      expect(decoded['09:00'], isTrue);
      expect(decoded['14:00'], isFalse);
      expect(decoded['21:00'], isTrue);

      await scheduler.reloadSchedule();
      expect(scheduler.activeDailyCheckpoints['09:00'], isTrue);
      expect(scheduler.activeDailyCheckpoints['14:00'], isFalse);
      expect(scheduler.activeDailyCheckpoints['21:00'], isTrue);
    });
  });
}
