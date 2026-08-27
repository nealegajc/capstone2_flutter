class ShelfRegionModel {
  final String id;
  final String code; // 'Layer A', 'Layer B', 'Layer C' or 'A', 'B', 'C'
  final String assignedProductId;
  final String assignedProductName;
  final String branch;
  final int cameraId; // 1, 2, 3 (each layer has a dedicated mounted camera)
  final String cameraName; // 'Camera 1 (Top)', 'Camera 2 (Middle)', 'Camera 3 (Bottom)'
  final String layerName; // 'Layer A (Top)', 'Layer B (Middle)', 'Layer C (Bottom)'
  final double left;
  final double right;
  final double top;
  final double bottom;

  ShelfRegionModel({
    required this.id,
    required this.code,
    required this.assignedProductId,
    required this.assignedProductName,
    required this.branch,
    this.cameraId = 1,
    this.cameraName = 'Camera 1 (Top)',
    this.layerName = 'Layer A (Top)',
    this.left = 0.0,
    this.right = 1.0,
    this.top = 0.0,
    this.bottom = 1.0,
  });

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
      cameraName: map['cameraName'] as String? ?? map['camera_name'] as String? ?? 'Camera 1 (Top)',
      layerName: map['layerName'] as String? ?? map['layer_name'] as String? ?? 'Layer A (Top)',
      left: ((map['left_coord'] ?? map['left']) as num?)?.toDouble() ?? 0.0,
      right: ((map['right_coord'] ?? map['right']) as num?)?.toDouble() ?? 1.0,
      top: ((map['top_coord'] ?? map['top']) as num?)?.toDouble() ?? 0.0,
      bottom: ((map['bottom_coord'] ?? map['bottom']) as num?)?.toDouble() ?? 1.0,
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
      'left_coord': left,
      'right_coord': right,
      'top_coord': top,
      'bottom_coord': bottom,
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
      'left_coord': left,
      'right_coord': right,
      'top_coord': top,
      'bottom_coord': bottom,
    };
  }
}

