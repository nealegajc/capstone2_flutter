import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/camera_hardware_service.dart';
import 'package:smart_shelf_linux/data/services/kiosk_scheduler_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';

/// Helper to set process environment variables via libc setenv
void setLinuxEnv(String key, String value) {
  try {
    final libc = DynamicLibrary.process();
    final setenv = libc.lookupFunction<
        Int32 Function(Pointer<Uint8>, Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, Pointer<Uint8>, int)>('setenv');
    final mallocFunc = libc.lookupFunction<
        Pointer<Uint8> Function(IntPtr),
        Pointer<Uint8> Function(int)>('malloc');
    final freeFunc = libc.lookupFunction<
        Void Function(Pointer<Uint8>),
        void Function(Pointer<Uint8>)>('free');

    Pointer<Uint8> toNative(String str) {
      final bytes = str.codeUnits;
      final ptr = mallocFunc(bytes.length + 1);
      for (int i = 0; i < bytes.length; i++) {
        ptr[i] = bytes[i];
      }
      ptr[bytes.length] = 0;
      return ptr;
    }

    final kPtr = toNative(key);
    final vPtr = toNative(value);
    setenv(kPtr, vPtr, 1);
    freeFunc(kPtr);
    freeFunc(vPtr);
  } catch (e) {
    // Non-Linux or FFI unavailable fallback
  }
}

/// Controllable mock Python API repository for testing multi-camera scan execution & faults
class MockPythonApiRepository extends PythonApiRepository {
  int triggerCount = 0;
  final List<int> requestedCameraIds = [];
  final List<String?> requestedCameraDevices = [];
  final Set<int> failingCameraIds = {};
  final Set<int> throwingCameraIds = {};
  Duration scanDelay = Duration.zero;

  void reset() {
    triggerCount = 0;
    requestedCameraIds.clear();
    requestedCameraDevices.clear();
    failingCameraIds.clear();
    throwingCameraIds.clear();
    scanDelay = Duration.zero;
  }

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
    final camId = cameraId ?? 1;
    requestedCameraIds.add(camId);
    requestedCameraDevices.add(cameraDevice);

    if (throwingCameraIds.contains(camId)) {
      throw const SocketException('Connection refused: Camera bus timed out');
    }

    if (failingCameraIds.contains(camId)) {
      return {
        'success': false,
        'error': 'Camera $camId hardware read error (V4L2 device timeout)',
        'cameraId': camId,
        'totalBottles': 0,
      };
    }

    // Generate balanced detections for the camera's default trays
    final trays = SqliteService.getDefaultTrayCodesForCamera(camId);
    final detections = <Map<String, dynamic>>[];
    final trayCounts = <String, int>{};

    for (final tray in trays) {
      final trayKey = 'tray_$tray';
      trayCounts[trayKey] = 2; // 2 bottles per tray
      detections.add({'roiId': trayKey, 'centerX': 0.1, 'centerY': 0.5});
      detections.add({'roiId': trayKey, 'centerX': 0.2, 'centerY': 0.5});
    }

