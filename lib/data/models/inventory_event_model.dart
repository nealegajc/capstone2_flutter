import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryEventModel {
  final String id;
  final String eventType; // 'REMOVED', 'RESTOCKED', 'MISPLACED', 'VERIFIED'
  final String productName;
  final String perfumeCode;
  final String shelfArea;
  final String branch;
  final int quantity;
  final DateTime timestamp;
  final String syncStatus; // 'synced', 'pending'

  InventoryEventModel({
    required this.id,
    required this.eventType,
    required this.productName,
    required this.perfumeCode,
    required this.shelfArea,
    required this.branch,
    required this.quantity,
    DateTime? timestamp,
    this.syncStatus = 'synced',
  }) : timestamp = timestamp ?? DateTime.now();

  factory InventoryEventModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final ts = map['timestamp'];
    if (ts is Timestamp) {
      parsedDate = ts.toDate();
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return InventoryEventModel(
      id: id,
      eventType: map['eventType'] as String? ?? map['status'] as String? ?? 'VERIFIED',
      productName: map['productName'] as String? ?? '',
      perfumeCode: map['perfumeCode'] as String? ?? '',
      shelfArea: map['shelfArea'] as String? ?? '',
      branch: map['branch'] as String? ?? 'San Pablo',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      timestamp: parsedDate,
      syncStatus: map['syncStatus'] as String? ?? 'synced',
    );
  }

  factory InventoryEventModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return InventoryEventModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'eventType': eventType,
      'productName': productName,
      'perfumeCode': perfumeCode,
      'shelfArea': shelfArea,
      'branch': branch,
      'quantity': quantity,
      'timestamp': Timestamp.fromDate(timestamp),
      'syncStatus': syncStatus,
    };
  }
}
