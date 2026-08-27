import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../models/hardware_camera_device.dart';

enum CameraQualityMode {
  fhd1080p('1920x1080', 30, '1080p FHD (30 FPS)'),
  qhd2k('2560x1440', 30, '2K QHD (30 FPS - Max Quality)'),
  hd720p('1280x720', 30, '720p HD (30 FPS)');

  final String resolution;
  final int framerate;
  final String label;
  const CameraQualityMode(this.resolution, this.framerate, this.label);
}

class CameraHardwareService extends ChangeNotifier {
  static CameraHardwareService? _instance;
  static CameraHardwareService get instance => _instance ??= CameraHardwareService._();

  CameraHardwareService._();

  List<HardwareCameraDevice> _devices = [];
  Timer? _pollingTimer;
  bool _isProbing = false;
  String? _lastCapturedRapooPath;

  // Live Stream Pipeline
  Process? _streamProcess;
  final StreamController<Uint8List> _frameStreamController =
      StreamController<Uint8List>.broadcast();
  Uint8List? _latestFrame;
  bool _isStreaming = false;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime? _fpsStartTime;
  CameraQualityMode _currentQualityMode = CameraQualityMode.fhd1080p;

  List<HardwareCameraDevice> get devices => _devices;
  HardwareCameraDevice? get rapooCamera =>
      _devices.where((d) => d.isRapooCamera).firstOrNull;
  String? get lastCapturedRapooPath => _lastCapturedRapooPath;
  Stream<Uint8List> get frameStream => _frameStreamController.stream;
  Uint8List? get latestFrame => _latestFrame;
  bool get isStreaming => _isStreaming;
  double get currentFps => _currentFps;
  CameraQualityMode get currentQualityMode => _currentQualityMode;

  /// Initializes periodic hardware presence polling (every 3 seconds)
  void startMonitoring({Duration interval = const Duration(seconds: 3)}) {
    probeHardwareDevices();
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(interval, (_) => probeHardwareDevices());
  }

