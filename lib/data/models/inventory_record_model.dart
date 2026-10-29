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
  bool get isSeasonalOff => status == 'seasonal_off' || status == 'inactive';
  bool get isActive => !isSeasonalOff && status != 'deleted';

  factory InventoryRecordModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final recordId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final lastUpdatedVal = map['lastUpdated'] ?? map['last_updated'];
    if (lastUpdatedVal is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(lastUpdatedVal);
    } else if (lastUpdatedVal is String) {
      parsedDate = DateTime.tryParse(lastUpdatedVal) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return InventoryRecordModel(
      id: recordId,
      perfumeCode:
          map['perfumeCode'] as String? ??
          map['perfume_code'] as String? ??
          map['code'] as String? ??
          '',
      name: map['name'] as String? ?? map['productName'] as String? ?? '',
      category: map['category'] as String? ?? 'Men',
      branch: map['branch'] as String? ?? 'San Pablo',
      shelf: map['shelf'] as String? ?? 'Area A',
      recorded: (map['recorded'] as num?)?.toInt() ?? 5,
      detected: (map['detected'] as num?)?.toInt() ?? 5,
      status: map['status'] as String? ?? 'normal',
      misplacementDetails:
          map['misplacementDetails'] as String? ??
          map['misplacement_details'] as String? ??
          '',
      lastUpdated: parsedDate,
      price: (map['price'] as num?)?.toDouble() ?? 250.0,
    );
  }

  /// SQLite-compatible Map with exact column names
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'perfumeCode': perfumeCode,
      'name': name,
      'category': category,
      'branch': branch,
      'shelf': shelf,
      'recorded': recorded,
      'detected': detected,
      'status': status,
      'misplacementDetails': misplacementDetails,
      'price': price,
      'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    };
  }

  /// Supabase-compatible Map with snake_case columns
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'perfume_code': perfumeCode,
      'name': name,
      'category': category,
      'branch': branch,
      'shelf': shelf,
      'recorded': recorded,
      'detected': detected,
      'status': status,
      'misplacement_details': misplacementDetails,
      'price': price,
      'last_updated': lastUpdated.toIso8601String(),
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
