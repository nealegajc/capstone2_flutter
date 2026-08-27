import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

class PinDotsIndicator extends StatefulWidget {
  const PinDotsIndicator({
    super.key,
    required this.pinLength,
    required this.enteredLength,
    this.hasError = false,
    this.isLockedOut = false,
  });

  final int pinLength;
  final int enteredLength;
  final bool hasError;
  final bool isLockedOut;

  @override
  State<PinDotsIndicator> createState() => _PinDotsIndicatorState();
}

class _PinDotsIndicatorState extends State<PinDotsIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Sine wave horizontal shake
    _shakeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _shakeController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant PinDotsIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasError && !oldWidget.hasError) {
      _shakeController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        final double offset = sin(_shakeAnimation.value * pi * 4) * 14 * (1 - _shakeAnimation.value);
        return Transform.translate(
          offset: Offset(offset, 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(widget.pinLength, (index) {
          final isFilled = index < widget.enteredLength;
          final isCurrent = index == widget.enteredLength;

          Color borderColor;
          Color fillColor;

          if (widget.isLockedOut) {
            borderColor = AppColors.statusRed.withValues(alpha: 0.4);
            fillColor = Colors.transparent;
          } else if (widget.hasError) {
            borderColor = AppColors.statusRed;
            fillColor = AppColors.statusRed.withValues(alpha: 0.3);
          } else if (isFilled) {
            borderColor = AppColors.brandAccent;
            fillColor = AppColors.brandAccent;
          } else if (isCurrent) {
            borderColor = AppColors.brandAccent.withValues(alpha: 0.6);
            fillColor = Colors.transparent;
          } else {
            borderColor = AppColors.darkBorder;
            fillColor = Colors.transparent;
          }

          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            width: isFilled ? 26 : 22,
            height: isFilled ? 26 : 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fillColor,
              border: Border.all(
                color: borderColor,
                width: isFilled || isCurrent ? 2.5 : 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: isFilled
                      ? AppColors.brandAccent.withValues(alpha: 0.35)
                      : Colors.transparent,
                  blurRadius: isFilled ? 8.0 : 0.0,
                  spreadRadius: isFilled ? 1.0 : 0.0,
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
