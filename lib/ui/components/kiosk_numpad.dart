import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';

class KioskNumpad extends StatelessWidget {
  const KioskNumpad({
    super.key,
    required this.onDigitPressed,
    required this.onDeletePressed,
    required this.onClearPressed,
    this.isEnabled = true,
  });

  final ValueChanged<String> onDigitPressed;
  final VoidCallback onDeletePressed;
  final VoidCallback onClearPressed;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 480),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(context, ['1', '2', '3']),
          const SizedBox(height: 12),
          _buildRow(context, ['4', '5', '6']),
          const SizedBox(height: 12),
          _buildRow(context, ['7', '8', '9']),
          const SizedBox(height: 12),
          _buildBottomRow(context),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, List<String> digits) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: digits.map((digit) {
        return Expanded(
          child: _NumpadKey(
            key: ValueKey('numpad_key_$digit'),
            label: digit,
            onTap: isEnabled ? () => onDigitPressed(digit) : null,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBottomRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Clear Button
        Expanded(
          child: _NumpadActionKey(
            key: const ValueKey('numpad_action_clear'),
            label: 'CLEAR',
            icon: Icons.refresh_rounded,
            bgColor: AppColors.statusRed,
            onTap: isEnabled ? onClearPressed : null,
          ),
        ),
        // Digit 0
        Expanded(
          child: _NumpadKey(
            key: const ValueKey('numpad_key_0'),
            label: '0',
            onTap: isEnabled ? () => onDigitPressed('0') : null,
          ),
        ),
        // Backspace Button
        Expanded(
          child: _NumpadActionKey(
            key: const ValueKey('numpad_action_delete'),
            label: 'DELETE',
            icon: Icons.backspace_outlined,
            bgColor: AppColors.statusOrange,
            onTap: isEnabled ? onDeletePressed : null,
          ),
        ),
      ],
    );
  }
}

class _NumpadKey extends StatefulWidget {
  const _NumpadKey({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_NumpadKey> createState() => _NumpadKeyState();
}

class _NumpadKeyState extends State<_NumpadKey> {
  bool _isPressed = false;

  void _handleTapDown() {
    if (widget.onTap == null) return;
    if (mounted) {
      setState(() => _isPressed = true);
    }
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _handleTapUp() {
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTap() {
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    final isDark = context.isDark;

    final baseKeyBg = isDark ? AppColors.numpadKeyBg : context.surfaceColor;
    final pressedBg = isDark
        ? AppColors.brandAccent.withValues(alpha: 0.35)
        : AppColors.brandAccent.withValues(alpha: 0.2);

    final keyBg = isEnabled
        ? (_isPressed ? pressedBg : baseKeyBg)
        : baseKeyBg.withValues(alpha: 0.4);

    final borderColor = isEnabled
        ? (_isPressed ? AppColors.brandAccent : context.borderColor)
        : context.borderColor.withValues(alpha: 0.4);

    final textColor = isEnabled
        ? (_isPressed ? AppColors.brandAccent : context.textPrimaryColor)
        : context.textMutedColor;

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: 'Digit ${widget.label}',
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isEnabled ? (_) => _handleTapDown() : null,
        onTapUp: isEnabled ? (_) => _handleTapUp() : null,
        onTapCancel: isEnabled ? () => _handleTapCancel() : null,
        onTap: isEnabled ? () => _handleTap() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: AnimatedScale(
            scale: _isPressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              height: AppConstants.numpadKeyHeight,
              decoration: BoxDecoration(
                color: keyBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: borderColor,
                  width: _isPressed ? 2.5 : 1.5,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: _isPressed
                              ? AppColors.brandAccent.withValues(alpha: 0.3)
                              : Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.06,
                                ),
                          offset: _isPressed
                              ? const Offset(0, 1)
                              : const Offset(0, 4),
                          blurRadius: _isPressed ? 4 : 8,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumpadActionKey extends StatefulWidget {
  const _NumpadActionKey({
    super.key,
    required this.label,
    required this.icon,
    required this.bgColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color bgColor;
  final VoidCallback? onTap;

  @override
  State<_NumpadActionKey> createState() => _NumpadActionKeyState();
}

class _NumpadActionKeyState extends State<_NumpadActionKey> {
  bool _isPressed = false;

  void _handleTapDown() {
    if (widget.onTap == null) return;
    if (mounted) {
      setState(() => _isPressed = true);
    }
    SystemSound.play(SystemSoundType.click);
    HapticFeedback.lightImpact();
  }

  void _handleTapUp() {
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTapCancel() {
    if (mounted) {
      setState(() => _isPressed = false);
    }
  }

  void _handleTap() {
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onTap != null;
    final semanticLabel = widget.label == 'DELETE'
        ? 'Delete last digit'
        : 'Clear all digits';

    final activeBg = widget.bgColor.withValues(alpha: _isPressed ? 0.75 : 1.0);
    final currentBg = isEnabled
        ? activeBg
        : widget.bgColor.withValues(alpha: 0.3);

    return Semantics(
      button: true,
      enabled: isEnabled,
      label: semanticLabel,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: isEnabled ? (_) => _handleTapDown() : null,
        onTapUp: isEnabled ? (_) => _handleTapUp() : null,
        onTapCancel: isEnabled ? () => _handleTapCancel() : null,
        onTap: isEnabled ? () => _handleTap() : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: AnimatedScale(
            scale: _isPressed ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 60),
              height: AppConstants.numpadKeyHeight,
              decoration: BoxDecoration(
                color: currentBg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isEnabled
                      ? (_isPressed
                            ? Colors.white70
                            : widget.bgColor.withValues(alpha: 0.6))
                      : widget.bgColor.withValues(alpha: 0.2),
                  width: _isPressed ? 2.5 : 1.5,
                ),
                boxShadow: isEnabled
                    ? [
                        BoxShadow(
                          color: widget.bgColor.withValues(
                            alpha: _isPressed ? 0.4 : 0.25,
                          ),
                          offset: _isPressed
                              ? const Offset(0, 1)
                              : const Offset(0, 4),
                          blurRadius: _isPressed ? 4 : 8,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.icon,
                    color: isEnabled ? Colors.white : Colors.white54,
                    size: 26,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    widget.label,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
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
