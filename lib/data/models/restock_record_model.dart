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

  factory RestockRecordModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final restockId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ca = map['createdAt'] ?? map['created_at'] ?? map['date'];
    if (ca is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ca);
    } else if (ca is String) {
      parsedDate = DateTime.tryParse(ca) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return RestockRecordModel(
      id: restockId,
      productName: map['productName'] as String? ??
          map['product_name'] as String? ??
          '',
      perfumeCode: map['perfumeCode'] as String? ??
          map['perfume_code'] as String? ??
          '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      fromBranch: map['fromBranch'] as String? ??
          map['from_branch'] as String? ??
          'San Pablo',
      toBranch: map['toBranch'] as String? ??
          map['to_branch'] as String? ??
          'Lipa',
      requestedBy: map['requestedBy'] as String? ??
          map['requested_by'] as String? ??
          '',
      status: map['status'] as String? ?? 'pending',
      createdAt: parsedDate,
    );
  }

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'productName': productName,
      'perfumeCode': perfumeCode,
      'quantity': quantity,
      'fromBranch': fromBranch,
      'toBranch': toBranch,
      'requestedBy': requestedBy,
      'status': status,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  /// Supabase-compatible Map
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'product_name': productName,
      'perfume_code': perfumeCode,
      'quantity': quantity,
      'from_branch': fromBranch,
      'to_branch': toBranch,
      'requested_by': requestedBy,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
