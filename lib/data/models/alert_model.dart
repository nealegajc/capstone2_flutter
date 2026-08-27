import 'package:intl/intl.dart';

class AlertModel {
  final String id;
  final String title;
  final String desc;
  final String branch;
  final String type; // 'low_stock', 'out_of_stock', 'misplaced', 'restock', 'connection', 'cloud'
  final bool isRead;
  final String perfumeCode;
  final DateTime createdAt;

  AlertModel({
    required this.id,
    required this.title,
    required this.desc,
    required this.branch,
    required this.type,
    this.isRead = false,
    this.perfumeCode = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String get formattedTime {
    return DateFormat('MMM dd, hh:mm a').format(createdAt);
  }

  String get formattedTimestamp => formattedTime;

  factory AlertModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final alertId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ca = map['createdAt'] ?? map['created_at'] ?? map['time'];
    if (ca is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ca);
    } else if (ca is String) {
      parsedDate = DateTime.tryParse(ca) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    final rawIsRead = map['isRead'] ?? map['is_read'];
    final bool parsedIsRead = (rawIsRead is bool)
        ? rawIsRead
        : (rawIsRead == 1 || rawIsRead == '1' || rawIsRead == 'true');

    return AlertModel(
      id: alertId,
      title: map['title'] as String? ?? 'System Alert',
      desc: map['desc'] as String? ?? map['description'] as String? ?? '',
      branch: map['branch'] as String? ?? 'San Pablo',
      type: map['type'] as String? ?? 'low_stock',
      isRead: parsedIsRead,
      perfumeCode: map['perfumeCode'] as String? ?? map['perfume_code'] as String? ?? '',
      createdAt: parsedDate,
    );
  }

  /// SQLite-compatible Map with exact column names
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'desc': desc,
      'branch': branch,
      'type': type,
      'isRead': isRead ? 1 : 0,
      'perfumeCode': perfumeCode,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  /// Supabase-compatible Map
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'title': title,
      'description': desc,
      'branch': branch,
      'type': type,
      'is_read': isRead,
      'perfume_code': perfumeCode,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AlertModel copyWith({
    String? id,
    String? title,
    String? desc,
    String? branch,
    String? type,
    bool? isRead,
    String? perfumeCode,
    DateTime? createdAt,
  }) {
    return AlertModel(
      id: id ?? this.id,
      title: title ?? this.title,
      desc: desc ?? this.desc,
      branch: branch ?? this.branch,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      perfumeCode: perfumeCode ?? this.perfumeCode,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
