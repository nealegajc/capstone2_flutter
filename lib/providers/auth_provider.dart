import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_constants.dart';
import '../data/models/auth_state.dart';
import '../data/services/auth_service.dart';
import 'api_provider.dart';

import '../data/services/sqlite_service.dart';

final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  final authService = ref.watch(authServiceProvider);
  return AuthNotifier(authService);
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._authService) : super(const AuthState()) {
    checkKioskLockout();
  }

  final AuthService _authService;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  /// Checks SQLite for persistent lockout state across app restarts
  Future<void> checkKioskLockout() async {
    try {
      final status = await _authService.getLockoutStatus();
      if (status.isLockedOut) {
        _resumeLockout(status.remainingSeconds, status.failedAttempts);
      } else {
        state = state.copyWith(
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          failedAttempts: status.failedAttempts,
        );
      }
    } catch (_) {}
  }

  void appendDigit(String digit, {bool autoVerify = true}) {
    if (state.isLockedOut || state.isLoading) return;
    if (state.enteredPin.length >= AppConstants.pinLength) return;

    final newPin = '${state.enteredPin}$digit';
    state = state.copyWith(enteredPin: newPin, clearError: true);

    // Automatically verify once 6 digits are typed
    if (autoVerify && newPin.length == AppConstants.pinLength) {
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
    state = state.copyWith(enteredPin: '', clearError: true);
  }

  Future<bool> verifyPin(String pin) async {
    if (state.isLockedOut || state.isLoading) return false;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final isSuccess = await _authService.verifyPin(pin);

      if (isSuccess) {
        _lockoutTimer?.cancel();
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          enteredPin: '',
          failedAttempts: 0,
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          clearError: true,
        );
        return true;
      } else {
        final status = await _authService.getLockoutStatus();
        if (status.isLockedOut) {
          _resumeLockout(status.remainingSeconds, status.failedAttempts);
        } else {
          state = state.copyWith(
            isAuthenticated: false,
            isLoading: false,
            enteredPin: '',
            failedAttempts: status.failedAttempts,
            errorMessage:
                'Incorrect PIN, please try again (${5 - status.failedAttempts} attempts left)',
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

  void _resumeLockout(int seconds, int attempts) {
    _lockoutTimer?.cancel();
    if (seconds <= 0) {
      unawaited(_authService.resetLockout());
      state = state.copyWith(
        isLockedOut: false,
        lockoutRemainingSeconds: 0,
        failedAttempts: 0,
        clearError: true,
      );
      return;
    }

    state = state.copyWith(
      isLockedOut: true,
      lockoutRemainingSeconds: seconds,
      enteredPin: '',
      failedAttempts: attempts,
      isLoading: false,
      errorMessage: 'Too many incorrect attempts. Please wait ${seconds}s.',
    );

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = state.lockoutRemainingSeconds - 1;
      if (remaining <= 0) {
        timer.cancel();
        unawaited(_authService.resetLockout());
        state = state.copyWith(
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          failedAttempts: 0,
          clearError: true,
        );
      } else {
        state = state.copyWith(
          lockoutRemainingSeconds: remaining,
          errorMessage:
              'Too many incorrect attempts. Please wait ${remaining}s.',
        );
      }
    });
  }

  /// Sets up initial 6-digit owner PIN during first-time terminal setup
  Future<bool> setupInitialOwnerPin(String pin) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _authService.setupInitialPin(pin);
      if (success) {
        _lockoutTimer?.cancel();
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          enteredPin: '',
          failedAttempts: 0,
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to configure PIN. Must be 6 digits.',
        );
        return false;
      }
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error configuring PIN. Please try again.',
      );
      return false;
    }
  }

  /// Emergency manager override bypassing security lockouts
  Future<bool> emergencyOverride(String masterKey) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _authService.verifyEmergencyOverride(masterKey);
      if (success) {
        _lockoutTimer?.cancel();
        state = state.copyWith(
          isAuthenticated: true,
          isLoading: false,
          enteredPin: '',
          failedAttempts: 0,
          isLockedOut: false,
          lockoutRemainingSeconds: 0,
          clearError: true,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Invalid master recovery key. Access denied.',
        );
        return false;
      }
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error processing emergency override.',
      );
      return false;
    }
  }

  void resetLockoutAndState() {
    _lockoutTimer?.cancel();
    _authService.resetLockout();
    state = const AuthState();
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
