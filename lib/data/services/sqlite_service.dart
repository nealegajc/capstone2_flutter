import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/inventory_record_model.dart';
import '../models/product_model.dart';
import '../models/shelf_region_model.dart';
import '../models/inventory_event_model.dart';
import '../models/alert_model.dart';
import '../models/system_log_model.dart';
import '../models/sync_queue_model.dart';
import '../models/user_model.dart';

class SqliteService {
  static SqliteService? _instance;
  static SqliteService get instance => _instance ??= SqliteService._();

  SqliteService._();

  Database? _db;

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    return await initialize();
  }

  Future<Database> initDatabase({bool inMemory = false, String? customPath}) =>
      initialize(inMemory: inMemory, customPath: customPath);

  Future<Database> initialize({bool inMemory = false, String? customPath}) async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }

    String dbPath;
    if (inMemory) {
      dbPath = inMemoryDatabasePath;
    } else if (customPath != null) {
      dbPath = customPath;
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      final dir = Directory(p.join(appSupportDir.path, 'smart_shelf'));
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      dbPath = p.join(dir.path, 'smart_shelf_local.db');
    }

    final db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: _onCreate,
        onOpen: _onOpen,
      ),
    );

    _db = db;
    return db;
  }

  Future<void> _onOpen(Database db) async {
    await _ensureUsersTable(db);
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await _seedInitialUsersIfEmpty(db);
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();

    // 1. Products Catalog Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        perfumeCode TEXT NOT NULL,
        name TEXT NOT NULL,
        brand TEXT,
        category TEXT,
        bottleSize TEXT,
        price REAL NOT NULL DEFAULT 250.0,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');

    // 2. Shelf Regions (ROI) Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS shelf_regions (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL,
        assignedProductId TEXT,
        assignedProductName TEXT,
        branch TEXT NOT NULL,
        left_coord REAL NOT NULL,
        right_coord REAL NOT NULL,
        top_coord REAL NOT NULL DEFAULT 0.15,
        bottom_coord REAL NOT NULL DEFAULT 0.85,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');

    // 3. Current Inventory Records Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS inventory_records (
        id TEXT PRIMARY KEY,
        perfumeCode TEXT NOT NULL,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT 'Men',
        branch TEXT NOT NULL,
        shelf TEXT NOT NULL,
        recorded INTEGER NOT NULL DEFAULT 5,
        detected INTEGER NOT NULL DEFAULT 5,
        status TEXT NOT NULL DEFAULT 'normal',
        misplacementDetails TEXT NOT NULL DEFAULT '',
        price REAL NOT NULL DEFAULT 250.0,
        lastUpdated INTEGER NOT NULL
      )
    ''');

    // 4. Inventory Events (Audit Log) Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS inventory_events (
        id TEXT PRIMARY KEY,
        eventType TEXT NOT NULL,
        productName TEXT NOT NULL,
        perfumeCode TEXT NOT NULL,
        shelfArea TEXT NOT NULL,
        branch TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        timestamp INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    // 5. Sync Queue Table (Offline Mutation Queue)
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        pendingEventId TEXT,
        targetCollection TEXT NOT NULL,
        operation TEXT NOT NULL DEFAULT 'UPSERT',
        payload TEXT NOT NULL DEFAULT '{}',
        retryCount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        errorStatus TEXT,
        branch TEXT NOT NULL,
        createdAt INTEGER NOT NULL,
        lastAttempt INTEGER
      )
    ''');

    // 6. Alert Notifications Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS alerts (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        desc TEXT NOT NULL,
        branch TEXT NOT NULL,
        type TEXT NOT NULL,
        perfumeCode TEXT,
        isRead INTEGER NOT NULL DEFAULT 0,
        createdAt INTEGER NOT NULL
      )
    ''');

    // 7. System Activity Logs Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS system_logs (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        description TEXT NOT NULL,
        user TEXT NOT NULL,
        branch TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // 8. Image Quality Logs Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS image_quality_logs (
        id TEXT PRIMARY KEY,
        brightness REAL NOT NULL,
        contrast REAL NOT NULL,
        sharpness REAL NOT NULL,
        isAcceptable INTEGER NOT NULL DEFAULT 1,
        preprocessingApplied TEXT NOT NULL DEFAULT '[]',
        retryCount INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'ACCEPTED',
        branch TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');

    // 9. Inter-Branch Restock Records Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS restock_records (
        id TEXT PRIMARY KEY,
        productName TEXT NOT NULL,
        perfumeCode TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        fromBranch TEXT NOT NULL,
        toBranch TEXT NOT NULL,
        requestedBy TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        createdAt INTEGER NOT NULL,
        verifiedAt INTEGER
      )
    ''');

    // 10. System Settings Key-Value Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 11. Local Users Table with Password Hashes
    batch.execute('''
      CREATE TABLE IF NOT EXISTS users (
        uid TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        passwordHash TEXT NOT NULL DEFAULT '',
        role TEXT NOT NULL DEFAULT 'staff',
        branch TEXT NOT NULL DEFAULT 'San Pablo',
        lastLogin INTEGER NOT NULL
      )
    ''');

    await batch.commit(noResult: true);
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

    // Seed Master Products
    final products = [
      {'id': 'prod_A', 'perfumeCode': 'A', 'name': 'Otto Scents Ocean Breeze', 'brand': 'Otto Scents', 'category': 'Men', 'bottleSize': '50ml', 'price': 250.0, 'status': 'active'},
      {'id': 'prod_B', 'perfumeCode': 'B', 'name': 'Otto Scents Velvet Rose', 'brand': 'Otto Scents', 'category': 'Women', 'bottleSize': '50ml', 'price': 250.0, 'status': 'active'},
      {'id': 'prod_C', 'perfumeCode': 'C', 'name': 'Otto Scents Vanilla Musk', 'brand': 'Otto Scents', 'category': 'Unisex', 'bottleSize': '50ml', 'price': 250.0, 'status': 'active'},
      {'id': 'prod_D', 'perfumeCode': 'D', 'name': 'Otto Scents Citrus Blossom', 'brand': 'Otto Scents', 'category': 'Women', 'bottleSize': '50ml', 'price': 250.0, 'status': 'active'},
    ];
    for (final p in products) {
      batch.insert('products', p, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Seed Shelf Regions (San Pablo & Lipa)
    for (final branch in ['San Pablo', 'Lipa']) {
      final regions = [
        {'id': 'roi_${branch}_A', 'code': 'A', 'assignedProductId': 'prod_A', 'assignedProductName': 'Otto Scents Ocean Breeze', 'branch': branch, 'left_coord': 0.0, 'right_coord': 0.25, 'top_coord': 0.15, 'bottom_coord': 0.85, 'status': 'active'},
        {'id': 'roi_${branch}_B', 'code': 'B', 'assignedProductId': 'prod_B', 'assignedProductName': 'Otto Scents Velvet Rose', 'branch': branch, 'left_coord': 0.25, 'right_coord': 0.50, 'top_coord': 0.15, 'bottom_coord': 0.85, 'status': 'active'},
        {'id': 'roi_${branch}_C', 'code': 'C', 'assignedProductId': 'prod_C', 'assignedProductName': 'Otto Scents Vanilla Musk', 'branch': branch, 'left_coord': 0.50, 'right_coord': 0.75, 'top_coord': 0.15, 'bottom_coord': 0.85, 'status': 'active'},
        {'id': 'roi_${branch}_D', 'code': 'D', 'assignedProductId': 'prod_D', 'assignedProductName': 'Otto Scents Citrus Blossom', 'branch': branch, 'left_coord': 0.75, 'right_coord': 1.0, 'top_coord': 0.15, 'bottom_coord': 0.85, 'status': 'active'},
      ];
      for (final r in regions) {
        batch.insert('shelf_regions', r, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }

    // Seed Initial Inventory
    final inventory = [
      {'id': 'inv_sp_A', 'perfumeCode': 'A', 'name': 'Otto Scents Ocean Breeze', 'category': 'Men', 'branch': 'San Pablo', 'shelf': 'Area A', 'recorded': 5, 'detected': 5, 'status': 'normal', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_sp_B', 'perfumeCode': 'B', 'name': 'Otto Scents Velvet Rose', 'category': 'Women', 'branch': 'San Pablo', 'shelf': 'Area B', 'recorded': 5, 'detected': 2, 'status': 'low', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_sp_C', 'perfumeCode': 'C', 'name': 'Otto Scents Vanilla Musk', 'category': 'Unisex', 'branch': 'San Pablo', 'shelf': 'Area C', 'recorded': 5, 'detected': 4, 'status': 'normal', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_sp_D', 'perfumeCode': 'D', 'name': 'Otto Scents Citrus Blossom', 'category': 'Women', 'branch': 'San Pablo', 'shelf': 'Area D', 'recorded': 5, 'detected': 1, 'status': 'low', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_lipa_A', 'perfumeCode': 'A', 'name': 'Otto Scents Ocean Breeze', 'category': 'Men', 'branch': 'Lipa', 'shelf': 'Area A', 'recorded': 5, 'detected': 4, 'status': 'normal', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_lipa_B', 'perfumeCode': 'B', 'name': 'Otto Scents Velvet Rose', 'category': 'Women', 'branch': 'Lipa', 'shelf': 'Area B', 'recorded': 5, 'detected': 5, 'status': 'normal', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_lipa_C', 'perfumeCode': 'C', 'name': 'Otto Scents Vanilla Musk', 'category': 'Unisex', 'branch': 'Lipa', 'shelf': 'Area C', 'recorded': 5, 'detected': 0, 'status': 'out_of_stock', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
      {'id': 'inv_lipa_D', 'perfumeCode': 'D', 'name': 'Otto Scents Citrus Blossom', 'category': 'Women', 'branch': 'Lipa', 'shelf': 'Area D', 'recorded': 5, 'detected': 3, 'status': 'normal', 'misplacementDetails': '', 'price': 250.0, 'lastUpdated': now},
    ];
    for (final inv in inventory) {
      batch.insert('inventory_records', inv, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    // Seed Default System Settings
    final settings = {
      'captureSchedule': 'Every hour',
      'lowStockThreshold': '2',
      'roiBoundaries': '[0.0, 0.25, 0.50, 0.75, 1.0]',
      'roiTop': '0.15',
      'roiBottom': '0.85',
    };
    settings.forEach((k, v) {
      batch.insert('system_settings', {'key': k, 'value': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await batch.commit(noResult: true);
    await _seedInitialUsersIfEmpty(db);
  }

  Future<void> _seedInitialUsersIfEmpty(Database db) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      final count = (rows.isNotEmpty) ? (rows.first['count'] as num?)?.toInt() ?? 0 : 0;
      if (count == 0) {
        final batch = db.batch();
        final defaultHash = hashPassword('password123');
        final now = DateTime.now().millisecondsSinceEpoch;

        batch.insert('users', {
          'uid': 'admin_default_sp',
          'email': 'admin@ottoscents.com',
          'passwordHash': defaultHash,
          'role': 'admin',
          'branch': 'San Pablo',
          'lastLogin': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        batch.insert('users', {
          'uid': 'staff_default_lipa',
          'email': 'staff1@ottoscents.com',
          'passwordHash': defaultHash,
          'role': 'staff',
          'branch': 'Lipa',
          'lastLogin': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // PRODUCTS CRUD
  // ---------------------------------------------------------------------------
  Future<List<ProductModel>> getProducts() => getAllProducts();

  Future<List<ProductModel>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products', where: "status = 'active'");
    return maps.map((m) => ProductModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<ProductModel?> getProductByCode(String code) async {
    final db = await database;
    final maps = await db.query('products', where: 'perfumeCode = ?', whereArgs: [code], limit: 1);
    if (maps.isNotEmpty) return ProductModel.fromMap(maps.first, maps.first['id'] as String? ?? '');
    return null;
  }

  // ---------------------------------------------------------------------------
  // SHELF REGIONS (ROI) CRUD
  // ---------------------------------------------------------------------------
  Future<List<ShelfRegionModel>> getShelfRegions(String branch) async {
    final db = await database;
    final maps = await db.query('shelf_regions', where: 'branch = ?', whereArgs: [branch], orderBy: 'code ASC');
    return maps.map((m) => ShelfRegionModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> updateShelfRegion(ShelfRegionModel region) async {
    final db = await database;
    final map = region.toMap();
    map['id'] = region.id;
    map['left_coord'] = region.left;
    map['right_coord'] = region.right;
    map['top_coord'] = region.top;
    map['bottom_coord'] = region.bottom;
    await db.insert('shelf_regions', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // INVENTORY RECORDS CRUD
  // ---------------------------------------------------------------------------
  Future<List<InventoryRecordModel>> getInventoryRecords(String? branch) => getInventory(branch);

  Future<List<InventoryRecordModel>> getInventory(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query('inventory_records', where: 'branch = ?', whereArgs: [branch], orderBy: 'perfumeCode ASC');
    } else {
      maps = await db.query('inventory_records', orderBy: 'branch ASC, perfumeCode ASC');
    }
    return maps.map((m) => InventoryRecordModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> upsertInventoryRecord(InventoryRecordModel record) => saveInventoryRecord(record);

  Future<void> saveInventoryRecord(InventoryRecordModel record) async {
    final db = await database;
    final map = record.toMap();
    map['id'] = record.id;
    if (map['lastUpdated'] is Timestamp) {
      map['lastUpdated'] = (map['lastUpdated'] as Timestamp).millisecondsSinceEpoch;
    }
    await db.insert('inventory_records', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteInventoryRecord(String id) async {
    final db = await database;
    await db.delete('inventory_records', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // INVENTORY EVENTS (MOVEMENT LOGS) CRUD
  // ---------------------------------------------------------------------------
  Future<List<InventoryEventModel>> getInventoryEvents(String? branch, {int limit = 100}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'inventory_events',
        where: 'branch = ?',
        whereArgs: [branch],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      maps = await db.query('inventory_events', orderBy: 'timestamp DESC', limit: limit);
    }
    return maps.map((m) => InventoryEventModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> logInventoryEvent(InventoryEventModel event) async {
    final db = await database;
    final map = event.toMap();
    map['id'] = event.id;
    if (map['timestamp'] is Timestamp) {
      map['timestamp'] = (map['timestamp'] as Timestamp).millisecondsSinceEpoch;
    }
    await db.insert('inventory_events', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---------------------------------------------------------------------------
  // ALERTS CRUD
  // ---------------------------------------------------------------------------
  Future<List<AlertModel>> getAlerts(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query('alerts', where: 'branch = ?', whereArgs: [branch], orderBy: 'createdAt DESC');
    } else {
      maps = await db.query('alerts', orderBy: 'createdAt DESC');
    }
    return maps.map((m) => AlertModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> insertAlert(AlertModel alert) => saveAlert(alert);

  Future<void> saveAlert(AlertModel alert) async {
    final db = await database;
    final map = alert.toMap();
    map['id'] = alert.id;
    if (map['isRead'] is bool) {
      map['isRead'] = (map['isRead'] as bool) ? 1 : 0;
    }
    if (map['createdAt'] is Timestamp) {
      map['createdAt'] = (map['createdAt'] as Timestamp).millisecondsSinceEpoch;
    }
    await db.insert('alerts', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markAlertRead(String id) async {
    final db = await database;
    await db.update('alerts', {'isRead': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> markAllAlertsRead(List<String> ids) async {
    if (ids.isEmpty) return;
    final db = await database;
    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawUpdate('UPDATE alerts SET isRead = 1 WHERE id IN ($placeholders)', ids);
  }

  Future<void> deleteAlert(String id) async {
    final db = await database;
    await db.delete('alerts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllReadAlerts([dynamic arg]) async {
    final db = await database;
    if (arg is List<String>) {
      if (arg.isEmpty) return;
      final placeholders = List.filled(arg.length, '?').join(',');
      await db.delete('alerts', where: 'id IN ($placeholders)', whereArgs: arg);
    } else if (arg is String && arg.isNotEmpty && arg != 'All Branches') {
      await db.delete('alerts', where: 'isRead = 1 AND branch = ?', whereArgs: [arg]);
    } else {
      await db.delete('alerts', where: 'isRead = 1');
    }
  }

  // ---------------------------------------------------------------------------
  // SYSTEM ACTIVITY LOGS CRUD
  // ---------------------------------------------------------------------------
  Future<List<SystemLogModel>> getSystemLogs(String? branch, {int limit = 100}) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'system_logs',
        where: 'branch = ?',
        whereArgs: [branch],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      maps = await db.query('system_logs', orderBy: 'timestamp DESC', limit: limit);
    }
    return maps.map((m) => SystemLogModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> logSystemActivity(SystemLogModel log) async {
    final db = await database;
    await db.insert('system_logs', log.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSystemLog(String id) async {
    final db = await database;
    await db.delete('system_logs', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllSystemLogs([List<String>? ids]) async {
    final db = await database;
    if (ids != null && ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete('system_logs', where: 'id IN ($placeholders)', whereArgs: ids);
    } else {
      await db.delete('system_logs');
    }
  }

  // ---------------------------------------------------------------------------
  // SYNC QUEUE CRUD
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getPendingSyncItems() async {
    final db = await database;
    return await db.query('sync_queue', where: "status = 'pending'", orderBy: 'createdAt ASC');
  }

  Future<List<SyncQueueModel>> getPendingSyncQueue() async {
    final maps = await getPendingSyncItems();
    return maps.map((m) => SyncQueueModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<List<SyncQueueModel>> getSyncQueue(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query('sync_queue', where: 'branch = ?', whereArgs: [branch], orderBy: 'createdAt DESC');
    } else {
      maps = await db.query('sync_queue', orderBy: 'createdAt DESC');
    }
    return maps.map((m) => SyncQueueModel.fromMap(m, m['id'] as String? ?? '')).toList();
  }

  Future<void> enqueueSyncItem({
    required String id,
    required String pendingEventId,
    required String targetCollection,
    required String operation,
    required Map<String, dynamic> payload,
    required String branch,
  }) async {
    final db = await database;
    await db.insert(
      'sync_queue',
      {
        'id': id,
        'pendingEventId': pendingEventId,
        'targetCollection': targetCollection,
        'operation': operation,
        'payload': jsonEncode(payload),
        'retryCount': 0,
        'status': 'pending',
        'branch': branch,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> enqueueSyncTask(SyncQueueModel task) async {
    final db = await database;
    await db.insert('sync_queue', task.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markSyncItemStatus(String id, String status) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {
        'status': status,
        'lastAttempt': DateTime.now().millisecondsSinceEpoch,
        'errorStatus': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSyncQueueSuccess(String id) => markSyncItemStatus(id, 'synced');

  Future<void> incrementSyncRetry(String id, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE sync_queue
      SET retryCount = retryCount + 1,
          errorStatus = ?,
          lastAttempt = ?
      WHERE id = ?
    ''', [error, DateTime.now().millisecondsSinceEpoch, id]);
  }

  Future<void> clearSyncedQueueItems() async {
    final db = await database;
    await db.delete('sync_queue', where: "status = 'synced'");
  }

  // ---------------------------------------------------------------------------
  // SYSTEM SETTINGS CRUD
  // ---------------------------------------------------------------------------
  Future<Map<String, dynamic>> getSystemSettings() async {
    final db = await database;
    final maps = await db.query('system_settings');
    final Map<String, dynamic> result = {};
    for (final m in maps) {
      final k = m['key'] as String;
      final v = m['value'] as String;
      if (v.startsWith('[') || v.startsWith('{')) {
        try {
          result[k] = jsonDecode(v);
        } catch (_) {
          result[k] = v;
        }
      } else {
        result[k] = v;
      }
    }
    return result;
  }

  Future<void> setSystemSetting(String key, dynamic value) async {
    final db = await database;
    final strVal = (value is String) ? value : jsonEncode(value);
    await db.insert(
      'system_settings',
      {'key': key, 'value': strVal},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---------------------------------------------------------------------------
  // USERS CRUD (Cached local logins with hashed credentials)
  // ---------------------------------------------------------------------------
  Future<void> saveUser(UserModel user, {String? password}) async {
    try {
      final db = await database;
      await _ensureUsersTable(db);
      final map = <String, dynamic>{
        'uid': user.uid,
        'email': user.email.toLowerCase().trim(),
        'role': user.role,
        'branch': user.branch,
        'lastLogin': DateTime.now().millisecondsSinceEpoch,
      };
      if (password != null && password.isNotEmpty) {
        map['passwordHash'] = hashPassword(password);
      }
      await db.insert('users', map, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserWithCredentials(String email) async {
    try {
      final db = await database;
      await _ensureUsersTable(db);
      final maps = await db.query('users', where: 'LOWER(email) = ?', whereArgs: [email.toLowerCase().trim()]);
      if (maps.isNotEmpty) {
        final m = maps.first;
        final user = UserModel(
          uid: m['uid'] as String? ?? '',
          email: m['email'] as String? ?? '',
          role: m['role'] as String? ?? 'staff',
          branch: m['branch'] as String? ?? 'San Pablo',
        );
        return {
          'user': user,
          'passwordHash': m['passwordHash'] as String? ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  Future<UserModel?> getUser(String email) async {
    final creds = await getUserWithCredentials(email);
    return creds?['user'] as UserModel?;
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final db = await database;
      await _ensureUsersTable(db);
      final maps = await db.query('users');
      return maps.map((m) => UserModel(
        uid: m['uid'] as String? ?? '',
        email: m['email'] as String? ?? '',
        role: m['role'] as String? ?? 'staff',
        branch: m['branch'] as String? ?? 'San Pablo',
      )).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _ensureUsersTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        uid TEXT PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        passwordHash TEXT NOT NULL DEFAULT '',
        role TEXT NOT NULL DEFAULT 'staff',
        branch TEXT NOT NULL DEFAULT 'San Pablo',
        lastLogin INTEGER NOT NULL
      )
    ''');
  }
}
