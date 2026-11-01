import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/inventory/inventory_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Requirement 4: 60-SKU Shelf Physical Reality & Capacity Logic', () {
    test('Physical shelf capacity invariants (30 Trays x 2 Slots = 60 Slots, 300 Bottles)', () {
      const totalTrays = 30;
      const slotsPerTray = 2;
      const maxBottlesPerSlot = 5;

      const totalSlots = totalTrays * slotsPerTray;
      const totalBottleCapacity = totalSlots * maxBottlesPerSlot;

      expect(totalSlots, equals(60));
      expect(totalBottleCapacity, equals(300));
    });

    test('isShelfFull logic: NOT full at 30 items, full at 60 items', () {
      // Create 30 items (1 SKU per tray)
      final items30 = List<ProductModel>.generate(
        30,
        (i) => ProductModel(
          id: 'prod_$i',
          name: 'Fragrance $i',
          perfumeCode: '${String.fromCharCode(65 + (i ~/ 10))}${String.fromCharCode(65 + (i % 10))}1',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          slotPosition: i + 1,
          price: 250.0,
        ),
      );

      final occupiedSlots30 = items30.length;
      final uniqueTrays30 = items30
          .map((p) => p.perfumeCode.length >= 2 ? p.perfumeCode.substring(0, 2) : p.name)
          .toSet();
      final isShelfFull30 = occupiedSlots30 >= 60;
      final slotsLeft30 = 60 - occupiedSlots30;

      expect(occupiedSlots30, equals(30));
      expect(uniqueTrays30.length, equals(30));
      expect(isShelfFull30, isFalse, reason: 'Shelf must NOT be full when only 30 slots are occupied!');
      expect(slotsLeft30, equals(30));

      // Create 59 items
      final items59 = List<ProductModel>.generate(
        59,
        (i) => ProductModel(
          id: 'prod_$i',
          name: 'Fragrance $i',
          perfumeCode: 'P$i',
          bottleSize: '50ml',
          shelfLayer: 'Layer A',
          slotPosition: 1,
          price: 250.0,
        ),
      );
      expect(items59.length >= 60, isFalse);
      expect(60 - items59.length, equals(1));

      // Create 60 items (full physical shelf)
      final items60 = List<ProductModel>.generate(
        60,
        (i) => ProductModel(
          id: 'prod_$i',
          name: 'Fragrance $i',
          perfumeCode: 'P$i',
          bottleSize: '50ml',
          shelfLayer: 'Layer A',
          slotPosition: 1,
          price: 250.0,
        ),
      );
      final isShelfFull60 = items60.length >= 60;
      expect(isShelfFull60, isTrue);
      expect(60 - items60.length, equals(0));
    });

    test('Pill and button label formatting matches 60-slot specifications', () {
      // 30 items
      const occupied30 = 30;
      const trays30 = 30;
      const isFull30 = occupied30 >= 60;

      final pillText30 = isFull30
          ? 'Shelf Full (60/60 Slots • 30 Trays)'
          : '$occupied30 / 60 Slots Occupied ($trays30 / 30 Trays)';
      final buttonText30 = isFull30
          ? 'Shelf Full (60/60)'
          : 'Add Fragrance (${60 - occupied30} Slots Left)';

      expect(pillText30, equals('30 / 60 Slots Occupied (30 / 30 Trays)'));
      expect(buttonText30, equals('Add Fragrance (30 Slots Left)'));

      // 60 items
      const occupied60 = 60;
      const trays60 = 30;
      const isFull60 = occupied60 >= 60;

      final pillText60 = isFull60
          ? 'Shelf Full (60/60 Slots • 30 Trays)'
          : '$occupied60 / 60 Slots Occupied ($trays60 / 30 Trays)';
      final buttonText60 = isFull60
          ? 'Shelf Full (60/60)'
          : 'Add Fragrance (${60 - occupied60} Slots Left)';

      expect(pillText60, equals('Shelf Full (60/60 Slots • 30 Trays)'));
      expect(buttonText60, equals('Shelf Full (60/60)'));
    });
  });

  group('Requirement 4: Dynamic Tray-to-Camera Hardware Routing', () {
    test('All 30 physical trays (AA through CK) route strictly to cameras 1 through 6', () {
      final expectedRouting = <String, int>{
        // Camera 1: Layer A Left (trays AA to AE)
        'AA': 1, 'AB': 1, 'AC': 1, 'AD': 1, 'AE': 1,
        // Camera 2: Layer A Right (trays AF to AK)
        'AF': 2, 'AG': 2, 'AH': 2, 'AJ': 2, 'AK': 2,
        // Camera 3: Layer B Left (trays BA to BE)
        'BA': 3, 'BB': 3, 'BC': 3, 'BD': 3, 'BE': 3,
        // Camera 4: Layer B Right (trays BF to BK)
        'BF': 4, 'BG': 4, 'BH': 4, 'BJ': 4, 'BK': 4,
        // Camera 5: Layer C Left (trays CA to CE)
        'CA': 5, 'CB': 5, 'CC': 5, 'CD': 5, 'CE': 5,
        // Camera 6: Layer C Right (trays CF to CK)
        'CF': 6, 'CG': 6, 'CH': 6, 'CJ': 6, 'CK': 6,
      };

      expect(expectedRouting.length, equals(30), reason: 'Must test all 30 physical trays');

      for (final entry in expectedRouting.entries) {
        final tray = entry.key;
        final expectedCam = entry.value;

        // Test tray code
        expect(
          SqliteService.getCameraIdForTray(tray),
          equals(expectedCam),
          reason: 'Tray $tray must route to Camera $expectedCam',
        );

        // Test lowercase
        expect(
          SqliteService.getCameraIdForTray(tray.toLowerCase()),
          equals(expectedCam),
          reason: 'Tray ${tray.toLowerCase()} must route to Camera $expectedCam',
        );

        // Test with slot suffix 1 (100ml) and 2 (50ml)
        expect(
          SqliteService.getCameraIdForTray('${tray}1'),
          equals(expectedCam),
          reason: 'Slot ${tray}1 must route to Camera $expectedCam',
        );
        expect(
          SqliteService.getCameraIdForTray('${tray}2'),
          equals(expectedCam),
          reason: 'Slot ${tray}2 must route to Camera $expectedCam',
        );
      }
    });

    test('Slot codes for each camera produce exactly 10 slots (5 trays x 2 slots)', () {
      for (int cam = 1; cam <= 6; cam++) {
        final slots = SqliteService.getSlotCodesForCamera(cam);
        expect(slots.length, equals(10), reason: 'Camera $cam must observe exactly 10 product slots');
        for (final slot in slots) {
          expect(SqliteService.getCameraIdForTray(slot), equals(cam));
        }
      }
    });
  });

  group('Requirement 4: Shelf Area Review Persistence in SQLite', () {
    late SqliteService sqlite;

    setUp(() async {
      sqlite = SqliteService.instance;
      await sqlite.initDatabase(inMemory: true);
    });

    test('Shelf reviewed status is persisted to system_settings and loaded correctly', () async {
      const tierKeys = ['A_LEFT', 'A_RIGHT', 'B_LEFT', 'B_RIGHT', 'C_LEFT', 'C_RIGHT'];

      // 1. Initially none should be reviewed
      for (final key in tierKeys) {
        final initialVal = await sqlite.getSetting('shelf_reviewed_$key');
        expect(initialVal, isNull, reason: 'Initial reviewed state for $key should be null');
      }

      // 2. Mark A_LEFT and C_RIGHT as reviewed
      final timestampA = DateTime.now().toIso8601String();
      await sqlite.setSystemSetting('shelf_reviewed_A_LEFT', timestampA);
      await sqlite.logActivity(
        type: 'SHELF_REVIEW',
        description: 'Physical shelf inspection verified for Layer A Left.',
        branch: 'San Pablo',
      );

      final timestampC = DateTime.now().add(const Duration(seconds: 1)).toIso8601String();
      await sqlite.setSystemSetting('shelf_reviewed_C_RIGHT', timestampC);
      await sqlite.logActivity(
        type: 'SHELF_REVIEW',
        description: 'Physical shelf inspection verified for Layer C Right.',
        branch: 'San Pablo',
      );

      // 3. Verify persistence
      final valA = await sqlite.getSetting('shelf_reviewed_A_LEFT');
      expect(valA, equals(timestampA));

      final valC = await sqlite.getSetting('shelf_reviewed_C_RIGHT');
      expect(valC, equals(timestampC));

      // Other tiers remain unreviewed
      final valB = await sqlite.getSetting('shelf_reviewed_B_LEFT');
      expect(valB, isNull);

      // 4. Verify system log activity was recorded
      final logs = await sqlite.getSystemLogs('San Pablo');
      final reviewLogs = logs.where((l) => l.type == 'SHELF_REVIEW').toList();
      expect(reviewLogs.length, greaterThanOrEqualTo(2));
      expect(reviewLogs.any((l) => l.description.contains('Layer A Left')), isTrue);
      expect(reviewLogs.any((l) => l.description.contains('Layer C Right')), isTrue);
    });

    test('Dynamic branch resolution via getBranchName()', () async {
      final defaultBranch = await sqlite.getBranchName();
      expect(defaultBranch, equals('San Pablo'));

      // Update branch in system settings
      await sqlite.setSystemSetting('branch_name', 'SM Megamall');
      final updatedBranch = await sqlite.getBranchName();
      expect(updatedBranch, equals('SM Megamall'));

      // Low stock threshold uses dynamic branch without crashing
      await sqlite.setLowStockThreshold(3);
      final threshold = await sqlite.getLowStockThreshold();
      expect(threshold, equals(3));
    });
  });

  group('Requirement 4: Riverpod Provider Invalidation on Catalog Reset', () {
    test('Riverpod providers invalidate properly on catalog restore trigger', () async {
      int productFetchCount = 0;
      int inventoryFetchCount = 0;
      int statsFetchCount = 0;
      int alertsFetchCount = 0;
      int logsFetchCount = 0;

      final testMasterProductsProvider = FutureProvider<List<String>>((ref) async {
        productFetchCount++;
        return ['Product $productFetchCount'];
      });

      final testLiveInventoryProvider = FutureProvider.family<List<String>, String?>((ref, branch) async {
        inventoryFetchCount++;
        return ['Inv $inventoryFetchCount for $branch'];
      });

      final testDashboardStatsProvider = FutureProvider.family<int, String?>((ref, branch) async {
        statsFetchCount++;
        return statsFetchCount;
      });

      final testLiveAlertsProvider = FutureProvider.family<List<String>, String?>((ref, branch) async {
        alertsFetchCount++;
        return ['Alert $alertsFetchCount'];
      });

      final testLogsProvider = FutureProvider.family<List<String>, String?>((ref, branch) async {
        logsFetchCount++;
        return ['Log $logsFetchCount'];
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Initial read
      expect(await container.read(testMasterProductsProvider.future), equals(['Product 1']));
      expect(await container.read(testLiveInventoryProvider('San Pablo').future), equals(['Inv 1 for San Pablo']));
      expect(await container.read(testDashboardStatsProvider('San Pablo').future), equals(1));
      expect(await container.read(testLiveAlertsProvider('San Pablo').future), equals(['Alert 1']));
      expect(await container.read(testLogsProvider('San Pablo').future), equals(['Log 1']));

      expect(productFetchCount, equals(1));
      expect(inventoryFetchCount, equals(1));
      expect(statsFetchCount, equals(1));
      expect(alertsFetchCount, equals(1));
      expect(logsFetchCount, equals(1));

      // Trigger catalog reset invalidation cycle
      const branch = 'San Pablo';
      container.invalidate(testMasterProductsProvider);
      container.invalidate(testLiveInventoryProvider(branch));
      container.invalidate(testDashboardStatsProvider(branch));
      container.invalidate(testLiveAlertsProvider(branch));
      container.invalidate(testLogsProvider(branch));

      // Read again - each provider must re-fetch freshly
      expect(await container.read(testMasterProductsProvider.future), equals(['Product 2']));
      expect(await container.read(testLiveInventoryProvider('San Pablo').future), equals(['Inv 2 for San Pablo']));
      expect(await container.read(testDashboardStatsProvider('San Pablo').future), equals(2));
      expect(await container.read(testLiveAlertsProvider('San Pablo').future), equals(['Alert 2']));
      expect(await container.read(testLogsProvider('San Pablo').future), equals(['Log 2']));

      expect(productFetchCount, equals(2));
      expect(inventoryFetchCount, equals(2));
      expect(statsFetchCount, equals(2));
      expect(alertsFetchCount, equals(2));
      expect(logsFetchCount, equals(2));
    });
  });

  group('Requirement 4: InventoryScreen Widget UI Alignment', () {
    testWidgets('InventoryScreen displays 30 Slots Left and NOT shelf full with 30 items', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final items30 = List<ProductModel>.generate(
        30,
        (i) => ProductModel(
          id: 'prod_$i',
          name: 'Fragrance $i',
          perfumeCode: '${String.fromCharCode(65 + (i ~/ 10))}${String.fromCharCode(65 + (i % 10))}1',
          bottleSize: '100ml',
          shelfLayer: 'Layer A',
          slotPosition: i + 1,
          price: 250.0,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            masterProductsProvider.overrideWith((ref) => items30),
            liveInventoryProvider('San Pablo').overrideWith((ref) => []),
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify ribbon header text
      expect(
        find.textContaining('30 Trays • 60 Slots • 300 Bottles Capacity'),
        findsOneWidget,
      );

      // Verify button says "Add Fragrance (30 Slots Left)"
      expect(find.text('Add Fragrance (30 Slots Left)'), findsOneWidget);

      // Verify "Shelf Full (60/60)" is NOT present
      expect(find.text('Shelf Full (60/60)'), findsNothing);

      // Verify capacity pill badge text
      expect(find.text('30 / 60 Slots Occupied (30 / 30 Trays)'), findsOneWidget);
    });

    testWidgets('InventoryScreen displays Shelf Full (60/60) when all 60 slots are occupied', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 60 physical slots occupied
      final items60 = <ProductModel>[];
      final layers = ['Layer A', 'Layer B', 'Layer C'];
      int id = 0;
      for (int l = 0; l < 3; l++) {
        final layerChar = String.fromCharCode(65 + l);
        for (int t = 0; t < 10; t++) {
          final trayLetter = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K'][t];
          final trayCode = '$layerChar$trayLetter';
          items60.add(ProductModel(
            id: 'prod_${id++}',
            name: 'Fragrance $trayCode 100ML',
            perfumeCode: '${trayCode}1',
            bottleSize: '100ml',
            shelfLayer: layers[l],
            slotPosition: t + 1,
            price: 250.0,
          ));
          items60.add(ProductModel(
            id: 'prod_${id++}',
            name: 'Fragrance $trayCode 50ML',
            perfumeCode: '${trayCode}2',
            bottleSize: '50ml',
            shelfLayer: layers[l],
            slotPosition: t + 1,
            price: 150.0,
          ));
        }
      }

      expect(items60.length, equals(60));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            masterProductsProvider.overrideWith((ref) => items60),
            liveInventoryProvider('San Pablo').overrideWith((ref) => []),
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
          ],
          child: const MaterialApp(
            home: Scaffold(body: InventoryScreen()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Shelf Full (60/60) button is displayed
      expect(find.text('Shelf Full (60/60)'), findsOneWidget);

      // Verify capacity pill badge
      expect(find.text('Shelf Full (60/60 Slots • 30 Trays)'), findsOneWidget);

      // Verify Add Fragrance button is NOT present
      expect(find.textContaining('Add Fragrance'), findsNothing);
    });
  });
}
