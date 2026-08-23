import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/inventory_record_model.dart';
import '../models/alert_model.dart';
import '../models/inventory_event_model.dart';
import '../models/system_log_model.dart';
import '../models/restock_record_model.dart';
import '../models/sync_queue_model.dart';
import '../models/shelf_region_model.dart';

class FirestoreRepository {
  FirebaseFirestore? _safeFirestore;
  FirebaseFirestore? get _firestore {
    try {
      return _safeFirestore ??= FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // INVENTORY RECORDS
  // ---------------------------------------------------------------------------
  Stream<List<InventoryRecordModel>> streamInventory(String? branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      Query<Map<String, dynamic>> query = fs.collection('inventory_records');
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.where('branch', isEqualTo: branch);
      }
      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => InventoryRecordModel.fromFirestore(doc)).toList();
      }).handleError((_) => <InventoryRecordModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveInventoryRecord(InventoryRecordModel item) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs
          .collection('inventory_records')
          .doc(item.id.isEmpty ? null : item.id)
          .set(item.toMap(), SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> deleteInventoryRecord(String id) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('inventory_records').doc(id).delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // ALERTS
  // ---------------------------------------------------------------------------
  Stream<List<AlertModel>> streamAlerts(String? branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      Query<Map<String, dynamic>> query = fs.collection('alerts');
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.where('branch', isEqualTo: branch);
      }
      return query.snapshots().map((snapshot) {
        final list = snapshot.docs.map((doc) => AlertModel.fromFirestore(doc)).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      }).handleError((_) => <AlertModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> saveAlert(AlertModel alert) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('alerts').doc(alert.id.isEmpty ? null : alert.id).set(alert.toMap());
    } catch (_) {}
  }

  Future<void> markAlertRead(String id) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('alerts').doc(id).update({'isRead': true});
    } catch (_) {}
  }

  Future<void> markAllAlertsRead(List<String> ids) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      final batch = fs.batch();
      for (final id in ids) {
        batch.update(fs.collection('alerts').doc(id), {'isRead': true});
      }
      await batch.commit();
    } catch (_) {}
  }

  Future<void> deleteAlert(String id) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('alerts').doc(id).delete();
    } catch (_) {}
  }

  Future<void> deleteAllReadAlerts(List<String> readIds) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      final batch = fs.batch();
      for (final id in readIds) {
        batch.delete(fs.collection('alerts').doc(id));
      }
      await batch.commit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // INVENTORY EVENTS (MOVEMENT LOGS)
  // ---------------------------------------------------------------------------
  Stream<List<InventoryEventModel>> streamInventoryEvents(String? branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      Query<Map<String, dynamic>> query = fs.collection('inventory_events');
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.where('branch', isEqualTo: branch);
      }
      return query.snapshots().map((snapshot) {
        final list = snapshot.docs.map((doc) => InventoryEventModel.fromFirestore(doc)).toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      }).handleError((_) => <InventoryEventModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> logInventoryEvent(InventoryEventModel event) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('inventory_events').doc(event.id.isEmpty ? null : event.id).set(event.toMap());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SYSTEM LOGS
  // ---------------------------------------------------------------------------
  Stream<List<SystemLogModel>> streamSystemLogs(String? branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      Query<Map<String, dynamic>> query = fs.collection('system_logs');
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.where('branch', isEqualTo: branch);
      }
      return query.snapshots().map((snapshot) {
        final list = snapshot.docs.map((doc) => SystemLogModel.fromFirestore(doc)).toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      }).handleError((_) => <SystemLogModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> logSystemActivity(SystemLogModel log) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('system_logs').doc(log.id.isEmpty ? null : log.id).set(log.toMap());
    } catch (_) {}
  }

  Future<void> deleteSystemLog(String id) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('system_logs').doc(id).delete();
    } catch (_) {}
  }

  Future<void> deleteAllSystemLogs(List<String> ids) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      final batch = fs.batch();
      for (final id in ids) {
        batch.delete(fs.collection('system_logs').doc(id));
      }
      await batch.commit();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SYNC QUEUE
  // ---------------------------------------------------------------------------
  Stream<List<SyncQueueModel>> streamSyncQueue(String? branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      Query<Map<String, dynamic>> query = fs.collection('sync_queue');
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        query = query.where('branch', isEqualTo: branch);
      }
      return query.snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => SyncQueueModel.fromFirestore(doc)).toList();
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
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      return fs.collection('restock_records').snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => RestockRecordModel.fromFirestore(doc)).toList();
      }).handleError((_) => <RestockRecordModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  Future<void> createRestockRequest(RestockRecordModel restock) async {
    try {
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('restock_records').doc(restock.id.isEmpty ? null : restock.id).set(restock.toMap());
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SHELF REGIONS & PRODUCTS
  // ---------------------------------------------------------------------------
  Stream<List<ShelfRegionModel>> streamShelfRegions(String branch) {
    try {
      final fs = _firestore;
      if (fs == null) return const Stream.empty();

      return fs
          .collection('shelf_regions')
          .where('branch', isEqualTo: branch)
          .snapshots()
          .map((snapshot) {
        return snapshot.docs.map((doc) => ShelfRegionModel.fromFirestore(doc)).toList();
      }).handleError((_) => <ShelfRegionModel>[]);
    } catch (_) {
      return const Stream.empty();
    }
  }

  // ---------------------------------------------------------------------------
  // SETTINGS & CONFIG
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getSystemSettings() async {
    try {
      final fs = _firestore;
      if (fs != null) {
        final doc = await fs.collection('settings').doc('global_config').get();
        if (doc.exists && doc.data() != null) {
          return doc.data()!;
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
      final fs = _firestore;
      if (fs == null) return;
      await fs.collection('settings').doc('global_config').set(settings, SetOptions(merge: true));
    } catch (_) {}
  }
}
