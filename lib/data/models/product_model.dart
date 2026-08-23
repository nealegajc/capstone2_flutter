import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String perfumeCode; // 'A', 'B', 'C', 'D'
  final String name;
  final String brand;
  final String category; // 'Men', 'Women', 'Unisex'
  final String bottleSize; // e.g. '50ml', '100ml'
  final double price;
  final String status;

  ProductModel({
    required this.id,
    required this.perfumeCode,
    required this.name,
    this.brand = 'Otto Scents',
    this.category = 'Men',
    this.bottleSize = '50ml',
    this.price = 250.0,
    this.status = 'active',
  });

  factory ProductModel.fromMap(Map<String, dynamic> map, String id) {
    return ProductModel(
      id: id,
      perfumeCode: map['perfumeCode'] as String? ?? map['code'] as String? ?? '',
      name: map['name'] as String? ?? map['productName'] as String? ?? '',
      brand: map['brand'] as String? ?? 'Otto Scents',
      category: map['category'] as String? ?? 'Men',
      bottleSize: map['bottleSize'] as String? ?? '50ml',
      price: (map['price'] as num?)?.toDouble() ?? 250.0,
      status: map['status'] as String? ?? 'active',
    );
  }

  factory ProductModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ProductModel.fromMap(doc.data() ?? {}, doc.id);
  }

  Map<String, dynamic> toMap() {
    return {
      'perfumeCode': perfumeCode,
      'name': name,
      'brand': brand,
      'category': category,
      'bottleSize': bottleSize,
      'price': price,
      'status': status,
    };
  }
}
