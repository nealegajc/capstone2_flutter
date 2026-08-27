import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import 'sqlite_service.dart';

class AuthService {
  AuthService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Verifies the 6-digit PIN against the authoritative local SQLite store
  Future<bool> verifyPin(String pin) async {
    try {
      final sqlite = SqliteService.instance;
      return await sqlite.verifyOwnerPin(pin);
    } catch (_) {
      return false;
    }
  }

  /// Changes the 6-digit PIN in local SQLite storage and notifies backend if running
  Future<bool> changePin({required String oldPin, required String newPin}) async {
    bool localSuccess = false;

    // 1. Update in local authoritative SQLite database
    try {
      final sqlite = SqliteService.instance;
      localSuccess = await sqlite.updateOwnerPin(oldPin: oldPin, newPin: newPin);
    } catch (_) {}

    // 2. Notify local FastAPI backend if active
    if (localSuccess) {
      try {
        await _apiClient.post(
          ApiEndpoints.changePin,
          data: {
            'old_pin': oldPin,
            'new_pin': newPin,
          },
        );
      } catch (_) {}
    }

    return localSuccess;
  }
}
