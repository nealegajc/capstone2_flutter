class HardwareCameraDevice {
  final String deviceNode; // e.g., '/dev/video2'
  final String name; // e.g., 'rapoo camera: rapoo camera'
  final String vendorId; // e.g., '0c45'
  final String modelId; // e.g., '6365'
  final String busInfo; // e.g., 'Bus 001 Device 010'
  final String usbPort; // e.g. '1-2.1', '1-2.3'
  final String sysfsPath;
  final bool isConnected;
  final String?
  assignedLayer; // 'Layer A (Top)', 'Layer B (Middle)', 'Layer C (Bottom)'
  final String? lastCapturedImagePath;
  final DateTime? lastCaptureTime;

  const HardwareCameraDevice({
    required this.deviceNode,
    required this.name,
    this.vendorId = '',
    this.modelId = '',
    this.busInfo = '',
    this.usbPort = '',
    this.sysfsPath = '',
    this.isConnected = true,
    this.assignedLayer,
    this.lastCapturedImagePath,
    this.lastCaptureTime,
  });

  bool get isJieliCamera =>
      (vendorId.toLowerCase() == '5258' && modelId.toLowerCase() == '4a55') ||
      name.toLowerCase().contains('jieli') ||
      name.toLowerCase().contains('composite');

  bool get isRapowCamera =>
      (vendorId.toLowerCase() == '5843' && modelId.toLowerCase() == 'd527') ||
      (vendorId.toLowerCase() == '0c45' && modelId.toLowerCase() == '6365') ||
      name.toLowerCase().contains('rapow') ||
      name.toLowerCase().contains('rapoo') ||
      name.toLowerCase().contains('sunplus') ||
      vendorId.toLowerCase() == '5843';

  bool get isRapooCamera => isRapowCamera;

  bool get isSunplusCamera => isRapowCamera;

  bool get isBuiltInWebcam =>
      !isRapowCamera &&
      !isJieliCamera &&
      (name.toLowerCase().contains('integrated') ||
          name.toLowerCase().contains('built-in') ||
          name.toLowerCase().contains('azurewave') ||
          (vendorId.toLowerCase() == '13d3' &&
              modelId.toLowerCase() == '56bd'));

  String get displayName {
    if (isJieliCamera) {
      final portInfo = usbPort.isNotEmpty
          ? ' • Port $usbPort'
          : (busInfo.isNotEmpty ? ' • $busInfo' : '');
      return 'Jieli USB Camera ($deviceNode$portInfo)';
    }
    if (isRapowCamera) {
      String hubInfo = '';
      if (usbPort.startsWith('1-1.') || usbPort.startsWith('1-3.')) {
        final p = usbPort.replaceFirst(RegExp(r'1-[13]\.'), '');
        hubInfo = 'Hub 1 (Left) Port $p';
      } else if (usbPort.startsWith('1-2.') || usbPort.startsWith('1-4.')) {
        final p = usbPort.replaceFirst(RegExp(r'1-[24]\.'), '');
        hubInfo = 'Hub 2 (Right) Port $p';
      } else if (usbPort.isNotEmpty) {
        hubInfo = 'Port $usbPort';
      }
      final portStr = hubInfo.isNotEmpty
          ? ' • $hubInfo'
          : (busInfo.isNotEmpty ? ' • $busInfo' : '');
      return 'Rapow USB Camera ($deviceNode$portStr)';
    }
    if (isBuiltInWebcam) {
      return 'Laptop Integrated Webcam ($deviceNode)';
    }
    return name.isNotEmpty ? '$name ($deviceNode)' : 'USB Camera ($deviceNode)';
  }

  HardwareCameraDevice copyWith({
    String? deviceNode,
    String? name,
    String? vendorId,
    String? modelId,
    String? busInfo,
    String? usbPort,
    String? sysfsPath,
    bool? isConnected,
    String? assignedLayer,
    String? lastCapturedImagePath,
    DateTime? lastCaptureTime,
  }) {
    return HardwareCameraDevice(
      deviceNode: deviceNode ?? this.deviceNode,
      name: name ?? this.name,
      vendorId: vendorId ?? this.vendorId,
      modelId: modelId ?? this.modelId,
      busInfo: busInfo ?? this.busInfo,
      usbPort: usbPort ?? this.usbPort,
      sysfsPath: sysfsPath ?? this.sysfsPath,
      isConnected: isConnected ?? this.isConnected,
      assignedLayer: assignedLayer ?? this.assignedLayer,
      lastCapturedImagePath:
          lastCapturedImagePath ?? this.lastCapturedImagePath,
      lastCaptureTime: lastCaptureTime ?? this.lastCaptureTime,
    );
  }
}
