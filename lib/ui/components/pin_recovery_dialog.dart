import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _ans1Controller.dispose();
    _ans2Controller.dispose();
    _ans3Controller.dispose();
    _newPinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
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
        width: 580,
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
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
              Divider(height: 28, color: context.borderColor),

              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
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
                const SizedBox(height: 18),
              ],

              if (_currentStep == 0) ...[
                // Question 1
                _buildQuestionField(
                  label: AppConstants.recoveryQuestion1,
                  hint: 'Enter founding year (e.g., 2024)',
                  controller: _ans1Controller,
                  icon: Icons.calendar_today_rounded,
                ),
                const SizedBox(height: 18),

                // Question 2
                _buildQuestionField(
                  label: AppConstants.recoveryQuestion2,
                  hint: 'Enter security answer',
                  controller: _ans2Controller,
                  icon: Icons.badge_outlined,
                ),
                const SizedBox(height: 18),

                // Question 3
                _buildQuestionField(
                  label: AppConstants.recoveryQuestion3,
                  hint: 'Enter registered branch name (e.g., San Pablo)',
                  controller: _ans3Controller,
                  icon: Icons.storefront_outlined,
                ),
                const SizedBox(height: 26),

                SizedBox(
                  height: 54,
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
                  label: 'New 6-Digit Store PIN',
                  controller: _newPinController,
                ),
                const SizedBox(height: 18),
                _buildPinField(
                  label: 'Confirm New PIN',
                  controller: _confirmPinController,
                ),
                const SizedBox(height: 26),

                SizedBox(
                  height: 54,
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
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textPrimaryColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          style: TextStyle(color: context.textPrimaryColor, fontSize: 16),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: context.textMutedColor),
            prefixIcon: Icon(icon, color: AppColors.brandAccent, size: 22),
            filled: true,
            fillColor: context.isDark
                ? const Color(0xFF161922)
                : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 16,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.brandAccent,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPinField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: context.textPrimaryColor,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          maxLength: AppConstants.pinLength,
          obscureText: true,
          style: TextStyle(
            color: context.textPrimaryColor,
            fontSize: 24,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: TextStyle(
              color: context.textMutedColor,
              letterSpacing: 8,
            ),
            prefixIcon: const Icon(
              Icons.pin_rounded,
              color: AppColors.brandAccent,
              size: 24,
            ),
            filled: true,
            fillColor: context.isDark
                ? const Color(0xFF161922)
                : const Color(0xFFF3F4F6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 18,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor, width: 1.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: context.borderColor, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: AppColors.brandAccent,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
