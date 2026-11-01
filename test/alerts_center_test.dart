import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/alerts/alerts_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Alerts Center Overhaul & History Auditing Tests (R1)', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
    });

    test('R1: liveAlertsProvider returns unreadOnly and history provider returns readOnly', () async {
      const branch = 'San Pablo';
      final alertActive = AlertModel(
        id: 'alert_active_1',
        title: 'Low Stock Alert',
        desc: 'Low stock for AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      final alertResolved = AlertModel(
        id: 'alert_resolved_1',
        title: 'Out of Stock Alert',
        desc: 'Out of stock for AD2',
        branch: branch,
        type: 'out_of_stock',
        perfumeCode: 'AD2',
        isRead: true,
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await sqliteService.saveAlert(alertActive);
      await sqliteService.saveAlert(alertResolved);

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(container.dispose);

      final activeAlerts = await container.read(liveAlertsProvider(branch).future);
      final historyAlerts = await container.read(resolvedAlertsHistoryProvider(branch).future);

      expect(activeAlerts.length, equals(1));
      expect(activeAlerts.first.id, equals('alert_active_1'));

      expect(historyAlerts.length, equals(1));
      expect(historyAlerts.first.id, equals('alert_resolved_1'));
    });

    testWidgets('R1: AlertsScreen renders updated filter chips and eliminates legacy misplaced/quality chips', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final testAlerts = [
        AlertModel(
          id: 'a1',
          title: 'Out of Stock Alert',
          desc: '0 bottles in slot AA1',
          branch: branch,
          type: 'out_of_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        AlertModel(
          id: 'a2',
          title: 'Low Stock Alert',
          desc: '1 bottle in slot AA2',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'AA2',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        AlertModel(
          id: 'a3',
          title: 'Camera Scan Service Unavailable',
          desc: 'Failed to communicate with Camera 1',
          branch: branch,
          type: 'system',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => testAlerts),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(id: 'inv_aa1', perfumeCode: 'AA1', name: 'Perfume AA1', branch: branch, shelf: 'Shelf 1', detected: 0, recorded: 5, status: 'out_of_stock'),
              InventoryRecordModel(id: 'inv_aa2', perfumeCode: 'AA2', name: 'Perfume AA2', branch: branch, shelf: 'Shelf 1', detected: 1, recorded: 5, status: 'low'),
            ]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify updated filter chips
      expect(find.text('All Alerts'), findsOneWidget);
      expect(find.text('Out of Stock'), findsWidgets);
      expect(find.text('Low Stock'), findsWidgets);
      expect(find.text('System / Camera'), findsOneWidget);

      // Verify legacy chips are completely gone
      expect(find.text('Misplaced'), findsNothing);
      expect(find.text('Needs Verification'), findsNothing);

      // Filter by Out of Stock
      await tester.tap(find.text('Out of Stock').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsOneWidget);
      expect(find.text('Low Stock Alert'), findsNothing);
      expect(find.text('Camera Scan Service Unavailable'), findsNothing);

      // Filter by Low Stock
      await tester.tap(find.text('Low Stock').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsNothing);
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('Camera Scan Service Unavailable'), findsNothing);

      // Filter by System / Camera
      await tester.tap(find.text('System / Camera').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsNothing);
      expect(find.text('Low Stock Alert'), findsNothing);
      expect(find.text('Camera Scan Service Unavailable'), findsOneWidget);
    });

    testWidgets('R1: Active Alerts vs Resolved History toggle switches views and displays audited past alerts', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final activeAlerts = [
        AlertModel(
          id: 'act_1',
          title: 'Low Stock Alert',
          desc: 'Low stock for BA1',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'BA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      final resolvedAlerts = [
        AlertModel(
          id: 'res_1',
          title: 'Verified Restock',
          desc: 'Restock verified for BB1',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'BB1',
          isRead: true,
          createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => activeAlerts),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => resolvedAlerts),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(id: 'inv_ba1', perfumeCode: 'BA1', name: 'Perfume BA1', branch: branch, shelf: 'Shelf 1', detected: 2, recorded: 5, status: 'low'),
              InventoryRecordModel(id: 'inv_bb1', perfumeCode: 'BB1', name: 'Perfume BB1', branch: branch, shelf: 'Shelf 1', detected: 5, recorded: 5, status: 'normal'),
            ]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially on Active Alerts tab
      expect(find.text('1 ACTIVE'), findsOneWidget);
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('Acknowledge All'), findsOneWidget);
      expect(find.text('Verified Restock'), findsNothing);

      // Tap Resolved History tab
      await tester.tap(find.text('Resolved History'));
      await tester.pumpAndSettle();

      // Now viewing Resolved History
      expect(find.text('1 RESOLVED'), findsOneWidget);
      expect(find.text('Resolved Alerts & Audit History'), findsOneWidget);
      expect(find.text('Verified Restock'), findsOneWidget);
      expect(find.text('Low Stock Alert'), findsNothing);
      expect(find.text('Acknowledge All'), findsNothing);
    });

    testWidgets('R1: Live stock capacity badge is rendered on alert cards', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const branch = 'San Pablo';
      final activeAlerts = [
        AlertModel(
          id: 'stock_alert_1',
          title: 'Low Stock Alert',
          desc: 'Slot AD1 low stock',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'AD1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => activeAlerts),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => [
              InventoryRecordModel(id: 'inv_ad1', perfumeCode: 'AD1', name: 'Perfume AD1', branch: branch, shelf: 'Shelf 1', detected: 1, recorded: 5, status: 'low'),
            ]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Live stock capacity badge should be displayed
      expect(find.text('Stock: 1 / 5 Bottles'), findsOneWidget);
    });
  });
}
