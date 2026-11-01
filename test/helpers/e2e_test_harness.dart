import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';

/// Test Infrastructure Harness for Otto Scents Smart Shelf E2E Tests.
/// Encapsulates specifications and interface contracts across R1 through R5.

// =============================================================================
// R1: SECURITY & PBKDF2 HARNESS
// =============================================================================
class Pbkdf2Harness {
  static const int defaultIterations = 100000;
  static const int defaultKeyLength = 32;
  static const String defaultMasterRecoveryKey = 'OTTO-MASTER-RECOVERY-2026';

  /// Derives PBKDF2-HMAC-SHA256 key from password and salt.
  static Uint8List pbkdf2HmacSha256({
    required String password,
    required List<int> salt,
    int iterations = defaultIterations,
    int derivedKeyLength = defaultKeyLength,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password));
    final numBlocks = (derivedKeyLength / 32).ceil();
    final result = Uint8List(derivedKeyLength);

    for (int blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      final blockBytes = Uint8List(salt.length + 4);
      blockBytes.setRange(0, salt.length, salt);
      blockBytes[salt.length] = (blockIndex >> 24) & 0xff;
      blockBytes[salt.length + 1] = (blockIndex >> 16) & 0xff;
      blockBytes[salt.length + 2] = (blockIndex >> 8) & 0xff;
      blockBytes[salt.length + 3] = blockIndex & 0xff;

      var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
      final blockResult = Uint8List.fromList(u);

      for (int iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int i = 0; i < 32; i++) {
          blockResult[i] ^= u[i];
        }
      }

      final destOffset = (blockIndex - 1) * 32;
      final lengthToCopy = (derivedKeyLength - destOffset).clamp(0, 32);
      result.setRange(destOffset, destOffset + lengthToCopy, blockResult);
    }

    return result;
  }

  /// Generates a cryptographically secure random salt.
  static Uint8List generateSalt([int length = 32]) {
    final rng = Random.secure();
    final salt = Uint8List(length);
    for (int i = 0; i < length; i++) {
      salt[i] = rng.nextInt(256);
    }
    return salt;
  }

  /// Converts byte array to lowercase hexadecimal string.
  static String toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Parses hexadecimal string to byte array.
  static Uint8List fromHex(String hex) {
    final clean = hex.replaceAll(' ', '');
    final result = Uint8List(clean.length ~/ 2);
    for (int i = 0; i < clean.length; i += 2) {
      result[i ~/ 2] = int.parse(clean.substring(i, i + 2), radix: 16);
    }
    return result;
  }

  /// Hashes a PIN using PBKDF2-HMAC-SHA256 with the given salt.
  static String hashPin(String pin, List<int> salt, {int iterations = defaultIterations}) {
    final derived = pbkdf2HmacSha256(
      password: pin,
      salt: salt,
      iterations: iterations,
    );
    return toHex(derived);
  }

  /// Verifies a PIN against stored hex hash.
  static bool verifyPin(String pin, String storedHash, List<int> salt, {int iterations = defaultIterations}) {
    if (storedHash.isEmpty) return false;
    final computed = hashPin(pin, salt, iterations: iterations);
    return computed.toLowerCase() == storedHash.toLowerCase();
  }

  /// Verifies Emergency Master Recovery Key.
  static bool verifyMasterKey(String candidateKey, String storedMasterHash, List<int> salt, {int iterations = defaultIterations}) {
    if (storedMasterHash.isEmpty) return false;
    final computed = hashPin(candidateKey.trim(), salt, iterations: iterations);
    return computed.toLowerCase() == storedMasterHash.toLowerCase();
  }
}

/// Models Lockout Status for Persistent Brute-Force Protection.
class LockoutState {
  final int failedAttempts;
  final int lockedUntilEpochMs;

  const LockoutState({
    required this.failedAttempts,
    required this.lockedUntilEpochMs,
  });

  bool isLocked(DateTime now) {
    return now.millisecondsSinceEpoch < lockedUntilEpochMs;
  }

