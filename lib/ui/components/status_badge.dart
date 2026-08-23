import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

enum StatusBadgeType {
  synced,
  good,
  lowStock,
  alert,
  pendingSync,
  misplaced,
  needsVerification,
  scanning,
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.type,
    this.customLabel,
    this.large = false,
  });

  final StatusBadgeType type;
  final String? customLabel;
  final bool large;

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color bgColor;
    IconData icon;
    String defaultLabel;

    switch (type) {
      case StatusBadgeType.synced:
        textColor = AppColors.statusGreen;
        bgColor = AppColors.statusGreenBg;
        icon = Icons.check_circle_outline_rounded;
        defaultLabel = 'Synced';
        break;
      case StatusBadgeType.good:
        textColor = AppColors.statusGreen;
        bgColor = AppColors.statusGreenBg;
        icon = Icons.check_circle_rounded;
        defaultLabel = 'Normal';
        break;
      case StatusBadgeType.lowStock:
        textColor = AppColors.statusRed;
        bgColor = AppColors.statusRedBg;
        icon = Icons.warning_amber_rounded;
        defaultLabel = 'Low Stock';
        break;
      case StatusBadgeType.alert:
        textColor = AppColors.statusRed;
        bgColor = AppColors.statusRedBg;
        icon = Icons.error_outline_rounded;
        defaultLabel = 'Alert';
        break;
      case StatusBadgeType.pendingSync:
        textColor = AppColors.statusOrange;
        bgColor = AppColors.statusOrangeBg;
        icon = Icons.sync_problem_rounded;
        defaultLabel = 'Pending Sync';
        break;
      case StatusBadgeType.misplaced:
        textColor = AppColors.statusOrange;
        bgColor = AppColors.statusOrangeBg;
        icon = Icons.move_up_rounded;
        defaultLabel = 'Misplaced';
        break;
      case StatusBadgeType.needsVerification:
        textColor = AppColors.statusOrange;
        bgColor = AppColors.statusOrangeBg;
        icon = Icons.help_outline_rounded;
        defaultLabel = 'Needs Verification';
        break;
      case StatusBadgeType.scanning:
        textColor = AppColors.statusBlue;
        bgColor = AppColors.statusBlueBg;
        icon = Icons.radar_rounded;
        defaultLabel = 'Active Scanning';
        break;
    }

    final label = customLabel ?? defaultLabel;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 16 : 12,
        vertical: large ? 8 : 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: textColor.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: large ? 20 : 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: large ? 15 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
