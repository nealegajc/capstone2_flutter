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
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(18.0),
          border: Border.all(color: accentColor.withOpacity(0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
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
                color: accentColor.withOpacity(0.2),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded, color: Colors.white60, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
