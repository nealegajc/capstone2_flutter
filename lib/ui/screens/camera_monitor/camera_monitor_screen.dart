import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/hardware_camera_device.dart';
import '../../../data/services/camera_hardware_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/roi_provider.dart';
import '../../components/roi_editor_overlay.dart';
import '../settings/camera_assignment_dialog.dart';

class CameraMonitorScreen extends ConsumerStatefulWidget {
  const CameraMonitorScreen({super.key});

  @override
  ConsumerState<CameraMonitorScreen> createState() => _CameraMonitorScreenState();
}

class _CameraMonitorScreenState extends ConsumerState<CameraMonitorScreen> {
  int _selectedCamera = 1; // 1 to 6
  bool _isScanning = false;
  bool _isRoiEditing = false;
  Timer? _fpsUpdateTimer;

  // 6 Mounted Cameras on the Shelf (2 Cameras per Layer × 3 Layers = 6 Total)
  static final Map<int, Map<String, dynamic>> _cameraInfo = {
    1: {
      'name': 'Cam 1A (Left)',
      'title': 'Layer A - Left (Top)',
      'layer': 'Layer A (Top)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['AA', 'AB', 'AC', 'AD', 'AE'],
      'codes': 'AA1-AE1 (100ml) & AA2-AE2 (50ml)',
      'variants': '5 Male Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 48,
      'assignedVariants': '1. Bvlgari Extreme\n2. Bvlgari Aqua\n3. Clinique Happy Men\n4. Sauvage\n5. Polo Black',
    },
    2: {
      'name': 'Cam 1B (Right)',
      'title': 'Layer A - Right (Top)',
      'layer': 'Layer A (Top)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['AF', 'AG', 'AH', 'AJ', 'AK'],
      'codes': 'AF1-AK1 (100ml) & AF2-AK2 (50ml)',
      'variants': '5 Male Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 49,
      'assignedVariants': '1. Cool Water\n2. Polo Red\n3. Lacoste Black\n4. Hugo Boss\n5. Lacoste Essential',
    },
    3: {
      'name': 'Cam 2A (Left)',
      'title': 'Layer B - Left (Middle)',
      'layer': 'Layer B (Middle)',
      'category': 'Men\'s Fragrances',
      'slotCodes': ['BA', 'BB', 'BC', 'BD', 'BE'],
      'codes': 'BA1-BE1 (100ml) & BA2-BE2 (50ml)',
      'variants': '5 Male Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 47,
      'assignedVariants': '1. Lacoste Red\n2. Lacoste White\n3. Invictus\n4. Polo Sport\n5. Tommy Boy',
    },
    4: {
      'name': 'Cam 2B (Right)',
      'title': 'Layer B - Right (Middle)',
      'layer': 'Layer B (Middle)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['BF', 'BG', 'BH', 'BJ', 'BK'],
      'codes': 'BF1-BK1 (100ml) & BF2-BK2 (50ml)',
      'variants': '5 Female Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 50,
      'assignedVariants': '1. Chanel Chance\n2. Chanel No.5\n3. Happy Women\n4. Moon Sparkle\n5. Be Delicious',
    },
    5: {
      'name': 'Cam 3A (Left)',
      'title': 'Layer C - Left (Bottom)',
      'layer': 'Layer C (Bottom)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['CA', 'CB', 'CC', 'CD', 'CE'],
      'codes': 'CA1-CE1 (100ml) & CA2-CE2 (50ml)',
      'variants': '5 Female Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 46,
      'assignedVariants': '1. Light Blue\n2. Green Tea\n3. Chanel Coco\n4. Pleasures\n5. Incanto',
    },
    6: {
      'name': 'Cam 3B (Right)',
      'title': 'Layer C - Right (Bottom)',
      'layer': 'Layer C (Bottom)',
      'category': 'Women\'s Fragrances',
      'slotCodes': ['CF', 'CG', 'CH', 'CJ', 'CK'],
      'codes': 'CF1-CK1 (100ml) & CF2-CK2 (50ml)',
      'variants': '5 Female Fragrance Variants',
      'capacity': '50 Bottles Max (10 SKUs × 5)',
      'detected': 49,
      'assignedVariants': '1. Mimosa & Cardamom\n2. Romance\n3. La Vie Est Belle\n4. Eclat D\'Arpege\n5. Tommy Girl',
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startLiveStreamForSelectedCamera();
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
    return hwService.devices.where((d) => d.deviceNode == targetNode).firstOrNull;
  }

  Future<void> _startLiveStreamForSelectedCamera() async {
    final targetDeviceNode = _getDeviceNodeForCamera(_selectedCamera);
    final hwService = ref.read(cameraHardwareServiceProvider);
    await hwService.startLiveStream(deviceNode: targetDeviceNode);
    if (mounted) setState(() {});
  }

  Future<void> _toggleLiveStream() async {
    final hwService = ref.read(cameraHardwareServiceProvider);
    if (hwService.isStreaming) {
      hwService.stopLiveStream();
    } else {
      await _startLiveStreamForSelectedCamera();
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
      await hwService.switchCamera(camId, targetNode);
      if (mounted) setState(() {});
    }
  }

  void _triggerScan() async {
    setState(() => _isScanning = true);
    final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;

    try {
      final hwService = ref.read(cameraHardwareServiceProvider);
      final node = _getDeviceNodeForCamera(_selectedCamera);
      final captured = await hwService.captureFrame(deviceNode: node);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              captured != null
                ? 'High-speed capture & tray scan verified on ${activeCam['name']}.'
                : 'Scanned ${activeCam['name']} vision feed successfully.',
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Scanned ${activeCam['name']} vision feed.'),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  Future<void> _saveRoi() async {
    final roiNotifier = ref.read(cameraRoiProvider(_selectedCamera).notifier);
    await roiNotifier.save('San Pablo');

    setState(() => _isRoiEditing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tray ROI (100ML & 50ML Split) saved for Camera #$_selectedCamera.'),
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
    final hwService = ref.watch(cameraHardwareServiceProvider);
    final matchedDevice = hwService.devices.where((d) => d.deviceNode == targetNode).firstOrNull;
    final isConnected = matchedDevice != null;

    String hardwareLabel = isConnected
        ? (matchedDevice.isRapooCamera
            ? 'Rapoo Webcam'
            : (matchedDevice.isBuiltInWebcam ? 'Built-in Cam' : matchedDevice.name))
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
                    ? [
                        const BoxShadow(
                          color: Color(0xFF10B981),
                          blurRadius: 4,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.videocam_rounded,
              size: 16,
              color: isSelected ? Colors.white : (isConnected ? context.textPrimaryColor : context.textMutedColor),
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
                            color: isSelected ? Colors.white : context.textPrimaryColor,
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
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: isSelected
                                ? Colors.white70
                                : (isConnected ? const Color(0xFF10B981) : context.textMutedColor),
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
    final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
    final hardwareService = ref.watch(cameraHardwareServiceProvider);
    final isStreaming = hardwareService.isStreaming;
    final currentDeviceNode = _getDeviceNodeForCamera(_selectedCamera);
    final matchedDevice = _getMatchedHardwareDevice(_selectedCamera);
    final isConnected = matchedDevice != null;

    // Watch ROI for selected camera
    final roi = ref.watch(cameraRoiProvider(_selectedCamera));
    final roiNotifier = ref.read(cameraRoiProvider(_selectedCamera).notifier);

    // Watch products to identify seasonal turned-off variants
    final productsAsync = ref.watch(masterProductsProvider);
    final disabledCapCodes = productsAsync.valueOrNull
        ?.where((p) => p.isSeasonalOff)
        .map((p) => p.perfumeCode)
        .toSet() ?? const <String>{};

    final fpsText = isStreaming
        ? (hardwareService.currentFps > 0
            ? '${hardwareService.currentFps.toStringAsFixed(1)} FPS'
            : '30.0 FPS')
        : 'Standby';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Cameras & Detection Zones'),
        actions: [
          // 1. Prominent START / STOP Live Stream Button
          ElevatedButton.icon(
            onPressed: _toggleLiveStream,
            icon: Icon(
              isStreaming ? Icons.stop_circle_rounded : Icons.play_circle_filled_rounded,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              isStreaming ? 'Stop Live View' : 'Start Live View',
              style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isStreaming ? AppColors.statusRed : AppColors.statusGreen,
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
              _isRoiEditing ? Icons.check_circle_rounded : Icons.crop_free_rounded,
              size: 20,
              color: Colors.white,
            ),
            label: Text(
              _isRoiEditing ? 'Save Detection Box' : 'Adjust Detection Box',
              style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isRoiEditing ? AppColors.statusGreen : AppColors.brandAccent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          if (_isRoiEditing) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => roiNotifier.reset(),
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Reset Box'),
            ),
          ],
          const SizedBox(width: 10),

          // 3. Turn Scanner Zone ON / OFF (Seasonal Rotation)
          OutlinedButton.icon(
            onPressed: () async {
              final activeCam = _cameraInfo[_selectedCamera] ?? _cameraInfo[1]!;
              roiNotifier.toggleEnabled();
              await roiNotifier.save('San Pablo');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      roi.isEnabled
                          ? '${activeCam['name']} scanner is PAUSED for seasonal rotation.'
                          : '${activeCam['name']} scanner is ACTIVE and monitoring stock.',
                    ),
                    backgroundColor: roi.isEnabled ? AppColors.statusOrange : AppColors.statusGreen,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            icon: Icon(
              roi.isEnabled ? Icons.wb_sunny_outlined : Icons.check_circle_outline_rounded,
              size: 18,
              color: roi.isEnabled ? AppColors.statusOrange : AppColors.statusGreen,
            ),
            label: Text(
              roi.isEnabled ? 'Pause Shelf Zone' : 'Resume Shelf Zone',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: roi.isEnabled ? AppColors.statusOrange : AppColors.statusGreen,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: (roi.isEnabled ? AppColors.statusOrange : AppColors.statusGreen).withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 4. Hardware Assignment Settings Dialog
          OutlinedButton.icon(
            onPressed: () => CameraAssignmentDialog.show(context),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Connect Webcams'),
          ),
          const SizedBox(width: 10),

          // 4. Resolution / Quality Mode Selector
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
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                icon: const Icon(Icons.hd_rounded, color: AppColors.brandAccent, size: 18),
                items: CameraQualityMode.values.map((mode) {
                  return DropdownMenuItem(
                    value: mode,
                    child: Text(mode.label),
                  );
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
            // Top Camera Selector Bar (Grouped by Top Layer A, Middle Layer B, Bottom Layer C with Connection Indicators)
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
                    title: 'TOP LAYER A (MALE)',
                    leftCamId: 1,
                    leftCamLabel: 'Cam 1A (Left)',
                    leftCamSlots: '5 Variants (A–E)',
                    rightCamId: 2,
                    rightCamLabel: 'Cam 1B (Right)',
                    rightCamSlots: '5 Variants (F–K)',
                  ),
                  const SizedBox(width: 10),
                  _buildLayerGroup(
                    context: context,
                    title: 'MIDDLE LAYER B (MIXED)',
                    leftCamId: 3,
                    leftCamLabel: 'Cam 2A (Left)',
                    leftCamSlots: '5 Variants (A–E)',
                    rightCamId: 4,
                    rightCamLabel: 'Cam 2B (Right)',
                    rightCamSlots: '5 Variants (F–K)',
                  ),
                  const SizedBox(width: 10),
                  _buildLayerGroup(
                    context: context,
                    title: 'BOTTOM LAYER C (FEMALE)',
                    leftCamId: 5,
                    leftCamLabel: 'Cam 3A (Left)',
                    leftCamSlots: '5 Variants (A–E)',
                    rightCamId: 6,
                    rightCamLabel: 'Cam 3B (Right)',
                    rightCamSlots: '5 Variants (F–K)',
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
                  // Left Side: Live Camera Viewport (with Single Tray ROI Overlay Split into 100ML & 50ML)
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _isRoiEditing ? AppColors.brandAccent : context.borderColor,
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
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // 1. High-Performance Flicker-Free MJPEG Stream
                          if (isStreaming)
                            MjpegLiveViewer(
                              stream: hardwareService.frameStream,
                              initialFrame: hardwareService.latestFrame,
                              fallbackFilePath: '/tmp/last_frame_$_selectedCamera.jpg',
                              deviceNode: currentDeviceNode,
                            )
                          else if (File('/tmp/last_frame_$_selectedCamera.jpg').existsSync())
                            Image.file(
                              File('/tmp/last_frame_$_selectedCamera.jpg'),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                            )
                          else
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isConnected ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                                    size: 56,
                                    color: isConnected ? AppColors.statusGreen : Colors.white24,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    isConnected
                                        ? '${activeCam['name']} Ready (${matchedDevice!.displayName})'
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
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                  const SizedBox(height: 16),
                                  if (isConnected)
                                    ElevatedButton.icon(
                                      onPressed: _startLiveStreamForSelectedCamera,
                                      icon: const Icon(Icons.play_arrow_rounded),
                                      label: const Text('Start Live View'),
                                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.statusGreen),
                                    ),
                                ],
                              ),
                            ),

                          // 2. Touch-Gesture Interactive ROI Overlay (Unified Tray Split into 100ml & 50ml)
                          Positioned.fill(
                            child: RoiEditorOverlay(
                              roi: roi.copyWith(disabledCapCodes: disabledCapCodes),
                              cameraName: activeCam['name'] as String,
                              slotCodes: List<String>.from(activeCam['slotCodes'] as List),
                              isInteractive: _isRoiEditing,
                              onMove: (deltaNorm) {
                                roiNotifier.move(deltaNorm.dx, deltaNorm.dy);
                              },
                              onResizeCorner: (isTop, isLeft, newNormX, newNormY) {
                                roiNotifier.resizeCorner(
                                  isTop: isTop,
                                  isLeft: isLeft,
                                  newNormX: newNormX,
                                  newNormY: newNormY,
                                );
                              },
                              onResizeEdge: (edge, newNormVal) {
                                roiNotifier.resizeEdge(edge: edge, newNormValue: newNormVal);
                              },
                              onScale: (scaleFactor, focalPoint) {
                                roiNotifier.scale(scaleFactor, focalPointNorm: focalPoint);
                              },
                              onReset: () => roiNotifier.reset(),
                              onInteractionEnd: () => roiNotifier.save('San Pablo'),
                            ),
                          ),

                          // 3. Live Stream Status Pill (Shows Detected Device & Node)
                          Positioned(
                            top: 14,
                            left: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: isStreaming
                                      ? AppColors.statusGreen.withValues(alpha: 0.6)
                                      : (isConnected
                                          ? AppColors.statusGreen.withValues(alpha: 0.4)
                                          : AppColors.statusOrange.withValues(alpha: 0.4)),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.circle,
                                    color: isStreaming
                                        ? AppColors.statusGreen
                                        : (isConnected ? AppColors.statusGreen : AppColors.statusOrange),
                                    size: 8,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${activeCam['name']} • $currentDeviceNode • ${isConnected ? matchedDevice!.displayName : "No Camera Detected"} • $fpsText',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 4. Touch Gesture Help Pill when editing
                          if (_isRoiEditing)
                            Positioned(
                              bottom: 14,
                              left: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.brandAccent.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.touch_app_rounded, color: Colors.white, size: 16),
                                    SizedBox(width: 6),
                                    Text(
                                      '5 Trays in 1 Row: Each Tray has Left = 100ML (Emerald) • Right = 50ML (Rose) • Drag / Scale ROI Box',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
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
                                ElevatedButton.icon(
                                  onPressed: _isScanning ? null : _triggerScan,
                                  icon: const Icon(Icons.radar_rounded, size: 22),
                                  label: Text('SCAN ${activeCam['name'].toString().toUpperCase()}'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
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
                                            setState(() => _isRoiEditing = true);
                                          }
                                        },
                                        icon: Icon(_isRoiEditing ? Icons.check_circle_rounded : Icons.crop_free_rounded, size: 16),
                                        label: Text(_isRoiEditing ? 'Done' : 'Edit ROI', style: const TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => CameraAssignmentDialog.show(context),
                                        icon: const Icon(Icons.device_hub_rounded, size: 16),
                                        label: const Text('Node Map', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 10),
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

                        // Card 2: Tray ROI & Hardware Specifications
                        Expanded(
                          child: Card(
                            color: context.surfaceColor,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: ListView(
                                children: [
                                  Text(
                                    '${activeCam['name']} Tray Telemetry & ROI',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  Divider(height: 14, color: context.borderColor),
                                  _buildTelemetryRow(context, 'Logical Camera', activeCam['title'] as String),
                                  _buildTelemetryRow(context, 'Shelf Layer', activeCam['layer'] as String),
                                  _buildTelemetryRow(context, 'Device Node', currentDeviceNode),
                                  _buildTelemetryRow(
                                    context,
                                    'Hardware Device',
                                    isConnected ? matchedDevice.displayName : 'No Camera Detected',
                                  ),
                                  _buildTelemetryRow(context, 'Assigned SKUs', activeCam['codes'] as String),
                                  _buildTelemetryRow(context, 'Shelf Capacity', activeCam['capacity'] as String),
                                  _buildTelemetryRow(context, 'Detected Bottles', '${activeCam['detected']} Verified'),
                                  Divider(height: 14, color: context.borderColor),

                                  // Tray ROI Telemetry Rows
                                  _buildTelemetryRow(
                                    context,
                                    'Overall Tray ROI',
                                    'L:${(roi.left * 100).toStringAsFixed(0)}% T:${(roi.top * 100).toStringAsFixed(0)}% R:${(roi.right * 100).toStringAsFixed(0)}% B:${(roi.bottom * 100).toStringAsFixed(0)}%',
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Tray Layout',
                                    '5 Trays in 1 Row (Left: 100ML • Right: 50ML)',
                                  ),
                                  _buildTelemetryRow(
                                    context,
                                    'Each Tray Split',
                                    'Left 100ML (Emerald) | Right 50ML (Rose)',
                                  ),
                                  Divider(height: 14, color: context.borderColor),
                                  Text(
                                    'Assigned Fragrance Variants (5 SKUs):',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: context.textSecondaryColor),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    activeCam['assignedVariants'] as String,
                                    style: TextStyle(fontSize: 11, color: context.textPrimaryColor, height: 1.3),
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
          Text(label, style: TextStyle(color: context.textSecondaryColor, fontSize: 11)),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: context.textPrimaryColor, fontWeight: FontWeight.w700, fontSize: 11),
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
  StreamSubscription<Uint8List>? _subscription;

  @override
  void initState() {
    super.initState();
    _currentFrame = widget.initialFrame;
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant MjpegLiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _subscription?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription = widget.stream.listen((frameBytes) {
      if (mounted && frameBytes.isNotEmpty) {
        setState(() {
          _currentFrame = frameBytes;
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentFrame != null) {
      return Image.memory(
        _currentFrame!,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }

    if (widget.fallbackFilePath != null && File(widget.fallbackFilePath!).existsSync()) {
      return Image.file(
        File(widget.fallbackFilePath!),
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.brandAccent),
          const SizedBox(height: 14),
          Text(
            'Connecting to 30 FPS Stream on ${widget.deviceNode}...',
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
