import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/hardware_camera_device.dart';
import '../../../data/services/camera_hardware_service.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/roi_provider.dart';
import '../../components/roi_editor_overlay.dart';
import '../../components/scan_workflow_dialog.dart';
import '../settings/camera_assignment_dialog.dart';

class CameraMonitorScreen extends ConsumerStatefulWidget {
  const CameraMonitorScreen({super.key});

  @override
  ConsumerState<CameraMonitorScreen> createState() =>
      _CameraMonitorScreenState();
}

class _CameraMonitorScreenState extends ConsumerState<CameraMonitorScreen> {
  int _selectedCamera = 1; // 1 to 6
  bool _isScanning = false;
  bool _isRoiEditing = false;
  Timer? _fpsUpdateTimer;

  // 6 Mounted Cameras on the Shelf (2 Cameras per Layer × 3 Layers = 6 Total)
  static final Map<int, Map<String, dynamic>> _cameraInfo = {
    1: {
      'name': 'Top Shelf - Left Side',
      'title': 'Top Shelf (Left)',
      'layer': 'Top Shelf (Men\'s Fragrances)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['AA', 'AB', 'AC', 'AD', 'AE'],
      'codes': 'Slots AA to AE (50ml & 100ml)',
      'variants': '5 Men\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Bvlgari Extreme\n2. Bvlgari Aqua\n3. Clinique Happy Men\n4. Sauvage\n5. Polo Black',
    },
    2: {
      'name': 'Top Shelf - Right Side',
      'title': 'Top Shelf (Right)',
      'layer': 'Top Shelf (Men\'s Fragrances)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['AF', 'AG', 'AH', 'AJ', 'AK'],
      'codes': 'Slots AF to AK (50ml & 100ml)',
      'variants': '5 Men\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Cool Water\n2. Polo Red\n3. Lacoste Black\n4. Hugo Boss\n5. Lacoste Essential',
    },
    3: {
      'name': 'Middle Shelf - Left Side',
      'title': 'Middle Shelf (Left)',
      'layer': 'Middle Shelf (Mixed Fragrances)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['BA', 'BB', 'BC', 'BD', 'BE'],
      'codes': 'Slots BA to BE (50ml & 100ml)',
      'variants': '5 Men\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Lacoste Red\n2. Lacoste White\n3. Invictus\n4. Polo Sport\n5. Tommy Boy',
    },
    4: {
      'name': 'Middle Shelf - Right Side',
      'title': 'Middle Shelf (Right)',
      'layer': 'Middle Shelf (Mixed Fragrances)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['BF', 'BG', 'BH', 'BJ', 'BK'],
      'codes': 'Slots BF to BK (50ml & 100ml)',
      'variants': '5 Women\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Chanel Chance\n2. Chanel No.5\n3. Happy Women\n4. Moon Sparkle\n5. Be Delicious',
    },
    5: {
      'name': 'Bottom Shelf - Left Side',
      'title': 'Bottom Shelf (Left)',
      'layer': 'Bottom Shelf (Women\'s Fragrances)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['CA', 'CB', 'CC', 'CD', 'CE'],
      'codes': 'Slots CA to CE (50ml & 100ml)',
      'variants': '5 Women\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Light Blue\n2. Green Tea\n3. Chanel Coco\n4. Pleasures\n5. Incanto',
    },
    6: {
      'name': 'Bottom Shelf - Right Side',
      'title': 'Bottom Shelf (Right)',
      'layer': 'Bottom Shelf (Women\'s Fragrances)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['CF', 'CG', 'CH', 'CJ', 'CK'],
      'codes': 'Slots CF to CK (50ml & 100ml)',
      'variants': '5 Women\'s Fragrance Scents',
      'capacity': '50 Bottles Max (10 Scents × 5)',
      'assignedVariants': '1. Mimosa & Cardamom\n2. Romance\n3. La Vie Est Belle\n4. Eclat D\'Arpege\n5. Tommy Girl',
    },
  };

