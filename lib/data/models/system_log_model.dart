import 'package:intl/intl.dart';

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

  String get formattedTimestamp {
    return DateFormat('MMM dd, hh:mm a').format(timestamp);
  }

  factory SystemLogModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final logId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ts = map['timestamp'] ?? map['createdAt'] ?? map['created_at'];
    if (ts is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return SystemLogModel(
      id: logId,
      type: map['type'] as String? ?? 'info',
      description: map['description'] as String? ?? map['desc'] as String? ?? '',
      user: map['user'] as String? ?? 'System',
      branch: map['branch'] as String? ?? 'San Pablo',
      timestamp: parsedDate,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'user': user,
      'branch': branch,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
