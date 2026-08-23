import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../components/kiosk_numpad.dart';
import '../../components/pin_dots_indicator.dart';

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
    // Request focus for optional physical keyboard numpad input
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _keyboardFocusNode.dispose();
    super.dispose();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final authNotifier = ref.read(authNotifierProvider.notifier);
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.backspace) {
      authNotifier.deleteDigit();
    } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.delete) {
      authNotifier.clearPin();
    } else {
      final char = event.character;
      if (char != null && RegExp(r'^[0-9]$').hasMatch(char)) {
        authNotifier.appendDigit(char);
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
        backgroundColor: AppColors.darkBackground,
        body: Row(
          children: [
            // Left Panel: Store Branding & Information (Landscape Kiosk Optimized)
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF1E293B),
                    ],
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Brand Header
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.brandAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.brandAccent.withValues(alpha: 0.3),
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.shelves,
                                  color: AppColors.brandAccent,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'OTTO SCENTS',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 2.0,
                                      ),
                                    ),
                                    Text(
                                      'SMART SHELF SYSTEM',
                                      style: TextStyle(
                                        color: AppColors.brandAccent,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            'Automated Perfume\nInventory Monitoring',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Computer Vision real-time stock detection and retail shelf verification.',
                            style: TextStyle(
                              color: AppColors.darkTextSecondary,
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 36),

                      // Kiosk Status Footer
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.darkSurface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.darkBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, color: AppColors.statusGreen, size: 12),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Kiosk Online • Touchscreen Ready',
                                style: TextStyle(
                                  color: AppColors.darkTextPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              'v1.0',
                              style: TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Right Panel: 6-Digit Touchscreen PIN Authentication
            Expanded(
              flex: 6,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
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
                                : AppColors.brandAccent.withValues(alpha: 0.4),
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
                      const Text(
                        'Enter Store PIN',
                        style: TextStyle(
                          color: AppColors.darkTextPrimary,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        authState.isLockedOut
                            ? 'Security Lockout Active'
                            : 'Enter your 6-digit owner PIN to unlock the kiosk',
                        style: TextStyle(
                          color: authState.isLockedOut
                              ? AppColors.statusRed
                              : AppColors.darkTextSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // 6-Digit Visual Indicator Dots with Shake Animation
                      PinDotsIndicator(
                        pinLength: AppConstants.pinLength,
                        enteredLength: authState.enteredPin.length,
                        hasError: authState.errorMessage != null && !authState.isLockedOut,
                        isLockedOut: authState.isLockedOut,
                      ),
                      const SizedBox(height: 20),

                      // Status / Error / Loading Message
                      SizedBox(
                        height: 36,
                        child: Center(
                          child: authState.isLoading
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.brandAccent),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Verifying PIN...',
                                      style: TextStyle(
                                        color: AppColors.brandAccent,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                )
                              : authState.errorMessage != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppColors.statusRedBg,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: AppColors.statusRed.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Text(
                                        authState.errorMessage!,
                                        style: const TextStyle(
                                          color: AppColors.statusRed,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 3x4 Touch Numpad (0-9, Clear, Delete)
                      KioskNumpad(
                        isEnabled: !authState.isLockedOut && !authState.isLoading,
                        onDigitPressed: authNotifier.appendDigit,
                        onDeletePressed: authNotifier.deleteDigit,
                        onClearPressed: authNotifier.clearPin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
