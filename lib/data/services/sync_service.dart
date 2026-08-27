import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'sqlite_service.dart';
import '../models/inventory_record_model.dart';
import '../models/inventory_event_model.dart';
import '../models/alert_model.dart';
import '../models/product_model.dart';
import '../models/shelf_region_model.dart';
import '../models/system_log_model.dart';
import '../models/image_quality_log_model.dart';
import '../models/restock_record_model.dart';

class SyncService extends ChangeNotifier {
  static SyncService? _instance;
  static SyncService get instance => _instance ??= SyncService._();

  SyncService._();

  final SqliteService _sqlite = SqliteService.instance;

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

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
      _autoSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) {
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

  /// Triggers full sync of local pending SQLite queue to Supabase Cloud Database
  Future<bool> syncPendingQueue() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    final client = _supabase;
    if (client == null) {
      _isOnline = false;
      _lastError = 'Supabase client is not initialized.';
      _isSyncing = false;
      notifyListeners();
      return false;
    }

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

      int syncedCount = 0;
      for (final item in pendingItems) {
        final id = item['id'] as String;
        final targetCollection = item['targetCollection'] as String;
        final operation = item['operation'] as String? ?? 'UPSERT';
        final payloadStr = item['payload'] as String;
        final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
        final docId = item['pendingEventId'] as String;

        try {
          if (operation == 'DELETE') {
            if (targetCollection == 'system_settings') {
              await client.from('system_settings').delete().eq('key', docId);
            } else if (targetCollection == 'users') {
              await client.from('users').delete().eq('uid', docId);
            } else {
              await client.from(targetCollection).delete().eq('id', docId);
            }
          } else {
            // Precise Table-Aware Mapping to Supabase Cloud Schema
            switch (targetCollection) {
              case 'system_settings':
                final key = payload['key'] as String? ?? docId;
                final value = payload['value']?.toString() ?? '';
                await client.from('system_settings').upsert(
                  {
                    'key': key,
                    'value': value,
                  },
                  onConflict: 'key',
                );
                break;

              case 'users':
                await client.from('users').upsert(
                  {
                    'uid': payload['id'] ?? payload['uid'] ?? docId,
                    'email': payload['email'] ?? 'admin@ottoscents.com',
                    'role': payload['role'] ?? 'owner',
                    'branch': payload['branch'] ?? 'San Pablo',
                    'last_login': DateTime.now().toIso8601String(),
                  },
                  onConflict: 'uid',
                );
                break;

              case 'products':
                await client.from('products').upsert({
                  'id': docId,
                  'perfume_code': payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'name': payload['name'] ?? '',
                  'brand': payload['brand'] ?? 'Otto Scents',
                  'category': payload['category'] ?? 'Men',
                  'bottle_size': payload['bottleSize'] ?? payload['bottle_size'] ?? '50ml',
                  'price': payload['price'] ?? 0.0,
                  'status': payload['status'] ?? 'active',
                });
                break;

              case 'shelf_regions':
                await client.from('shelf_regions').upsert({
                  'id': docId,
                  'code': payload['code'] ?? '',
                  'assigned_product_id': payload['assignedProductId'] ?? payload['assigned_product_id'],
                  'assigned_product_name': payload['assignedProductName'] ?? payload['assigned_product_name'],
                  'branch': payload['branch'] ?? 'San Pablo',
                  'left_coord': (payload['left_coord'] ?? payload['left'] as num?)?.toDouble() ?? 0.0,
                  'right_coord': (payload['right_coord'] ?? payload['right'] as num?)?.toDouble() ?? 1.0,
                  'top_coord': (payload['top_coord'] ?? payload['top'] as num?)?.toDouble() ?? 0.0,
                  'bottom_coord': (payload['bottom_coord'] ?? payload['bottom'] as num?)?.toDouble() ?? 1.0,
                  'status': payload['status'] ?? 'active',
                });
                break;

              case 'system_logs':
                await client.from('system_logs').upsert({
                  'id': docId,
                  'type': payload['type'] ?? 'SYSTEM_EVENT',
                  'description': payload['description'] ?? payload['desc'] ?? '',
                  'user': payload['user'] ?? 'Store Owner',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'timestamp': payload['timestamp'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(payload['timestamp'] as int).toIso8601String()
                      : (payload['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
                });
                break;

              case 'inventory_events':
                await client.from('inventory_events').upsert({
                  'id': docId,
                  'event_type': payload['eventType'] ?? payload['event_type'] ?? 'RESTOCKED',
                  'product_name': payload['productName'] ?? payload['product_name'] ?? '',
                  'perfume_code': payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'shelf_area': payload['shelfArea'] ?? payload['shelf_area'] ?? 'Layer A',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'quantity': payload['quantity'] ?? 1,
                  'timestamp': payload['timestamp'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(payload['timestamp'] as int).toIso8601String()
                      : (payload['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
                  'sync_status': 'synced',
                });
                break;

              case 'inventory_records':
                await client.from('inventory_records').upsert({
                  'id': docId,
                  'perfume_code': payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'name': payload['name'] ?? '',
                  'category': payload['category'] ?? 'Men',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'shelf': payload['shelf'] ?? payload['shelfLayer'] ?? 'Layer A',
                  'recorded': payload['recorded'] ?? 5,
                  'detected': payload['detected'] ?? 5,
                  'status': payload['status'] ?? 'normal',
                  'misplacement_details': payload['misplacementDetails'] ?? payload['misplacement_details'] ?? '',
                  'price': payload['price'] ?? 0.0,
                  'last_updated': DateTime.now().toIso8601String(),
                });
                break;

              case 'alerts':
                await client.from('alerts').upsert({
                  'id': docId,
                  'title': payload['title'] ?? '',
                  'description': payload['desc'] ?? payload['description'] ?? '',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'type': payload['type'] ?? 'notice',
                  'perfume_code': payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'is_read': payload['isRead'] == 1 || payload['isRead'] == true || payload['is_read'] == true,
                  'created_at': payload['createdAt'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(payload['createdAt'] as int).toIso8601String()
                      : (payload['created_at']?.toString() ?? DateTime.now().toIso8601String()),
                });
                break;

              case 'image_quality_logs':
                await client.from('image_quality_logs').upsert({
                  'id': docId,
                  'brightness': (payload['brightness'] as num?)?.toDouble() ?? 0.0,
                  'contrast': (payload['contrast'] as num?)?.toDouble() ?? 0.0,
                  'sharpness': (payload['sharpness'] as num?)?.toDouble() ?? 0.0,
                  'is_acceptable': payload['isAcceptable'] == 1 || payload['isAcceptable'] == true || payload['is_acceptable'] == true,
                  'preprocessing_applied': payload['preprocessingApplied'] is String
                      ? jsonDecode(payload['preprocessingApplied'] as String)
                      : (payload['preprocessingApplied'] ?? payload['preprocessing_applied'] ?? []),
                  'retry_count': (payload['retryCount'] ?? payload['retry_count'] as num?)?.toInt() ?? 0,
                  'status': payload['status'] ?? 'ACCEPTED',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'timestamp': payload['timestamp'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(payload['timestamp'] as int).toIso8601String()
                      : (payload['timestamp']?.toString() ?? DateTime.now().toIso8601String()),
                });
                break;

              case 'restock_records':
                await client.from('restock_records').upsert({
                  'id': docId,
                  'product_name': payload['productName'] ?? payload['product_name'] ?? '',
                  'perfume_code': payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'quantity': (payload['quantity'] as num?)?.toInt() ?? 1,
                  'from_branch': payload['fromBranch'] ?? payload['from_branch'] ?? '',
                  'to_branch': payload['toBranch'] ?? payload['to_branch'] ?? 'San Pablo',
                  'requested_by': payload['requestedBy'] ?? payload['requested_by'] ?? 'Store Owner',
                  'status': payload['status'] ?? 'pending',
                  'created_at': payload['createdAt'] is int
                      ? DateTime.fromMillisecondsSinceEpoch(payload['createdAt'] as int).toIso8601String()
                      : (payload['created_at']?.toString() ?? DateTime.now().toIso8601String()),
                  'verified_at': payload['verifiedAt'] != null || payload['verified_at'] != null
                      ? (payload['verifiedAt'] is int
                          ? DateTime.fromMillisecondsSinceEpoch(payload['verifiedAt'] as int).toIso8601String()
                          : (payload['verifiedAt'] ?? payload['verified_at']).toString())
                      : null,
                });
                break;

              default:
                final Map<String, dynamic> genericPayload = Map<String, dynamic>.from(payload);
                if (!genericPayload.containsKey('id')) {
                  genericPayload['id'] = docId;
                }
                await client.from(targetCollection).upsert(genericPayload);
                break;
            }
          }

          await _sqlite.markSyncItemStatus(id, 'synced');
          syncedCount++;
        } catch (e) {
          _isOnline = false;
          _lastError = e.toString();
          await _sqlite.incrementSyncRetry(id, e.toString());
        }
      }

      if (syncedCount > 0) {
        try {
          await _sqlite.logActivity(
            type: 'SYNC_COMPLETED',
            description: 'Cloud sync complete: $syncedCount mutation(s) synchronized with Supabase.',
          );
        } catch (_) {}
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

  /// Pulls latest Supabase cloud data into local SQLite cache
  Future<void> pullRemoteData(String branch) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // 1. Pull Products Catalog
      final prodData = await client.from('products').select();
      for (final row in prodData) {
        final product = ProductModel.fromMap(row);
        await _sqlite.saveProduct(product);
      }

      // 2. Pull Shelf Regions
      final roiData = await client.from('shelf_regions').select().eq('branch', branch);
      for (final row in roiData) {
        final region = ShelfRegionModel.fromMap(row);
        await _sqlite.updateShelfRegion(region);
      }

      // 3. Pull Inventory Records
      final invData = await client.from('inventory_records').select().eq('branch', branch);
      for (final row in invData) {
        final record = InventoryRecordModel.fromMap(row);
        await _sqlite.upsertInventoryRecord(record);
      }

      // 4. Pull Inventory Events
      final eventsData = await client.from('inventory_events').select().eq('branch', branch).limit(50);
      for (final row in eventsData) {
        final event = InventoryEventModel.fromMap(row);
        await _sqlite.logInventoryEvent(event);
      }

      // 5. Pull Alerts
      final alertsData = await client.from('alerts').select().eq('branch', branch).limit(50);
      for (final row in alertsData) {
        final alert = AlertModel.fromMap(row);
        await _sqlite.insertAlert(alert);
      }

      // 6. Pull System Settings (including PIN if present)
      final settingsData = await client.from('system_settings').select();
      for (final row in settingsData) {
        final k = row['key'] as String?;
        final v = row['value'];
        if (k != null && v != null) {
          await _sqlite.setSystemSetting(k, v);
        }
      }

      // 7. Pull Restock Records
      final restockData = await client.from('restock_records').select().or('to_branch.eq.$branch,from_branch.eq.$branch').limit(50);
      for (final row in restockData) {
        final restock = RestockRecordModel.fromMap(row);
        await _sqlite.saveRestockRecord(restock);
      }

      // 8. Pull Image Quality Logs
      final iqData = await client.from('image_quality_logs').select().eq('branch', branch).limit(50);
      for (final row in iqData) {
        final iq = ImageQualityLogModel.fromMap(row);
        await _sqlite.logImageQuality(iq);
      }

      // 9. Pull System Logs
      final logsData = await client.from('system_logs').select().eq('branch', branch).limit(50);
      for (final row in logsData) {
        final log = SystemLogModel.fromMap(row);
        await _sqlite.logSystemActivity(log);
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
