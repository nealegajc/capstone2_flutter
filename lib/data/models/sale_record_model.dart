import 'package:intl/intl.dart';

class SaleRecordModel {
  final String id;
  final String perfumeCode;
  final String productName;
  final String bottleSize; // '100ml' or '50ml'
  final int quantitySold;
  final double unitPrice; // 260.0 or 180.0
  final double totalAmount; // unitPrice * quantitySold
  final String branch;
  final String soldBy;
  final DateTime soldAt;
  final String syncStatus; // 'synced' or 'pending'

  SaleRecordModel({
    required this.id,
    required this.perfumeCode,
    required this.productName,
    this.bottleSize = '100ml',
    this.quantitySold = 1,
    required this.unitPrice,
    double? totalAmount,
    this.branch = 'San Pablo',
    this.soldBy = 'staff',
    DateTime? soldAt,
    this.syncStatus = 'synced',
  }) : totalAmount = totalAmount ?? (unitPrice * quantitySold),
       soldAt = soldAt ?? DateTime.now();

  String get formattedDate {
    return DateFormat('MMM dd, yyyy • hh:mm a').format(soldAt);
  }

  String get formattedShortDate {
    return DateFormat('MMM dd, hh:mm a').format(soldAt);
  }

  String get formattedTotal {
    return '₱${totalAmount.toStringAsFixed(2)}';
  }

  String get formattedUnitPrice {
    return '₱${unitPrice.toStringAsFixed(2)}';
  }

  factory SaleRecordModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final recordId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ts =
        map['soldAt'] ?? map['sold_at'] ?? map['timestamp'] ?? map['createdAt'];
    if (ts is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    final rawQty =
        map['quantitySold'] ?? map['quantity_sold'] ?? map['quantity'];
    final qty = (rawQty is num)
        ? rawQty.toInt()
        : (int.tryParse(rawQty?.toString() ?? '') ?? 1);

    final rawPrice = map['unitPrice'] ?? map['unit_price'] ?? map['price'];
    final price = (rawPrice is num)
        ? rawPrice.toDouble()
        : (double.tryParse(rawPrice?.toString() ?? '') ?? 260.0);

    final rawTotal = map['totalAmount'] ?? map['total_amount'];
    final total = (rawTotal is num)
        ? rawTotal.toDouble()
        : (double.tryParse(rawTotal?.toString() ?? '') ?? (price * qty));

    return SaleRecordModel(
      id: recordId,
      perfumeCode:
          map['perfumeCode'] as String? ??
          map['perfume_code'] as String? ??
          map['code'] as String? ??
          '',
      productName:
          map['productName'] as String? ??
          map['product_name'] as String? ??
          map['name'] as String? ??
          '',
      bottleSize:
          map['bottleSize'] as String? ??
          map['bottle_size'] as String? ??
          '100ml',
      quantitySold: qty,
      unitPrice: price,
      totalAmount: total,
      branch: map['branch'] as String? ?? 'San Pablo',
      soldBy:
          map['soldBy'] as String? ??
          map['sold_by'] as String? ??
          map['user'] as String? ??
          'staff',
      soldAt: parsedDate,
      syncStatus:
          map['syncStatus'] as String? ??
          map['sync_status'] as String? ??
          'synced',
    );
  }

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'perfumeCode': perfumeCode,
      'productName': productName,
      'bottleSize': bottleSize,
      'quantitySold': quantitySold,
      'unitPrice': unitPrice,
      'totalAmount': totalAmount,
      'branch': branch,
      'soldBy': soldBy,
      'soldAt': soldAt.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
    };
  }

  /// Supabase-compatible Map (snake_case)
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'perfume_code': perfumeCode,
      'product_name': productName,
      'bottle_size': bottleSize,
      'quantity_sold': quantitySold,
      'unit_price': unitPrice,
      'total_amount': totalAmount,
      'branch': branch,
      'sold_by': soldBy,
      'sold_at': soldAt.toIso8601String(),
      'sync_status': syncStatus,
    };
  }

  SaleRecordModel copyWith({
    String? id,
    String? perfumeCode,
    String? productName,
    String? bottleSize,
    int? quantitySold,
    double? unitPrice,
    double? totalAmount,
    String? branch,
    String? soldBy,
    DateTime? soldAt,
    String? syncStatus,
  }) {
    return SaleRecordModel(
      id: id ?? this.id,
      perfumeCode: perfumeCode ?? this.perfumeCode,
      productName: productName ?? this.productName,
      bottleSize: bottleSize ?? this.bottleSize,
      quantitySold: quantitySold ?? this.quantitySold,
      unitPrice: unitPrice ?? this.unitPrice,
      totalAmount: totalAmount ?? this.totalAmount,
      branch: branch ?? this.branch,
      soldBy: soldBy ?? this.soldBy,
      soldAt: soldAt ?? this.soldAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }
}
