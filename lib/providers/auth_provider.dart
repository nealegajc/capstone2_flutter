import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_constants.dart';
import '../data/models/auth_state.dart';
import '../data/services/auth_service.dart';
import 'api_provider.dart';

import '../data/services/sqlite_service.dart';

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService) : super(const AuthState());

  final AuthService _authService;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  void appendDigit(String digit) {
    if (state.isLockedOut || state.isLoading) return;
    if (state.enteredPin.length >= AppConstants.pinLength) return;

    final newPin = '${state.enteredPin}$digit';
    state = state.copyWith(
      enteredPin: newPin,
      clearError: true,
    );

    // Automatically verify once 6 digits are typed
    if (newPin.length == AppConstants.pinLength) {
      verifyPin(newPin);
    }
  }

  void deleteDigit() {
    if (state.isLockedOut || state.isLoading) return;
    if (state.enteredPin.isEmpty) return;

    state = state.copyWith(
      enteredPin: state.enteredPin.substring(0, state.enteredPin.length - 1),
      clearError: true,
    );
  }

  void clearPin() {
    if (state.isLockedOut || state.isLoading) return;
    state = state.copyWith(
      enteredPin: '',
      clearError: true,
    );
  }

  Future<bool> verifyPin(String pin) async {
    if (state.isLockedOut || state.isLoading) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final isSuccess = await _authService.verifyPin(pin);

      if (isSuccess) {
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          enteredPin: '',
          failedAttempts: 0,
          clearError: true,
        );

        // Log successful authentication audit
        try {
          await SqliteService.instance.logActivity(
            type: 'USER_LOGIN',
            description: 'Store Owner authenticated successfully via PIN at kiosk terminal.',
          );
        } catch (_) {}

        return true;
      } else {
        final attempts = state.failedAttempts + 1;

        // Log failed attempt audit
        try {
          await SqliteService.instance.logActivity(
            type: 'AUTH_FAILURE',
            description: 'Failed PIN authentication attempt ($attempts of ${AppConstants.maxFailedAttempts}).',
          );
        } catch (_) {}

        if (attempts >= AppConstants.maxFailedAttempts) {
          _startLockout();
        } else {
          state = state.copyWith(
            isAuthenticated: false,
            isLoading: false,
            enteredPin: '',
            failedAttempts: attempts,
            errorMessage: 'Incorrect PIN, please try again (${AppConstants.maxFailedAttempts - attempts} attempts left)',
          );
        }
        return false;
      }
    } catch (_) {
      state = state.copyWith(
        isAuthenticated: false,
        isLoading: false,
        enteredPin: '',
        errorMessage: 'Connection error. Please try again.',
      );
      return false;
    }
  }

  void _startLockout() {
    _lockoutTimer?.cancel();
    state = state.copyWith(
      isLockedOut: true,
      lockoutRemainingSeconds: AppConstants.lockoutDurationSeconds,
      enteredPin: '',
      isLoading: false,
      errorMessage: 'Too many incorrect attempts. Please wait ${AppConstants.lockoutDurationSeconds}s.',
    );

    // Log security lockout audit
    try {
      SqliteService.instance.logActivity(
        type: 'SECURITY_LOCKOUT',
        description: 'Security lockout initiated for ${AppConstants.lockoutDurationSeconds}s after repeated invalid PIN attempts.',
      );
    } catch (_) {}

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.lockoutRemainingSeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        state = state.copyWith(
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          failedAttempts: 0,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          lockoutRemainingSeconds: remaining,
          errorMessage: 'Too many incorrect attempts. Please wait ${remaining}s.',
        );
      }
    });
  }

  void logout() {
    _lockoutTimer?.cancel();
    state = const AuthState();

    // Log kiosk lock / logout audit
    try {
      SqliteService.instance.logActivity(
        type: 'USER_LOGOUT',
        description: 'Kiosk locked / owner session ended.',
      );
    } catch (_) {}
  }
}
