import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/hardware_camera_device.dart';
import '../../../data/models/shelf_region_model.dart';
import '../../../data/services/camera_hardware_service.dart';
import '../../../providers/kiosk_providers.dart';

class CameraAssignmentDialog extends ConsumerStatefulWidget {
  const CameraAssignmentDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CameraAssignmentDialog(),
    );
  }

  @override
  ConsumerState<CameraAssignmentDialog> createState() => _CameraAssignmentDialogState();
}

class _CameraAssignmentDialogState extends ConsumerState<CameraAssignmentDialog> {
  final Map<int, String> _assignedNodes = {};
  bool _isLoading = true;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _logicalCameras = [
    {
      'id': 1,
      'name': 'Camera 1A',
      'layer': 'Layer A (Top) - Left',
      'variants': '5 Variants (Slots A to E, AA1 to AE2)',
    },
    {
      'id': 2,
      'name': 'Camera 1B',
      'layer': 'Layer A (Top) - Right',
      'variants': '5 Variants (Slots F to K, AF1 to AK2)',
    },
    {
      'id': 3,
      'name': 'Camera 2A',
      'layer': 'Layer B (Middle) - Left',
      'variants': '5 Variants (Slots A to E, BA1 to BE2)',
    },
    {
      'id': 4,
      'name': 'Camera 2B',
      'layer': 'Layer B (Middle) - Right',
      'variants': '5 Variants (Slots F to K, BF1 to BK2)',
    },
    {
      'id': 5,
      'name': 'Camera 3A',
      'layer': 'Layer C (Bottom) - Left',
      'variants': '5 Variants (Slots A to E, CA1 to CE2)',
    },
    {
      'id': 6,
      'name': 'Camera 3B',
      'layer': 'Layer C (Bottom) - Right',
      'variants': '5 Variants (Slots F to K, CF1 to CK2)',
    },
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentAssignments();
  }

  Future<void> _loadCurrentAssignments() async {
    final hwService = ref.read(cameraHardwareServiceProvider);
    _assignedNodes.addAll(hwService.cameraNodeMap);

    try {
      final sqlite = ref.read(sqliteServiceProvider);
      final regions = await sqlite.getShelfRegions('San Pablo');
      for (final r in regions) {
        if (r.deviceNode.isNotEmpty) {
          _assignedNodes[r.cameraId] = r.deviceNode;
        }
      }
    } catch (_) {}

    // Ensure all 6 cameras have a default
    for (int i = 1; i <= 6; i++) {
      _assignedNodes.putIfAbsent(i, () => '/dev/video${i - 1}');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAssignments() async {
    setState(() => _isSaving = true);
    final sqlite = ref.read(sqliteServiceProvider);
    final hwService = ref.read(cameraHardwareServiceProvider);

    try {
      // 1. Update Hardware Service map
      hwService.setCameraAssignments(_assignedNodes);

      // 2. Persist to SQLite shelf_regions
      final regions = await sqlite.getShelfRegions('San Pablo');
      for (int camId = 1; camId <= 6; camId++) {
        final node = _assignedNodes[camId] ?? '/dev/video${camId - 1}';
        final match = regions.where((r) => r.cameraId == camId).firstOrNull;
        if (match != null) {
          final updated = match.copyWith(deviceNode: node);
          await sqlite.updateShelfRegion(updated);
        } else {
          final newRegion = ShelfRegionModel(
            id: 'roi_San_Pablo_cam_$camId',
            code: 'Camera $camId',
            assignedProductId: '',
            assignedProductName: 'Camera $camId Region',
            branch: 'San Pablo',
            cameraId: camId,
            deviceNode: node,
          );
          await sqlite.updateShelfRegion(newRegion);
        }
      }

      // 3. Invalidate Riverpod cache
      ref.invalidate(shelfRegionsProvider('San Pablo'));
      ref.invalidate(shelfRegionsProvider(''));

      // 4. If streaming, switch to the new device node
      if (hwService.isStreaming) {
        final activeNode = _assignedNodes[hwService.activeCameraId];
        if (activeNode != null) {
          await hwService.switchCamera(hwService.activeCameraId, activeNode);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera device node assignments saved and applied.'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save assignments: $e'),
            backgroundColor: AppColors.statusRed,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hardwareCamerasAsync = ref.watch(hardwareCamerasProvider);
    final detectedDevices = hardwareCamerasAsync.valueOrNull ?? [];

    // Distinct list of available node choices: detected physical devices first, then standard nodes
    final Map<String, String> nodeLabels = {};
    for (final d in detectedDevices) {
      nodeLabels[d.deviceNode] = d.displayName;
    }
    for (int i = 0; i <= 5; i++) {
      nodeLabels.putIfAbsent('/dev/video$i', () => '/dev/video$i (V4L2 Video Node)');
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.surfaceColor,
      child: Container(
        width: 760,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.videocam_rounded, color: AppColors.brandAccent, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '6-Camera Hardware Node Assignment',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Text(
                          'Assign physical V4L2 device nodes (e.g. Built-in Webcam vs Rapoo USB) to each shelf camera',
                          style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Divider(height: 24, color: context.borderColor),

            // Camera List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppColors.brandAccent),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _logicalCameras.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final cam = _logicalCameras[index];
                    final camId = cam['id'] as int;
                    final currentNode = _assignedNodes[camId] ?? '/dev/video${camId - 1}';

                    // Check if currentNode matches a detected physical camera
                    final physicalMatch = detectedDevices.where((d) => d.deviceNode == currentNode).firstOrNull;

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceElevatedColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: physicalMatch != null
                              ? AppColors.statusGreen.withValues(alpha: 0.4)
                              : context.borderColor,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.brandAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              cam['name'] as String,
                              style: const TextStyle(
                                color: AppColors.brandAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cam['layer'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                Text(
                                  cam['variants'] as String,
                                  style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Node Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: context.surfaceColor,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: physicalMatch != null
                                    ? AppColors.statusGreen.withValues(alpha: 0.6)
                                    : context.borderColor,
                              ),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: nodeLabels.containsKey(currentNode) ? currentNode : nodeLabels.keys.first,
                                dropdownColor: context.surfaceElevatedColor,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: context.textPrimaryColor,
                                ),
                                items: nodeLabels.entries.map((entry) {
                                  final isDevDetected = detectedDevices.any((d) => d.deviceNode == entry.key);
                                  return DropdownMenuItem(
                                    value: entry.key,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isDevDetected ? Icons.check_circle_rounded : Icons.device_hub_rounded,
                                          size: 14,
                                          color: isDevDetected ? AppColors.statusGreen : context.textMutedColor,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(entry.value),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newNode) {
                                  if (newNode != null) {
                                    setState(() {
                                      _assignedNodes[camId] = newNode;
                                    });
                                  }
                                },
                              ),
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAssignments,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(_isSaving ? 'Saving...' : 'Save & Apply Assignments'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
