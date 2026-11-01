import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../repositories/python_api_repository.dart';
import 'camera_hardware_service.dart';
import 'sqlite_service.dart';

class KioskSchedulerService extends ChangeNotifier {
  static KioskSchedulerService? _instance;
  static KioskSchedulerService get instance =>
      _instance ??= KioskSchedulerService._();

  KioskSchedulerService._();

  PythonApiRepository _pythonApi = PythonApiRepository();
  Timer? _tickerTimer;
  bool _isScanning = false;
  String _scheduleMode = 'daily'; // 'daily' or 'interval'
  String _selectedInterval = '1hour';

  // Fixed checkpoint times (HH:mm in 24h format) -> label
  static const Map<String, String> defaultCheckpointLabels = {
    '09:00': 'Store Opening Check (09:00 AM)',
    '14:00': 'Shift Change Check (02:00 PM)',
    '21:00': 'Store Closing Check (09:00 PM)',
  };

  Map<String, bool> _activeDailyCheckpoints = {
    '09:00': true,
    '14:00': true,
    '21:00': true,
  };

  final Set<String> _executedCheckpointsToday = {};
  DateTime? _lastIntervalScanTime;

  bool get isScanning => _isScanning;
  String get scheduleMode => _scheduleMode;
  String get selectedInterval => _selectedInterval;
  Map<String, bool> get activeDailyCheckpoints =>
      Map.unmodifiable(_activeDailyCheckpoints);
  Map<String, String> get checkpointLabels => defaultCheckpointLabels;
  DateTime? get lastIntervalScanTime => _lastIntervalScanTime;

  @visibleForTesting
  void setPythonApiForTesting(PythonApiRepository api) {
    _pythonApi = api;
  }

  @visibleForTesting
  void setLastIntervalScanTimeForTesting(DateTime? time) {
    _lastIntervalScanTime = time;
  }

  @visibleForTesting
  void resetExecutedCheckpointsForTesting() {
    _executedCheckpointsToday.clear();
    _lastIntervalScanTime = null;
  }

  @visibleForTesting
  static void resetInstanceForTesting() {
    _instance?.stop();
    _instance = null;
  }

  Future<void> initialize() async {
    await reloadSchedule();
    start();
  }

  void start() {
    _tickerTimer?.cancel();
    _lastIntervalScanTime ??= DateTime.now();
    _tickerTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => evaluateSchedule(),
    );
  }

  void stop() {
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  Future<void> reloadSchedule() async {
    try {
      final mode = await SqliteService.instance.getSetting('schedule_mode');
      final interval =
          await SqliteService.instance.getSetting('schedule_interval');
      final dailyTimesJson =
          await SqliteService.instance.getSetting('schedule_daily_times');

      if (mode != null && mode.isNotEmpty) _scheduleMode = mode;
      if (interval != null && interval.isNotEmpty) _selectedInterval = interval;

      if (dailyTimesJson != null && dailyTimesJson.isNotEmpty) {
        final decoded = jsonDecode(dailyTimesJson);
        if (decoded is Map<String, dynamic>) {
          final updated = <String, bool>{};
          for (final entry in decoded.entries) {
            final key = entry.key.contains(':')
                ? entry.key.substring(0, 5)
                : entry.key;
            updated[key] = entry.value == true ||
                entry.value == 1 ||
                entry.value == 'true';
          }
          for (final defKey in defaultCheckpointLabels.keys) {
            if (!updated.containsKey(defKey)) {
              updated[defKey] = true;
            }
          }
          _activeDailyCheckpoints = updated;
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[KioskSchedulerService] Error loading schedule: $e');
    }
  }

  Future<void> evaluateSchedule({DateTime? currentTime}) async {
    if (_isScanning) return;
    final now = currentTime ?? DateTime.now();

    if (_scheduleMode == 'interval') {
      int intervalMinutes = 60;
      switch (_selectedInterval) {
        case '15min':
          intervalMinutes = 15;
          break;
        case '30min':
          intervalMinutes = 30;
          break;
        case '1hour':
          intervalMinutes = 60;
          break;
        case '2hours':
          intervalMinutes = 120;
          break;
      }

      if (_lastIntervalScanTime == null ||
          now.difference(_lastIntervalScanTime!).inMinutes >= intervalMinutes) {
        _lastIntervalScanTime = now;
        await executeScheduledScan(
          checkpointName: 'Interval Scan ($_selectedInterval)',
        );
      }
    } else {
      // Daily Fixed Checkpoints (Store Opening: 09:00, Shift Change: 14:00, Store Closing: 21:00)
      final timeKey =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final executionKey =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_$timeKey';

      if (_activeDailyCheckpoints[timeKey] == true &&
          !_executedCheckpointsToday.contains(executionKey)) {
        _executedCheckpointsToday.add(executionKey);
        final label =
            defaultCheckpointLabels[timeKey] ?? 'Scheduled Check ($timeKey)';
        await executeScheduledScan(checkpointName: label);
      }
    }
  }

  Future<bool> executeScheduledScan({required String checkpointName}) async {
    if (_isScanning) return false;
    _isScanning = true;
    notifyListeners();

    int totalBottlesAcrossCams = 0;
    int succeededCams = 0;

    try {
      final hwService = CameraHardwareService.instance;
      final branch = await SqliteService.instance.getBranchName();

      if (hwService.isStreaming) {
        await hwService.stopLiveStream();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      for (int camId = 1; camId <= 6; camId++) {
        final targetNode = hwService.getAssignedDeviceNode(camId);
        final scanResult = await _pythonApi.triggerManualScan(
          branch,
          cameraId: camId,
          cameraDevice: targetNode,
        );

        if (scanResult['success'] == true) {
          succeededCams++;
          final rawDets = scanResult['detections'];
          final List<Map<String, dynamic>> detectionsList = (rawDets is List)
              ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
              : <Map<String, dynamic>>[];

          final cameraSlotCodes = SqliteService.getSlotCodesForCamera(camId);
          final counts =
              await SqliteService.instance.updateInventoryFromDetections(
            cameraId: camId,
            detections: detectionsList,
            branch: branch,
            targetSlotCodes: cameraSlotCodes,
          );
          totalBottlesAcrossCams += counts.values.fold(0, (a, b) => a + b);
        }
      }

      // Log automated checkpoint completion to system_logs and enqueue to sync_queue
      await SqliteService.instance.logActivity(
        type: 'CHECKPOINT_SCAN',
        description:
            'Automated checkpoint shelf scan completed ($checkpointName). '
            '$totalBottlesAcrossCams bottles detected across $succeededCams/6 cameras.',
        user: 'Automated Scheduler',
        branch: branch,
        enqueueSync: true,
      );

      debugPrint(
        '[KioskSchedulerService] Checkpoint scan ($checkpointName) completed: '
        '$totalBottlesAcrossCams bottles detected across $succeededCams/6 cameras.',
      );
      return true;
    } catch (e) {
      debugPrint('[KioskSchedulerService] Checkpoint scan error: $e');
      return false;
    } finally {
      _isScanning = false;
      notifyListeners();
    }
  }
}
