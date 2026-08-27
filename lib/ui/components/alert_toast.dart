import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AlertToast extends StatelessWidget {
  final String title;
  final String message;
  final String type;
  final VoidCallback? onDismiss;

  const AlertToast({
    super.key,
    required this.title,
    required this.message,
    this.type = 'info',
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Color accentColor;
    IconData icon;

    switch (type.toLowerCase()) {
      case 'low_stock':
      case 'warning':
        accentColor = AppColors.orange;
        icon = Icons.warning_amber_rounded;
        break;
      case 'out_of_stock':
      case 'missing':
      case 'error':
        accentColor = AppColors.red;
        icon = Icons.error_outline_rounded;
        break;
      case 'misplaced':
        accentColor = AppColors.purple;
        icon = Icons.swap_horiz_rounded;
        break;
      case 'success':
      case 'restock':
        accentColor = AppColors.green;
        icon = Icons.check_circle_outline_rounded;
        break;
      default:
        accentColor = AppColors.blue;
        icon = Icons.info_outline_rounded;
    }

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16.0),
        constraints: const BoxConstraints(maxWidth: 450),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: accentColor.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: TextStyle(
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: isDark ? Colors.white60 : Colors.black45,
                  size: 20,
                ),
                onPressed: onDismiss,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
