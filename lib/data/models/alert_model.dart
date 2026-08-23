import 'package:cloud_firestore/cloud_firestore.dart';

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

  factory AlertModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final ca = map['createdAt'] ?? map['time'];
    if (ca is Timestamp) {
      parsedDate = ca.toDate();
    } else if (ca is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ca);
    } else if (ca is String) {
      parsedDate = DateTime.tryParse(ca) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    final rawIsRead = map['isRead'];
    final bool parsedIsRead = (rawIsRead is bool)
        ? rawIsRead
        : (rawIsRead == 1 || rawIsRead == '1' || rawIsRead == 'true');

    return AlertModel(
      id: id,
      title: map['title'] as String? ?? 'System Alert',
      desc: map['desc'] as String? ?? map['description'] as String? ?? '',
      branch: map['branch'] as String? ?? 'San Pablo',
      type: map['type'] as String? ?? 'low_stock',
      isRead: parsedIsRead,
      perfumeCode: map['perfumeCode'] as String? ?? '',
      createdAt: parsedDate,
    );
  }

  factory AlertModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return AlertModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'desc': desc,
      'branch': branch,
      'type': type,
      'isRead': isRead,
      'perfumeCode': perfumeCode,
      'createdAt': Timestamp.fromDate(createdAt),
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
