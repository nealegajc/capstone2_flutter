import 'package:cloud_firestore/cloud_firestore.dart';

class RestockRecordModel {
  final String id;
  final String productName;
  final String perfumeCode;
  final int quantity;
  final String fromBranch;
  final String toBranch;
  final String requestedBy;
  final String status; // 'pending', 'in_transit', 'received', 'verified'
  final DateTime createdAt;

  RestockRecordModel({
    required this.id,
    required this.productName,
    required this.perfumeCode,
    required this.quantity,
    required this.fromBranch,
    required this.toBranch,
    required this.requestedBy,
    this.status = 'pending',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory RestockRecordModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final ca = map['createdAt'] ?? map['date'];
    if (ca is Timestamp) {
      parsedDate = ca.toDate();
    } else if (ca is String) {
      parsedDate = DateTime.tryParse(ca) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return RestockRecordModel(
      id: id,
      productName: map['productName'] as String? ?? '',
      perfumeCode: map['perfumeCode'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      fromBranch: map['fromBranch'] as String? ?? 'San Pablo',
      toBranch: map['toBranch'] as String? ?? 'Lipa',
      requestedBy: map['requestedBy'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      createdAt: parsedDate,
    );
  }

  factory RestockRecordModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return RestockRecordModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'perfumeCode': perfumeCode,
      'quantity': quantity,
      'fromBranch': fromBranch,
      'toBranch': toBranch,
      'requestedBy': requestedBy,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
