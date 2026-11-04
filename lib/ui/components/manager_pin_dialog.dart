import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/sqlite_service.dart';
import 'kiosk_numpad.dart';
import 'pin_dots_indicator.dart';

class ManagerPinDialog extends StatefulWidget {
  final String actionTitle;
  final String actionDescription;
  final String? targetSku;

  const ManagerPinDialog({
    super.key,
    required this.actionTitle,
    required this.actionDescription,
    this.targetSku,
  });

  static Future<bool> show(
    BuildContext context, {
    required String actionTitle,
    required String actionDescription,
    String? targetSku,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ManagerPinDialog(
        actionTitle: actionTitle,
        actionDescription: actionDescription,
        targetSku: targetSku,
      ),
    );
    return result ?? false;
  }

  @override
  State<ManagerPinDialog> createState() => _ManagerPinDialogState();
}

class _ManagerPinDialogState extends State<ManagerPinDialog> {
  String _pin = '';
  bool _hasError = false;
  bool _isLockedOut = false;
  bool _isLoading = false;
  String? _errorMessage;
  int _remainingLockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _checkInitialLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkInitialLockout() async {
    final lockout = await SqliteService.instance.getLockoutStatus();
    if (!mounted) return;
    if (lockout.isLockedOut) {
      _startLockoutCountdown(lockout.remainingSeconds);
    }
  }

  void _startLockoutCountdown(int seconds) {
    _lockoutTimer?.cancel();
    setState(() {
      _isLockedOut = true;
      _remainingLockoutSeconds = seconds;
      _errorMessage =
          'Security Lockout: Too many failed attempts. Try again in $_remainingLockoutSeconds s.';
      _pin = '';
    });

    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_remainingLockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _isLockedOut = false;
          _remainingLockoutSeconds = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _remainingLockoutSeconds--;
          _errorMessage =
              'Security Lockout: Too many failed attempts. Try again in $_remainingLockoutSeconds s.';
        });
      }
    });
  }

  void _handleDigit(String digit) {
    if (_isLockedOut || _isLoading) return;
    if (_pin.length < 6) {
      setState(() {
        _pin += digit;
        _hasError = false;
        _errorMessage = null;
      });

      if (_pin.length == 6) {
        _verifyPin();
      }
    }
  }

  void _handleDelete() {
    if (_isLockedOut || _isLoading) return;
    if (_pin.isNotEmpty) {
      setState(() {
        _pin = _pin.substring(0, _pin.length - 1);
        _hasError = false;
        _errorMessage = null;
      });
    }
  }

  void _handleClear() {
    if (_isLockedOut || _isLoading) return;
    setState(() {
      _pin = '';
      _hasError = false;
      _errorMessage = null;
    });
  }

  Future<void> _verifyPin() async {
    setState(() => _isLoading = true);

    try {
      final isValid = await SqliteService.instance.verifyOwnerPin(_pin);
      if (!mounted) return;

      if (isValid) {
        Navigator.of(context).pop(true);
      } else {
        final lockout = await SqliteService.instance.getLockoutStatus();
        if (!mounted) return;

        if (lockout.isLockedOut) {
          _startLockoutCountdown(lockout.remainingSeconds);
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = 'Invalid Manager PIN. Please try again.';
            _pin = '';
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: context.borderColor, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with Lock Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.brandGold.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.brandGold.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.lock_rounded,
                  color: AppColors.brandGold,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),

              Text(
                widget.actionTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 6),

              Text(
                widget.actionDescription,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: context.textSecondaryColor,
                ),
              ),

              if (widget.targetSku != null && widget.targetSku!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    'SKU: ${widget.targetSku}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brandAccent,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // PIN Dots Indicator
              PinDotsIndicator(
                pinLength: 6,
                enteredLength: _pin.length,
                hasError: _hasError,
                isLockedOut: _isLockedOut,
              ),
              const SizedBox(height: 12),

              // Feedback message or loading
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _isLockedOut
                          ? AppColors.statusOrange
                          : AppColors.statusRed,
                    ),
                  ),
                )
              else
                const SizedBox(height: 20),

              const SizedBox(height: 12),

              // Keypad
              KioskNumpad(
                onDigitPressed: _handleDigit,
                onDeletePressed: _handleDelete,
                onClearPressed: _handleClear,
                isEnabled: !_isLockedOut && !_isLoading,
              ),
              const SizedBox(height: 20),

              // Cancel button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: context.borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Cancel Authorization',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
