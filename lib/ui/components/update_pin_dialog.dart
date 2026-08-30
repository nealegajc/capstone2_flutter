import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/sqlite_service.dart';
import 'pin_dots_indicator.dart';

enum UpdatePinStep {
  currentPin,
  newPin,
  confirmPin,
}

class UpdatePinDialog extends StatefulWidget {
  const UpdatePinDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const UpdatePinDialog(),
    );
  }

  @override
  State<UpdatePinDialog> createState() => _UpdatePinDialogState();
}

class _UpdatePinDialogState extends State<UpdatePinDialog> {
  UpdatePinStep _currentStep = UpdatePinStep.currentPin;
  String _currentPinInput = '';
  String _newPinInput = '';
  String _confirmPinInput = '';

  String? _errorMessage;
  bool _isLoading = false;

  void _onKeyPress(String val) {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      switch (_currentStep) {
        case UpdatePinStep.currentPin:
          if (_currentPinInput.length < 6) {
            _currentPinInput += val;
            if (_currentPinInput.length == 6) {
              _validateCurrentPin();
            }
          }
          break;
        case UpdatePinStep.newPin:
          if (_newPinInput.length < 6) {
            _newPinInput += val;
            if (_newPinInput.length == 6) {
              _currentStep = UpdatePinStep.confirmPin;
            }
          }
          break;
        case UpdatePinStep.confirmPin:
          if (_confirmPinInput.length < 6) {
            _confirmPinInput += val;
            if (_confirmPinInput.length == 6) {
              _validateAndSaveNewPin();
            }
          }
          break;
      }
    });
  }

  void _onBackspace() {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      switch (_currentStep) {
        case UpdatePinStep.currentPin:
          if (_currentPinInput.isNotEmpty) {
            _currentPinInput = _currentPinInput.substring(0, _currentPinInput.length - 1);
          }
          break;
        case UpdatePinStep.newPin:
          if (_newPinInput.isNotEmpty) {
            _newPinInput = _newPinInput.substring(0, _newPinInput.length - 1);
          }
          break;
        case UpdatePinStep.confirmPin:
          if (_confirmPinInput.isNotEmpty) {
            _confirmPinInput = _confirmPinInput.substring(0, _confirmPinInput.length - 1);
          } else {
            // Go back to new pin step
            _currentStep = UpdatePinStep.newPin;
          }
          break;
      }
    });
  }

  void _onClear() {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      switch (_currentStep) {
        case UpdatePinStep.currentPin:
          _currentPinInput = '';
          break;
        case UpdatePinStep.newPin:
          _newPinInput = '';
          break;
        case UpdatePinStep.confirmPin:
          _confirmPinInput = '';
          break;
      }
    });
  }

  Future<void> _validateCurrentPin() async {
    setState(() => _isLoading = true);
    final isValid = await SqliteService.instance.verifyOwnerPin(_currentPinInput);

    if (!mounted) return;
    if (isValid) {
      setState(() {
        _isLoading = false;
        _currentStep = UpdatePinStep.newPin;
      });
    } else {
      setState(() {
        _isLoading = false;
        _currentPinInput = '';
        _errorMessage = 'Incorrect current PIN. Please try again.';
      });
    }
  }

  Future<void> _validateAndSaveNewPin() async {
    if (_newPinInput != _confirmPinInput) {
      setState(() {
        _confirmPinInput = '';
        _errorMessage = 'New PINs do not match. Please re-enter.';
      });
      return;
    }

    if (_newPinInput == _currentPinInput) {
      setState(() {
        _confirmPinInput = '';
        _newPinInput = '';
        _currentStep = UpdatePinStep.newPin;
        _errorMessage = 'New PIN must be different from current PIN.';
      });
      return;
    }

    setState(() => _isLoading = true);
    try {
      final success = await SqliteService.instance.updateOwnerPin(
        oldPin: _currentPinInput,
        newPin: _newPinInput,
      );
      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop(true);
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to update PIN in local database.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error saving PIN: $e';
        });
      }
    }
  }

  int get _currentPinLength {
    switch (_currentStep) {
      case UpdatePinStep.currentPin:
        return _currentPinInput.length;
      case UpdatePinStep.newPin:
        return _newPinInput.length;
      case UpdatePinStep.confirmPin:
        return _confirmPinInput.length;
    }
  }

  Widget _buildStepIndicator(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStepBadge(context, 1, 'Current', _currentStep == UpdatePinStep.currentPin, _currentStep.index > 0),
        Container(width: 10, height: 2, color: _currentStep.index >= 1 ? AppColors.brandAccent : context.borderColor),
        _buildStepBadge(context, 2, 'New PIN', _currentStep == UpdatePinStep.newPin, _currentStep.index > 1),
        Container(width: 10, height: 2, color: _currentStep.index >= 2 ? AppColors.brandAccent : context.borderColor),
        _buildStepBadge(context, 3, 'Confirm', _currentStep == UpdatePinStep.confirmPin, false),
      ],
    );
  }

  Widget _buildStepBadge(BuildContext context, int step, String title, bool isCurrent, bool isCompleted) {
    Color bg;
    Color border;
    Color text;

    if (isCompleted) {
      bg = AppColors.statusGreenBg;
      border = AppColors.statusGreen;
      text = AppColors.statusGreen;
    } else if (isCurrent) {
      bg = AppColors.brandAccent.withValues(alpha: 0.2);
      border = AppColors.brandAccent;
      text = AppColors.brandAccent;
    } else {
      bg = context.surfaceElevatedColor;
      border = context.borderColor;
      text = context.textMutedColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: isCurrent ? 1.5 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCompleted)
            const Icon(Icons.check_rounded, color: AppColors.statusGreen, size: 12)
          else
            Text(
              '$step',
              style: TextStyle(color: text, fontWeight: FontWeight.bold, fontSize: 11),
            ),
          const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(color: text, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildNumpadKey(BuildContext context, String label, {VoidCallback? onTap, Color? color}) {
    return SizedBox(
      width: 72,
      height: 60,
      child: ElevatedButton(
        onPressed: _isLoading ? null : (onTap ?? () => _onKeyPress(label)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? context.surfaceElevatedColor,
          foregroundColor: context.textPrimaryColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.zero,
          elevation: 0,
          side: BorderSide(color: context.borderColor),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String stepTitle;
    String stepSubtitle;

    switch (_currentStep) {
      case UpdatePinStep.currentPin:
        stepTitle = 'Enter Current Security PIN';
        stepSubtitle = 'Authenticate using your existing 6-digit PIN';
        break;
      case UpdatePinStep.newPin:
        stepTitle = 'Enter New 6-Digit PIN';
        stepSubtitle = 'Choose a secure 6-digit numeric PIN for the terminal';
        break;
      case UpdatePinStep.confirmPin:
        stepTitle = 'Confirm New PIN';
        stepSubtitle = 'Re-enter your new 6-digit PIN to confirm';
        break;
    }

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 440,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lock_reset_rounded, color: AppColors.brandAccent, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'Update Security PIN',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.textPrimaryColor),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close_rounded, color: context.textSecondaryColor),
                  tooltip: 'Cancel',
                ),
              ],
            ),
            Divider(height: 20, color: context.borderColor),

            // Stepper
            _buildStepIndicator(context),
            const SizedBox(height: 18),

            // Step Title & Subtitle
            Text(
              stepTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
            ),
            const SizedBox(height: 4),
            Text(
              stepSubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 16),

            // Pin Dots
            PinDotsIndicator(
              pinLength: 6,
              enteredLength: _currentPinLength,
              hasError: _errorMessage != null,
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.statusRedBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.statusRed.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: AppColors.statusRed, size: 16),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: AppColors.statusRed, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),

            // On-screen Touch Numpad
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNumpadKey(context, '1'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '2'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '3'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNumpadKey(context, '4'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '5'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '6'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNumpadKey(context, '7'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '8'),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '9'),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildNumpadKey(
                      context,
                      'C',
                      onTap: _onClear,
                      color: AppColors.statusOrangeBg,
                    ),
                    const SizedBox(width: 12),
                    _buildNumpadKey(context, '0'),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 72,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _onBackspace,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.surfaceElevatedColor,
                          foregroundColor: context.textPrimaryColor,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: EdgeInsets.zero,
                          elevation: 0,
                          side: BorderSide(color: context.borderColor),
                        ),
                        child: Icon(Icons.backspace_outlined, size: 20, color: context.textPrimaryColor),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
