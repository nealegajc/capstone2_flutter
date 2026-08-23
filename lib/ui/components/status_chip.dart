import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class StatusChip extends StatelessWidget {
  final String status;
  final String? customLabel;
  final IconData? icon;
  final double fontSize;

  const StatusChip({
    super.key,
    required this.status,
    this.customLabel,
    this.icon,
    this.fontSize = 13.0,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    IconData defaultIcon;
    String text = customLabel ?? status.replaceAll('_', ' ').toUpperCase();

    switch (status.toLowerCase()) {
      case 'normal':
      case 'synced':
      case 'active':
      case 'connected':
      case 'verified':
      case 'received':
      case 'present':
        bg = AppColors.greenBg;
        fg = AppColors.green;
        defaultIcon = Icons.check_circle_outline;
        break;
      case 'low':
      case 'pending':
      case 'warning':
        bg = AppColors.orangeBg;
        fg = AppColors.orange;
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case 'out_of_stock':
      case 'missing':
      case 'failed':
      case 'offline':
      case 'critical':
      case 'stopped_max_retry':
        bg = AppColors.redBg;
        fg = AppColors.red;
        defaultIcon = Icons.error_outline_rounded;
        break;
      case 'misplaced':
        bg = AppColors.purpleBg;
        fg = AppColors.purple;
        defaultIcon = Icons.swap_horiz_rounded;
        break;
      case 'needs_review':
      case 'review':
      case 'enhanced':
      case 'syncing':
        bg = AppColors.blueBg;
        fg = AppColors.blue;
        defaultIcon = Icons.sync_rounded;
        break;
      default:
        bg = AppColors.grayBg;
        fg = AppColors.gray;
        defaultIcon = Icons.info_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(30.0),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? defaultIcon, size: fontSize + 2, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
