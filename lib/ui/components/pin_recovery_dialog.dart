import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/sqlite_service.dart';

class PinRecoveryDialog extends StatefulWidget {
  final VoidCallback onPinResetSuccess;

  const PinRecoveryDialog({super.key, required this.onPinResetSuccess});

  @override
  State<PinRecoveryDialog> createState() => _PinRecoveryDialogState();
}

class _PinRecoveryDialogState extends State<PinRecoveryDialog> {
  final _ans1Controller = TextEditingController();
  final _ans2Controller = TextEditingController();
  final _ans3Controller = TextEditingController();
  final _newPinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  int _currentStep = 0; // 0: Answer Questions, 1: Enter New PIN
  bool _isLoading = false;
  String? _errorMessage;

  int _activeField = 0; // 0: ans1, 1: ans2, 2: ans3

  @override
  void dispose() {
    _ans1Controller.dispose();
    _ans2Controller.dispose();
    _ans3Controller.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _onVirtualKeyPress(String char) {
    TextEditingController target;
    if (_currentStep == 0) {
      target = _activeField == 0
          ? _ans1Controller
          : (_activeField == 1 ? _ans2Controller : _ans3Controller);
    } else {
      target = _activeField == 0 ? _newPinController : _confirmPinController;
      if (target.text.length >= AppConstants.pinLength) return;
    }
    setState(() {
      target.text += char;
    });
  }

  void _onVirtualBackspace() {
    TextEditingController target;
    if (_currentStep == 0) {
      target = _activeField == 0
          ? _ans1Controller
          : (_activeField == 1 ? _ans2Controller : _ans3Controller);
    } else {
      target = _activeField == 0 ? _newPinController : _confirmPinController;
    }
    if (target.text.isNotEmpty) {
      setState(() {
        target.text = target.text.substring(0, target.text.length - 1);
      });
    }
  }

  void _onVirtualClear() {
    TextEditingController target;
    if (_currentStep == 0) {
      target = _activeField == 0
          ? _ans1Controller
          : (_activeField == 1 ? _ans2Controller : _ans3Controller);
    } else {
      target = _activeField == 0 ? _newPinController : _confirmPinController;
    }
    setState(() {
      target.clear();
    });
  }

  Future<void> _handleVerifyQuestions() async {
    final a1 = _ans1Controller.text.trim();
    final a2 = _ans2Controller.text.trim();
    final a3 = _ans3Controller.text.trim();

    if (a1.isEmpty || a2.isEmpty || a3.isEmpty) {
      setState(() => _errorMessage = 'Please answer all 3 security questions.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final isValid = await SqliteService.instance.verifyRecoveryQuestions(
        answer1: a1,
        answer2: a2,
        answer3: a3,
      );

      if (!mounted) return;

      if (isValid) {
        setState(() {
          _isLoading = false;
          _currentStep = 1;
          _activeField = 0;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'One or more security answers are incorrect. Please verify.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error verifying questions. Please try again.';
      });
    }
  }

  Future<void> _handleSaveNewPin() async {
    final newPin = _newPinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (newPin.length != AppConstants.pinLength ||
        !RegExp(r'^\d+$').hasMatch(newPin)) {
      setState(() => _errorMessage = 'PIN must be exactly 6 numeric digits.');
      return;
    }

    if (newPin != confirmPin) {
      setState(() => _errorMessage = 'PINs do not match. Please re-enter.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final success = await SqliteService.instance.resetOwnerPinViaRecovery(
        answer1: _ans1Controller.text.trim(),
        answer2: _ans2Controller.text.trim(),
        answer3: _ans3Controller.text.trim(),
        newPin: newPin,
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop();
        widget.onPinResetSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Store Owner PIN has been successfully reset. Please log in.',
            ),
            backgroundColor: AppColors.statusGreen,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to reset PIN. Please try again.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error saving new PIN.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide(color: context.borderColor, width: 1.5),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: 640,
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.brandAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.lock_reset_rounded,
                      color: AppColors.brandAccent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentStep == 0
                              ? 'PIN Recovery'
                              : 'Create New Security PIN',
                          style: TextStyle(
                            color: context.textPrimaryColor,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _currentStep == 0
                              ? 'Answer security questions to reset your Store PIN'
                              : 'Set a new 6-digit numeric PIN for terminal access',
                          style: TextStyle(
                            color: context.textSecondaryColor,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      color: context.textSecondaryColor,
                      size: 26,
                    ),
                    tooltip: 'Close',
                  ),
                ],
              ),
              Divider(height: 24, color: context.borderColor),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.statusRedBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusRed.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.statusRed,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: AppColors.statusRed,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (_currentStep == 0) ...[
                // Question 1
                _buildQuestionField(
                  fieldIndex: 0,
                  label: AppConstants.recoveryQuestion1,
                  hint: 'Enter founding year',
                  controller: _ans1Controller,
                  icon: Icons.calendar_today_rounded,
                ),
                const SizedBox(height: 12),

                // Question 2
                _buildQuestionField(
                  fieldIndex: 1,
                  label: AppConstants.recoveryQuestion2,
                  hint: 'Enter security answer',
                  controller: _ans2Controller,
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 12),

                // Question 3
                _buildQuestionField(
                  fieldIndex: 2,
                  label: AppConstants.recoveryQuestion3,
                  hint: 'Enter business name',
                  controller: _ans3Controller,
                  icon: Icons.storefront_outlined,
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleVerifyQuestions,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Verify Security Answers',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ] else ...[
                // Step 1: Set New PIN
                _buildPinField(
                  fieldIndex: 0,
                  label: 'New 6-Digit Store PIN',
                  controller: _newPinController,
                ),
                const SizedBox(height: 14),
                _buildPinField(
                  fieldIndex: 1,
                  label: 'Confirm New PIN',
                  controller: _confirmPinController,
                ),
                const SizedBox(height: 16),

                // Touch Virtual Numpad for PIN Setting
                _buildVirtualNumpad(),
                const SizedBox(height: 16),

                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSaveNewPin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Reset & Save New Security PIN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuestionField({
    required int fieldIndex,
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    final isSelected = _activeField == fieldIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _activeField = fieldIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? AppColors.brandAccent
                        : context.textPrimaryColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Active Touch Input',
                    style: TextStyle(
                      color: AppColors.brandAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onTap: () => setState(() => _activeField = fieldIndex),
            style: TextStyle(color: context.textPrimaryColor, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: context.textMutedColor),
              prefixIcon: Icon(
                icon,
                color: isSelected
                    ? AppColors.brandAccent
                    : context.textSecondaryColor,
                size: 20,
              ),
              filled: true,
              fillColor: isSelected
                  ? AppColors.brandAccent.withValues(alpha: 0.08)
                  : (context.isDark
                      ? const Color(0xFF161922)
                      : const Color(0xFFF3F4F6)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isSelected ? AppColors.brandAccent : context.borderColor,
                  width: isSelected ? 2 : 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.brandAccent,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinField({
    required int fieldIndex,
    required String label,
    required TextEditingController controller,
  }) {
    final isSelected = _activeField == fieldIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _activeField = fieldIndex),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? AppColors.brandAccent
                      : context.textPrimaryColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Active Touch Input',
                    style: TextStyle(
                      color: AppColors.brandAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onTap: () => setState(() => _activeField = fieldIndex),
            keyboardType: TextInputType.number,
            maxLength: AppConstants.pinLength,
            obscureText: true,
            style: TextStyle(
              color: context.textPrimaryColor,
              fontSize: 20,
              letterSpacing: 6,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: '••••••',
              hintStyle: TextStyle(
                color: context.textMutedColor,
                letterSpacing: 6,
              ),
              prefixIcon: Icon(
                Icons.pin_rounded,
                color: isSelected
                    ? AppColors.brandAccent
                    : context.textSecondaryColor,
                size: 20,
              ),
              filled: true,
              fillColor: isSelected
                  ? AppColors.brandAccent.withValues(alpha: 0.08)
                  : (context.isDark
                      ? const Color(0xFF161922)
                      : const Color(0xFFF3F4F6)),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isSelected ? AppColors.brandAccent : context.borderColor,
                  width: isSelected ? 2 : 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.brandAccent,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildVirtualNumpad() {
    final digits = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['CLR', '0', '⌫'],
    ];

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF12151C) : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        children: [
          for (final row in digits)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final key in row)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _VirtualKey(
                        label: key,
                        color: key == 'CLR'
                            ? AppColors.statusRed
                            : (key == '⌫' ? AppColors.statusOrange : null),
                        icon: key == '⌫' ? Icons.backspace_outlined : null,
                        width: 72,
                        height: 44,
                        onTap: () {
                          if (key == 'CLR') {
                            _onVirtualClear();
                          } else if (key == '⌫') {
                            _onVirtualBackspace();
                          } else {
                            _onVirtualKeyPress(key);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VirtualKey extends StatefulWidget {
  const _VirtualKey({
    required this.label,
    this.icon,
    this.color,
    this.width,
    this.height,
    required this.onTap,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final double? width;
  final double? height;
  final VoidCallback onTap;

  @override
  State<_VirtualKey> createState() => _VirtualKeyState();
}

class _VirtualKeyState extends State<_VirtualKey> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double keyWidth = widget.width ?? 42.0;
    final double keyHeight = widget.height ?? 38.0;

    final bg = widget.color != null
        ? widget.color!.withValues(alpha: _isPressed ? 0.7 : 0.85)
        : (context.isDark
            ? (_isPressed ? const Color(0xFF2C3242) : const Color(0xFF1E222D))
            : (_isPressed ? const Color(0xFFD1D5DB) : Colors.white));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        setState(() => _isPressed = true);
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
      },
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 50),
        child: Container(
          width: keyWidth,
          height: keyHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.color ?? context.borderColor,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: widget.icon != null
              ? Icon(widget.icon, size: 18, color: Colors.white)
              : Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.color != null
                        ? Colors.white
                        : context.textPrimaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}

