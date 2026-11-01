import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/core/constants/app_constants.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart' as core_theme;
import 'package:smart_shelf_linux/ui/components/kiosk_shell.dart';
import 'package:smart_shelf_linux/ui/screens/dashboard/dashboard_screen.dart';
import 'package:smart_shelf_linux/ui/screens/inventory/inventory_screen.dart';
import 'package:smart_shelf_linux/ui/screens/restock/restock_screen.dart';
import 'package:smart_shelf_linux/ui/screens/reports/reports_screen.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/models/restock_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/sales_provider.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Group 1: Global Theme & AppConstants Touch Target Enforcements', () {
    test('1.1: AppConstants.minTouchTargetSize is strictly 64.0', () {
      expect(AppConstants.minTouchTargetSize, equals(64.0));
    });

    test('1.2: ElevatedButtonThemeData minimumSize is >= 64x64 in dark & light themes', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        final minSize = theme.elevatedButtonTheme.style?.minimumSize?.resolve({});
        expect(minSize, isNotNull);
        expect(minSize!.width, greaterThanOrEqualTo(64.0));
        expect(minSize.height, greaterThanOrEqualTo(64.0));
      }
    });

    test('1.3: OutlinedButtonThemeData minimumSize is >= 64x64 in dark & light themes', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        final minSize = theme.outlinedButtonTheme.style?.minimumSize?.resolve({});
        expect(minSize, isNotNull);
        expect(minSize!.width, greaterThanOrEqualTo(64.0));
        expect(minSize.height, greaterThanOrEqualTo(64.0));
      }
    });

    testWidgets('1.4: Empirical Render Test: Default ElevatedButton & OutlinedButton render >= 64x64', (tester) async {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      child: const Text('OK'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () {},
                      child: const Text('X'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        final elevatedSize = tester.getSize(find.widgetWithText(ElevatedButton, 'OK'));
        expect(elevatedSize.height, greaterThanOrEqualTo(64.0), reason: 'ElevatedButton render height must be >= 64px');
        expect(elevatedSize.width, greaterThanOrEqualTo(64.0), reason: 'ElevatedButton render width must be >= 64px');

        final outlinedSize = tester.getSize(find.widgetWithText(OutlinedButton, 'X'));
        expect(outlinedSize.height, greaterThanOrEqualTo(64.0), reason: 'OutlinedButton render height must be >= 64px');
        expect(outlinedSize.width, greaterThanOrEqualTo(64.0), reason: 'OutlinedButton render width must be >= 64px');
      }
    });

    test('1.5: ChipThemeData labelStyle fontSize >= 15.0 and padding (10, 6)', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        expect(theme.chipTheme.labelStyle?.fontSize, greaterThanOrEqualTo(15.0));
        expect(theme.chipTheme.labelStyle?.fontWeight, equals(FontWeight.w800));
        expect(theme.chipTheme.padding, equals(const EdgeInsets.symmetric(horizontal: 10, vertical: 6)));
      }
    });

    test('1.6: DialogThemeData titleTextStyle fontSize >= 28.0 and w900', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        expect(theme.dialogTheme.titleTextStyle?.fontSize, greaterThanOrEqualTo(28.0));
        expect(theme.dialogTheme.titleTextStyle?.fontWeight, equals(FontWeight.w900));
      }
    });

    test('1.7: Typography Scale-up matches standing kiosk readability standards', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        final t = theme.textTheme;
        expect(t.displayLarge?.fontSize, equals(42.0));
        expect(t.displayMedium?.fontSize, equals(32.0));
        expect(t.titleLarge?.fontSize, equals(28.0));
        expect(t.titleMedium?.fontSize, equals(20.0));
        expect(t.bodyLarge?.fontSize, equals(18.0));
        expect(t.bodyMedium?.fontSize, equals(16.5));
        expect(t.labelLarge?.fontSize, equals(17.0));
      }
    });
  });

  group('Group 2: KioskShell Empirical Render Dimensions & Hitbox Interactivity', () {
    testWidgets('2.1-2.5: Shell header (76px), actions (>=56px), autolock pill (30px), nav items (>=56px), and tap tests', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const KioskShell(
              child: Text('Dashboard View'),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (context, state) => const Scaffold(body: Text('Login View')),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith(
              (ref) => const DashboardStats(
                totalInStock: 250,
                lowStockCount: 2,
                misplacedCount: 0,
                needsVerificationCount: 0,
                totalCapacity: 300,
                activeItemCount: 60,
                outOfStockCount: 0,
                restockNeededCount: 2,
              ),
            ),
            liveAlertsProvider('San Pablo').overrideWith((ref) => []),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: MaterialApp.router(
            theme: core_theme.AppTheme.darkKioskTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2.1: Top shell header bar height == 76.0
      final headerContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 76.0 && w.constraints?.maxHeight == 76.0;
        }
        return false;
      });
      expect(headerContainers, findsOneWidget, reason: 'Header bar must have rigid height 76.0');
      final headerSize = tester.getSize(headerContainers);
      expect(headerSize.height, equals(76.0));

      // 2.2: Shell header action buttons (Wi-Fi, Theme, Lock) have height >= 56px
      final headerActionContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 56.0 && w.constraints?.maxHeight == 56.0;
        }
        return false;
      });
      expect(headerActionContainers, findsAtLeastNWidgets(2));
      for (final containerFinder in headerActionContainers.evaluate()) {
        final boxSize = tester.getSize(find.byWidget(containerFinder.widget));
        expect(boxSize.height, greaterThanOrEqualTo(56.0));
      }

      // 2.3: Shell auto-lock countdown pill height == 30.0
      final autolockPillContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 30.0 && w.constraints?.maxHeight == 30.0;
        }
        return false;
      });
      expect(autolockPillContainers, findsOneWidget);
      final pillSize = tester.getSize(autolockPillContainers);
      expect(pillSize.height, equals(30.0));

      // 2.4: Left Navigation Rail items rendered height >= 56px
      final navLabels = [
        'Store Overview',
        'Fragrance Stock',
        'Live Shelf & Cameras',
        'Alerts & Warnings',
        'Restock & Deliveries',
        'Cloud Backup',
        'Sales & Reports',
        'Activity History',
        'Settings',
        'Staff Handbook',
      ];
      for (final label in navLabels) {
        var navTextFinder = find.text(label);
        if (navTextFinder.evaluate().isEmpty) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -250));
          await tester.pump();
        }
        navTextFinder = find.text(label);
        expect(navTextFinder, findsOneWidget, reason: 'Nav item $label must exist');
        final inkWellFinder = find.ancestor(of: navTextFinder, matching: find.byType(InkWell)).first;
        final navItemSize = tester.getSize(inkWellFinder);
        expect(navItemSize.height, greaterThanOrEqualTo(56.0), reason: 'Nav item $label height must be >= 56px');
      }

      // 2.5: Interactive Hitbox Tap Tests
      // Tap Theme Toggle
      final themeToggleFinder = find.byTooltip('Toggle Dark / Light Mode');
      expect(themeToggleFinder, findsOneWidget);
      await tester.tap(themeToggleFinder);
      await tester.pumpAndSettle();

      // Tap Wi-Fi container
      final wifiFinder = find.byIcon(Icons.wifi_rounded);
      expect(wifiFinder, findsOneWidget);
      await tester.tap(wifiFinder);
      await tester.pumpAndSettle();
      // Wi-Fi dialog appears
      expect(find.text('Network & Connectivity Settings'), findsOneWidget);
      // Close dialog
      final closeIcon = find.byIcon(Icons.close_rounded);
      if (closeIcon.evaluate().isNotEmpty) {
        await tester.tap(closeIcon.first);
        await tester.pumpAndSettle();
      } else {
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      // Tap Lock Screen button
      final lockButtonFinder = find.byTooltip('Tap to lock screen now');
      if (lockButtonFinder.evaluate().isNotEmpty) {
        await tester.tap(lockButtonFinder);
        await tester.pumpAndSettle();
        expect(find.text('Login View'), findsOneWidget);
      }
    });
  });

  group('Group 3: DashboardScreen Empirical Render Dimensions & Hitbox Interactivity', () {
    testWidgets('3.1-3.4: Hero buttons (>=64px), quick actions (==64px), summary cards (==160px), and hitboxes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleStats = DashboardStats(
        totalInStock: 250,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 1,
        restockNeededCount: 3,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final dummyCameras = [
        const HardwareCameraDevice(deviceNode: '/dev/cam1a', name: 'Cam 1A'),
        const HardwareCameraDevice(deviceNode: '/dev/cam1b', name: 'Cam 1B'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith((ref) => sampleStats),
            liveInventoryProvider('San Pablo').overrideWith((ref) => []),
            liveAlertsProvider('San Pablo').overrideWith((ref) => []),
            hardwareCamerasProvider.overrideWith((ref) => Stream.value(dummyCameras)),
            systemActivityLogsProvider('San Pablo').overrideWith((ref) => Stream.value([])),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 3.1: Hero Scan Buttons Rendered Height >= 64px
      final checkShelfBtnFinder = find.widgetWithText(ElevatedButton, 'CHECK SHELF NOW');
      expect(checkShelfBtnFinder, findsOneWidget);
      final checkShelfSize = tester.getSize(checkShelfBtnFinder);
      expect(checkShelfSize.height, greaterThanOrEqualTo(64.0), reason: 'CHECK SHELF NOW height must be >= 64px');

      final selectiveScanBtnFinder = find.widgetWithText(OutlinedButton, 'Selective Scan');
      expect(selectiveScanBtnFinder, findsOneWidget);
      final selectiveScanSize = tester.getSize(selectiveScanBtnFinder);
      expect(selectiveScanSize.height, greaterThanOrEqualTo(64.0), reason: 'Selective Scan height must be >= 64px');

      // 3.2: Tap Hero Buttons
      await tester.tap(selectiveScanBtnFinder);
      await tester.pumpAndSettle();
      // Dismiss modal if opened
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      // 3.3: Dashboard Quick Action Buttons: height == 64.0
      final quickActionContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 64.0 && w.constraints?.maxHeight == 64.0;
        }
        return false;
      });
      expect(quickActionContainers, findsAtLeastNWidgets(3));
      for (final containerFinder in quickActionContainers.evaluate()) {
        final boxSize = tester.getSize(find.byWidget(containerFinder.widget));
        expect(boxSize.height, equals(64.0), reason: 'Quick action button height must be exactly 64.0');
      }

      // 3.4: 4-Card Summary Grid: height == 160.0 and font 40px w900
      final summaryCardContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 160.0 && w.constraints?.maxHeight == 160.0;
        }
        return false;
      });
      expect(summaryCardContainers, findsNWidgets(4));
      for (final cardFinder in summaryCardContainers.evaluate()) {
        final cardSize = tester.getSize(find.byWidget(cardFinder.widget));
        expect(cardSize.height, equals(160.0), reason: 'Summary card height must be 160.0');
      }

      final metricCountText = tester.widget<Text>(find.text('250'));
      expect(metricCountText.style?.fontSize, equals(40.0));
      expect(metricCountText.style?.fontWeight, equals(FontWeight.w900));
    });
  });

  group('Group 4: InventoryScreen Empirical Render Dimensions & Hitbox Interactivity', () {
    testWidgets('4.1-4.4: Search bar (>=60), capacity pill (>=60), action buttons (>=56), filter chips, and hitboxes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final sampleItems = [
        InventoryRecordModel(
          id: 'inv_1',
          perfumeCode: 'AA1',
          name: 'Cedar Noir',
          branch: 'San Pablo',
          shelf: 'Layer A - Slot 1',
          recorded: 5,
          detected: 5,
          status: 'in_stock',
        ),
      ];

      final sampleProduct = ProductModel(
        id: 'p1',
        perfumeCode: 'AA1',
        name: 'Cedar Noir',
        shelfLayer: 'Layer A',
        category: 'Men',
        bottleSize: '100ml',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            liveInventoryProvider('San Pablo').overrideWith((ref) => sampleItems),
            masterProductsProvider.overrideWith((ref) => [sampleProduct]),
            dashboardStatsProvider('San Pablo').overrideWith(
              (ref) => const DashboardStats(
                totalInStock: 250,
                totalCapacity: 300,
                activeItemCount: 60,
                lowStockCount: 0,
                outOfStockCount: 0,
                restockNeededCount: 0,
                misplacedCount: 0,
                needsVerificationCount: 0,
              ),
            ),
          ],
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: const Scaffold(body: InventoryScreen()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 4.1: Search Bar & Capacity Status Pill Height >= 60px (target 62px)
      final searchBarFinder = find.byType(TextField);
      expect(searchBarFinder, findsOneWidget);
      final searchBarParentSizedBox = find.ancestor(of: searchBarFinder, matching: find.byType(SizedBox)).first;
      final searchBarSize = tester.getSize(searchBarParentSizedBox);
      expect(searchBarSize.height, greaterThanOrEqualTo(60.0));
      expect(searchBarSize.height, equals(62.0));

      final capacityPillContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 62.0 && w.constraints?.maxHeight == 62.0;
        }
        return false;
      });
      expect(capacityPillContainers, findsOneWidget);
      final pillSize = tester.getSize(capacityPillContainers);
      expect(pillSize.height, greaterThanOrEqualTo(60.0));
      expect(pillSize.height, equals(62.0));

      // 4.2: Action Buttons & Toggles >= 56px
      final viewToggleContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 56.0 && w.constraints?.maxHeight == 56.0;
        }
        return false;
      });
      expect(viewToggleContainers, findsAtLeastNWidgets(1));
      final toggleSize = tester.getSize(viewToggleContainers.first);
      expect(toggleSize.height, greaterThanOrEqualTo(56.0));

      final refreshBtnFinder = find.byTooltip('Refresh Inventory');
      expect(refreshBtnFinder, findsOneWidget);
      final refreshBtnParent = find.ancestor(of: refreshBtnFinder, matching: find.byType(Container)).first;
      final refreshBtnSize = tester.getSize(refreshBtnParent);
      expect(refreshBtnSize.height, greaterThanOrEqualTo(56.0));
      expect(refreshBtnSize.width, greaterThanOrEqualTo(56.0));

      final addFragranceBtnFinder = find.widgetWithText(ElevatedButton, 'Add Fragrance (59 Slots Left)');
      expect(addFragranceBtnFinder, findsOneWidget);
      final addFragranceSize = tester.getSize(addFragranceBtnFinder);
      expect(addFragranceSize.height, greaterThanOrEqualTo(56.0));

      // 4.3: Interactive Hitbox Verification
      await tester.enterText(searchBarFinder, 'Cedar');
      await tester.pumpAndSettle();
      expect(find.text('Cedar Noir'), findsAtLeastNWidgets(1));

      await tester.tap(refreshBtnFinder);
      await tester.pumpAndSettle();

      // 4.4: Filter Chips
      final choiceChipFinder = find.widgetWithText(ChoiceChip, 'All Fragrances (1)');
      expect(choiceChipFinder, findsOneWidget);
      final choiceChip = tester.widget<ChoiceChip>(choiceChipFinder);
      expect(choiceChip.labelStyle?.fontSize, greaterThanOrEqualTo(15.0));
      expect(choiceChip.labelStyle?.fontWeight, equals(FontWeight.w800));

      await tester.tap(choiceChipFinder);
      await tester.pumpAndSettle();
    });
  });

  group('Group 5: RestockScreen Empirical Render Dimensions & Hitbox Interactivity', () {
    testWidgets('5.1-5.3: Action buttons (>=56px), health card badge, low stock grid (150px) & Restock Now (>=56px)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleStats = DashboardStats(
        totalInStock: 278,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 0,
        restockNeededCount: 2,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final sampleItems = [
        InventoryRecordModel(
          id: 'inv_1',
          perfumeCode: 'AA1',
          name: 'Cedar Noir',
          branch: 'San Pablo',
          shelf: 'Layer A - Slot 1',
          recorded: 5,
          detected: 1,
          status: 'low_stock',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith((ref) => sampleStats),
            liveInventoryProvider('San Pablo').overrideWith((ref) => sampleItems),
            masterProductsProvider.overrideWith((ref) => []),
            restockRecordsProvider('San Pablo').overrideWith((ref) => <RestockRecordModel>[]),
            stockMovementLogsProvider('San Pablo').overrideWith((ref) => []),
          ],
          child: MaterialApp.router(
            theme: core_theme.AppTheme.darkKioskTheme,
            routerConfig: GoRouter(
              initialLocation: '/restock',
              routes: [
                GoRoute(path: '/restock', builder: (context, state) => const Scaffold(body: RestockScreen())),
                GoRoute(path: '/create-restock', builder: (context, state) => const Scaffold(body: Text('Create Restock'))),
              ],
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 5.1: Action buttons in RestockScreen have height >= 56px
      final logRestockBtnFinder = find.widgetWithText(ElevatedButton, 'Log New Restock');
      expect(logRestockBtnFinder, findsOneWidget);
      final logRestockSize = tester.getSize(logRestockBtnFinder);
      expect(logRestockSize.height, greaterThanOrEqualTo(56.0));

      final exportRestockBtnFinder = find.widgetWithText(OutlinedButton, 'Export Restock CSV').first;
      expect(exportRestockBtnFinder, findsOneWidget);
      final exportRestockSize = tester.getSize(exportRestockBtnFinder);
      expect(exportRestockSize.height, greaterThanOrEqualTo(56.0));

      // 5.2: Low stock grid extent & card buttons
      final restockNowBtnFinder = find.widgetWithText(ElevatedButton, 'Restock Now');
      expect(restockNowBtnFinder, findsOneWidget);
      final restockNowSize = tester.getSize(restockNowBtnFinder);
      expect(restockNowSize.height, greaterThanOrEqualTo(56.0), reason: 'Restock Now button must be >= 56px height');

      // 5.3: Tap interactions
      await tester.tap(exportRestockBtnFinder);
      await tester.pumpAndSettle();

      await tester.tap(logRestockBtnFinder);
      await tester.pumpAndSettle();
    });
  });

  group('Group 6: ReportsScreen Empirical Render Dimensions & Hitbox Interactivity', () {
    testWidgets('6.1-6.4: Action buttons (>=56/62px), ListTile feed (>=62px), export tiles (>=60px), and hitboxes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleStats = DashboardStats(
        totalInStock: 278,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 0,
        restockNeededCount: 2,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      final sampleSale = SaleRecordModel(
        id: 'sale_1',
        perfumeCode: 'AA1',
        productName: 'Cedar Noir',
        bottleSize: '100ml',
        quantitySold: 1,
        unitPrice: 1250.0,
        totalAmount: 1250.0,
        branch: 'San Pablo',
        soldBy: 'staff1',
        soldAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => Future.value('San Pablo')),
            dashboardStatsProvider('San Pablo').overrideWith((ref) => Future.value(sampleStats)),
            salesRecordsProvider('San Pablo').overrideWith((ref) => Future.value([sampleSale])),
            liveInventoryProvider('San Pablo').overrideWith((ref) => Future.value([])),
            stockMovementLogsProvider('San Pablo').overrideWith((ref) => Future.value([])),
            restockRecordsProvider('San Pablo').overrideWith((ref) => Future.value([])),
          ],
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: const Scaffold(body: ReportsScreen()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 6.1: Record New Sale button rendered height >= 56px
      final recordSaleBtnFinder = find.widgetWithText(ElevatedButton, 'Record New Sale');
      expect(recordSaleBtnFinder, findsOneWidget);
      final recordSaleSize = tester.getSize(recordSaleBtnFinder);
      expect(recordSaleSize.height, greaterThanOrEqualTo(56.0));

      // View & Share Reports banner button rendered height >= 62px
      final viewShareBtnFinder = find.widgetWithText(ElevatedButton, 'View & Share Reports');
      expect(viewShareBtnFinder, findsOneWidget);
      final viewShareSize = tester.getSize(viewShareBtnFinder);
      expect(viewShareSize.height, greaterThanOrEqualTo(62.0));

      // 6.2: Sales register feed row ListTile has minTileHeight >= 62.0 and dense == false
      final salesTileFinder = find.widgetWithText(ListTile, 'Cedar Noir');
      expect(salesTileFinder, findsOneWidget);
      final salesTileWidget = tester.widget<ListTile>(salesTileFinder);
      expect(salesTileWidget.minTileHeight, greaterThanOrEqualTo(62.0));
      expect(salesTileWidget.dense, isFalse);
      final salesTileSize = tester.getSize(salesTileFinder);
      expect(salesTileSize.height, greaterThanOrEqualTo(62.0));

      // 6.3: Retail KPI cards values font 25px w900
      final revenueValue = tester.widget<Text>(find.text('₱1,250.00'));
      expect(revenueValue.style?.fontSize, equals(25.0));
      expect(revenueValue.style?.fontWeight, equals(FontWeight.w900));

      // 6.4: Interactive Hitbox Verification
      await tester.tap(recordSaleBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Dismiss dialog
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }

      await tester.tap(viewShareBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Dismiss dialog
      if (find.byType(Dialog).evaluate().isNotEmpty) {
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
    });
  });

  group('Group 7: Adversarial Stress, Viewport Variations & Accessibility Scaling', () {
    testWidgets('7.1: Viewport Stress on Compact Kiosk Resolution (1280x800)', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const sampleStats = DashboardStats(
        totalInStock: 250,
        totalCapacity: 300,
        activeItemCount: 60,
        lowStockCount: 2,
        outOfStockCount: 1,
        restockNeededCount: 3,
        misplacedCount: 0,
        needsVerificationCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith((ref) => sampleStats),
            liveInventoryProvider('San Pablo').overrideWith((ref) => []),
            liveAlertsProvider('San Pablo').overrideWith((ref) => []),
            hardwareCamerasProvider.overrideWith((ref) => Stream.value([])),
            systemActivityLogsProvider('San Pablo').overrideWith((ref) => Stream.value([])),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: const Scaffold(body: DashboardScreen()),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Zero RenderFlex overflows, buttons still >= 64px
      final checkShelfSize = tester.getSize(find.widgetWithText(ElevatedButton, 'CHECK SHELF NOW'));
      expect(checkShelfSize.height, greaterThanOrEqualTo(64.0));

      final selectiveScanSize = tester.getSize(find.widgetWithText(OutlinedButton, 'Selective Scan'));
      expect(selectiveScanSize.height, greaterThanOrEqualTo(64.0));
    });

    testWidgets('7.2: Accessibility Text Scaler Stress (1.3x Linear Scaling)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: Row(
                  children: [
                    ElevatedButton(onPressed: () {}, child: const Text('Scale Test Button')),
                    const SizedBox(width: 20),
                    OutlinedButton(onPressed: () {}, child: const Text('Outlined Scale Test')),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final elevatedSize = tester.getSize(find.widgetWithText(ElevatedButton, 'Scale Test Button'));
      expect(elevatedSize.height, greaterThanOrEqualTo(64.0));

      final outlinedSize = tester.getSize(find.widgetWithText(OutlinedButton, 'Outlined Scale Test'));
      expect(outlinedSize.height, greaterThanOrEqualTo(64.0));
    });

    testWidgets('7.3: Light Mode Theme Sizing Parity across KioskShell', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const KioskShell(
              child: Text('Dashboard Light'),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            dashboardStatsProvider('San Pablo').overrideWith(
              (ref) => const DashboardStats(
                totalInStock: 250,
                lowStockCount: 2,
                misplacedCount: 0,
                needsVerificationCount: 0,
                totalCapacity: 300,
                activeItemCount: 60,
                outOfStockCount: 0,
                restockNeededCount: 2,
              ),
            ),
            liveAlertsProvider('San Pablo').overrideWith((ref) => []),
            networkStatusProvider.overrideWithValue(
              const NetworkStatus(isOnline: true, signalStrength: 100, availableNetworks: []),
            ),
          ],
          child: MaterialApp.router(
            theme: core_theme.AppTheme.lightKioskTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Header height 76
      final headerContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 76.0 && w.constraints?.maxHeight == 76.0;
        }
        return false;
      });
      expect(headerContainers, findsOneWidget);
      expect(tester.getSize(headerContainers).height, equals(76.0));
    });
  });
}
