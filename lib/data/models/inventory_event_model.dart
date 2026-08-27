import 'package:intl/intl.dart';

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

  String get formattedTimestamp {
    return DateFormat('MMM dd, hh:mm a').format(timestamp);
  }

  factory InventoryEventModel.fromMap(Map<String, dynamic> map, [String? id]) {
    final eventId = id ?? (map['id'] as String? ?? '');
    DateTime parsedDate;
    final ts = map['timestamp'] ?? map['createdAt'];
    if (ts is int) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(ts);
    } else if (ts is String) {
      parsedDate = DateTime.tryParse(ts) ?? DateTime.now();
    } else {
      parsedDate = DateTime.now();
    }

    return InventoryEventModel(
      id: eventId,
      eventType: map['eventType'] as String? ??
          map['event_type'] as String? ??
          map['status'] as String? ??
          'VERIFIED',
      productName: map['productName'] as String? ??
          map['product_name'] as String? ??
          '',
      perfumeCode: map['perfumeCode'] as String? ??
          map['perfume_code'] as String? ??
          '',
      shelfArea: map['shelfArea'] as String? ??
          map['shelf_area'] as String? ??
          '',
      branch: map['branch'] as String? ?? 'San Pablo',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      timestamp: parsedDate,
      syncStatus: map['syncStatus'] as String? ??
          map['sync_status'] as String? ??
          'synced',
    );
  }

  /// SQLite-compatible Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'eventType': eventType,
      'productName': productName,
      'perfumeCode': perfumeCode,
      'shelfArea': shelfArea,
      'branch': branch,
      'quantity': quantity,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'syncStatus': syncStatus,
    };
  }

  /// Supabase-compatible Map
  Map<String, dynamic> toSupabaseMap() {
    return {
      'id': id,
      'event_type': eventType,
      'product_name': productName,
      'perfume_code': perfumeCode,
      'shelf_area': shelfArea,
      'branch': branch,
      'quantity': quantity,
      'timestamp': timestamp.toIso8601String(),
      'sync_status': syncStatus,
    };
  }
}
