import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/alert_model.dart';
import '../../providers/kiosk_providers.dart';
import 'scan_workflow_dialog.dart';

class MisplacementBanner extends ConsumerWidget {
  const MisplacementBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final misplacements = ref.watch(activeMisplacementsProvider);

    if (misplacements.isEmpty) {
      return const SizedBox.shrink();
    }

    final AlertModel primaryAlert = misplacements.first;
    final int extraCount = misplacements.length - 1;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.statusRed.withValues(alpha: 0.95),
        boxShadow: [
          BoxShadow(
            color: AppColors.statusRed.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          // Flashing warning icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),

          // Alert Message Description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'SHELF MISPLACEMENT INCIDENT ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (extraCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '+$extraCount More Misplaced',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  primaryAlert.desc.isNotEmpty
                      ? primaryAlert.desc
                      : 'A misplaced perfume bottle was detected on the wrong tray. Please relocate it to its designated shelf slot.',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Primary "Done Fixing, Verify Now" Action Button
          ElevatedButton.icon(
            onPressed: () {
              ScanWorkflowDialog.show(
                context,
                isTargetedVerification: true,
                targetAlert: primaryAlert,
              );
            },
            icon: const Icon(Icons.check_circle_rounded, size: 20),
            label: const Text(
              'Done Fixing, Verify Now',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 0.2,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.statusRed,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
