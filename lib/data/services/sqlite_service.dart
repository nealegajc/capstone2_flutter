import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Rect;

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
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'sync_service.dart';

/// Cryptographically secure PBKDF2-HMAC-SHA256 key derivation utility
class Pbkdf2Auth {
  static const int iterations = 100000;
  static const int keyLength = 32;

  /// Generates cryptographically secure random salt bytes
  static List<int> generateSalt([int length = 32]) {
    final rnd = Random.secure();
    return List<int>.generate(length, (_) => rnd.nextInt(256));
  }

  /// Implements standard RFC 2898 / PKCS #5 v2.0 PBKDF2-HMAC-SHA256
  static Uint8List deriveKey({
    required String password,
    required List<int> salt,
    int iterations = iterations,
    int derivedKeyLength = keyLength,
  }) {
    final hmac = Hmac(sha256, utf8.encode(password.trim()));
    final numBlocks = (derivedKeyLength / 32).ceil();
    final result = Uint8List(derivedKeyLength);

    for (int blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      // U_1 = PRF(P, S || INT_32_BE(blockIndex))
      final blockBytes = Uint8List(salt.length + 4);
      blockBytes.setRange(0, salt.length, salt);
      blockBytes[salt.length] = (blockIndex >> 24) & 0xff;
      blockBytes[salt.length + 1] = (blockIndex >> 16) & 0xff;
      blockBytes[salt.length + 2] = (blockIndex >> 8) & 0xff;
      blockBytes[salt.length + 3] = blockIndex & 0xff;

      var u = Uint8List.fromList(hmac.convert(blockBytes).bytes);
      final blockResult = Uint8List.fromList(u);

      for (int iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int i = 0; i < 32; i++) {
          blockResult[i] ^= u[i];
        }
      }

      final destOffset = (blockIndex - 1) * 32;
      final lengthToCopy = (derivedKeyLength - destOffset).clamp(0, 32);
      result.setRange(destOffset, destOffset + lengthToCopy, blockResult);
    }

