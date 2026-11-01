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
  final sampleProducts = [
    ProductModel(
      id: 'p1',
      perfumeCode: 'AA1',
      name: 'Active Amber Scent 100ml',
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
      name: 'Winter Spice (Seasonal) 50ml',
      brand: 'OttoScents',
      category: 'Men',
      shelfLayer: 'Top Shelf',
      slotPosition: 2,
      bottleSize: '50ml',
      price: 69.0,
      status: 'seasonal_off',
    ),
    ProductModel(
      id: 'p3',
      perfumeCode: 'AB1',
      name: 'Bvlgari Aqua 100ml',
      brand: 'OttoScents',
      category: 'Men',
      shelfLayer: 'Top Shelf',
      slotPosition: 1,
      bottleSize: '100ml',
      price: 110.0,
      status: 'active',
    ),
    ProductModel(
      id: 'p4',
      perfumeCode: 'CF1',
      name: 'Mimosa & Cardamom 100ml',
      brand: 'OttoScents',
      category: 'Women',
      shelfLayer: 'Bottom Shelf',
      slotPosition: 1,
      bottleSize: '100ml',
      price: 125.0,
      status: 'active',
    ),
  ];

  final sampleRecords = [
    InventoryRecordModel(
      id: 'inv_1',
      perfumeCode: 'AA1',
      name: 'Active Amber Scent 100ml',
      branch: 'San Pablo',
      shelf: 'Layer A',
      recorded: 5,
      detected: 5,
      status: 'normal',
    ),
    InventoryRecordModel(
      id: 'inv_2',
      perfumeCode: 'AA2',
      name: 'Winter Spice (Seasonal) 50ml',
      branch: 'San Pablo',
      shelf: 'Layer A',
      recorded: 5,
      detected: 0,
      status: 'seasonal_off',
    ),
    InventoryRecordModel(
      id: 'inv_3',
      perfumeCode: 'AB1',
      name: 'Bvlgari Aqua 100ml',
      branch: 'San Pablo',
      shelf: 'Layer A',
      recorded: 5,
      detected: 4,
      status: 'normal',
    ),
    InventoryRecordModel(
      id: 'inv_4',
      perfumeCode: 'CF1',
      name: 'Mimosa & Cardamom 100ml',
      branch: 'San Pablo',
      shelf: 'Layer C',
      recorded: 5,
      detected: 3,
      status: 'normal',
    ),
  ];

  Widget buildTestScope({
    ThemeData? theme,
    List<ProductModel>? products,
    List<InventoryRecordModel>? records,
  }) {
    return ProviderScope(
      overrides: [
        masterProductsProvider.overrideWith((ref) => products ?? sampleProducts),
        liveInventoryProvider('San Pablo').overrideWith((ref) => records ?? sampleRecords),
        currentBranchProvider.overrideWith((ref) => 'San Pablo'),
        liveAlertsProvider('San Pablo').overrideWith((ref) => <AlertModel>[]),
      ],
      child: MaterialApp(
        theme: theme ?? ThemeData.dark(),
        home: const CameraMonitorScreen(),
      ),
    );
  }

  group('Adversarial Challenge 1: Absence of DropdownButton and Resolution Selectors', () {
    testWidgets('Verify no DropdownButton, DropdownMenu, PopupMenuButton, or resolution switch exists anywhere in widget tree', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. Check by widget types
      expect(find.byType(DropdownButton), findsNothing, reason: 'DropdownButton must be absent');
      expect(find.byType(DropdownButtonFormField), findsNothing, reason: 'DropdownButtonFormField must be absent');
      expect(find.byType(DropdownMenu), findsNothing, reason: 'DropdownMenu must be absent');
      expect(find.byType(PopupMenuButton), findsNothing, reason: 'PopupMenuButton must be absent');

      // 2. Check for resolution selection keywords in any button
      expect(find.widgetWithText(ElevatedButton, 'Resolution'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Resolution'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Resolution'), findsNothing);
      expect(find.text('Select Resolution'), findsNothing);
      expect(find.text('Change Resolution'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 2: Absence of Pause/Resume Shelf Zone Actions', () {
    testWidgets('Verify no Pause Shelf Zone or Resume Shelf Zone button exists anywhere', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Pause Shelf Zone'), findsNothing);
      expect(find.text('Resume Shelf Zone'), findsNothing);
      expect(find.textContaining('Pause Shelf'), findsNothing);
      expect(find.textContaining('Resume Shelf'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Pause'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'Pause'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 3: Absence of Card 1 Quick Actions and Redundant Buttons', () {
    testWidgets('Verify Card 1, Quick Actions, SCAN, Adjust Grid, and redundant Cameras button are eliminated', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // No Quick Actions card
      expect(find.textContaining('Quick Actions'), findsNothing, reason: 'Card 1: Quick Actions must be removed');
      expect(find.textContaining('Card 1'), findsNothing, reason: 'Card 1 title must not exist');

      // No shelf scan buttons in camera monitor
      expect(find.textContaining('SCAN TOP'), findsNothing);
      expect(find.textContaining('SCAN MIDDLE'), findsNothing);
      expect(find.textContaining('SCAN BOTTOM'), findsNothing);
      expect(find.textContaining('SCAN SHELF'), findsNothing);
      expect(find.widgetWithText(ElevatedButton, 'SCAN'), findsNothing);

      // No redundant 'Adjust Grid' button (only 'Adjust Slot Positions' in AppBar is allowed)
      expect(find.text('Adjust Grid'), findsNothing, reason: 'Redundant Adjust Grid button must be removed');
      expect(find.widgetWithText(ElevatedButton, 'Adjust Grid'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Adjust Grid'), findsNothing);

      // No redundant 'Cameras' button (only 'Camera Settings' in AppBar is allowed)
      expect(find.widgetWithText(ElevatedButton, 'Cameras'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Cameras'), findsNothing);

      // Legitimate AppBar actions
      expect(find.text('Align Shelf Trays'), findsOneWidget);
      expect(find.text('Camera Settings'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 4: Static 2K QHD Badge Verification', () {
    testWidgets('Verify static 2K QHD badge is present in AppBar and Telemetry Header and non-interactive', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1. AppBar Badge
      final appBarBadgeText = find.text('2K QHD (2560x1440)');
      expect(appBarBadgeText, findsOneWidget);
      expect(find.byIcon(Icons.hd_rounded), findsWidgets);

      // Tapping badge should not trigger any modal or interaction
      await tester.tap(appBarBadgeText);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Dialog), findsNothing);

      // 2. Telemetry Card Header Badge
      final telemetryBadgeText = find.text('2K QHD');
      expect(telemetryBadgeText, findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 5: Main Row Flex Ratio 8:3 Verification', () {
    testWidgets('Verify main row flex ratio is strictly 8:3 (72.73% : 27.27%)', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Locate the main row containing video viewport and telemetry panel
      final rows = tester.widgetList<Row>(find.byType(Row)).toList();
      Row? mainRow;
      for (final r in rows) {
        final expandeds = r.children.whereType<Expanded>().toList();
        if (expandeds.any((e) => e.flex == 8)) {
          mainRow = r;
          break;
        }
      }

      expect(mainRow, isNotNull, reason: 'Main content Row with flex 8 must exist');
      final mainExpandeds = mainRow!.children.whereType<Expanded>().toList();
      expect(mainExpandeds.length, equals(2), reason: 'Main row must contain exactly 2 Expanded columns');

      final videoExpanded = mainExpandeds[0];
      final telemetryExpanded = mainExpandeds[1];

      expect(videoExpanded.flex, equals(8), reason: 'Left video column flex must be 8');
      expect(telemetryExpanded.flex, equals(3), reason: 'Right telemetry column flex must be 3');

      final ratio = videoExpanded.flex / telemetryExpanded.flex;
      expect(ratio, closeTo(8.0 / 3.0, 0.001));

      // Verify video expanded contains viewport and telemetry expanded contains Card
      expect(videoExpanded.child, isA<Column>());
      expect(telemetryExpanded.child, isA<Card>());

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 6: Telemetry Card Display & Overflow Stress Harness', () {
    testWidgets('Verify 1920x1200 resolution displays all telemetry metrics without RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Zero exceptions / zero overflows on 1920x1200
      expect(tester.takeException(), isNull, reason: 'Must not throw any overflow error on 1920x1200');

      // Verify Telemetry Metrics are rendered
      expect(find.text('Stream Quality'), findsOneWidget);
      expect(find.text('2560x1440 (2K Max)'), findsOneWidget);
      expect(find.text('Stream FPS'), findsOneWidget);
      expect(find.text('Camera Port'), findsOneWidget);
      expect(find.text('Shelf Level'), findsOneWidget);
      expect(find.text('Assigned Fragrances'), findsOneWidget);
      expect(find.text('Tray Capacity'), findsOneWidget);
      expect(find.text('Bottles Counted'), findsOneWidget);
      expect(find.text('Bottle Tray Slots'), findsOneWidget);
      expect(find.text('Slot Layout'), findsOneWidget);
      expect(find.text('Fragrances on this Shelf:'), findsOneWidget);

      // Verify Seasonal Off status indicator
      expect(find.text('SEASONAL / OFF (SKIPPED)'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Verify 1280x800 resolution displays telemetry without overflow', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Stream Quality'), findsOneWidget);
      expect(find.text('Stream FPS'), findsOneWidget);
      expect(find.text('Camera Port'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Verify 1024x768 touchscreen renders without RenderFlex overflows in Telemetry Row and AppBar', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final layoutErrors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        layoutErrors.add(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Telemetry metrics check (elements exist in widget tree)
      expect(find.text('Stream Quality'), findsOneWidget);
      expect(find.text('Stream FPS'), findsOneWidget);
      expect(find.text('Camera Port'), findsOneWidget);
      expect(find.text('Shelf Level'), findsOneWidget);

      FlutterError.onError = originalOnError;

      final overflowErrors = layoutErrors
          .where((e) => e.toString().contains('A RenderFlex overflowed'))
          .toList();

      expect(overflowErrors, isEmpty, reason: 'Must not have any RenderFlex overflow on 1024x768');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('Adversarial Challenge 7: Camera Switching & Device Node Stress Testing', () {
    testWidgets('Switching across all 6 shelf cameras does not trigger layout overflows at 1920x1200', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final leftRightButtons = find.byType(InkWell);
      for (final btn in leftRightButtons.evaluate()) {
        await tester.tap(find.byWidget(btn.widget).first);
        await tester.pump();
        expect(tester.takeException(), isNull);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Extremely long device node and USB port paths are constrained by Flexible and ellipsis', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final hwService = CameraHardwareService.instance;
      hwService.setCameraAssignments(
        {1: '/dev/v4l/by-path/pci-0000:00:14.0-usb-0:1.3:1.0-video-index0'},
        usbPorts: {1: 'USB-3.1-LONG-PCI-PORT-PATH-EXTENDED-PORT-8899'},
      );

      await tester.pumpWidget(buildTestScope());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'Long device node must not overflow horizontally');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Dark and Light themes render without any color or contrast assertion failures at 1920x1200', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Light theme
      await tester.pumpWidget(buildTestScope(theme: ThemeData.light()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      // Dark theme
      await tester.pumpWidget(buildTestScope(theme: ThemeData.dark()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
