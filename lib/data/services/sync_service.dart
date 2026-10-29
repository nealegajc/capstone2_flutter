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
import '../models/sale_record_model.dart';

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
  bool _isPullingLogs = false;
  bool _initialized = false;
  int _pendingCount = 0;
  DateTime? _lastSyncTime;
  String? _lastError;
  Timer? _autoSyncTimer;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  int get pendingCount => _pendingCount;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;

  String _toUtcIso(dynamic val) {
    if (val == null) return DateTime.now().toUtc().toIso8601String();
    if (val is DateTime) return val.toUtc().toIso8601String();
    if (val is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        val.toInt(),
        isUtc: false,
      ).toUtc().toIso8601String();
    }
    if (val is String) {
      final parsed = DateTime.tryParse(val);
      if (parsed != null) {
        return parsed.toUtc().toIso8601String();
      }
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  void initialize({bool enableAutoSync = true}) {
    if (_initialized) return;
    _initialized = true;

    _refreshPendingCount();
    _sqlite.getSetting('last_cloud_sync_timestamp').then((saved) {
      if (saved != null && saved.isNotEmpty) {
        _lastSyncTime = DateTime.tryParse(saved);
        notifyListeners();
      }
    });
    pullLatestSystemLogs();
    syncPendingQueue();
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
        final online = await checkSupabaseConnectivity();
        if (online) {
          _lastSyncTime = DateTime.now();
          pullLatestSystemLogs(limit: 50);
        }
        _isSyncing = false;
        notifyListeners();
        return online;
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
          if (operation == 'CLEAR_ALL' ||
              (operation == 'DELETE' && docId == 'all')) {
            if (targetCollection == 'system_logs') {
              final b = payload['branch'] as String? ?? 'San Pablo';
              await client.from('system_logs').delete().eq('branch', b);
            }
          } else if (operation == 'DELETE') {
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
                await client.from('system_settings').upsert({
                  'key': key,
                  'value': value,
                }, onConflict: 'key');
                break;

              case 'users':
                await client.from('users').upsert({
                  'uid': payload['id'] ?? payload['uid'] ?? docId,
                  'email': payload['email'] ?? 'admin@ottoscents.com',
                  'role': payload['role'] ?? 'staff',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'last_login': DateTime.now().toUtc().toIso8601String(),
                }, onConflict: 'uid');
                break;

              case 'products':
                await client.from('products').upsert({
                  'id': docId,
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'name': payload['name'] ?? '',
                  'brand': payload['brand'] ?? 'Otto Scents',
                  'category': payload['category'] ?? 'Men',
                  'bottle_size':
                      payload['bottleSize'] ?? payload['bottle_size'] ?? '50ml',
                  'shelf_layer':
                      payload['shelfLayer'] ??
                      payload['shelf_layer'] ??
                      'Layer A',
                  'slot_position':
                      (payload['slotPosition'] ??
                              payload['slot_position'] as num?)
                          ?.toInt() ??
                      1,
                  'price': (payload['price'] as num?)?.toDouble() ?? 0.0,
                  'status': payload['status'] ?? 'active',
                });
                break;

              case 'shelf_regions':
                await client.from('shelf_regions').upsert({
                  'id': docId,
                  'code': payload['code'] ?? '',
                  'assigned_product_id':
                      payload['assignedProductId'] ??
                      payload['assigned_product_id'],
                  'assigned_product_name':
                      payload['assignedProductName'] ??
                      payload['assigned_product_name'],
                  'branch': payload['branch'] ?? 'San Pablo',
                  'camera_id':
                      (payload['cameraId'] ?? payload['camera_id'] as num?)
                          ?.toInt() ??
                      1,
                  'camera_name':
                      payload['cameraName'] ??
                      payload['camera_name'] ??
                      'Camera 1A (Top Left)',
                  'layer_name':
                      payload['layerName'] ??
                      payload['layer_name'] ??
                      'Layer A (Top)',
                  'camera_position':
                      payload['cameraPosition'] ??
                      payload['camera_position'] ??
                      'left',
                  'device_node':
                      payload['deviceNode'] ??
                      payload['device_node'] ??
                      '/dev/video2',
                  'bottle_size':
                      payload['bottleSize'] ??
                      payload['bottle_size'] ??
                      '100ml',
                  'left_coord':
                      (payload['left_coord'] ?? payload['left'] as num?)
                          ?.toDouble() ??
                      0.0,
                  'right_coord':
                      (payload['right_coord'] ?? payload['right'] as num?)
                          ?.toDouble() ??
                      1.0,
                  'top_coord':
                      (payload['top_coord'] ?? payload['top'] as num?)
                          ?.toDouble() ??
                      0.0,
                  'bottom_coord':
                      (payload['bottom_coord'] ?? payload['bottom'] as num?)
                          ?.toDouble() ??
                      1.0,
                  'status': payload['status'] ?? 'active',
                });
                break;

              case 'system_logs':
                await client.from('system_logs').upsert({
                  'id': docId,
                  'type': payload['type'] ?? 'SYSTEM_EVENT',
                  'description':
                      payload['description'] ?? payload['desc'] ?? '',
                  'user': payload['user'] ?? 'Store Staff',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'timestamp': _toUtcIso(payload['timestamp']),
                });
                break;

              case 'inventory_events':
                await client.from('inventory_events').upsert({
                  'id': docId,
                  'event_type':
                      payload['eventType'] ??
                      payload['event_type'] ??
                      'RESTOCKED',
                  'product_name':
                      payload['productName'] ?? payload['product_name'] ?? '',
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'shelf_area':
                      payload['shelfArea'] ??
                      payload['shelf_area'] ??
                      'Layer A',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'quantity': (payload['quantity'] as num?)?.toInt() ?? 1,
                  'timestamp': _toUtcIso(payload['timestamp']),
                  'sync_status': 'synced',
                });
                break;

              case 'inventory_records':
                final luStr = _toUtcIso(
                  payload['lastUpdated'] ?? payload['last_updated'],
                );
                await client.from('inventory_records').upsert({
                  'id': docId,
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'name': payload['name'] ?? '',
                  'category': payload['category'] ?? 'Men',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'shelf':
                      payload['shelf'] ?? payload['shelfLayer'] ?? 'Layer A',
                  'recorded': (payload['recorded'] as num?)?.toInt() ?? 5,
                  'detected': (payload['detected'] as num?)?.toInt() ?? 5,
                  'status': payload['status'] ?? 'normal',
                  'misplacement_details':
                      payload['misplacementDetails'] ??
                      payload['misplacement_details'] ??
                      '',
                  'price': (payload['price'] as num?)?.toDouble() ?? 0.0,
                  'last_updated': luStr,
                });
                break;

              case 'alerts':
                await client.from('alerts').upsert({
                  'id': docId,
                  'title': payload['title'] ?? '',
                  'description':
                      payload['desc'] ?? payload['description'] ?? '',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'type': payload['type'] ?? 'notice',
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'is_read':
                      payload['isRead'] == 1 ||
                      payload['isRead'] == true ||
                      payload['is_read'] == true,
                  'created_at': _toUtcIso(
                    payload['createdAt'] ?? payload['created_at'],
                  ),
                });
                break;

              case 'image_quality_logs':
                await client.from('image_quality_logs').upsert({
                  'id': docId,
                  'brightness':
                      (payload['brightness'] as num?)?.toDouble() ?? 0.0,
                  'contrast': (payload['contrast'] as num?)?.toDouble() ?? 0.0,
                  'sharpness':
                      (payload['sharpness'] as num?)?.toDouble() ?? 0.0,
                  'is_acceptable':
                      payload['isAcceptable'] == 1 ||
                      payload['isAcceptable'] == true ||
                      payload['is_acceptable'] == true,
                  'preprocessing_applied':
                      payload['preprocessingApplied'] is String
                      ? jsonDecode(payload['preprocessingApplied'] as String)
                      : (payload['preprocessingApplied'] ??
                            payload['preprocessing_applied'] ??
                            []),
                  'retry_count':
                      (payload['retryCount'] ?? payload['retry_count'] as num?)
                          ?.toInt() ??
                      0,
                  'status': payload['status'] ?? 'ACCEPTED',
                  'branch': payload['branch'] ?? 'San Pablo',
                  'timestamp': _toUtcIso(payload['timestamp']),
                });
                break;

              case 'restock_records':
                await client.from('restock_records').upsert({
                  'id': docId,
                  'product_name':
                      payload['productName'] ?? payload['product_name'] ?? '',
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'quantity': (payload['quantity'] as num?)?.toInt() ?? 1,
                  'from_branch':
                      payload['fromBranch'] ?? payload['from_branch'] ?? '',
                  'to_branch':
                      payload['toBranch'] ??
                      payload['to_branch'] ??
                      'San Pablo',
                  'requested_by':
                      payload['requestedBy'] ??
                      payload['requested_by'] ??
                      'Store Staff',
                  'status': payload['status'] ?? 'pending',
                  'created_at': _toUtcIso(
                    payload['createdAt'] ?? payload['created_at'],
                  ),
                  'verified_at':
                      (payload['verifiedAt'] != null ||
                          payload['verified_at'] != null)
                      ? _toUtcIso(
                          payload['verifiedAt'] ?? payload['verified_at'],
                        )
                      : null,
                });
                break;

              case 'sales_records':
                final rawQty =
                    payload['quantitySold'] ??
                    payload['quantity_sold'] ??
                    payload['quantity'];
                final qty = (rawQty is num)
                    ? rawQty.toInt()
                    : (int.tryParse(rawQty?.toString() ?? '') ?? 1);
                final rawPrice =
                    payload['unitPrice'] ??
                    payload['unit_price'] ??
                    payload['price'];
                final price = (rawPrice is num)
                    ? rawPrice.toDouble()
                    : (double.tryParse(rawPrice?.toString() ?? '') ?? 260.0);
                final rawTotal =
                    payload['totalAmount'] ?? payload['total_amount'];
                final total = (rawTotal is num)
                    ? rawTotal.toDouble()
                    : (double.tryParse(rawTotal?.toString() ?? '') ??
                          (price * qty));

                await client.from('sales_records').upsert({
                  'id': docId,
                  'perfume_code':
                      payload['perfumeCode'] ?? payload['perfume_code'] ?? '',
                  'product_name':
                      payload['productName'] ?? payload['product_name'] ?? '',
                  'bottle_size':
                      payload['bottleSize'] ??
                      payload['bottle_size'] ??
                      '100ml',
                  'quantity_sold': qty,
                  'unit_price': price,
                  'total_amount': total,
                  'branch': payload['branch'] ?? 'San Pablo',
                  'sold_by': payload['soldBy'] ?? payload['sold_by'] ?? 'staff',
                  'sold_at': _toUtcIso(payload['soldAt'] ?? payload['sold_at']),
                  'sync_status': 'synced',
                });
                break;

              default:
                final Map<String, dynamic> genericPayload =
                    Map<String, dynamic>.from(payload);
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
          _lastError = _formatSupabaseError(e);
          final retryCount = (item['retryCount'] as num?)?.toInt() ?? 0;
          if (retryCount >= 5) {
            await _sqlite.markSyncItemStatus(id, 'failed');
          } else {
            await _sqlite.incrementSyncRetry(id, e.toString());
          }

          // If failure was caused by network connectivity loss, abort immediately
          // to preserve FIFO order and prevent exhausting retry budgets for all queued items
          if (_isNetworkException(e)) {
            debugPrint('[SyncService] Network dropped during queue sync. Halting queue loop.');
            break;
          }
        }
      }

      if (syncedCount > 0) {
        try {
          await _sqlite.logActivity(
            type: 'SYNC_COMPLETED',
            description:
                'Cloud sync complete: $syncedCount mutation(s) synchronized with Supabase.',
            enqueueSync: false,
          );
        } catch (_) {}
      }

      await _refreshPendingCount();
      _isOnline = true;
      _lastSyncTime = DateTime.now();
      _sqlite.setSystemSetting(
        'last_cloud_sync_timestamp',
        _lastSyncTime!.toIso8601String(),
        enqueueSync: false,
      );
      pullLatestSystemLogs(limit: 50);
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

  /// Pulls latest Supabase cloud data into local SQLite cache without echo re-enqueuing
  Future<void> pullRemoteData(String branch) async {
    final client = _supabase;
    if (client == null) return;

    try {
      // 1. Pull Products Catalog (pass enqueueSync: false to prevent mutation loop)
      final prodData = await client.from('products').select();
      for (final row in prodData) {
        final product = ProductModel.fromMap(row);
        await _sqlite.saveProduct(product, enqueueSync: false);
      }

      // 2. Pull Shelf Regions
      final roiData = await client
          .from('shelf_regions')
          .select()
          .eq('branch', branch);
      for (final row in roiData) {
        final region = ShelfRegionModel.fromMap(row);
        await _sqlite.updateShelfRegion(region, enqueueSync: false);
      }

      // 3. Pull Inventory Records
      final invData = await client
          .from('inventory_records')
          .select()
          .eq('branch', branch);
      for (final row in invData) {
        final record = InventoryRecordModel.fromMap(row);
        await _sqlite.upsertInventoryRecord(record, enqueueSync: false);
      }

      // 4. Pull Inventory Events
      final eventsData = await client
          .from('inventory_events')
          .select()
          .eq('branch', branch)
          .limit(50);
      for (final row in eventsData) {
        final event = InventoryEventModel.fromMap(row);
        await _sqlite.logInventoryEvent(event, enqueueSync: false);
      }

      // 5. Pull Alerts
      final alertsData = await client
          .from('alerts')
          .select()
          .eq('branch', branch)
          .limit(50);
      for (final row in alertsData) {
        final alert = AlertModel.fromMap(row);
        await _sqlite.insertAlert(alert, enqueueSync: false);
      }

      // 6. Pull System Settings (including PIN if present)
      final settingsData = await client.from('system_settings').select();
      for (final row in settingsData) {
        final k = row['key'] as String?;
        final v = row['value'];
        if (k != null && v != null) {
          await _sqlite.setSystemSetting(k, v, enqueueSync: false);
        }
      }

      // 7. Pull Restock Records
      final restockData = await client
          .from('restock_records')
          .select()
          .or('to_branch.eq.$branch,from_branch.eq.$branch')
          .limit(50);
      for (final row in restockData) {
        final restock = RestockRecordModel.fromMap(row);
        await _sqlite.saveRestockRecord(restock, enqueueSync: false);
      }

      // 8. Pull Image Quality Logs
      final iqData = await client
          .from('image_quality_logs')
          .select()
          .eq('branch', branch)
          .limit(50);
      for (final row in iqData) {
        final iq = ImageQualityLogModel.fromMap(row);
        await _sqlite.logImageQuality(iq, enqueueSync: false);
      }

      // 9. Pull System Logs (newest logs ordered descending)
      final logsData = await client
          .from('system_logs')
          .select()
          .order('timestamp', ascending: false)
          .limit(200);
      final List<SystemLogModel> logs = (logsData as List)
          .map((row) => SystemLogModel.fromMap(row as Map<String, dynamic>))
          .toList();
      await _sqlite.upsertSystemLogsFromCloud(logs);

      // 10. Pull Sales Records
      final salesData = await client
          .from('sales_records')
          .select()
          .eq('branch', branch)
          .limit(100);
      for (final row in salesData) {
        final sale = SaleRecordModel.fromMap(row);
        await _sqlite.insertSaleRecord(sale, enqueueSync: false);
      }

      _isOnline = true;
      _lastSyncTime = DateTime.now();
      _lastError = null;
      notifyListeners();
    } catch (e) {
      _isOnline = false;
      _lastError = _formatSupabaseError(e);
      notifyListeners();
    }
  }

  /// Pulls the latest system audit logs from Supabase Cloud ordered descending by timestamp
  Future<int> pullLatestSystemLogs({int limit = 200}) async {
    if (_isPullingLogs) return 0;
    _isPullingLogs = true;
    final client = _supabase;
    if (client == null) {
      _isPullingLogs = false;
      return 0;
    }
    try {
      final logsData = await client
          .from('system_logs')
          .select()
          .order('timestamp', ascending: false)
          .limit(limit);

      final List<SystemLogModel> logs = (logsData as List)
          .map((row) => SystemLogModel.fromMap(row as Map<String, dynamic>))
          .toList();

      await _sqlite.upsertSystemLogsFromCloud(logs);
      return logs.length;
    } catch (_) {
      return 0;
    } finally {
      _isPullingLogs = false;
    }
  }

  /// Verifies whether Supabase Cloud is reachable with an active project
  Future<bool> checkSupabaseConnectivity({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final client = _supabase;
    if (client == null) {
      _isOnline = false;
      _lastError = 'Supabase client is not initialized.';
      notifyListeners();
      return false;
    }
    try {
      await client.from('products').select('id').limit(1).timeout(timeout);
      _isOnline = true;
      _lastError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _isOnline = false;
      _lastError = _formatSupabaseError(e);
      notifyListeners();
      return false;
    }
  }

  bool _isNetworkException(dynamic e) {
    final str = e.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('timeoutexception') ||
        str.contains('clientexception') ||
        str.contains('failed host lookup') ||
        str.contains('connection refused') ||
        str.contains('network is unreachable') ||
        str.contains('handshakeexception');
  }

  /// Formats raw Supabase / HTTP errors into clear, actionable messages
  String _formatSupabaseError(dynamic e) {
    final str = e.toString();
    if (_isNetworkException(e)) {
      return 'Supabase Cloud is unreachable ($str). If you are using Supabase Free Tier, the project may be paused due to inactivity. Please visit https://supabase.com/dashboard to unpause it.';
    }
    return str;
  }

  /// Uploads all local SQLite records (products, shelf regions, inventory, sales, restocks, system logs, settings)
  /// directly to Supabase cloud. Throws an exception if Supabase is unreachable.
  Future<Map<String, int>> pushFullBackupToSupabase({
    String branch = 'San Pablo',
  }) async {
    final client = _supabase;
    if (client == null) {
      _isOnline = false;
      _lastError = 'Supabase client is not initialized.';
      notifyListeners();
      throw Exception(_lastError);
    }

    _isSyncing = true;
    _lastError = null;
    notifyListeners();

    try {
      // 1. Pre-flight connectivity check to verify host is up
      final isUp = await checkSupabaseConnectivity();
      if (!isUp) {
        throw Exception(_lastError ?? 'Supabase Cloud unreachable.');
      }

      final Map<String, int> stats = {};

      // 2. Backup Products Catalog (all 60 SKUs)
      final products = await _sqlite.getAllProducts();
      if (products.isNotEmpty) {
        final List<Map<String, dynamic>> prodMaps = products
            .map((p) => p.toSupabaseMap())
            .toList();
        for (var i = 0; i < prodMaps.length; i += 50) {
          final end = (i + 50 < prodMaps.length) ? i + 50 : prodMaps.length;
          await client
              .from('products')
              .upsert(prodMaps.sublist(i, end), onConflict: 'id');
        }
        stats['products'] = products.length;
      }

      // 3. Backup Shelf Regions
      final regions = await _sqlite.getShelfRegions(branch);
      if (regions.isNotEmpty) {
        final List<Map<String, dynamic>> regMaps = regions
            .map((r) => r.toSupabaseMap())
            .toList();
        for (var i = 0; i < regMaps.length; i += 50) {
          final end = (i + 50 < regMaps.length) ? i + 50 : regMaps.length;
          await client
              .from('shelf_regions')
              .upsert(regMaps.sublist(i, end), onConflict: 'id');
        }
        stats['shelf_regions'] = regions.length;
      }

      // 4. Backup Inventory Records
      final inventory = await _sqlite.getInventory(branch);
      if (inventory.isNotEmpty) {
        final List<Map<String, dynamic>> invMaps = inventory
            .map((inv) => inv.toSupabaseMap())
            .toList();
        for (var i = 0; i < invMaps.length; i += 50) {
          final end = (i + 50 < invMaps.length) ? i + 50 : invMaps.length;
          await client
              .from('inventory_records')
              .upsert(invMaps.sublist(i, end), onConflict: 'id');
        }
        stats['inventory_records'] = inventory.length;
      }

      // 5. Backup Sales Records
      final sales = await _sqlite.getSalesRecords(branch, limit: 1000);
      if (sales.isNotEmpty) {
        final List<Map<String, dynamic>> saleMaps = sales
            .map((s) => s.toSupabaseMap())
            .toList();
        for (var i = 0; i < saleMaps.length; i += 50) {
          final end = (i + 50 < saleMaps.length) ? i + 50 : saleMaps.length;
          await client
              .from('sales_records')
              .upsert(saleMaps.sublist(i, end), onConflict: 'id');
        }
        stats['sales_records'] = sales.length;
      }

      // 6. Backup Restock Records
      final restocks = await _sqlite.getRestockRecords(branch);
      if (restocks.isNotEmpty) {
        final List<Map<String, dynamic>> restockMaps = restocks
            .map((r) => r.toSupabaseMap())
            .toList();
        for (var i = 0; i < restockMaps.length; i += 50) {
          final end = (i + 50 < restockMaps.length)
              ? i + 50
              : restockMaps.length;
          await client
              .from('restock_records')
              .upsert(restockMaps.sublist(i, end), onConflict: 'id');
        }
        stats['restock_records'] = restocks.length;
      }

      // 7. Backup System Logs
      final logs = await _sqlite.getSystemLogs(branch, limit: 500);
      if (logs.isNotEmpty) {
        final List<Map<String, dynamic>> logMaps = logs
            .map((l) => l.toSupabaseMap())
            .toList();
        for (var i = 0; i < logMaps.length; i += 50) {
          final end = (i + 50 < logMaps.length) ? i + 50 : logMaps.length;
          await client
              .from('system_logs')
              .upsert(logMaps.sublist(i, end), onConflict: 'id');
        }
        stats['system_logs'] = logs.length;
      }

      // 8. Backup System Settings (including PIN and configuration)
      final settings = await _sqlite.getSystemSettings();
      if (settings.isNotEmpty) {
        final List<Map<String, dynamic>> settingMaps = settings.entries
            .map((e) => {'key': e.key, 'value': e.value?.toString() ?? ''})
            .toList();
        await client
            .from('system_settings')
            .upsert(settingMaps, onConflict: 'key');
        stats['system_settings'] = settingMaps.length;
      }

      // 9. Clear and purge pending sync queue items since all tables are freshly backed up
      final pending = await _sqlite.getPendingSyncItems();
      for (final item in pending) {
        final id = item['id'] as String;
        await _sqlite.markSyncItemStatus(id, 'synced');
      }
      await _sqlite.purgeSyncedQueueItems();

      final totalCount = stats.values.fold<int>(0, (sum, count) => sum + count);

      await _sqlite.logActivity(
        type: 'CLOUD_BACKUP_COMPLETED',
        description:
            'Full cloud backup completed: $totalCount records uploaded to Supabase across ${stats.length} tables.',
        enqueueSync: false,
      );

      await _refreshPendingCount();
      _isOnline = true;
      _lastSyncTime = DateTime.now();
      await _sqlite.setSystemSetting(
        'last_cloud_sync_timestamp',
        _lastSyncTime!.toIso8601String(),
        enqueueSync: false,
      );
      _lastError = null;
      _isSyncing = false;
      notifyListeners();

      return stats;
    } catch (e) {
      _isOnline = false;
      _lastError = _formatSupabaseError(e);
      try {
        await _sqlite.logActivity(
          type: 'CLOUD_BACKUP_FAILED',
          description: 'Cloud backup failed: ${_lastError ?? e.toString()}',
          enqueueSync: false,
        );
      } catch (_) {}
      _isSyncing = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Manually requested Force Sync from UI: pushes full backup to cloud, then pulls remote modifications
  Future<Map<String, int>> forceSyncNow(String branch) async {
    final stats = await pushFullBackupToSupabase(branch: branch);
    try {
      await pullRemoteData(branch);
    } catch (_) {}
    await _refreshPendingCount();
    return stats;
  }
}
