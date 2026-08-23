import 'package:cloud_firestore/cloud_firestore.dart';

class ShelfRegionModel {
  final String id;
  final String code; // 'A', 'B', 'C', 'D'
  final String assignedProductId;
  final String assignedProductName;
  final String branch;
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
    this.left = 0.0,
    this.right = 1.0,
    this.top = 0.0,
    this.bottom = 1.0,
  });

  factory ShelfRegionModel.fromMap(Map<String, dynamic> map, String id) {
    return ShelfRegionModel(
      id: id,
      code: map['code'] as String? ?? '',
      assignedProductId: map['assignedProductId'] as String? ?? '',
      assignedProductName: map['assignedProductName'] as String? ?? '',
      branch: map['branch'] as String? ?? 'San Pablo',
      left: ((map['left_coord'] ?? map['left']) as num?)?.toDouble() ?? 0.0,
      right: ((map['right_coord'] ?? map['right']) as num?)?.toDouble() ?? 1.0,
      top: ((map['top_coord'] ?? map['top']) as num?)?.toDouble() ?? 0.0,
      bottom: ((map['bottom_coord'] ?? map['bottom']) as num?)?.toDouble() ?? 1.0,
    );
  }

  factory ShelfRegionModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ShelfRegionModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'code': code,
      'assignedProductId': assignedProductId,
      'assignedProductName': assignedProductName,
      'branch': branch,
      'left': left,
      'right': right,
      'top': top,
      'bottom': bottom,
    };
  }
}
