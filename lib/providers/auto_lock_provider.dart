import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/sqlite_service.dart';
import 'auth_provider.dart';

class AutoLockState {
  final int timeoutMinutes; // 0 = disabled, 1, 2, 3, 5, 10
  final int remainingSeconds;
  final bool isRunning;

  const AutoLockState({
    this.timeoutMinutes = 3,
    this.remainingSeconds = 180,
    this.isRunning = false,
  });

  bool get isEnabled => timeoutMinutes > 0;

  String get timeoutLabel {
    if (timeoutMinutes <= 0) return 'Disabled (Never)';
    if (timeoutMinutes == 1) return '1 Minute';
    return '$timeoutMinutes Minutes';
  }

  AutoLockState copyWith({
    int? timeoutMinutes,
    int? remainingSeconds,
    bool? isRunning,
  }) {
    return AutoLockState(
      timeoutMinutes: timeoutMinutes ?? this.timeoutMinutes,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      isRunning: isRunning ?? this.isRunning,
    );
  }
}

class AutoLockNotifier extends StateNotifier<AutoLockState> {
  final Ref _ref;
  final SqliteService _sqlite;
  Timer? _ticker;

  static const String _settingKey = 'auto_lock_timeout_minutes';
  static const int defaultTimeoutMinutes = 3;

  AutoLockNotifier(this._ref, this._sqlite) : super(const AutoLockState()) {
    _loadSettings();
    _listenToAuth();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _sqlite.getSystemSettings();
      final savedMinutes = settings[_settingKey];
      int minutes = defaultTimeoutMinutes;

      if (savedMinutes != null) {
        if (savedMinutes is int) {
          minutes = savedMinutes;
        } else if (savedMinutes is String) {
          minutes = int.tryParse(savedMinutes) ?? defaultTimeoutMinutes;
        }
      }

      state = state.copyWith(
        timeoutMinutes: minutes,
        remainingSeconds: minutes * 60,
      );

      final authState = _ref.read(authNotifierProvider);
      if (authState.isAuthenticated && minutes > 0) {
        startTimer();
      }
    } catch (e) {
      debugPrint('[AutoLockNotifier] Error loading setting: $e');
    }
  }

  void _listenToAuth() {
    _ref.listen(authNotifierProvider, (previous, next) {
      if (next.isAuthenticated) {
        resetTimer();
        startTimer();
      } else {
        stopTimer();
      }
    });
  }

  void startTimer() {
    _ticker?.cancel();
    if (state.timeoutMinutes <= 0) {
      state = state.copyWith(isRunning: false);
      return;
    }

    state = state.copyWith(
      remainingSeconds: state.timeoutMinutes * 60,
      isRunning: true,
    );

    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      final authState = _ref.read(authNotifierProvider);
      if (!authState.isAuthenticated) {
        timer.cancel();
        state = state.copyWith(isRunning: false);
        return;
      }

      if (state.remainingSeconds <= 1) {
        timer.cancel();
        state = state.copyWith(remainingSeconds: 0, isRunning: false);
        _triggerAutoLock();
      } else {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });
  }

  void stopTimer() {
    _ticker?.cancel();
    _ticker = null;
    state = state.copyWith(isRunning: false);
  }

  void resetTimer() {
    if (state.timeoutMinutes <= 0) return;

    final newRemaining = state.timeoutMinutes * 60;
    state = state.copyWith(remainingSeconds: newRemaining);

    if (!state.isRunning) {
      final authState = _ref.read(authNotifierProvider);
      if (authState.isAuthenticated) {
        startTimer();
      }
    }
  }

  Future<void> setTimeoutMinutes(int minutes) async {
    state = state.copyWith(
      timeoutMinutes: minutes,
      remainingSeconds: minutes * 60,
    );

    try {
      await _sqlite.setSystemSetting(_settingKey, minutes);
    } catch (e) {
      debugPrint('[AutoLockNotifier] Error saving setting: $e');
    }

    if (minutes <= 0) {
      stopTimer();
    } else {
      resetTimer();
      startTimer();
    }
  }

  Future<void> _triggerAutoLock() async {
    try {
      await _sqlite.logActivity(
        type: 'AUTOLOCK',
        description: 'Terminal automatically locked due to ${state.timeoutMinutes} min(s) of inactivity.',
      );
    } catch (_) {}

    _ref.read(authNotifierProvider.notifier).logout();
  }
}

final autoLockProvider = StateNotifierProvider<AutoLockNotifier, AutoLockState>((ref) {
  final sqlite = SqliteService.instance;
  return AutoLockNotifier(ref, sqlite);
});
