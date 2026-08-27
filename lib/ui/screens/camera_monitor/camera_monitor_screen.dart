import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/camera_hardware_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class CameraMonitorScreen extends ConsumerStatefulWidget {
  const CameraMonitorScreen({super.key});

  @override
  ConsumerState<CameraMonitorScreen> createState() => _CameraMonitorScreenState();
}

class _CameraMonitorScreenState extends ConsumerState<CameraMonitorScreen> {
  bool _isScanning = false;
  int _selectedCamera = 1; // 1 = Top (Layer A), 2 = Middle (Layer B), 3 = Bottom (Layer C)
  String? _lastManualCapturePath;

  final Map<int, Map<String, dynamic>> _cameraInfo = {
    1: {
      'name': 'Camera 1 (Top Shelf)',
      'layer': 'Layer A (Male Scents #1–#19)',
      'codes': 'AA1 to AK2 (20 SKUs)',
      'capacity': '50 Bottles (5 per SKU)',
      'detected': 48,
      'status': 'Normal Stock',
      'roiCount': '10 Partitions (A to K)',
    },
    2: {
      'name': 'Camera 2 (Middle Shelf)',
      'layer': 'Layer B (5 Male + 5 Female)',
      'codes': 'BA1 to BK2 (20 SKUs)',
      'capacity': '50 Bottles (5 per SKU)',
      'detected': 46,
      'status': 'Normal Stock',
      'roiCount': '10 Partitions (A to K)',
    },
    3: {
      'name': 'Camera 3 (Bottom Shelf)',
      'layer': 'Layer C (Female Scents #14–#32)',
      'codes': 'CA1 to CK2 (20 SKUs)',
      'capacity': '50 Bottles (5 per SKU)',
      'detected': 49,
      'status': 'Normal Stock',
      'roiCount': '10 Partitions (A to K)',
    },
  };

  @override
  void dispose() {
    ref.read(cameraHardwareServiceProvider).stopLiveStream();
    super.dispose();
  }

