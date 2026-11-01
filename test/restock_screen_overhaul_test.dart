import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/models/restock_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/restock/create_restock_screen.dart';
import 'package:smart_shelf_linux/ui/screens/restock/restock_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Milestone 2 (R2): Restock & Deliveries Screen Overhaul Tests', () {
    setUp(() async {
      await SqliteService.instance.initDatabase(inMemory: true);
    });

    testWidgets('R2.1 & R2.2: RestockScreen displays dynamic branch and Card 1 Shelf Capacity Health metrics', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 278,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 0,
        restockNeededCount: 2,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify dynamic branch header
      expect(find.text('Branch: San Pablo'), findsOneWidget);
      expect(find.text('Restock & Deliveries Management'), findsOneWidget);
      expect(find.text('Log New Restock'), findsOneWidget);
      expect(find.text('Export Restock CSV'), findsWidgets);

      // Verify Card 1: Shelf Capacity Health
      expect(find.text('Shelf Capacity Health'), findsOneWidget);
      expect(find.text('278 / 300'), findsOneWidget);
      expect(find.text('Bottles on Shelf'), findsOneWidget);
      expect(find.text('92.7% Capacity Filled'), findsOneWidget);
      expect(find.text('OPTIMAL'), findsOneWidget);

      // Verify sub-metrics
      expect(find.text('Active Slots Count'), findsOneWidget);
      expect(find.text('60 Slots'), findsOneWidget);
      expect(find.text('Empty Bottle Deficit'), findsOneWidget);
      expect(find.text('22 Bottles'), findsOneWidget);
    });

    testWidgets('R2.3: Shelf Capacity Health status badge updates based on percentage thresholds', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'Makati';

      // 1. Critical (< 50%)
      const criticalStats = DashboardStats(
        totalInStock: 120,
        totalCapacity: 300, // 40%
        activeItemCount: 60,
        lowStockCount: 15,
        outOfStockCount: 10,
        restockNeededCount: 25,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(criticalStats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('CRITICAL'), findsOneWidget);

      // 2. Restock Recommended (50-74%)
      const recommendedStats = DashboardStats(
        totalInStock: 180,
        totalCapacity: 300, // 60%
        activeItemCount: 60,
        lowStockCount: 5,
        outOfStockCount: 2,
        restockNeededCount: 7,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(recommendedStats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('RESTOCK RECOMMENDED'), findsOneWidget);

      // 3. Normal (75-89%)
      const normalStats = DashboardStats(
        totalInStock: 250,
        totalCapacity: 300, // 83.3%
        activeItemCount: 60,
        lowStockCount: 3,
        outOfStockCount: 0,
        restockNeededCount: 3,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(normalStats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NORMAL'), findsOneWidget);
    });

    testWidgets('R2.4: Card 2 Trays Needing Restock renders low stock items and celebratory optimal state', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 270,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 1,
        restockNeededCount: 3,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final dummyProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          category: 'Men',
        ),
        ProductModel(
          id: 'p2',
          perfumeCode: 'BB2',
          name: 'Chanel Coco Mademoiselle',
          bottleSize: '50ml',
          shelfLayer: 'Layer B',
          category: 'Women',
        ),
      ];

      final lowStockInventory = [
        InventoryRecordModel(
          id: 'inv1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          branch: testBranch,
          shelf: 'Layer A',
          detected: 1,
          recorded: 1,
        ),
        InventoryRecordModel(
          id: 'inv2',
          perfumeCode: 'BB2',
          name: 'Chanel Coco Mademoiselle',
          branch: testBranch,
          shelf: 'Layer B',
          detected: 0,
          recorded: 0,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value(lowStockInventory)),
            masterProductsProvider.overrideWith((ref) => Future.value(dummyProducts)),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Card 2 header
      expect(find.text('Trays Needing Restock'), findsOneWidget);
      expect(find.text('2 Trays Require Refill'), findsOneWidget);

      // Verify Fragrance 1: AD1
      expect(find.text('AD1'), findsOneWidget);
      expect(find.text('Christian Dior Sauvage'), findsOneWidget);
      expect(find.text('Tray AD - Layer A • 100ML'), findsOneWidget);
      expect(find.text('1 / 5 Bottles'), findsOneWidget);
      expect(find.text('Needs +4 bottles to fill'), findsOneWidget);

      // Verify Fragrance 2: BB2 (Out of stock)
      expect(find.text('BB2'), findsOneWidget);
      expect(find.text('Chanel Coco Mademoiselle'), findsOneWidget);
      expect(find.text('Tray BB - Layer B • 50ML'), findsOneWidget);
      expect(find.text('0 / 5 Bottles'), findsOneWidget);
      expect(find.text('Needs +5 bottles to fill'), findsOneWidget);

      // Direct action buttons
      expect(find.text('Restock Now'), findsNWidgets(2));

      // Now verify celebratory card when 0 trays need replenishment
      final optimalInventory = [
        InventoryRecordModel(
          id: 'inv1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          branch: testBranch,
          shelf: 'Layer A',
          detected: 5,
          recorded: 5,
        ),
        InventoryRecordModel(
          id: 'inv2',
          perfumeCode: 'BB2',
          name: 'Chanel Coco Mademoiselle',
          branch: testBranch,
          shelf: 'Layer B',
          detected: 4,
          recorded: 4,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value(optimalInventory)),
            masterProductsProvider.overrideWith((ref) => Future.value(dummyProducts)),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Shelf Stock Optimal: 0 Trays Require Replenishment'), findsOneWidget);
      expect(find.text('All Trays Stocked'), findsOneWidget);
    });

    testWidgets('R2.5: Card 3 Recent Restock Activity displays delivery batches and status badges', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      const stats = DashboardStats(
        totalInStock: 285,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 0,
        outOfStockCount: 0,
        restockNeededCount: 0,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final dummyRecords = [
        RestockRecordModel(
          id: 'rst_1001',
          productName: 'Bleu de Chanel',
          perfumeCode: 'AA1',
          quantity: 5,
          fromBranch: 'Main Warehouse',
          toBranch: testBranch,
          requestedBy: 'Manager',
          status: 'verified',
          createdAt: DateTime(2026, 11, 1, 10, 30),
        ),
        RestockRecordModel(
          id: 'rst_1002',
          productName: 'Tom Ford Black Orchid',
          perfumeCode: 'CF2',
          quantity: 3,
          fromBranch: 'Main Warehouse',
          toBranch: testBranch,
          requestedBy: 'Manager',
          status: 'received',
          createdAt: DateTime(2026, 11, 1, 9, 15),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            dashboardStatsProvider(testBranch).overrideWith((ref) => Future.value(stats)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value([])),
            masterProductsProvider.overrideWith((ref) => Future.value([])),
            restockRecordsProvider(testBranch).overrideWith((ref) => Future.value(dummyRecords)),
            stockMovementLogsProvider(testBranch).overrideWith((ref) => Future.value([])),
          ],
          child: const MaterialApp(
            home: RestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recent Restock Activity'), findsOneWidget);
      expect(find.text('Bleu de Chanel'), findsOneWidget);
      expect(find.text('AA1'), findsOneWidget);
      expect(find.text('+5 Bottles'), findsOneWidget);
      expect(find.text('Verified'), findsOneWidget);

      expect(find.text('Tom Ford Black Orchid'), findsOneWidget);
      expect(find.text('CF2'), findsOneWidget);
      expect(find.text('+3 Bottles'), findsOneWidget);
      expect(find.text('Received'), findsOneWidget);
    });

    testWidgets('R2.6: CreateRestockScreen pre-selects perfume when initialPerfumeCode is provided', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      final dummyProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          category: 'Men',
        ),
        ProductModel(
          id: 'p2',
          perfumeCode: 'BB2',
          name: 'Chanel Coco Mademoiselle',
          bottleSize: '50ml',
          shelfLayer: 'Layer B',
          category: 'Women',
        ),
      ];

      final inventory = [
        InventoryRecordModel(
          id: 'inv1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          branch: testBranch,
          shelf: 'Layer A',
          detected: 1,
          recorded: 1,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            masterProductsProvider.overrideWith((ref) => Future.value(dummyProducts)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value(inventory)),
          ],
          child: const MaterialApp(
            home: CreateRestockScreen(initialPerfumeCode: 'AD1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Screen should open directly on Step 2 with Christian Dior Sauvage pre-selected
      expect(find.text('Christian Dior Sauvage'), findsOneWidget);
      expect(find.text('AD1'), findsOneWidget);
      expect(find.text('Camera 1'), findsOneWidget);
      expect(find.text('Current Stock: 1 / 5 Bottles (Deficit: +4)'), findsOneWidget);

      // Deficit is 4, so Fill Tray (4) button should be present
      expect(find.text('Fill Tray (4)'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.text('Confirm Restock'), findsOneWidget);
      expect(find.text('Verify with Camera (Camera 1)'), findsOneWidget);
    });

    testWidgets('R2.7: CreateRestockScreen Step 1 supports search, filter chips, visual selection, and step progression', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      final dummyProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AA1',
          name: 'Bleu de Chanel',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          category: 'Men',
        ),
        ProductModel(
          id: 'p2',
          perfumeCode: 'BA2',
          name: 'Miss Dior Rose',
          bottleSize: '50ml',
          shelfLayer: 'Layer B',
          category: 'Women',
        ),
        ProductModel(
          id: 'p3',
          perfumeCode: 'CA1',
          name: 'Autumn Spice Seasonal',
          bottleSize: '100ml',
          shelfLayer: 'Layer C',
          category: 'Unisex',
          status: 'seasonal',
        ),
      ];

      final inventory = [
        InventoryRecordModel(
          id: 'inv1',
          perfumeCode: 'AA1',
          name: 'Bleu de Chanel',
          branch: testBranch,
          shelf: 'Layer A',
          detected: 2, // low stock
          recorded: 2,
        ),
        InventoryRecordModel(
          id: 'inv2',
          perfumeCode: 'BA2',
          name: 'Miss Dior Rose',
          branch: testBranch,
          shelf: 'Layer B',
          detected: 5, // full stock
          recorded: 5,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            masterProductsProvider.overrideWith((ref) => Future.value(dummyProducts)),
            liveInventoryProvider(testBranch).overrideWith((ref) => Future.value(inventory)),
          ],
          child: const MaterialApp(
            home: CreateRestockScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1 headers and filter chips
      expect(find.text('1. Pick Perfume / Tray'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Layer A'), findsOneWidget);
      expect(find.text('Layer B'), findsOneWidget);
      expect(find.text('Layer C'), findsOneWidget);
      expect(find.text('Low Stock <=2'), findsOneWidget);

      // Verify all 3 visual cards are initially visible
      expect(find.text('Bleu de Chanel'), findsOneWidget);
      expect(find.text('Miss Dior Rose'), findsOneWidget);
      expect(find.text('Autumn Spice Seasonal'), findsOneWidget);

      // Test Search query filter
      await tester.enterText(find.byType(TextField), 'Rose');
      await tester.pumpAndSettle();
      expect(find.text('Miss Dior Rose'), findsOneWidget);
      expect(find.text('Bleu de Chanel'), findsNothing);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Bleu de Chanel'), findsOneWidget);

      // Test Low Stock <=2 filter chip
      await tester.tap(find.text('Low Stock <=2'));
      await tester.pumpAndSettle();
      expect(find.text('Bleu de Chanel'), findsOneWidget); // stock 2
      expect(find.text('Miss Dior Rose'), findsNothing); // stock 5

      // Select Bleu de Chanel card
      await tester.tap(find.text('Bleu de Chanel'));
      await tester.pumpAndSettle();

      // Proceed to Step 2
      await tester.tap(find.text('Continue to Step 2 (Select Quantity)'));
      await tester.pumpAndSettle();

      // Should now be on Step 2
      expect(find.text('Select Replenishment Quantity'), findsOneWidget);
      expect(find.text('Bleu de Chanel'), findsOneWidget);
      expect(find.text('Current Stock: 2 / 5 Bottles (Deficit: +3)'), findsOneWidget);
      expect(find.text('Fill Tray (3)'), findsOneWidget);
    });

    testWidgets('R2.8 & R2.9: CreateRestockScreen Step 2 quick tap buttons (+1, +5, Fill Tray), capacity guard, and confirm restock', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testBranch = 'San Pablo';
      final dummyProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          category: 'Men',
        ),
      ];

      // Initial inventory in SQLite - update existing seeded record
      final existingRec = await SqliteService.instance.getInventoryRecord('AD1', testBranch);
      final recordId = existingRec?.id ?? 'inv_ad1';
      await SqliteService.instance.upsertInventoryRecord(
        InventoryRecordModel(
          id: recordId,
          perfumeCode: 'AD1',
          name: 'Christian Dior Sauvage',
          branch: testBranch,
          shelf: 'Layer A',
          detected: 2,
          recorded: 2,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value(testBranch)),
            masterProductsProvider.overrideWith((ref) => Future.value(dummyProducts)),
            liveInventoryProvider(testBranch).overrideWith(
              (ref) => Future.value([
                InventoryRecordModel(
                  id: 'inv_ad1',
                  perfumeCode: 'AD1',
                  name: 'Christian Dior Sauvage',
                  branch: testBranch,
                  shelf: 'Layer A',
                  detected: 2,
                  recorded: 2,
                ),
              ]),
            ),
          ],
          child: const MaterialApp(
            home: CreateRestockScreen(initialPerfumeCode: 'AD1'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Deficit is (5 - 2) = 3
      expect(find.text('Fill Tray (3)'), findsOneWidget);

      // 1. Tap '+1' quick button -> sets quantity to 1
      await tester.tap(find.text('+1'));
      await tester.pumpAndSettle();
      expect(find.text('1'), findsWidgets);
      expect(find.text('Bottle Added'), findsOneWidget);

      // 2. Tap '+5' quick button -> sets quantity to 5
      await tester.tap(find.text('+5'));
      await tester.pumpAndSettle();
      expect(find.text('5'), findsWidgets);
      expect(find.text('Bottles Added'), findsOneWidget);

      // Capacity guard warning should appear because 2 + 5 = 7 > 5
      expect(find.textContaining('Capacity Warning: Adding 5 bottles will bring total stock to 7'), findsOneWidget);

      // 3. Tap 'Fill Tray (3)' quick button -> sets quantity to exactly 3
      await tester.tap(find.text('Fill Tray (3)'));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsWidgets);
      // Warning should be gone because 2 + 3 = 5 <= 5
      expect(find.textContaining('Capacity Warning'), findsNothing);

      // 4. Test manual Stepper '-' and '+'
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsWidgets);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(find.text('3'), findsWidgets);

      // 5. Enter batch notes
      await tester.enterText(
        find.byType(TextFormField),
        'Supplier invoice #8812, batch ref A',
      );
      await tester.pumpAndSettle();

      // 6. Tap Confirm Restock button
      await tester.ensureVisible(find.text('Confirm Restock'));
      await tester.tap(find.text('Confirm Restock'));
      await tester.pumpAndSettle();

      // Verify SQLite state: recorded stock was incremented from 2 to 5 (2 + 3)
      final updatedInv = await SqliteService.instance.getInventoryRecord('AD1', testBranch);
      expect(updatedInv, isNotNull);
      expect(updatedInv!.recorded, equals(5));
      expect(updatedInv.detected, equals(2)); // camera detected invariant preserved

      // Verify restock record was created
      final restocks = await SqliteService.instance.getRestockRecords(testBranch);
      expect(restocks.any((r) => r.perfumeCode == 'AD1' && r.quantity == 3), isTrue);

      // Verify inventory event was logged
      final events = await SqliteService.instance.getInventoryEvents(testBranch);
      expect(events.any((e) => e.eventType == 'RESTOCKED' && e.perfumeCode == 'AD1' && e.quantity == 3), isTrue);
    });
  });
}
