import 'dart:async';

import '../../core/api/api_client.dart';
import 'sqlite_service.dart';
import 'sync_service.dart';

class AuthService {
  AuthService({this.apiClient});

  final ApiClient? apiClient;

  /// Verifies the 6-digit PIN against the authoritative local SQLite store
  Future<bool> verifyPin(String pin) async {
    try {
      final sqlite = SqliteService.instance;
      return await sqlite.verifyOwnerPin(pin);
    } catch (_) {
      return false;
    }
  }

  /// Changes the 6-digit PIN in local SQLite storage and triggers sync queue
  Future<bool> changePin({
    required String oldPin,
    required String newPin,
  }) async {
    try {
      final sqlite = SqliteService.instance;
      final localSuccess = await sqlite.updateOwnerPin(
        oldPin: oldPin,
        newPin: newPin,
      );

      if (localSuccess) {
        try {
          unawaited(SyncService.instance.syncPendingQueue());
        } catch (_) {}
      }

      return localSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Checks if an owner PIN has been configured
  Future<bool> isOwnerPinSet() async {
    try {
      return await SqliteService.instance.isOwnerPinSet();
    } catch (_) {
      return false;
    }
  }

  /// Configures initial 6-digit owner PIN during first-time terminal setup
  Future<bool> setupInitialPin(String pin) async {
    try {
      final success = await SqliteService.instance.setInitialOwnerPin(pin);
      if (success) {
        try {
          unawaited(SyncService.instance.syncPendingQueue());
        } catch (_) {}
      }
      return success;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves persistent brute-force lockout status from SQLite
  Future<LockoutStatus> getLockoutStatus() async {
    try {
      return await SqliteService.instance.getLockoutStatus();
    } catch (_) {
      return const LockoutStatus(
        isLockedOut: false,
        remainingSeconds: 0,
        failedAttempts: 0,
      );
    }
  }

  /// Manually clears persistent lockout in SQLite
  Future<void> resetLockout() async {
    try {
      await SqliteService.instance.resetLockout();
    } catch (_) {}
  }

  /// Verifies the emergency manager override master recovery key
  Future<bool> verifyEmergencyOverride(String masterKey) async {
    try {
      return await SqliteService.instance.verifyEmergencyManagerOverride(masterKey);
    } catch (_) {
      return false;
    }
  }
}

