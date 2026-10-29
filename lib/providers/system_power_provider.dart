import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/system_power_service.dart';

enum SystemPowerAction { restart, shutdown }

class SystemRestartState {
  final bool isCountingDown;
  final int remainingSeconds;
  final SystemPowerAction action;

  const SystemRestartState({
    this.isCountingDown = false,
    this.remainingSeconds = 15,
    this.action = SystemPowerAction.restart,
  });

  SystemRestartState copyWith({
    bool? isCountingDown,
    int? remainingSeconds,
    SystemPowerAction? action,
  }) {
    return SystemRestartState(
      isCountingDown: isCountingDown ?? this.isCountingDown,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      action: action ?? this.action,
    );
  }
}

class SystemRestartNotifier extends StateNotifier<SystemRestartState> {
  Timer? _timer;

  SystemRestartNotifier() : super(const SystemRestartState());

  void startCountdown({SystemPowerAction action = SystemPowerAction.restart}) {
    _timer?.cancel();
    state = SystemRestartState(
      isCountingDown: true,
      remainingSeconds: 15,
      action: action,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds <= 1) {
        timer.cancel();
        final currentAction = state.action;
        state = state.copyWith(isCountingDown: false, remainingSeconds: 0);
        if (currentAction == SystemPowerAction.shutdown) {
          SystemPowerService.instance.shutdownSystem();
        } else {
          SystemPowerService.instance.restartSystem();
        }
      } else {
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });
  }

  void cancelCountdown() {
    _timer?.cancel();
    _timer = null;
    state = const SystemRestartState(
      isCountingDown: false,
      remainingSeconds: 15,
    );
  }

  void executeNow() {
    _timer?.cancel();
    _timer = null;
    final currentAction = state.action;
    state = state.copyWith(isCountingDown: false, remainingSeconds: 0);
    if (currentAction == SystemPowerAction.shutdown) {
      SystemPowerService.instance.shutdownSystem();
    } else {
      SystemPowerService.instance.restartSystem();
    }
  }

  void restartNow() => executeNow();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final systemRestartProvider =
    StateNotifierProvider<SystemRestartNotifier, SystemRestartState>((ref) {
      return SystemRestartNotifier();
    });
