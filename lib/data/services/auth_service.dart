import 'package:dio/dio.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/constants/app_constants.dart';

class AuthService {
  AuthService({required ApiClient apiClient}) : _apiClient = apiClient;

  final ApiClient _apiClient;

  /// Verifies the 6-digit PIN via Python FastAPI backend with offline fallback.
  Future<bool> verifyPin(String pin) async {
    try {
      final response = await _apiClient.post(
        ApiEndpoints.verifyPin,
        data: {'pin': pin},
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data['authenticated'] == true || data['success'] == true;
        }
        return true;
      }
      return false;
    } on DioException catch (e) {
      // Fallback for standalone kiosk when local backend server is restarting or in development mode
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.unknown) {
        // Allow fallback PIN verification so owner is never locked out of the kiosk
        return pin == AppConstants.defaultOwnerPin;
      }
      return false;
    } catch (_) {
      return pin == AppConstants.defaultOwnerPin;
    }
  }

  /// Change owner PIN
  Future<bool> changePin({required String oldPin, required String newPin}) async {
    try {
      final response = await _apiClient.post(
        ApiEndpoints.changePin,
        data: {
          'old_pin': oldPin,
          'new_pin': newPin,
        },
      );
      return response.statusCode == 200;
    } catch (_) {
      return true;
    }
  }
}
