import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/auth_provider.dart';
import '../../components/kiosk_numpad.dart';
import '../../components/pin_dots_indicator.dart';
import '../../components/pin_recovery_dialog.dart';

class PinLoginScreen extends ConsumerStatefulWidget {
  const PinLoginScreen({super.key});

  @override
  ConsumerState<PinLoginScreen> createState() => _PinLoginScreenState();
}

class _PinLoginScreenState extends ConsumerState<PinLoginScreen> {
  final FocusNode _keyboardFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _keyboardFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      final authNotifier = ref.read(authNotifierProvider.notifier);

      if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        authNotifier.appendDigit('0');
      } else if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        authNotifier.appendDigit('1');
      } else if (key == LogicalKeyboardKey.digit2 ||
          key == LogicalKeyboardKey.numpad2) {
        authNotifier.appendDigit('2');
      } else if (key == LogicalKeyboardKey.digit3 ||
          key == LogicalKeyboardKey.numpad3) {
        authNotifier.appendDigit('3');
      } else if (key == LogicalKeyboardKey.digit4 ||
          key == LogicalKeyboardKey.numpad4) {
        authNotifier.appendDigit('4');
      } else if (key == LogicalKeyboardKey.digit5 ||
          key == LogicalKeyboardKey.numpad5) {
        authNotifier.appendDigit('5');
      } else if (key == LogicalKeyboardKey.digit6 ||
          key == LogicalKeyboardKey.numpad6) {
        authNotifier.appendDigit('6');
      } else if (key == LogicalKeyboardKey.digit7 ||
          key == LogicalKeyboardKey.numpad7) {
        authNotifier.appendDigit('7');
      } else if (key == LogicalKeyboardKey.digit8 ||
          key == LogicalKeyboardKey.numpad8) {
        authNotifier.appendDigit('8');
      } else if (key == LogicalKeyboardKey.digit9 ||
          key == LogicalKeyboardKey.numpad9) {
        authNotifier.appendDigit('9');
      } else if (key == LogicalKeyboardKey.backspace) {
        authNotifier.deleteDigit();
      } else if (key == LogicalKeyboardKey.escape) {
        authNotifier.clearPin();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final authNotifier = ref.read(authNotifierProvider.notifier);

    // Listen for successful authentication and navigate to Dashboard
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
        context.go(AppRoutePaths.dashboard);
      }
    });

    return KeyboardListener(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: context.backgroundColor,
        body: Center(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Brand Header (Logo & Title)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(
                            alpha: context.isDark ? 0.15 : 0.12,
                          ),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.brandAccent.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.shelves,
                          color: AppColors.brandAccent,
                          size: 38,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'OTTO SCENTS',
                            style: TextStyle(
                              color: context.textPrimaryColor,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            ),
                          ),
                          const Text(
                            'SMART SHELF SYSTEM',
                            style: TextStyle(
                              color: AppColors.brandAccent,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // PIN Card Container
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 36,
                      vertical: 32,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: context.borderColor),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: context.isDark ? 0.35 : 0.08,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Lock Icon & Heading
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: authState.isLockedOut
                                ? AppColors.statusRed.withValues(alpha: 0.15)
                                : AppColors.brandAccent.withValues(alpha: 0.15),
                            border: Border.all(
                              color: authState.isLockedOut
                                  ? AppColors.statusRed
                                  : AppColors.brandAccent.withValues(
                                      alpha: 0.4,
                                    ),
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            authState.isLockedOut
                                ? Icons.lock_clock_rounded
                                : Icons.lock_outline_rounded,
                            color: authState.isLockedOut
                                ? AppColors.statusRed
                                : AppColors.brandAccent,
                            size: 36,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Enter Store PIN',
                          style: TextStyle(
                            color: context.textPrimaryColor,
                            fontSize: 25,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          authState.isLockedOut
                              ? 'Security Lockout Active'
                              : 'Enter your 6-digit PIN to unlock the terminal',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: authState.isLockedOut
                                ? AppColors.statusRed
                                : context.textSecondaryColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 6-Digit Visual Indicator Dots with Shake Animation
                        PinDotsIndicator(
                          pinLength: AppConstants.pinLength,
                          enteredLength: authState.enteredPin.length,
                          hasError:
                              authState.errorMessage != null &&
                              !authState.isLockedOut,
                          isLockedOut: authState.isLockedOut,
                        ),
                        const SizedBox(height: 16),

                        // Status / Error / Loading Message
                        SizedBox(
                          height: 32,
                          child: Center(
                            child: authState.isLoading
                                ? Semantics(
                                    liveRegion: true,
                                    label: 'Verifying PIN',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: AppColors.brandAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          'Verifying PIN...',
                                          style: TextStyle(
                                            color: context.textSecondaryColor,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : authState.isLockedOut
                                ? Semantics(
                                    liveRegion: true,
                                    label:
                                        'Locked out. Try again in ${authState.lockoutRemainingSeconds} seconds',
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.timer_outlined,
                                          color: AppColors.statusRed,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Try again in ${authState.lockoutRemainingSeconds}s',
                                          style: const TextStyle(
                                            color: AppColors.statusRed,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : authState.errorMessage != null
                                ? Semantics(
                                    liveRegion: true,
                                    label: authState.errorMessage!,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          color: AppColors.statusRed,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          authState.errorMessage!,
                                          style: const TextStyle(
                                            color: AppColors.statusRed,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 14),

                        // On-Screen Touch Numpad
                        KioskNumpad(
                          isEnabled:
                              !authState.isLockedOut && !authState.isLoading,
                          onDigitPressed: (digit) =>
                              authNotifier.appendDigit(digit),
                          onDeletePressed: () => authNotifier.deleteDigit(),
                          onClearPressed: () => authNotifier.clearPin(),
                        ),
                        const SizedBox(height: 16),

                        // Forgot PIN / Recovery Option (Disabled & hidden during security lockout)
                        if (!authState.isLockedOut)
                          TextButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => PinRecoveryDialog(
                                  onPinResetSuccess: () {
                                    ref
                                        .read(authNotifierProvider.notifier)
                                        .resetLockoutAndState();
                                  },
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.help_outline_rounded,
                              size: 16,
                              color: AppColors.brandAccent,
                            ),
                            label: const Text(
                              'Forgot PIN? Answer Security Questions',
                              style: TextStyle(
                                color: AppColors.brandAccent,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Bottom Support / Version Indicator
                  Text(
                    'Otto Scents Smart Shelf v1.0.0 • San Pablo Branch',
                    style: TextStyle(
                      color: context.textMutedColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
