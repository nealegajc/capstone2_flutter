import 'package:intl/intl.dart';

class SystemLogModel {
  final String id;
  final String
  type; // 'user_login', 'product_update', 'shelf_check', 'sync', 'error'
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
    return DateFormat('MMM dd, hh:mm a').format(timestamp.toLocal());
  }

  String get category {
    final t = type.toUpperCase();
    if (t.contains('SALE')) return 'Sales';
    if (t.contains('PRODUCT') ||
        t.contains('RESTOCK') ||
        t.contains('VARIANT') ||
        t.contains('INVENTORY')) {
      return 'Inventory';
    }
    if (t.contains('SCAN') ||
        t.contains('VISION') ||
        t.contains('SNAPSHOT') ||
        t.contains('STREAM') ||
        t.contains('ROI')) {
      return 'Vision & Scans';
    }
    if (t.contains('LOGIN') ||
        t.contains('AUTH') ||
        t.contains('SECURITY') ||
        t.contains('LOCKOUT') ||
        t.contains('PIN')) {
      return 'Security & Auth';
    }
    return 'System & Sync';
  }

  factory SystemLogModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final logId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ts = map['timestamp'] ?? map['createdAt'] ?? map['created_at'];
    if (ts is num) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ts.toInt()).toLocal();
    } else if (ts is String) {
      parsedDate = (DateTime.tryParse(ts) ?? DateTime.now()).toLocal();
    } else if (ts is DateTime) {
      parsedDate = ts.toLocal();
    } else {
      parsedDate = DateTime.now();
    }

    return SystemLogModel(
      id: logId,
      type: map['type'] as String? ?? 'info',
      description:
          map['description'] as String? ?? map['desc'] as String? ?? '',
      user: map['user'] as String? ?? 'System',
      branch: map['branch'] as String? ?? 'San Pablo',
      timestamp: parsedDate,
    );
  }

  /// SQLite-compatible Map with exact column names
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'user': user,
      'branch': branch,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  /// Supabase-compatible Map (snake_case/ISO-8601 UTC timestamp)
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'type': type,
      'description': description,
      'user': user,
      'branch': branch,
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }
}