  void stopMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    stopLiveStream();
  }

  /// Sets quality mode (e.g. 2K QHD vs 1080p FHD) and restarts live stream if active
  void setQualityMode(CameraQualityMode mode) {
    if (_currentQualityMode != mode) {
      _currentQualityMode = mode;
      notifyListeners();
      if (_isStreaming) {
        restartLiveStream();
      }
    }
  }

  /// Starts real-time hardware MJPEG stream via zero-copy pipeline with robust byte frame parsing
  Future<void> startLiveStream({String? deviceNode}) async {
    if (_isStreaming) return;

    final targetDevice = deviceNode ??
        rapooCamera?.deviceNode ??
        (_devices.isNotEmpty ? _devices.first.deviceNode : '/dev/video2');

    try {
      _streamProcess = await Process.start(
        'ffmpeg',
        [
          '-y',
          '-f', 'v4l2',
          '-input_format', 'mjpeg',
          '-video_size', _currentQualityMode.resolution,
          '-framerate', '${_currentQualityMode.framerate}',
          '-i', targetDevice,
          '-c:v', 'copy', // Zero CPU copy from hardware MJPEG
          '-f', 'image2pipe',
          '-',
        ],
      );

      _isStreaming = true;
      _frameCount = 0;
      _fpsStartTime = DateTime.now();
      notifyListeners();

      final buffer = <int>[];

      _streamProcess!.stdout.listen(
        (chunk) {
          buffer.addAll(chunk);

          // Extract all complete JPEG frames in the buffer
          while (true) {
            // Find Start of Image (SOI: 0xFF, 0xD8)
            int soi = -1;
            for (int i = 0; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD8) {
                soi = i;
                break;
              }
            }

            if (soi == -1) {
              // Discard garbage if no SOI
              if (buffer.length > 1) {
                buffer.removeRange(0, buffer.length - 1);
              }
              break;
            }

            // Drop any corrupted prefix before SOI
            if (soi > 0) {
              buffer.removeRange(0, soi);
            }

            // Find End of Image (EOI: 0xFF, 0xD9)
            int eoi = -1;
            for (int i = 2; i < buffer.length - 1; i++) {
              if (buffer[i] == 0xFF && buffer[i + 1] == 0xD9) {
                eoi = i + 2;
                break;
              }
            }

            if (eoi == -1) {
              // Frame is incomplete; wait for more chunks
              break;
            }

            // Complete, pristine JPEG frame
            final frameBytes = Uint8List.fromList(buffer.sublist(0, eoi));
            buffer.removeRange(0, eoi);

            // Sanity check: valid MJPEG frame must be at least 1KB
            if (frameBytes.length > 1000) {
              _latestFrame = frameBytes;
              if (!_frameStreamController.isClosed) {
                _frameStreamController.add(frameBytes);
              }

              _frameCount++;
              if (_fpsStartTime != null) {
                final elapsedSec = DateTime.now().difference(_fpsStartTime!).inMilliseconds / 1000.0;
                if (elapsedSec >= 1.0) {
                  _currentFps = _frameCount / elapsedSec;
                  _frameCount = 0;
                  _fpsStartTime = DateTime.now();
                  notifyListeners();
                }
              }
            }
          }
        },
        onError: (err) {
          debugPrint('[CameraHardwareService] Live stream error: $err');
          _isStreaming = false;
          notifyListeners();
        },
        onDone: () {
          _isStreaming = false;
          notifyListeners();
        },
        cancelOnError: true,
      );

      _streamProcess!.stderr.drain();
    } catch (e) {
      debugPrint('[CameraHardwareService] Failed to start live stream: $e');
      _isStreaming = false;
      notifyListeners();
    }
  }

  void stopLiveStream() {
    try {
      _streamProcess?.kill(ProcessSignal.sigterm);
      _streamProcess = null;
    } catch (_) {}
    _isStreaming = false;
    _currentFps = 0.0;
    notifyListeners();
  }

  void restartLiveStream() async {
    stopLiveStream();
    await Future.delayed(const Duration(milliseconds: 300));
    await startLiveStream();
  }

  /// Scans Linux /sys/class/video4linux and udev properties for connected cameras
  Future<List<HardwareCameraDevice>> probeHardwareDevices() async {
    if (_isProbing) return _devices;
    _isProbing = true;

    final discovered = <HardwareCameraDevice>[];

    try {
      final v4lDir = Directory('/sys/class/video4linux');
      if (await v4lDir.exists()) {
        final entries = await v4lDir.list().toList();

        for (final entity in entries) {
          if (entity is Directory) {
            final nodeName = entity.path.split('/').last;
            final devicePath = '/dev/$nodeName';

            final indexFile = File('${entity.path}/index');
            if (await indexFile.exists()) {
              final idxStr = (await indexFile.readAsString()).trim();
              if (idxStr != '0') {
                continue;
              }
            }

            String name = 'USB Video Device';
            final nameFile = File('${entity.path}/name');
            if (await nameFile.exists()) {
              name = (await nameFile.readAsString()).trim();
            }

            String vendorId = '';
            String modelId = '';
            String busInfo = '';

            try {
              final result = await Process.run('udevadm', ['info', '-q', 'property', '-n', devicePath]);
              if (result.exitCode == 0) {
                final output = result.stdout.toString();
                for (final line in output.split('\n')) {
                  if (line.startsWith('ID_VENDOR_ID=')) {
                    vendorId = line.replaceFirst('ID_VENDOR_ID=', '').trim();
                  } else if (line.startsWith('ID_MODEL_ID=')) {
                    modelId = line.replaceFirst('ID_MODEL_ID=', '').trim();
                  } else if (line.startsWith('ID_MODEL=')) {
                    final m = line.replaceFirst('ID_MODEL=', '').trim();
                    if (m.isNotEmpty && name == 'USB Video Device') {
                      name = m.replaceAll('_', ' ');
                    }
                  }
                }
              }
            } catch (_) {}

            try {
              final lsusbResult = await Process.run('lsusb', []);
              if (lsusbResult.exitCode == 0) {
                final lsusbLines = lsusbResult.stdout.toString().split('\n');
                for (final line in lsusbLines) {
                  if (line.contains('$vendorId:$modelId') || (vendorId == '0c45' && line.contains('rapoo'))) {
                    final match = RegExp(r'(Bus\s+\d+\s+Device\s+\d+)').firstMatch(line);
                    if (match != null) {
                      busInfo = match.group(1) ?? '';
                    }
                  }
                }
              }
            } catch (_) {}

            String layer = 'Layer A (Top)';
            if (vendorId.toLowerCase() == '0c45' && modelId.toLowerCase() == '6365') {
              layer = 'Layer A (Top - Microdia Rapoo)';
            }

            discovered.add(
              HardwareCameraDevice(
                deviceNode: devicePath,
                name: name,
                vendorId: vendorId,
                modelId: modelId,
                busInfo: busInfo.isNotEmpty ? busInfo : 'USB V4L2',
                sysfsPath: entity.path,
                isConnected: true,
                assignedLayer: layer,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[CameraHardwareService] Error probing devices: $e');
    } finally {
      _isProbing = false;
    }

    _devices = discovered;
    notifyListeners();
    return _devices;
  }

  /// Captures a pristine high-resolution snapshot (2K QHD or 1080p FHD)
  Future<String?> captureFrame({String? deviceNode, CameraQualityMode? mode}) async {
    final quality = mode ?? _currentQualityMode;
    final targetDevice = deviceNode ??
        rapooCamera?.deviceNode ??
        (_devices.isNotEmpty ? _devices.first.deviceNode : '/dev/video2');
    final outputPath = '/tmp/smart_shelf_${targetDevice.replaceAll('/', '_')}.jpg';

    final wasStreaming = _isStreaming;
    if (wasStreaming) {
      stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 200));
    }

    try {
      await Process.run(
        'ffmpeg',
        [
          '-y',
          '-f', 'v4l2',
          '-input_format', 'mjpeg',
          '-video_size', quality.resolution,
          '-framerate', '${quality.framerate}',
          '-i', targetDevice,
          '-frames:v', '1',
          '-update', '1',
          outputPath,
        ],
      );

      final file = File(outputPath);
      if (await file.exists() && await file.length() > 0) {
        _lastCapturedRapooPath = outputPath;
        notifyListeners();
        if (wasStreaming) {
          startLiveStream(deviceNode: targetDevice);
        }
        return outputPath;
      }
    } catch (e) {
      debugPrint('[CameraHardwareService] Capture error: $e');
    }

    if (wasStreaming) {
      startLiveStream(deviceNode: targetDevice);
    }
    return null;
  }
}
