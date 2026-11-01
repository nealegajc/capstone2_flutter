import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/fragrance_pick_list_dialog.dart';
import 'package:smart_shelf_linux/ui/components/low_stock_banner.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/dashboard/dashboard_screen.dart';

class _FakePythonApiRepository extends PythonApiRepository {
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
      'camera_id': cameraId ?? 1,
      'detections': [
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95, 'class': 'bottle'},
        {'roiId': 'tray_AB', 'centerX': 0.25, 'confidence': 0.95, 'class': 'bottle'},
      ],
      'bottlesDetected': 2,
    };
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Kiosk UI & Dashboard Refactor Tests (R2, R3 Acceptance Criteria)', () {
    setUp(() async {
      await SqliteService.instance.initDatabase(inMemory: true);
    });

    testWidgets('R2: Store Overview renders 4 metric cards and primary CHECK SHELF NOW button is unlocked', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testStats = DashboardStats(
        totalInStock: 250,
        lowStockCount: 3,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 300,
        activeItemCount: 60,
        outOfStockCount: 1,
        restockNeededCount: 4,
      );

      final dummyCameras = [
        const HardwareCameraDevice(deviceNode: '/dev/cam1a', name: 'Cam 1A'),
        const HardwareCameraDevice(deviceNode: '/dev/cam1b', name: 'Cam 1B'),
        const HardwareCameraDevice(deviceNode: '/dev/cam2a', name: 'Cam 2A'),
        const HardwareCameraDevice(deviceNode: '/dev/cam2b', name: 'Cam 2B'),
        const HardwareCameraDevice(deviceNode: '/dev/cam3a', name: 'Cam 3A'),
        const HardwareCameraDevice(deviceNode: '/dev/cam3b', name: 'Cam 3B'),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardStatsProvider('San Pablo').overrideWith((ref) => testStats),
            hardwareCamerasProvider.overrideWith((ref) => Stream.value(dummyCameras)),
            liveAlertsProvider('San Pablo').overrideWith((ref) => []),
            liveInventoryProvider('San Pablo').overrideWith((ref) => []),
            syncQueueListProvider('San Pablo').overrideWith((ref) => []),
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

      // 1. Verify 4 metric card titles are present on Store Overview
      expect(find.text('Total In Stock'), findsOneWidget);
      expect(find.text('Low Stock Alerts'), findsOneWidget);
      expect(find.text('Restock Needed'), findsOneWidget);
      expect(find.text('Shelf Cameras'), findsOneWidget);

      // Verify Card 1 Total In Stock displays 250 and 83% Full (250/300)
      expect(find.text('250'), findsOneWidget);
      expect(find.text('83% Full'), findsOneWidget);

      // Verify Card 2 Low Stock Alerts displays 3
      expect(find.text('3'), findsOneWidget);

      // Verify Card 3 Restock Needed displays 4 and '1 Out'
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1 Out'), findsOneWidget);

      // Verify Card 4 Shelf Cameras displays '6 / 6' and '6 / 6 Connected'
      expect(find.text('6 / 6'), findsOneWidget);
      expect(find.text('6 / 6 Connected'), findsOneWidget);

      // 2. Verify NO misplaced stat card or banner appears on Store Overview
      expect(find.text('Misplaced Bottles'), findsNothing);
      expect(find.text('Misplaced Alert'), findsNothing);
      expect(find.textContaining('Misplacement Detected'), findsNothing);

      // 3. Verify 'CHECK SHELF NOW' button is present, visible, and enabled (unlocked)
      final checkShelfButton = find.widgetWithText(ElevatedButton, 'CHECK SHELF NOW');
      expect(checkShelfButton, findsOneWidget);
      final elevatedButton = tester.widget<ElevatedButton>(checkShelfButton);
      expect(elevatedButton.enabled, isTrue, reason: 'CHECK SHELF NOW must never be disabled or locked');
    });

    testWidgets('R2: LowStockBanner activates on low/out-of-stock and displays View Details quick action', (tester) async {
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
        outOfStockCount: 1,
        restockNeededCount: 3,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardStatsProvider('San Pablo').overrideWith((ref) => testStats),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LowStockBanner(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Low Stock / Out of Stock Banner must be visible with View Details button
      expect(find.textContaining('OUT OF STOCK DETECTED: 3 Fragrances Require Refill'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
    });

    testWidgets('R2: LowStockBanner hides when all fragrances are fully stocked', (tester) async {
      const optimalStats = DashboardStats(
        totalInStock: 300,
        lowStockCount: 0,
        misplacedCount: 0,
        needsVerificationCount: 0,
        totalCapacity: 300,
        activeItemCount: 60,
        outOfStockCount: 0,
        restockNeededCount: 0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardStatsProvider('San Pablo').overrideWith((ref) => optimalStats),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  LowStockBanner(),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      // Banner should return SizedBox.shrink()
      expect(find.textContaining('LOW STOCK DETECTED'), findsNothing);
      expect(find.textContaining('OUT OF STOCK DETECTED'), findsNothing);
      expect(find.text('View Details'), findsNothing);
    });

    testWidgets('R3: FragrancePickListDialog displays 60 fragrances, search filtering, and derives cameras', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Generate 60 test inventory records: 20 per layer
      final items = <InventoryRecordModel>[];
      for (final layer in ['A', 'B', 'C']) {
        for (final slot in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'J', 'K']) {
          for (final size in ['1', '2']) {
            final code = '$layer$slot$size';
            items.add(InventoryRecordModel(
              id: 'inv_San Pablo_$code',
              perfumeCode: code,
              name: code == 'AD1' ? 'Christian Dior Sauvage (100ML)' : 'Perfume $code',
              category: layer == 'A' ? 'Men' : (layer == 'C' ? 'Women' : 'Unisex'),
              branch: 'San Pablo',
              shelf: 'Layer $layer - Slot $slot',
              recorded: 5,
              detected: code == 'AA1' ? 1 : 5,
              status: code == 'AA1' ? 'low' : 'normal',
            ));
          }
        }
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveInventoryProvider('San Pablo').overrideWith((ref) => items),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FragrancePickListDialog(branch: 'San Pablo'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify Dialog Title and Header
      expect(find.text('Fragrance Pick List & Selective Scan'), findsOneWidget);

      // Verify Tier Filter Chips
      expect(find.textContaining('All (60)'), findsOneWidget);
      expect(find.textContaining('Layer A - Top (20)'), findsOneWidget);
      expect(find.textContaining('Layer B - Mid (20)'), findsOneWidget);
      expect(find.textContaining('Layer C - Bot (20)'), findsOneWidget);

      // Verify Search Filtering
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Sauvage');
      await tester.pump();

      // Should find Dior Sauvage
      expect(find.textContaining('Sauvage'), findsWidgets);

      // Select Sauvage item checkbox
      final sauvageCheckbox = find.byType(Checkbox).first;
      await tester.tap(sauvageCheckbox);
      await tester.pump();

      // Sauvage is in Tray AD (Cam 1) -> Target Cameras: Cam 1
      expect(find.text('Cam 1'), findsOneWidget);
      expect(find.textContaining('1 Fragrances Selected'), findsOneWidget);
      expect(find.textContaining('(1 Trays)'), findsOneWidget);
    });

    testWidgets('R1: ScanWorkflowDialog shows Full Shelf Scan readiness checklist and pure YOLO metrics without misplaced stat cards', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pythonApiRepositoryProvider.overrideWithValue(_FakePythonApiRepository()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ScanWorkflowDialog(),
            ),
          ),
        ),
      );

      await tester.pump();

      // 1. In Guidance stage, verify Full Shelf Scan readiness checklist items (R1 rules) and absence of Single Tray Check
      expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
      expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);
      expect(find.text('Do Not Cover Perfume Caps or Camera Lenses'), findsOneWidget);
      expect(find.text('Upright Bottle Caps Facing Upward'), findsOneWidget);
      expect(find.text('Camera Line of Sight & Obstruction'), findsNothing);
      expect(find.text('Adequate LED Shelf Lighting'), findsNothing);
      expect(find.text('Shelf Glass Door Closed'), findsNothing);
      expect(find.text('Upright Bottle Caps & SKU Cap Stickers Facing Upward'), findsNothing);
      expect(find.text('Single Tray Check'), findsNothing);

      // 2. Verify NO misplaced bottles banner appears on guidance UI
      expect(find.textContaining('Misplacement Detected'), findsNothing);
      expect(find.textContaining('MISPLACED BOTTLES DETECTED'), findsNothing);

      // 3. Tap start button to advance through progress to completed view
      final proceedScanBtn = find.text('Start Full Shelf Scan');
      expect(proceedScanBtn, findsOneWidget);
      await tester.ensureVisible(proceedScanBtn);
      await tester.pumpAndSettle();
      await tester.tap(proceedScanBtn);
      await tester.pump();

      // Pump through scan timer duration
      for (int i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('Bottles Detected').evaluate().isNotEmpty) break;
      }

      // In completed stage, verify summary stat strip contains pure YOLO metrics
      expect(find.text('Bottles Detected'), findsOneWidget);
      expect(find.text('Low Stock'), findsOneWidget);
      expect(find.text('Shelf Status'), findsOneWidget);

      // Verify ZERO misplaced cards or banners appear on the completed UI
      expect(find.textContaining('MISPLACED BOTTLES DETECTED'), findsNothing);
      expect(find.textContaining('Misplacement Detected'), findsNothing);
      expect(find.textContaining('Misplacements'), findsNothing);

      // Cleanly unmount and drain disposal timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}