  @override
  void initState() {
    super.initState();
    // Proactively probe hardware devices upon navigation without opening video streams
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cameraHardwareServiceProvider).probeHardwareDevices();
    });

    _fpsUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _fpsUpdateTimer?.cancel();
    CameraHardwareService.instance.stopLiveStream();
    super.dispose();
  }

  String _getDeviceNodeForCamera(int cameraId) {
    return CameraHardwareService.instance.getAssignedDeviceNode(cameraId);
  }

  HardwareCameraDevice? _getMatchedHardwareDevice(int cameraId) {
    final targetNode = _getDeviceNodeForCamera(cameraId);
    final hwService = ref.read(cameraHardwareServiceProvider);

    final direct = hwService.devices
        .where((d) => d.deviceNode == targetNode)
        .firstOrNull;
    if (direct != null) return direct;

    try {
      final file = File(targetNode);
      if (file.existsSync()) {
        final resolved = file.resolveSymbolicLinksSync();
        final symMatch = hwService.devices
            .where((d) => d.deviceNode == resolved)
            .firstOrNull;
        if (symMatch != null) return symMatch;
      }
    } catch (_) {}

    final port = hwService.cameraUsbPortMap[cameraId];
    if (port != null && port.isNotEmpty) {
      final portMatch = hwService.devices
          .where((d) => d.usbPort == port)
          .firstOrNull;
      if (portMatch != null) return portMatch;
    }

    return null;
  }

  Future<void> _startLiveStreamForSelectedCamera() async {
    final targetDeviceNode = _getDeviceNodeForCamera(_selectedCamera);
    final hwService = ref.read(cameraHardwareServiceProvider);
    await hwService.startLiveStream(deviceNode: targetDeviceNode);
    if (mounted) setState(() {});
  }

  Future<void> _toggleLiveStream() async {
    final hwService = ref.read(cameraHardwareServiceProvider);
    final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
    if (hwService.isStreaming) {
      await hwService.stopLiveStream();
      await SqliteService.instance.logActivity(
        type: 'CAMERA_STREAM',
        description: 'Live video monitoring stopped for ${activeCam['name']}.',
        branch: 'San Pablo',
      );
    } else {
      await _startLiveStreamForSelectedCamera();
      await SqliteService.instance.logActivity(
        type: 'CAMERA_STREAM',
        description: 'Live video monitoring started for ${activeCam['name']}.',
        branch: 'San Pablo',
      );
    }
    if (mounted) setState(() {});
  }

  void _onCameraSelected(int camId) async {
    if (_selectedCamera != camId) {
      setState(() {
        _selectedCamera = camId;
      });
      final hwService = ref.read(cameraHardwareServiceProvider);
      final targetNode = _getDeviceNodeForCamera(camId);
      if (hwService.isStreaming) {
        await hwService.switchCamera(camId, targetNode);
      }
      if (mounted) setState(() {});
    }
  }

  void _triggerScan() async {
    final hasActiveMisplacement = ref.read(hasActiveMisplacementProvider);
    if (hasActiveMisplacement) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Please resolve active shelf misplacements before running an inventory scan.'),
          backgroundColor: AppColors.statusRed,
        ),
      );
      return;
    }
    setState(() => _isScanning = true);
    try {
      await ScanWorkflowDialog.show(context, initialCameraId: _selectedCamera);
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _saveRoi() async {
    final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
    final slotCodes = List<String>.from(activeCam['slotCodes'] as List);
    final roiNotifier = ref.read(cameraRoiProvider(_selectedCamera).notifier);
    await roiNotifier.save('San Pablo', slotCodes: slotCodes);

    await SqliteService.instance.logActivity(
      type: 'ROI_CALIBRATION',
      description:
          'Detached tray ROI boundaries saved for ${activeCam['name']} (${slotCodes.join(", ")}).',
      branch: 'San Pablo',
    );

    setState(() => _isRoiEditing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Detached Tray ROIs saved for Camera #$_selectedCamera.',
          ),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  Widget _buildLayerGroup({
    required BuildContext context,
    required String title,
    required int leftCamId,
    required String leftCamLabel,
    required String leftCamSlots,
    required int rightCamId,
    required String rightCamLabel,
    required String rightCamSlots,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: context.surfaceElevatedColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.borderColor.withValues(alpha: 0.7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: context.textSecondaryColor,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildCameraCard(
                    context: context,
                    camId: leftCamId,
                    label: leftCamLabel,
                    subLabel: leftCamSlots,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCameraCard(
                    context: context,
                    camId: rightCamId,
                    label: rightCamLabel,
                    subLabel: rightCamSlots,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraCard({
    required BuildContext context,
    required int camId,
    required String label,
    required String subLabel,
  }) {
    final isSelected = _selectedCamera == camId;
    final targetNode = _getDeviceNodeForCamera(camId);
    final matchedDevice = _getMatchedHardwareDevice(camId);
    final isConnected = matchedDevice != null || File(targetNode).existsSync();

    String hardwareLabel = isConnected
        ? (matchedDevice?.isRapowCamera == true ||
                  matchedDevice?.isSunplusCamera == true ||
                  matchedDevice?.isRapooCamera == true
              ? 'Rapow Cam'
              : (matchedDevice?.isBuiltInWebcam == true
                    ? 'Built-in Cam'
                    : (matchedDevice?.name ?? 'Rapow Cam')))
        : 'No Camera';

    return InkWell(
      onTap: () => _onCameraSelected(camId),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6) : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF60A5FA) : context.borderColor,
            width: isSelected ? 1.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Status Circle Dot
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? const Color(0xFF10B981) : Colors.grey,
                boxShadow: isConnected
                    ? [const BoxShadow(color: Color(0xFF10B981), blurRadius: 4)]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.videocam_rounded,
              size: 16,
              color: isSelected
                  ? Colors.white
                  : (isConnected
                        ? context.textPrimaryColor
                        : context.textMutedColor),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            color: isSelected
                                ? Colors.white
                                : context.textPrimaryColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '$subLabel • $hardwareLabel',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: isSelected
                                ? Colors.white70
                                : (isConnected
                                      ? const Color(0xFF10B981)
                                      : context.textMutedColor),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveMisplacement = ref.watch(hasActiveMisplacementProvider);
    final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
    final activeSlotCodes = List<String>.from(activeCam['slotCodes'] as List);
    final hardwareService = ref.watch(cameraHardwareServiceProvider);
    final isStreaming = hardwareService.isStreaming;
    final currentDeviceNode = _getDeviceNodeForCamera(_selectedCamera);
    final matchedDevice = _getMatchedHardwareDevice(_selectedCamera);
    final isConnected =
        matchedDevice != null || File(currentDeviceNode).existsSync();

    // Watch ROI for selected camera
    final roi = ref.watch(cameraRoiProvider(_selectedCamera));
    final roiNotifier = ref.read(cameraRoiProvider(_selectedCamera).notifier);

    // Watch live inventory to compute actual detected bottles dynamically
    final inventoryAsync = ref.watch(liveInventoryProvider('San Pablo'));
    final allInvRecords = inventoryAsync.valueOrNull ?? [];
    final activeCamDetected = allInvRecords
        .where(
          (inv) =>
              activeSlotCodes.any((slot) => inv.perfumeCode.startsWith(slot)),
        )
        .fold<int>(0, (sum, inv) => sum + inv.detected);

    // Watch products to identify seasonal turned-off variants
    final productsAsync = ref.watch(masterProductsProvider);
    final disabledCapCodes =
        productsAsync.valueOrNull
            ?.where((p) => p.isSeasonalOff)
            .map((p) => p.perfumeCode)
            .toSet() ??
        const <String>{};

    final fpsText = isStreaming
        ? (hardwareService.currentFps > 0
              ? '${hardwareService.currentFps.toStringAsFixed(1)} FPS'
              : '30.0 FPS')
        : 'Standby';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Shelf Cameras'),
        actions: [
          // 1. Prominent START / STOP Live Stream Button
          ElevatedButton.icon(
            onPressed: _toggleLiveStream,
            icon: Icon(
              isStreaming
                  ? Icons.stop_circle_rounded
                  : Icons.play_circle_filled_rounded,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              isStreaming ? 'Stop Live View' : 'Start Live View',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isStreaming
                  ? AppColors.statusRed
                  : AppColors.statusGreen,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 10),

          // 2. Interactive Detection Box Switch Button
          ElevatedButton.icon(
            onPressed: () {
              if (_isRoiEditing) {
                _saveRoi();
              } else {
                setState(() => _isRoiEditing = true);
              }
            },
            icon: Icon(
              _isRoiEditing
                  ? Icons.check_circle_rounded
                  : Icons.crop_free_rounded,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              _isRoiEditing ? 'Save Slot Positions' : 'Adjust Slot Positions',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRoiEditing
                  ? AppColors.statusGreen
                  : AppColors.brandAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          if (_isRoiEditing) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => roiNotifier.reset(activeSlotCodes),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset Slot Grid'),
            ),
          ],
          const SizedBox(width: 10),

          // 3. Turn Scanner Zone ON / OFF (Seasonal Rotation)
          OutlinedButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
              roiNotifier.toggleEnabled();
              await roiNotifier.save('San Pablo');
              await SqliteService.instance.logActivity(
                type: 'SCANNER_STATUS',
                description:
                    '${activeCam['name']} scanner zone ${roi.isEnabled ? "paused" : "resumed"} (seasonal rotation).',
                branch: 'San Pablo',
              );
              if (mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      roi.isEnabled
                          ? '${activeCam['name']} scanner is PAUSED for seasonal rotation.'
                          : '${activeCam['name']} scanner is ACTIVE and monitoring stock.',
                    ),
                    backgroundColor: roi.isEnabled
                        ? AppColors.statusOrange
                        : AppColors.statusGreen,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: Icon(
              roi.isEnabled
                  ? Icons.wb_sunny_outlined
                  : Icons.check_circle_outline_rounded,
              size: 18,
              color: roi.isEnabled
                  ? AppColors.statusOrange
                  : AppColors.statusGreen,
            ),
            label: Text(
              roi.isEnabled ? 'Pause Shelf Zone' : 'Resume Shelf Zone',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: roi.isEnabled
                    ? AppColors.statusOrange
                    : AppColors.statusGreen,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color:
                    (roi.isEnabled
                            ? AppColors.statusOrange
                            : AppColors.statusGreen)
                        .withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 4. Hardware Assignment Settings Dialog
          OutlinedButton.icon(
            onPressed: () => CameraAssignmentDialog.show(context),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Camera Settings'),
          ),
          const SizedBox(width: 10),

          // 5. Resolution / Quality Mode Selector
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.borderColor),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CameraQualityMode>(
                value: hardwareService.currentQualityMode,
                dropdownColor: context.surfaceElevatedColor,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
                icon: const Icon(
                  Icons.hd_rounded,
                  color: AppColors.brandAccent,
                  size: 18,
                ),
                items: CameraQualityMode.values.map((mode) {
                  return DropdownMenuItem(value: mode, child: Text(mode.label));
                }).toList(),
                onChanged: (newMode) async {
                  if (newMode != null) {
                    await hardwareService.setQualityMode(newMode);
                    if (mounted) setState(() {});
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Camera Selector Bar (Grouped by Top Shelf, Middle Shelf, Bottom Shelf with Connection Indicators)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  _buildLayerGroup(
                    context: context,
                    title: 'TOP SHELF (MEN\'S)',
                    leftCamId: 1,
                    leftCamLabel: 'Left Side',
                    leftCamSlots: '5 Scents (Slots AA–AE)',
                    rightCamId: 2,
                    rightCamLabel: 'Right Side',
                    rightCamSlots: '5 Scents (Slots AF–AK)',
                  ),
                  const SizedBox(width: 10),
                  _buildLayerGroup(
                    context: context,
                    title: 'MIDDLE SHELF (MIXED)',
                    leftCamId: 3,
                    leftCamLabel: 'Left Side',
                    leftCamSlots: '5 Scents (Slots BA–BE)',
                    rightCamId: 4,
                    rightCamLabel: 'Right Side',
                    rightCamSlots: '5 Scents (Slots BF–BK)',
                  ),
                  const SizedBox(width: 10),
                  _buildLayerGroup(
                    context: context,
                    title: 'BOTTOM SHELF (WOMEN\'S)',
                    leftCamId: 5,
                    leftCamLabel: 'Left Side',
                    leftCamSlots: '5 Scents (Slots CA–CE)',
                    rightCamId: 6,
                    rightCamLabel: 'Right Side',
                    rightCamSlots: '5 Scents (Slots CF–CK)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Main Camera Feed & Telemetry Area
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Side: Live Camera Viewport (Clean 16:9 AspectRatio with Controls Outside)
                  Expanded(
                    flex: 7,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 1. Top Control Bar (OUTSIDE the video):
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: context.surfaceColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: context.borderColor),
                          ),
                          child: Row(
                            children: [
                              // Camera Status & Device Node Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isStreaming
                                        ? AppColors.statusGreen.withValues(
                                            alpha: 0.6,
                                          )
                                        : (isConnected
                                            ? AppColors.statusGreen.withValues(
                                                alpha: 0.4,
                                              )
                                            : AppColors.statusOrange.withValues(
                                                alpha: 0.4,
                                              )),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.circle,
                                      color: isStreaming
                                          ? AppColors.statusGreen
                                          : (isConnected
                                              ? AppColors.statusGreen
                                              : AppColors.statusOrange),
                                      size: 8,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${activeCam['name']} • $currentDeviceNode • $fpsText',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Standalone Tray & Size Selector Bar (Always accessible outside video)
                              Expanded(
                                child: TraySelectorBar(
                                  slotCodes: activeSlotCodes,
                                  selectedCode: roi.selectedTrayCode,
                                  onSelectTray: (code) =>
                                      roiNotifier.selectTray(code),
                                  onResetTray: (code) => roiNotifier.resetTray(
                                    code,
                                    activeSlotCodes,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 2. Camera Viewport
                        Expanded(
                          child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isRoiEditing
                              ? AppColors.brandAccent
                              : context.borderColor,
                          width: _isRoiEditing ? 2.5 : 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 1. High-Performance Flicker-Free MJPEG Stream
                              if (isStreaming)
                                MjpegLiveViewer(
                                  stream: hardwareService.frameStream,
                                  initialFrame: hardwareService.latestFrame,
                                  fallbackFilePath:
                                      '/tmp/last_frame_$_selectedCamera.jpg',
                                  deviceNode: currentDeviceNode,
                                )
                              else if (File(
                                '/tmp/last_frame_$_selectedCamera.jpg',
                              ).existsSync())
                                Image.file(
                                  File('/tmp/last_frame_$_selectedCamera.jpg'),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                )
                              else
                                Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        isConnected
                                            ? Icons.videocam_rounded
                                            : Icons.videocam_off_rounded,
                                        size: 56,
                                        color: isConnected
                                            ? AppColors.statusGreen
                                            : Colors.white24,
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        isConnected
                                            ? '${activeCam['name']} Ready (${matchedDevice?.displayName})'
                                            : 'No Camera Detected on $currentDeviceNode',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        isConnected
                                            ? 'Tap "Start Live View" in the top bar to begin streaming.'
                                            : 'Plug in USB camera device or remap in "Assign Cameras".',
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      if (isConnected)
                                        ElevatedButton.icon(
                                          onPressed:
                                              _startLiveStreamForSelectedCamera,
                                          icon: const Icon(
                                            Icons.play_arrow_rounded,
                                          ),
                                          label: const Text('Start Live View'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.statusGreen,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                              // 2. Touch-Gesture Interactive ROI Overlay (Detached Individual Tray Boxes)
                              Positioned.fill(
                                child: RoiEditorOverlay(
                                  roi: roi.copyWith(
                                    disabledCapCodes: disabledCapCodes,
                                  ),
                                  cameraName: activeCam['name'] as String,
                                  slotCodes: activeSlotCodes,
                                  isInteractive: _isRoiEditing,
                                  onSelectTray: (code) {
                                    roiNotifier.selectTray(code);
                                  },
                                  onMoveTray: (code, deltaNorm) {
                                    roiNotifier.moveTray(
                                      code,
                                      deltaNorm.dx,
                                      deltaNorm.dy,
                                      activeSlotCodes,
                                    );
                                  },
                                  onMove: (deltaNorm) {
                                    roiNotifier.move(
                                      deltaNorm.dx,
                                      deltaNorm.dy,
                                      activeSlotCodes,
                                    );
                                  },
                                  onResizeTrayCorner:
                                      (
                                        code,
                                        isTop,
                                        isLeft,
                                        newNormX,
                                        newNormY,
                                      ) {
                                        roiNotifier.resizeTrayCorner(
                                          code: code,
                                          isTop: isTop,
                                          isLeft: isLeft,
                                          newNormX: newNormX,
                                          newNormY: newNormY,
                                          slotCodes: activeSlotCodes,
                                        );
                                      },
                                  onResizeCorner:
                                      (isTop, isLeft, newNormX, newNormY) {
                                        roiNotifier.resizeCorner(
                                          isTop: isTop,
                                          isLeft: isLeft,
                                          newNormX: newNormX,
                                          newNormY: newNormY,
                                          slotCodes: activeSlotCodes,
                                        );
                                      },
                                  onResizeTrayEdge: (code, edge, newNormVal) {
                                    roiNotifier.resizeTrayEdge(
                                      code: code,
                                      edge: edge,
                                      newNormValue: newNormVal,
                                      slotCodes: activeSlotCodes,
                                    );
                                  },
                                  onResizeEdge: (edge, newNormVal) {
                                    roiNotifier.resizeEdge(
                                      edge: edge,
                                      newNormValue: newNormVal,
                                      slotCodes: activeSlotCodes,
                                    );
                                  },
                                  onScale: (scaleFactor, focalPoint) {
                                    roiNotifier.scale(
                                      scaleFactor,
                                      focalPointNorm: focalPoint,
                                      slotCodes: activeSlotCodes,
                                    );
                                  },
                                  onResetTray: (code) => roiNotifier.resetTray(
                                    code,
                                    activeSlotCodes,
                                  ),
                                  onReset: () =>
                                      roiNotifier.reset(activeSlotCodes),
                                  onInteractionEnd: () => roiNotifier.save(
                                    'San Pablo',
                                    slotCodes: activeSlotCodes,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                    // 3. Bottom Calibration & Gesture Status Bar (OUTSIDE the video):
                    if (_isRoiEditing) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: context.surfaceColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.brandAccent.withValues(
                              alpha: 0.4,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.touch_app_rounded,
                              color: AppColors.brandAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                roi.selectedTrayCode != null
                                    ? (roi.selectedTrayCode!.endsWith('1')
                                        ? 'Slot ${roi.selectedTrayCode} (100ML) Selected: Drag any of the 8 blue handles to align independently'
                                        : (roi.selectedTrayCode!.endsWith('2')
                                            ? 'Slot ${roi.selectedTrayCode} (50ML) Selected: Drag any of the 8 blue handles to align independently'
                                            : 'Tray ${roi.selectedTrayCode} (Both Sizes) Selected: Drag handles or pan body to reposition whole tray'))
                                    : 'Detached Calibration: Tap any 100ML or 50ML slot directly in video to align • 8 touch handles per slot',
                                style: TextStyle(
                                  color: context.textPrimaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
                  const SizedBox(width: 20),

                  // Right Side: Camera Hardware Telemetry & ROI Calibration Panel
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        // Card 1: Quick Actions
                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Tooltip(
                                  message: hasActiveMisplacement
                                      ? '⚠️ Resolve shelf misplacements before running a scan.'
                                      : 'Run scan workflow for camera',
                                  child: ElevatedButton.icon(
                                    onPressed: (_isScanning || hasActiveMisplacement) ? null : _triggerScan,
                                    icon: Icon(
                                      hasActiveMisplacement
                                          ? Icons.lock_clock_rounded
                                          : Icons.radar_rounded,
                                      size: 22,
                                    ),
                                    label: Text(
                                      hasActiveMisplacement
                                          ? 'SCAN LOCKED (FIX MISPLACED)'
                                          : 'SCAN ${activeCam['name'].toString().toUpperCase()}',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: hasActiveMisplacement
                                          ? Colors.grey.shade600
                                          : null,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: hasActiveMisplacement
                                          ? Colors.grey.shade600
                                          : null,
                                      disabledForegroundColor: hasActiveMisplacement
                                          ? Colors.white70
                                          : null,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          if (_isRoiEditing) {
                                            _saveRoi();
                                          } else {
                                            setState(
                                              () => _isRoiEditing = true,
                                            );
                                          }
                                        },
                                        icon: Icon(
                                          _isRoiEditing
                                              ? Icons.check_circle_rounded
                                              : Icons.crop_free_rounded,
                                          size: 16,
                                        ),
                                        label: Text(
                                          _isRoiEditing
                                              ? 'Done'
                                              : 'Adjust Grid',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () =>
                                            CameraAssignmentDialog.show(
                                              context,
                                            ),
                                        icon: const Icon(
                                          Icons.videocam_rounded,
                                          size: 16,
                                        ),
                                        label: const Text(
                                          'Cameras',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Card 2: Shelf Slot Details & Fragrances
                        Expanded(
                          child: Card(
                            color: context.surfaceColor,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: ListView(
                                children: [
                                  Text(
                                    '${activeCam['name']} - Shelf & Stock Info',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  Divider(
                                    height: 14,
                                    color: context.borderColor,
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Shelf Level',
                                    activeCam['layer'] as String,
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Assigned Fragrances',
                                    activeCam['codes'] as String,
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Tray Capacity',
                                    activeCam['capacity'] as String,
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Bottles Counted',
                                    '$activeCamDetected In Place',
                                  ),
                                  Divider(
                                    height: 14,
                                    color: context.borderColor,
                                  ),

                                  _buildTelemetryRow(
                                    context,
                                    'Bottle Tray Slots',
                                    '${activeSlotCodes.length} Tray Slots (Drag to fit bottles)',
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Slot Layout',
                                    'Front 100ML | Back 50ML',
                                  ),
                                  Divider(
                                    height: 14,
                                    color: context.borderColor,
                                  ),
                                  Text(
                                    'Fragrances on this Shelf:',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: context.textSecondaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    activeCam['assignedVariants'] as String,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.textPrimaryColor,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: context.textSecondaryColor, fontSize: 11),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: context.textPrimaryColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// A dedicated flicker-free MJPEG stream viewport widget that holds the previous frame
/// in memory so the canvas never drops to black between video frames.
class MjpegLiveViewer extends StatefulWidget {
  final Stream<Uint8List> stream;
  final Uint8List? initialFrame;
  final String? fallbackFilePath;
  final String deviceNode;

  const MjpegLiveViewer({
    super.key,
    required this.stream,
    this.initialFrame,
    this.fallbackFilePath,
    required this.deviceNode,
  });

  @override
  State<MjpegLiveViewer> createState() => _MjpegLiveViewerState();
}

class _MjpegLiveViewerState extends State<MjpegLiveViewer> {
  Uint8List? _currentFrame;
  Uint8List? _pendingFrame;
  bool _isFrameScheduled = false;
  StreamSubscription<Uint8List>? _subscription;
  DateTime? _lastFrameReceivedTime;
  DateTime _connectionStartTime = DateTime.now();
  Timer? _watchdogTimer;
  bool _isStalled = false;

  @override
  void initState() {
    super.initState();
    _connectionStartTime = DateTime.now();
    _subscribe();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        final now = DateTime.now();
        final frameStalled =
            _lastFrameReceivedTime != null &&
            now.difference(_lastFrameReceivedTime!).inSeconds >= 4;
        final connectStalled =
            _currentFrame == null &&
            now.difference(_connectionStartTime).inSeconds >= 4;

        if (frameStalled || connectStalled) {
          if (!_isStalled) {
            setState(() => _isStalled = true);
          }
        } else if (_isStalled &&
            _lastFrameReceivedTime != null &&
            now.difference(_lastFrameReceivedTime!).inSeconds < 4) {
          setState(() => _isStalled = false);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant MjpegLiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream ||
        oldWidget.deviceNode != widget.deviceNode) {
      _subscription?.cancel();
      setState(() {
        _currentFrame = null;
        _pendingFrame = null;
        _isFrameScheduled = false;
        _lastFrameReceivedTime = null;
        _connectionStartTime = DateTime.now();
        _isStalled = false;
      });
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.stream.listen((frameBytes) {
      if (!mounted || frameBytes.isEmpty) return;
      _lastFrameReceivedTime = DateTime.now();
      if (_isStalled) {
        setState(() => _isStalled = false);
      }

      _pendingFrame = frameBytes;
      if (!_isFrameScheduled) {
        _isFrameScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _isFrameScheduled = false;
          if (_pendingFrame != null) {
            setState(() {
              _currentFrame = _pendingFrame;
            });
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            _currentFrame!,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox.shrink();
            },
          ),
          if (_isStalled)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade900.withAlpha(220),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Video signal stalled on ${widget.deviceNode}. Please re-plug this camera USB cable.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    if (widget.fallbackFilePath != null &&
        File(widget.fallbackFilePath!).existsSync()) {
      return Image.file(
        File(widget.fallbackFilePath!),
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    }

    if (_isStalled) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF181B20),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.amber.shade700.withAlpha(160)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 48,
                color: AppColors.brandGold,
              ),
              const SizedBox(height: 12),
              Text(
                'Video Signal Stalled on ${widget.deviceNode}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Camera hardware is not transmitting video frames.\nPlease unplug and re-plug this camera\'s USB cable.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _connectionStartTime = DateTime.now();
                    _isStalled = false;
                  });
                  CameraHardwareService.instance.restartLiveStream();
                },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry Connection'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandAccent,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.brandAccent),
          const SizedBox(height: 14),
          Text(
            'Connecting to Stream on ${widget.deviceNode}...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
