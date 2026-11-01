import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';

class _MockPythonApiRepository extends PythonApiRepository {
  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    await Future.delayed(const Duration(milliseconds: 50));
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

  setUp(() async {
    await SqliteService.instance.initDatabase(inMemory: true);
  });

  Widget buildTestDialog({
    bool isTargetedVerification = false,
    List<String>? targetTrayCodes,
    List<String>? targetSlotCodes,
  }) {
    return ProviderScope(
      overrides: [
        currentBranchProvider.overrideWith((ref) => 'Otto Scents Store'),
        pythonApiRepositoryProvider.overrideWithValue(_MockPythonApiRepository()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: ScanWorkflowDialog(
            isTargetedVerification: isTargetedVerification,
            targetTrayCodes: targetTrayCodes,
            targetSlotCodes: targetSlotCodes,
          ),
        ),
      ),
    );
  }

  group('Empirical Challenger: Pre-Scan Readiness Checklist & Pipeline Phrasing', () {
    testWidgets('1. Verify all 3 checklist items, icons, and info banner in Full Shelf Scan mode', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      // Info banner assertions
      expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
      expect(
        find.text('Fast bottle count scan with automatic detection for 100ML (left) and 50ML (right) shelf slots.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);

      // Checklist Title assertions
      expect(find.text('Full Shelf Scan Pre-Scan Readiness Checklist'), findsOneWidget);
      expect(find.byIcon(Icons.fact_check_rounded), findsOneWidget);

      // Item 1: Hand / bottle rule
      expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);
      expect(
        find.text('Keep hands away from shelves while scanning. Do not take or place bottles until the scan completes.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.pan_tool_rounded), findsOneWidget);

      // Item 2: Lens / cap visibility rule
      expect(find.text('Do Not Cover Perfume Caps or Camera Lenses'), findsOneWidget);
      expect(
        find.text('Ensure all bottle caps and overhead cameras are fully visible with nothing resting on top of them.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);

      // Item 3: Upright caps rule
      expect(find.text('Upright Bottle Caps Facing Upward'), findsOneWidget);
      expect(
        find.text('Ensure bottles are seated upright in tray slots with caps clean and facing overhead cameras.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.vertical_align_top_rounded), findsOneWidget);

      // Confirm complete absence of legacy strings
      expect(find.text('Camera Line of Sight & Obstruction'), findsNothing);
      expect(find.text('Adequate LED Shelf Lighting'), findsNothing);
      expect(find.text('Shelf Glass Door Closed'), findsNothing);
      expect(find.text('Upright Bottle Caps & SKU Cap Stickers Facing Upward'), findsNothing);
      expect(find.text('Single Tray Check'), findsNothing);

      // Clean unmount
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('2. Verify execution progress displays retail phrasing and all 5 pipeline phases without jargon', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestDialog());
      await tester.pumpAndSettle();

      // Tap start full shelf scan
      final startBtn = find.text('Start Full Shelf Scan');
      expect(startBtn, findsOneWidget);
      await tester.ensureVisible(startBtn);
      await tester.pumpAndSettle();
      await tester.tap(startBtn);

      // Pump single frame to transition into _ScanStage.inProgress
      await tester.pump();

      // In Progress view assertions
      expect(find.text('Automatic Bottle Count in Progress'), findsOneWidget);
      expect(find.text('AUTOMATIC BOTTLE COUNTING PIPELINE'), findsOneWidget);

      // Verify retail status message during zone scanning
      expect(find.textContaining('Scanning shelf zone'), findsOneWidget);

      // Ensure technical jargon is strictly absent
      expect(find.text('AI Vision Scan in Progress'), findsNothing);
      expect(find.text('Lockscreen watchdog paused • Processing edge models'), findsNothing);
      expect(find.text('VISION BACKEND PIPELINE PROCESS'), findsNothing);

      // Verify all 5 pipeline phases render
      expect(find.text('Camera Check: Activating camera and capturing shelf view...'), findsOneWidget);
      expect(find.text('Clarity Check: Verifying lighting and image sharpness...'), findsOneWidget);
      expect(find.text('Bottle Counter: Detecting circular bottle caps on shelf...'), findsOneWidget);
      expect(find.text('Slot Mapping: Matching bottles to 100ML and 50ML positions...'), findsOneWidget);
      expect(find.text('Inventory Sync: Updating shelf stock counts in the system...'), findsOneWidget);

      // Advance scan timer until complete
      for (int i = 0; i < 35; i++) {
        await tester.pump(const Duration(milliseconds: 250));
        if (find.text('SHELF DETECTION & STOCK SUMMARY').evaluate().isNotEmpty) break;
      }

      // Completed view assertions
      expect(find.text('SHELF DETECTION & STOCK SUMMARY'), findsOneWidget);
      expect(find.text('Shelf Bottle Count successfully completed.'), findsOneWidget);
      expect(find.textContaining('Fragrances Monitored'), findsOneWidget);
      expect(find.textContaining('SKUs Monitored'), findsNothing);
      expect(find.textContaining('Vision Scan'), findsNothing);
      expect(find.textContaining('Vision Check'), findsNothing);

      // Clean unmount and drain disposal timers
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('3. Responsive layout stress-test: no RenderFlex overflow on multiple screen constraints', (tester) async {
      final resolutions = [
        const Size(1920, 1080), // Standard 1080p kiosk
        const Size(1366, 768),  // 768p standard kiosk
        const Size(1280, 800),  // 16:10 touchscreen
        const Size(1024, 768),  // 4:3 touchscreen
        const Size(800, 600),   // Compact touchscreen
        const Size(720, 1280),  // Portrait kiosk
      ];

      for (final res in resolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Check for any layout exception in guidance stage
        expect(tester.takeException(), isNull, reason: 'Guidance overflow at resolution $res');

        // Verify key widgets are present and rendered
        expect(find.text('Full Shelf Scan Pre-Scan Readiness Checklist'), findsOneWidget);
        expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
        expect(find.byIcon(Icons.pan_tool_rounded), findsOneWidget);
        expect(find.byIcon(Icons.visibility_rounded), findsOneWidget);
        expect(find.byIcon(Icons.vertical_align_top_rounded), findsOneWidget);

        // Tap Start to verify in-progress layout also does not overflow
        final startBtn = find.text('Start Full Shelf Scan');
        await tester.ensureVisible(startBtn);
        await tester.pumpAndSettle();
        await tester.tap(startBtn);
        await tester.pump();

        expect(tester.takeException(), isNull, reason: 'In-progress overflow at resolution $res');
        expect(find.text('AUTOMATIC BOTTLE COUNTING PIPELINE'), findsOneWidget);

        // Advance to completed stage before unmounting to avoid orphaned timer exceptions
        for (int i = 0; i < 25; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (find.text('SHELF DETECTION & STOCK SUMMARY').evaluate().isNotEmpty) break;
        }

        // Verify completed stage also has zero overflow
        expect(tester.takeException(), isNull, reason: 'Completed overflow at resolution $res');

        // Unmount and drain timers cleanly
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      }

      tester.view.resetPhysicalSize();
    });

    testWidgets('4. Verify Targeted Verification and Selective Scan modes phrasing and checklist', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 4a. Targeted Verification
      await tester.pumpWidget(buildTestDialog(
        isTargetedVerification: true,
        targetSlotCodes: ['AA1'],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Targeted Shelf Verification'), findsOneWidget);
      expect(find.text('Verify that the reported scent or tray issue has been resolved.'), findsOneWidget);
      expect(find.text('I Understand, Verify Now'), findsOneWidget);
      expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);
      expect(find.text('Do Not Cover Perfume Caps or Camera Lenses'), findsOneWidget);
      expect(find.text('Upright Bottle Caps Facing Upward'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));

      // 4b. Selective Scan
      await tester.pumpWidget(buildTestDialog(
        targetTrayCodes: ['AA', 'AB'],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Selective Tray Scan Readiness'), findsOneWidget);
      expect(find.text('Review pre-scan readiness checklist for targeted shelf zones.'), findsOneWidget);
      expect(find.text('SELECTIVE SCAN: 2 TRAYS TARGETED'), findsOneWidget);
      expect(find.text('Start Selective Scan'), findsOneWidget);
      expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
      expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
