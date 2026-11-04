import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/data/services/camera_hardware_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/alerts/alerts_screen.dart';

class MockPythonApiRepository extends PythonApiRepository {
  final Future<Map<String, dynamic>> Function({int? cameraId, String? targetTray}) onScan;
  MockPythonApiRepository({required this.onScan});

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    return onScan(cameraId: cameraId, targetTray: targetTray);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Challenger 1 Empirical Stress Tests: R1 & R2', () {
    late SqliteService sqliteService;
    const branch = 'San Pablo';

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      final db = await sqliteService.database;
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('restock_records');
      await db.delete('inventory_events');
      await db.delete('system_logs');
    });

    // -------------------------------------------------------------------------
    // Challenge 1: Targeted Slot Isolation & Non-Interference
    // -------------------------------------------------------------------------
    test('Empirical Challenge: Sister slot bottles on same tray DO NOT satisfy target slot verification', () async {
      // Slot AD1 has 0 bottles. Sister slot AD2 on the SAME tray AD has 5 bottles.
      // Total bottles on tray AD = 5 bottles.
      // Verify that AD1 detected count is strictly 0 and fails threshold check (0 < 3).
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 0,
        status: 'out_of_stock',
      ));
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD2',
        perfumeCode: 'AD2',
        name: 'Sauvage 50ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      final countAD1 = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
      final countAD2 = await sqliteService.getDetectedCountForSlot('AD2', branch: branch);

      expect(countAD1, 0, reason: 'Target slot AD1 must be exactly 0');
      expect(countAD2, 5, reason: 'Sister slot AD2 must be 5');
      expect(countAD1 >= 3, isFalse, reason: 'Target slot AD1 must NOT pass threshold >= 3');

      final deficit = 3 - countAD1;
      final shortfall = 5 - countAD1;
      expect(deficit, 3, reason: 'Deficit for 0 bottles must be exactly 3');
      expect(shortfall, 5, reason: 'Shortfall to full capacity (5) must be 5');
    });

    test('Empirical Challenge: Camera-wide bottle count does NOT satisfy target slot verification', () async {
      // Camera 1 hosts Tray AA, AB, AC, AD, AE (10 slots).
      // Suppose other slots have 25 bottles in total, but target AD1 has only 1 bottle.
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));
      // Other slot on Camera 1
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AA1',
        perfumeCode: 'AA1',
        name: 'Perfume AA1',
        branch: branch,
        shelf: 'Tray AA',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      final countAD1 = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
      expect(countAD1, 1);
      expect(countAD1 >= 3, isFalse);
      expect(3 - countAD1, 2, reason: 'Deficit to threshold must be 2');
      expect(5 - countAD1, 4, reason: 'Shortfall to capacity must be 4');
    });

    // -------------------------------------------------------------------------
    // Challenge 2: Boundary Values for Deficit & Auto-Resolution (0, 1, 2 vs 3, 4, 5)
    // -------------------------------------------------------------------------
    test('Empirical Challenge: Boundary values 0, 1, 2 must fail verification with exact deficits', () async {
      for (int count = 0; count <= 2; count++) {
        await sqliteService.saveInventoryRecord(InventoryRecordModel(
          id: 'inv_${branch}_AD1',
          perfumeCode: 'AD1',
          name: 'Sauvage 100ML',
          branch: branch,
          shelf: 'Tray AD',
          recorded: 5,
          detected: count,
          status: count == 0 ? 'out_of_stock' : 'low',
        ));

        final detected = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
        expect(detected, count);
        expect(detected >= 3, isFalse, reason: 'Count $count must NOT auto-resolve');

        final deficit = 3 - detected;
        final capacityMissing = 5 - detected;
        expect(deficit, 3 - count, reason: 'Deficit for $count must be ${3 - count}');
        expect(capacityMissing, 5 - count, reason: 'Capacity shortfall for $count must be ${5 - count}');
      }
    });

    test('Empirical Challenge: Boundary values 3, 4, 5 must satisfy threshold and auto-resolve', () async {
      for (int count = 3; count <= 5; count++) {
        await sqliteService.saveInventoryRecord(InventoryRecordModel(
          id: 'inv_${branch}_AD1',
          perfumeCode: 'AD1',
          name: 'Sauvage 100ML',
          branch: branch,
          shelf: 'Tray AD',
          recorded: 5,
          detected: count,
          status: 'normal',
        ));

        final detected = await sqliteService.getDetectedCountForSlot('AD1', branch: branch);
        expect(detected, count);
        expect(detected >= 3, isTrue, reason: 'Count $count MUST auto-resolve');
      }
    });

    // -------------------------------------------------------------------------
    // Challenge 3: Full ScanWorkflowDialog Execution & Boundary Status Messages
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: ScanWorkflowDialog boundary count = 1 shows deficit message and keeps alert unread', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      // Seed inventory with 1 bottle for AD1
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      // Mock Python API returning 1 bottle detection for Tray AD
      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': true,
          'totalBottles': 1,
          'trayCounts': {'tray_AD': 1},
          'detections': [
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.50, 'bbox': [0.65, 0.45, 0.75, 0.55]}
          ],
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('I Understand, Verify Now'), findsOneWidget);

      // Tap verify
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Verification should be incomplete because 1 < 3
      expect(find.text('Verification Incomplete'), findsOneWidget);
      expect(find.textContaining('Deficit: 2 more needed for threshold, 4 to full capacity'), findsOneWidget);

      // Alert must remain active in SQLite
      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.perfumeCode == 'AD1'), isTrue, reason: 'AD1 alert must remain active/unread');
    });

    testWidgets('Empirical Challenge: ScanWorkflowDialog boundary count = 3 shows success message and marks alert read', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      // Seed initial low-stock inventory record for AD1
      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      // Mock Python API returning 3 bottles detection for Tray AD (left column AD1 < 0.7584)
      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': true,
          'totalBottles': 3,
          'trayCounts': {'tray_AD': 3},
          'detections': [
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.30, 'bbox': [0.65, 0.25, 0.75, 0.35]},
            {'roiId': 'tray_AD', 'centerX': 0.71, 'centerY': 0.50, 'bbox': [0.66, 0.45, 0.76, 0.55]},
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.70, 'bbox': [0.65, 0.65, 0.75, 0.75]},
          ],
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Verification should succeed at count = 3
      expect(find.text('Scan Completed Successfully'), findsOneWidget);
      expect(find.textContaining('Restock Verified!'), findsOneWidget);
      expect(find.textContaining('3 / 5 bottles'), findsOneWidget);

      // Verify no active unread alert for AD1
      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.perfumeCode == 'AD1'), isFalse, reason: 'Active alert for AD1 must be cleared');

      await tester.pump(const Duration(milliseconds: 350));
    });

    // -------------------------------------------------------------------------
    // Challenge 4: Camera Failure Fallback System Alert Logging
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: Camera failure during targeted verification logs a system alert to SQLite', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_low',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      // Mock Python API failing
      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': false,
          'message': 'Failed to connect to edge camera sensor /dev/cam1a',
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Dialog should report failure
      expect(find.text('Verification Incomplete'), findsOneWidget);
      expect(find.textContaining('Shelf scan failed: Unable to connect to camera system.'), findsOneWidget);

      // Verify SQLite has a system alert recorded
      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      final systemAlerts = unreadAlerts.where((a) => a.type == 'system').toList();
      expect(systemAlerts.isNotEmpty, isTrue, reason: 'A system alert must be persisted');
      expect(systemAlerts.first.title, 'Camera Scan Service Unavailable');
      expect(systemAlerts.first.desc, contains('Camera(s): 1'));
      expect(systemAlerts.first.desc, contains('Tray AD (AD1)'));

      // Original stock alert must still be unread
      final stockAlert = unreadAlerts.firstWhere((a) => a.id == 'alert_ad1_low');
      expect(stockAlert.isRead, isFalse);
    });

    // -------------------------------------------------------------------------
    // Challenge 5: Alerts Screen Filter Chips Strict Isolation & Dynamic Capacity Badges
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: Filter chips strictly isolate out_of_stock, low_stock, and system', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testAlerts = [
        AlertModel(
          id: 'alt_oos',
          title: 'Out of Stock Alert',
          desc: '0 bottles in slot AA1',
          branch: branch,
          type: 'out_of_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        AlertModel(
          id: 'alt_low',
          title: 'Low Stock Alert',
          desc: '2 bottles in slot AA2',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'AA2',
          isRead: false,
          createdAt: DateTime.now(),
        ),
        AlertModel(
          id: 'alt_sys',
          title: 'Camera Scan Service Unavailable',
          desc: 'Failed to communicate with Camera 2',
          branch: branch,
          type: 'system',
          perfumeCode: '',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      final inventory = [
        InventoryRecordModel(id: 'inv_aa1', perfumeCode: 'AA1', name: 'Perfume AA1', branch: branch, shelf: 'Shelf 1', detected: 0, recorded: 5, status: 'out_of_stock'),
        InventoryRecordModel(id: 'inv_aa2', perfumeCode: 'AA2', name: 'Perfume AA2', branch: branch, shelf: 'Shelf 1', detected: 2, recorded: 5, status: 'low'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => testAlerts),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => inventory),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check capacity badges rendered
      expect(find.text('Stock: 0 / 5 Bottles'), findsOneWidget);
      expect(find.text('Stock: 2 / 5 Bottles'), findsOneWidget);

      // 1. Out of stock filter: ONLY alt_oos visible
      await tester.tap(find.text('Out of Stock').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsOneWidget);
      expect(find.text('Low Stock Alert'), findsNothing);
      expect(find.text('Camera Scan Service Unavailable'), findsNothing);

      // 2. Low stock filter: ONLY alt_low visible
      await tester.tap(find.text('Low Stock').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsNothing);
      expect(find.text('Low Stock Alert'), findsOneWidget);
      expect(find.text('Camera Scan Service Unavailable'), findsNothing);

      // 3. System filter: ONLY alt_sys visible
      await tester.tap(find.text('System / Anomaly').first);
      await tester.pumpAndSettle();
      expect(find.text('Out of Stock Alert'), findsNothing);
      expect(find.text('Low Stock Alert'), findsNothing);
      expect(find.text('Camera Scan Service Unavailable'), findsOneWidget);
    });

    testWidgets('Empirical Challenge: Capacity badge dynamically updates when live inventory state changes', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testAlerts = [
        AlertModel(
          id: 'alt_low',
          title: 'Low Stock Alert',
          desc: '1 bottle in slot AA2',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'AA2',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      final invState = StateProvider<List<InventoryRecordModel>>((ref) => [
        InventoryRecordModel(id: 'inv_aa2', perfumeCode: 'AA2', name: 'Perfume AA2', branch: branch, shelf: 'Shelf 1', detected: 1, recorded: 5, status: 'low'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => testAlerts),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => []),
            liveInventoryProvider(branch).overrideWith((ref) => ref.watch(invState)),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Stock: 1 / 5 Bottles'), findsOneWidget);

      // Now update inventory to 4 bottles
      final element = tester.element(find.byType(AlertsScreen));
      final container = ProviderScope.containerOf(element);
      container.read(invState.notifier).state = [
        InventoryRecordModel(id: 'inv_aa2', perfumeCode: 'AA2', name: 'Perfume AA2', branch: branch, shelf: 'Shelf 1', detected: 4, recorded: 5, status: 'normal'),
      ];

      await tester.pumpAndSettle();
      expect(find.text('Stock: 4 / 5 Bottles'), findsOneWidget);
      expect(find.text('Stock: 1 / 5 Bottles'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // Challenge 6: Boundary Values count = 2 and count = 5 in ScanWorkflowDialog
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: Boundary count = 2 in ScanWorkflowDialog shows exact deficit 1 and capacity shortfall 3', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_low_2',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 2,
        status: 'low',
      ));

      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': true,
          'totalBottles': 2,
          'trayCounts': {'tray_AD': 2},
          'detections': [
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.30, 'bbox': [0.65, 0.25, 0.75, 0.35]},
            {'roiId': 'tray_AD', 'centerX': 0.71, 'centerY': 0.50, 'bbox': [0.66, 0.45, 0.76, 0.55]},
          ],
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('Verification Incomplete'), findsOneWidget);
      expect(find.textContaining('Deficit: 1 more needed for threshold, 3 to full capacity'), findsOneWidget);

      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.perfumeCode == 'AD1'), isTrue, reason: 'Alert must remain active when count = 2');

      await tester.pump(const Duration(milliseconds: 350));
    });

    testWidgets('Empirical Challenge: Boundary count = 5 (Full Capacity) in ScanWorkflowDialog succeeds and resolves alert', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_low_5',
        title: 'Low Stock Alert',
        desc: 'Low stock on AD1',
        branch: branch,
        type: 'low_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 1,
        status: 'low',
      ));

      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': true,
          'totalBottles': 5,
          'trayCounts': {'tray_AD': 5},
          'detections': [
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.20, 'bbox': [0.65, 0.15, 0.75, 0.25]},
            {'roiId': 'tray_AD', 'centerX': 0.71, 'centerY': 0.35, 'bbox': [0.66, 0.30, 0.76, 0.40]},
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.50, 'bbox': [0.65, 0.45, 0.75, 0.55]},
            {'roiId': 'tray_AD', 'centerX': 0.71, 'centerY': 0.65, 'bbox': [0.66, 0.60, 0.76, 0.70]},
            {'roiId': 'tray_AD', 'centerX': 0.70, 'centerY': 0.80, 'bbox': [0.65, 0.75, 0.75, 0.85]},
          ],
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.text('Scan Completed Successfully'), findsOneWidget);
      expect(find.textContaining('Restock Verified!'), findsOneWidget);
      expect(find.textContaining('5 / 5 bottles'), findsOneWidget);

      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.perfumeCode == 'AD1'), isFalse, reason: 'Alert must be auto-resolved when count = 5');

      await tester.pump(const Duration(milliseconds: 350));
    });

    // -------------------------------------------------------------------------
    // Challenge 7: Sister Slot UI Isolation in ScanWorkflowDialog
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: In ScanWorkflowDialog, AD2 having 5 bottles does NOT satisfy AD1 verification', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeAlert = AlertModel(
        id: 'alert_ad1_isolation',
        title: 'Out of Stock Alert',
        desc: '0 bottles in slot AD1',
        branch: branch,
        type: 'out_of_stock',
        perfumeCode: 'AD1',
        isRead: false,
        createdAt: DateTime.now(),
      );
      await sqliteService.saveAlert(activeAlert);

      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD1',
        perfumeCode: 'AD1',
        name: 'Sauvage 100ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 0,
        status: 'out_of_stock',
      ));

      await sqliteService.saveInventoryRecord(InventoryRecordModel(
        id: 'inv_${branch}_AD2',
        perfumeCode: 'AD2',
        name: 'Sauvage 50ML',
        branch: branch,
        shelf: 'Tray AD',
        recorded: 5,
        detected: 5,
        status: 'normal',
      ));

      // 5 bottles detected strictly in RIGHT column (AD2, centerX >= 0.7584, e.g. 0.80)
      final mockApi = MockPythonApiRepository(onScan: ({cameraId, targetTray}) async {
        return {
          'success': true,
          'totalBottles': 5,
          'trayCounts': {'tray_AD': 5},
          'detections': [
            {'roiId': 'tray_AD', 'centerX': 0.80, 'centerY': 0.20, 'bbox': [0.75, 0.15, 0.85, 0.25]},
            {'roiId': 'tray_AD', 'centerX': 0.80, 'centerY': 0.35, 'bbox': [0.75, 0.30, 0.85, 0.40]},
            {'roiId': 'tray_AD', 'centerX': 0.80, 'centerY': 0.50, 'bbox': [0.75, 0.45, 0.85, 0.55]},
            {'roiId': 'tray_AD', 'centerX': 0.80, 'centerY': 0.65, 'bbox': [0.75, 0.60, 0.85, 0.70]},
            {'roiId': 'tray_AD', 'centerX': 0.80, 'centerY': 0.80, 'bbox': [0.75, 0.75, 0.85, 0.85]},
          ],
        };
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sqliteServiceProvider.overrideWithValue(sqliteService),
            pythonApiRepositoryProvider.overrideWithValue(mockApi),
            cameraHardwareServiceProvider.overrideWith((ref) => CameraHardwareService.instance),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(
                isTargetedVerification: true,
                targetAlert: activeAlert,
                targetSlotCodes: const ['AD1'],
                targetTrayCodes: const ['AD'],
                initialCameraId: 1,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      await tester.tap(find.text('I Understand, Verify Now'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      // Must fail because AD1 has 0 bottles (even though AD2 and entire tray has 5 bottles!)
      expect(find.text('Verification Incomplete'), findsOneWidget);
      expect(find.textContaining('only 0 bottle(s) detected'), findsOneWidget);
      expect(find.textContaining('Deficit: 3 more needed for threshold, 5 to full capacity'), findsOneWidget);

      final unreadAlerts = await sqliteService.getAlerts(branch, unreadOnly: true);
      expect(unreadAlerts.any((a) => a.perfumeCode == 'AD1'), isTrue, reason: 'AD1 alert must NOT be cleared by AD2 bottles');

      await tester.pump(const Duration(milliseconds: 350));
    });

    // -------------------------------------------------------------------------
    // Challenge 8: Active Alerts vs Resolved History Toggle & Audit Integrity
    // -------------------------------------------------------------------------
    testWidgets('Empirical Challenge: Active Alerts vs Resolved History toggle correctly audits acknowledged incidents', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final activeList = [
        AlertModel(
          id: 'alt_active_1',
          title: 'Out of Stock Alert - AA1',
          desc: '0 bottles remaining',
          branch: branch,
          type: 'out_of_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        ),
      ];

      final historyList = [
        AlertModel(
          id: 'alt_hist_1',
          title: 'Resolved Low Stock Alert - BB1',
          desc: 'Restock verified 5 / 5 bottles',
          branch: branch,
          type: 'low_stock',
          perfumeCode: 'BB1',
          isRead: true,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveAlertsProvider(branch).overrideWith((ref) => activeList),
            resolvedAlertsHistoryProvider(branch).overrideWith((ref) => historyList),
            liveInventoryProvider(branch).overrideWith((ref) => []),
          ],
          child: const MaterialApp(
            home: AlertsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // In Active view:
      expect(find.text('1 ACTIVE'), findsOneWidget);
      expect(find.text('Out of Stock Alert - AA1'), findsOneWidget);
      expect(find.text('Resolved Low Stock Alert - BB1'), findsNothing);
      expect(find.text('Acknowledge All'), findsNothing);

      // Switch to Resolved History view:
      await tester.tap(find.text('Resolved History'));
      await tester.pumpAndSettle();

      expect(find.text('1 RESOLVED'), findsOneWidget);
      expect(find.text('Resolved Low Stock Alert - BB1'), findsOneWidget);
      expect(find.text('Out of Stock Alert - AA1'), findsNothing);
      expect(find.text('Resolved'), findsOneWidget); // Status badge
      expect(find.text('Acknowledge All'), findsNothing);
    });
  });
}
