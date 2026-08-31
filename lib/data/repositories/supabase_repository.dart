import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/inventory_record_model.dart';
import '../models/alert_model.dart';
import '../models/inventory_event_model.dart';
import '../models/system_log_model.dart';
import '../models/restock_record_model.dart';
import '../models/sync_queue_model.dart';
import '../models/shelf_region_model.dart';

class SupabaseRepository {
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // INVENTORY RECORDS
  // ---------------------------------------------------------------------------
  Stream<List<InventoryRecordModel>> streamInventory(String? branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      var query = client.from('inventory_records').stream(primaryKey: ['id']);
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.eq('branch', branch);
      }
      return query.map((data) {
        return data.map((row) => InventoryRecordModel.fromMap(row)).toList();
      }).handleError((_) => <InventoryRecordModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveInventoryRecord(InventoryRecordModel item) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('inventory_records').upsert(item.toSupabaseMap());
    } catch (_) {}
  }

  Future<void> deleteInventoryRecord(String id) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('inventory_records').delete().eq('id', id);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // ALERTS
  // ---------------------------------------------------------------------------
  Stream<List<AlertModel>> streamAlerts(String? branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      var query = client.from('alerts').stream(primaryKey: ['id']);
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.eq('branch', branch);
      }
      return query.map((data) {
        final list = data.map((row) => AlertModel.fromMap(row)).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      }).handleError((_) => <AlertModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveAlert(AlertModel alert) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('alerts').upsert(alert.toSupabaseMap());
    } catch (_) {}
  }

  Future<void> markAlertRead(String id) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('alerts').update({'is_read': true}).eq('id', id);
    } catch (_) {}
  }

  Future<void> markAllAlertsRead(List<String> ids) async {
    try {
      final client = _supabase;
      if (client == null || ids.isEmpty) return;
      await client.from('alerts').update({'is_read': true}).inFilter('id', ids);
    } catch (_) {}
  }

  Future<void> deleteAlert(String id) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('alerts').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> deleteAllReadAlerts(List<String> readIds) async {
    try {
      final client = _supabase;
      if (client == null || readIds.isEmpty) return;
      await client.from('alerts').delete().inFilter('id', readIds);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // INVENTORY EVENTS (MOVEMENT LOGS)
  // ---------------------------------------------------------------------------
  Stream<List<InventoryEventModel>> streamInventoryEvents(String? branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      var query = client.from('inventory_events').stream(primaryKey: ['id']);
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.eq('branch', branch);
      }
      return query.map((data) {
        final list = data.map((row) => InventoryEventModel.fromMap(row)).toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      }).handleError((_) => <InventoryEventModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> logInventoryEvent(InventoryEventModel event) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('inventory_events').upsert(event.toSupabaseMap());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SYSTEM LOGS
  // ---------------------------------------------------------------------------
  Stream<List<SystemLogModel>> streamSystemLogs(String? branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      var query = client.from('system_logs').stream(primaryKey: ['id']);
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.eq('branch', branch);
      }
      return query.map((data) {
        final list = data.map((row) => SystemLogModel.fromMap(row)).toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      }).handleError((_) => <SystemLogModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> logSystemActivity(SystemLogModel log) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('system_logs').upsert(log.toSupabaseMap());
    } catch (_) {}
  }

  Future<void> deleteSystemLog(String id) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('system_logs').delete().eq('id', id);
    } catch (_) {}
  }

  Future<void> deleteAllSystemLogs(List<String> ids) async {
    try {
      final client = _supabase;
      if (client == null || ids.isEmpty) return;
      await client.from('system_logs').delete().inFilter('id', ids);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SYNC QUEUE
  // ---------------------------------------------------------------------------
  Stream<List<SyncQueueModel>> streamSyncQueue(String? branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      var query = client.from('sync_queue').stream(primaryKey: ['id']);
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.eq('branch', branch);
      }
      return query.map((data) {
        return data.map((row) => SyncQueueModel.fromMap(row)).toList();
      }).handleError((_) => <SyncQueueModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  // ---------------------------------------------------------------------------
  // RESTOCK RECORDS
  // ---------------------------------------------------------------------------
  Stream<List<RestockRecordModel>> streamRestockRecords() {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      return client.from('restock_records').stream(primaryKey: ['id']).map((data) {
        return data.map((row) => RestockRecordModel.fromMap(row)).toList();
      }).handleError((_) => <RestockRecordModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> createRestockRequest(RestockRecordModel restock) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('restock_records').upsert(restock.toSupabaseMap());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SHELF REGIONS & PRODUCTS
  // ---------------------------------------------------------------------------
  Stream<List<ProductModel>> streamProducts() {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      return client
          .from('products')
          .stream(primaryKey: ['id'])
          .map((data) {
        return data.map((row) => ProductModel.fromMap(row)).toList();
      }).handleError((_) => <ProductModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveProduct(ProductModel product) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('products').upsert(product.toSupabaseMap());
    } catch (_) {}
  }

  Future<void> deleteProduct(String id) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('products').delete().eq('id', id);
    } catch (_) {}
  }

  Stream<List<ShelfRegionModel>> streamShelfRegions(String branch) {
    try {
      final client = _supabase;
      if (client == null) return const Stream.empty();

      return client
          .from('shelf_regions')
          .stream(primaryKey: ['id'])
          .eq('branch', branch)
          .map((data) {
        return data.map((row) => ShelfRegionModel.fromMap(row)).toList();
      }).handleError((_) => <ShelfRegionModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveShelfRegion(ShelfRegionModel region) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('shelf_regions').upsert(region.toSupabaseMap());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SETTINGS & CONFIG
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final client = _supabase;
      if (client != null) {
        final data = await client.from('system_settings').select().eq('key', 'global_config').maybeSingle();
        if (data != null && data['value'] != null) {
          return data;
        }
      }
    } catch (_) {}
    return {
      'captureSchedule': 'Every hour',
      'lowStockThreshold': 2,
      'roiBoundaries': [0.0, 0.25, 0.50, 0.75, 1.0],
      'roiTop': 0.15,
      'roiBottom': 0.85,
    };
  }

  Future<void> saveSystemSettings(Map<String, dynamic> settings) async {
    try {
      final client = _supabase;
      if (client == null) return;
      await client.from('system_settings').upsert({
        'key': 'global_config',
        'value': settings.toString(),
      });
    } catch (_) {}
  }
}
