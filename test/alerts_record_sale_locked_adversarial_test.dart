import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/alerts/alerts_screen.dart';
import 'package:smart_shelf_linux/ui/screens/reports/record_sale_dialog.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  late SqliteService sqliteService;
  const String branch = 'San Pablo';

  setUp(() async {
    sqliteService = SqliteService.instance;
    await sqliteService.close();
    await sqliteService.initDatabase(inMemory: true);

    // Seed test inventory record for CD1 (100ml, detected: 2)
    await sqliteService.saveInventoryRecord(InventoryRecordModel(
      id: 'inv_${branch}_CD1',
      perfumeCode: 'CD1',
      name: 'Estee Lauder Pleasures',
      branch: branch,
      shelf: 'Tray CD',
      recorded: 5,
      detected: 2,
      status: 'low',
      lastUpdated: DateTime.now(),
    ));

    // Seed test inventory record for CD2 (50ml, detected: 4)
    await sqliteService.saveInventoryRecord(InventoryRecordModel(
      id: 'inv_${branch}_CD2',
      perfumeCode: 'CD2',
      name: 'Estee Lauder Pleasures (50ml)',
      branch: branch,
      shelf: 'Tray CD',
      recorded: 5,
      detected: 4,
      status: 'normal',
      lastUpdated: DateTime.now(),
    ));
  });

  tearDown(() async {
    await sqliteService.close();
  });

  group('R1 Adversarial: RecordSaleDialog Locked Mode & Dropdown Purge', () {
    test('recordSaleWithInventoryDeduction standalone unit test', () async {
      final saleRecord = SaleRecordModel(
        id: 'sale_test_1',
        perfumeCode: 'CD1',
        productName: 'Estee Lauder Pleasures',
        bottleSize: '100ml',
        quantitySold: 2,
        unitPrice: 260.0,
        totalAmount: 520.0,
        branch: branch,
        soldBy: 'Staff',
        soldAt: DateTime.now(),
        syncStatus: 'synced',
      );
      final event = InventoryEventModel(
        id: 'evt_sale_1',
        eventType: 'REMOVED',
        productName: 'Estee Lauder Pleasures',
        perfumeCode: 'CD1',
        shelfArea: 'Tray CD',
        branch: branch,
        quantity: 2,
        timestamp: DateTime.now(),
      );

      await sqliteService.recordSaleWithInventoryDeduction(
        saleRecord: saleRecord,
        event: event,
        branch: branch,
      );

      final sales = await sqliteService.getSalesRecords(branch);
      expect(sales.length, 1);
    });

    testWidgets('R1.1 Locked modal eliminates DropdownButton and shows locked card info', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = ProductModel(
        id: 'prod_CD1',
        perfumeCode: 'CD1',
        name: 'Estee Lauder Pleasures',
        category: 'Women',
        bottleSize: '100ml',
        shelfLayer: 'Tray CD',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Scaffold(
              body: RecordSaleDialog(
                initialProduct: product,
                branch: branch,
                isLocked: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1. DropdownButton must be completely purged
      expect(find.byType(DropdownButton<ProductModel>), findsNothing);
      expect(find.text('Choose fragrance from catalog...'), findsNothing);

      // 2. Styled locked summary card components must be present
      expect(find.text('Selected Fragrance (Locked to Alert)'), findsOneWidget);
      expect(find.text('LOCKED'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      expect(find.text('CD1'), findsOneWidget);
      expect(find.text('Estee Lauder Pleasures'), findsOneWidget);
      expect(find.text('Bottle Size: 100ml'), findsOneWidget);
      expect(find.text('Unit Price: ₱260.00 / bottle'), findsOneWidget);

      // 3. Touch Stepper interactivity and dynamic price recalculation
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Confirm Sale (₱260.00)'), findsOneWidget);

      // Tap + button
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('2'), findsOneWidget);
      expect(find.text('Confirm Sale (₱520.00)'), findsOneWidget);

      // Tap - button
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1'), findsOneWidget);
      expect(find.text('Confirm Sale (₱260.00)'), findsOneWidget);
    });

    testWidgets('R1.2 Full atomic transaction: Sale recording and inventory deduction', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = ProductModel(
        id: 'prod_CD1',
        perfumeCode: 'CD1',
        name: 'Estee Lauder Pleasures',
        category: 'Women',
        bottleSize: '100ml',
        shelfLayer: 'Tray CD',
      );

      bool? dialogResult;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    dialogResult = await RecordSaleDialog.show(
                      context,
                      initialProduct: product,
                      branch: branch,
                      isLocked: true,
                    );
                  },
                  child: const Text('Open Modal'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.tap(find.text('Open Modal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Increase quantity to 2
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Confirm Sale
      await tester.tap(find.text('Confirm Sale (₱520.00)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(dialogResult, isTrue);

      // Verify SQLite state
      final sales = await sqliteService.getSalesRecords(branch);
      expect(sales.length, 1);
      expect(sales.first.perfumeCode, 'CD1');
      expect(sales.first.quantitySold, 2);
      expect(sales.first.unitPrice, 260.0);
      expect(sales.first.totalAmount, 520.0);

      final invRecords = await sqliteService.getInventoryRecords(branch);
      final inv = invRecords.where((i) => i.perfumeCode == 'CD1').firstOrNull;
      expect(inv, isNotNull);
      expect(inv!.detected, 0); // 2 - 2 = 0
      expect(inv.status, 'out_of_stock');
    });

    testWidgets('R1.3 Locked modal with null product NEVER falls back to dropdown', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: RecordSaleDialog(
                initialProduct: null,
                branch: branch,
                isLocked: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dropdown MUST NOT be rendered
      expect(find.byType(DropdownButton<ProductModel>), findsNothing);
      expect(find.text('No perfume product specified for this alert.'), findsOneWidget);

      // Confirm button must be disabled
      final button = tester.widget<ElevatedButton>(
        find.ancestor(of: find.textContaining('Confirm Sale'), matching: find.byType(ElevatedButton)),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('R1.4 Unlocked modal displays DropdownButton without LOCKED card', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockProducts = [
        ProductModel(
          id: 'p1',
          perfumeCode: 'AA1',
          name: 'Sauvage Dior',
          category: 'Men',
          bottleSize: '100ml',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            masterProductsProvider.overrideWith((ref) => mockProducts),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: const Scaffold(
              body: RecordSaleDialog(
                isLocked: false,
                branch: branch,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Select Product / SKU'), findsOneWidget);
      expect(find.byType(DropdownButton<ProductModel>), findsOneWidget);
      expect(find.text('LOCKED'), findsNothing);
    });
  });

  group('AlertsScreen Ribbon, Subtitles, and Record Sale Actions (R1-R3)', () {
    testWidgets('AlertsScreen: Log Restock ribbon button and clean subtitle branding (pure low stock has NO Record Sale)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final alert = AlertModel(
        id: 'alt_cd1_low',
        title: 'Low Stock Alert - CD1',
        desc: 'Only 2 bottles remaining on shelf',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'CD1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [alert]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify ribbon buttons are purged
      expect(find.widgetWithText(ElevatedButton, 'Log Restock'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Acknowledge All'), findsNothing);

      // Verify clean subtitle branding without branch jargon
      expect(find.textContaining('Smart Shelf Display'), findsOneWidget);
      expect(find.textContaining('Shelf Station'), findsNothing);
      expect(find.textContaining('Branch: San Pablo'), findsNothing);

      // Pure low stock alert MUST NOT render Record Sale
      expect(find.widgetWithText(ElevatedButton, 'Record Sale'), findsNothing);
    });

    testWidgets('AlertsScreen: Tapping Record Sale opens locked dialog and marks alert read on confirm', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final alert = AlertModel(
        id: 'alt_cd1_disc',
        title: 'Stock Discrepancy - CD1',
        desc: 'Camera detected 2 bottles, but ledger recorded 5',
        branch: branch,
        type: 'discrepancy',
        perfumeCode: 'CD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(alert);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [alert]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Take Action'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Unified Stock Movement Hub'), findsOneWidget);
      expect(find.text('Sale'), findsWidgets);

      // Confirm sale from hub
      await tester.tap(find.byKey(const ValueKey('submit_stock_movement_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Choose Computer Vision verification
      expect(find.byKey(const ValueKey('verification_choice_vision')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('verification_choice_vision')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.id == 'alt_cd1_disc'), isFalse);
    });

    testWidgets('AlertsScreen Edge Case: Whitespace or empty perfumeCode hides Record Sale button', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final systemAlert = AlertModel(
        id: 'alt_sys_1',
        title: 'Camera 2 Connection Lost',
        desc: 'Sensor at /dev/cam2 failed to respond',
        branch: branch,
        type: 'system',
        perfumeCode: '   ', // whitespace only
        isRead: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [systemAlert]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Record Sale button MUST NOT be rendered
      expect(find.widgetWithText(ElevatedButton, 'Record Sale'), findsNothing);
    });

    testWidgets('AlertsScreen Edge Case: Unknown perfume SKU infers correct bottle size', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 100ml unknown SKU (ends with '1')
      final alert100 = AlertModel(
        id: 'alt_xx1_disc',
        title: 'Stock Discrepancy - XX1',
        desc: 'Camera detected 1 bottle, but ledger recorded 3',
        branch: branch,
        type: 'discrepancy',
        perfumeCode: 'XX1',
        isRead: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [alert100]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Take Action'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Unified Stock Movement Hub'), findsOneWidget);
      expect(find.textContaining('XX1'), findsWidgets);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('RecordSaleDialog: Stepper bounds clamping (1 min, 50 max) and price recalculation', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final product = ProductModel(
        id: 'prod_CD1',
        perfumeCode: 'CD1',
        name: 'Estee Lauder Pleasures',
        category: 'Women',
        bottleSize: '100ml',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: RecordSaleDialog(
                initialProduct: product,
                branch: branch,
                isLocked: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Initially quantity is 1
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Confirm Sale (₱260.00)'), findsOneWidget);

      // Decrement button should be disabled (onTap is null)
      final removeFinder = find.byIcon(Icons.remove_rounded);
      await tester.tap(removeFinder);
      await tester.pump();
      // Quantity remains 1
      expect(find.text('1'), findsOneWidget);

      // Tap add 49 times to reach 50
      final addFinder = find.byIcon(Icons.add_rounded);
      for (int i = 0; i < 49; i++) {
        await tester.tap(addFinder);
      }
      await tester.pump();

      // Quantity must be 50
      expect(find.text('50'), findsOneWidget);
      expect(find.text('Confirm Sale (₱13000.00)'), findsOneWidget);

      // Attempt to increment past 50: should remain 50
      await tester.tap(addFinder);
      await tester.pump();
      expect(find.text('50'), findsOneWidget);
    });

    testWidgets('RecordSaleDialog: Null product displays ₱0.00 pricing and total', (tester) async {
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
              body: RecordSaleDialog(
                initialProduct: null,
                branch: branch,
                isLocked: true,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Unit price and total amount must be ₱0.00 when product is null
      expect(find.text('₱0.00'), findsOneWidget);
      expect(find.textContaining('Confirm Sale (₱0.00)'), findsOneWidget);
    });

    testWidgets('AlertsScreen: Whitespace-padded SKU correctly matches product and trims code', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final alertSpaced = AlertModel(
        id: 'alt_cd1_spaces',
        title: 'Stock Discrepancy - CD1',
        desc: 'Camera detected 2 bottles, but ledger recorded 5',
        branch: branch,
        type: 'discrepancy',
        perfumeCode: '  CD1  ',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(alertSpaced);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [alertSpaced]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Take Action button must be visible for trimmed code
      expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Take Action'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Must find trimmed code CD1 in Hub
      expect(find.text('Unified Stock Movement Hub'), findsOneWidget);
      expect(find.textContaining('CD1'), findsWidgets);

      // Close modal
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('R4 Surplus Discrepancy: Shows Take Action button and opens Restock tab', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Surplus: detected (4) > recorded (2)
      final surplusAlert = AlertModel(
        id: 'alt_cd2_surplus',
        title: 'Stock Discrepancy - CD2',
        desc: 'Camera detected 4 bottles, but ledger recorded 2',
        branch: branch,
        type: 'discrepancy',
        perfumeCode: 'CD2',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(surplusAlert);

      final invSurplus = InventoryRecordModel(
        id: 'inv_${branch}_CD2',
        perfumeCode: 'CD2',
        name: 'Estee Lauder Pleasures (50ml)',
        branch: branch,
        shelf: 'Tray CD',
        recorded: 2,
        detected: 4,
        status: 'needs_review',
        lastUpdated: DateTime.now(),
      );
      await sqliteService.saveInventoryRecord(invSurplus);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [surplusAlert]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => [invSurplus]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Surplus discrepancy renders consolidated Take Action button
      expect(find.widgetWithText(ElevatedButton, 'Take Action'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Record Sale'), findsNothing);

      // Tap Take Action
      await tester.tap(find.widgetWithText(ElevatedButton, 'Take Action'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Should open Hub with Restock tab pre-selected
      expect(find.text('Unified Stock Movement Hub'), findsOneWidget);
      expect(find.text('Restock'), findsWidgets);

      // Verify Restock quantity is capped to surplus delta (detected 4 - recorded 2 = 2)
      expect(find.text('2'), findsOneWidget);
      expect(find.text('(Capped to 2 added bottles)'), findsOneWidget);

      // '+' button must be disabled because quantity is already at surplus cap (2)
      final addButtonFinder = find.widgetWithIcon(IconButton, Icons.add_rounded);
      expect(tester.widget<IconButton>(addButtonFinder).onPressed, isNull);

      // Verify 'Reconcile Deficit Discrepancy' checkbox is completely purged from UI
      expect(find.text('Reconcile Deficit Discrepancy'), findsNothing);
    });

    testWidgets('R4 Alert Consolidation: Discrepancy and Low Stock merge into 1 card with secondary badge', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final discAlert = AlertModel(
        id: 'alt_cd1_disc_combo',
        title: 'Stock Discrepancy Detected',
        desc: 'Camera detected 1 bottle, but ledger recorded 4',
        branch: branch,
        type: 'discrepancy',
        perfumeCode: 'CD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      final lowAlert = AlertModel(
        id: 'alt_cd1_low_combo',
        title: 'Low Stock Alert - CD1',
        desc: 'Only 1 bottle remaining on shelf',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'CD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(discAlert);
      await sqliteService.saveAlert(lowAlert);

      final invItem = InventoryRecordModel(
        id: 'inv_${branch}_CD1',
        perfumeCode: 'CD1',
        name: 'Estee Lauder Pleasures',
        branch: branch,
        shelf: 'Tray CD',
        recorded: 4,
        detected: 1,
        status: 'low',
        lastUpdated: DateTime.now(),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            liveAlertsProvider(branch).overrideWith((ref) => [discAlert, lowAlert]),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => [invItem]),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 1 card total for active CD1 alerts (not 2 cards)
      expect(find.text('1 ACTIVE'), findsOneWidget);
      expect(find.text('Stock Discrepancy Detected'), findsOneWidget);
      expect(find.text('Low Stock Alert - CD1'), findsNothing);

      // Discrepancy primary status + Low Stock secondary badge inside the card
      expect(find.text('Discrepancy'), findsOneWidget);
      expect(find.descendant(of: find.byType(ListView), matching: find.text('Low Stock')), findsOneWidget);

      // Direct Mark as Resolved checkmark button is purged from the alert card
      final dismissBtn = find.byTooltip('Mark as Resolved');
      expect(dismissBtn, findsNothing);
    });
  });
}
