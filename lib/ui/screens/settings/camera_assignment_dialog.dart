import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/shelf_region_model.dart';
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
  ConsumerState<CameraAssignmentDialog> createState() =>
      _CameraAssignmentDialogState();
}

class _CameraAssignmentDialogState
    extends ConsumerState<CameraAssignmentDialog> {
  final Map<int, String> _assignedNodes = {};
  bool _isLoading = true;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _logicalCameras = [
    {
      'id': 1,
      'name': 'Cam 1A (left)',
      'layer': 'Layer A (Top) - Left',
      'variants': '5 Variants (Slots A to E, AA1 to AE2)',
    },
    {
      'id': 2,
      'name': 'Cam 1B (Right)',
      'layer': 'Layer A (Top) - Right',
      'variants': '5 Variants (Slots F to K, AF1 to AK2)',
    },
    {
      'id': 3,
      'name': 'Cam 2A (left)',
      'layer': 'Layer B (Middle) - Left',
      'variants': '5 Variants (Slots A to E, BA1 to BE2)',
    },
    {
      'id': 4,
      'name': 'Cam 2B (Right)',
      'layer': 'Layer B (Middle) - Right',
      'variants': '5 Variants (Slots F to K, BF1 to BK2)',
    },
    {
      'id': 5,
      'name': 'Cam 3A (left)',
      'layer': 'Layer C (Bottom) - Left',
      'variants': '5 Variants (Slots A to E, CA1 to CE2)',
    },
    {
      'id': 6,
      'name': 'Cam 3B (Right)',
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

    // 1. Primary Source of Truth: Hardware Service persistent map (backed by camera_assignments.json)
    _assignedNodes.addAll(hwService.cameraNodeMap);

    // 2. Default mapping: use hardware service assigned device nodes per camera
    for (int i = 1; i <= 6; i++) {
      _assignedNodes.putIfAbsent(i, () => hwService.getAssignedDeviceNode(i));
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
      // 1. Update Hardware Service persistent map & auto-lock to physical USB ports
      hwService.setCameraAssignments(_assignedNodes);

      // 2. Persist to ALL SQLite shelf_regions (updating both 100ml and 50ml regions per camera)
      final regions = await sqlite.getShelfRegions('San Pablo');
      for (final r in regions) {
        final node = _assignedNodes[r.cameraId];
        if (node != null && node.isNotEmpty) {
          final updated = r.copyWith(deviceNode: node);
          await sqlite.updateShelfRegion(updated);
        }
      }

      // If regions did not exist, seed them properly
      if (regions.isEmpty) {
        for (int camId = 1; camId <= 6; camId++) {
          final node = _assignedNodes[camId] ?? '/dev/video2';
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

    // Map physical camera nodes to clear, user-friendly App shelf names
    String formatFriendlyLabel(
      String node, {
      String? usbPort,
      String? fallbackName,
      bool isRapoo = false,
      bool isSunplus = false,
      bool isBuiltIn = false,
    }) {
      final port = usbPort ?? '';
      String portStr = port.isNotEmpty ? ' • Port $port' : '';

      if (port.startsWith('1-1.')) {
        final p = port.replaceFirst('1-1.', '');
        portStr = ' • Hub 1 Port $p';
      } else if (port.startsWith('1-2.')) {
        final p = port.replaceFirst('1-2.', '');
        portStr = ' • Hub 2 Port $p';
      }

      if (isBuiltIn ||
          (fallbackName != null &&
              fallbackName.toLowerCase().contains('integrated')) ||
          node == '/dev/video0') {
        return 'Laptop Integrated Webcam ($node)';
      }

      String shelfName = '';
      if (port == '1-1.1') {
        shelfName = 'Cam 1A (Top Left - Hub 1)';
      } else if (port == '1-2.1') {
        shelfName = 'Cam 1B (Top Right - Hub 2)';
      } else if (port == '1-1.2') {
        shelfName = 'Cam 2A (Mid Left - Hub 1)';
      } else if (port == '1-2.2') {
        shelfName = 'Cam 2B (Mid Right - Hub 2)';
      } else if (port == '1-1.3') {
        shelfName = 'Cam 3A (Bottom Left - Hub 1)';
      } else if (port == '1-2.3') {
        shelfName = 'Cam 3B (Bottom Right - Hub 2)';
      }

      if (shelfName.isNotEmpty) {
        return '$shelfName • $node$portStr';
      }

      if (isSunplus ||
          (fallbackName != null &&
              (fallbackName.toLowerCase().contains('sunplus') ||
                  fallbackName.toLowerCase().contains('web camera')))) {
        return 'SunplusIT Web Camera ($node$portStr)';
      }

      if (isRapoo ||
          (fallbackName != null &&
              fallbackName.toLowerCase().contains('rapoo'))) {
        return 'Rapoo 2K QHD Webcam ($node$portStr)';
      }

      return fallbackName != null && fallbackName.isNotEmpty
          ? '$fallbackName ($node$portStr)'
          : 'USB Camera ($node$portStr)';
    }

    // Clean, distinct list of choices matching the App's camera names
    final Map<String, String> nodeLabels = {'none': 'None / Unassigned (N/A)'};
    for (final d in detectedDevices) {
      nodeLabels[d.deviceNode] = formatFriendlyLabel(
        d.deviceNode,
        usbPort: d.usbPort,
        fallbackName: d.displayName,
        isRapoo: d.isRapooCamera,
        isSunplus: d.isSunplusCamera,
        isBuiltIn: d.isBuiltInWebcam,
      );
    }
    for (final entry in _assignedNodes.entries) {
      final node = entry.value;
      if (node != 'none' && node.isNotEmpty && !nodeLabels.containsKey(node)) {
        final camMeta = _logicalCameras
            .where((c) => c['id'] == entry.key)
            .firstOrNull;
        final camTitle = camMeta != null
            ? '${camMeta['name']}'
            : 'Camera ${entry.key}';
        nodeLabels[node] = '$camTitle • $node';
      }
    }

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: context.surfaceColor,
      child: Container(
        width: 840,
        constraints: BoxConstraints(
          maxWidth: 880,
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
                          Icons.videocam_rounded,
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
                              '6-Camera Hardware Node Assignment',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Assign physical V4L2 device nodes to each shelf zone or set to "None (N/A)"',
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

            // Informative Exclusive Binding Notice
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
                    Icons.swap_horiz_rounded,
                    color: AppColors.brandAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Flexible Camera Reassignment: Set any camera to "None (N/A)" to disconnect it, or select an in-use camera node to transfer it automatically.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Camera List
            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(
                    color: AppColors.brandAccent,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _logicalCameras.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final cam = _logicalCameras[index];
                    final camId = cam['id'] as int;
                    final currentNode = _assignedNodes[camId] ?? 'none';
                    final isUnassigned =
                        currentNode == 'none' || currentNode.isEmpty;

                    // Find which nodes are already assigned to other cameras (only when multiple external cameras exist)
                    final hasMultipleExternal =
                        detectedDevices
                            .where((d) => !d.isBuiltInWebcam)
                            .length >
                        2;
                    final Map<String, String> nodesAssignedToOther = {};
                    final Map<String, int> nodeToOtherCamId = {};
                    if (hasMultipleExternal) {
                      for (final other in _logicalCameras) {
                        final otherId = other['id'] as int;
                        if (otherId != camId) {
                          final assigned = _assignedNodes[otherId];
                          if (assigned != null &&
                              assigned != 'none' &&
                              assigned.isNotEmpty) {
                            nodesAssignedToOther[assigned] =
                                other['name'] as String;
                            nodeToOtherCamId[assigned] = otherId;
                          }
                        }
                      }
                    }

                    // Check if currentNode matches a detected physical camera
                    final physicalMatch = !isUnassigned
                        ? detectedDevices
                              .where((d) => d.deviceNode == currentNode)
                              .firstOrNull
                        : null;

                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isUnassigned
                            ? (context.isDark
                                  ? const Color(0xFF181B20)
                                  : const Color(0xFFF3F4F6))
                            : context.surfaceElevatedColor,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isUnassigned
                              ? context.borderColor.withValues(alpha: 0.5)
                              : (physicalMatch != null
                                    ? AppColors.statusGreen.withValues(
                                        alpha: 0.4,
                                      )
                                    : context.borderColor),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 120,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: isUnassigned
                                  ? context.textMutedColor.withValues(
                                      alpha: 0.15,
                                    )
                                  : AppColors.brandAccent.withValues(
                                      alpha: 0.15,
                                    ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              cam['name'] as String,
                              style: TextStyle(
                                color: isUnassigned
                                    ? context.textMutedColor
                                    : AppColors.brandAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  cam['layer'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: isUnassigned
                                        ? context.textSecondaryColor
                                        : context.textPrimaryColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  cam['variants'] as String,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.textMutedColor,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          // Node Dropdown with None / N/A and Auto-Transfer
                          Expanded(
                            flex: 5,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: context.surfaceColor,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isUnassigned
                                      ? context.borderColor
                                      : (physicalMatch != null
                                            ? AppColors.statusGreen.withValues(
                                                alpha: 0.6,
                                              )
                                            : context.borderColor),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: nodeLabels.containsKey(currentNode)
                                      ? currentNode
                                      : 'none',
                                  dropdownColor: context.surfaceElevatedColor,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: context.textPrimaryColor,
                                  ),
                                  items: nodeLabels.entries.map((entry) {
                                    final isNoneChoice = entry.key == 'none';
                                    final isAssignedToOther =
                                        !isNoneChoice &&
                                        nodesAssignedToOther.containsKey(
                                          entry.key,
                                        );
                                    final assignedCamName =
                                        nodesAssignedToOther[entry.key];
                                    final isDevDetected = detectedDevices.any(
                                      (d) => d.deviceNode == entry.key,
                                    );

                                    return DropdownMenuItem<String>(
                                      value: entry.key,
                                      child: Row(
                                        children: [
                                          Icon(
                                            isNoneChoice
                                                ? Icons
                                                      .do_not_disturb_on_outlined
                                                : (isAssignedToOther
                                                      ? Icons.swap_horiz_rounded
                                                      : (isDevDetected
                                                            ? Icons
                                                                  .check_circle_rounded
                                                            : Icons
                                                                  .device_hub_rounded)),
                                            size: 14,
                                            color: isNoneChoice
                                                ? context.textMutedColor
                                                : (isAssignedToOther
                                                      ? AppColors.brandGold
                                                      : (isDevDetected
                                                            ? AppColors
                                                                  .statusGreen
                                                            : context
                                                                  .textMutedColor)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              isAssignedToOther
                                                  ? '${entry.value} • (In use by $assignedCamName ⇄ Transfer)'
                                                  : entry.value,
                                              style: TextStyle(
                                                color: isNoneChoice
                                                    ? context.textMutedColor
                                                    : (isAssignedToOther
                                                          ? AppColors.brandGold
                                                          : context
                                                                .textPrimaryColor),
                                                fontStyle: isNoneChoice
                                                    ? FontStyle.italic
                                                    : FontStyle.normal,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (newNode) {
                                    if (newNode != null) {
                                      setState(() {
                                        // If the node was assigned to another camera, auto-transfer only if multiple external cameras are present
                                        if (hasMultipleExternal &&
                                            newNode != 'none' &&
                                            nodeToOtherCamId.containsKey(
                                              newNode,
                                            )) {
                                          final otherId =
                                              nodeToOtherCamId[newNode]!;
                                          final otherName =
                                              nodesAssignedToOther[newNode];
                                          _assignedNodes[otherId] = 'none';

                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Transferred ${nodeLabels[newNode]} to ${cam['name']}. ($otherName is now Unassigned).',
                                              ),
                                              backgroundColor:
                                                  AppColors.brandAccent,
                                              duration: const Duration(
                                                seconds: 3,
                                              ),
                                            ),
                                          );
                                        }

                                        _assignedNodes[camId] = newNode;
                                      });
                                    }
                                  },
                                ),
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
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveAssignments,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _isSaving ? 'Saving...' : 'Save & Apply Assignments',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
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
