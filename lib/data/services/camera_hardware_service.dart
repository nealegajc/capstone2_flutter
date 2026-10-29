import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/hardware_camera_device.dart';

enum CameraQualityMode {
  hd720p('1280x720', 30, '720p HD (1280x720 - Ultra Smooth / Zero Lag)'),
  fhd1080p('1920x1080', 30, '1080p FHD (1920x1080 - High Clarity)'),
  qhd1440p('2560x1440', 30, '2K QHD (2560x1440 - Max Detail)'),
  vga480p('640x480', 30, '480p SD (640x480 - Performance Mode)');

  final String resolution;
  final int framerate;
  final String label;
  const CameraQualityMode(this.resolution, this.framerate, this.label);
}

class CameraHardwareService extends ChangeNotifier {
  static CameraHardwareService? _instance;
  static CameraHardwareService get instance =>
      _instance ??= CameraHardwareService._();

  CameraHardwareService._();

  List<HardwareCameraDevice> _devices = [];
  Timer? _pollingTimer;
  bool _isProbing = false;
  String? _lastCapturedPath;
  bool _hasLoadedPersistentConfig = false;

  // Camera node mapping (cameraId 1..6 -> deviceNode)
  final Map<int, String> _cameraNodeMap = {
    1: '/dev/video8',
    2: '/dev/video2',
    3: '/dev/video10',
    4: '/dev/video4',
    5: '/dev/video12',
    6: '/dev/video6',
  };

  // Physical USB Hub Port mapping (cameraId 1..6 -> physical usbPort e.g. '1-1.1')
  // This NEVER changes across Linux reboots or device re-enumerations!
  final Map<int, String> _cameraUsbPortMap = {
    1: '1-1.1',
    2: '1-2.1',
    3: '1-1.2',
    4: '1-2.2',
    5: '1-1.3',
    6: '1-2.3',
  };