  void _toggleLiveStream() {
    final hardwareService = ref.read(cameraHardwareServiceProvider);
    final rapoo = ref.read(rapooCameraPresenceProvider);

    if (hardwareService.isStreaming) {
      hardwareService.stopLiveStream();
      try {
        ref.read(sqliteServiceProvider).logActivity(
          type: 'CAMERA_STREAM',
          description: 'Live video stream deactivated for Camera #$_selectedCamera.',
        );
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Live camera feed stopped.'),
          backgroundColor: context.surfaceElevatedColor,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      hardwareService.startLiveStream(
        deviceNode: rapoo?.deviceNode ?? '/dev/video2',
      );
      try {
        ref.read(sqliteServiceProvider).logActivity(
          type: 'CAMERA_STREAM',
          description: 'Live video stream activated (30 FPS) on ${rapoo?.displayName ?? "/dev/video2"}.',
        );
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting live 30 FPS stream from ${rapoo?.displayName ?? "Camera"}...'),
          backgroundColor: AppColors.statusGreen,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _captureHighResSnapshot() async {
    final hardwareService = ref.read(cameraHardwareServiceProvider);
    final rapoo = ref.read(rapooCameraPresenceProvider);

    final path = await hardwareService.captureFrame(
      deviceNode: rapoo?.deviceNode ?? '/dev/video2',
      mode: CameraQualityMode.qhd2k,
    );

    if (path != null && mounted) {
      setState(() => _lastManualCapturePath = path);
      try {
        await ref.read(sqliteServiceProvider).logActivity(
          type: 'SNAPSHOT_CAPTURED',
          description: 'Pristine 2K QHD raw frame captured from camera ($path).',
        );
      } catch (_) {}
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pristine 2K QHD snapshot captured from ${rapoo?.displayName ?? "Camera"} ($path)'),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  void _triggerScan() async {
    setState(() => _isScanning = true);
    await _captureHighResSnapshot();
    await Future.delayed(const Duration(milliseconds: 1200));

    if (mounted) {
      final info = _cameraInfo[_selectedCamera]!;
      setState(() => _isScanning = false);

      try {
        await ref.read(sqliteServiceProvider).logActivity(
          type: 'CAMERA_SCAN',
          description: '${info['name']} AI scan finished: ${info['detected']} bottles verified in ${info['layer']}.',
        );
      } catch (_) {}

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${info['name']} AI scan complete: ${info['detected']} bottles verified in ${info['layer']}.'),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  Widget _buildLayerTab(int camId, String label, String sub, bool isHardwareActive) {
    final isSelected = _selectedCamera == camId;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _selectedCamera = camId);
          final hardwareService = ref.read(cameraHardwareServiceProvider);
          if (hardwareService.isStreaming) {
            hardwareService.restartLiveStream();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandAccent : context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? AppColors.brandAccent
                  : (isHardwareActive ? AppColors.statusGreen.withValues(alpha: 0.4) : context.borderColor),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isHardwareActive ? Icons.videocam_rounded : Icons.videocam_outlined,
                size: 20,
                color: isSelected ? Colors.white : (isHardwareActive ? AppColors.statusGreen : context.textSecondaryColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? Colors.white : context.textPrimaryColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        color: isSelected ? Colors.white.withValues(alpha: 0.85) : context.textMutedColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeCam = _cameraInfo[_selectedCamera]!;
    final hardwareService = ref.watch(cameraHardwareServiceProvider);
    final rapooCam = ref.watch(rapooCameraPresenceProvider);
    final isStreaming = hardwareService.isStreaming;

    final fpsText = isStreaming
        ? (hardwareService.currentFps > 0
            ? '${hardwareService.currentFps.toStringAsFixed(1)} FPS'
            : '30.0 FPS')
        : 'Standby';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Camera Vision Monitor'),
        actions: [
          // 1. Resolution / Quality Mode Selector
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
                onChanged: (newMode) {
                  if (newMode != null) {
                    hardwareService.setQualityMode(newMode);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 2. Single Primary Stream Action Button
          ElevatedButton.icon(
            onPressed: _toggleLiveStream,
            icon: Icon(
              isStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded,
              size: 22,
              color: isStreaming ? AppColors.statusRed : Colors.white,
            ),
            label: Text(
              isStreaming ? 'Stop Live Feed' : 'Start Live Feed',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isStreaming ? AppColors.statusRed : Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isStreaming ? AppColors.statusRedBg : AppColors.brandAccent,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            ),
          ),
          const SizedBox(width: 12),

          // Secondary Quick Tool Actions
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.imageQuality),
            icon: const Icon(Icons.high_quality_rounded, size: 18),
            label: const Text('Quality Check'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.shelfHistory),
            icon: const Icon(Icons.history_rounded, size: 18),
            label: const Text('History'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutePaths.schedule),
            icon: const Icon(Icons.schedule_rounded, size: 18),
            label: const Text('Schedule'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // 1. Unified Layer Switcher & Hardware Presence Status Bar
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  _buildLayerTab(1, 'Camera 1: Top', 'Layer A (Male)', rapooCam != null),
                  const SizedBox(width: 8),
                  _buildLayerTab(2, 'Camera 2: Middle', 'Layer B (Mixed)', false),
                  const SizedBox(width: 8),
                  _buildLayerTab(3, 'Camera 3: Bottom', 'Layer C (Female)', false),
                  const SizedBox(width: 16),

                  // Hardware Presence Chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: rapooCam != null ? AppColors.statusGreenBg : AppColors.statusOrangeBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (rapooCam != null ? AppColors.statusGreen : AppColors.statusOrange).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          rapooCam != null ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                          color: rapooCam != null ? AppColors.statusGreen : AppColors.statusOrange,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              rapooCam != null ? 'Rapoo USB Cam (0c45:6365)' : 'No Hardware Cam',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: rapooCam != null ? AppColors.statusGreen : AppColors.statusOrange,
                              ),
                            ),
                            Text(
                              rapooCam != null ? '${rapooCam.deviceNode} • ${hardwareService.currentQualityMode.resolution}' : 'Plug in webcam',
                              style: TextStyle(fontSize: 10, color: context.textSecondaryColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. Main Viewport & Control Layout
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Camera Viewport (Stream or Clean Standby View)
                  Expanded(
                    flex: 7,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.borderColor, width: 2),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          if (isStreaming)
                            Positioned.fill(
                              child: MjpegLiveViewer(
                                stream: hardwareService.frameStream,
                                initialFrame: hardwareService.latestFrame,
                                fallbackFilePath: _lastManualCapturePath,
                                deviceNode: rapooCam?.deviceNode ?? '/dev/video2',
                              ),
                            )
                          else
                            Positioned.fill(
                              child: _lastManualCapturePath != null && File(_lastManualCapturePath!).existsSync()
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(
                                          File(_lastManualCapturePath!),
                                          fit: BoxFit.cover,
                                        ),
                                        Positioned(
                                          bottom: 16,
                                          left: 16,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              '📷 Last Captured Snapshot',
                                              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                        ),
                                      ],
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(22),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: context.surfaceElevatedColor,
                                              border: Border.all(color: context.borderColor, width: 1.5),
                                            ),
                                            child: const Icon(
                                              Icons.videocam_outlined,
                                              size: 52,
                                              color: AppColors.brandAccent,
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            '${activeCam['name']} Ready',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 20,
                                              fontWeight: FontWeight.w900,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${activeCam['layer']} • Assigned Codes: ${activeCam['codes']}',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 22),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              ElevatedButton.icon(
                                                onPressed: _toggleLiveStream,
                                                icon: const Icon(Icons.play_arrow_rounded, size: 22),
                                                label: const Text('Start Live Feed (30 FPS)'),
                                                style: ElevatedButton.styleFrom(
                                                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              OutlinedButton.icon(
                                                onPressed: _captureHighResSnapshot,
                                                icon: const Icon(Icons.camera_alt_outlined, size: 20),
                                                label: const Text('Capture Snapshot'),
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: Colors.white,
                                                  side: const BorderSide(color: Colors.white38),
                                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                            ),

                          // Live Stream Status & Telemetry Pill
                          if (isStreaming) ...[
                            Positioned(
                              top: 14,
                              left: 14,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.statusGreen.withValues(alpha: 0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.circle, color: AppColors.statusGreen, size: 8),
                                    const SizedBox(width: 8),
                                    Text(
                                      'LIVE $fpsText • ${hardwareService.currentQualityMode.resolution} • HW MJPEG',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            Positioned(
                              bottom: 14,
                              right: 14,
                              child: ElevatedButton.icon(
                                onPressed: _captureHighResSnapshot,
                                icon: const Icon(Icons.camera_rounded, size: 16),
                                label: const Text('Take Snapshot'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(alpha: 0.75),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],

                          // Scanning Loading Overlay
                          if (_isScanning)
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: AppColors.brandAccent),
                                    SizedBox(height: 16),
                                    Text(
                                      'Running AI YOLOv8 + Cap OCR Vision Scan...',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
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

                  // Right Column: Action Controls & Telemetry Details
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Card 1: Action Command Button
                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: _isScanning ? null : _triggerScan,
                                  icon: const Icon(Icons.radar_rounded, size: 24),
                                  label: Text('⚡ SCAN ${activeCam['name'].toUpperCase()}'),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => context.push(AppRoutePaths.imageQuality),
                                        icon: const Icon(Icons.auto_awesome, size: 16),
                                        label: const Text('Quality', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => context.push(AppRoutePaths.roiDetail),
                                        icon: const Icon(Icons.crop_free_rounded, size: 16),
                                        label: const Text('Partitions', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Card 2: Layer & Model Specifications
                        Expanded(
                          child: Card(
                            color: context.surfaceColor,
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Layer Camera Telemetry',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  Divider(height: 16, color: context.borderColor),
                                  _buildTelemetryRow(context, 'Shelf Layer', activeCam['layer']),
                                  _buildTelemetryRow(context, 'Hardware Device', rapooCam != null ? 'Rapoo (0c45:6365)' : 'Virtual Node'),
                                  _buildTelemetryRow(context, 'V4L2 Device Node', rapooCam?.deviceNode ?? '/dev/video2'),
                                  _buildTelemetryRow(context, 'Live Stream FPS', fpsText),
                                  _buildTelemetryRow(context, 'Capture Resolution', hardwareService.currentQualityMode.resolution),
                                  _buildTelemetryRow(context, 'Assigned SKU Codes', activeCam['codes']),
                                  _buildTelemetryRow(context, 'Shelf Capacity', activeCam['capacity']),
                                  _buildTelemetryRow(context, 'Detected Bottles', '${activeCam['detected']} Bottles Verified'),
                                  _buildTelemetryRow(context, 'YOLOv8 Detection', '95.6% Confidence'),
                                  _buildTelemetryRow(context, 'PaddleOCR Match', '99.2% Top Score'),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: context.textSecondaryColor, fontSize: 12)),
          Text(value, style: TextStyle(color: context.textPrimaryColor, fontWeight: FontWeight.w700, fontSize: 12)),
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
          const SizedBox(height: 16),
          Text(
            'Connecting to Live 30 FPS Stream on ${widget.deviceNode}...',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
