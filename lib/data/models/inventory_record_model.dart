import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryRecordModel {
  final String id;
  final String perfumeCode;
  final String name;
  final String category;
  final String branch;
  final String shelf;
  final int recorded;
  final int detected;
  final String status;
  final String misplacementDetails;
  final DateTime lastUpdated;
  final double price;

  InventoryRecordModel({
    required this.id,
    required this.perfumeCode,
    required this.name,
    this.category = 'Men',
    required this.branch,
    required this.shelf,
    this.recorded = 5,
    this.detected = 5,
    this.status = 'normal',
    this.misplacementDetails = '',
    DateTime? lastUpdated,
    this.price = 250.0,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  bool get isLowStock => status == 'low' || detected <= 2;
  bool get isOutOfStock => status == 'out_of_stock' || detected == 0;
  bool get isMisplaced => status == 'misplaced';
  bool get isNeedsReview => status == 'needs_review';

  factory InventoryRecordModel.fromMap(Map<String, dynamic> map, String id) {
    DateTime parsedDate;
    final lastUpdatedVal = map['lastUpdated'];
    if (lastUpdatedVal is Timestamp) {
      parsedDate = lastUpdatedVal.toDate();
    } else if (lastUpdatedVal is String) {
      parsedDate = DateTime.tryParse(lastUpdatedVal) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return InventoryRecordModel(
      id: id,
      perfumeCode: map['perfumeCode'] as String? ?? map['code'] as String? ?? '',
      name: map['name'] as String? ?? map['productName'] as String? ?? '',
      category: map['category'] as String? ?? 'Men',
      branch: map['branch'] as String? ?? 'San Pablo',
      shelf: map['shelf'] as String? ?? 'Area A',
      recorded: (map['recorded'] as num?)?.toInt() ?? 5,
      detected: (map['detected'] as num?)?.toInt() ?? 5,
      status: map['status'] as String? ?? 'normal',
      misplacementDetails: map['misplacementDetails'] as String? ?? '',
      lastUpdated: parsedDate,
      price: (map['price'] as num?)?.toDouble() ?? 250.0,
    );
  }

  factory InventoryRecordModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return InventoryRecordModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'perfumeCode': perfumeCode,
      'name': name,
      'category': category,
      'branch': branch,
      'shelf': shelf,
      'recorded': recorded,
      'detected': detected,
      'status': status,
      'misplacementDetails': misplacementDetails,
      'lastUpdated': Timestamp.fromDate(lastUpdated),
      'price': price,
    };
  }

  InventoryRecordModel copyWith({
    String? id,
    String? perfumeCode,
    String? name,
    String? category,
    String? branch,
    String? shelf,
    int? recorded,
    int? detected,
    String? status,
    String? misplacementDetails,
    DateTime? lastUpdated,
    double? price,
  }) {
    return InventoryRecordModel(
      id: id ?? this.id,
      perfumeCode: perfumeCode ?? this.perfumeCode,
      name: name ?? this.name,
      category: category ?? this.category,
      branch: branch ?? this.branch,
      shelf: shelf ?? this.shelf,
      recorded: recorded ?? this.recorded,
      detected: detected ?? this.detected,
      status: status ?? this.status,
      misplacementDetails: misplacementDetails ?? this.misplacementDetails,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      price: price ?? this.price,
    );
  }
}
