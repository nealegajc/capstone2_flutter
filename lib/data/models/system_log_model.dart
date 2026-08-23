import 'package:cloud_firestore/cloud_firestore.dart';

class SystemLogModel {
  final String id;
  final String type; // 'user_login', 'product_update', 'shelf_check', 'sync', 'error'
  final String description;
  final String user;
  final String branch;
  final DateTime timestamp;

  SystemLogModel({
    required this.id,
    required this.type,
    required this.description,
    required this.user,
    required this.branch,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory SystemLogModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final ts = map['timestamp'] ?? map['createdAt'];
    if (ts is Timestamp) {
      parsedDate = ts.toDate();
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SystemLogModel(
      id: id,
      type: map['type'] as String? ?? 'info',
      description: map['description'] as String? ?? '',
      user: map['user'] as String? ?? 'System',
      branch: map['branch'] as String? ?? 'San Pablo',
      timestamp: parsedDate,
    );
  }

  factory SystemLogModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return SystemLogModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'description': description,
      'user': user,
      'branch': branch,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }
}