  File get _configFile {
    final candidates = [
      File('camera_assignments.json'),
      File('capstone2_flutter/camera_assignments.json'),
      File('../camera_assignments.json'),
    ];
    for (final c in candidates) {
      if (c.existsSync()) {
        return c;
      }
    }
    try {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        final dir = Directory('$home/.local/share/smart_shelf');
        if (!dir.existsSync()) {
          dir.createSync(recursive: true);
        }
        return File('${dir.path}/camera_assignments.json');
      }
    } catch (_) {}
    return candidates.first;
  }

  Future<void> _loadPersistentAssignments() async {
    try {
      final file = _configFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        for (final entry in json.entries) {
          final camId = int.tryParse(entry.key);
          if (camId != null) {
            final data = entry.value as Map<String, dynamic>;
            final node = data['node'] as String?;
            final port = data['usbPort'] as String?;
            if (node != null && node.isNotEmpty) {
              _cameraNodeMap[camId] = node;
            }
            if (port != null && port.isNotEmpty) {
              _cameraUsbPortMap[camId] = port;
            }
          }
        }
      }
    } catch (e) {
      debugPrint(
        '[CameraHardwareService] Error loading persistent assignments: $e',
      );
    }
  }

  Future<void> _savePersistentAssignments() async {
    try {
      final file = _configFile;
      final json = <String, dynamic>{};
      for (int i = 1; i <= 6; i++) {
        json['$i'] = {
          'node': _cameraNodeMap[i] ?? '',
          'usbPort': _cameraUsbPortMap[i] ?? '',
        };
      }
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(json),
      );
      debugPrint(
        '[CameraHardwareService] Saved persistent camera assignments to ${file.path}',
      );
    } catch (e) {
      debugPrint(
        '[CameraHardwareService] Error saving persistent assignments: $e',
      );
    }
  }

  // Live Stream Pipeline
  Process? _streamProcess;
  final StreamController<Uint8List> _frameStreamController =
      StreamController<Uint8List>.broadcast();
  Uint8List? _latestFrame;
  bool _isStreaming = false;
  double _currentFps = 0.0;
  int _frameCount = 0;
  DateTime? _fpsStartTime;
  CameraQualityMode _currentQualityMode = CameraQualityMode.hd720p;
  String? _activeDeviceNode;
  int _activeCameraId = 1;

  List<HardwareCameraDevice> get devices => _devices;
  HardwareCameraDevice? get rapooCamera =>
      _devices.where((d) => d.isRapooCamera || d.isSunplusCamera).firstOrNull;
  HardwareCameraDevice? get sunplusCamera =>
      _devices.where((d) => d.isSunplusCamera).firstOrNull;
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
  Map<int, String> get cameraUsbPortMap => Map.unmodifiable(_cameraUsbPortMap);

  String getAssignedDeviceNode(int cameraId) {
    return _cameraNodeMap[cameraId] ?? '/dev/video${(cameraId - 1) * 2}';
  }

  void setCameraNode(int cameraId, String deviceNode) {
    _cameraNodeMap[cameraId] = deviceNode;
    final matched = _devices
        .where((d) => d.deviceNode == deviceNode)
        .firstOrNull;
    if (matched != null && matched.usbPort.isNotEmpty) {
      _cameraUsbPortMap[cameraId] = matched.usbPort;
    }
    if (_activeCameraId == cameraId) {
      _activeDeviceNode = deviceNode;
    }
    _savePersistentAssignments();
    notifyListeners();
  }

  void setCameraAssignments(
    Map<int, String> assignments, {
    Map<int, String>? usbPorts,
  }) {
    _cameraNodeMap.addAll(assignments);
    if (usbPorts != null) {
      _cameraUsbPortMap.addAll(usbPorts);
    } else {
      // Auto-bind to physical USB port so it locks across reboots
      for (final entry in assignments.entries) {
        final camId = entry.key;
        final node = entry.value;
        final matched = _devices.where((d) => d.deviceNode == node).firstOrNull;
        if (matched != null && matched.usbPort.isNotEmpty) {
          _cameraUsbPortMap[camId] = matched.usbPort;
        }
      }
    }
    if (_cameraNodeMap.containsKey(_activeCameraId)) {
      _activeDeviceNode = _cameraNodeMap[_activeCameraId];
    }
    _savePersistentAssignments();
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

  /// Sets quality mode and restarts live stream seamlessly
  Future<void> setQualityMode(CameraQualityMode mode) async {
    _currentQualityMode = mode;
    notifyListeners();
    if (_isStreaming || _activeDeviceNode != null) {
      final node = _activeDeviceNode ?? getAssignedDeviceNode(_activeCameraId);
      await stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 200));
      await startLiveStream(deviceNode: node);
    }
  }

  /// Switches active camera stream to another camera / device node seamlessly
  Future<void> switchCamera(int cameraId, String? targetNode) async {
    _activeCameraId = cameraId;
    final node = targetNode ?? getAssignedDeviceNode(cameraId);
    _activeDeviceNode = node;

    await stopLiveStream();
    await Future.delayed(const Duration(milliseconds: 200));
    await startLiveStream(deviceNode: node);
  }

  /// Starts real-time hardware video stream via universal low-latency FFmpeg pipeline
  Future<void> startLiveStream({String? deviceNode}) async {
    final targetDevice =
        deviceNode ??
        _activeDeviceNode ??
        getAssignedDeviceNode(_activeCameraId);

    if (_isStreaming) {
      await stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    _activeDeviceNode = targetDevice;

    // Check if target device is a SunplusIT/Rapoo/Jieli camera or has hardware MJPEG
    final matchedDevice = _devices
        .where((d) => d.deviceNode == targetDevice)
        .firstOrNull;
    final isHardwareMjpeg =
        matchedDevice?.isSunplusCamera == true ||
        matchedDevice?.isRapooCamera == true ||
        matchedDevice?.isJieliCamera == true ||
        matchedDevice?.name.toLowerCase().contains('sunplus') == true ||
        matchedDevice?.name.toLowerCase().contains('rapoo') == true ||
        matchedDevice?.name.toLowerCase().contains('jieli') == true ||
        matchedDevice?.name.toLowerCase().contains('composite') == true;

    List<String> ffmpegArgs;
    if (isHardwareMjpeg) {
      ffmpegArgs = [
        '-y',
        '-loglevel',
        'error',
        '-fflags',
        'nobuffer+flush_packets+discardcorrupt',
        '-flags',
        'low_delay',
        '-thread_queue_size',
        '2',
        '-probesize',
        '32',
        '-analyzeduration',
        '0',
        '-f',
        'v4l2',
        '-input_format',
        'mjpeg',
        '-video_size',
        _currentQualityMode.resolution,
        '-framerate',
        '${_currentQualityMode.framerate}',
        '-i',
        targetDevice,
        '-an',
        '-c:v',
        'copy',
        '-flush_packets',
        '1',
        '-f',
        'image2pipe',
        '-',
      ];
    } else {
      // Universal raw video / built-in webcam pipeline with high quality encoding
      ffmpegArgs = [
        '-y',
        '-loglevel',
        'error',
        '-fflags',
        'nobuffer+flush_packets+discardcorrupt',
        '-flags',
        'low_delay',
        '-thread_queue_size',
        '2',
        '-probesize',
        '32',
        '-analyzeduration',
        '0',
        '-f',
        'v4l2',
        '-video_size',
        _currentQualityMode.resolution,
        '-framerate',
        '${_currentQualityMode.framerate}',
        '-i',
        targetDevice,
        '-an',
        '-c:v',
        'mjpeg',
        '-q:v',
        '2',
        '-flush_packets',
        '1',
        '-f',
        'image2pipe',
        '-',
      ];
    }

    try {
      final currentProc = await Process.start('ffmpeg', ffmpegArgs);
      _streamProcess = currentProc;

      _isStreaming = true;
      _frameCount = 0;
      _fpsStartTime = DateTime.now();
      notifyListeners();

      final builder = BytesBuilder(copy: false);

      // Actively consume and discard stderr in non-blocking fashion
      currentProc.stderr.listen(
        (data) {},
        onError: (_) {},
        cancelOnError: false,
      );

      currentProc.stdout.listen(
        (chunk) {
          if (_streamProcess != currentProc) return;
          builder.add(chunk);

          // Fast typed Uint8List buffer access
          final bytes = builder.takeBytes();
          final len = bytes.length;

          // Find the LAST complete JPEG frame in the incoming stream
          // SOI = 0xFF 0xD8, EOI = 0xFF 0xD9
          int lastSoi = -1;
          int lastEoi = -1;

          int searchIdx = 0;
          while (searchIdx < len - 1) {
            int soi = -1;
            for (int i = searchIdx; i < len - 1; i++) {
              if (bytes[i] == 0xFF && bytes[i + 1] == 0xD8) {
                soi = i;
                break;
              }
            }
            if (soi == -1) break;

            int eoi = -1;
            for (int i = soi + 2; i < len - 1; i++) {
              if (bytes[i] == 0xFF && bytes[i + 1] == 0xD9) {
                eoi = i + 2;
                break;
              }
            }
            if (eoi == -1) break;

            // Found complete frame
            lastSoi = soi;
            lastEoi = eoi;
            searchIdx = eoi;
          }

          if (lastSoi != -1 && lastEoi != -1 && (lastEoi - lastSoi) > 1000) {
            // Extract ONLY the freshest, most recent complete frame
            // Any older frames in the buffer are discarded instantly (zero lag accumulation!)
            final frameBytes = bytes.sublist(lastSoi, lastEoi);
            _latestFrame = frameBytes;
            if (!_frameStreamController.isClosed) {
              _frameStreamController.add(frameBytes);
            }

            _frameCount++;
            if (_fpsStartTime != null) {
              final elapsedSec =
                  DateTime.now().difference(_fpsStartTime!).inMilliseconds /
                  1000.0;
              if (elapsedSec >= 1.0) {
                _currentFps = _frameCount / elapsedSec;
                _frameCount = 0;
                _fpsStartTime = DateTime.now();
                notifyListeners();
              }
            }

            // Keep any trailing partial bytes after the last complete frame
            if (lastEoi < len) {
              builder.add(bytes.sublist(lastEoi));
            }
          } else {
            // No complete frame yet; keep trailing bytes unless buffer exceeds 1MB corrupt limit
            if (len < 1024 * 1024) {
              builder.add(bytes);
            }
          }
        },
        onError: (err) {
          if (_streamProcess == currentProc) {
            debugPrint('[CameraHardwareService] Live stream error: $err');
            _isStreaming = false;
            notifyListeners();
          }
        },
        onDone: () {
          if (_streamProcess == currentProc) {
            _isStreaming = false;
            notifyListeners();
          }
        },
        cancelOnError: true,
      );
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
        proc.kill(ProcessSignal.sigkill);
        await proc.exitCode.timeout(
          const Duration(milliseconds: 300),
          onTimeout: () => -1,
        );
      } catch (_) {}
    }
    await Future.delayed(const Duration(milliseconds: 200));
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

    // Load persistent assignments from disk on first probe
    if (!_hasLoadedPersistentConfig) {
      await _loadPersistentAssignments();
      _hasLoadedPersistentConfig = true;
    }

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
            String usbPort = '';

            // 1. Inspect sysfs parents directly for accurate USB vendor, product, and physical port
            try {
              final realEntityPath = await entity.resolveSymbolicLinks();
              final parts = realEntityPath.split('/');
              for (final p in parts) {
                if (p.contains(':') &&
                    (p.startsWith('1-') || p.startsWith('2-'))) {
                  usbPort = p.split(':').first;
                  break;
                } else if ((p.startsWith('1-') || p.startsWith('2-')) &&
                    p.contains('.')) {
                  usbPort = p;
                }
              }

              Directory? curDir = Directory(realEntityPath);
              while (curDir != null &&
                  curDir.path != '/' &&
                  curDir.path != '.') {
                final vendorFile = File('${curDir.path}/idVendor');
                if (await vendorFile.exists()) {
                  vendorId = (await vendorFile.readAsString()).trim();
                  final modelFile = File('${curDir.path}/idProduct');
                  if (await modelFile.exists()) {
                    modelId = (await modelFile.readAsString()).trim();
                  }
                  final busFile = File('${curDir.path}/busnum');
                  final devFile = File('${curDir.path}/devnum');
                  if (await busFile.exists() && await devFile.exists()) {
                    final bus = (await busFile.readAsString()).trim().padLeft(
                      3,
                      '0',
                    );
                    final dev = (await devFile.readAsString()).trim().padLeft(
                      3,
                      '0',
                    );
                    busInfo = 'Bus $bus Device $dev';
                  }
                  final prodFile = File('${curDir.path}/product');
                  if (await prodFile.exists()) {
                    final pName = (await prodFile.readAsString()).trim();
                    if (pName.isNotEmpty &&
                        (name == 'USB Video Device' ||
                            name.startsWith('USB '))) {
                      name = pName;
                    }
                  }
                  break;
                }
                curDir = curDir.parent;
              }
            } catch (_) {}

            // 2. Fallback to udevadm if sysfs traversal did not find vendor
            if (vendorId.isEmpty) {
              try {
                final result = await Process.run('udevadm', [
                  'info',
                  '-q',
                  'property',
                  '-n',
                  devicePath,
                ]);
                if (result.exitCode == 0) {
                  final output = result.stdout.toString();
                  for (final line in output.split('\n')) {
                    if (line.startsWith('ID_VENDOR_ID=')) {
                      vendorId = line.replaceFirst('ID_VENDOR_ID=', '').trim();
                    } else if (line.startsWith('ID_MODEL_ID=')) {
                      modelId = line.replaceFirst('ID_MODEL_ID=', '').trim();
                    } else if (line.startsWith('ID_MODEL=')) {
                      final m = line.replaceFirst('ID_MODEL=', '').trim();
                      if (m.isNotEmpty &&
                          (name == 'USB Video Device' ||
                              name.startsWith('USB '))) {
                        name = m.replaceAll('_', ' ');
                      }
                    }
                  }
                }
              } catch (_) {}
            }

            discovered.add(
              HardwareCameraDevice(
                deviceNode: devicePath,
                name: name,
                vendorId: vendorId,
                modelId: modelId,
                busInfo: busInfo.isNotEmpty ? busInfo : 'USB V4L2',
                usbPort: usbPort,
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

    // Auto-lock dynamic /dev/video* nodes to their physical USB ports across reboots!
    for (int camId = 1; camId <= 6; camId++) {
      final lockedPort = _cameraUsbPortMap[camId];
      if (lockedPort != null && lockedPort.isNotEmpty && lockedPort != 'none') {
        final matchedDev = discovered
            .where((d) => d.usbPort == lockedPort)
            .firstOrNull;
        if (matchedDev != null) {
          _cameraNodeMap[camId] = matchedDev.deviceNode;
        }
      }
    }

    // Persistent symlink priority (from udev rules /dev/cam1a .. /dev/cam3b)
    final persistentSymlinks = {
      1: '/dev/cam1a',
      2: '/dev/cam1b',
      3: '/dev/cam2a',
      4: '/dev/cam2b',
      5: '/dev/cam3a',
      6: '/dev/cam3b',
    };
    bool hasSymlinks = true;
    for (final sym in persistentSymlinks.values) {
      if (!File(sym).existsSync()) {
        hasSymlinks = false;
        break;
      }
    }
    if (hasSymlinks) {
      for (int i = 1; i <= 6; i++) {
        _cameraNodeMap[i] = persistentSymlinks[i]!;
      }
    }

    // Default 2-hub topology fallback (Hub 1: 1-1.* or 1-3.* | Hub 2: 1-2.* or 1-4.*)
    final hub1Devs = discovered
        .where(
          (d) => d.usbPort.startsWith('1-1.') || d.usbPort.startsWith('1-3.'),
        )
        .toList();
    final hub2Devs = discovered
        .where(
          (d) => d.usbPort.startsWith('1-2.') || d.usbPort.startsWith('1-4.'),
        )
        .toList();
    if (hub1Devs.isNotEmpty || hub2Devs.isNotEmpty) {
      // Hub 1: Left side (Cam 1A, 2A, 3A -> IDs 1, 3, 5)
      final p11 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.1') &&
                (d.usbPort.startsWith('1-1.') || d.usbPort.startsWith('1-3.')),
          )
          .firstOrNull;
      final p12 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.2') &&
                (d.usbPort.startsWith('1-1.') || d.usbPort.startsWith('1-3.')),
          )
          .firstOrNull;
      final p13 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.3') &&
                (d.usbPort.startsWith('1-1.') || d.usbPort.startsWith('1-3.')),
          )
          .firstOrNull;
      if (p11 != null &&
          (_cameraNodeMap[1] == null ||
              _cameraNodeMap[1] == 'none' ||
              !_cameraUsbPortMap.containsKey(1))) {
        _cameraNodeMap[1] = p11.deviceNode;
        _cameraUsbPortMap[1] = p11.usbPort;
      }
      if (p12 != null &&
          (_cameraNodeMap[3] == null ||
              _cameraNodeMap[3] == 'none' ||
              !_cameraUsbPortMap.containsKey(3))) {
        _cameraNodeMap[3] = p12.deviceNode;
        _cameraUsbPortMap[3] = p12.usbPort;
      }
      if (p13 != null &&
          (_cameraNodeMap[5] == null ||
              _cameraNodeMap[5] == 'none' ||
              !_cameraUsbPortMap.containsKey(5))) {
        _cameraNodeMap[5] = p13.deviceNode;
        _cameraUsbPortMap[5] = p13.usbPort;
      }

      // Hub 2: Right side (Cam 1B, 2B, 3B -> IDs 2, 4, 6)
      final p21 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.1') &&
                (d.usbPort.startsWith('1-2.') || d.usbPort.startsWith('1-4.')),
          )
          .firstOrNull;
      final p22 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.2') &&
                (d.usbPort.startsWith('1-2.') || d.usbPort.startsWith('1-4.')),
          )
          .firstOrNull;
      final p23 = discovered
          .where(
            (d) =>
                d.usbPort.endsWith('.3') &&
                (d.usbPort.startsWith('1-2.') || d.usbPort.startsWith('1-4.')),
          )
          .firstOrNull;
      if (p21 != null &&
          (_cameraNodeMap[2] == null ||
              _cameraNodeMap[2] == 'none' ||
              !_cameraUsbPortMap.containsKey(2))) {
        _cameraNodeMap[2] = p21.deviceNode;
        _cameraUsbPortMap[2] = p21.usbPort;
      }
      if (p22 != null &&
          (_cameraNodeMap[4] == null ||
              _cameraNodeMap[4] == 'none' ||
              !_cameraUsbPortMap.containsKey(4))) {
        _cameraNodeMap[4] = p22.deviceNode;
        _cameraUsbPortMap[4] = p22.usbPort;
      }
      if (p23 != null &&
          (_cameraNodeMap[6] == null ||
              _cameraNodeMap[6] == 'none' ||
              !_cameraUsbPortMap.containsKey(6))) {
        _cameraNodeMap[6] = p23.deviceNode;
        _cameraUsbPortMap[6] = p23.usbPort;
      }
    } else {
      // Single external camera bench test fallback (only if <= 1 external camera connected and unassigned)
      final externalCameras = discovered
          .where((d) => !d.isBuiltInWebcam)
          .toList();
      if (externalCameras.length == 1) {
        final singleCam = externalCameras.first;
        for (int camId = 1; camId <= 6; camId++) {
          if (_cameraNodeMap[camId] == null ||
              _cameraNodeMap[camId] == 'none') {
            _cameraNodeMap[camId] = singleCam.deviceNode;
            _cameraUsbPortMap[camId] = singleCam.usbPort;
          }
        }
      }
    }

    if (_activeDeviceNode == null ||
        !discovered.any((d) => d.deviceNode == _activeDeviceNode)) {
      _activeDeviceNode =
          _cameraNodeMap[_activeCameraId] ?? discovered.firstOrNull?.deviceNode;
    }

    // Sort discovered devices deterministically by device node
    discovered.sort((a, b) {
      final aNum =
          int.tryParse(a.deviceNode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      final bNum =
          int.tryParse(b.deviceNode.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      return aNum.compareTo(bNum);
    });

    // Check if discovered devices changed before notifying listeners
    bool hasChanged = discovered.length != _devices.length;
    if (!hasChanged) {
      for (int i = 0; i < discovered.length; i++) {
        if (discovered[i].deviceNode != _devices[i].deviceNode ||
            discovered[i].name != _devices[i].name ||
            discovered[i].usbPort != _devices[i].usbPort) {
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
  Future<String?> captureFrame({
    String? deviceNode,
    CameraQualityMode? mode,
  }) async {
    final targetDevice =
        deviceNode ??
        _activeDeviceNode ??
        getAssignedDeviceNode(_activeCameraId);
    final outputPath =
        '/tmp/smart_shelf_${targetDevice.replaceAll('/', '_')}.jpg';

    final wasStreaming = _isStreaming;
    if (wasStreaming) {
      stopLiveStream();
      await Future.delayed(const Duration(milliseconds: 250));
    }

    final matchedDevice = _devices
        .where((d) => d.deviceNode == targetDevice)
        .firstOrNull;
    final isHardwareMjpeg =
        matchedDevice?.isSunplusCamera == true ||
        matchedDevice?.isRapooCamera == true ||
        matchedDevice?.isJieliCamera == true ||
        matchedDevice?.name.toLowerCase().contains('sunplus') == true ||
        matchedDevice?.name.toLowerCase().contains('rapoo') == true ||
        matchedDevice?.name.toLowerCase().contains('jieli') == true ||
        matchedDevice?.name.toLowerCase().contains('composite') == true;

    List<String> captureArgs;
    final quality = mode ?? _currentQualityMode;
    if (isHardwareMjpeg) {
      captureArgs = [
        '-y',
        '-fflags',
        '+discardcorrupt',
        '-f',
        'v4l2',
        '-input_format',
        'mjpeg',
        '-video_size',
        quality.resolution,
        '-framerate',
        '${quality.framerate}',
        '-i',
        targetDevice,
        '-an',
        '-vframes',
        '1',
        '-q:v',
        '1',
        '-update',
        '1',
        outputPath,
      ];
    } else {
      captureArgs = [
        '-y',
        '-fflags',
        '+discardcorrupt',
        '-f',
        'v4l2',
        '-video_size',
        quality.resolution,
        '-framerate',
        '${quality.framerate}',
        '-i',
        targetDevice,
        '-an',
        '-vframes',
        '1',
        '-q:v',
        '1',
        '-update',
        '1',
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