    return result;
  }

  /// Hashes a PIN or secret with salt and returns a lowercase hex string
  static String hashPin(
    String pin,
    List<int> saltBytes, {
    int iterations = iterations,
  }) {
    final keyBytes = deriveKey(
      password: pin,
      salt: saltBytes,
      iterations: iterations,
      derivedKeyLength: keyLength,
    );
    return toHex(keyBytes);
  }

  static String toHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static List<int> fromHex(String hex) {
    final clean = hex.trim();
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Constant-time string equality check to prevent timing analysis (CWE-208)
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Represents the brute-force security lockout state persisted in SQLite
class LockoutStatus {
  final bool isLockedOut;
  final int remainingSeconds;
  final int failedAttempts;

  const LockoutStatus({
    required this.isLockedOut,
    required this.remainingSeconds,
    required this.failedAttempts,
  });
}

class SqliteService {
  static SqliteService? _instance;
  static SqliteService get instance => _instance ??= SqliteService._();

  SqliteService._();

  static const String defaultMasterRecoveryKey = 'OTTO-MASTER-RECOVERY-2026';

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

  Future<void> close() async {
    if (_db != null) {
      if (_db!.isOpen) {
        await _db!.close();
      }
      _db = null;
    }
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
    await _createTablesAndIndexes(db);
    await _seedInitialUsersIfEmpty(db);
    await _ensureSecuritySettings(db);

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

    // Purge legacy mock/test records from inventory_events
    try {
      await db.delete(
        'inventory_events',
        where:
            "id LIKE 'test_%' OR id LIKE 'mock_%' OR perfumeCode IN ('A', 'B', 'C', 'D')",
      );
    } catch (_) {}

    // Ensure inventory_events has a reason column
    try {
      final info = await db.rawQuery('PRAGMA table_info(inventory_events)');
      final cols = info.map((r) => r['name'] as String).toSet();
      if (!cols.contains('reason')) {
        await db.execute('ALTER TABLE inventory_events ADD COLUMN reason TEXT DEFAULT ""');
      }
    } catch (_) {}
  }

  /// Consolidated single helper containing all 12 tables and 11 indexes (CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS)
  Future<void> _createTablesAndIndexes(DatabaseExecutor db) async {
    // 1. Products Catalog Table
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_events (
        id TEXT PRIMARY KEY,
        eventType TEXT NOT NULL,
        productName TEXT NOT NULL,
        perfumeCode TEXT NOT NULL,
        shelfArea TEXT NOT NULL,
        branch TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        reason TEXT DEFAULT '',
        timestamp INTEGER NOT NULL,
        syncStatus TEXT NOT NULL DEFAULT 'synced'
      )
    ''');

    // 5. Sync Queue Table (Offline Mutation Queue)
    await db.execute('''
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
    await db.execute('''
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

    // 8. Image Quality Logs Table
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // 11. Local Users Table with Password Hashes
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

    // 12. Sales Records Table
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

    // Performance Indexes
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_code ON products(perfumeCode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_branch ON inventory_records(branch)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_code ON inventory_records(perfumeCode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_shelf_regions_branch ON shelf_regions(branch)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_alerts_branch_read ON alerts(branch, isRead)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_inventory_events_branch_time ON inventory_events(branch, timestamp)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_system_logs_branch_time ON system_logs(branch, timestamp)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_status ON sync_queue(status)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sales_records_branch_time ON sales_records(branch, soldAt)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_restock_records_branch ON restock_records(toBranch, fromBranch)',
    );
  }

  @visibleForTesting
  Future<void> createTablesAndIndexes(DatabaseExecutor db) =>
      _createTablesAndIndexes(db);

  Future<void> _onCreate(Database db, int version) async {
    await _createTablesAndIndexes(db);
    await _seedInitialData(db);
  }

  Future<void> _seedInitialData(Database db) async {
    // 1. Seed 60 products (30 variants × 2 sizes across 3 shelf layers/cameras)
    await CatalogSeedData.seedToSqlite(db, branch: 'San Pablo');

    // 2. Seed Default System Settings
    final batch = db.batch();
    final settings = {
      'branch_name': 'San Pablo',
      'captureSchedule': 'Every hour',
      'lowStockThreshold': '2',
      'roiBoundaries': '[0.0, 0.33, 0.66, 1.0]',
      'roiTop': '0.0',
      'roiBottom': '1.0',
      'cameraCount': '3',
      'camera_1_tray_rois':
          '{"AA":{"left":0.06028,"top":0.05912,"right":0.22274,"bottom":0.98},'
          '"AB":{"left":0.26177,"top":0.04656,"right":0.42423,"bottom":0.98},'
          '"AC":{"left":0.45826,"top":0.09903,"right":0.62073,"bottom":0.98},'
          '"AD":{"left":0.67717,"top":0.08573,"right":0.83963,"bottom":0.98},'
          '"AE":{"left":0.85220,"top":0.07982,"right":0.98000,"bottom":0.98}}',
      'camera_2_tray_rois':
          '{"AF":{"left":0.0200,"top":0.10,"right":0.1800,"bottom":0.98},'
          '"AG":{"left":0.2200,"top":0.10,"right":0.3800,"bottom":0.98},'
          '"AH":{"left":0.4200,"top":0.10,"right":0.5800,"bottom":0.98},'
          '"AJ":{"left":0.6200,"top":0.10,"right":0.7800,"bottom":0.98},'
          '"AK":{"left":0.8200,"top":0.10,"right":0.9800,"bottom":0.98}}',
      'camera_3_tray_rois':
          '{"BA":{"left":0.0200,"top":0.10,"right":0.1800,"bottom":0.98},'
          '"BB":{"left":0.2200,"top":0.10,"right":0.3800,"bottom":0.98},'
          '"BC":{"left":0.4200,"top":0.10,"right":0.5800,"bottom":0.98},'
          '"BD":{"left":0.6200,"top":0.10,"right":0.7800,"bottom":0.98},'
          '"BE":{"left":0.8200,"top":0.10,"right":0.9800,"bottom":0.98}}',
      'camera_4_tray_rois':
          '{"BF":{"left":0.0200,"top":0.10,"right":0.1800,"bottom":0.98},'
          '"BG":{"left":0.2200,"top":0.10,"right":0.3800,"bottom":0.98},'
          '"BH":{"left":0.4200,"top":0.10,"right":0.5800,"bottom":0.98},'
          '"BJ":{"left":0.6200,"top":0.10,"right":0.7800,"bottom":0.98},'
          '"BK":{"left":0.8200,"top":0.10,"right":0.9800,"bottom":0.98}}',
      'camera_5_tray_rois':
          '{"CA":{"left":0.1983,"top":0.10,"right":0.3533,"bottom":0.98},'
          '"CB":{"left":0.3658,"top":0.10,"right":0.5208,"bottom":0.98},'
          '"CC":{"left":0.5333,"top":0.10,"right":0.6883,"bottom":0.98},'
          '"CD":{"left":0.7008,"top":0.10,"right":0.8558,"bottom":0.98},'
          '"CE":{"left":0.8916,"top":0.10,"right":1.0000,"bottom":0.98}}',
      'camera_6_tray_rois':
          '{"CF":{"left":0.1803,"top":0.10,"right":0.3353,"bottom":0.98},'
          '"CG":{"left":0.3478,"top":0.10,"right":0.5028,"bottom":0.98},'
          '"CH":{"left":0.5153,"top":0.10,"right":0.6703,"bottom":0.98},'
          '"CJ":{"left":0.6828,"top":0.10,"right":0.8378,"bottom":0.98},'
          '"CK":{"left":0.8556,"top":0.10,"right":1.0000,"bottom":0.98}}',
    };
    settings.forEach((k, v) {
      batch.insert('system_settings', {
        'key': k,
        'value': v,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await batch.commit(noResult: true);
    await _seedInitialUsersIfEmpty(db);
    await _ensureSecuritySettings(db);
  }

  /// Dynamically retrieves current branch name from system_settings.branch_name, defaulting to 'San Pablo'
  Future<String> getBranchName() async {
    try {
      final val = await getSetting('branch_name');
      if (val != null && val.trim().isNotEmpty) {
        return val.trim();
      }
    } catch (_) {}
    return 'San Pablo';
  }

  /// Re-seeds catalog data into SQLite
  Future<void> seedCatalog({String? branch}) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    await CatalogSeedData.seedToSqlite(db, branch: effectiveBranch);
  }

  Future<void> _seedInitialUsersIfEmpty(Database db) async {
    try {
      final rows = await db.rawQuery('SELECT COUNT(*) as count FROM users');
      final count = (rows.isNotEmpty)
          ? (rows.first['count'] as num?)?.toInt() ?? 0
          : 0;
      if (count == 0) {
        final batch = db.batch();
        final now = DateTime.now().millisecondsSinceEpoch;

        // No default hardcoded PIN ('123456'); passwordHash left empty until owner configures PIN
        batch.insert('users', {
          'uid': 'admin_default_sp',
          'email': 'admin@ottoscents.com',
          'passwordHash': '',
          'role': 'admin',
          'branch': 'San Pablo',
          'lastLogin': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        batch.insert('users', {
          'uid': 'staff_default_lipa',
          'email': 'staff1@ottoscents.com',
          'passwordHash': '',
          'role': 'staff',
          'branch': 'Lipa',
          'lastLogin': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await batch.commit(noResult: true);
      }
    } catch (_) {}
  }

  Future<void> _ensureSecuritySettings(Database db) async {
    try {
      // 1. Ensure kiosk_auth_salt exists (32 cryptographically secure random bytes stored as hex)
      final saltRows = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['kiosk_auth_salt'],
      );
      List<int> saltBytes;
      if (saltRows.isEmpty ||
          (saltRows.first['value'] as String? ?? '').trim().isEmpty) {
        saltBytes = Pbkdf2Auth.generateSalt(32);
        final saltHex = Pbkdf2Auth.toHex(saltBytes);
        await db.insert(
          'system_settings',
          {'key': 'kiosk_auth_salt', 'value': saltHex},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else {
        final saltHex = saltRows.first['value'] as String;
        saltBytes = Pbkdf2Auth.fromHex(saltHex);
      }

      // 2. Ensure master_recovery_key_hash exists (PBKDF2-HMAC-SHA256 of default master key)
      final masterRows = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['master_recovery_key_hash'],
      );
      if (masterRows.isEmpty ||
          (masterRows.first['value'] as String? ?? '').trim().isEmpty) {
        final masterHash =
            Pbkdf2Auth.hashPin(defaultMasterRecoveryKey, saltBytes);
        await db.insert(
          'system_settings',
          {'key': 'master_recovery_key_hash', 'value': masterHash},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 3. Ensure failed_pin_attempts exists
      final attemptsRows = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['failed_pin_attempts'],
      );
      if (attemptsRows.isEmpty) {
        await db.insert(
          'system_settings',
          {'key': 'failed_pin_attempts', 'value': '0'},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // 4. Ensure locked_until_epoch exists
      final lockoutRows = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['locked_until_epoch'],
      );
      if (lockoutRows.isEmpty) {
        await db.insert(
          'system_settings',
          {'key': 'locked_until_epoch', 'value': '0'},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    } catch (_) {}
  }

  /// Retrieves the 32-byte salt for kiosk authentication (generating and persisting if absent)
  Future<List<int>> getKioskSaltBytes() async {
    final saltHex = await getSetting('kiosk_auth_salt');
    if (saltHex != null && saltHex.trim().isNotEmpty) {
      try {
        final bytes = Pbkdf2Auth.fromHex(saltHex);
        if (bytes.length >= 16) return bytes;
      } catch (_) {}
    }
    final newSalt = Pbkdf2Auth.generateSalt(32);
    final newSaltHex = Pbkdf2Auth.toHex(newSalt);
    await setSystemSetting('kiosk_auth_salt', newSaltHex, enqueueSync: false);
    return newSalt;
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

  Future<Set<String>> getSeasonalOffSlotCodes({String? branch}) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final Set<String> codes = {};

    final pRows = await db.query(
      'products',
      columns: ['perfumeCode'],
      where: 'status = ? OR status = ?',
      whereArgs: ['seasonal_off', 'inactive'],
    );
    for (final r in pRows) {
      final code = (r['perfumeCode'] as String?)?.trim().toUpperCase();
      if (code != null && code.isNotEmpty) codes.add(code);
    }

    final invRows = await db.query(
      'inventory_records',
      columns: ['perfumeCode'],
      where: 'branch = ? AND (status = ? OR status = ?)',
      whereArgs: [effectiveBranch, 'seasonal_off', 'inactive'],
    );
    for (final r in invRows) {
      final code = (r['perfumeCode'] as String?)?.trim().toUpperCase();
      if (code != null && code.isNotEmpty) codes.add(code);
    }
    return codes;
  }

  Future<void> toggleProductStatus({
    required String productId,
    required String newStatus, // 'active', 'seasonal_off', etc.
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
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
    await db.update(
      'products',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [productId],
    );

    // Also update corresponding inventory record status if seasonal or active
    try {
      String invStatus = 'normal';
      if (newStatus == 'seasonal_off' || newStatus == 'inactive') {
        invStatus = 'seasonal_off';
      } else {
        final currentRows = await db.query(
          'inventory_records',
          columns: ['detected'],
          where: 'perfumeCode = ? AND branch = ?',
          whereArgs: [existing.perfumeCode, effectiveBranch],
          limit: 1,
        );
        final currentDetected = currentRows.isNotEmpty
            ? (currentRows.first['detected'] as num?)?.toInt() ?? 5
            : 5;
        if (currentDetected == 0) {
          invStatus = 'out_of_stock';
        } else if (currentDetected <= 2) {
          invStatus = 'low';
        } else {
          invStatus = 'normal';
        }
      }
      final invUpdateData = <String, dynamic>{'status': invStatus};
      if (invStatus == 'seasonal_off') {
        invUpdateData['detected'] = 0;
      }
      await db.update(
        'inventory_records',
        invUpdateData,
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [existing.perfumeCode, effectiveBranch],
      );

      // Enqueue inventory_record sync to cloud
      final invMaps = await db.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [existing.perfumeCode, effectiveBranch],
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
          branch: effectiveBranch,
        );
      }
    } catch (_) {}

    // Manage active stock alerts based on status transition
    try {
      if (newStatus == 'seasonal_off' || newStatus == 'inactive') {
        // Delete or resolve all active low_stock, out_of_stock, and discrepancy alerts for that perfumeCode
        await db.delete(
          'alerts',
          where:
              '(type = ? OR type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
          whereArgs: [
            'low_stock',
            'lowStock',
            'out_of_stock',
            'outOfStock',
            'discrepancy',
            existing.perfumeCode,
            effectiveBranch,
          ],
        );
      } else if (newStatus == 'active') {
        // When setting newStatus = 'active', re-evaluate current stock and generate an alert if detected <= 2
        final invMaps = await db.query(
          'inventory_records',
          where: 'perfumeCode = ? AND branch = ?',
          whereArgs: [existing.perfumeCode, effectiveBranch],
          limit: 1,
        );
        if (invMaps.isNotEmpty) {
          final detected = (invMaps.first['detected'] as num?)?.toInt() ?? 0;
          final pName = (invMaps.first['name'] as String?) ?? existing.name;
          final now = DateTime.now();

          // Clear any stale alerts first
          await db.delete(
            'alerts',
            where:
                '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
            whereArgs: [
              'low_stock',
              'lowStock',
              'out_of_stock',
              'outOfStock',
              existing.perfumeCode,
              effectiveBranch,
            ],
          );

          if (detected == 0) {
            await db.insert(
              'alerts',
              {
                'id': 'alert_oos_${effectiveBranch}_${existing.perfumeCode}',
                'title': 'Out of Stock Alert',
                'desc':
                    'Slot ${existing.perfumeCode} ($pName): 0 bottles remaining. Immediate refill required.',
                'branch': effectiveBranch,
                'type': 'out_of_stock',
                'perfumeCode': existing.perfumeCode,
                'isRead': 0,
                'createdAt': now.millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } else if (detected <= 2) {
            await db.insert(
              'alerts',
              {
                'id': 'alert_low_stock_${effectiveBranch}_${existing.perfumeCode}',
                'title': 'Low Stock Alert',
                'desc':
                    'Slot ${existing.perfumeCode} ($pName): Low stock ($detected remaining, Threshold: 2 bottles).',
                'branch': effectiveBranch,
                'type': 'low_stock',
                'perfumeCode': existing.perfumeCode,
                'isRead': 0,
                'createdAt': now.millisecondsSinceEpoch,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    } catch (_) {}

    // Queue sync for products using targeted UPDATE operation
    try {
      await enqueueSyncItem(
        id: 'sync_prod_status_${productId}_${DateTime.now().millisecondsSinceEpoch}',
        pendingEventId: productId,
        targetCollection: 'products',
        operation: 'UPDATE',
        payload: {'status': newStatus},
        branch: effectiveBranch,
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
      branch: effectiveBranch,
    );
  }

  /// Updates product status directly and enqueues targeted UPDATE sync item
  Future<void> updateProductStatus(
    String productId,
    String newStatus, {
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    await db.update(
      'products',
      {'status': newStatus},
      where: 'id = ?',
      whereArgs: [productId],
    );

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_prod_status_${productId}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: productId,
          targetCollection: 'products',
          operation: 'UPDATE',
          payload: {'status': newStatus},
          branch: effectiveBranch,
        );
      } catch (_) {}
    }
  }

  Future<void> saveProduct(
    ProductModel product, {
    bool enqueueSync = true,
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
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
          branch: effectiveBranch,
        );
      } catch (_) {}
    }

    // Automatically audit log product catalog addition/modification
    if (enqueueSync) {
      await logActivity(
        type: 'PRODUCT_CATALOG',
        description:
            'Product "${product.name}" (${product.perfumeCode} • ${product.bottleSize}) updated in catalog.',
        branch: effectiveBranch,
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<void> deleteProduct(
    String id, {
    bool enqueueSync = true,
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
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
          branch: effectiveBranch,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'PRODUCT_DELETE',
        description: 'Product SKU #$id deleted from catalog.',
        branch: effectiveBranch,
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
  Future<List<InventoryRecordModel>> getInventoryRecords([String? branch]) =>
      getInventory(branch);

  Future<List<InventoryRecordModel>> getInventory([String? branch]) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != 'All Branches') {
      final effectiveBranch = branch ?? await getBranchName();
      maps = await db.query(
        'inventory_records',
        where: 'branch = ?',
        whereArgs: [effectiveBranch],
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
    String perfumeCode, [
    String? branch,
  ]) async {
    final db = await database;
    final effectiveBranch = branch ?? await getBranchName();
    final maps = await db.query(
      'inventory_records',
      where: 'perfumeCode = ? AND branch = ?',
      whereArgs: [perfumeCode, effectiveBranch],
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
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
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
          branch: effectiveBranch,
        );
      } catch (_) {}
    }
  }

  /// Helper mapping logical camera ID (1-6) to its 5 tray codes
  static List<String> getDefaultTrayCodesForCamera(int cameraId) {
    switch (cameraId) {
      case 1:
        return ['AA', 'AB', 'AC', 'AD', 'AE'];
      case 2:
        return ['AF', 'AG', 'AH', 'AJ', 'AK'];
      case 3:
        return ['BA', 'BB', 'BC', 'BD', 'BE'];
      case 4:
        return ['BF', 'BG', 'BH', 'BJ', 'BK'];
      case 5:
        return ['CA', 'CB', 'CC', 'CD', 'CE'];
      case 6:
        return ['CF', 'CG', 'CH', 'CJ', 'CK'];
      default:
        return ['AA', 'AB', 'AC', 'AD', 'AE'];
    }
  }

  static final Map<String, String> _perfumeFullNameCache = {};

  /// Resolves the full descriptive fragrance name with size for any 3-char SKU code (e.g. CD1 -> 'Estee Lauder Pleasures (100ML)')
  static String getPerfumeFullName(String code) {
    if (_perfumeFullNameCache.isEmpty) {
      for (final p in CatalogSeedData.products) {
        final sizeStr = p.bottleSize.replaceAll('ml', 'ML');
        _perfumeFullNameCache[p.perfumeCode] = '${p.name} ($sizeStr)';
      }
    }
    return _perfumeFullNameCache[code] ?? code;
  }

  /// Formats perfume item count strictly in user's requested format: [how many] [code] [perfume name]
  /// Example: '5x CD1 - Estee Lauder Pleasures (100ML)'
  static String formatPerfumeItem(int count, String code) {
    final name = getPerfumeFullName(code);
    return '${count}x $code - $name';
  }

  /// Extracts the base perfume title for a 2-char tray code (e.g. 'CD' -> 'Estee Lauder Pleasures')
  static String getTrayTitle(String trayCode) {
    final code1 = '${trayCode}1';
    final full = getPerfumeFullName(code1);
    return full.replaceAll(RegExp(r'\s*\(\d+ML\)$', caseSensitive: false), '').trim();
  }

  /// Automatically maps 2-char tray code to its observing hardware camera ID (1-6)
  static int getCameraIdForTray(String trayCode) {
    if (trayCode.isEmpty) return 1;
    final layer = trayCode[0].toUpperCase();
    final slot = trayCode.length > 1 ? trayCode[1].toUpperCase() : 'A';
    final isRight = ['F', 'G', 'H', 'J', 'K'].contains(slot);
    if (layer == 'A') return isRight ? 2 : 1;
    if (layer == 'B') return isRight ? 4 : 3;
    if (layer == 'C') return isRight ? 6 : 5;
    return 1;
  }

  /// Helper mapping logical camera ID (1-6) to its 10 product slot codes (50ml and 100ml)
  static List<String> getSlotCodesForCamera(int cameraId) {
    final trays = getDefaultTrayCodesForCamera(cameraId);
    final codes = <String>[];
    for (final t in trays) {
      codes.add('${t}1');
      codes.add('${t}2');
    }
    return codes;
  }

  /// Public alias for processing vision scan results (R3)
  Future<Map<String, int>> processScanResults({
    required int cameraId,
    required List<Map<String, dynamic>> detections,
    String? branch,
    List<String>? targetSlotCodes,
    List<String>? targetTrayCodes,
  }) =>
      updateInventoryFromDetections(
        cameraId: cameraId,
        detections: detections,
        branch: branch,
        targetSlotCodes: targetSlotCodes,
        targetTrayCodes: targetTrayCodes,
      );

  /// Updates inventory records' detected bottle counts after an AI vision scan.
  /// Maps detected bounding boxes to calibrated ROIs for the camera, or uses
  /// recognized SKU codes. If slot ROIs are not calibrated, distributes detected
  /// bottles across active slots for the camera.
  Future<Map<String, int>> updateInventoryFromDetections({
    required int cameraId,
    required List<Map<String, dynamic>> detections,
    String? branch,
    List<String>? targetSlotCodes,
    List<String>? targetTrayCodes,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final now = DateTime.now();
    final lowThreshold = await getLowStockThreshold();

    // 1. Fetch calibrated tray ROIs for this camera
    Map<String, dynamic>? slotRois;
    try {
      final savedJson = await getSetting('camera_${cameraId}_tray_rois');
      if (savedJson != null && savedJson.isNotEmpty) {
        final raw = jsonDecode(savedJson);
        if (raw is Map) {
          slotRois = {};
          raw.forEach((k, v) {
            final cleanKey = k.toString().replaceFirst('tray_', '').trim().toUpperCase();
            slotRois![cleanKey] = v;
          });
        }
      }
    } catch (_) {}

    final defaultTrays = getDefaultTrayCodesForCamera(cameraId);

    // Derive active trays targeted for update
    final Set<String> activeTraySet = {};
    if (targetTrayCodes != null && targetTrayCodes.isNotEmpty) {
      activeTraySet.addAll(
        targetTrayCodes.map((t) => t.replaceFirst('tray_', '').trim().toUpperCase()),
      );
    } else if (targetSlotCodes != null && targetSlotCodes.isNotEmpty) {
      for (final c in targetSlotCodes) {
        final clean = c.replaceAll(RegExp(r'\d+$'), '').trim().toUpperCase();
        activeTraySet.add(clean);
      }
    } else {
      activeTraySet.addAll(defaultTrays);
    }

    // Geometry Rect for each of the 5 physical trays on this camera
    final Map<String, Rect> trayRects = {};
    for (int i = 0; i < defaultTrays.length; i++) {
      final code = defaultTrays[i];
      if (slotRois != null && slotRois.containsKey(code)) {
        final r = slotRois[code] as Map<String, dynamic>;
        trayRects[code] = Rect.fromLTRB(
          (r['left'] as num?)?.toDouble() ?? 0.0,
          (r['top'] as num?)?.toDouble() ?? 0.10,
          (r['right'] as num?)?.toDouble() ?? 1.0,
          (r['bottom'] as num?)?.toDouble() ?? 0.98,
        );
      } else if (slotRois != null &&
          (slotRois.containsKey('${code}1') || slotRois.containsKey('${code}2'))) {
        final r1 = slotRois['${code}1'] as Map<String, dynamic>?;
        final r2 = slotRois['${code}2'] as Map<String, dynamic>?;
        final l = (r1?['left'] as num?)?.toDouble() ?? (r2?['left'] as num?)?.toDouble() ?? 0.0;
        final t = (r1?['top'] as num?)?.toDouble() ?? (r2?['top'] as num?)?.toDouble() ?? 0.10;
        final r = (r2?['right'] as num?)?.toDouble() ?? (r1?['right'] as num?)?.toDouble() ?? 1.0;
        final b = (r1?['bottom'] as num?)?.toDouble() ?? (r2?['bottom'] as num?)?.toDouble() ?? 0.98;
        trayRects[code] = Rect.fromLTRB(l, t, r, b);
      } else {
        // Contiguous midpoint partitioning across default 5 trays (0% dead-zone gaps)
        final count = defaultTrays.length;
        final step = 1.0 / count;
        final l = i * step;
        final r = (i + 1) * step;
        trayRects[code] = Rect.fromLTRB(l, 0.10, r, 0.98);
      }
    }

    final Map<String, List<Map<String, dynamic>>> trayDetections = {
      for (final t in defaultTrays) t: <Map<String, dynamic>>[],
    };

    // 1. Spatially map each detection to its physical tray
    for (int detIdx = 0; detIdx < detections.length; detIdx++) {
      final det = detections[detIdx];
      if (det['roiId'] == 'outside_shelf_roi') {
        continue;
      }

      double detCenterX = (det['centerX'] as num?)?.toDouble() ?? 0.0;
      final bbox = det['bbox'] ?? det['boundingBox'];
      double bx = 0, bw = 0;
      if (bbox is List && bbox.length >= 3) {
        bx = (bbox[0] as num).toDouble();
        bw = (bbox[2] as num).toDouble();
      }
      if (detCenterX <= 0.0) {
        detCenterX = bx + (bw > 0 ? bw / 2 : 0.02);
      }
      det['_detCenterX'] = detCenterX;

      String? physicalTray;
      final rawRoi = det['roiId'] as String?;
      if (rawRoi != null && rawRoi.isNotEmpty) {
        final clean = rawRoi.replaceFirst('tray_', '').trim().toUpperCase();
        if (defaultTrays.contains(clean)) {
          physicalTray = clean;
        }
      }

      if (physicalTray == null) {
        for (final t in defaultTrays) {
          final tr = trayRects[t]!;
          if (detCenterX >= tr.left && detCenterX <= tr.right) {
            physicalTray = t;
            break;
          }
        }
      }

      if (physicalTray != null && trayDetections.containsKey(physicalTray)) {
        trayDetections[physicalTray]!.add(det);
      }
    }

    // 2. Process active trays: centerline partition into 100ML (left, max 5) and 50ML (right, max 5)
    final Map<String, int> productDetectedCounts = {};
    final List<Map<String, dynamic>> misplacedItems = [];

    for (final trayCode in defaultTrays) {
      if (!activeTraySet.contains(trayCode)) {
        continue; // Unselected tray: NEVER modified in selective scanning
      }

      final detsInTray = trayDetections[trayCode] ?? [];
      final tr = trayRects[trayCode]!;
      double trayMidX = (tr.left + tr.right) / 2.0;

      // Dynamic cluster midpoint calculation (R3):
      // When detections within a tray exhibit two distinct bottle column clusters separated
      // by a gap (>= 0.025), calculate the cluster midpoint dynamically to ensure resilience
      // against minor physical tray shifts or bottle placement variations.
      // Fall back gracefully to (tr.left + tr.right) / 2.0 when fewer bottles exist
      // or when bottles belong to only one column.
      if (detsInTray.length >= 2) {
        final xCoords = detsInTray
            .map((det) => (det['_detCenterX'] as double?) ?? 0.0)
            .toList()
          ..sort();

        final trayWidth = tr.right - tr.left;
        final nominalMid = trayMidX;
        double maxGap = 0.0;
        int bestSplitIndex = -1;

        for (int i = 0; i < xCoords.length - 1; i++) {
          final gap = xCoords[i + 1] - xCoords[i];
          final leftCount = i + 1;
          final rightCount = xCoords.length - leftCount;
          // Valid two-cluster partition: each side has at least 1 and at most 5 bottles,
          // separated by a distinct gap (>= 0.025).
          // Crucially, the candidate midpoint must lie near the nominal divider corridor
          // (within 18% of tray width), the two clusters must reside on opposite sides of the
          // nominal divider corridor (C1 in left slot, C2 in right slot), and the column
          // centroids must be distinctly separated (>= 25% of tray width) to ensure this gap
          // separates two physical columns rather than intra-column jitter on one side.
          if (gap >= 0.025 && leftCount <= 5 && rightCount <= 5) {
            final candidateMid = (xCoords[i] + xCoords[i + 1]) / 2.0;
            final isNearDivider = (candidateMid - nominalMid).abs() <= trayWidth * 0.18;
            final c1 = xCoords.sublist(0, leftCount).reduce((a, b) => a + b) / leftCount;
            final c2 = xCoords.sublist(leftCount).reduce((a, b) => a + b) / rightCount;
            final clustersOnCorrectSides = c1 < nominalMid && c2 > nominalMid;
            final clusterSeparation = (c2 - c1) >= trayWidth * 0.25;

            if (candidateMid > tr.left &&
                candidateMid < tr.right &&
                isNearDivider &&
                clustersOnCorrectSides &&
                clusterSeparation) {
              if (gap > maxGap) {
                maxGap = gap;
                bestSplitIndex = i;
              }
            }
          }
        }

        if (bestSplitIndex != -1) {
          trayMidX = (xCoords[bestSplitIndex] + xCoords[bestSplitIndex + 1]) / 2.0;
        }
      }

      int count100ml = 0;
      int count50ml = 0;

      for (final det in detsInTray) {
        // Legacy misplacement detection for tests
        final rawCode = (det['recognizedCode'] as String?)?.trim().toUpperCase() ?? '';
        final String recognizedCode = (rawCode == 'UNREADABLE') ? '' : rawCode;
        String? expectedTray;
        String? bottleSize;
        if (RegExp(r'^[A-C][A-HJ-K][1-2]$').hasMatch(recognizedCode)) {
          expectedTray = recognizedCode.substring(0, 2);
          bottleSize = recognizedCode.substring(2);
        }

        if (expectedTray != null && expectedTray != trayCode) {
          det['matchResult'] = 'misplaced';
          misplacedItems.add({
            'recognizedCode': recognizedCode,
            'expectedTray': expectedTray,
            'physicalTray': trayCode,
            'bottleSize': bottleSize ?? '1',
            'det': det,
          });
        } else if (expectedTray != null && expectedTray == trayCode) {
          det['matchResult'] = 'matched';
        }

        // Centerline partitioning per R4:
        // Left half (< trayMidX) counts toward 100ML (slot 1), max 5
        // Right half (>= trayMidX) counts toward 50ML (slot 2), max 5
        final cx = (det['_detCenterX'] as double?) ?? 0.0;
        if (cx < trayMidX) {
          if (count100ml < 5) count100ml++;
        } else {
          if (count50ml < 5) count50ml++;
        }
      }

      final code1 = '${trayCode}1'; // 100ML
      final code2 = '${trayCode}2'; // 50ML

      // If targeted by specific slots, only include the selected slots
      if (targetSlotCodes != null && targetSlotCodes.isNotEmpty) {
        if (targetSlotCodes.contains(code1)) {
          productDetectedCounts[code1] = count100ml;
        }
        if (targetSlotCodes.contains(code2)) {
          productDetectedCounts[code2] = count50ml;
        }
      } else {
        productDetectedCounts[code1] = count100ml;
        productDetectedCounts[code2] = count50ml;
      }
    }

    // Fetch existing recorded counts and status for the active targeted slots
    final Map<String, int> recordedCounts = {};
    final Map<String, String> slotStatuses = {};
    if (productDetectedCounts.isNotEmpty) {
      final placeholders =
          List.filled(productDetectedCounts.keys.length, '?').join(',');
      final existingRows = await db.query(
        'inventory_records',
        columns: ['perfumeCode', 'recorded', 'status'],
        where: 'perfumeCode IN ($placeholders) AND branch = ?',
        whereArgs: [...productDetectedCounts.keys, effectiveBranch],
      );
      for (final row in existingRows) {
        final pCode = row['perfumeCode'] as String;
        recordedCounts[pCode] = (row['recorded'] as num?)?.toInt() ?? 5;
        slotStatuses[pCode] = row['status'] as String? ?? 'normal';
      }

      // Cross-check products table status for seasonal_off or inactive
      final productRows = await db.query(
        'products',
        columns: ['perfumeCode', 'status'],
        where: 'perfumeCode IN ($placeholders)',
        whereArgs: [...productDetectedCounts.keys],
      );
      for (final pRow in productRows) {
        final pCode = pRow['perfumeCode'] as String;
        final pStatus = pRow['status'] as String? ?? 'active';
        if (pStatus == 'seasonal_off' || pStatus == 'inactive') {
          slotStatuses[pCode] = 'seasonal_off';
        }
      }
    }

    // Query active unread discrepancy alerts for the targeted slots
    final Set<String> activeDiscrepancyCodes = {};
    if (productDetectedCounts.isNotEmpty) {
      final placeholders =
          List.filled(productDetectedCounts.keys.length, '?').join(',');
      final activeAlertRows = await db.query(
        'alerts',
        columns: ['perfumeCode'],
        where:
            'type = ? AND isRead = 0 AND perfumeCode IN ($placeholders) AND branch = ?',
        whereArgs: ['discrepancy', ...productDetectedCounts.keys, effectiveBranch],
      );
      for (final row in activeAlertRows) {
        final pCode = row['perfumeCode'] as String?;
        if (pCode != null) activeDiscrepancyCodes.add(pCode);
      }
    }

    // 3. Batch update SQLite ONLY for active targeted slots
    final batch = db.batch();

    for (final entry in productDetectedCounts.entries) {
      final code = entry.key;
      final rawDetected = entry.value;
      final detectedCount = rawDetected.clamp(0, 5); // Invariant: clamp detectedCount <= 5
      final recordedCount = recordedCounts[code] ?? 5;
      final bool hasDiscrepancy = detectedCount != recordedCount;

      final matchingMisplaced = misplacedItems.where((m) =>
          m['recognizedCode'] == code || '${m['expectedTray']}${m['bottleSize']}' == code).firstOrNull;
      final bool isMisplaced = matchingMisplaced != null;
      final String misplacementDetail = isMisplaced
          ? 'Detected in Tray ${matchingMisplaced['physicalTray']} (Expected: Tray ${matchingMisplaced['expectedTray']})'
          : '';

      final currentSlotStatus = slotStatuses[code] ?? 'normal';
      final bool isSeasonalOff =
          currentSlotStatus == 'seasonal_off' || currentSlotStatus == 'inactive';

      final effectiveDetected = isSeasonalOff ? 0 : detectedCount;
      productDetectedCounts[code] = effectiveDetected;

      final String newStatus = isSeasonalOff
          ? 'seasonal_off'
          : (isMisplaced
              ? 'misplaced'
              : (detectedCount == 0
                  ? 'out_of_stock'
                  : (detectedCount <= lowThreshold
                      ? 'low'
                      : (hasDiscrepancy ? 'needs_review' : 'normal'))));

      batch.update(
        'inventory_records',
        {
          'detected': effectiveDetected,
          'status': newStatus,
          'misplacementDetails': misplacementDetail,
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [code, effectiveBranch],
      );

      // Clean or insert alerts
      if (!isMisplaced) {
        batch.delete(
          'alerts',
          where: 'type = ? AND perfumeCode = ? AND branch = ?',
          whereArgs: ['misplaced', code, effectiveBranch],
        );
      }

      // Discrepancy Alert logic: alert when detected != recorded (suppressed for seasonal off)
      if (hasDiscrepancy && !isMisplaced && !isSeasonalOff) {
        final pName = getPerfumeFullName(code);
        batch.insert(
          'alerts',
          {
            'id': 'alert_discrepancy_${effectiveBranch}_$code',
            'title': 'Stock Discrepancy Detected',
            'desc':
                'Slot $code ($pName): Camera detected $detectedCount bottle(s), but ledger recorded $recordedCount bottle(s).',
            'branch': effectiveBranch,
            'type': 'discrepancy',
            'perfumeCode': code,
            'isRead': 0,
            'createdAt': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      } else if (!hasDiscrepancy || isSeasonalOff) {
        // If an active unread discrepancy alert was logged for this slot and the physical count
        // returned to recorded count without staff taking action/resolving it, do NOT silently
        // delete the alert! Doing so would erase revenue audit trails if a bottle was removed/sold
        // and subsequently restocked without logging.
        final hadActiveDiscrepancy = activeDiscrepancyCodes.contains(code);
        if (!hadActiveDiscrepancy || isSeasonalOff) {
          batch.delete(
            'alerts',
            where: 'type = ? AND perfumeCode = ? AND branch = ?',
            whereArgs: ['discrepancy', code, effectiveBranch],
          );
        } else {
          // Flag as Unreconciled Discrepancy anomaly: count recovered to recorded count,
          // but previous movement has not been logged in ledger.
          final pName = getPerfumeFullName(code);
          batch.update(
            'alerts',
            {
              'title': 'Unreconciled Discrepancy (Anomaly)',
              'desc':
                  'Slot $code ($pName): Physical shelf count returned to $detectedCount bottle(s), but previous deficit was not logged in ledger. Please verify if sold & restocked or returned.',
            },
            where: 'type = ? AND perfumeCode = ? AND branch = ? AND isRead = 0',
            whereArgs: ['discrepancy', code, effectiveBranch],
          );
        }
      }

      if (isSeasonalOff) {
        // Skip low-stock and out-of-stock alert generation for seasonal off slots
        batch.delete(
          'alerts',
          where:
              '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
          whereArgs: [
            'low_stock',
            'lowStock',
            'out_of_stock',
            'outOfStock',
            code,
            effectiveBranch,
          ],
        );
      } else if (detectedCount > lowThreshold) {
        // Auto-resolve stock alert whenever subsequent scan detects stock >= 3
        batch.delete(
          'alerts',
          where:
              '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
          whereArgs: [
            'low_stock',
            'lowStock',
            'out_of_stock',
            'outOfStock',
            code,
            effectiveBranch,
          ],
        );
      } else {
        // Trigger low_stock alert whenever slot count <= lowThreshold (including 0)
        final pName = getPerfumeFullName(code);
        batch.insert(
          'alerts',
          {
            'id': 'alert_low_stock_${effectiveBranch}_$code',
            'title': 'Low Stock Alert',
            'desc':
                'Low Stock: ${detectedCount}x $code - $pName remaining (Threshold: 2 bottles).',
            'branch': effectiveBranch,
            'type': 'low_stock',
            'perfumeCode': code,
            'isRead': 0,
            'createdAt': now.millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (detectedCount == 0) {
          batch.insert(
            'alerts',
            {
              'id': 'alert_oos_${effectiveBranch}_$code',
              'title': 'Out of Stock Alert',
              'desc':
                  'Slot $code ($pName): 0 bottles remaining. Immediate refill required.',
              'branch': effectiveBranch,
              'type': 'out_of_stock',
              'perfumeCode': code,
              'isRead': 0,
              'createdAt': now.millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          // If stock recovered to 1-2, clean up any auto out_of_stock alert
          batch.delete(
            'alerts',
            where: '(type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
            whereArgs: ['out_of_stock', 'outOfStock', code, effectiveBranch],
          );
        }
      }
    }

    // Insert legacy misplaced alerts if any
    for (int i = 0; i < misplacedItems.length; i++) {
      final m = misplacedItems[i];
      final code = m['recognizedCode'] as String;
      final exp = m['expectedTray'] as String;
      final sz = m['bottleSize'] as String;
      final fullCode = code.length == 3 ? code : '$exp$sz';
      final phys = m['physicalTray'] as String;
      final pName = getPerfumeFullName(fullCode);

      batch.insert(
        'alerts',
        {
          'id': 'alert_misplaced_${fullCode}_${now.millisecondsSinceEpoch}_$i',
          'title': 'Misplaced Bottle Detected',
          'desc': 'Bottle 1x $fullCode - $pName was detected in Tray $phys. Expected location is Tray $exp.',
          'branch': effectiveBranch,
          'type': 'misplaced',
          'perfumeCode': fullCode,
          'isRead': 0,
          'createdAt': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      batch.insert(
        'inventory_events',
        {
          'id': 'evt_misplaced_${now.millisecondsSinceEpoch}_$i',
          'eventType': 'MISPLACED',
          'productName': pName,
          'perfumeCode': fullCode,
          'shelfArea': 'Tray $phys',
          'branch': effectiveBranch,
          'quantity': 1,
          'timestamp': now.millisecondsSinceEpoch,
          'syncStatus': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    return productDetectedCounts;
  }

  /// Safely updates inventory records for ONLY a single targeted tray (e.g. 'CD')
  /// without modifying or zeroing out unselected trays.
  Future<Map<String, int>> updateTrayInventoryFromDetections({
    required int cameraId,
    required String trayCode,
    required List<Map<String, dynamic>> detections,
    String? branch,
  }) async {
    return updateInventoryFromDetections(
      cameraId: cameraId,
      detections: detections,
      branch: branch,
      targetTrayCodes: [trayCode],
    );
  }

  /// One-click automated restock order creation per R4.
  /// Finds all items with low/out-of-stock count (<= 2 bottles),
  /// generates restock orders pre-populating refill quantities up to the slot capacity of 5,
  /// updates inventory records to 5 bottles, and auto-resolves low_stock alerts.
  Future<int> createAutoRestockOrder({String? branch}) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final now = DateTime.now();
    final lowThreshold = await getLowStockThreshold();

    final allInv = await getInventoryRecords(effectiveBranch);
    final restockCandidates = allInv
        .where((i) =>
            !i.isSeasonalOff &&
            (i.detected <= lowThreshold || i.status == 'low' || i.status == 'out_of_stock') &&
            i.detected < 5)
        .toList();

    if (restockCandidates.isEmpty) return 0;

    final batch = db.batch();
    for (int i = 0; i < restockCandidates.length; i++) {
      final item = restockCandidates[i];
      final refillQty = (5 - item.detected).clamp(1, 5);
      final pName = item.name.isNotEmpty ? item.name : getPerfumeFullName(item.perfumeCode);

      final restockId = 'rst_${item.perfumeCode}_${now.millisecondsSinceEpoch}_$i';
      batch.insert(
        'restock_records',
        {
          'id': restockId,
          'productName': pName,
          'perfumeCode': item.perfumeCode,
          'quantity': refillQty,
          'fromBranch': 'Main Warehouse',
          'toBranch': effectiveBranch,
          'requestedBy': 'Kiosk Auto-Restock',
          'status': 'received',
          'createdAt': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final eventId = 'evt_restock_${item.perfumeCode}_${now.millisecondsSinceEpoch}_$i';
      batch.insert(
        'inventory_events',
        {
          'id': eventId,
          'eventType': 'RESTOCKED',
          'productName': pName,
          'perfumeCode': item.perfumeCode,
          'shelfArea': item.shelf,
          'branch': effectiveBranch,
          'quantity': refillQty,
          'timestamp': now.millisecondsSinceEpoch,
          'syncStatus': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      batch.update(
        'inventory_records',
        {
          'recorded': 5,
          'detected': 5,
          'status': 'normal',
          'misplacementDetails': '',
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [item.perfumeCode, effectiveBranch],
      );

      batch.delete(
        'alerts',
        where: '(type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
        whereArgs: ['low_stock', 'lowStock', 'out_of_stock', item.perfumeCode, effectiveBranch],
      );
    }

    await batch.commit(noResult: true);
    return restockCandidates.length;
  }

  // ---------------------------------------------------------------------------
  // INVENTORY EVENTS (MOVEMENT LOGS) CRUD
  // ---------------------------------------------------------------------------
  Future<List<InventoryEventModel>> getInventoryEvents([
    String? branch,
    int limit = 100,
  ]) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != 'All Branches') {
      final effectiveBranch = branch ?? await getBranchName();
      maps = await db.query(
        'inventory_events',
        where: 'branch = ?',
        whereArgs: [effectiveBranch],
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
  Future<List<AlertModel>> getAlerts(String? branch, {bool? unreadOnly}) async {
    final db = await database;
    final effectiveBranch = (branch != null && branch != 'All Branches')
        ? branch
        : await getBranchName();

    // Synchronize active alerts with current inventory detection (skip when querying history with unreadOnly: false)
    if (unreadOnly != false) {
      try {
        final now = DateTime.now();
        // Query all inventory_records for the branch where status != 'seasonal_off' and status != 'inactive'
        final invRows = await db.query(
          'inventory_records',
          where: 'branch = ? AND status != ? AND status != ?',
          whereArgs: [effectiveBranch, 'seasonal_off', 'inactive'],
        );

        if (invRows.isNotEmpty) {
          final unreadAlerts = await db.query(
            'alerts',
            where: 'branch = ? AND isRead = 0',
            whereArgs: [effectiveBranch],
          );

          final Map<String, List<Map<String, dynamic>>> unreadByCode = {};
          for (final a in unreadAlerts) {
            final pCode = a['perfumeCode'] as String?;
            if (pCode != null && pCode.isNotEmpty) {
              unreadByCode.putIfAbsent(pCode, () => []).add(a);
            }
          }

          final batch = db.batch();
          bool hasChanges = false;

          // Cross-check products table for seasonal_off or inactive to ensure alerts are suppressed
          final seasonalOffProducts = await db.query(
            'products',
            columns: ['perfumeCode'],
            where: 'status = ? OR status = ?',
            whereArgs: ['seasonal_off', 'inactive'],
          );
          final seasonalOffCodes = seasonalOffProducts
              .map((r) => r['perfumeCode'] as String)
              .toSet();

          for (final row in invRows) {
            final code = row['perfumeCode'] as String;
            if (seasonalOffCodes.contains(code)) continue;

            final detected = (row['detected'] as num?)?.toInt() ?? 0;
            final pName = (row['name'] as String?) ?? getPerfumeFullName(code);
            final existingUnread = unreadByCode[code] ?? [];

            if (detected == 0) {
              final hasOos = existingUnread.any((a) =>
                  a['type'] == 'out_of_stock' || a['type'] == 'outOfStock');
              if (!hasOos) {
                batch.insert(
                  'alerts',
                  {
                    'id': 'alert_oos_${effectiveBranch}_$code',
                    'title': 'Out of Stock Alert',
                    'desc':
                        'Slot $code ($pName): 0 bottles remaining. Immediate refill required.',
                    'branch': effectiveBranch,
                    'type': 'out_of_stock',
                    'perfumeCode': code,
                    'isRead': 0,
                    'createdAt': now.millisecondsSinceEpoch,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                hasChanges = true;
              }
              final hasLow = existingUnread.any((a) =>
                  a['type'] == 'low_stock' || a['type'] == 'lowStock');
              if (!hasLow) {
                batch.insert(
                  'alerts',
                  {
                    'id': 'alert_low_stock_${effectiveBranch}_$code',
                    'title': 'Low Stock Alert',
                    'desc':
                        'Slot $code ($pName): Low stock (0 remaining, Threshold: 2 bottles).',
                    'branch': effectiveBranch,
                    'type': 'low_stock',
                    'perfumeCode': code,
                    'isRead': 0,
                    'createdAt': now.millisecondsSinceEpoch,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                hasChanges = true;
              }
            } else if (detected > 0 && detected <= 2) {
              final hasLow = existingUnread.any((a) =>
                  a['type'] == 'low_stock' || a['type'] == 'lowStock');
              if (!hasLow) {
                batch.insert(
                  'alerts',
                  {
                    'id': 'alert_low_stock_${effectiveBranch}_$code',
                    'title': 'Low Stock Alert',
                    'desc':
                        'Slot $code ($pName): Low stock ($detected remaining, Threshold: 2 bottles).',
                    'branch': effectiveBranch,
                    'type': 'low_stock',
                    'perfumeCode': code,
                    'isRead': 0,
                    'createdAt': now.millisecondsSinceEpoch,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                hasChanges = true;
              }
              // If stock recovered to 1-2, clean up any auto out_of_stock alert
              final oosAlerts = existingUnread.where((a) {
                final id = (a['id'] as String?) ?? '';
                final type = a['type'] as String?;
                return (type == 'out_of_stock' || type == 'outOfStock') &&
                    (id.startsWith('alert_oos_') || id.startsWith('alert_out_of_stock_'));
              }).toList();
              for (final oos in oosAlerts) {
                batch.delete('alerts', where: 'id = ?', whereArgs: [oos['id']]);
                hasChanges = true;
              }
            } else if (detected >= 3) {
              final stockAlertsToResolve = existingUnread.where((a) {
                final id = (a['id'] as String?) ?? '';
                final type = a['type'] as String?;
                final isStockType = type == 'low_stock' ||
                    type == 'lowStock' ||
                    type == 'out_of_stock' ||
                    type == 'outOfStock';
                final isAutoStockAlert = id.startsWith('alert_low_stock_') ||
                    id.startsWith('alert_oos_') ||
                    id.startsWith('alert_out_of_stock_') ||
                    id.startsWith('alert_stock_');
                return isStockType && isAutoStockAlert;
              }).toList();

              for (final alertToResolve in stockAlertsToResolve) {
                batch.delete(
                  'alerts',
                  where: 'id = ?',
                  whereArgs: [alertToResolve['id']],
                );
                hasChanges = true;
              }
            }
          }

          // Clean up any unread stock alerts for seasonal_off or inactive slots
          final seasonalOffRows = await db.query(
            'inventory_records',
            columns: ['perfumeCode'],
            where: 'branch = ? AND (status = ? OR status = ?)',
            whereArgs: [effectiveBranch, 'seasonal_off', 'inactive'],
          );
          final allSeasonalOffCodes = {
            ...seasonalOffRows.map((r) => r['perfumeCode'] as String),
            ...seasonalOffCodes,
          };
          for (final sCode in allSeasonalOffCodes) {
            if (unreadByCode.containsKey(sCode)) {
              final hasStockAlert = unreadByCode[sCode]!.any((a) =>
                  a['type'] == 'low_stock' ||
                  a['type'] == 'lowStock' ||
                  a['type'] == 'out_of_stock' ||
                  a['type'] == 'outOfStock');
              if (hasStockAlert) {
                batch.delete(
                  'alerts',
                  where:
                      '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ? AND isRead = 0',
                  whereArgs: [
                    'low_stock',
                    'lowStock',
                    'out_of_stock',
                    'outOfStock',
                    sCode,
                    effectiveBranch,
                  ],
                );
                hasChanges = true;
              }
            }
          }

          if (hasChanges) {
            await batch.commit(noResult: true);
          }
        }
      } catch (_) {}
    }

    List<Map<String, dynamic>> maps;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (branch != 'All Branches') {
      conditions.add('branch = ?');
      args.add(effectiveBranch);
    }

    if (unreadOnly != null) {
      conditions.add('isRead = ?');
      args.add(unreadOnly ? 0 : 1);
    }

    final whereClause = conditions.isNotEmpty ? conditions.join(' AND ') : null;

    maps = await db.query(
      'alerts',
      where: whereClause,
      whereArgs: args.isNotEmpty ? args : null,
      orderBy: 'createdAt DESC',
    );

    return maps
        .map((m) => AlertModel.fromMap(m, m['id'] as String? ?? ''))
        .toList();
  }

  Future<List<AlertModel>> getAlertsHistory([String? branch]) =>
      getAlerts(branch, unreadOnly: false);

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

  Future<void> markAlertRead(
    String id, {
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    await db.update('alerts', {'isRead': 1}, where: 'id = ?', whereArgs: [id]);

    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_read_alert_${id}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: id,
          targetCollection: 'alerts',
          operation: 'UPDATE',
          payload: {'id': id, 'isRead': 1},
          branch: effectiveBranch,
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
    final effectiveBranch = branch ?? await getBranchName();

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
              operation: 'UPDATE',
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
          whereArgs: [effectiveBranch],
        );
        await db.rawUpdate('UPDATE alerts SET isRead = 1 WHERE branch = ?', [
          effectiveBranch,
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
                operation: 'UPDATE',
                payload: {'id': alertId, 'isRead': 1},
                branch: effectiveBranch,
              );
            } catch (_) {}
          }
        }
      }
    }
  }

  Future<void> deleteAlert(
    String id, {
    bool enqueueSync = true,
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
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
          branch: effectiveBranch,
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

  Future<List<RestockRecordModel>> getRestockRecords([String? branch]) async {
    final db = await database;
    List<Map<String, dynamic>> maps;
    if (branch != 'All Branches') {
      final effectiveBranch = branch ?? await getBranchName();
      maps = await db.query(
        'restock_records',
        where: 'toBranch = ? OR fromBranch = ?',
        whereArgs: [effectiveBranch, effectiveBranch],
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
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    await db.update(
      'restock_records',
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );

    if (enqueueSync) {
      try {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final payload = <String, dynamic>{
          'id': id,
          'status': status,
          if (status == 'verified') 'verifiedAt': nowMs,
        };
        await enqueueSyncItem(
          id: 'sync_status_restock_${id}_$nowMs',
          pendingEventId: id,
          targetCollection: 'restock_records',
          operation: 'UPDATE',
          payload: payload,
          branch: effectiveBranch,
        );
      } catch (_) {}
    }

    if (enqueueSync) {
      await logActivity(
        type: 'RESTOCK_STATUS',
        description: 'Restock order #$id status changed to $status.',
        branch: effectiveBranch,
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<int> getDetectedCountForSlot(
    String perfumeCode, {
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final rows = await db.query(
      'inventory_records',
      columns: ['detected'],
      where: 'perfumeCode = ? AND branch = ?',
      whereArgs: [perfumeCode, effectiveBranch],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return (rows.first['detected'] as num?)?.toInt() ?? 0;
    }
    return 0;
  }

  Future<void> markStockAlertsReadForPerfume(
    String perfumeCode, {
    String? branch,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    await db.update(
      'alerts',
      {'isRead': 1},
      where:
          '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ? AND isRead = 0',
      whereArgs: [
        'low_stock',
        'lowStock',
        'out_of_stock',
        'discrepancy',
        perfumeCode,
        effectiveBranch,
      ],
    );
  }

  Future<void> resolveRestockDelivery({
    required String restockId,
    required String perfumeCode,
    required int verifiedQuantity,
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final now = DateTime.now();

    // 1. Update restock status to 'verified'
    await updateRestockStatus(
      restockId,
      'verified',
      branch: effectiveBranch,
      enqueueSync: enqueueSync,
    );

    // 2. Clear any active alerts for this fragrance (mark isRead = 1 for history auditing)
    await db.update(
      'alerts',
      {'isRead': 1},
      where:
          '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ? AND isRead = 0',
      whereArgs: ['low_stock', 'lowStock', 'out_of_stock', 'discrepancy', perfumeCode, effectiveBranch],
    );

    // 2b. Synchronize ledger recorded count to verified restock quantity
    final invRows = await db.query(
      'inventory_records',
      where: 'perfumeCode = ? AND branch = ?',
      whereArgs: [perfumeCode, effectiveBranch],
      limit: 1,
    );
    if (invRows.isNotEmpty) {
      final curDet = (invRows.first['detected'] as num?)?.toInt() ?? verifiedQuantity;
      final newRec = verifiedQuantity.clamp(0, 5);
      await db.update(
        'inventory_records',
        {
          'recorded': newRec,
          'detected': curDet,
          'status': newRec == curDet ? 'normal' : 'needs_review',
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
      );
    }

    // 3. Log RESTOCKED event in inventory_events
    final pName = getPerfumeFullName(perfumeCode);
    final tray = perfumeCode.length >= 2
        ? 'Tray ${perfumeCode.substring(0, 2).toUpperCase()}'
        : 'Shelf';
    final event = InventoryEventModel(
      id: 'event_restock_${restockId}_${now.millisecondsSinceEpoch}',
      eventType: 'RESTOCKED',
      productName: pName,
      perfumeCode: perfumeCode,
      shelfArea: tray,
      branch: effectiveBranch,
      quantity: verifiedQuantity,
      timestamp: now,
      syncStatus: 'synced',
    );
    await logInventoryEvent(event, enqueueSync: enqueueSync);

    await logActivity(
      type: 'RESTOCK_VERIFIED',
      description:
          'Restock verified for $perfumeCode ($pName): +$verifiedQuantity bottles verified onto $tray.',
      branch: effectiveBranch,
      enqueueSync: enqueueSync,
    );
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

  /// Safely deletes historical movement events from inventory_events and restock_records
  /// while strictly safeguarding products, sales_records, and active inventory in inventory_records.
  Future<void> clearMovementAndRestockLogs(
    String branch, {
    bool purgeSystemInventoryLogs = true,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      // 1. Safely delete historical movement events from inventory_events
      await txn.delete(
        'inventory_events',
        where: 'branch = ?',
        whereArgs: [branch],
      );

      // 2. Delete restock records for this branch
      await txn.delete(
        'restock_records',
        where: 'toBranch = ? OR fromBranch = ?',
        whereArgs: [branch, branch],
      );

      // 3. Purge inventory-related system logs if requested
      if (purgeSystemInventoryLogs) {
        await txn.delete(
          'system_logs',
          where:
              "branch = ? AND (type LIKE '%RESTOCK%' OR type LIKE '%INVENTORY%' OR type LIKE '%WRITEOFF%')",
          whereArgs: [branch],
        );
      }

      // 4. Record audit ledger entry
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.insert(
        'system_logs',
        {
          'id': 'log_cleanslate_$now',
          'type': 'AUDIT_CLEAN_SLATE',
          'description':
              'Store Manager executed clean slate on historical restock & movement logs.',
          'user': 'Manager',
          'branch': branch,
          'timestamp': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _activityLogUpdateController.add(null);
  }

  Future<void> clearHistoricalMovementAndRestockLogs(
    String branch, {
    bool purgeSystemInventoryLogs = true,
  }) =>
      clearMovementAndRestockLogs(
        branch,
        purgeSystemInventoryLogs: purgeSystemInventoryLogs,
      );

  /// Synchronizes ledger (recorded = detected), logs RESTOCKED event with surplus delta,
  /// and automatically dismisses associated discrepancy, low_stock, and out_of_stock alerts.
  Future<void> confirmSurplusRestock({
    required String perfumeCode,
    String? branch,
    int? detectedCount,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final db = await database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. Fetch current inventory record
      final records = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
        limit: 1,
      );
      if (records.isEmpty) return;

      final rec = records.first;
      final int detected =
          detectedCount ?? (rec['detected'] as num?)?.toInt() ?? 0;
      final int recorded = (rec['recorded'] as num?)?.toInt() ?? 0;
      final String name =
          (rec['name'] as String?) ?? getPerfumeFullName(perfumeCode);
      final String shelf = (rec['shelf'] as String?) ?? 'Shelf';

      // 2. Align recorded ledger to detected physical count
      await txn.update(
        'inventory_records',
        {
          'recorded': detected,
          'status': 'normal',
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
      );

      // 3. Log RESTOCKED event with surplus delta (min 1)
      final surplusQty = (detected - recorded) > 0 ? (detected - recorded) : 1;
      await txn.insert(
        'inventory_events',
        {
          'id':
              'evt_manual_restock_${perfumeCode}_${now.millisecondsSinceEpoch}',
          'eventType': 'RESTOCKED',
          'productName': name,
          'perfumeCode': perfumeCode,
          'shelfArea': shelf,
          'branch': effectiveBranch,
          'quantity': surplusQty,
          'timestamp': now.millisecondsSinceEpoch,
          'syncStatus': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 4. Clear/dismiss both discrepancy and low/out-of-stock alerts for this SKU
      await txn.update(
        'alerts',
        {'isRead': 1},
        where:
            '(type = ? OR type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ? AND isRead = 0',
        whereArgs: [
          'discrepancy',
          'low_stock',
          'lowStock',
          'out_of_stock',
          'outOfStock',
          perfumeCode,
          effectiveBranch,
        ],
      );

      // 5. System activity log
      await txn.insert(
        'system_logs',
        {
          'id':
              'log_manual_restock_${perfumeCode}_${now.millisecondsSinceEpoch}',
          'type': 'RESTOCK_MANUAL_CHECK',
          'description':
              'Manually verified restock for $perfumeCode ($name): synchronized recorded ledger to $detected bottles.',
          'user': 'Staff',
          'branch': effectiveBranch,
          'timestamp': now.millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _activityLogUpdateController.add(null);
  }

  Future<void> manuallyCheckRestock({
    required String perfumeCode,
    String? branch,
    int? detectedCount,
  }) =>
      confirmSurplusRestock(
        perfumeCode: perfumeCode,
        branch: branch,
        detectedCount: detectedCount,
      );

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
    final branch = await getBranchName();
    if (enqueueSync) {
      try {
        await enqueueSyncItem(
          id: 'sync_setting_${key}_${DateTime.now().millisecondsSinceEpoch}',
          pendingEventId: key,
          targetCollection: 'system_settings',
          operation: 'UPSERT',
          payload: {'key': key, 'value': strVal},
          branch: branch,
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
        branch: branch,
        enqueueSync: enqueueSync,
      );
    }
  }

  Future<int> getLowStockThreshold() async {
    final val = await getSetting('lowStockThreshold');
    if (val != null) {
      final parsed = int.tryParse(val);
      if (parsed != null && parsed > 0) return parsed;
    }
    return 2;
  }

  Future<void> setLowStockThreshold(int threshold) async {
    await setSystemSetting('lowStockThreshold', threshold.toString());
    final branch = await getBranchName();
    final allInv = await getInventoryRecords(branch);
    final db = await database;
    final batch = db.batch();
    for (final inv in allInv) {
      if (inv.status != 'misplaced') {
        final newStatus = inv.detected == 0
            ? 'out_of_stock'
            : (inv.detected <= threshold ? 'low' : 'normal');
        if (newStatus != inv.status) {
          batch.update(
            'inventory_records',
            {'status': newStatus},
            where: 'id = ?',
            whereArgs: [inv.id],
          );
        }
      }
    }
    await batch.commit(noResult: true);
  }

  Future<void> verifyAndClearMisplacement({
    required String perfumeCode,
    String branch = 'San Pablo',
  }) async {
    final db = await database;
    final lowThreshold = await getLowStockThreshold();
    final invRows = await db.query(
      'inventory_records',
      where: 'perfumeCode = ? AND branch = ?',
      whereArgs: [perfumeCode, branch],
    );
    if (invRows.isNotEmpty) {
      final detected = (invRows.first['detected'] as num?)?.toInt() ?? 0;
      final newStatus = detected == 0
          ? 'out_of_stock'
          : (detected <= lowThreshold ? 'low' : 'normal');
      await db.update(
        'inventory_records',
        {
          'status': newStatus,
          'misplacementDetails': '',
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );
    }
    await db.delete(
      'alerts',
      where: 'type = ? AND perfumeCode = ? AND branch = ?',
      whereArgs: ['misplaced', perfumeCode, branch],
    );
  }

  // ---------------------------------------------------------------------------
  // USERS CRUD (Cached local logins with hashed credentials)
  // ---------------------------------------------------------------------------
  Future<void> saveUser(UserModel user, {String? password}) async {
    try {
      final db = await database;
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

      final match3 = (a3 == expected3) ||
          (a3.replaceAll(' ', '') == expected3.replaceAll(' ', '')) ||
          (expected3 == 'ottoscents' && a3 == 'otto scents');

      return a1 == expected1 && a2 == expected2 && match3;
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

      final cleanNewPin = newPin.trim();
      if (cleanNewPin.length != AppConstants.pinLength || int.tryParse(cleanNewPin) == null) {
        return false;
      }

      final db = await database;
      final saltBytes = await getKioskSaltBytes();
      final newHash = Pbkdf2Auth.hashPin(cleanNewPin, saltBytes);

      // Save new PIN hash
      await setSystemSetting('owner_pin_hash', newHash);

      // Update admin user credentials
      await db.update(
        'users',
        {
          'passwordHash': newHash,
          'lastLogin': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      await resetLockout();

      await logActivity(
        type: 'PIN_RECOVERED',
        description: 'Store Owner PIN successfully reset via security recovery questions.',
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Retrieves persistent brute-force lockout status from SQLite
  Future<LockoutStatus> getLockoutStatus() async {
    try {
      final lockedUntilStr = await getSetting('locked_until_epoch');
      final failedAttemptsStr = await getSetting('failed_pin_attempts');
      final lockedUntil = int.tryParse(lockedUntilStr ?? '') ?? 0;
      final failedAttempts = int.tryParse(failedAttemptsStr ?? '') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lockedUntil > now) {
        final remaining = ((lockedUntil - now) / 1000).ceil();
        return LockoutStatus(
          isLockedOut: true,
          remainingSeconds: remaining > 0 ? remaining : 1,
          failedAttempts: failedAttempts,
        );
      }

      // If lockout expired, reset attempts and lockout epoch
      if (lockedUntil > 0 && lockedUntil <= now) {
        await resetLockout();
        return const LockoutStatus(
          isLockedOut: false,
          remainingSeconds: 0,
          failedAttempts: 0,
        );
      }

      return LockoutStatus(
        isLockedOut: false,
        remainingSeconds: 0,
        failedAttempts: failedAttempts,
      );
    } catch (_) {
      return const LockoutStatus(
        isLockedOut: false,
        remainingSeconds: 0,
        failedAttempts: 0,
      );
    }
  }

  /// Resets failed PIN attempts and clears persistent lockout in SQLite
  Future<void> resetLockout() async {
    try {
      await setSystemSetting('failed_pin_attempts', '0', enqueueSync: false);
      await setSystemSetting('locked_until_epoch', '0', enqueueSync: false);
    } catch (_) {}
  }

  /// Checks whether an owner PIN has been established on this kiosk
  Future<bool> isOwnerPinSet() async {
    try {
      final db = await database;
      final maps = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['owner_pin_hash'],
      );
      if (maps.isNotEmpty) {
        final stored = (maps.first['value'] as String? ?? '').trim();
        if (stored.isNotEmpty) return true;
      }
      final adminCreds = await getUserWithCredentials('admin@ottoscents.com');
      if (adminCreds != null) {
        final hash = (adminCreds['passwordHash'] as String? ?? '').trim();
        if (hash.isNotEmpty) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Establishes the initial owner PIN during first-time terminal setup
  Future<bool> setInitialOwnerPin(String pin) async {
    try {
      final cleanPin = pin.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(cleanPin)) {
        return false;
      }

      final db = await database;
      final saltBytes = await getKioskSaltBytes();
      final newHash = Pbkdf2Auth.hashPin(cleanPin, saltBytes);

      // 1. Save in system_settings
      await setSystemSetting('owner_pin_hash', newHash);

      // 2. Update admin user credentials in local SQLite and queue for Supabase
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
            'updated_at': DateTime.now().toIso8601String(),
          },
          branch: 'San Pablo',
        );
      } catch (_) {}

      await logActivity(
        type: 'INITIAL_PIN_SETUP',
        description:
            'First-time owner security PIN configured successfully with PBKDF2 salt derivation.',
      );

      await resetLockout();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Emergency manager override backed by PBKDF2-hashed master recovery key
  Future<bool> verifyEmergencyManagerOverride(String masterKey) async {
    try {
      final cleanKey = masterKey.trim();
      if (cleanKey.isEmpty) return false;

      final saltBytes = await getKioskSaltBytes();
      final computedHash = Pbkdf2Auth.hashPin(cleanKey, saltBytes);
      final storedMasterHash = await getSetting('master_recovery_key_hash') ?? '';

      String expectedHash = storedMasterHash.trim();
      if (expectedHash.isEmpty) {
        expectedHash = Pbkdf2Auth.hashPin(defaultMasterRecoveryKey, saltBytes);
        await setSystemSetting('master_recovery_key_hash', expectedHash, enqueueSync: false);
      }

      if (Pbkdf2Auth.constantTimeEquals(computedHash, expectedHash)) {
        await resetLockout();
        await logActivity(
          type: 'SECURITY_OVERRIDE',
          description:
              'Emergency manager override key utilized to bypass terminal security lockout and reset attempts.',
          user: 'Store Manager',
        );
        try {
          unawaited(SyncService.instance.syncPendingQueue());
        } catch (_) {}
        return true;
      }

      await logActivity(
        type: 'OVERRIDE_FAILURE',
        description: 'Invalid emergency manager override key attempt recorded.',
        user: 'Store Manager',
      );
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Verifies the 6-digit owner PIN with PBKDF2 and enforces persistent lockout
  Future<bool> verifyOwnerPin(String pin) async {
    try {
      // 1. Enforce persistent lockout check
      final lockout = await getLockoutStatus();
      if (lockout.isLockedOut) {
        return false;
      }

      // 2. Enforce strict 6-digit format validation
      final cleanPin = pin.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(cleanPin)) {
        return false;
      }

      final db = await database;
      final maps = await db.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['owner_pin_hash'],
      );

      String storedHash = '';
      if (maps.isNotEmpty) {
        storedHash = (maps.first['value'] as String? ?? '').trim();
      }

      if (storedHash.isEmpty) {
        final adminCreds = await getUserWithCredentials('admin@ottoscents.com');
        if (adminCreds != null) {
          storedHash = (adminCreds['passwordHash'] as String? ?? '').trim();
        }
      }

      // If no PIN has been configured, reject (eliminate hardcoded fallback)
      if (storedHash.isEmpty) {
        return false;
      }

      final saltBytes = await getKioskSaltBytes();
      final computedHash = Pbkdf2Auth.hashPin(cleanPin, saltBytes);

      bool isMatch = Pbkdf2Auth.constantTimeEquals(storedHash, computedHash);

      // Legacy SHA-256 migration path: if stored hash was legacy sha256 (not default 123456)
      if (!isMatch &&
          cleanPin != '123456' &&
          Pbkdf2Auth.constantTimeEquals(
            storedHash,
            sha256.convert(utf8.encode(cleanPin)).toString(),
          )) {
        isMatch = true;
        // Auto-upgrade stored hash to PBKDF2
        await setSystemSetting('owner_pin_hash', computedHash);
        await db.update(
          'users',
          {'passwordHash': computedHash},
          where: 'role = ?',
          whereArgs: ['admin'],
        );
      }

      if (isMatch) {
        await resetLockout();
        await logActivity(
          type: 'USER_LOGIN',
          description: 'Store Owner authenticated successfully via PIN at kiosk terminal.',
        );
        return true;
      }

      // Handle failed attempt: atomically re-read fresh failed attempts inside SQLite transaction
      int recordedAttempts = 1;
      bool triggeredLockout = false;
      await db.transaction((txn) async {
        final freshRows = await txn.query(
          'system_settings',
          where: "key IN ('failed_pin_attempts', 'locked_until_epoch')",
        );
        String? failedStr;
        String? lockedUntilStr;
        for (final row in freshRows) {
          if (row['key'] == 'failed_pin_attempts') failedStr = row['value'] as String?;
          if (row['key'] == 'locked_until_epoch') lockedUntilStr = row['value'] as String?;
        }
        final lockedUntil = int.tryParse(lockedUntilStr ?? '') ?? 0;
        final failedAttempts = int.tryParse(failedStr ?? '') ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;

        if (lockedUntil > now) {
          triggeredLockout = true;
          recordedAttempts = failedAttempts;
          return;
        }

        final nextAttempts = failedAttempts + 1;
        recordedAttempts = nextAttempts;
        if (nextAttempts >= 5) {
          triggeredLockout = true;
          final newLockedUntil = now + (300 * 1000);
          await txn.insert(
            'system_settings',
            {'key': 'failed_pin_attempts', 'value': nextAttempts.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert(
            'system_settings',
            {'key': 'locked_until_epoch', 'value': newLockedUntil.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        } else {
          await txn.insert(
            'system_settings',
            {'key': 'failed_pin_attempts', 'value': nextAttempts.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      if (triggeredLockout) {
        await logActivity(
          type: 'SECURITY_LOCKOUT',
          description: 'Security lockout initiated for 300s after 5 repeated invalid PIN attempts.',
        );
      } else {
        await logActivity(
          type: 'AUTH_FAILURE',
          description: 'Failed PIN authentication attempt ($recordedAttempts of 5).',
        );
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateOwnerPin({
    required String oldPin,
    required String newPin,
  }) async {
    try {
      final cleanNewPin = newPin.trim();
      if (!RegExp(r'^\d{6}$').hasMatch(cleanNewPin)) {
        return false;
      }

      final isValidOld = await verifyOwnerPin(oldPin);
      if (!isValidOld) return false;

      final db = await database;
      final saltBytes = await getKioskSaltBytes();
      final newHash = Pbkdf2Auth.hashPin(cleanNewPin, saltBytes);

      // 1. Save in system_settings (auto-enqueues to sync_queue)
      await setSystemSetting('owner_pin_hash', newHash);

      // 2. Update admin user credentials in local SQLite and queue for Supabase
      await db.update(
        'users',
        {
          'passwordHash': newHash,
          'lastLogin': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'role = ?',
        whereArgs: ['admin'],
      );

      final branch = await getBranchName();
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
            'branch': branch,
          },
          branch: branch,
        );
      } catch (_) {}

      // 3. Insert system audit log (auto-enqueues to sync_queue)
      final logId = 'log_${DateTime.now().millisecondsSinceEpoch}_pin';
      await logSystemActivity(
        SystemLogModel(
          id: logId,
          user: 'Store Owner',
          type: 'SECURITY_UPDATE',
          description: 'Store owner 6-digit PIN successfully changed with PBKDF2 salt derivation.',
          timestamp: DateTime.now(),
          branch: branch,
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
    bool isDeficitResolution = false,
    bool enqueueSync = true,
  }) async {
    final lowThreshold = await getLowStockThreshold();
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
        final int newDetected;
        final int newRecorded;
        if (isDeficitResolution) {
          // Deficit discrepancy resolution: reconcile recorded ledger with detected physical count,
          // leaving detected untouched so on-shelf stock remains at the true physical bottle count.
          newRecorded = current.detected.clamp(0, 5);
          newDetected = current.detected.clamp(0, 5);
        } else {
          newDetected =
              (current.detected - saleRecord.quantitySold).clamp(0, 100);
          newRecorded =
              (current.recorded - saleRecord.quantitySold).clamp(0, 100);
        }

        final updatedInv = current.copyWith(
          detected: newDetected,
          recorded: newRecorded,
          lastUpdated: DateTime.now(),
          status: newDetected == 0
              ? 'out_of_stock'
              : (newDetected <= lowThreshold ? 'low' : 'normal'),
        );
        await txn.insert(
          'inventory_records',
          updatedInv.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (isDeficitResolution) {
          // Auto-dismiss any active discrepancy alert for that slot
          await txn.update(
            'alerts',
            {'isRead': 1},
            where: 'type = ? AND perfumeCode = ? AND branch = ?',
            whereArgs: ['discrepancy', saleRecord.perfumeCode, branch],
          );
        }

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

  /// Records a customer return & refund transaction.
  /// When [isResellable] is true: increments recorded and detected counts (clamped to 5) and logs RETURN_RESTOCKED.
  /// When [isResellable] is false: writes off bottle with no shelf restock and logs refund/damage event.
  /// Always inserts a negative sale transaction to offset gross revenue.
  Future<void> recordCustomerReturnRefund({
    required String perfumeCode,
    required String productName,
    required String bottleSize,
    required int quantity,
    required double unitPrice,
    required bool isResellable,
    required String authorizedBy,
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final lowThreshold = await getLowStockThreshold();
    final db = await database;
    final now = DateTime.now();
    final refundAmount = -(unitPrice * quantity);

    await db.transaction((txn) async {
      // 1. Insert negative sale record for refund financial accounting
      final saleId = 'refund_${now.millisecondsSinceEpoch}';
      final refundSale = SaleRecordModel(
        id: saleId,
        perfumeCode: perfumeCode,
        productName: productName,
        bottleSize: bottleSize,
        quantitySold: quantity,
        unitPrice: unitPrice,
        totalAmount: refundAmount,
        branch: effectiveBranch,
        soldBy: authorizedBy,
        soldAt: now,
        syncStatus: 'synced',
      );
      await txn.insert(
        'sales_records',
        refundSale.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Insert inventory event
      final eventId = 'evt_return_${now.millisecondsSinceEpoch}';
      final eventType = isResellable ? 'RETURN_RESTOCKED' : 'DAMAGE_WRITEOFF';
      final reason = isResellable
          ? 'Customer Return Resellable'
          : 'Customer Return Damaged';
      final invEvent = InventoryEventModel(
        id: eventId,
        eventType: eventType,
        productName: productName,
        perfumeCode: perfumeCode,
        shelfArea: 'Layer ${perfumeCode.isNotEmpty ? perfumeCode[0] : 'A'}',
        branch: effectiveBranch,
        quantity: quantity,
        reason: reason,
        timestamp: now,
        syncStatus: 'synced',
      );
      await txn.insert(
        'inventory_events',
        invEvent.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 3. Update inventory record if resellable
      final invRows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
      );
      if (invRows.isNotEmpty) {
        final current = InventoryRecordModel.fromMap(invRows.first);
        if (isResellable) {
          final newRecorded = (current.recorded + quantity).clamp(0, 5);
          final newDetected = (current.detected + quantity).clamp(0, 5);
          final updated = current.copyWith(
            recorded: newRecorded,
            detected: newDetected,
            status: newDetected == 0
                ? 'out_of_stock'
                : (newDetected <= lowThreshold ? 'low' : 'normal'),
            lastUpdated: now,
          );
          await txn.insert(
            'inventory_records',
            updated.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          if (enqueueSync) {
            await txn.insert('sync_queue', {
              'id': 'sync_inv_${updated.id}',
              'pendingEventId': updated.id,
              'targetCollection': 'inventory_records',
              'operation': 'UPSERT',
              'payload': jsonEncode(updated.toMap()),
              'retryCount': 0,
              'status': 'pending',
              'branch': updated.branch,
              'createdAt': now.millisecondsSinceEpoch,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          }
        }
      }

      if (enqueueSync) {
        await txn.insert('sync_queue', {
          'id': 'sync_sale_$saleId',
          'pendingEventId': saleId,
          'targetCollection': 'sales_records',
          'operation': 'UPSERT',
          'payload': jsonEncode(refundSale.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': effectiveBranch,
          'createdAt': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);

        await txn.insert('sync_queue', {
          'id': 'sync_evt_$eventId',
          'pendingEventId': eventId,
          'targetCollection': 'inventory_events',
          'operation': 'UPSERT',
          'payload': jsonEncode(invEvent.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': effectiveBranch,
          'createdAt': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    if (enqueueSync) {
      await logActivity(
        type: 'CUSTOMER_REFUND',
        description:
            'Customer refund processed: $quantity x $productName ($bottleSize) authorized by $authorizedBy. Condition: ${isResellable ? 'Resellable' : 'Damaged'}. Amount: -₱${(unitPrice * quantity).toStringAsFixed(2)}.',
        user: authorizedBy,
        branch: effectiveBranch,
        enqueueSync: enqueueSync,
      );
    }
  }

  /// Records a damaged fragrance bottle write-off.
  /// Supports strictly 3 cause categories: 'Broken Bottle', 'Leaking / Evaporated', 'Defective Atomizer / Cap'.
  Future<void> recordDamagedWriteOff({
    required String perfumeCode,
    required String productName,
    required String bottleSize,
    required int quantity,
    required String reasonCategory,
    required String authorizedBy,
    bool isDeficitResolution = false,
    String? branch,
    bool enqueueSync = true,
  }) async {
    const validReasons = {
      'Broken Bottle',
      'Leaking / Evaporated',
      'Defective Atomizer / Cap',
    };
    if (!validReasons.contains(reasonCategory)) {
      throw ArgumentError(
        'Invalid damage reason category: "$reasonCategory". Must be one of: ${validReasons.join(', ')}.',
      );
    }

    final effectiveBranch = branch ?? await getBranchName();
    final lowThreshold = await getLowStockThreshold();
    final db = await database;
    final now = DateTime.now();

    await db.transaction((txn) async {
      // 1. Insert inventory event
      final eventId = 'evt_damage_${now.millisecondsSinceEpoch}';
      final invEvent = InventoryEventModel(
        id: eventId,
        eventType: 'DAMAGE_WRITEOFF',
        productName: productName,
        perfumeCode: perfumeCode,
        shelfArea: 'Layer ${perfumeCode.isNotEmpty ? perfumeCode[0] : 'A'}',
        branch: effectiveBranch,
        quantity: quantity,
        reason: reasonCategory,
        timestamp: now,
        syncStatus: 'synced',
      );
      await txn.insert(
        'inventory_events',
        invEvent.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 2. Deduct inventory record
      final invRows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
      );
      if (invRows.isNotEmpty) {
        final current = InventoryRecordModel.fromMap(invRows.first);
        final int newRecorded;
        final int newDetected;
        if (isDeficitResolution) {
          // Reconciling deficit: align recorded to detected without reducing detected again
          newRecorded = current.detected.clamp(0, 5);
          newDetected = current.detected.clamp(0, 5);
        } else {
          newRecorded = (current.recorded - quantity).clamp(0, 5);
          newDetected = (current.detected - quantity).clamp(0, 5);
        }

        final updated = current.copyWith(
          recorded: newRecorded,
          detected: newDetected,
          status: newDetected == 0
              ? 'out_of_stock'
              : (newDetected <= lowThreshold ? 'low' : 'normal'),
          lastUpdated: now,
        );
        await txn.insert(
          'inventory_records',
          updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (isDeficitResolution) {
          // Clear active discrepancy alert
          await txn.update(
            'alerts',
            {'isRead': 1},
            where: 'type = ? AND perfumeCode = ? AND branch = ?',
            whereArgs: ['discrepancy', perfumeCode, effectiveBranch],
          );
        }

        if (enqueueSync) {
          await txn.insert('sync_queue', {
            'id': 'sync_inv_${updated.id}',
            'pendingEventId': updated.id,
            'targetCollection': 'inventory_records',
            'operation': 'UPSERT',
            'payload': jsonEncode(updated.toMap()),
            'retryCount': 0,
            'status': 'pending',
            'branch': updated.branch,
            'createdAt': now.millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      if (enqueueSync) {
        await txn.insert('sync_queue', {
          'id': 'sync_evt_$eventId',
          'pendingEventId': eventId,
          'targetCollection': 'inventory_events',
          'operation': 'UPSERT',
          'payload': jsonEncode(invEvent.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': effectiveBranch,
          'createdAt': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    if (enqueueSync) {
      await logActivity(
        type: 'DAMAGE_WRITEOFF',
        description:
            'Damaged fragrance write-off: $quantity x $productName ($bottleSize) authorized by $authorizedBy. Reason: $reasonCategory.',
        user: authorizedBy,
        branch: effectiveBranch,
        enqueueSync: enqueueSync,
      );
    }
  }

  /// Commits a visual count audit directly to SQLite, aligning detected = count and recorded = count.
  /// Automatically updates slot status to 'normal' (or low/oos) and clears active discrepancy alerts.
  Future<void> recordVisualCountAudit({
    required String perfumeCode,
    required int countedBottles,
    required String shelfArea,
    required String auditor,
    String? branch,
    bool enqueueSync = true,
  }) async {
    final effectiveBranch = branch ?? await getBranchName();
    final lowThreshold = await getLowStockThreshold();
    final count = countedBottles.clamp(0, 5);
    final db = await database;
    final now = DateTime.now();
    String resolvedProductName = getPerfumeFullName(perfumeCode);

    await db.transaction((txn) async {
      // 1. Update inventory record: set both detected = count and recorded = count
      final invRows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, effectiveBranch],
      );
      if (invRows.isNotEmpty) {
        final current = InventoryRecordModel.fromMap(invRows.first);
        resolvedProductName = current.name;
        final updated = current.copyWith(
          recorded: count,
          detected: count,
          status: count == 0
              ? 'out_of_stock'
              : (count <= lowThreshold ? 'low' : 'normal'),
          lastUpdated: now,
        );
        await txn.insert(
          'inventory_records',
          updated.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        if (enqueueSync) {
          await txn.insert('sync_queue', {
            'id': 'sync_inv_${updated.id}',
            'pendingEventId': updated.id,
            'targetCollection': 'inventory_records',
            'operation': 'UPSERT',
            'payload': jsonEncode(updated.toMap()),
            'retryCount': 0,
            'status': 'pending',
            'branch': updated.branch,
            'createdAt': now.millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      // 2. Clear active discrepancy alerts
      await txn.update(
        'alerts',
        {'isRead': 1},
        where: 'type = ? AND perfumeCode = ? AND branch = ?',
        whereArgs: ['discrepancy', perfumeCode, effectiveBranch],
      );

      // If count > lowThreshold, also clear low_stock and out_of_stock alerts
      if (count > lowThreshold) {
        await txn.update(
          'alerts',
          {'isRead': 1},
          where:
              '(type = ? OR type = ? OR type = ? OR type = ?) AND perfumeCode = ? AND branch = ?',
          whereArgs: [
            'low_stock',
            'lowStock',
            'out_of_stock',
            'outOfStock',
            perfumeCode,
            effectiveBranch,
          ],
        );
      }

      // 3. Insert inventory event
      final eventId = 'evt_audit_${now.millisecondsSinceEpoch}';
      final invEvent = InventoryEventModel(
        id: eventId,
        eventType: 'AUDIT_VISUAL_COUNT',
        productName: resolvedProductName,
        perfumeCode: perfumeCode,
        shelfArea: shelfArea,
        branch: effectiveBranch,
        quantity: count,
        reason: 'Visual Count Audit by $auditor',
        timestamp: now,
        syncStatus: 'synced',
      );
      await txn.insert(
        'inventory_events',
        invEvent.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      if (enqueueSync) {
        await txn.insert('sync_queue', {
          'id': 'sync_evt_$eventId',
          'pendingEventId': eventId,
          'targetCollection': 'inventory_events',
          'operation': 'UPSERT',
          'payload': jsonEncode(invEvent.toMap()),
          'retryCount': 0,
          'status': 'pending',
          'branch': effectiveBranch,
          'createdAt': now.millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });

    if (enqueueSync) {
      await logActivity(
        type: 'AUDIT_VISUAL_COUNT',
        description:
            'Visual shelf count audit for $perfumeCode ($resolvedProductName): count committed to $count bottles by $auditor. Discrepancy alerts resolved.',
        user: auditor,
        branch: effectiveBranch,
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
    String targetBranch = await getBranchName();
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
