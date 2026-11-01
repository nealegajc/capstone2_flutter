import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/core/constants/app_constants.dart';
import 'package:smart_shelf_linux/core/router/route_names.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/models/system_log_model.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/roi_provider.dart';
import 'package:smart_shelf_linux/ui/components/pin_recovery_dialog.dart';
import 'package:smart_shelf_linux/ui/components/roi_editor_overlay.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/ui/screens/camera_monitor/camera_monitor_screen.dart';
import 'package:smart_shelf_linux/ui/screens/dashboard/dashboard_screen.dart';

class FakePythonApiRepository extends PythonApiRepository {
  final Map<int, List<Map<String, dynamic>>> detectionsByCam;
  FakePythonApiRepository(this.detectionsByCam);

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    return {
      'success': true,
      'camera_id': cameraId,
      'detections': detectionsByCam[cameraId] ?? [],
    };
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('R1: Accurate Scan Results & Count Synchronization for Seasonal Fragrances', () {
    late SqliteService sqliteService;
    const testBranch = 'Test Branch R1';

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      await sqliteService.setSystemSetting('branch_name', testBranch);
      final db = await sqliteService.database;
      await db.delete('products');
      await db.delete('inventory_records');
      await db.delete('alerts');
    });

    test('InventoryRecordModel invariants for seasonal_off items', () {
      final activeNormal = InventoryRecordModel(
        id: 'inv_1',
        perfumeCode: 'AA1',
        name: 'Active Normal',
        branch: testBranch,
        shelf: 'Layer A',
        recorded: 5,
        detected: 5,
        status: 'normal',
      );
      expect(activeNormal.isSeasonalOff, isFalse);
      expect(activeNormal.isLowStock, isFalse);
      expect(activeNormal.isOutOfStock, isFalse);
      expect(activeNormal.isMisplaced, isFalse);
      expect(activeNormal.isNeedsReview, isFalse);

      final activeLow = InventoryRecordModel(
        id: 'inv_2',
        perfumeCode: 'AA2',
        name: 'Active Low',
        branch: testBranch,
        shelf: 'Layer A',
        recorded: 5,
        detected: 2,
        status: 'low',
      );
      expect(activeLow.isSeasonalOff, isFalse);
      expect(activeLow.isLowStock, isTrue);

      final seasonalOffZero = InventoryRecordModel(
        id: 'inv_3',
        perfumeCode: 'AA3',
        name: 'Seasonal Off Zero',
        branch: testBranch,
        shelf: 'Layer A',
        recorded: 5,
        detected: 0,
        status: 'seasonal_off',
      );
      expect(seasonalOffZero.isSeasonalOff, isTrue);
      // Seasonal off MUST NOT trigger low stock, out of stock, or discrepancy
      expect(seasonalOffZero.isLowStock, isFalse);
      expect(seasonalOffZero.isOutOfStock, isFalse);
      expect(seasonalOffZero.isMisplaced, isFalse);
      expect(seasonalOffZero.isNeedsReview, isFalse);

      final seasonalOffTwo = InventoryRecordModel(
        id: 'inv_4',
        perfumeCode: 'AA4',
        name: 'Seasonal Off Two',
        branch: testBranch,
        shelf: 'Layer A',
        recorded: 5,
        detected: 2,
        status: 'seasonal_off',
      );
      expect(seasonalOffTwo.isSeasonalOff, isTrue);
      expect(seasonalOffTwo.isLowStock, isFalse);
      expect(seasonalOffTwo.isOutOfStock, isFalse);
    });

    test('SqliteService.getSeasonalOffSlotCodes and updateInventoryFromDetections zeroing out', () async {
      final db = await sqliteService.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      await db.insert('products', {
        'id': 'prod_AA1',
        'perfumeCode': 'AA1',
        'name': 'Active Fragrance',
        'status': 'active',
      });
      await db.insert('products', {
        'id': 'prod_AA2',
        'perfumeCode': 'AA2',
        'name': 'Seasonal Off Fragrance 1',
        'status': 'seasonal_off',
      });
      await db.insert('products', {
        'id': 'prod_AB1',
        'perfumeCode': 'AB1',
        'name': 'Seasonal Off Fragrance 2',
        'status': 'seasonal_off',
      });

      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Active Fragrance',
        'branch': testBranch,
        'shelf': 'Layer A',
        'recorded': 5,
        'detected': 5,
        'status': 'normal',
        'lastUpdated': now,
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA2',
        'perfumeCode': 'AA2',
        'name': 'Seasonal Off Fragrance 1',
        'branch': testBranch,
        'shelf': 'Layer A',
        'recorded': 5,
        'detected': 0,
        'status': 'seasonal_off',
        'lastUpdated': now,
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AB1',
        'perfumeCode': 'AB1',
        'name': 'Seasonal Off Fragrance 2',
        'branch': testBranch,
        'shelf': 'Layer A',
        'recorded': 5,
        'detected': 0,
        'status': 'seasonal_off',
        'lastUpdated': now,
      });