  int remainingSeconds(DateTime now) {
    final diff = (lockedUntilEpochMs - now.millisecondsSinceEpoch) / 1000;
    return diff > 0 ? diff.ceil() : 0;
  }

  LockoutState recordFailure(DateTime now, {int maxAttempts = 5, int lockoutDurationSeconds = 300}) {
    final newAttempts = failedAttempts + 1;
    if (newAttempts >= maxAttempts) {
      return LockoutState(
        failedAttempts: newAttempts,
        lockedUntilEpochMs: now.millisecondsSinceEpoch + (lockoutDurationSeconds * 1000),
      );
    }
    return LockoutState(
      failedAttempts: newAttempts,
      lockedUntilEpochMs: lockedUntilEpochMs,
    );
  }

  LockoutState resetOnSuccess() {
    return const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);
  }

  static Future<LockoutState> loadFromDb(Database db) async {
    final rows = await db.query('system_settings', where: 'key IN (?, ?)', whereArgs: [
      'failed_pin_attempts',
      'locked_until_epoch',
    ]);
    int attempts = 0;
    int lockedUntil = 0;
    for (final row in rows) {
      final key = row['key'] as String;
      final val = row['value'] as String? ?? '0';
      if (key == 'failed_pin_attempts') {
        attempts = int.tryParse(val) ?? 0;
      } else if (key == 'locked_until_epoch') {
        lockedUntil = int.tryParse(val) ?? 0;
      }
    }
    return LockoutState(failedAttempts: attempts, lockedUntilEpochMs: lockedUntil);
  }

  Future<void> saveToDb(Database db) async {
    final batch = db.batch();
    batch.insert(
      'system_settings',
      {'key': 'failed_pin_attempts', 'value': failedAttempts.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    batch.insert(
      'system_settings',
      {'key': 'locked_until_epoch', 'value': lockedUntilEpochMs.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await batch.commit(noResult: true);
  }
}

// =============================================================================
// R2: DATA INTEGRITY & SYNC HARNESS
// =============================================================================
class SyncDataHarness {
  /// Detects whether an enqueued payload is partial (targeted update) vs full entity.
  static bool isPartialPayload(Map<String, dynamic> payload) {
    // If payload contains only status/read flags without primary model descriptors
    const primaryFields = {'name', 'perfumeCode', 'category', 'shelf', 'title', 'price'};
    final presentPrimary = payload.keys.where((k) => primaryFields.contains(k)).length;
    return presentPrimary == 0 && payload.containsKey('id');
  }

  /// Resolves conflicts per documented strategy:
  /// - Product Catalog / Pricing: Cloud wins on pull.
  /// - Sales & Restock Events: Local kiosk wins; append-only queue.
  static Map<String, dynamic> resolveConflict({
    required String collection,
    required Map<String, dynamic> localRecord,
    required Map<String, dynamic> cloudRecord,
  }) {
    if (collection == 'products' || collection == 'catalog' || collection == 'pricing') {
      return Map<String, dynamic>.from(cloudRecord);
    }
    if (collection == 'sales_records' || collection == 'inventory_events' || collection == 'restock_records') {
      return Map<String, dynamic>.from(localRecord);
    }
    // Default: local timestamp comparison
    final localTs = localRecord['lastUpdated'] ?? localRecord['timestamp'] ?? 0;
    final cloudTs = cloudRecord['lastUpdated'] ?? cloudRecord['timestamp'] ?? 0;
    return (cloudTs >= localTs) ? cloudRecord : localRecord;
  }

  /// Retrieves dynamic branch name from system settings.
  static Future<String> getDynamicBranch(Database db, {String fallback = 'San Pablo'}) async {
    final rows = await db.query(
      'system_settings',
      where: 'key = ?',
      whereArgs: ['branch_name'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final name = rows.first['value'] as String?;
      if (name != null && name.trim().isNotEmpty) {
        return name.trim();
      }
    }
    return fallback;
  }

  /// Validates stock count invariants:
  /// - detected count must strictly be clamped between 0 and 5
  /// - recorded count represents physical ledger and must not artificially inflate detected
  static void validateStockInvariants(InventoryRecordModel record) {
    if (record.detected < 0 || record.detected > 5) {
      throw StateError('Detected count must strictly be within [0, 5], got ${record.detected}');
    }
  }

  /// Determines if a discrepancy exists requiring audit review.
  static bool hasDiscrepancy(int recorded, int detected) {
    return recorded != detected;
  }
}

// =============================================================================
// R3: SCHEDULER & REAL DIAGNOSTICS HARNESS
// =============================================================================
class SchedulerDiagnosticsHarness {
  static const List<String> defaultCheckpoints = ['09:00', '14:00', '21:00'];

  /// Checks if current time matches any scheduled checkpoint and hasn't run yet in that minute.
  static bool isCheckpointDue({
    required DateTime now,
    required List<String> checkpoints,
    DateTime? lastExecutionTime,
  }) {
    final currentHhMm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    if (!checkpoints.contains(currentHhMm)) return false;

    if (lastExecutionTime != null) {
      final sameDay = now.year == lastExecutionTime.year &&
          now.month == lastExecutionTime.month &&
          now.day == lastExecutionTime.day;
      final sameMinute = now.hour == lastExecutionTime.hour &&
          now.minute == lastExecutionTime.minute;
      if (sameDay && sameMinute) return false;
    }
    return true;
  }

  /// Logs checkpoint execution to system_logs table and enqueues sync item.
  static Future<void> logCheckpointScan(
    Database db, {
    required String checkpointName,
    required int totalBottles,
    required String branch,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final logId = 'log_${now.millisecondsSinceEpoch}_sched';
    await db.insert('system_logs', {
      'id': logId,
      'type': 'CHECKPOINT_SCAN',
      'description': 'Scheduled scan ($checkpointName) completed. Detected: $totalBottles bottles across 60 slots.',
      'user': 'KioskScheduler',
      'branch': branch,
      'timestamp': now.toIso8601String(),
    });

    await db.insert('sync_queue', {
      'id': 'sync_$logId',
      'pendingEventId': logId,
      'targetCollection': 'system_logs',
      'operation': 'UPSERT',
      'payload': jsonEncode({
        'id': logId,
        'type': 'CHECKPOINT_SCAN',
        'checkpoint': checkpointName,
        'totalBottles': totalBottles,
        'branch': branch,
        'timestamp': now.toIso8601String(),
      }),
      'status': 'pending',
      'retryCount': 0,
      'createdAt': now.millisecondsSinceEpoch,
      'branch': branch,
    });
  }

  /// Evaluates real image frame metrics (brightness, contrast, sharpness).
  static Map<String, double> evaluateFrameQuality(List<int> grayscalePixels) {
    if (grayscalePixels.isEmpty) {
      return {'brightness': 0.0, 'contrast': 0.0, 'sharpness': 0.0};
    }
    // Mean brightness
    double sum = 0;
    for (final p in grayscalePixels) {
      sum += p;
    }
    final mean = sum / grayscalePixels.length;

    // Variance & standard deviation (contrast)
    double varSum = 0;
    for (final p in grayscalePixels) {
      varSum += (p - mean) * (p - mean);
    }
    final variance = varSum / grayscalePixels.length;
    final stdDev = sqrt(variance);

    // Approximate sharpness via adjacent pixel difference (Laplacian gradient proxy)
    double gradientSum = 0;
    for (int i = 0; i < grayscalePixels.length - 1; i++) {
      gradientSum += (grayscalePixels[i] - grayscalePixels[i + 1]).abs();
    }
    final sharpness = gradientSum / (grayscalePixels.length - 1);

    return {
      'brightness': mean,
      'contrast': stdDev,
      'sharpness': sharpness,
    };
  }

  static bool isZeroLight(Map<String, double> metrics) {
    return (metrics['brightness'] ?? 0.0) < 5.0;
  }
}

// =============================================================================
// R4: 60-SKU SHELF ARCHITECTURE & DYNAMIC ROUTING HARNESS
// =============================================================================
class ShelfArchitectureHarness {
  static const int totalTrays = 30;
  static const int slotsPerTray = 2;
  static const int totalSlots = totalTrays * slotsPerTray; // 60 slots
  static const int maxSlotCapacity = 5;
  static const int totalCapacity = totalSlots * maxSlotCapacity; // 300 bottles

  static const List<String> allTrays = [
    'AA', 'AB', 'AC', 'AD', 'AE', // Camera 1
    'AF', 'AG', 'AH', 'AI', 'AJ', // Camera 2
    'BA', 'BB', 'BC', 'BD', 'BE', // Camera 3
    'BF', 'BG', 'BH', 'BI', 'BJ', // Camera 4
    'CA', 'CB', 'CC', 'CD', 'CE', // Camera 5
    'CF', 'CG', 'CH', 'CI', 'CK', // Camera 6
  ];

  /// Maps tray code (e.g. 'AD', 'CK') to physical camera ID (1..6).
  static int getCameraIdForTray(String trayCode) {
    final code = trayCode.trim().toUpperCase();
    final idx = allTrays.indexOf(code);
    if (idx < 0) {
      throw ArgumentError('Invalid tray code: $trayCode');
    }
    return (idx ~/ 5) + 1;
  }

  /// Maps camera ID (1..6) to assigned hardware device node.
  static String getCameraDevice(int cameraId) {
    switch (cameraId) {
      case 1:
        return '/dev/cam1a';
      case 2:
        return '/dev/cam1b';
      case 3:
        return '/dev/cam2a';
      case 4:
        return '/dev/cam2b';
      case 5:
        return '/dev/cam3a';
      case 6:
        return '/dev/cam3b';
      default:
        throw ArgumentError('Invalid cameraId: $cameraId');
    }
  }

  /// Partitions detections on a tray into 100ML (slot 1) and 50ML (slot 2).
  static Map<String, int> partitionTrayDetections({
    required String trayCode,
    required List<Map<String, dynamic>> detections,
    required double trayLeft,
    required double trayRight,
    double? calibratedMidpoint,
  }) {
    final midX = calibratedMidpoint ?? ((trayLeft + trayRight) / 2.0);
    int slot1Count = 0; // 100ML (Left)
    int slot2Count = 0; // 50ML (Right)

    for (final det in detections) {
      final cX = (det['centerX'] as num).toDouble();
      final cY = (det['centerY'] as num).toDouble();

      // Check vertical boundary: bottom extended to 0.985
      if (cY > 0.985) continue;

      if (cX < midX) {
        slot1Count++;
      } else {
        slot2Count++;
      }
    }

    return {
      '${trayCode}1': slot1Count.clamp(0, maxSlotCapacity),
      '${trayCode}2': slot2Count.clamp(0, maxSlotCapacity),
    };
  }
}

// =============================================================================
// R5: VISION ASYNC THREADING & SCHEMA HARNESS
// =============================================================================
class VisionAsyncHarness {
  /// Validates standard JSON response schema for camera scan.
  static bool validateScanResponseSchema(Map<String, dynamic> response) {
    if (!response.containsKey('cameraId') || response['cameraId'] is! int) return false;
    if (!response.containsKey('totalBottles') || response['totalBottles'] is! int) return false;
    if (!response.containsKey('trayCounts') || response['trayCounts'] is! Map) return false;
    if (!response.containsKey('detections') || response['detections'] is! List) return false;

    final detections = response['detections'] as List;
    for (final det in detections) {
      if (det is! Map) return false;
      if (!det.containsKey('roiId') || !det.containsKey('centerX') || !det.containsKey('centerY')) {
        return false;
      }
      final cX = (det['centerX'] as num).toDouble();
      final cY = (det['centerY'] as num).toDouble();
      if (cX < 0.0 || cX > 1.0 || cY < 0.0 || cY > 1.0) return false;
    }
    return true;
  }

  /// Verifies boundary extension accommodates bottles up to cY = 0.985.
  static bool isWithinVerticalBoundary(double cY) {
    return cY >= 0.0 && cY <= 0.985;
  }
}
