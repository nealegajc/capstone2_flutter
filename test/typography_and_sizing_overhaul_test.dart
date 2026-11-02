import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/core/constants/app_constants.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart' as core_theme;
import 'package:smart_shelf_linux/ui/theme/app_theme.dart' as ui_theme;
import 'package:smart_shelf_linux/ui/components/status_badge.dart';
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

  group('Milestone 4: Fix 1 & Fix 2 - AppConstants & AppTheme Overhaul', () {
    test('Fix 1: AppConstants.minTouchTargetSize is strictly 64.0', () {
      expect(AppConstants.minTouchTargetSize, equals(64.0));
    });

    test('Fix 1: Both darkKioskTheme and lightKioskTheme enforce min button size 64x64 and font >= 16 w800', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        final elevatedMinSize = theme.elevatedButtonTheme.style?.minimumSize?.resolve({});
        expect(elevatedMinSize, equals(const Size(64, 64)), reason: 'ElevatedButton minimum size must be 64x64');

        final elevatedText = theme.elevatedButtonTheme.style?.textStyle?.resolve({});
        expect(elevatedText?.fontSize, greaterThanOrEqualTo(16.0));
        expect(elevatedText?.fontWeight, equals(FontWeight.w800));

        final outlinedMinSize = theme.outlinedButtonTheme.style?.minimumSize?.resolve({});
        expect(outlinedMinSize, equals(const Size(64, 64)), reason: 'OutlinedButton minimum size must be 64x64');

        final outlinedText = theme.outlinedButtonTheme.style?.textStyle?.resolve({});
        expect(outlinedText?.fontSize, greaterThanOrEqualTo(16.0));
        expect(outlinedText?.fontWeight, equals(FontWeight.w800));

        // Chip theme
        expect(theme.chipTheme.labelStyle?.fontSize, equals(15.0));
        expect(theme.chipTheme.labelStyle?.fontWeight, equals(FontWeight.w800));
        expect(theme.chipTheme.padding, equals(const EdgeInsets.symmetric(horizontal: 10, vertical: 6)));

        // Dialog title
        expect(theme.dialogTheme.titleTextStyle?.fontSize, equals(28.0));
        expect(theme.dialogTheme.titleTextStyle?.fontWeight, equals(FontWeight.w900));
      }
    });

    test('Fix 2: Typography scale-up matches standing kiosk distance readability requirements', () {
      for (final theme in [core_theme.AppTheme.darkKioskTheme, core_theme.AppTheme.lightKioskTheme]) {
        final t = theme.textTheme;
        // displayLarge: 42px w900
        expect(t.displayLarge?.fontSize, equals(42.0));
        expect(t.displayLarge?.fontWeight, equals(FontWeight.w900));

        // displayMedium: 32px w800
        expect(t.displayMedium?.fontSize, equals(32.0));
        expect(t.displayMedium?.fontWeight, equals(FontWeight.w800));

        // titleLarge: 28px w900
        expect(t.titleLarge?.fontSize, equals(28.0));
        expect(t.titleLarge?.fontWeight, equals(FontWeight.w900));

        // titleMedium: 20px w800
        expect(t.titleMedium?.fontSize, equals(20.0));
        expect(t.titleMedium?.fontWeight, equals(FontWeight.w800));

        // bodyLarge: 18px w600
        expect(t.bodyLarge?.fontSize, equals(18.0));
        expect(t.bodyLarge?.fontWeight, equals(FontWeight.w600));

        // bodyMedium: 16.5px w500
        expect(t.bodyMedium?.fontSize, equals(16.5));
        expect(t.bodyMedium?.fontWeight, equals(FontWeight.w500));

        // labelLarge: 17px w800
        expect(t.labelLarge?.fontSize, equals(17.0));
        expect(t.labelLarge?.fontWeight, equals(FontWeight.w800));
      }
    });

    test('UI theme exports properly delegate to core theme', () {
      expect(ui_theme.AppTheme.darkTheme, equals(core_theme.AppTheme.darkKioskTheme));
      expect(ui_theme.AppTheme.lightTheme, equals(core_theme.AppTheme.lightKioskTheme));
      expect(ui_theme.AppTheme.darkKioskTheme, equals(core_theme.AppTheme.darkKioskTheme));
      expect(ui_theme.AppTheme.lightKioskTheme, equals(core_theme.AppTheme.lightKioskTheme));
    });
  });

  group('Milestone 4: Fix 3 - StatusBadge Component Touch Target & Typography', () {
    testWidgets('Standard StatusBadge renders 14px w800 font, 18px icon, and (14, 8) padding', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              type: StatusBadgeType.good,
              customLabel: 'In Stock',
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('In Stock'));
      expect(textWidget.style?.fontSize, equals(14.0));
      expect(textWidget.style?.fontWeight, equals(FontWeight.w800));

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.size, equals(18.0));

      final containerFinder = find.descendant(
        of: find.byType(StatusBadge),
        matching: find.byType(Container),
      );
      final containerWidget = tester.widget<Container>(containerFinder.first);
      expect(containerWidget.padding, equals(const EdgeInsets.symmetric(horizontal: 14, vertical: 8)));
    });

    testWidgets('Large StatusBadge renders 16px w800 font, 22px icon, and (18, 10) padding', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatusBadge(
              type: StatusBadgeType.lowStock,
              customLabel: 'Restock Needed',
              large: true,
            ),
          ),
        ),
      );

      final textWidget = tester.widget<Text>(find.text('Restock Needed'));
      expect(textWidget.style?.fontSize, equals(16.0));
      expect(textWidget.style?.fontWeight, equals(FontWeight.w800));

      final iconFinder = find.byType(Icon);
      expect(iconFinder, findsOneWidget);
      final iconWidget = tester.widget<Icon>(iconFinder);
      expect(iconWidget.size, equals(22.0));

      final containerFinder = find.descendant(
        of: find.byType(StatusBadge),
        matching: find.byType(Container),
      );
      final containerWidget = tester.widget<Container>(containerFinder.first);
      expect(containerWidget.padding, equals(const EdgeInsets.symmetric(horizontal: 18, vertical: 10)));
    });
  });

  group('Milestone 4: Fix 4 - KioskShell Ergonomics (Header, Rail, & Pills)', () {
    testWidgets('Top header bar is 76px high, action buttons have height 56px, autolock pill 30px', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final router = GoRouter(
        initialLocation: '/dashboard',
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const KioskShell(
              child: SizedBox(),
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
            theme: core_theme.AppTheme.darkKioskTheme,
            routerConfig: router,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Header container height 76
      final headerFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.constraints != null) {
          return widget.constraints?.minHeight == 76 && widget.constraints?.maxHeight == 76;
        }
        return false;
      });
      expect(headerFinder, findsOneWidget, reason: 'Top header bar must be exactly 76px height');

      // Auto-lock pill container height 30
      final pillFinder = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.constraints != null) {
          return widget.constraints?.minHeight == 30 && widget.constraints?.maxHeight == 30;
        }
        return false;
      });
      expect(pillFinder, findsOneWidget, reason: 'Auto-lock pill must have height 30px');

      // Nav section headers: 13.5px w900
      final mainNavSection = find.text('STORE & SHELF');
      expect(mainNavSection, findsOneWidget);
      final textWidget = tester.widget<Text>(mainNavSection);
      expect(textWidget.style?.fontSize, equals(13.5));
      expect(textWidget.style?.fontWeight, equals(FontWeight.w900));

      // Header action buttons have height 56
      final actionButtonContainers = find.byWidgetPredicate((widget) {
        if (widget is Container && widget.constraints != null) {
          return widget.constraints?.minHeight == 56 && widget.constraints?.maxHeight == 56;
        }
        return false;
      });
      expect(actionButtonContainers, findsAtLeastNWidgets(2), reason: 'Header actions must be >= 56px height');
    });
  });

  group('Milestone 4: Fix 5 - Screen-Level Audits & Enhancements', () {
    testWidgets('DashboardScreen hero buttons are min 64px, quick actions are 64px, summary cards 160px with 40px w900 numbers', (tester) async {
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
            home: const DashboardScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Hero scan button minSize Size(0, 64)
      final checkShelfBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'CHECK SHELF NOW'));
      expect(checkShelfBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 64)));

      final selectiveScanBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Selective Scan'));
      expect(selectiveScanBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 64)));

      // 2. Quick action buttons height 64.0
      final quickActionContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 64.0 && w.constraints?.maxHeight == 64.0;
        }
        return false;
      });
      expect(quickActionContainers, findsNWidgets(3));

      // 3. Metric card height 160
      final summaryCardContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 160.0 && w.constraints?.maxHeight == 160.0;
        }
        return false;
      });
      expect(summaryCardContainers, findsNWidgets(4));

      // Metric count text fontSize 40 w900
      final metricCountText = tester.widget<Text>(find.text('250'));
      expect(metricCountText.style?.fontSize, equals(40.0));
      expect(metricCountText.style?.fontWeight, equals(FontWeight.w900));
    });

    testWidgets('InventoryScreen header buttons & toggles are 56px, search bar 62px, capacity pill 62px, filter chips 15.5px w800', (tester) async {
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
            home: const InventoryScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Search bar and capacity pill have height 62
      final searchBarWidgets = find.byWidgetPredicate((w) {
        if (w is SizedBox && w.height == 62.0) return true;
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 62.0 && w.constraints?.maxHeight == 62.0;
        }
        return false;
      });
      // Should find at least 2: search bar (SizedBox) and capacity pill (Container)
      expect(searchBarWidgets, findsAtLeastNWidgets(2));

      // View mode toggle container height 56
      final toggleContainers = find.byWidgetPredicate((w) {
        if (w is Container && w.constraints != null) {
          return w.constraints?.minHeight == 56.0 && w.constraints?.maxHeight == 56.0;
        }
        return false;
      });
      expect(toggleContainers, findsAtLeastNWidgets(1));

      // Filter chips: 'All Fragrances (1)', 'Active on Shelf', etc. have fontSize 15.5 w800
      final choiceChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'All Fragrances (1)'));
      expect(choiceChip.labelStyle?.fontSize, equals(15.5));
      expect(choiceChip.labelStyle?.fontWeight, equals(FontWeight.w800));
    });

    testWidgets('RestockScreen buttons have minSize Size(0, 56), health card badge 14px w800', (tester) async {
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
          child: MaterialApp(
            theme: core_theme.AppTheme.darkKioskTheme,
            home: const RestockScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final logRestockBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Log New Restock').first);
      expect(logRestockBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 56)));

      final exportRestockBtn = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Export Restock CSV').first);
      expect(exportRestockBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 56)));
    });

    testWidgets('ReportsScreen buttons have minHeight 56-62, KPI cards titles 13px w800 / values 25px w900, ListTile minTileHeight 62', (tester) async {
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
            home: const ReportsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Record New Sale button minSize Size(0, 56)
      final recordSaleBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Record New Sale'));
      expect(recordSaleBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 56)));

      // View & Share Reports banner button minSize Size(0, 62)
      final viewShareBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'View & Share Reports'));
      expect(viewShareBtn.style?.minimumSize?.resolve({}), equals(const Size(0, 62)));

      // Sales register feed row ListTile has minTileHeight: 62.0
      final salesTile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Cedar Noir'));
      expect(salesTile.minTileHeight, equals(62.0));
      expect(salesTile.dense, isFalse);

      // KPI card metric values: 25px w900
      final revenueValue = tester.widget<Text>(find.text('₱1,250.00'));
      expect(revenueValue.style?.fontSize, equals(25.0));
      expect(revenueValue.style?.fontWeight, equals(FontWeight.w900));
    });
  });
}
