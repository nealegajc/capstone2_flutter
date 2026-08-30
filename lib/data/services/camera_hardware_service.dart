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
  String? _lastCapturedPath;

  // Camera node mapping (cameraId 1..6 -> deviceNode)
  final Map<int, String> _cameraNodeMap = {
    1: '/dev/video0', // Camera 1A (Top Left) default to Built-in webcam if present
    2: '/dev/video2', // Camera 1B (Top Right) default to USB Rapoo webcam if present
    3: '/dev/video2', // Camera 2A
    4: '/dev/video3', // Camera 2B
    5: '/dev/video4', // Camera 3A
    6: '/dev/video5', // Camera 3B
  };

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
  String? _activeDeviceNode;
  int _activeCameraId = 1;

  List<HardwareCameraDevice> get devices => _devices;
  HardwareCameraDevice? get rapooCamera =>
      _devices.where((d) => d.isRapooCamera).firstOrNull;
  HardwareCameraDevice? get builtInWebcam =>
      _devices.where((d) => d.isBuiltInWebcam).firstOrNull;
  String? get lastCapturedPath => _lastCapturedPath;
  Stream<Uint8List> get frameStream => _frameStreamController.stream;
  Uint8List? get latestFrame => _latestFrame;
  bool get isStreaming => _isStreaming;
  double get currentFps => _currentFps;
  CameraQualityMode get currentQualityMode => _currentQualityMode;
  String? get activeDeviceNode => _activeDeviceNode;
  int get activeCameraId => _activeCameraId;
  Map<int, String> get cameraNodeMap => Map.unmodifiable(_cameraNodeMap);

  String getAssignedDeviceNode(int cameraId) {
    return _cameraNodeMap[cameraId] ?? '/dev/video${cameraId - 1}';
  }

  void setCameraNode(int cameraId, String deviceNode) {
    _cameraNodeMap[cameraId] = deviceNode;
    if (_activeCameraId == cameraId) {
      _activeDeviceNode = deviceNode;
    }
    notifyListeners();
  }

  void setCameraAssignments(Map<int, String> assignments) {
    _cameraNodeMap.addAll(assignments);
    if (_cameraNodeMap.containsKey(_activeCameraId)) {
      _activeDeviceNode = _cameraNodeMap[_activeCameraId];
    }
    notifyListeners();
  }

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

  /// Sets quality mode (e.g. 2K QHD vs 1080p FHD) and restarts live stream seamlessly
  Future<void> setQualityMode(CameraQualityMode mode) async {
    _currentQualityMode = mode;
    notifyListeners();
    if (_isStreaming || _activeDeviceNode != null) {
      final node = _activeDeviceNode ?? getAssignedDeviceNode(_activeCameraId);
      await stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 300));
      await startLiveStream(deviceNode: node);
    }
  }

  /// Switches active camera stream to another camera / device node seamlessly
  Future<void> switchCamera(int cameraId, String? targetNode) async {
    _activeCameraId = cameraId;
    final node = targetNode ?? getAssignedDeviceNode(cameraId);
    _activeDeviceNode = node;

    await stopLiveStream();
    await Future.delayed(const Duration(milliseconds: 300));
    await startLiveStream(deviceNode: node);
  }

  /// Starts real-time hardware video stream via universal FFmpeg pipeline
  Future<void> startLiveStream({String? deviceNode}) async {
    final targetDevice = deviceNode ??
        _activeDeviceNode ??
        getAssignedDeviceNode(_activeCameraId);

    if (_isStreaming) {
      await stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 250));
    }

    _activeDeviceNode = targetDevice;

    // Check if target device is a Rapoo camera or has hardware MJPEG
    final matchedDevice = _devices.where((d) => d.deviceNode == targetDevice).firstOrNull;
    final isHardwareMjpeg = matchedDevice?.isRapooCamera == true ||
        matchedDevice?.name.toLowerCase().contains('rapoo') == true;

    List<String> ffmpegArgs;
    if (isHardwareMjpeg) {
      ffmpegArgs = [
        '-y',
        '-f', 'v4l2',
        '-input_format', 'mjpeg',
        '-video_size', _currentQualityMode.resolution,
        '-framerate', '${_currentQualityMode.framerate}',
        '-i', targetDevice,
        '-c:v', 'copy',
        '-f', 'image2pipe',
        '-',
      ];
    } else {
      // Universal raw video / built-in webcam pipeline with adaptive scaling
      ffmpegArgs = [
        '-y',
        '-f', 'v4l2',
        '-i', targetDevice,
        '-c:v', 'mjpeg',
        '-q:v', '3',
        '-f', 'image2pipe',
        '-',
      ];
    }

    try {
      _streamProcess = await Process.start('ffmpeg', ffmpegArgs);

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
              if (buffer.length > 1) {
                buffer.removeRange(0, buffer.length - 1);
              }
              break;
            }

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
              break;
            }

            final frameBytes = Uint8List.fromList(buffer.sublist(0, eoi));
            buffer.removeRange(0, eoi);

            if (frameBytes.length > 500) {
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

  Future<void> stopLiveStream() async {
    final proc = _streamProcess;
    _streamProcess = null;
    _isStreaming = false;
    _currentFps = 0.0;

    if (proc != null) {
      try {
        proc.kill(ProcessSignal.sigterm);
        await proc.exitCode.timeout(const Duration(milliseconds: 300), onTimeout: () {
          proc.kill(ProcessSignal.sigkill);
          return -1;
        });
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> restartLiveStream() async {
    await stopLiveStream();
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

            discovered.add(
              HardwareCameraDevice(
                deviceNode: devicePath,
                name: name,
                vendorId: vendorId,
                modelId: modelId,
                busInfo: busInfo.isNotEmpty ? busInfo : 'USB V4L2',
                sysfsPath: entity.path,
                isConnected: true,
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

    // Check if discovered devices changed before notifying listeners
    bool hasChanged = discovered.length != _devices.length;
    if (!hasChanged) {
      for (int i = 0; i < discovered.length; i++) {
        if (discovered[i].deviceNode != _devices[i].deviceNode ||
            discovered[i].name != _devices[i].name) {
          hasChanged = true;
          break;
        }
      }
    }

    if (hasChanged || _devices.isEmpty) {
      _devices = discovered;
      notifyListeners();
    }
    return _devices;
  }

  /// Captures a high-resolution snapshot from the assigned device node
  Future<String?> captureFrame({String? deviceNode, CameraQualityMode? mode}) async {
    final targetDevice = deviceNode ??
        _activeDeviceNode ??
        getAssignedDeviceNode(_activeCameraId);
    final outputPath = '/tmp/smart_shelf_${targetDevice.replaceAll('/', '_')}.jpg';

    final wasStreaming = _isStreaming;
    if (wasStreaming) {
      stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 250));
    }

    final matchedDevice = _devices.where((d) => d.deviceNode == targetDevice).firstOrNull;
    final isHardwareMjpeg = matchedDevice?.isRapooCamera == true;

    List<String> captureArgs;
    if (isHardwareMjpeg) {
      final quality = mode ?? _currentQualityMode;
      captureArgs = [
        '-y',
        '-f', 'v4l2',
        '-input_format', 'mjpeg',
        '-video_size', quality.resolution,
        '-framerate', '${quality.framerate}',
        '-i', targetDevice,
        '-frames:v', '1',
        '-update', '1',
        outputPath,
      ];
    } else {
      captureArgs = [
        '-y',
        '-f', 'v4l2',
        '-i', targetDevice,
        '-frames:v', '1',
        '-update', '1',
        outputPath,
      ];
    }

    try {
      await Process.run('ffmpeg', captureArgs);

      final file = File(outputPath);
      if (await file.exists() && await file.length() > 0) {
        _lastCapturedPath = outputPath;
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
