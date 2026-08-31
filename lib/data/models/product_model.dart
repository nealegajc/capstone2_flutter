class ProductModel {
  final String id;
  final String perfumeCode; // 3-char code printed on cap, e.g. 'AA1', 'AA2', 'BF1', 'CK2'
  final String name;
  final String brand;
  final String category; // 'Men', 'Women'
  final String bottleSize; // '100ml', '50ml'
  final String shelfLayer; // 'Layer A', 'Layer B', 'Layer C'
  final int slotPosition; // 1 to 10
  final double price; // optional/default 0 for pure inventory tracking
  final String status;

  ProductModel({
    required this.id,
    required this.perfumeCode,
    required this.name,
    this.brand = 'Otto Scents',
    this.category = 'Men',
    this.bottleSize = '50ml',
    this.shelfLayer = 'Layer A',
    this.slotPosition = 1,
    this.price = 0.0,
    this.status = 'active',
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final productId = id ?? (map['id'] as String? ?? '');
    return ProductModel(
      id: productId,
      perfumeCode: map['perfumeCode'] as String? ??
          map['perfume_code'] as String? ??
          map['code'] as String? ??
          '',
      name: map['name'] as String? ?? map['productName'] as String? ?? '',
      brand: map['brand'] as String? ?? 'Otto Scents',
      category: map['category'] as String? ?? 'Men',
      bottleSize: map['bottleSize'] as String? ??
          map['bottle_size'] as String? ??
          '50ml',
      shelfLayer: map['shelfLayer'] as String? ??
          map['shelf_layer'] as String? ??
          map['shelf'] as String? ??
          'Layer A',
      slotPosition: (map['slotPosition'] ?? map['slot_position'] as num?)?.toInt() ?? 1,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      status: map['status'] as String? ?? 'active',
    );
  }

  bool get isSeasonalOff =>
      status.toLowerCase() == 'seasonal_off' ||
      status.toLowerCase() == 'inactive' ||
      status.toLowerCase() == 'seasonal';

  bool get isActive => !isSeasonalOff && status.toLowerCase() != 'deleted';

  ProductModel copyWith({
    String? id,
    String? perfumeCode,
    String? name,
    String? brand,
    String? category,
    String? bottleSize,
    String? shelfLayer,
    int? slotPosition,
    double? price,
    String? status,
  }) {
    return ProductModel(
      id: id ?? this.id,
      perfumeCode: perfumeCode ?? this.perfumeCode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      bottleSize: bottleSize ?? this.bottleSize,
      shelfLayer: shelfLayer ?? this.shelfLayer,
      slotPosition: slotPosition ?? this.slotPosition,
      price: price ?? this.price,
      status: status ?? this.status,
    );
  }

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'perfumeCode': perfumeCode,
      'name': name,
      'brand': brand,
      'category': category,
      'bottleSize': bottleSize,
      'shelfLayer': shelfLayer,
      'slotPosition': slotPosition,
      'price': price,
      'status': status,
    };
  }

  /// Supabase-compatible Map (snake_case)
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'perfume_code': perfumeCode,
      'name': name,
      'brand': brand,
      'category': category,
      'bottle_size': bottleSize,
      'shelf_layer': shelfLayer,
      'slot_position': slotPosition,
      'price': price,
      'status': status,
    };
  }
}
