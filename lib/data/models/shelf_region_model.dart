class ShelfRegionModel {
  final String id;
  final String code; // e.g. 'Layer A - Left - 100ML', '1A-100ml', etc.
  final String assignedProductId;
  final String assignedProductName;
  final String branch;
  final int cameraId; // 1 (1A), 2 (1B), 3 (2A), 4 (2B), 5 (3A), 6 (3B)
  final String cameraName; // 'Camera 1A (Top Left)', 'Camera 1B (Top Right)', etc.
  final String layerName; // 'Layer A (Top)', 'Layer B (Middle)', 'Layer C (Bottom)'
  final String cameraPosition; // 'left' or 'right'
  final String deviceNode; // e.g. '/dev/video2'
  final String bottleSize; // '100ml' or '50ml'
  final double left;
  final double right;
  final double top;
  final double bottom;
  final String status;

  ShelfRegionModel({
    required this.id,
    required this.code,
    required this.assignedProductId,
    required this.assignedProductName,
    required this.branch,
    this.cameraId = 1,
    this.cameraName = 'Camera 1A (Top Left)',
    this.layerName = 'Layer A (Top)',
    this.cameraPosition = 'left',
    this.deviceNode = '/dev/video2',
    this.bottleSize = '100ml',
    this.left = 0.0,
    this.right = 1.0,
    this.top = 0.0,
    this.bottom = 1.0,
    this.status = 'active',
  });

  bool get isSeasonalOff =>
      status.toLowerCase() == 'seasonal_off' ||
      status.toLowerCase() == 'inactive' ||
      status.toLowerCase() == 'paused';

  bool get isActive => !isSeasonalOff && status.toLowerCase() != 'deleted';

  factory ShelfRegionModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final regionId = id ?? (map['id'] as String? ?? '');
    return ShelfRegionModel(
      id: regionId,
      code: map['code'] as String? ?? '',
      assignedProductId: map['assignedProductId'] as String? ??
          map['assigned_product_id'] as String? ??
          '',
      assignedProductName: map['assignedProductName'] as String? ??
          map['assigned_product_name'] as String? ??
          '',
      branch: map['branch'] as String? ?? 'San Pablo',
      cameraId: (map['cameraId'] ?? map['camera_id'] as num?)?.toInt() ?? 1,
      cameraName: map['cameraName'] as String? ?? map['camera_name'] as String? ?? 'Camera 1A (Top Left)',
      layerName: map['layerName'] as String? ?? map['layer_name'] as String? ?? 'Layer A (Top)',
      cameraPosition: map['cameraPosition'] as String? ?? map['camera_position'] as String? ?? 'left',
      deviceNode: map['deviceNode'] as String? ?? map['device_node'] as String? ?? '/dev/video2',
      bottleSize: map['bottleSize'] as String? ?? map['bottle_size'] as String? ?? '100ml',
      left: ((map['left_coord'] ?? map['left']) as num?)?.toDouble() ?? 0.0,
      right: ((map['right_coord'] ?? map['right']) as num?)?.toDouble() ?? 1.0,
      top: ((map['top_coord'] ?? map['top']) as num?)?.toDouble() ?? 0.0,
      bottom: ((map['bottom_coord'] ?? map['bottom']) as num?)?.toDouble() ?? 1.0,
      status: map['status'] as String? ?? 'active',
    );
  }

  ShelfRegionModel copyWith({
    String? id,
    String? code,
    String? assignedProductId,
    String? assignedProductName,
    String? branch,
    int? cameraId,
    String? cameraName,
    String? layerName,
    String? cameraPosition,
    String? deviceNode,
    String? bottleSize,
    double? left,
    double? right,
    double? top,
    double? bottom,
    String? status,
  }) {
    return ShelfRegionModel(
      id: id ?? this.id,
      code: code ?? this.code,
      assignedProductId: assignedProductId ?? this.assignedProductId,
      assignedProductName: assignedProductName ?? this.assignedProductName,
      branch: branch ?? this.branch,
      cameraId: cameraId ?? this.cameraId,
      cameraName: cameraName ?? this.cameraName,
      layerName: layerName ?? this.layerName,
      cameraPosition: cameraPosition ?? this.cameraPosition,
      deviceNode: deviceNode ?? this.deviceNode,
      bottleSize: bottleSize ?? this.bottleSize,
      left: left ?? this.left,
      right: right ?? this.right,
      top: top ?? this.top,
      bottom: bottom ?? this.bottom,
      status: status ?? this.status,
    );
  }

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'assignedProductId': assignedProductId,
      'assignedProductName': assignedProductName,
      'branch': branch,
      'cameraId': cameraId,
      'cameraName': cameraName,
      'layerName': layerName,
      'cameraPosition': cameraPosition,
      'deviceNode': deviceNode,
      'bottleSize': bottleSize,
      'left_coord': left,
      'right_coord': right,
      'top_coord': top,
      'bottom_coord': bottom,
      'status': status,
    };
  }

  /// Supabase-compatible Map
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'code': code,
      'assigned_product_id': assignedProductId,
      'assigned_product_name': assignedProductName,
      'branch': branch,
      'camera_id': cameraId,
      'camera_name': cameraName,
      'layer_name': layerName,
      'camera_position': cameraPosition,
      'device_node': deviceNode,
      'bottle_size': bottleSize,
      'left_coord': left,
      'right_coord': right,
      'top_coord': top,
      'bottom_coord': bottom,
      'status': status,
    };
  }
}
