import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'sqlite_service.dart';
import '../models/inventory_record_model.dart';
import '../models/alert_model.dart';

class SyncService extends ChangeNotifier {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();

  SyncService._();

  final SqliteService _sqlite = SqliteService.instance;

  bool _isOnline = true;
  bool _isSyncing = false;
  int _pendingCount = 0;
  DateTime? _lastSyncTime;
  String? _lastError;
  Timer? _autoSyncTimer;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;

  void initialize({bool enableAutoSync = true}) {
    _refreshPendingCount();
    _autoSyncTimer?.cancel();
    if (enableAutoSync) {
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (!_isSyncing) {
          syncPendingQueue();
        }
      });
    }
  }

  void stop() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    try {
      final pending = await _sqlite.getPendingSyncItems();
      _pendingCount = pending.length;
      notifyListeners();
    } catch (_) {}
  }

  /// Triggers full sync of local pending SQLite queue to Cloud Firestore
  Future<bool> syncPendingQueue() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      final pendingItems = await _sqlite.getPendingSyncItems();
      _pendingCount = pendingItems.length;

      if (pendingItems.isEmpty) {
        _isOnline = true;
        _lastSyncTime = DateTime.now();
        _isSyncing = false;
        notifyListeners();
        return true;
      }

      for (final item in pendingItems) {
        final id = item['id'] as String;
        final targetCollection = item['targetCollection'] as String;
        final operation = item['operation'] as String? ?? 'UPSERT';
        final payloadStr = item['payload'] as String;
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

        try {
          final firestore = FirebaseFirestore.instance;
          final docId = item['pendingEventId'] as String;

          if (operation == 'DELETE') {
            await firestore.collection(targetCollection).doc(docId).delete();
          } else {
            await firestore.collection(targetCollection).doc(docId).set(payload, SetOptions(merge: true));
          }

          await _sqlite.markSyncItemStatus(id, 'synced');
        } catch (e) {
          _isOnline = false;
          _lastError = e.toString();
          await _sqlite.incrementSyncRetry(id, e.toString());
        }
      }

      await _refreshPendingCount();
      _isOnline = true;
      _lastSyncTime = DateTime.now();
      _isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isOnline = false;
      _lastError = e.toString();
      _isSyncing = false;
      notifyListeners();
      return false;
    }
  }

  /// Pulls latest Cloud Firestore data into local SQLite cache
  Future<void> pullRemoteData(String branch) async {
    try {
      final firestore = FirebaseFirestore.instance;

      // 1. Pull Inventory Records
      final invSnapshot = await firestore
          .collection('inventory_records')
          .where('branch', isEqualTo: branch)
          .get();

      for (final doc in invSnapshot.docs) {
        final record = InventoryRecordModel.fromFirestore(doc);
        await _sqlite.upsertInventoryRecord(record);
      }

      // 2. Pull Alerts
      final alertsSnapshot = await firestore
          .collection('alerts')
          .where('branch', isEqualTo: branch)
          .limit(50)
          .get();

      for (final doc in alertsSnapshot.docs) {
        final alert = AlertModel.fromFirestore(doc);
        await _sqlite.insertAlert(alert);
      }

      _isOnline = true;
      _lastSyncTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
    }
  }

  /// Manually requested Force Sync from UI
  Future<void> forceSyncNow(String branch) async {
    await syncPendingQueue();
    await pullRemoteData(branch);
    await _refreshPendingCount();
  }
}