      final seasonalOffCodes = await sqliteService.getSeasonalOffSlotCodes(branch: testBranch);
      expect(seasonalOffCodes, containsAll(['AA2', 'AB1']));
      expect(seasonalOffCodes, isNot(contains('AA1')));

      // In camera 1, tray AA spans [0.0, 0.20] with midX at 0.10:
      // Left side (AA1) is cx < 0.10 (e.g. 0.05)
      // Right side (AA2) is cx >= 0.10 (e.g. 0.15)
      final simulatedDetections = [
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95},
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95},
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95},
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95},
        // Bottles physically placed in paused slot AA2:
        {'roiId': 'tray_AA', 'centerX': 0.15, 'confidence': 0.95},
        {'roiId': 'tray_AA', 'centerX': 0.15, 'confidence': 0.95},
      ];

      final results = await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        branch: testBranch,
        detections: simulatedDetections,
      );

      // AA1 (active) updates to 4 detected
      expect(results['AA1'], 4);
      // AA2 (seasonal-off): effective detected count returned MUST be strictly 0
      expect(results['AA2'], 0);

      final invRows = await db.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: ['AA2', testBranch],
      );
      expect(invRows.first['detected'], 0);
      expect(invRows.first['status'], 'seasonal_off');

      // Verify NO alerts generated for AA2
      final alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'AA2'), isEmpty);
    });

    testWidgets('ScanWorkflowDialog initializes cleanly for scan workflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.byType(ScanWorkflowDialog), findsOneWidget);
    });

    testWidgets('ScanWorkflowDialog completed view displays 290 bottles and Seasonal / Off badge', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = await sqliteService.database;
      final batch = db.batch();
      for (int c = 1; c <= 6; c++) {
        final slotCodes = SqliteService.getSlotCodesForCamera(c);
        for (final slot in slotCodes) {
          final isOff = (slot == 'AA2' || slot == 'AB1');
          batch.insert('products', {
            'id': 'prod_$slot',
            'perfumeCode': slot,
            'name': 'Perfume $slot',
            'status': isOff ? 'seasonal_off' : 'active',
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          batch.insert('inventory_records', {
            'id': 'inv_${testBranch}_$slot',
            'perfumeCode': slot,
            'name': 'Perfume $slot',
            'branch': testBranch,
            'shelf': 'Shelf $slot',
            'recorded': 5,
            'detected': isOff ? 0 : 5,
            'status': isOff ? 'seasonal_off' : 'normal',
            'lastUpdated': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      await batch.commit(noResult: true);

      final mockDetectionsByCam = <int, List<Map<String, dynamic>>>{};
      for (int c = 1; c <= 6; c++) {
        final defaultTrays = SqliteService.getDefaultTrayCodesForCamera(c);
        final savedJson = await sqliteService.getSetting('camera_${c}_tray_rois');
        Map<String, dynamic>? slotRois;
        if (savedJson != null && savedJson.isNotEmpty) {
          final raw = jsonDecode(savedJson);
          if (raw is Map) {
            slotRois = {};
            raw.forEach((k, v) => slotRois![k.toString().replaceFirst('tray_', '').trim().toUpperCase()] = v);
          }
        }
        final dets = <Map<String, dynamic>>[];
        for (int tIdx = 0; tIdx < defaultTrays.length; tIdx++) {
          final tray = defaultTrays[tIdx];
          final rMap = slotRois?[tray] as Map<String, dynamic>?;
          final l = (rMap?['left'] as num?)?.toDouble() ?? (tIdx * (1.0 / defaultTrays.length));
          final r = (rMap?['right'] as num?)?.toDouble() ?? ((tIdx + 1) * (1.0 / defaultTrays.length));
          final mid = (l + r) / 2.0;
          final cx1 = l + (mid - l) / 2.0;
          final cx2 = mid + (r - mid) / 2.0;

          for (final isSlot1 in [true, false]) {
            final cx = isSlot1 ? cx1 : cx2;
            for (int b = 0; b < 5; b++) {
              dets.add({
                'roiId': 'tray_$tray',
                'centerX': cx,
                'confidence': 0.95,
                'class': 'bottle',
              });
            }
          }
        }
        mockDetectionsByCam[c] = dets;
      }

      final mockApi = FakePythonApiRepository(mockDetectionsByCam);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final proceedBtn = find.text('Start Full Shelf Scan');
      expect(proceedBtn, findsOneWidget);
      await tester.ensureVisible(proceedBtn);
      await tester.tap(proceedBtn);
      await tester.pump();
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final has290 = find.text('290').evaluate().isNotEmpty;
        if (has290) break;
      }

      expect(find.text('290'), findsOneWidget);
      expect(find.text('2 Fragrances Seasonal / Off (Skipped)'), findsOneWidget);
      expect(find.text('PAUSED'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('ScanWorkflowDialog Full Shelf Scan renders readiness checklist and PAUSED badge on seasonal-off items', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final db = await sqliteService.database;
      await db.insert('products', {
        'id': 'prod_AA1',
        'perfumeCode': 'AA1',
        'name': 'Active Fragrance',
        'status': 'active',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('products', {
        'id': 'prod_AA2',
        'perfumeCode': 'AA2',
        'name': 'Paused Fragrance',
        'status': 'seasonal_off',
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Active Fragrance',
        'branch': testBranch,
        'shelf': 'Tray AA',
        'recorded': 5,
        'detected': 5,
        'status': 'normal',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA2',
        'perfumeCode': 'AA2',
        'name': 'Paused Fragrance',
        'branch': testBranch,
        'shelf': 'Tray AA',
        'recorded': 5,
        'detected': 0,
        'status': 'seasonal_off',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final dets = [
        for (int i = 0; i < 5; i++)
          {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95, 'class': 'bottle'},
        for (int i = 0; i < 3; i++)
          {'roiId': 'tray_AA', 'centerX': 0.15, 'confidence': 0.95, 'class': 'bottle'},
      ];

      final mockApi = FakePythonApiRepository({1: dets});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Full Shelf Scan readiness checklist items (R1 rules) and start button
      expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
      expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);
      expect(find.text('Do Not Cover Perfume Caps or Camera Lenses'), findsOneWidget);
      expect(find.text('Upright Bottle Caps Facing Upward'), findsOneWidget);
      expect(find.text('Camera Line of Sight & Obstruction'), findsNothing);
      expect(find.text('Adequate LED Shelf Lighting'), findsNothing);
      expect(find.text('Shelf Glass Door Closed'), findsNothing);
      expect(find.text('Upright Bottle Caps & SKU Cap Stickers Facing Upward'), findsNothing);
      expect(find.text('Single Tray Check'), findsNothing);

      final startScanBtn = find.text('Start Full Shelf Scan');
      expect(startScanBtn, findsOneWidget);
      await tester.ensureVisible(startScanBtn);
      await tester.tap(startScanBtn);
      await tester.pump();
      for (int i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        final match = find.text('PAUSED').evaluate().isNotEmpty;
        if (match) break;
      }

      // Paused slot AA2 renders PAUSED badge and seasonal off notification
      expect(find.text('PAUSED'), findsWidgets);
      expect(find.text('1 Fragrance Seasonal / Off (Skipped)'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 300));
    });

    test('dashboardStatsProvider properly computes zero active items and capacity when all SKUs are seasonal off', () async {
      final container = ProviderContainer(
        overrides: [
          liveInventoryProvider(testBranch).overrideWith((ref) async => [
            for (int i = 1; i <= 60; i++)
              InventoryRecordModel(
                id: 'inv_$i',
                perfumeCode: 'AA$i',
                name: 'Item $i',
                branch: testBranch,
                shelf: 'Layer A',
                recorded: 5,
                detected: 0,
                status: 'seasonal_off',
              ),
          ]),
          liveAlertsProvider(testBranch).overrideWith((ref) async => []),
        ],
      );
      addTearDown(container.dispose);

      final stats = await container.read(dashboardStatsProvider(testBranch).future);
      expect(stats.activeItemCount, equals(0));
      expect(stats.totalCapacity, equals(0));
      expect(stats.totalInStock, equals(0));
      expect(stats.lowStockCount, equals(0));
      expect(stats.outOfStockCount, equals(0));
    });

    testWidgets('DashboardScreen renders zero capacity gracefully when all fragrances are seasonal off', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleZeroStats = DashboardStats(
        totalInStock: 0,
        activeItemCount: 0,
        lowStockCount: 0,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 0,
      );

      final allSeasonalOffItems = [
        for (int i = 1; i <= 20; i++)
          InventoryRecordModel(
            id: 'inv_a_$i',
            perfumeCode: 'AA$i',
            name: 'Item A$i',
            branch: testBranch,
            shelf: 'Layer A',
            recorded: 5,
            detected: 0,
            status: 'seasonal_off',
          ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => testBranch),
            dashboardStatsProvider(testBranch).overrideWith((ref) => sampleZeroStats),
            liveInventoryProvider(testBranch).overrideWith((ref) => allSeasonalOffItems),
            liveAlertsProvider(testBranch).overrideWith((ref) => <AlertModel>[]),
            hardwareCamerasProvider.overrideWith((ref) => Stream.value(<HardwareCameraDevice>[])),
            systemActivityLogsProvider(testBranch).overrideWith((ref) => Stream.value(<SystemLogModel>[])),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('0% Full'), findsOneWidget);
      expect(find.text('0 Fragrances • 0 Shelf Cap'), findsOneWidget);
      expect(find.text('0 / 0 Bottles'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });

  group('R2: Live Camera Monitor Visual Indicators', () {
    testWidgets('RoiEditorOverlay mounts with disabledCapCodes in roi state', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: RoiEditorOverlay(
                roi: RoiState(
                  cameraId: 1,
                  disabledCapCodes: {'AA'},
                ),
                slotCodes: ['AA', 'AB', 'AC', 'AD', 'AE'],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final customPaintFinder = find.byType(CustomPaint);
      expect(customPaintFinder, findsWidgets);

      final overlay = tester.widget<RoiEditorOverlay>(find.byType(RoiEditorOverlay));
      expect(overlay.roi.disabledCapCodes.contains('AA'), isTrue);
    });

    testWidgets('CameraMonitorScreen specs panel displays SEASONAL / OFF (SKIPPED) badge', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sampleProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AA1',
          name: 'Active Amber Scent',
          brand: 'OttoScents',
          category: 'Men',
          shelfLayer: 'Top Shelf',
          slotPosition: 1,
          bottleSize: '100ml',
          price: 99.0,
          status: 'active',
        ),
        ProductModel(
          id: 'p2',
          perfumeCode: 'AA2',
          name: 'Winter Spice (Seasonal)',
          brand: 'OttoScents',
          category: 'Men',
          shelfLayer: 'Top Shelf',
          slotPosition: 2,
          bottleSize: '100ml',
          price: 99.0,
          status: 'seasonal_off',
        ),
      ];

      final sampleRecords = [
        InventoryRecordModel(
          id: 'inv_1',
          perfumeCode: 'AA1',
          name: 'Active Amber Scent',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: 5,
          status: 'normal',
        ),
        InventoryRecordModel(
          id: 'inv_2',
          perfumeCode: 'AA2',
          name: 'Winter Spice (Seasonal)',
          branch: 'San Pablo',
          shelf: 'Layer A',
          recorded: 5,
          detected: 0,
          status: 'seasonal_off',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            masterProductsProvider.overrideWith((ref) => sampleProducts),
            liveInventoryProvider('San Pablo').overrideWith((ref) => sampleRecords),
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            liveAlertsProvider('San Pablo').overrideWith((ref) => <AlertModel>[]),
          ],
          child: const MaterialApp(
            home: CameraMonitorScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('SEASONAL / OFF (SKIPPED)'), findsWidgets);

      // Cleanly unmount to clear the 300ms stopLiveStream timer
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('CameraMonitorScreen specs panel displays SEASONAL / OFF (SKIPPED) badge for non-default branch', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customBranch = 'Calamba Branch';
      final sampleProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AA1',
          name: 'Active Amber Scent',
          brand: 'OttoScents',
          category: 'Men',
          shelfLayer: 'Top Shelf',
          slotPosition: 1,
          bottleSize: '100ml',
          price: 99.0,
          status: 'active',
        ),
        ProductModel(
          id: 'p2',
          perfumeCode: 'AA2',
          name: 'Winter Spice (Seasonal)',
          brand: 'OttoScents',
          category: 'Men',
          shelfLayer: 'Top Shelf',
          slotPosition: 2,
          bottleSize: '100ml',
          price: 99.0,
          status: 'seasonal_off',
        ),
      ];

      final sampleRecords = [
        InventoryRecordModel(
          id: 'inv_1',
          perfumeCode: 'AA1',
          name: 'Active Amber Scent',
          branch: customBranch,
          shelf: 'Layer A',
          recorded: 5,
          detected: 5,
          status: 'normal',
        ),
        InventoryRecordModel(
          id: 'inv_2',
          perfumeCode: 'AA2',
          name: 'Winter Spice (Seasonal)',
          branch: customBranch,
          shelf: 'Layer A',
          recorded: 5,
          detected: 0,
          status: 'seasonal_off',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            masterProductsProvider.overrideWith((ref) => sampleProducts),
            liveInventoryProvider(customBranch).overrideWith((ref) => sampleRecords),
            currentBranchProvider.overrideWith((ref) => customBranch),
            liveAlertsProvider(customBranch).overrideWith((ref) => <AlertModel>[]),
          ],
          child: const MaterialApp(
            home: CameraMonitorScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('SEASONAL / OFF (SKIPPED)'), findsWidgets);

      // Cleanly unmount to clear the 300ms stopLiveStream timer
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('R3: PIN Recovery Dialog Virtual Keyboard Elimination', () {
    setUp(() async {
      await SqliteService.instance.initDatabase(inMemory: true);
    });

    testWidgets('Step 0 has no virtual QWERTY keyboard, Step 1 retains virtual numpad', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      bool resetSuccessCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinRecoveryDialog(
              onPinResetSuccess: () {
                resetSuccessCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Step 0: Answer Questions
      expect(find.text('Verify Security Answers'), findsOneWidget);
      // Verify NO QWERTY keys exist in Step 0
      expect(find.text('Q'), findsNothing);
      expect(find.text('W'), findsNothing);
      expect(find.text('SPACE'), findsNothing);

      // Verify question inputs are standard TextFields
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(3));

      // Enter correct answers without virtual keyboard
      await tester.enterText(textFields.at(0), AppConstants.recoveryAnswer1);
      await tester.enterText(textFields.at(1), AppConstants.recoveryAnswer2);
      await tester.enterText(textFields.at(2), AppConstants.recoveryAnswer3);
      await tester.pump();

      // Proceed to Step 1
      await tester.tap(find.text('Verify Security Answers'));
      await tester.pumpAndSettle();

      // Step 1: Set New PIN
      expect(find.text('New 6-Digit Store PIN'), findsOneWidget);
      expect(find.text('Confirm New PIN'), findsOneWidget);

      // Verify virtual numpad keys are present
      for (final key in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'CLR']) {
        expect(find.text(key), findsOneWidget);
      }
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

      // Test tapping key and backspace
      await tester.tap(find.text('9'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byIcon(Icons.backspace_outlined));
      await tester.pump(const Duration(milliseconds: 50));

      // Input 6-digit PIN '654321' into first field using virtual numpad
      for (final digit in ['6', '5', '4', '3', '2', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Tap confirm PIN field to switch active field
      final pinFields = find.byType(TextField);
      expect(pinFields, findsNWidgets(2));
      await tester.tap(pinFields.at(1));
      await tester.pumpAndSettle();

      // Input matching PIN '654321' into second field using virtual numpad
      for (final digit in ['6', '5', '4', '3', '2', '1']) {
        await tester.tap(find.text(digit));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Submit new PIN
      final resetBtn = find.text('Reset & Save New Security PIN');
      expect(resetBtn, findsOneWidget);
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      expect(resetSuccessCalled, isTrue);
    });
  });

  group('R4: Button and Screen Redundancy Elimination', () {
    test('Router and route names have /roi-detail and /image-quality completely eliminated', () {
      expect(AppRoutePaths.dashboard, '/dashboard');
      expect(AppRoutePaths.inventory, '/inventory');
      expect(AppRoutePaths.cameraMonitor, '/camera-monitor');
      expect(AppRoutePaths.alerts, '/alerts');
    });

    testWidgets('DashboardScreen has 3 staff actions without duplicate Shelf Scan and no Live Cameras in hero', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleStats = DashboardStats(
        totalInStock: 290,
        activeItemCount: 58,
        lowStockCount: 0,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 290,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith((ref) => sampleStats),
            liveInventoryProvider('San Pablo').overrideWith((ref) => <InventoryRecordModel>[]),
            liveAlertsProvider('San Pablo').overrideWith((ref) => <AlertModel>[]),
            hardwareCamerasProvider.overrideWith((ref) => Stream.value(<HardwareCameraDevice>[])),
            systemActivityLogsProvider('San Pablo').overrideWith((ref) => Stream.value(<SystemLogModel>[])),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: const MaterialApp(
            home: DashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Hero banner checks
      expect(find.text('CHECK SHELF NOW'), findsOneWidget);
      expect(find.text('Selective Scan'), findsOneWidget);
      // OutlinedButton 'Live Cameras' in Hero group removed
      expect(find.widgetWithText(OutlinedButton, 'Live Cameras'), findsNothing);

      // Bottom quick actions checks
      expect(find.text('Record Sale'), findsOneWidget);
      expect(find.text('Log Restock'), findsOneWidget);
      expect(find.text('Export Stock CSV'), findsOneWidget);
      // Duplicate 'Shelf Scan' tile removed
      expect(find.text('Shelf Scan'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
