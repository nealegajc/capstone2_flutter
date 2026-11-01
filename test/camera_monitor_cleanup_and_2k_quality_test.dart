import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/product_model.dart';
import 'package:smart_shelf_linux/data/services/camera_hardware_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/camera_monitor/camera_monitor_screen.dart';

void main() {
  group('Milestone 1 (R1): Camera Hardware Service 2K Max Quality & Fallback Ladder', () {
    late CameraHardwareService hardwareService;

    setUp(() {
      hardwareService = CameraHardwareService.instance;
      hardwareService.clearResolvedQualityCache();
    });

    test('1. CameraHardwareService default quality is permanently CameraQualityMode.qhd1440p (2K)', () {
      expect(hardwareService.currentQualityMode, equals(CameraQualityMode.qhd1440p));
      expect(hardwareService.currentQualityMode.resolution, equals('2560x1440'));
      expect(hardwareService.currentQualityMode.label, contains('2K QHD'));
    });

    test('2. Quality fallback ladder is strictly ordered from 2K QHD down to 480p VGA', () {
      expect(CameraHardwareService.fallbackLadder, equals([
        CameraQualityMode.qhd1440p,
        CameraQualityMode.fhd1080p,
        CameraQualityMode.hd720p,
        CameraQualityMode.vga480p,
      ]));
      expect(CameraHardwareService.fallbackLadder[0].resolution, equals('2560x1440'));
      expect(CameraHardwareService.fallbackLadder[1].resolution, equals('1920x1080'));
      expect(CameraHardwareService.fallbackLadder[2].resolution, equals('1280x720'));
      expect(CameraHardwareService.fallbackLadder[3].resolution, equals('640x480'));
    });

    test('3. Node resolution cache stores and reuses resolved quality without startup lag', () {
      const deviceA = '/dev/cam1a';
      const deviceB = '/dev/cam2a';

      expect(hardwareService.deviceResolvedQuality[deviceA], isNull);

      hardwareService.setResolvedQuality(deviceA, CameraQualityMode.fhd1080p);
      hardwareService.setResolvedQuality(deviceB, CameraQualityMode.qhd1440p);

      expect(hardwareService.deviceResolvedQuality[deviceA], equals(CameraQualityMode.fhd1080p));
      expect(hardwareService.deviceResolvedQuality[deviceB], equals(CameraQualityMode.qhd1440p));

      hardwareService.clearResolvedQualityCache();
      expect(hardwareService.deviceResolvedQuality[deviceA], isNull);
      expect(hardwareService.deviceResolvedQuality.isEmpty, isTrue);
    });

    test('4. setQualityMode updates current quality and records in resolution cache', () async {
      await hardwareService.setQualityMode(CameraQualityMode.fhd1080p);
      expect(hardwareService.currentQualityMode, equals(CameraQualityMode.fhd1080p));

      // Reset back to 2K QHD default
      await hardwareService.setQualityMode(CameraQualityMode.qhd1440p);
      expect(hardwareService.currentQualityMode, equals(CameraQualityMode.qhd1440p));
    });
  });

  group('Milestone 1 (R1): CameraMonitorScreen UI Cleanup & Viewport Maximization', () {
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

    testWidgets('1. Resolution dropdown selector is completely removed from AppBar', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      expect(find.byType(DropdownButton<CameraQualityMode>), findsNothing);
      expect(find.text('2K QHD (2560x1440)'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('2. Pause Shelf Zone button is completely removed from AppBar', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      expect(find.text('Pause Shelf Zone'), findsNothing);
      expect(find.text('Resume Shelf Zone'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('3. Redundant action buttons (SCAN, Adjust Grid, Cameras in right panel) are removed', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      // Scan button in right panel removed
      expect(find.text('SCAN TOP SHELF - LEFT SIDE'), findsNothing);
      // Redundant 'Adjust Grid' and 'Cameras' buttons removed from right column
      expect(find.text('Adjust Grid'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cameras'), findsNothing);

      // Verify the top AppBar actions remain accessible
      expect(find.text('Align Shelf Trays'), findsOneWidget);
      expect(find.text('Camera Settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('4. Video viewport flex is expanded to 8:3 ratio and telemetry panel renders clean metrics', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

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

      // Find the main Row children Expandeds
      final expandedWidgets = tester.widgetList<Expanded>(find.byType(Expanded)).toList();
      final flex8 = expandedWidgets.where((e) => e.flex == 8).toList();
      final flex3 = expandedWidgets.where((e) => e.flex == 3).toList();
      expect(flex8, isNotEmpty, reason: 'Main live camera viewport must have flex 8');
      expect(flex3, isNotEmpty, reason: 'Right telemetry panel must have flex 3');

      // Verify telemetry details
      expect(find.text('Stream Quality'), findsOneWidget);
      expect(find.text('2560x1440 (2K Max)'), findsOneWidget);
      expect(find.text('Stream FPS'), findsOneWidget);
      expect(find.text('Camera Port'), findsOneWidget);
      expect(find.text('SEASONAL / OFF (SKIPPED)'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
