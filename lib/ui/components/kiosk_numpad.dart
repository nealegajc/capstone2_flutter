import 'package:flutter/material.dart';
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
      constraints: const BoxConstraints(maxWidth: 380),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(context, ['1', '2', '3']),
          const SizedBox(height: 14),
          _buildRow(context, ['4', '5', '6']),
          const SizedBox(height: 14),
          _buildRow(context, ['7', '8', '9']),
          const SizedBox(height: 14),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: _NumpadKey(
              label: digit,
              onTap: isEnabled ? () => onDigitPressed(digit) : null,
            ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: _NumpadActionKey(
              label: 'CLEAR',
              icon: Icons.refresh_rounded,
              color: AppColors.statusRed,
              bgColor: AppColors.statusRedBg,
              onTap: isEnabled ? onClearPressed : null,
            ),
          ),
        ),
        // Digit 0
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: _NumpadKey(
              label: '0',
              onTap: isEnabled ? () => onDigitPressed('0') : null,
            ),
          ),
        ),
        // Backspace Button
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: _NumpadActionKey(
              label: 'DELETE',
              icon: Icons.backspace_outlined,
              color: AppColors.statusOrange,
              bgColor: AppColors.statusOrangeBg,
              onTap: isEnabled ? onDeletePressed : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _NumpadKey extends StatelessWidget {
  const _NumpadKey({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    final keyBg = context.isDark ? AppColors.numpadKeyBg : context.surfaceColor;
    final borderCol = isEnabled ? context.borderColor : context.borderColor.withValues(alpha: 0.4);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: AppColors.brandAccent.withValues(alpha: 0.3),
        highlightColor: context.isDark ? AppColors.numpadKeyPressed : Colors.black12,
        child: Ink(
          height: AppConstants.numpadKeyHeight,
          decoration: BoxDecoration(
            color: isEnabled ? keyBg : keyBg.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: borderCol,
              width: 1.5,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.05),
                      offset: const Offset(0, 4),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isEnabled ? context.textPrimaryColor : context.textMutedColor,
                fontSize: 32,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NumpadActionKey extends StatelessWidget {
  const _NumpadActionKey({
    required this.label,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isEnabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: color.withValues(alpha: 0.3),
        child: Ink(
          height: AppConstants.numpadKeyHeight,
          decoration: BoxDecoration(
            color: isEnabled ? bgColor : bgColor.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isEnabled ? color.withValues(alpha: 0.4) : color.withValues(alpha: 0.2),
              width: 1.5,
            ),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.05),
                      offset: const Offset(0, 4),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isEnabled ? color : color.withValues(alpha: 0.3),
                size: 24,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? color : color.withValues(alpha: 0.3),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
