import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/hardware_camera_device.dart';
import '../../../providers/kiosk_providers.dart';

/// Read-only Hardware & Camera Diagnostics dialog.
/// Displays locked physical camera bindings, USB hub ports, and live health status.
class CameraAssignmentDialog extends ConsumerStatefulWidget {
  const CameraAssignmentDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const CameraAssignmentDialog(),
    );
  }

  @override
  ConsumerState<CameraAssignmentDialog> createState() =>
      _CameraAssignmentDialogState();
}

class _CameraAssignmentDialogState
    extends ConsumerState<CameraAssignmentDialog> {
  bool _isProbing = false;

  final List<Map<String, dynamic>> _logicalCameras = [
    {
      'id': 1,
      'name': 'Cam 1A (Top Left)',
      'tier': 'Tier A (Top Shelf)',
      'position': 'Left Section • Slots A to E',
      'node': '/dev/cam1a',
      'hubPort': 'Hub 1 • Port 1 (1-1.1)',
      'portId': '1-1.1',
    },
    {
      'id': 2,
      'name': 'Cam 1B (Top Right)',
      'tier': 'Tier A (Top Shelf)',
      'position': 'Right Section • Slots F to K',
      'node': '/dev/cam1b',
      'hubPort': 'Hub 2 • Port 1 (1-2.1)',
      'portId': '1-2.1',
    },
    {
      'id': 3,
      'name': 'Cam 2A (Middle Left)',
      'tier': 'Tier B (Middle Shelf)',
      'position': 'Left Section • Slots A to E',
      'node': '/dev/cam2a',
      'hubPort': 'Hub 1 • Port 2 (1-1.2)',
      'portId': '1-1.2',
    },
    {
      'id': 4,
      'name': 'Cam 2B (Middle Right)',
      'tier': 'Tier B (Middle Shelf)',
      'position': 'Right Section • Slots F to K',
      'node': '/dev/cam2b',
      'hubPort': 'Hub 2 • Port 2 (1-2.2)',
      'portId': '1-2.2',
    },
    {
      'id': 5,
      'name': 'Cam 3A (Bottom Left)',
      'tier': 'Tier C (Bottom Shelf)',
      'position': 'Left Section • Slots A to E',
      'node': '/dev/cam3a',
      'hubPort': 'Hub 1 • Port 3 (1-1.3)',
      'portId': '1-1.3',
    },
    {
      'id': 6,
      'name': 'Cam 3B (Bottom Right)',
      'tier': 'Tier C (Bottom Shelf)',
      'position': 'Right Section • Slots F to K',
      'node': '/dev/cam3b',
      'hubPort': 'Hub 2 • Port 3 (1-2.3)',
      'portId': '1-2.3',
    },
  ];

  Future<void> _refreshHardware() async {
    setState(() => _isProbing = true);
    try {
      final hwService = ref.read(cameraHardwareServiceProvider);
      await hwService.probeHardwareDevices();
      ref.invalidate(hardwareCamerasProvider);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isProbing = false);
      }
    }
  }

  bool _isCameraOnline(
    String expectedNode,
    String portId,
    List<HardwareCameraDevice> detectedDevices,
  ) {
    try {
      final file = File(expectedNode);
      if (file.existsSync()) {
        final resolvedPath = file.resolveSymbolicLinksSync();
        if (detectedDevices.any((d) =>
            d.deviceNode == resolvedPath || d.deviceNode == expectedNode)) {
          return true;
        }
        // If symlink exists on the file system, camera node is physically present and online
        return true;
      }
    } catch (_) {}

    return detectedDevices.any((d) =>
        d.deviceNode == expectedNode ||
        d.usbPort == portId);
  }

  @override
  Widget build(BuildContext context) {
    final hardwareCamerasAsync = ref.watch(hardwareCamerasProvider);
    final detectedDevices = hardwareCamerasAsync.valueOrNull ?? [];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.surfaceColor,
      child: Container(
        width: 860,
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.health_and_safety_rounded,
                          color: AppColors.brandAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hardware & Camera Diagnostics',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Fixed shelf camera mappings, physical USB hub ports, and real-time connectivity status',
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Divider(height: 24, color: context.borderColor),

            // Locked Hardware Notice Pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.brandAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: AppColors.brandAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Cameras are permanently mounted and locked to physical USB hub ports via Linux udev rules (/dev/cam1a – /dev/cam3b). Manual reassignment is disabled to protect hardware integrity.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Diagnostic Camera List
            Expanded(
              child: ListView.separated(
                itemCount: _logicalCameras.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final cam = _logicalCameras[index];
                  final String expectedNode = cam['node'] as String;
                  final String portId = cam['portId'] as String;

                  // Determine connection status based on symlinks and detected devices
                  final isOnline = _isCameraOnline(expectedNode, portId, detectedDevices);

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceElevatedColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOnline
                            ? AppColors.statusGreen.withValues(alpha: 0.3)
                            : context.borderColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Camera Identifier Avatar
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.statusGreen.withValues(alpha: 0.15)
                                : Colors.grey.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Icon(
                              isOnline
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              color: isOnline
                                  ? AppColors.statusGreen
                                  : Colors.grey,
                              size: 22,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Camera & Tier Details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    cam['name'] as String,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: context.surfaceColor,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: context.borderColor,
                                      ),
                                    ),
                                    child: Text(
                                      cam['tier'] as String,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${cam['position']} • ${cam['hubPort']}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Fixed Device Symlink Pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.terminal_rounded,
                                size: 14,
                                color: AppColors.brandAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                expectedNode,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Real-time Health Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.statusGreen.withValues(alpha: 0.15)
                                : AppColors.statusRed.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isOnline
                                  ? AppColors.statusGreen
                                  : AppColors.statusRed,
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isOnline
                                      ? AppColors.statusGreen
                                      : AppColors.statusRed,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'ONLINE' : 'OFFLINE',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: isOnline
                                      ? AppColors.statusGreen
                                      : AppColors.statusRed,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Re-probe Button
                OutlinedButton.icon(
                  onPressed: _isProbing ? null : _refreshHardware,
                  icon: _isProbing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_isProbing ? 'Probing...' : 'Re-probe Hardware'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),

                // Close Button
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text('Close Diagnostics'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
