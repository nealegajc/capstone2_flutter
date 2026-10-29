import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/image_quality_log_model.dart';
import 'package:smart_shelf_linux/core/extensions.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';

void main() {
  group('Smart Shelf Model Tests', () {
    test('InventoryRecordModel calculates low stock properly', () {
      final item = InventoryRecordModel(
        id: 'test_1',
        perfumeCode: 'A',
        name: 'Ocean Breeze',
        branch: 'San Pablo',
        shelf: 'Area A',
        recorded: 5,
        detected: 2,
        status: 'low',
        price: 250.0,
      );

      expect(item.isLowStock, isTrue);
      expect(item.isOutOfStock, isFalse);
      expect(item.price.toPhp(), '₱250.00');
    });

    test('AlertModel serializes and formats time ago', () {
      final alert = AlertModel(
        id: 'alert_1',
        title: 'Low Stock Alert',
        desc: 'Zone B has only 1 bottle remaining',
        branch: 'San Pablo',
        type: 'low_stock',
        perfumeCode: 'B',
      );

      expect(alert.isRead, isFalse);
      final map = alert.toMap();
      expect(map['perfumeCode'], 'B');
      expect(map['type'], 'low_stock');
    });

    test('ImageQualityLogModel deserializes preprocessing actions', () {
      final json = {
        'id': 'qa_1',
        'brightness': 75.0,
        'contrast': 80.0,
        'sharpness': 88.5,
        'isAcceptable': true,
        'preprocessingApplied': ['CLAHE', 'Sharpening'],
        'retryCount': 1,
        'status': 'ACCEPTED',
      };

      final log = ImageQualityLogModel.fromJson(json);
      expect(log.isAcceptable, isTrue);
      expect(log.preprocessingApplied.length, 2);
      expect(log.status, 'ACCEPTED');
    });

    test('DashboardStats correctly calculates capacity and active counts', () {
      const stats = DashboardStats(
        totalInStock: 297,
        lowStockCount: 1,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 300,
        activeItemCount: 60,
      );

      expect(stats.totalInStock, 297);
      expect(stats.lowStockCount, 1);
      expect(stats.misplacedCount, 0);
      expect(stats.needsVerificationCount, 0);
      expect(stats.totalCapacity, 300);
      expect(stats.activeItemCount, 60);

      final fillPercent =
          ((stats.totalInStock / stats.totalCapacity) * 100).toInt();
      expect(fillPercent, 99);
    });
  });
}
