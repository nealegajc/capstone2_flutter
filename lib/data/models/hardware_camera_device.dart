class HardwareCameraDevice {
  final String deviceNode; // e.g., '/dev/video2'
  final String name; // e.g., 'rapoo camera: rapoo camera'
  final String vendorId; // e.g., '0c45'
  final String modelId; // e.g., '6365'
  final String busInfo; // e.g., 'Bus 001 Device 010'
  final String sysfsPath;
  final bool isConnected;
  final String? assignedLayer; // 'Layer A (Top)', 'Layer B (Middle)', 'Layer C (Bottom)'
  final String? lastCapturedImagePath;
  final DateTime? lastCaptureTime;

  const HardwareCameraDevice({
    required this.deviceNode,
    required this.name,
    this.vendorId = '',
    this.modelId = '',
    this.busInfo = '',
    this.sysfsPath = '',
    this.isConnected = true,
    this.assignedLayer,
    this.lastCapturedImagePath,
    this.lastCaptureTime,
  });

  bool get isRapooCamera =>
      vendorId.toLowerCase() == '0c45' && modelId.toLowerCase() == '6365' ||
      name.toLowerCase().contains('rapoo');

  String get displayName {
    if (isRapooCamera) {
      return 'Microdia Rapoo Camera (ID 0c45:6365)';
    }
    return name.isNotEmpty ? name : 'USB Camera ($deviceNode)';
  }

  HardwareCameraDevice copyWith({
    String? deviceNode,
    String? name,
    String? vendorId,
    String? modelId,
    String? busInfo,
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
      sysfsPath: sysfsPath ?? this.sysfsPath,
      isConnected: isConnected ?? this.isConnected,
      assignedLayer: assignedLayer ?? this.assignedLayer,
      lastCapturedImagePath: lastCapturedImagePath ?? this.lastCapturedImagePath,
      lastCaptureTime: lastCaptureTime ?? this.lastCaptureTime,
    );
  }
}
