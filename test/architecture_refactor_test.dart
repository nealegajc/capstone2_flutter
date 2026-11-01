import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Otto Scents Architecture Refactor Tests (R3, R4, Gate 2)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('R4: Centerline Partitioning (< trayMidX -> 100ML, >= trayMidX -> 50ML, max 5)', () async {
      // Configure ROIs for Camera 1: Tray AA [left: 0.0, right: 0.20, mid: 0.10]
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // 4 bottles in Left half (centerX = 0.05 < 0.10) -> AA1 (100ML)
      // 3 bottles in Right half (centerX = 0.15 >= 0.10) -> AA2 (50ML)
      final detections = [
        {'id': 'det_1', 'centerX': 0.04, 'centerY': 0.3},
        {'id': 'det_2', 'centerX': 0.05, 'centerY': 0.5},
        {'id': 'det_3', 'centerX': 0.06, 'centerY': 0.7},
        {'id': 'det_4', 'centerX': 0.07, 'centerY': 0.8},
        {'id': 'det_5', 'centerX': 0.12, 'centerY': 0.3},
        {'id': 'det_6', 'centerX': 0.14, 'centerY': 0.5},
        {'id': 'det_7', 'centerX': 0.16, 'centerY': 0.7},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      expect(counts['AA1'], equals(4)); // 4 bottles in 100ML slot
      expect(counts['AA2'], equals(3)); // 3 bottles in 50ML slot

      final inv = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = inv.firstWhere((i) => i.perfumeCode == 'AA1');
      final aa2 = inv.firstWhere((i) => i.perfumeCode == 'AA2');

      expect(aa1.detected, equals(4));
      expect(aa2.detected, equals(3));
    });

    test('R4: Centerline Partitioning caps detections strictly at 5 bottles per slot', () async {
      // Configure ROIs for Camera 1: Tray AA [left: 0.0, right: 0.20, mid: 0.10]
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // 7 bottles in Left half -> should clamp to 5 max
      final detections = List.generate(
        7,
        (i) => {'id': 'det_$i', 'centerX': 0.02 + (i * 0.01), 'centerY': 0.4},
      );

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      expect(counts['AA1'], equals(5)); // Capped at 5
    });

    test('R4: Low Stock Alert Lifecycle (<= 2 triggers alert, >= 3 auto-resolves)', () async {
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // Step 1: Scan detects 2 bottles in AA1 (Low Stock <= 2) and 0 in AA2 (Out of stock)
      final scan1 = [
        {'id': 'd1', 'centerX': 0.04, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.06, 'centerY': 0.5},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scan1,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      var alerts = await sqliteService.getAlerts('San Pablo');
      var lowAlerts = alerts.where((a) => a.type == 'low_stock').toList();

      expect(lowAlerts.any((a) => a.perfumeCode == 'AA1'), isTrue);
      expect(lowAlerts.any((a) => a.perfumeCode == 'AA2'), isTrue);

      // Step 2: Subsequent scan detects 4 bottles in AA1 and 3 bottles in AA2 (Restocked >= 3)
      final scan2 = [
        {'id': 'd1', 'centerX': 0.03, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.05, 'centerY': 0.4},
        {'id': 'd3', 'centerX': 0.06, 'centerY': 0.5},
        {'id': 'd4', 'centerX': 0.07, 'centerY': 0.6},
        {'id': 'd5', 'centerX': 0.12, 'centerY': 0.3},
        {'id': 'd6', 'centerX': 0.14, 'centerY': 0.4},
        {'id': 'd7', 'centerX': 0.16, 'centerY': 0.5},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scan2,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      alerts = await sqliteService.getAlerts('San Pablo');
      lowAlerts = alerts.where((a) => a.type == 'low_stock').toList();

      // Alerts for AA1 and AA2 should be auto-cleared!
      expect(lowAlerts.any((a) => a.perfumeCode == 'AA1'), isFalse);
      expect(lowAlerts.any((a) => a.perfumeCode == 'AA2'), isFalse);
    });

    test('R4: One-Click createAutoRestockOrder refills items to 5 and logs records', () async {
      // Set BA1 to 1 bottle, BA2 to 0 bottles
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_BA1',
        perfumeCode: 'BA1',
        name: 'Dior Fahrenheit',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer B - Slot 1',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_BA2',
        perfumeCode: 'BA2',
        name: 'Dior Fahrenheit 50ml',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer B - Slot 2',
        recorded: 5,
        detected: 0,
        status: 'out_of_stock',
      ));

      // Execute auto-restock order
      final restockedCount = await sqliteService.createAutoRestockOrder(branch: 'San Pablo');
      expect(restockedCount, greaterThanOrEqualTo(2));

      // Verify inventory records refilled to 5 bottles
      final inv = await sqliteService.getInventoryRecords('San Pablo');
      final ba1 = inv.firstWhere((i) => i.perfumeCode == 'BA1');
      final ba2 = inv.firstWhere((i) => i.perfumeCode == 'BA2');
      expect(ba1.detected, equals(5));
      expect(ba1.status, equals('normal'));
      expect(ba2.detected, equals(5));
      expect(ba2.status, equals('normal'));

      // Verify restock_records inserted
      final restockRecords = await sqliteService.getRestockRecords('San Pablo');
      expect(restockRecords.any((r) => r.perfumeCode == 'BA1' && r.quantity == 4), isTrue);
      expect(restockRecords.any((r) => r.perfumeCode == 'BA2' && r.quantity == 5), isTrue);

      // Verify inventory_events logged
      final events = await sqliteService.getInventoryEvents('San Pablo');
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'BA1'), isTrue);
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'BA2'), isTrue);
    });

    test('R3 & Gate 2: Selective Tray Scanning preserves unselected trays', () async {
      // Camera 5 covers trays CA, CB, CC, CD, CE
      await sqliteService.setSystemSetting(
        'camera_5_tray_rois',
        '{"CA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90},'
        '"CB":{"left":0.20,"top":0.10,"right":0.40,"bottom":0.90},'
        '"CC":{"left":0.40,"top":0.10,"right":0.60,"bottom":0.90},'
        '"CD":{"left":0.60,"top":0.10,"right":0.80,"bottom":0.90},'
        '"CE":{"left":0.80,"top":0.10,"right":1.00,"bottom":0.90}}',
      );

      // Initial state: Set CA1 to 4 bottles, CB1 to 5 bottles, CD1 to 1 bottle
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CA1',
        perfumeCode: 'CA1',
        name: 'Chanel No 5',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 4,
        status: 'normal',
      ));
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CB1',
        perfumeCode: 'CB1',
        name: 'Coco Mademoiselle',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CD1',
        perfumeCode: 'CD1',
        name: 'Chance Chanel',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      // Selective scan TARGETS ONLY Tray CD:
      // In Tray CD (midpoint is 0.70):
      // 3 bottles on left half (< 0.70) -> CD1
      // 2 bottles on right half (>= 0.70) -> CD2
      final detections = [
        {'id': 'd1', 'centerX': 0.63, 'centerY': 0.4},
        {'id': 'd2', 'centerX': 0.65, 'centerY': 0.5},
        {'id': 'd3', 'centerX': 0.67, 'centerY': 0.6},
        {'id': 'd4', 'centerX': 0.73, 'centerY': 0.4},
        {'id': 'd5', 'centerX': 0.75, 'centerY': 0.5},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 5,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['CD'], // Exclusively target tray CD!
      );

      expect(counts['CD1'], equals(3));
      expect(counts['CD2'], equals(2));

      // Verify SQLite state:
      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final ca1After = invAfter.firstWhere((i) => i.perfumeCode == 'CA1');
      final cb1After = invAfter.firstWhere((i) => i.perfumeCode == 'CB1');
      final cd1After = invAfter.firstWhere((i) => i.perfumeCode == 'CD1');
      final cd2After = invAfter.firstWhere((i) => i.perfumeCode == 'CD2');

      // Targeted tray CD must be updated:
      expect(cd1After.detected, equals(3));
      expect(cd2After.detected, equals(2));

      // UNSELECTED trays CA and CB must remain COMPLETELY UNCHANGED:
      expect(ca1After.detected, equals(4));
      expect(ca1After.status, equals('normal'));
      expect(cb1After.detected, equals(5));
      expect(cb1After.status, equals('normal'));
    });

    test('R3: Camera Subset Derivation from Selected Perfume Codes', () {
      List<int> deriveCameras(List<String> codes) {
        return codes
            .map((c) => c.length >= 2 ? c.substring(0, 2).toUpperCase() : c.toUpperCase())
            .toSet()
            .map((tray) => SqliteService.getCameraIdForTray(tray))
            .toSet()
            .toList()
          ..sort();
      }

      // Trays AA-AE -> Cam 1
      expect(deriveCameras(['AA1', 'AA2', 'AC1']), equals([1]));

      // Trays AF-AK -> Cam 2
      expect(deriveCameras(['AF1', 'AK2']), equals([2]));

      // Trays BA-BE -> Cam 3
      expect(deriveCameras(['BA1', 'BE2']), equals([3]));

      // Mixed across layers: AA (Cam 1), BA (Cam 3), CD (Cam 5)
      expect(deriveCameras(['AA1', 'BA1', 'CD2']), equals([1, 3, 5]));

      // All 6 cameras when picking perfumes across all camera zones
      expect(
        deriveCameras(['AA1', 'AF1', 'BA1', 'BF1', 'CA1', 'CF1']),
        equals([1, 2, 3, 4, 5, 6]),
      );

      // Empty selection derives empty camera list
      expect(deriveCameras([]), isEmpty);
    });

    test('Adversarial: Repeated low stock scans do NOT produce duplicate alert rows', () async {
      final scan = [
        {'id': 'd1', 'centerX': 0.04, 'centerY': 0.3}, // AA1 = 1 bottle (<= 2)
      ];

      // Scan 1
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scan,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      var alerts = await sqliteService.getAlerts('San Pablo');
      var aa1Alerts = alerts.where((a) => a.type == 'low_stock' && a.perfumeCode == 'AA1').toList();
      expect(aa1Alerts.length, equals(1));

      // Scan 2 (repeated scan under same conditions)
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scan,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      alerts = await sqliteService.getAlerts('San Pablo');
      aa1Alerts = alerts.where((a) => a.type == 'low_stock' && a.perfumeCode == 'AA1').toList();
      expect(aa1Alerts.length, equals(1), reason: 'Alerts must be deduplicated across consecutive scans');

      // Scan 3
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scan,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      alerts = await sqliteService.getAlerts('San Pablo');
      aa1Alerts = alerts.where((a) => a.type == 'low_stock' && a.perfumeCode == 'AA1').toList();
      expect(aa1Alerts.length, equals(1));
    });

    test('Adversarial: Uncalibrated default geometry seamlessly partitions trays and midpoints', () async {
      // Ensure NO calibrated ROIs in database
      await sqliteService.setSystemSetting('camera_1_tray_rois', '');

      // In Tray AA (default [0.0, 0.20], mid = 0.10):
      // 3 bottles on left (< 0.10) -> AA1
      // 2 bottles on right (>= 0.10) -> AA2
      // In Tray AB (default [0.20, 0.40], mid = 0.30):
      // 2 bottles on left (< 0.30) -> AB1
      // 4 bottles on right (>= 0.30) -> AB2
      final detections = [
        {'id': 'd1', 'centerX': 0.03, 'centerY': 0.4},
        {'id': 'd2', 'centerX': 0.05, 'centerY': 0.5},
        {'id': 'd3', 'centerX': 0.07, 'centerY': 0.6},
        {'id': 'd4', 'centerX': 0.12, 'centerY': 0.4},
        {'id': 'd5', 'centerX': 0.15, 'centerY': 0.5},
        {'id': 'd6', 'centerX': 0.23, 'centerY': 0.4},
        {'id': 'd7', 'centerX': 0.26, 'centerY': 0.5},
        {'id': 'd8', 'centerX': 0.32, 'centerY': 0.4},
        {'id': 'd9', 'centerX': 0.34, 'centerY': 0.5},
        {'id': 'd10', 'centerX': 0.36, 'centerY': 0.6},
        {'id': 'd11', 'centerX': 0.38, 'centerY': 0.7},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['AA', 'AB'],
      );

      expect(counts['AA1'], equals(3));
      expect(counts['AA2'], equals(2));
      expect(counts['AB1'], equals(2));
      expect(counts['AB2'], equals(4));
    });

    test('Adversarial: createAutoRestockOrder respects capacity limit, seasonal off, and integer createdAt', () async {
      // 1. Seasonal off item with 0 stock -> should NOT be restocked
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CA1',
        perfumeCode: 'CA1',
        name: 'Chanel No 5',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 0,
        status: 'seasonal_off',
      ));

      // 2. Fully stocked item with 5 bottles -> should NOT be restocked
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CA2',
        perfumeCode: 'CA2',
        name: 'Chanel No 5 50ml',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // 3. Low stock item with 1 bottle -> should be refilled by 4
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_CB1',
        perfumeCode: 'CB1',
        name: 'Coco Mademoiselle',
        category: 'Women',
        branch: 'San Pablo',
        shelf: 'Layer C',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      final restocked = await sqliteService.createAutoRestockOrder(branch: 'San Pablo');
      expect(restocked, greaterThanOrEqualTo(1));

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final ca1 = invAfter.firstWhere((i) => i.perfumeCode == 'CA1');
      final ca2 = invAfter.firstWhere((i) => i.perfumeCode == 'CA2');
      final cb1 = invAfter.firstWhere((i) => i.perfumeCode == 'CB1');

      // CA1 remains seasonal_off with 0 detected
      expect(ca1.status, equals('seasonal_off'));
      expect(ca1.detected, equals(0));

      // CA2 remains 5 detected
      expect(ca2.detected, equals(5));

      // CB1 refilled to 5
      expect(cb1.detected, equals(5));
      expect(cb1.status, equals('normal'));

      // Check restock_records has integer createdAt
      final db = await sqliteService.database;
      final rows = await db.rawQuery("SELECT createdAt, typeof(createdAt) as t FROM restock_records WHERE perfumeCode = 'CB1'");
      expect(rows, isNotEmpty);
      expect(rows.first['t'], equals('integer'));
    });

    test('Adversarial: targetSlotCodes updates exclusively requested slot (AA1) and preserves sister slot (AA2)', () async {
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // Initial state: AA1 = 2 bottles, AA2 = 4 bottles
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 4,
        detected: 2,
        status: 'low',
      ));
      await sqliteService.upsertInventoryRecord(InventoryRecordModel(
        id: 'inv_San Pablo_AA2',
        perfumeCode: 'AA2',
        name: 'Perfume AA2',
        category: 'Men',
        branch: 'San Pablo',
        shelf: 'Layer A',
        recorded: 5,
        detected: 4,
        status: 'normal',
      ));

      // Scan detects 4 bottles in left half (< 0.10) and 1 bottle in right half (>= 0.10)
      // BUT caller specifies targetSlotCodes: ['AA1'] (only target slot 1)
      final detections = [
        {'id': 'd1', 'centerX': 0.04, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.05, 'centerY': 0.4},
        {'id': 'd3', 'centerX': 0.06, 'centerY': 0.5},
        {'id': 'd4', 'centerX': 0.07, 'centerY': 0.6},
        {'id': 'd5', 'centerX': 0.14, 'centerY': 0.5},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      expect(counts.containsKey('AA1'), isTrue);
      expect(counts['AA1'], equals(4));
      expect(counts.containsKey('AA2'), isFalse, reason: 'Sister slot AA2 must NOT be included in counts when targeted by slot AA1');

      final invAfter = await sqliteService.getInventoryRecords('San Pablo');
      final aa1 = invAfter.firstWhere((i) => i.perfumeCode == 'AA1');
      final aa2 = invAfter.firstWhere((i) => i.perfumeCode == 'AA2');

      expect(aa1.detected, equals(4));
      expect(aa1.status, equals('normal'));
      expect(aa2.detected, equals(4), reason: 'AA2 was not in targetSlotCodes and must remain at 4 bottles');
      expect(aa2.status, equals('normal'));
    });

    test('Adversarial: roiId without tray_ prefix and calibrated key with tray_ prefix both map cleanly', () async {
      // Calibrated setting has 'tray_AA' as key
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"tray_AA":{"left":0.00,"top":0.10,"right":0.20,"bottom":0.90}}',
      );

      // Detection has raw 'AA' without 'tray_' prefix
      final detections = [
        {'id': 'd1', 'roiId': 'AA', 'centerX': 0.05, 'centerY': 0.3},
        {'id': 'd2', 'roiId': 'AA', 'centerX': 0.15, 'centerY': 0.3},
      ];

      final counts = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['AA'],
      );

      expect(counts['AA1'], equals(1));
      expect(counts['AA2'], equals(1));
    });

    test('Adversarial: Legacy camelCase lowStock alerts are cleaned up on auto-resolution and restock', () async {
      final db = await sqliteService.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Insert legacy alert with camelCase type 'lowStock'
      await db.insert('alerts', {
        'id': 'alert_legacy_lowStock_AA1',
        'title': 'Low Stock Alert',
        'desc': 'Low Stock remaining',
        'branch': 'San Pablo',
        'type': 'lowStock',
        'perfumeCode': 'AA1',
        'isRead': 0,
        'createdAt': now,
      });

      var alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1'), isTrue);

      // Auto-resolution scan with 4 bottles (> 2) in AA1
      final scanResolving = [
        {'id': 'd1', 'centerX': 0.03, 'centerY': 0.3},
        {'id': 'd2', 'centerX': 0.05, 'centerY': 0.4},
        {'id': 'd3', 'centerX': 0.07, 'centerY': 0.5},
        {'id': 'd4', 'centerX': 0.09, 'centerY': 0.6},
        {'id': 'd5', 'centerX': 0.08, 'centerY': 0.7},
      ];

      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: scanResolving,
        branch: 'San Pablo',
        targetSlotCodes: ['AA1'],
      );

      alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && (a.type == 'lowStock' || a.type == 'low_stock')), isFalse, reason: 'Legacy lowStock alert must be deleted upon auto-resolution');
    });

    test('R3: Dynamic cluster midpoint partitioning allocates 5 to AD1 and 5 to AD2 (Sauvage)', () async {
      // Tray AD on Camera 1 with physical divider at 0.7584:
      // left: 0.67717, right: 0.83963, bottom: 0.98.
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AD":{"left":0.67717,"top":0.08573,"right":0.83963,"bottom":0.98}}',
      );

      // 5 bottles in AD1 (100ML, left column): cX from 0.70 to 0.73
      // 5 bottles in AD2 (50ML, right column): cX from 0.78 to 0.82
      // Gap between column 1 (0.73) and column 2 (0.78) is 0.050 >= 0.025
      final detections = [
        {'id': 'ad1_1', 'centerX': 0.705, 'centerY': 0.20},
        {'id': 'ad1_2', 'centerX': 0.712, 'centerY': 0.38},
        {'id': 'ad1_3', 'centerX': 0.718, 'centerY': 0.55},
        {'id': 'ad1_4', 'centerX': 0.724, 'centerY': 0.72},
        {'id': 'ad1_5', 'centerX': 0.730, 'centerY': 0.92},
        {'id': 'ad2_1', 'centerX': 0.780, 'centerY': 0.22},
        {'id': 'ad2_2', 'centerX': 0.788, 'centerY': 0.40},
        {'id': 'ad2_3', 'centerX': 0.795, 'centerY': 0.58},
        {'id': 'ad2_4', 'centerX': 0.805, 'centerY': 0.75},
        {'id': 'ad2_5', 'centerX': 0.815, 'centerY': 0.93},
      ];

      final counts = await sqliteService.processScanResults(
        cameraId: 1,
        detections: detections,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(counts['AD1'], equals(5), reason: 'AD1 (100ML) must detect exactly 5 bottles');
      expect(counts['AD2'], equals(5), reason: 'AD2 (50ML) must detect exactly 5 bottles');

      final inv = await sqliteService.getInventoryRecords('San Pablo');
      final ad1 = inv.firstWhere((i) => i.perfumeCode == 'AD1');
      final ad2 = inv.firstWhere((i) => i.perfumeCode == 'AD2');

      expect(ad1.detected, equals(5));
      expect(ad1.status, equals('normal'));
      expect(ad2.detected, equals(5));
      expect(ad2.status, equals('normal'));

      // Check no low stock alert generated for AD1 or AD2
      final alerts = await sqliteService.getAlerts('San Pablo');
      expect(alerts.any((a) => a.perfumeCode == 'AD1' || a.perfumeCode == 'AD2'), isFalse);
    });

    test('R3: Fallback gracefully to (tr.left + tr.right) / 2.0 when fewer bottles or single column', () async {
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AD":{"left":0.67717,"top":0.08573,"right":0.83963,"bottom":0.98}}',
      );

      // Single bottle on left side
      final singleBottle = [
        {'id': 'single_1', 'centerX': 0.710, 'centerY': 0.50},
      ];

      final counts1 = await sqliteService.processScanResults(
        cameraId: 1,
        detections: singleBottle,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(counts1['AD1'], equals(1));
      expect(counts1['AD2'], equals(0));

      // 3 bottles on one side with small intra-column gaps (< 0.025)
      final threeBottles = [
        {'id': 'b1', 'centerX': 0.710, 'centerY': 0.30},
        {'id': 'b2', 'centerX': 0.715, 'centerY': 0.50},
        {'id': 'b3', 'centerX': 0.720, 'centerY': 0.70},
      ];

      final counts2 = await sqliteService.processScanResults(
        cameraId: 1,
        detections: threeBottles,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(counts2['AD1'], equals(3));
      expect(counts2['AD2'], equals(0));

      // Adversarial: 2 bottles in 100ML slot with wide intra-column gap (gap = 0.040 >= 0.025)
      // Must NOT falsely split single slot into 100ML and 50ML
      final twoBottlesLeftWithWideGap = [
        {'id': 'b_left1', 'centerX': 0.690, 'centerY': 0.30},
        {'id': 'b_left2', 'centerX': 0.730, 'centerY': 0.70},
      ];

      final countsWideGapLeft = await sqliteService.processScanResults(
        cameraId: 1,
        detections: twoBottlesLeftWithWideGap,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsWideGapLeft['AD1'], equals(2), reason: 'Both bottles belong to AD1 despite intra-column gap >= 0.025');
      expect(countsWideGapLeft['AD2'], equals(0), reason: 'AD2 must remain 0 when bottles are on left of divider');

      // Adversarial: 2 bottles in 50ML slot with wide intra-column gap (gap = 0.040 >= 0.025)
      // Must NOT falsely split single slot into 100ML and 50ML
      final twoBottlesRightWithWideGap = [
        {'id': 'b_right1', 'centerX': 0.780, 'centerY': 0.30},
        {'id': 'b_right2', 'centerX': 0.820, 'centerY': 0.70},
      ];

      final countsWideGapRight = await sqliteService.processScanResults(
        cameraId: 1,
        detections: twoBottlesRightWithWideGap,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsWideGapRight['AD1'], equals(0), reason: 'AD1 must remain 0 when bottles are on right of divider');
      expect(countsWideGapRight['AD2'], equals(2), reason: 'Both bottles belong to AD2 despite intra-column gap >= 0.025');

      // Adversarial: 3 bottles in 100ML slot with gap near divider (0.755 - 0.725 = 0.030 >= 0.025)
      // Must NOT falsely assign bottle to AD2
      final threeBottlesLeftWithDividerGap = [
        {'id': 'b_left1', 'centerX': 0.700, 'centerY': 0.30},
        {'id': 'b_left2', 'centerX': 0.725, 'centerY': 0.50},
        {'id': 'b_left3', 'centerX': 0.755, 'centerY': 0.70},
      ];

      final countsThreeLeft = await sqliteService.processScanResults(
        cameraId: 1,
        detections: threeBottlesLeftWithDividerGap,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsThreeLeft['AD1'], equals(3), reason: 'All 3 bottles belong to AD1 (< 0.7584 divider)');
      expect(countsThreeLeft['AD2'], equals(0), reason: 'AD2 must remain 0');

      // Adversarial: 3 bottles in 50ML slot with gap near divider (0.790 - 0.760 = 0.030 >= 0.025)
      // Must NOT falsely assign bottle to AD1
      final threeBottlesRightWithDividerGap = [
        {'id': 'b_right1', 'centerX': 0.760, 'centerY': 0.30},
        {'id': 'b_right2', 'centerX': 0.790, 'centerY': 0.50},
        {'id': 'b_right3', 'centerX': 0.820, 'centerY': 0.70},
      ];

      final countsThreeRight = await sqliteService.processScanResults(
        cameraId: 1,
        detections: threeBottlesRightWithDividerGap,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsThreeRight['AD1'], equals(0), reason: 'AD1 must remain 0');
      expect(countsThreeRight['AD2'], equals(3), reason: 'All 3 bottles belong to AD2 (> 0.7584 divider)');

      // Adversarial: Minor physical tray shift (+0.012 to right)
      // Dynamic cluster midpoint must adapt to shifted acrylic divider
      final shiftedDetections = [
        {'id': 's_ad1_1', 'centerX': 0.717, 'centerY': 0.20},
        {'id': 's_ad1_2', 'centerX': 0.724, 'centerY': 0.38},
        {'id': 's_ad1_3', 'centerX': 0.730, 'centerY': 0.55},
        {'id': 's_ad1_4', 'centerX': 0.736, 'centerY': 0.72},
        {'id': 's_ad1_5', 'centerX': 0.742, 'centerY': 0.92},
        {'id': 's_ad2_1', 'centerX': 0.792, 'centerY': 0.22},
        {'id': 's_ad2_2', 'centerX': 0.800, 'centerY': 0.40},
        {'id': 's_ad2_3', 'centerX': 0.807, 'centerY': 0.58},
        {'id': 's_ad2_4', 'centerX': 0.817, 'centerY': 0.75},
        {'id': 's_ad2_5', 'centerX': 0.827, 'centerY': 0.93},
      ];

      final countsShifted = await sqliteService.processScanResults(
        cameraId: 1,
        detections: shiftedDetections,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsShifted['AD1'], equals(5), reason: 'Shifted tray AD1 must detect 5 bottles');
      expect(countsShifted['AD2'], equals(5), reason: 'Shifted tray AD2 must detect 5 bottles');

      // Adversarial: Minor physical tray shift (-0.012 to left)
      final shiftedLeftDetections = [
        {'id': 'sl_ad1_1', 'centerX': 0.693, 'centerY': 0.20},
        {'id': 'sl_ad1_2', 'centerX': 0.700, 'centerY': 0.38},
        {'id': 'sl_ad1_3', 'centerX': 0.706, 'centerY': 0.55},
        {'id': 'sl_ad1_4', 'centerX': 0.712, 'centerY': 0.72},
        {'id': 'sl_ad1_5', 'centerX': 0.718, 'centerY': 0.92},
        {'id': 'sl_ad2_1', 'centerX': 0.768, 'centerY': 0.22},
        {'id': 'sl_ad2_2', 'centerX': 0.776, 'centerY': 0.40},
        {'id': 'sl_ad2_3', 'centerX': 0.783, 'centerY': 0.58},
        {'id': 'sl_ad2_4', 'centerX': 0.793, 'centerY': 0.75},
        {'id': 'sl_ad2_5', 'centerX': 0.803, 'centerY': 0.93},
      ];

      final countsShiftedLeft = await sqliteService.processScanResults(
        cameraId: 1,
        detections: shiftedLeftDetections,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsShiftedLeft['AD1'], equals(5), reason: 'Left-shifted tray AD1 must detect 5 bottles');
      expect(countsShiftedLeft['AD2'], equals(5), reason: 'Left-shifted tray AD2 must detect 5 bottles');

      // Adversarial: Asymmetric bottle counts across slots (1 in AD1, 5 in AD2)
      final asymmetric1and5 = [
        {'id': 'asym_1', 'centerX': 0.710, 'centerY': 0.40},
        {'id': 'asym_2', 'centerX': 0.780, 'centerY': 0.20},
        {'id': 'asym_3', 'centerX': 0.788, 'centerY': 0.38},
        {'id': 'asym_4', 'centerX': 0.795, 'centerY': 0.55},
        {'id': 'asym_5', 'centerX': 0.805, 'centerY': 0.72},
        {'id': 'asym_6', 'centerX': 0.815, 'centerY': 0.92},
      ];

      final countsAsym1 = await sqliteService.processScanResults(
        cameraId: 1,
        detections: asymmetric1and5,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsAsym1['AD1'], equals(1), reason: 'AD1 should detect exactly 1 bottle');
      expect(countsAsym1['AD2'], equals(5), reason: 'AD2 should detect exactly 5 bottles');

      // Adversarial: Asymmetric bottle counts across slots (5 in AD1, 1 in AD2)
      final asymmetric5and1 = [
        {'id': 'asym5_1', 'centerX': 0.705, 'centerY': 0.20},
        {'id': 'asym5_2', 'centerX': 0.712, 'centerY': 0.38},
        {'id': 'asym5_3', 'centerX': 0.718, 'centerY': 0.55},
        {'id': 'asym5_4', 'centerX': 0.724, 'centerY': 0.72},
        {'id': 'asym5_5', 'centerX': 0.730, 'centerY': 0.92},
        {'id': 'asym5_6', 'centerX': 0.790, 'centerY': 0.40},
      ];

      final countsAsym2 = await sqliteService.processScanResults(
        cameraId: 1,
        detections: asymmetric5and1,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsAsym2['AD1'], equals(5), reason: 'AD1 should detect exactly 5 bottles');
      expect(countsAsym2['AD2'], equals(1), reason: 'AD2 should detect exactly 1 bottle');

      // Adversarial: Bottom row bottles at cY = 0.90 to 0.96 are accepted and processed
      final bottomRowDetections = [
        {'id': 'bot_1', 'centerX': 0.715, 'centerY': 0.90},
        {'id': 'bot_2', 'centerX': 0.720, 'centerY': 0.94},
        {'id': 'bot_3', 'centerX': 0.725, 'centerY': 0.96},
        {'id': 'bot_4', 'centerX': 0.785, 'centerY': 0.90},
        {'id': 'bot_5', 'centerX': 0.795, 'centerY': 0.94},
        {'id': 'bot_6', 'centerX': 0.805, 'centerY': 0.96},
      ];

      final countsBottom = await sqliteService.processScanResults(
        cameraId: 1,
        detections: bottomRowDetections,
        branch: 'San Pablo',
        targetTrayCodes: ['AD'],
      );

      expect(countsBottom['AD1'], equals(3), reason: 'AD1 bottom row bottles accepted');
      expect(countsBottom['AD2'], equals(3), reason: 'AD2 bottom row bottles accepted');
    });

    test('Acceptance: Full 300/300 bottle stock accuracy across all 60 fragrance slots via end-to-end 6-camera scan', () async {
      final db = await sqliteService.database;

      // 1. Degrade inventory to low stock (1 bottle) and insert active low stock alerts
      await db.delete('alerts');
      await db.update('inventory_records', {'detected': 1, 'recorded': 5, 'status': 'low'});
      final initialInv = await sqliteService.getInventoryRecords('San Pablo');
      for (final item in initialInv) {
        await db.insert('alerts', {
          'id': 'alert_test_${item.perfumeCode}',
          'title': 'Low Stock Alert',
          'desc': 'Low stock detected',
          'branch': 'San Pablo',
          'type': 'low_stock',
          'perfumeCode': item.perfumeCode,
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });
      }

      var alertsBefore = await sqliteService.getAlerts('San Pablo');
      expect(alertsBefore.length, equals(60), reason: 'Precondition: 60 active low stock alerts');

      // 2. Configure calibrated ROIs matching physical shelf configuration (bottom = 0.98)
      await sqliteService.setSystemSetting(
        'camera_1_tray_rois',
        '{"AA":{"left":0.06028,"top":0.05912,"right":0.22274,"bottom":0.98},'
        '"AB":{"left":0.26177,"top":0.04656,"right":0.42423,"bottom":0.98},'
        '"AC":{"left":0.45826,"top":0.09903,"right":0.62073,"bottom":0.98},'
        '"AD":{"left":0.67717,"top":0.08573,"right":0.83963,"bottom":0.98},'
        '"AE":{"left":0.85220,"top":0.07982,"right":0.98000,"bottom":0.98}}',
      );
      await sqliteService.setSystemSetting(
        'camera_2_tray_rois',
        '{"AF":{"left":0.02,"top":0.10,"right":0.18,"bottom":0.98},'
        '"AG":{"left":0.22,"top":0.10,"right":0.38,"bottom":0.98},'
        '"AH":{"left":0.42,"top":0.10,"right":0.58,"bottom":0.98},'
        '"AJ":{"left":0.62,"top":0.10,"right":0.78,"bottom":0.98},'
        '"AK":{"left":0.82,"top":0.10,"right":0.98,"bottom":0.98}}',
      );
      await sqliteService.setSystemSetting(
        'camera_3_tray_rois',
        '{"BA":{"left":0.02,"top":0.10,"right":0.18,"bottom":0.98},'
        '"BB":{"left":0.22,"top":0.10,"right":0.38,"bottom":0.98},'
        '"BC":{"left":0.42,"top":0.10,"right":0.58,"bottom":0.98},'
        '"BD":{"left":0.62,"top":0.10,"right":0.78,"bottom":0.98},'
        '"BE":{"left":0.82,"top":0.10,"right":0.98,"bottom":0.98}}',
      );
      await sqliteService.setSystemSetting(
        'camera_4_tray_rois',
        '{"BF":{"left":0.02,"top":0.10,"right":0.18,"bottom":0.98},'
        '"BG":{"left":0.22,"top":0.10,"right":0.38,"bottom":0.98},'
        '"BH":{"left":0.42,"top":0.10,"right":0.58,"bottom":0.98},'
        '"BJ":{"left":0.62,"top":0.10,"right":0.78,"bottom":0.98},'
        '"BK":{"left":0.82,"top":0.10,"right":0.98,"bottom":0.98}}',
      );
      await sqliteService.setSystemSetting(
        'camera_5_tray_rois',
        '{"CA":{"left":0.1983,"top":0.10,"right":0.3533,"bottom":0.98},'
        '"CB":{"left":0.3658,"top":0.10,"right":0.5208,"bottom":0.98},'
        '"CC":{"left":0.5333,"top":0.10,"right":0.6883,"bottom":0.98},'
        '"CD":{"left":0.7008,"top":0.10,"right":0.8558,"bottom":0.98},'
        '"CE":{"left":0.8916,"top":0.10,"right":1.0000,"bottom":0.98}}',
      );
      await sqliteService.setSystemSetting(
        'camera_6_tray_rois',
        '{"CF":{"left":0.1803,"top":0.10,"right":0.3353,"bottom":0.98},'
        '"CG":{"left":0.3478,"top":0.10,"right":0.5028,"bottom":0.98},'
        '"CH":{"left":0.5153,"top":0.10,"right":0.6703,"bottom":0.98},'
        '"CJ":{"left":0.6828,"top":0.10,"right":0.8378,"bottom":0.98},'
        '"CK":{"left":0.8556,"top":0.10,"right":1.0000,"bottom":0.98}}',
      );

      // Calibrated coordinates map for all 6 cameras
      final Map<int, Map<String, List<double>>> cameraCalibrations = {
        1: {
          'AA': [0.06028, 0.22274],
          'AB': [0.26177, 0.42423],
          'AC': [0.45826, 0.62073],
          'AD': [0.67717, 0.83963],
          'AE': [0.85220, 0.98000],
        },
        2: {
          'AF': [0.02, 0.18],
          'AG': [0.22, 0.38],
          'AH': [0.42, 0.58],
          'AJ': [0.62, 0.78],
          'AK': [0.82, 0.98],
        },
        3: {
          'BA': [0.02, 0.18],
          'BB': [0.22, 0.38],
          'BC': [0.42, 0.58],
          'BD': [0.62, 0.78],
          'BE': [0.82, 0.98],
        },
        4: {
          'BF': [0.02, 0.18],
          'BG': [0.22, 0.38],
          'BH': [0.42, 0.58],
          'BJ': [0.62, 0.78],
          'BK': [0.82, 0.98],
        },
        5: {
          'CA': [0.1983, 0.3533],
          'CB': [0.3658, 0.5208],
          'CC': [0.5333, 0.6883],
          'CD': [0.7008, 0.8558],
          'CE': [0.8916, 1.0000],
        },
        6: {
          'CF': [0.1803, 0.3353],
          'CG': [0.3478, 0.5028],
          'CH': [0.5153, 0.6703],
          'CJ': [0.6828, 0.8378],
          'CK': [0.8556, 1.0000],
        },
      };

      // 3. Execute simulated full shelf scan across all 6 cameras
      int totalScannedBottles = 0;
      for (int camId = 1; camId <= 6; camId++) {
        final calTrays = cameraCalibrations[camId]!;
        final List<Map<String, dynamic>> camDetections = [];

        for (final entry in calTrays.entries) {
          final trayCode = entry.key;
          final l = entry.value[0];
          final r = entry.value[1];
          final mid = (l + r) / 2.0;
          final slot1W = mid - l;
          final slot2W = r - mid;

          // 5 bottles in left slot (100ML) with bottom bottle at cY = 0.94
          for (int b = 0; b < 5; b++) {
            final cx = l + (0.25 + (b * 0.10)) * slot1W;
            final cy = 0.20 + (b * (0.94 - 0.20) / 4.0);
            camDetections.add({
              'id': 'det_c${camId}_${trayCode}_l$b',
              'roiId': 'tray_$trayCode',
              'centerX': cx,
              'centerY': cy,
            });
          }

          // 5 bottles in right slot (50ML) with bottom bottle at cY = 0.94
          for (int b = 0; b < 5; b++) {
            final cx = mid + (0.25 + (b * 0.10)) * slot2W;
            final cy = 0.20 + (b * (0.94 - 0.20) / 4.0);
            camDetections.add({
              'id': 'det_c${camId}_${trayCode}_r$b',
              'roiId': 'tray_$trayCode',
              'centerX': cx,
              'centerY': cy,
            });
          }
        }

        final counts = await sqliteService.updateInventoryFromDetections(
          cameraId: camId,
          detections: camDetections,
          branch: 'San Pablo',
        );

        for (final entry in calTrays.entries) {
          final tray = entry.key;
          expect(counts['${tray}1'], equals(5), reason: '$tray 1 (100ML) must detect 5 bottles');
          expect(counts['${tray}2'], equals(5), reason: '$tray 2 (50ML) must detect 5 bottles');
          totalScannedBottles += counts['${tray}1']! + counts['${tray}2']!;
        }
      }

      expect(totalScannedBottles, equals(300), reason: 'Total detected bottles across all 6 cameras must be 300');

      // 4. Verify SQLite final state
      final inv = await sqliteService.getInventoryRecords('San Pablo');
      expect(inv.length, equals(60), reason: 'Must have exactly 60 fragrance slots');

      final totalDetected = inv.fold<int>(0, (sum, item) => sum + item.detected);
      final totalRecorded = inv.fold<int>(0, (sum, item) => sum + item.recorded);

      expect(totalDetected, equals(300), reason: 'Total detected stock must be 300');
      expect(totalRecorded, equals(300), reason: 'Total recorded stock must be 300');

      for (final item in inv) {
        expect(item.detected, equals(5), reason: '${item.perfumeCode} must be 5 bottles');
        expect(item.status, equals('normal'), reason: '${item.perfumeCode} status must be normal');
      }

      // 5. Verify all 60 pre-existing alerts were auto-resolved upon restock
      final alertsAfter = await sqliteService.getAlerts('San Pablo');
      final activeAlerts = alertsAfter.where((a) => a.type == 'low_stock' || a.type == 'lowStock' || a.type == 'out_of_stock').toList();
      expect(activeAlerts, isEmpty, reason: 'Zero false low stock or out of stock alerts on full restock');
    });
  });
}


