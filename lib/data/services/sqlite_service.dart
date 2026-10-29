import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/inventory_record_model.dart';
import '../models/product_model.dart';
import '../models/shelf_region_model.dart';
import '../models/inventory_event_model.dart';
import '../models/alert_model.dart';
import '../models/image_quality_log_model.dart';
import '../models/restock_record_model.dart';
import '../models/system_log_model.dart';
import '../models/sync_queue_model.dart';
import '../models/user_model.dart';
import '../models/sale_record_model.dart';
import '../seeds/catalog_seed_data.dart';
import '../../core/constants/app_constants.dart';
import 'sync_service.dart';

class SqliteService {
  static SqliteService? _instance;
  static SqliteService get instance => _instance ??= SqliteService._();

  SqliteService._();

  Database? _db;
  int _logSequence = 0;
  final _activityLogUpdateController = StreamController<void>.broadcast();
  Stream<void> get onActivityLogUpdated => _activityLogUpdateController.stream;

  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password.trim())).toString();
  }

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    return await initialize();
  }

  Future<Database> initDatabase({bool inMemory = false, String? customPath}) =>
      initialize(inMemory: inMemory, customPath: customPath);

  Future<Database> initialize({
    bool inMemory = false,
    String? customPath,
  }) async {
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales_records (
        id TEXT PRIMARY KEY,
        perfumeCode TEXT NOT NULL,
        productName TEXT NOT NULL,
        bottleSize TEXT NOT NULL DEFAULT '100ml',
        quantitySold INTEGER NOT NULL DEFAULT 1,
        unitPrice REAL NOT NULL,
        totalAmount REAL NOT NULL,
        branch TEXT NOT NULL,
        soldBy TEXT NOT NULL DEFAULT 'staff',
        soldAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_logs (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        description TEXT NOT NULL,
        user TEXT NOT NULL,
        branch TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_system_logs_branch_time
      ON system_logs (branch, timestamp DESC)
    ''');
    await _seedInitialUsersIfEmpty(db);

    // Ensure shelf_regions has all necessary columns
    try {
      final info = await db.rawQuery('PRAGMA table_info(shelf_regions)');
      final cols = info.map((r) => r['name'] as String).toSet();
      if (!cols.contains('cameraPosition')) {
        await db.execute(
          'ALTER TABLE shelf_regions ADD COLUMN cameraPosition TEXT DEFAULT "left"',
        );
      }
      if (!cols.contains('deviceNode')) {
        await db.execute(
          'ALTER TABLE shelf_regions ADD COLUMN deviceNode TEXT DEFAULT "/dev/video2"',
        );
      }
      if (!cols.contains('bottleSize')) {
        await db.execute(
          'ALTER TABLE shelf_regions ADD COLUMN bottleSize TEXT DEFAULT "100ml"',
        );
      }
    } catch (_) {}

    // Automatically purge old dummy products ('A', 'B', 'C', 'D' or legacy tests)
    // and ensure the full 60 SKUs catalog is present in SQLite.
    try {
      final oldDummyRes = await db.rawQuery(
        "SELECT COUNT(*) as c FROM products WHERE perfumeCode IN ('A', 'B', 'C', 'D') OR name LIKE '%Ocean Breeze%' OR name LIKE '%Velvet Rose%'",
      );
      final hasOldDummy = (oldDummyRes.first['c'] as num?)?.toInt() ?? 0;

      final validCountRes = await db.rawQuery(
        "SELECT COUNT(*) as c FROM products WHERE perfumeCode NOT IN ('A', 'B', 'C', 'D')",
      );
      final validCount = (validCountRes.first['c'] as num?)?.toInt() ?? 0;

      final regionCountRes = await db.rawQuery(
        'SELECT COUNT(*) as c FROM shelf_regions',
      );
      final regionCount = (regionCountRes.first['c'] as num?)?.toInt() ?? 0;

      if (hasOldDummy > 0 || validCount < 60 || regionCount < 12) {
        await db.delete('products');
        await db.delete('shelf_regions');
        await db.delete('inventory_records');
        await CatalogSeedData.seedToSqlite(db, branch: 'San Pablo');
      }
    } catch (_) {}

    // Normalize and convert any legacy string timestamps in system_logs to integer epoch ms
    try {
      final textLogs = await db.rawQuery(
        "SELECT id, timestamp FROM system_logs WHERE typeof(timestamp) = 'text'",
      );
      for (final row in textLogs) {
        final id = row['id'] as String;
        final rawTs = row['timestamp'] as String;
        final parsed =
            DateTime.tryParse(rawTs)?.millisecondsSinceEpoch ??
            int.tryParse(rawTs) ??
            DateTime.now().millisecondsSinceEpoch;
        await db.update(
          'system_logs',
          {'timestamp': parsed},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    } catch (_) {}

    // Automatically purge old already-synced items from sync_queue
    try {
      await db.delete('sync_queue', where: "status = 'synced'");
    } catch (_) {}
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
        shelfLayer TEXT DEFAULT 'Layer A',
        slotPosition INTEGER DEFAULT 1,
        price REAL NOT NULL DEFAULT 0.0,
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
        cameraId INTEGER DEFAULT 1,
        cameraName TEXT DEFAULT 'Camera 1A (Top Left)',
        layerName TEXT DEFAULT 'Layer A (Top)',
        cameraPosition TEXT DEFAULT 'left',
        deviceNode TEXT DEFAULT '/dev/video2',
        bottleSize TEXT DEFAULT '100ml',
        left_coord REAL NOT NULL,
        right_coord REAL NOT NULL,
        top_coord REAL NOT NULL DEFAULT 0.0,
        bottom_coord REAL NOT NULL DEFAULT 1.0,
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

    // 12. Sales Records Table
    batch.execute('''
      CREATE TABLE IF NOT EXISTS sales_records (
        id TEXT PRIMARY KEY,
        perfumeCode TEXT NOT NULL,
        productName TEXT NOT NULL,
        bottleSize TEXT NOT NULL DEFAULT '100ml',
        quantitySold INTEGER NOT NULL DEFAULT 1,
        unitPrice REAL NOT NULL,
        totalAmount REAL NOT NULL,
        branch TEXT NOT NULL,
        soldBy TEXT NOT NULL DEFAULT 'staff',
        soldAt INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    // 13. Performance Indexes
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_code ON products(perfumeCode)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_branch ON inventory_records(branch)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_code ON inventory_records(perfumeCode)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_shelf_regions_branch ON shelf_regions(branch)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_alerts_branch_read ON alerts(branch, isRead)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_events_branch_time ON inventory_events(branch, timestamp)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_system_logs_branch_time ON system_logs(branch, timestamp)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_records_branch_time ON sales_records(branch, soldAt)',
    );
    batch.execute(
      'CREATE INDEX IF NOT EXISTS idx_restock_records_branch ON restock_records(toBranch, fromBranch)',
    );

    await batch.commit(noResult: true);
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    // 1. Seed 60 products (30 variants × 2 sizes across 3 shelf layers/cameras)
    await CatalogSeedData.seedToSqlite(db, branch: 'San Pablo');

    // 2. Seed Default System Settings
    final batch = db.batch();
    final settings = {
      'captureSchedule': 'Every hour',
      'lowStockThreshold': '2',
      'roiBoundaries': '[0.0, 0.33, 0.66, 1.0]',
      'roiTop': '0.0',
      'roiBottom': '1.0',
      'cameraCount': '3',
      'owner_pin_hash': hashPassword(AppConstants.defaultOwnerPin),
    };
    settings.forEach((k, v) {
      batch.insert('system_settings', {
        'key': k,
        'value': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await batch.commit(noResult: true);
    await _seedInitialUsersIfEmpty(db);
  }

  /// Re-seeds catalog data into SQLite
  Future<void> seedCatalog({String branch = 'San Pablo'}) async {
    final db = await database;
    await CatalogSeedData.seedToSqlite(db, branch: branch);
  }

  Future<void> _seedInitialUsersIfEmpty(Database db) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      final count = (rows.isNotEmpty)
          ? (rows.first['count'] as num?)?.toInt() ?? 0
          : 0;
      if (count == 0) {
        final batch = db.batch();
        final defaultHash = hashPassword(AppConstants.defaultOwnerPin);
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
  // ---------------------------------------------------------------------------
  // PRODUCTS CRUD
  // ---------------------------------------------------------------------------
  Future<List<ProductModel>> getProducts({bool activeOnly = false}) =>
      getAllProducts(activeOnly: activeOnly);

  Future<List<ProductModel>> getAllProducts({bool activeOnly = false}) async {
    final db = await database;
    final maps = activeOnly
        ? await db.query('products', where: "status = 'active'")
        : await db.query('products', where: "status != 'deleted'");
    return maps
        .map((m) => ProductModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> toggleProductStatus({
    required String productId,
    required String newStatus, // 'active', 'seasonal_off', etc.
    String branch = 'San Pablo',
  }) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (maps.isEmpty) return;

    final existing = ProductModel.fromMap(
      maps.first,
      maps.first['id'] as String? ?? '',
    );
    final updated = existing.copyWith(status: newStatus);

    await db.update(
      'products',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [productId],
    );

    // Also update corresponding inventory record status if seasonal
    try {
      final invStatus = (newStatus == 'seasonal_off' || newStatus == 'inactive')
          ? 'seasonal_off'
          : 'normal';
      await db.update(
        'inventory_records',
        {'status': invStatus},
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [existing.perfumeCode, branch],
      );

      // Enqueue inventory_record sync to cloud
      final invMaps = await db.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [existing.perfumeCode, branch],
        limit: 1,
      );
      if (invMaps.isNotEmpty) {
        final invRecord = InventoryRecordModel.fromMap(
          invMaps.first,
          invMaps.first['id'] as String? ?? '',
        );
        await enqueueSyncItem(
          id: 'sync_inv_status_${invRecord.id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: invRecord.id,
          targetCollection: 'inventory_records',
          operation: 'UPSERT',
          payload: invRecord.toMap(),
          branch: branch,
        );
      }
    } catch (_) {}

    // Queue sync for products
    try {
      await enqueueSyncItem(
        id: 'sync_prod_status_${productId}_${DateTime.now().millisecondsSinceEpoch}',
        pendingEventId: productId,
        targetCollection: 'products',
        operation: 'UPSERT',
        payload: updated.toMap(),
        branch: branch,
      );
    } catch (_) {}

    // Log system activity
    final statusLabel = (newStatus == 'seasonal_off' || newStatus == 'inactive')
        ? 'Turned OFF (Seasonal)'
        : 'Turned ON (Active)';
    await logActivity(
      type: 'VARIANT_STATUS',
      description:
          'Perfume "${existing.name}" (${existing.perfumeCode}) $statusLabel.',
      branch: branch,
    );
  }

  Future<void> saveProduct(
    ProductModel product, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.insert(
      'products',
      product.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_prod_${product.id}',
          pendingEventId: product.id,
          targetCollection: 'products',
          operation: 'UPSERT',
          payload: product.toMap(),
          branch: 'San Pablo',
        );
      } catch (_) {}
    }

    // Automatically audit log product catalog addition/modification
    if (enqueueSync) {
      await logActivity(
        type: 'PRODUCT_CATALOG',
        description:
            'Product "${product.name}" (${product.perfumeCode} • ${product.bottleSize}) updated in catalog.',
        branch: 'San Pablo',
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<void> deleteProduct(String id, {bool enqueueSync = true}) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_del_prod_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'products',
          operation: 'DELETE',
          payload: {'id': id},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'PRODUCT_DELETE',
        description: 'Product SKU #$id deleted from catalog.',
        branch: 'San Pablo',
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<ProductModel?> getProductByCode(String code) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'perfumeCode = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (maps.isNotEmpty) {
      return ProductModel.fromMap(
        maps.first,
        maps.first['id'] as String? ?? '',
      );
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // SHELF REGIONS (ROI) CRUD
  // ---------------------------------------------------------------------------
  Future<List<ShelfRegionModel>> getShelfRegions(String branch) async {
    final db = await database;
    final maps = await db.query(
      'shelf_regions',
      where: 'branch = ?',
      whereArgs: [branch],
      orderBy: 'code ASC',
    );
    return maps
        .map((m) => ShelfRegionModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> updateShelfRegion(
    ShelfRegionModel region, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final map = region.toMap();
    map['id'] = region.id;
    map['left_coord'] = region.left;
    map['right_coord'] = region.right;
    map['top_coord'] = region.top;
    map['bottom_coord'] = region.bottom;
    try {
      await db.insert(
        'shelf_regions',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      try {
        await db.execute(
          'ALTER TABLE shelf_regions ADD COLUMN bottleSize TEXT DEFAULT "100ml"',
        );
        await db.insert(
          'shelf_regions',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_roi_${region.id}',
          pendingEventId: region.id,
          targetCollection: 'shelf_regions',
          operation: 'UPSERT',
          payload: region.toMap(),
          branch: region.branch,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'ROI_CALIBRATION',
        description:
            'ROI configured for slot ${region.code} (${region.assignedProductName.isNotEmpty ? region.assignedProductName : (region.assignedProductId.isNotEmpty ? region.assignedProductId : "Unassigned")}).',
        branch: region.branch,
        enqueueSync: enqueueSync,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // INVENTORY RECORDS CRUD
  // ---------------------------------------------------------------------------
  Future<List<InventoryRecordModel>> getInventoryRecords(String? branch) =>
      getInventory(branch);

  Future<List<InventoryRecordModel>> getInventory(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'inventory_records',
        where: 'branch = ?',
        whereArgs: [branch],
        orderBy: 'perfumeCode ASC',
      );
    } else {
      maps = await db.query(
        'inventory_records',
        orderBy: 'branch ASC, perfumeCode ASC',
      );
    }
    return maps
        .map((m) => InventoryRecordModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<InventoryRecordModel?> getInventoryRecord(
    String perfumeCode,
    String branch,
  ) async {
    final db = await database;
    final maps = await db.query(
      'inventory_records',
      where: 'perfumeCode = ? AND branch = ?',
      whereArgs: [perfumeCode, branch],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return InventoryRecordModel.fromMap(
      maps.first,
      maps.first['id'] as String? ?? '',
    );
  }

  Future<void> upsertInventoryRecord(
    InventoryRecordModel record, {
    bool enqueueSync = true,
  }) => saveInventoryRecord(record, enqueueSync: enqueueSync);

  Future<void> saveInventoryRecord(
    InventoryRecordModel record, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final map = record.toMap();
    map['id'] = record.id;
    if (map['lastUpdated'] is DateTime) {
      map['lastUpdated'] =
          (map['lastUpdated'] as DateTime).millisecondsSinceEpoch;
    }
    await db.insert(
      'inventory_records',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_inv_${record.id}',
          pendingEventId: record.id,
          targetCollection: 'inventory_records',
          operation: 'UPSERT',
          payload: record.toMap(),
          branch: record.branch,
        );
      } catch (_) {}
    }
  }

  Future<void> deleteInventoryRecord(
    String id, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.delete('inventory_records', where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_del_inv_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'inventory_records',
          operation: 'DELETE',
          payload: {'id': id},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // INVENTORY EVENTS (MOVEMENT LOGS) CRUD
  // ---------------------------------------------------------------------------
  Future<List<InventoryEventModel>> getInventoryEvents(
    String? branch, {
    int limit = 100,
  }) async {
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
      maps = await db.query(
        'inventory_events',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
    return maps
        .map((m) => InventoryEventModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> logInventoryEvent(
    InventoryEventModel event, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final map = event.toMap();
    map['id'] = event.id;
    if (map['timestamp'] is DateTime) {
      map['timestamp'] = (map['timestamp'] as DateTime).millisecondsSinceEpoch;
    } else if (map['timestamp'] is String) {
      map['timestamp'] =
          DateTime.tryParse(map['timestamp'] as String)
              ?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    }
    await db.insert(
      'inventory_events',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_event_${event.id}',
          pendingEventId: event.id,
          targetCollection: 'inventory_events',
          operation: 'UPSERT',
          payload: event.toMap(),
          branch: event.branch,
        );
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // ALERTS CRUD
  // ---------------------------------------------------------------------------
  Future<List<AlertModel>> getAlerts(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'alerts',
        where: 'branch = ?',
        whereArgs: [branch],
        orderBy: 'createdAt DESC',
      );
    } else {
      maps = await db.query('alerts', orderBy: 'createdAt DESC');
    }
    return maps
        .map((m) => AlertModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> insertAlert(AlertModel alert, {bool enqueueSync = true}) =>
      saveAlert(alert, enqueueSync: enqueueSync);

  Future<void> saveAlert(AlertModel alert, {bool enqueueSync = true}) async {
    final db = await database;
    final map = alert.toMap();
    map['id'] = alert.id;
    if (map['isRead'] is bool) {
      map['isRead'] = (map['isRead'] as bool) ? 1 : 0;
    }
    if (map['createdAt'] is DateTime) {
      map['createdAt'] = (map['createdAt'] as DateTime).millisecondsSinceEpoch;
    }
    await db.insert(
      'alerts',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_alert_${alert.id}',
          pendingEventId: alert.id,
          targetCollection: 'alerts',
          operation: 'UPSERT',
          payload: alert.toMap(),
          branch: alert.branch,
        );
      } catch (_) {}
    }
  }

  Future<void> markAlertRead(String id, {bool enqueueSync = true}) async {
    final db = await database;
    await db.update('alerts', {'isRead': 1}, where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_read_alert_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'alerts',
          operation: 'UPSERT',
          payload: {'id': id, 'isRead': 1},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }
  }

  Future<void> markAllAlertsRead([
    List<String>? ids,
    String? branch,
    bool enqueueSync = true,
  ]) async {
    final db = await database;
    final effectiveBranch = branch ?? 'San Pablo';

    if (ids != null && ids.isNotEmpty) {
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.rawUpdate(
        'UPDATE alerts SET isRead = 1 WHERE id IN ($placeholders)',
        ids,
      );

      if (enqueueSync) {
        for (final alertId in ids) {
          try {
            await enqueueSyncItem(
              id: 'sync_read_alert_${alertId}_${DateTime.now().millisecondsSinceEpoch}',
              pendingEventId: alertId,
              targetCollection: 'alerts',
              operation: 'UPSERT',
              payload: {'id': alertId, 'isRead': 1},
              branch: effectiveBranch,
            );
          } catch (_) {}
        }
      }
    } else {
      // Mark all unread alerts for branch (or all) as read
      List<Map<String, dynamic>> unread;
      if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
        unread = await db.query(
          'alerts',
          columns: ['id'],
          where: 'branch = ? AND isRead = 0',
          whereArgs: [branch],
        );
        await db.rawUpdate('UPDATE alerts SET isRead = 1 WHERE branch = ?', [
          branch,
        ]);
      } else {
        unread = await db.query('alerts', columns: ['id'], where: 'isRead = 0');
        await db.rawUpdate('UPDATE alerts SET isRead = 1');
      }

      if (enqueueSync) {
        for (final row in unread) {
          final alertId = row['id'] as String?;
          if (alertId != null) {
            try {
              await enqueueSyncItem(
                id: 'sync_read_alert_${alertId}_${DateTime.now().millisecondsSinceEpoch}',
                pendingEventId: alertId,
                targetCollection: 'alerts',
                operation: 'UPSERT',
                payload: {'id': alertId, 'isRead': 1},
                branch: effectiveBranch,
              );
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<void> deleteAlert(String id, {bool enqueueSync = true}) async {
    final db = await database;
    await db.delete('alerts', where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_del_alert_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'alerts',
          operation: 'DELETE',
          payload: {'id': id},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }
  }

  Future<void> deleteAllReadAlerts([
    dynamic arg,
    bool enqueueSync = true,
  ]) async {
    final db = await database;
    List<String> deletedIds = [];
    if (arg is List<String>) {
      if (arg.isEmpty) return;
      deletedIds = List<String>.from(arg);
      final placeholders = List.filled(arg.length, '?').join(',');
      await db.delete('alerts', where: 'id IN ($placeholders)', whereArgs: arg);
    } else if (arg is String && arg.isNotEmpty && arg != 'All Branches') {
      final rows = await db.query(
        'alerts',
        columns: ['id'],
        where: 'isRead = 1 AND branch = ?',
        whereArgs: [arg],
      );
      deletedIds = rows.map((r) => r['id'] as String).toList();
      await db.delete(
        'alerts',
        where: 'isRead = 1 AND branch = ?',
        whereArgs: [arg],
      );
    } else {
      final rows = await db.query(
        'alerts',
        columns: ['id'],
        where: 'isRead = 1',
      );
      deletedIds = rows.map((r) => r['id'] as String).toList();
      await db.delete('alerts', where: 'isRead = 1');
    }

    if (enqueueSync && deletedIds.isNotEmpty) {
      for (final alertId in deletedIds) {
        try {
          await enqueueSyncItem(
            id: 'sync_del_alert_${alertId}_${DateTime.now().millisecondsSinceEpoch}',
            pendingEventId: alertId,
            targetCollection: 'alerts',
            operation: 'DELETE',
            payload: {'id': alertId},
            branch: 'San Pablo',
          );
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IMAGE QUALITY LOGS CRUD
  // ---------------------------------------------------------------------------
  Future<void> logImageQuality(
    ImageQualityLogModel log, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.insert(
      'image_quality_logs',
      log.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_iq_${log.id}',
          pendingEventId: log.id,
          targetCollection: 'image_quality_logs',
          operation: 'UPSERT',
          payload: log.toMap(),
          branch: log.branch,
        );
      } catch (_) {}
    }
  }

  Future<List<ImageQualityLogModel>> getImageQualityLogs(
    String? branch, {
    int limit = 50,
  }) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'image_quality_logs',
        where: 'branch = ?',
        whereArgs: [branch],
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    } else {
      maps = await db.query(
        'image_quality_logs',
        orderBy: 'timestamp DESC',
        limit: limit,
      );
    }
    return maps
        .map((m) => ImageQualityLogModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // RESTOCK RECORDS CRUD
  // ---------------------------------------------------------------------------
  Future<void> saveRestockRecord(
    RestockRecordModel restock, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.insert(
      'restock_records',
      restock.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_restock_${restock.id}',
          pendingEventId: restock.id,
          targetCollection: 'restock_records',
          operation: 'UPSERT',
          payload: restock.toMap(),
          branch: restock.toBranch,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'RESTOCK_DELIVERY',
        description:
            'Restock logged: ${restock.quantity}x ${restock.productName} (${restock.perfumeCode}) for ${restock.toBranch}.',
        branch: restock.toBranch,
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<List<RestockRecordModel>> getRestockRecords(String? branch) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'restock_records',
        where: 'toBranch = ? OR fromBranch = ?',
        whereArgs: [branch, branch],
        orderBy: 'createdAt DESC',
      );
    } else {
      maps = await db.query('restock_records', orderBy: 'createdAt DESC');
    }
    return maps
        .map((m) => RestockRecordModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> updateRestockStatus(
    String id,
    String status, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.update(
      'restock_records',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_status_restock_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'restock_records',
          operation: 'UPSERT',
          payload: {'id': id, 'status': status},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'RESTOCK_STATUS',
        description: 'Restock order #$id status changed to $status.',
        branch: 'San Pablo',
        enqueueSync: enqueueSync,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // SYSTEM ACTIVITY LOGS CRUD
  // ---------------------------------------------------------------------------
  Future<List<SystemLogModel>> getSystemLogs(
    String? branch, {
    int limit = 300,
  }) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      maps = await db.query(
        'system_logs',
        where: 'branch = ? OR branch = ? OR branch IS NULL OR branch = ?',
        whereArgs: [branch, 'All Branches', ''],
        orderBy: 'CAST(timestamp AS INTEGER) DESC',
        limit: limit,
      );
    } else {
      maps = await db.query(
        'system_logs',
        orderBy: 'CAST(timestamp AS INTEGER) DESC',
        limit: limit,
      );
    }
    final logs = maps
        .map((m) => SystemLogModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }

  Future<void> logSystemActivity(
    SystemLogModel log, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final map = log.toMap();
    map['id'] = log.id;
    if (map['timestamp'] is String) {
      map['timestamp'] =
          DateTime.tryParse(map['timestamp'] as String)
              ?.millisecondsSinceEpoch ??
          DateTime.now().millisecondsSinceEpoch;
    }
    await db.insert(
      'system_logs',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _activityLogUpdateController.add(null);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_log_${log.id}',
          pendingEventId: log.id,
          targetCollection: 'system_logs',
          operation: 'UPSERT',
          payload: log.toMap(),
          branch: log.branch,
        );
      } catch (_) {}
    }
  }

  Future<void> upsertSystemLogsFromCloud(List<SystemLogModel> logs) async {
    if (logs.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final log in logs) {
        final map = log.toMap();
        map['id'] = log.id;
        if (map['timestamp'] is String) {
          map['timestamp'] =
              DateTime.tryParse(map['timestamp'] as String)
                  ?.millisecondsSinceEpoch ??
              DateTime.now().millisecondsSinceEpoch;
        }
        batch.insert(
          'system_logs',
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
    _activityLogUpdateController.add(null);
  }

  Future<void> logActivity({
    required String type,
    required String description,
    String user = 'Store Owner',
    String branch = 'San Pablo',
    bool enqueueSync = true,
  }) async {
    try {
      final seq = (++_logSequence) % 1000000;
      final log = SystemLogModel(
        id: 'log_${DateTime.now().microsecondsSinceEpoch}_${seq}_${type.toLowerCase()}',
        type: type,
        description: description,
        user: user,
        branch: branch,
        timestamp: DateTime.now(),
      );
      await logSystemActivity(log, enqueueSync: enqueueSync);
    } catch (_) {
      // Defensive: failures in audit logging should never crash the host application
    }
  }

  Future<void> clearAllSystemLogs(
    String branch, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.delete('system_logs', where: 'branch = ?', whereArgs: [branch]);
    _activityLogUpdateController.add(null);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_clear_logs_${DateTime.now().microsecondsSinceEpoch}',
          pendingEventId: 'all',
          targetCollection: 'system_logs',
          operation: 'CLEAR_ALL',
          payload: {'branch': branch},
          branch: branch,
        );
      } catch (_) {}
    }
  }

  Future<void> deleteSystemLog(String id, {bool enqueueSync = true}) async {
    final db = await database;
    await db.delete('system_logs', where: 'id = ?', whereArgs: [id]);
    _activityLogUpdateController.add(null);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_del_log_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'system_logs',
          operation: 'DELETE',
          payload: {'id': id},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }
  }

  Future<void> deleteAllSystemLogs([
    List<String>? ids,
    bool enqueueSync = true,
  ]) async {
    final db = await database;
    List<String> deletedIds = [];
    if (ids != null && ids.isNotEmpty) {
      deletedIds = List<String>.from(ids);
      final placeholders = List.filled(ids.length, '?').join(',');
      await db.delete(
        'system_logs',
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );
    } else {
      final rows = await db.query('system_logs', columns: ['id']);
      deletedIds = rows.map((r) => r['id'] as String).toList();
      await db.delete('system_logs');
    }
    _activityLogUpdateController.add(null);

    if (enqueueSync && deletedIds.isNotEmpty) {
      for (final logId in deletedIds) {
        try {
          await enqueueSyncItem(
            id: 'sync_del_log_${logId}_${DateTime.now().millisecondsSinceEpoch}',
            pendingEventId: logId,
            targetCollection: 'system_logs',
            operation: 'DELETE',
            payload: {'id': logId},
            branch: 'San Pablo',
          );
        } catch (_) {}
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SYNC QUEUE CRUD
  // ---------------------------------------------------------------------------
  Future<List<Map<String, dynamic>>> getPendingSyncItems({
    bool applyBackoff = true,
  }) async {
    final db = await database;
    final allPending = await db.query(
      'sync_queue',
      where: "status = 'pending'",
      orderBy: 'createdAt ASC',
    );
    if (!applyBackoff) return allPending;

    final now = DateTime.now().millisecondsSinceEpoch;
    return allPending.where((item) {
      final retryCount = (item['retryCount'] as num?)?.toInt() ?? 0;
      final lastAttempt = (item['lastAttempt'] as num?)?.toInt();
      if (retryCount == 0 || lastAttempt == null) {
        return true;
      }
      // Exponential backoff: min 5s, max 300s (5 minutes)
      final backoffSeconds = (1 << retryCount.clamp(0, 6)) * 5;
      final backoffMs = (backoffSeconds > 300 ? 300 : backoffSeconds) * 1000;
      return (now - lastAttempt) >= backoffMs;
    }).toList();
  }

  Future<List<SyncQueueModel>> getPendingSyncQueue() async {
    final maps = await getPendingSyncItems();
    return maps
        .map((m) => SyncQueueModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<List<SyncQueueModel>> getSyncQueue(
    String? branch, {
    bool pendingOnly = true,
  }) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    final where = <String>[];
    final args = <dynamic>[];
    if (pendingOnly) {
      where.add("status = 'pending'");
    }
    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      where.add('branch = ?');
      args.add(branch);
    }
    final whereClause = where.isNotEmpty ? where.join(' AND ') : null;
    maps = await db.query(
      'sync_queue',
      where: whereClause,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'createdAt DESC',
    );
    return maps
        .map((m) => SyncQueueModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<int> purgeSyncedQueueItems() async {
    final db = await database;
    return await db.delete('sync_queue', where: "status = 'synced'");
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
    await db.insert('sync_queue', {
      'id': id,
      'pendingEventId': pendingEventId,
      'targetCollection': targetCollection,
      'operation': operation,
      'payload': jsonEncode(payload),
      'retryCount': 0,
      'status': 'pending',
      'branch': branch,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> enqueueSyncTask(SyncQueueModel task) async {
    final db = await database;
    await db.insert(
      'sync_queue',
      task.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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

  Future<void> markSyncQueueSuccess(String id) =>
      markSyncItemStatus(id, 'synced');

  Future<void> incrementSyncRetry(String id, String error) async {
    final db = await database;
    await db.rawUpdate(
      '''
      UPDATE sync_queue
      SET retryCount = retryCount + 1,
          errorStatus = ?,
          lastAttempt = ?
      WHERE id = ?
    ''',
      [error, DateTime.now().millisecondsSinceEpoch, id],
    );
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

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query(
      'system_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  Future<void> setSystemSetting(
    String key,
    dynamic value, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final strVal = (value is String) ? value : jsonEncode(value);
    await db.insert('system_settings', {
      'key': key,
      'value': strVal,
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    // Queue for cloud synchronization with Supabase
    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_setting_${key}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: key,
          targetCollection: 'system_settings',
          operation: 'UPSERT',
          payload: {'key': key, 'value': strVal},
          branch: 'San Pablo',
        );
      } catch (_) {}
    }

    if (enqueueSync &&
        !key.startsWith('last_') &&
        !key.contains('tray_rois') &&
        !key.contains('roi')) {
      await logActivity(
        type: 'SETTINGS_UPDATE',
        description: 'System setting "$key" configured.',
        branch: 'San Pablo',
        enqueueSync: enqueueSync,
      );
    }
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
      await db.insert(
        'users',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> getUserWithCredentials(String email) async {
    try {
      final db = await database;
      await _ensureUsersTable(db);
      final maps = await db.query(
        'users',
        where: 'LOWER(email) = ?',
        whereArgs: [email.toLowerCase().trim()],
      );
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
      return maps
          .map(
            (m) => UserModel(
              uid: m['uid'] as String? ?? '',
              email: m['email'] as String? ?? '',
              role: m['role'] as String? ?? 'staff',
              branch: m['branch'] as String? ?? 'San Pablo',
            ),
          )
          .toList();
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

  // ---------------------------------------------------------------------------
  // OWNER PIN OPERATIONS & RECOVERY
  // ---------------------------------------------------------------------------
  Future<bool> verifyRecoveryQuestions({
    required String answer1,
    required String answer2,
    required String answer3,
  }) async {
    try {
      final db = await database;
      final maps = await db.query(
        'system_settings',
        where: 'key LIKE ?',
        whereArgs: ['recovery_ans_%'],
      );
      final storedAnswers = {
        for (final m in maps) m['key'] as String: m['value'] as String,
      };

      final expected1 =
          (storedAnswers['recovery_ans_1'] ?? AppConstants.recoveryAnswer1)
              .trim()
              .toLowerCase();
      final expected2 =
          (storedAnswers['recovery_ans_2'] ?? AppConstants.recoveryAnswer2)
              .trim()
              .toLowerCase();
      final expected3 =
          (storedAnswers['recovery_ans_3'] ?? AppConstants.recoveryAnswer3)
              .trim()
              .toLowerCase();

      final a1 = answer1.trim().toLowerCase();
      final a2 = answer2.trim().toLowerCase();
      final a3 = answer3.trim().toLowerCase();

      return a1 == expected1 && a2 == expected2 && a3 == expected3;
    } catch (_) {
      return false;
    }
  }

  Future<bool> resetOwnerPinViaRecovery({
    required String answer1,
    required String answer2,
    required String answer3,
    required String newPin,
  }) async {
    try {
      final isValid = await verifyRecoveryQuestions(
        answer1: answer1,
        answer2: answer2,
        answer3: answer3,
      );
      if (!isValid) return false;

      final db = await database;
      final newHash = hashPassword(newPin);

      // Save new PIN hash
      await setSystemSetting('owner_pin_hash', newHash);

      // Update admin user credentials
      await _ensureUsersTable(db);
      await db.update(
        'users',
        {
          'passwordHash': newHash,
          'lastLogin': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      await logActivity(
        type: 'PIN_RECOVERED',
        description: 'Store Owner PIN successfully reset via security recovery questions.',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> verifyOwnerPin(String pin) async {
    try {
      final db = await database;
      final maps = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['owner_pin_hash'],
      );
      if (maps.isNotEmpty) {
        final storedHash = maps.first['value'] as String? ?? '';
        if (storedHash.isNotEmpty) {
          // If a custom PIN hash is stored, ONLY this hash is valid
          return storedHash == hashPassword(pin);
        }
      }
      // Check admin user in users table if not set in system settings
      final adminCreds = await getUserWithCredentials('admin@ottoscents.com');
      if (adminCreds != null &&
          (adminCreds['passwordHash'] as String).isNotEmpty) {
        final hash = adminCreds['passwordHash'] as String;
        return hash == hashPassword(pin);
      }
      // Initial factory default PIN
      return pin == AppConstants.defaultOwnerPin;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateOwnerPin({
    required String oldPin,
    required String newPin,
  }) async {
    try {
      final isValidOld = await verifyOwnerPin(oldPin);
      if (!isValidOld) return false;

      final db = await database;
      final newHash = hashPassword(newPin);

      // 1. Save in system_settings (auto-enqueues to sync_queue)
      await setSystemSetting('owner_pin_hash', newHash);

      // 2. Update admin user credentials in local SQLite and queue for Supabase
      await _ensureUsersTable(db);
      await db.update(
        'users',
        {
          'passwordHash': newHash,
          'lastLogin': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      try {
        await enqueueSyncItem(
          id: 'sync_user_admin_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: 'admin_san_pablo',
          targetCollection: 'users',
          operation: 'UPSERT',
          payload: {
            'uid': 'admin_san_pablo',
            'email': 'admin@ottoscents.com',
            'role': 'owner',
            'branch': 'San Pablo',
          },
          branch: 'San Pablo',
        );
      } catch (_) {}

      // 3. Insert system audit log (auto-enqueues to sync_queue)
      final logId = 'log_${DateTime.now().millisecondsSinceEpoch}_pin';
      await logSystemActivity(
        SystemLogModel(
          id: logId,
          user: 'Store Owner',
          type: 'SECURITY_UPDATE',
          description: 'Store owner 6-digit PIN successfully changed.',
          timestamp: DateTime.now(),
          branch: 'San Pablo',
        ),
      );

      // 4. Trigger immediate real-time sync with Supabase cloud
      unawaited(SyncService.instance.syncPendingQueue());

      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // SALES RECORDS (REVENUE TRACKING) CRUD
  // ---------------------------------------------------------------------------
  Future<void> insertSaleRecord(
    SaleRecordModel record, {
    bool enqueueSync = true,
  }) async {
    final db = await database;
    final map = record.toMap();
    await db.insert(
      'sales_records',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_sale_${record.id}',
          pendingEventId: record.id,
          targetCollection: 'sales_records',
          operation: 'UPSERT',
          payload: record.toMap(),
          branch: record.branch,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'SALE_TRANSACTION',
        description:
            'Sale recorded: ${record.quantitySold}x ${record.productName} (${record.bottleSize}) for ₱${record.totalAmount.toStringAsFixed(2)}.',
        user: record.soldBy,
        branch: record.branch,
        enqueueSync: enqueueSync,
      );
    }
  }

  /// Atomically records a sale, logs the inventory reduction event, updates the inventory
  /// count, and enqueues sync tasks within a single ACID transaction to prevent race conditions.
  Future<void> recordSaleWithInventoryDeduction({
    required SaleRecordModel saleRecord,
    required InventoryEventModel event,
    required String branch,
    bool enqueueSync = true,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Insert sale record
      await txn.insert(
        'sales_records',
        saleRecord.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Insert inventory event
      final eventMap = event.toMap();
      if (eventMap['timestamp'] is String) {
        eventMap['timestamp'] =
            DateTime.tryParse(eventMap['timestamp'] as String)
                ?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
      }
      await txn.insert(
        'inventory_events',
        eventMap,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Deduct inventory record detection and recorded count
      final invRows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [saleRecord.perfumeCode, branch],
      );
      if (invRows.isNotEmpty) {
        final current = InventoryRecordModel.fromMap(invRows.first);
        final newDetected =
            (current.detected - saleRecord.quantitySold).clamp(0, 100);
        final newRecorded =
            (current.recorded - saleRecord.quantitySold).clamp(0, 100);
        final updatedInv = current.copyWith(
          detected: newDetected,
          recorded: newRecorded,
          lastUpdated: DateTime.now(),
          status: newDetected == 0
              ? 'out_of_stock'
              : (newDetected <= 2 ? 'low' : 'normal'),
        );
        await txn.insert(
          'inventory_records',
          updatedInv.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (enqueueSync) {
          await txn.insert('sync_queue', {
            'id': 'sync_inv_${updatedInv.id}',
            'pendingEventId': updatedInv.id,
            'targetCollection': 'inventory_records',
            'operation': 'UPSERT',
            'payload': jsonEncode(updatedInv.toMap()),
            'retryCount': 0,
            'status': 'pending',
            'branch': updatedInv.branch,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 4. Atomic sync queue insertions
      if (enqueueSync) {
        await txn.insert('sync_queue', {
          'id': 'sync_sale_${saleRecord.id}',
          'pendingEventId': saleRecord.id,
          'targetCollection': 'sales_records',
          'operation': 'UPSERT',
          'payload': jsonEncode(saleRecord.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': saleRecord.branch,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.insert('sync_queue', {
          'id': 'sync_event_${event.id}',
          'pendingEventId': event.id,
          'targetCollection': 'inventory_events',
          'operation': 'UPSERT',
          'payload': jsonEncode(event.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': event.branch,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    if (enqueueSync) {
      await logActivity(
        type: 'SALE_TRANSACTION',
        description:
            'Sale recorded: ${saleRecord.quantitySold}x ${saleRecord.productName} (${saleRecord.bottleSize}) for ₱${saleRecord.totalAmount.toStringAsFixed(2)}.',
        user: saleRecord.soldBy,
        branch: saleRecord.branch,
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<List<SaleRecordModel>> getSalesRecords(
    String? branch, {
    DateTime? from,
    DateTime? to,
    int limit = 200,
  }) async {
    final db = await database;
    final List<String> whereClauses = [];
    final List<dynamic> whereArgs = [];

    if (branch != null && branch.isNotEmpty && branch != 'All Branches') {
      whereClauses.add('branch = ?');
      whereArgs.add(branch);
    }

    if (from != null) {
      whereClauses.add('soldAt >= ?');
      whereArgs.add(from.millisecondsSinceEpoch);
    }

    if (to != null) {
      whereClauses.add('soldAt <= ?');
      whereArgs.add(to.millisecondsSinceEpoch);
    }

    final whereStr = whereClauses.isNotEmpty
        ? whereClauses.join(' AND ')
        : null;

    final maps = await db.query(
      'sales_records',
      where: whereStr,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: 'soldAt DESC',
      limit: limit,
    );

    return maps
        .map((m) => SaleRecordModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<void> deleteSaleRecord(String id, {bool enqueueSync = true}) async {
    final db = await database;
    String targetBranch = 'San Pablo';
    try {
      final existing = await db.query(
        'sales_records',
        columns: ['branch'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (existing.isNotEmpty && existing.first['branch'] != null) {
        targetBranch = existing.first['branch'] as String;
      }
    } catch (_) {}

    await db.delete('sales_records', where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_del_sale_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'sales_records',
          operation: 'DELETE',
          payload: {'id': id},
          branch: targetBranch,
        );
      } catch (_) {}
    }
  }

  Future<void> deleteAllSalesRecords() async {
    final db = await database;
    await db.delete('sales_records');
  }
}