    return {
      'success': true,
      'cameraId': camId,
      'device': cameraDevice,
      'totalBottles': detections.length,
      'bottlesDetected': detections.length,
      'trayCounts': trayCounts,
      'detections': detections,
    };
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // Set up mock ffmpeg for streaming tests so ffmpeg process stays alive until killed
    try {
      final mockBinDir = Directory('/tmp/mock_ffmpeg_bin');
      if (!mockBinDir.existsSync()) {
        mockBinDir.createSync(recursive: true);
      }
      final mockFfmpeg = File('${mockBinDir.path}/ffmpeg');
      mockFfmpeg.writeAsStringSync('#!/bin/sh\nsleep 120\n');
      Process.runSync('chmod', ['+x', mockFfmpeg.path]);

      final currentPath = Platform.environment['PATH'] ?? '';
      setLinuxEnv('PATH', '${mockBinDir.path}:$currentPath');
    } catch (_) {}
  });

  group('CHALLENGER M3: Multi-Camera Automated Scan Pipeline Simulation', () {
    late SqliteService sqliteService;
    late KioskSchedulerService scheduler;
    late MockPythonApiRepository mockApi;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      KioskSchedulerService.resetInstanceForTesting();
      scheduler = KioskSchedulerService.instance;
      mockApi = MockPythonApiRepository();
      scheduler.setPythonApiForTesting(mockApi);
      scheduler.resetExecutedCheckpointsForTesting();
    });

    tearDown(() async {
      scheduler.stop();
      if (CameraHardwareService.instance.isStreaming) {
        await CameraHardwareService.instance.stopLiveStream();
      }
    });

    test('1. Full 6-camera scheduled scan iterates all zones with correct devices and slot updates', () async {
      const branch = 'San Pablo Test';
      await sqliteService.setSystemSetting('branch_name', branch);

      final success = await scheduler.executeScheduledScan(
        checkpointName: 'Store Opening Check (09:00 AM)',
      );

      expect(success, isTrue);
      expect(mockApi.triggerCount, equals(6));
      expect(mockApi.requestedCameraIds, equals([1, 2, 3, 4, 5, 6]));

      // Verify assigned hardware nodes are passed
      final hw = CameraHardwareService.instance;
      for (int i = 0; i < 6; i++) {
        final camId = i + 1;
        expect(
          mockApi.requestedCameraDevices[i],
          equals(hw.getAssignedDeviceNode(camId)),
          reason: 'Camera $camId must use its hardware node assignment',
        );
      }

      // Verify activity log
      final logs = await sqliteService.getSystemLogs(branch);
      expect(logs, isNotEmpty);
      final log = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(log.user, equals('Automated Scheduler'));
      expect(log.branch, equals(branch));
      expect(log.description, contains('6/6 cameras'));
      // 5 trays * 2 bottles = 10 bottles per camera * 6 cameras = 60 bottles
      expect(log.description, contains('60 bottles detected'));

      // Verify sync_queue enqueued
      final db = await sqliteService.database;
      final syncItems = await db.query(
        'sync_queue',
        where: "targetCollection = 'system_logs'",
      );
      expect(syncItems, isNotEmpty);
    });

    test('2. Streaming camera interruption: scheduler stops live stream before capturing frames', () async {
      final hw = CameraHardwareService.instance;

      // Start live stream
      await hw.startLiveStream();
      expect(hw.isStreaming, isTrue, reason: 'CameraHardwareService should report isStreaming = true');

      // Trigger scheduled scan while streaming is active
      final scanSuccess = await scheduler.executeScheduledScan(
        checkpointName: 'Midday Quality Scan',
      );

      expect(scanSuccess, isTrue);
      // Stream must have been stopped during scan execution
      expect(hw.isStreaming, isFalse, reason: 'Live stream must be stopped before frame captures');
      expect(mockApi.triggerCount, equals(6), reason: 'All 6 cameras must be scanned');

      // Verify live stream can be cleanly restarted after scan completion
      await hw.startLiveStream();
      expect(hw.isStreaming, isTrue, reason: 'Live stream must be restartable after scan completes');
      await hw.stopLiveStream();
      expect(hw.isStreaming, isFalse);
    });

    test('3. Partial camera failure resilience: Camera 3 fails, remaining 5 cameras proceed', () async {
      const branch = 'San Pablo Test';
      await sqliteService.setSystemSetting('branch_name', branch);

      // Simulate Camera 3 failure
      mockApi.failingCameraIds.add(3);

      final result = await scheduler.executeScheduledScan(
        checkpointName: 'Shift Change Check (02:00 PM)',
      );

      // executeScheduledScan returns true because 5 cameras succeeded
      expect(result, isTrue);
      expect(mockApi.triggerCount, equals(6), reason: 'All 6 cameras must be attempted');
      expect(mockApi.requestedCameraIds, equals([1, 2, 3, 4, 5, 6]));

      // Verify activity log accurately records 5/6 cameras and 50 bottles
      final logs = await sqliteService.getSystemLogs(branch);
      final log = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(log.description, contains('5/6 cameras'));
      expect(log.description, contains('50 bottles detected'));
    });

    test('4. Multi-camera failure resilience: Cameras 2 and 5 fail, remaining 4 proceed', () async {
      const branch = 'San Pablo Test';
      await sqliteService.setSystemSetting('branch_name', branch);

      mockApi.failingCameraIds.addAll([2, 5]);

      final result = await scheduler.executeScheduledScan(
        checkpointName: 'Store Closing Check (09:00 PM)',
      );

      expect(result, isTrue);
      expect(mockApi.triggerCount, equals(6));

      final logs = await sqliteService.getSystemLogs(branch);
      final log = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(log.description, contains('4/6 cameras'));
      // 4 cameras * 10 bottles = 40 bottles
      expect(log.description, contains('40 bottles detected'));
    });

    test('5. Complete camera failure resilience: all 6 cameras fail without crash', () async {
      const branch = 'San Pablo Test';
      await sqliteService.setSystemSetting('branch_name', branch);

      mockApi.failingCameraIds.addAll([1, 2, 3, 4, 5, 6]);

      final result = await scheduler.executeScheduledScan(
        checkpointName: 'Complete Hardware Blackout Scan',
      );

      expect(result, isTrue);
      expect(mockApi.triggerCount, equals(6));

      final logs = await sqliteService.getSystemLogs(branch);
      final log = logs.firstWhere((l) => l.type == 'CHECKPOINT_SCAN');
      expect(log.description, contains('0/6 cameras'));
      expect(log.description, contains('0 bottles detected'));
    });

    test('6. Unhandled camera exception resilience: scheduler catches and safely aborts without crash', () async {
      mockApi.throwingCameraIds.add(4);

      // Should not throw uncaught exception
      final result = await scheduler.executeScheduledScan(
        checkpointName: 'Exception Handling Scan',
      );

      expect(result, isFalse, reason: 'Scan must return false when an unhandled exception occurs');
      expect(scheduler.isScanning, isFalse, reason: 'isScanning lock must be released even on failure');

      // Subsequent scan should still be able to execute normally
      mockApi.reset();
      final subsequentResult = await scheduler.executeScheduledScan(
        checkpointName: 'Subsequent Recovery Scan',
      );
      expect(subsequentResult, isTrue);
      expect(mockApi.triggerCount, equals(6));
    });

    test('7. Concurrent scan rejection: lock prevents overlapping executions', () async {
      mockApi.scanDelay = const Duration(milliseconds: 60);

      final futureScan1 = scheduler.executeScheduledScan(checkpointName: 'Concurrent Batch 1');
      final futureScan2 = scheduler.executeScheduledScan(checkpointName: 'Concurrent Batch 2');

      final outcomes = await Future.wait([futureScan1, futureScan2]);

      expect(outcomes, containsAllInOrder([true, false]));
      expect(scheduler.isScanning, isFalse);
      expect(mockApi.triggerCount, equals(6), reason: 'Only the accepted scan runs');
    });
  });
}
