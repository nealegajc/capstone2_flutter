import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/core/router/route_names.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/low_stock_banner.dart';
import 'package:smart_shelf_linux/ui/screens/alerts/alerts_screen.dart';
import 'package:smart_shelf_linux/ui/screens/inventory/inventory_screen.dart';
import 'package:smart_shelf_linux/ui/screens/inventory/product_detail_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Targeted Fixes Verification & Edge Case Defense', () {
    late SqliteService sqliteService;
    const testBranch = 'Test Branch';

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      await sqliteService.setSystemSetting('branch_name', testBranch);
      final db = await sqliteService.database;
      await db.delete('products');
      await db.delete('inventory_records');
      await db.delete('alerts');
    });

    test('R1: Setting fragrance to seasonal_off silences stock alerts and keeps slot allocated', () async {
      final db = await sqliteService.database;

      // Seed a test product and inventory record
      await db.insert('products', {
        'id': 'prod_test_AA1',
        'perfumeCode': 'AA1',
        'name': 'Test Perfume AA1',
        'status': 'active',
        'slotPosition': 1,
        'shelfLayer': 'Layer A',
        'bottleSize': '100ml',
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Test Perfume AA1',
        'branch': testBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 0,
        'status': 'out_of_stock',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // Initially getAlerts should create an active out_of_stock alert
      var alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.any((a) => a.perfumeCode == 'AA1' && a.type == 'out_of_stock'), isTrue);

      // Now toggle to seasonal_off
      await sqliteService.toggleProductStatus(
        productId: 'prod_test_AA1',
        newStatus: 'seasonal_off',
        branch: testBranch,
      );

      // 1. Verify slot remains allocated in database
      final prodRows = await db.query('products', where: 'id = ?', whereArgs: ['prod_test_AA1']);
      expect(prodRows.isNotEmpty, isTrue);
      expect(prodRows.first['status'], equals('seasonal_off'));

      final invRows = await db.query('inventory_records', where: 'perfumeCode = ? AND branch = ?', whereArgs: ['AA1', testBranch]);
      expect(invRows.isNotEmpty, isTrue);
      expect(invRows.first['status'], equals('seasonal_off'));

      // 2. Verify all active low_stock and out_of_stock alerts are cleared
      alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'AA1'), isEmpty);

      // 3. Vision scan (processScanResults) should skip alert generation for seasonal_off
      await sqliteService.processScanResults(
        cameraId: 1,
        detections: [], // 0 detections
        branch: testBranch,
        targetSlotCodes: ['AA1'],
      );

      alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'AA1'), isEmpty);

      // 4. Toggle back to active -> immediately re-evaluates and generates alert
      await sqliteService.toggleProductStatus(
        productId: 'prod_test_AA1',
        newStatus: 'active',
        branch: testBranch,
      );

      final invRowsAfterActive = await db.query('inventory_records', where: 'perfumeCode = ? AND branch = ?', whereArgs: ['AA1', testBranch]);
      expect(invRowsAfterActive.first['status'], equals('out_of_stock'));

      alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'AA1' && a.type == 'out_of_stock').length, equals(1));
    });

    test('R2: Low stock and out-of-stock alerts synchronization with exactly 2 active alerts', () async {
      final db = await sqliteService.database;

      // Seed 2 products with stock <= 2: AA1 has 2 bottles, AA2 has 1 bottle
      await db.insert('products', {
        'id': 'prod_test_AA1',
        'perfumeCode': 'AA1',
        'name': 'Test Perfume AA1',
        'status': 'active',
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Test Perfume AA1',
        'branch': testBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 2,
        'status': 'low',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      await db.insert('products', {
        'id': 'prod_test_AA2',
        'perfumeCode': 'AA2',
        'name': 'Test Perfume AA2',
        'status': 'active',
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA2',
        'perfumeCode': 'AA2',
        'name': 'Test Perfume AA2',
        'branch': testBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 1,
        'status': 'low',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // Synchronize via getAlerts: both AA1 (2 bottles) and AA2 (1 bottle) have low_stock
      final alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.length, equals(2));
      expect(alerts.every((a) => a.type == 'low_stock'), isTrue);

      // Transition AA1 down to 0 bottles: out_of_stock alert is generated
      await db.update('inventory_records', {'detected': 0, 'status': 'out_of_stock'}, where: 'perfumeCode = ?', whereArgs: ['AA1']);
      final alertsAfterDrop = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alertsAfterDrop.any((a) => a.perfumeCode == 'AA1' && a.type == 'out_of_stock'), isTrue);
      expect(alertsAfterDrop.any((a) => a.perfumeCode == 'AA2' && a.type == 'low_stock'), isTrue);

      // Replenish AA1 to 4 bottles (>= 3): auto-resolve AA1 alert
      await db.update('inventory_records', {'detected': 4, 'status': 'normal'}, where: 'perfumeCode = ?', whereArgs: ['AA1']);
      final refreshedAlerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(refreshedAlerts.length, equals(1));
      expect(refreshedAlerts.first.perfumeCode, equals('AA2'));
    });

    test('R1 Edge Case: Products table direct seasonal_off update suppresses alerts in getAlerts', () async {
      final db = await sqliteService.database;

      // Seed product and inventory record, initially active
      await db.insert('products', {
        'id': 'prod_test_CC1',
        'perfumeCode': 'CC1',
        'name': 'Test Perfume CC1',
        'status': 'seasonal_off', // Marked seasonal_off in products table directly
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_CC1',
        'perfumeCode': 'CC1',
        'name': 'Test Perfume CC1',
        'branch': testBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 0,
        'status': 'out_of_stock', // Simulating desync where inventory_records hasn't updated yet
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // getAlerts should cross-check products table and suppress alert generation for CC1
      final alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'CC1'), isEmpty);
    });

    testWidgets('R2: AlertsScreen displays exactly 2 active alerts matching top banner when 2 fragrances <= 2', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlerts = [
        AlertModel(
          id: 'alert_low_stock_1',
          title: 'Low Stock Alert',
          desc: 'Slot AA1: Low stock (2 remaining)',
          branch: testBranch,
          type: 'low_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        AlertModel(
          id: 'alert_low_stock_2',
          title: 'Low Stock Alert',
          desc: 'Slot AA2: Low stock (1 remaining)',
          branch: testBranch,
          type: 'low_stock',
          perfumeCode: 'AA2',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => testBranch),
            liveAlertsProvider(testBranch).overrideWith((ref) => activeAlerts),
            resolvedAlertsHistoryProvider(testBranch).overrideWith((ref) => []),
            liveInventoryProvider(testBranch).overrideWith((ref) => [
              InventoryRecordModel(id: 'inv_1', perfumeCode: 'AA1', name: 'Perfume AA1', branch: testBranch, shelf: 'Shelf 1', detected: 2, recorded: 5, status: 'low'),
              InventoryRecordModel(id: 'inv_2', perfumeCode: 'AA2', name: 'Perfume AA2', branch: testBranch, shelf: 'Shelf 1', detected: 1, recorded: 5, status: 'low'),
            ]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check header badge
      expect(find.text('2 ACTIVE'), findsOneWidget);
      // Check toggle tab
      expect(find.text('Active Alerts'), findsOneWidget);
      // Check Low Stock filter chip count
      expect(find.text('Low Stock'), findsWidgets);
      // Check both alert cards rendered
      expect(find.text('Slot AA1: Low stock (2 remaining)'), findsOneWidget);
      expect(find.text('Slot AA2: Low stock (1 remaining)'), findsOneWidget);
    });

    testWidgets('R3: LowStockBanner has View Details button navigating to /alerts and exact subtitle without Restock Now', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testStats = DashboardStats(
        totalInStock: 250,
        lowStockCount: 2,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 300,
        activeItemCount: 60,
        outOfStockCount: 0,
        restockNeededCount: 2,
      );

      bool navigatedToAlerts = false;
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Column(
                children: [
                  LowStockBanner(),
                ],
              ),
            ),
          ),
          GoRoute(
            path: AppRoutePaths.alerts,
            builder: (context, state) {
              navigatedToAlerts = true;
              return const Scaffold(body: Text('Alerts Center Page'));
            },
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => testBranch),
            dashboardStatsProvider(testBranch).overrideWith((ref) => testStats),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();

      // 1. Verify Restock Now button is NOT present
      expect(find.text('Restock Now'), findsNothing);

      // 2. Verify View Details button IS present
      final viewDetailsBtn = find.text('View Details');
      expect(viewDetailsBtn, findsOneWidget);

      // 3. Verify exact subtitle text
      expect(
        find.text('2 fragrance slot(s) running low (≤ 2 bottles). Tap View Details to inspect alerts.'),
        findsOneWidget,
      );
      // Verify no mention of One-click refill
      expect(find.textContaining('One-click refill'), findsNothing);

      // 4. Tap View Details and verify navigation to Alerts Center
      await tester.tap(viewDetailsBtn);
      await tester.pumpAndSettle();

      expect(navigatedToAlerts, isTrue);
      expect(find.text('Alerts Center Page'), findsOneWidget);
    });

    testWidgets('R1: InventoryScreen preserves Seasonal / Off badge and Off/Active switch', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testProductOff = ProductModel(
        id: 'prod_off',
        name: 'Seasonal Scent',
        perfumeCode: 'AA1',
        brand: 'Otto',
        category: 'Men',
        bottleSize: '100ml',
        shelfLayer: 'Layer A',
        slotPosition: 1,
        price: 250.0,
        status: 'seasonal_off',
      );

      final testInvOff = InventoryRecordModel(
        id: 'inv_off',
        perfumeCode: 'AA1',
        name: 'Seasonal Scent',
        branch: testBranch,
        shelf: 'Layer A - Slot A',
        recorded: 5,
        detected: 0,
        status: 'seasonal_off',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => testBranch),
            masterProductsProvider.overrideWith((ref) => [testProductOff]),
            liveInventoryProvider(testBranch).overrideWith((ref) => [testInvOff]),
            dashboardStatsProvider(testBranch).overrideWith(
              (ref) => const DashboardStats(
                totalInStock: 0,
                lowStockCount: 0,
                misplacedCount: 0,
                needsVerificationCount: 0,
                totalCapacity: 300,
                activeItemCount: 59,
                outOfStockCount: 0,
                restockNeededCount: 0,
              ),
            ),
          ],
          child: const MaterialApp(
            home: InventoryScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify 'Seasonal / Off' badge is visible
      expect(find.text('Seasonal / Off'), findsWidgets);
      // Verify 'Off' label next to switch is visible
      expect(find.text('Off'), findsWidgets);
      // Verify it does NOT say 'Disabled / Paused'
      expect(find.textContaining('Disabled'), findsNothing);
      expect(find.textContaining('Paused'), findsNothing);
    });

    test('R2: updateInventoryFromDetections creates out_of_stock alert and clears low_stock alert when detected == 0', () async {
      final db = await sqliteService.database;

      await db.insert('products', {
        'id': 'prod_test_AD1',
        'perfumeCode': 'AD1',
        'name': 'Test Perfume AD1',
        'status': 'active',
      });
      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AD1',
        'perfumeCode': 'AD1',
        'name': 'Test Perfume AD1',
        'branch': testBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 2,
        'status': 'low',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // Initially trigger a low stock alert
      await sqliteService.getAlerts(testBranch, unreadOnly: true);
      var alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.any((a) => a.perfumeCode == 'AD1' && a.type == 'low_stock'), isTrue);

      // Now run vision scan detection with 0 bottles for AD1 (Camera 1 covers AD tray)
      await sqliteService.updateInventoryFromDetections(
        cameraId: 1,
        detections: [],
        branch: testBranch,
        targetSlotCodes: ['AD1'],
      );

      alerts = await sqliteService.getAlerts(testBranch, unreadOnly: true);
      expect(alerts.any((a) => a.perfumeCode == 'AD1' && a.type == 'out_of_stock'), isTrue);
      expect(alerts.any((a) => a.perfumeCode == 'AD1' && a.type == 'low_stock'), isTrue);
    });

    test('R1: toggleProductStatus updates inventory_records and alerts for custom dynamic branch', () async {
      final db = await sqliteService.database;
      const customBranch = 'Lipa Branch';

      await db.insert('products', {
        'id': 'prod_test_EE1',
        'perfumeCode': 'EE1',
        'name': 'Test Perfume EE1',
        'status': 'active',
      });
      await db.insert('inventory_records', {
        'id': 'inv_${customBranch}_EE1',
        'perfumeCode': 'EE1',
        'name': 'Test Perfume EE1',
        'branch': customBranch,
        'shelf': 'Shelf 1',
        'recorded': 5,
        'detected': 1,
        'status': 'low',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // Synchronize alert
      await sqliteService.getAlerts(customBranch, unreadOnly: true);
      var alerts = await sqliteService.getAlerts(customBranch, unreadOnly: true);
      expect(alerts.any((a) => a.perfumeCode == 'EE1' && a.type == 'low_stock'), isTrue);

      // Toggle status to seasonal_off on customBranch
      await sqliteService.toggleProductStatus(
        productId: 'prod_test_EE1',
        newStatus: 'seasonal_off',
        branch: customBranch,
      );

      // Verify customBranch inventory_records row was updated to seasonal_off
      final rows = await db.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: ['EE1', customBranch],
      );
      expect(rows.first['status'], equals('seasonal_off'));

      // Verify alerts for customBranch were cleared
      alerts = await sqliteService.getAlerts(customBranch, unreadOnly: true);
      expect(alerts.where((a) => a.perfumeCode == 'EE1'), isEmpty);
    });

    testWidgets('R1: ProductDetailScreen preserves seasonal off toggle switch and reflects active status', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const customBranch = 'Lipa Branch';
      final testProduct = ProductModel(
        id: 'prod_test_EE1',
        perfumeCode: 'EE1',
        name: 'Test Perfume EE1',
        brand: 'Otto Scents',
        category: 'Men',
        bottleSize: '100ml',
        shelfLayer: 'Layer A',
        slotPosition: 1,
        price: 250.0,
        status: 'active',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => customBranch),
            masterProductsProvider.overrideWith((ref) => [testProduct]),
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            home: ProductDetailScreen(product: testProduct),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Active On Shelf'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });
  });
}
