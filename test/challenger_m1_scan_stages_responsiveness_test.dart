import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/repositories/python_api_repository.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart';

class _MockSuccessPythonApiRepository extends PythonApiRepository {
  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    // Simulate camera hardware inference time so inProgress state can be sampled
    await Future.delayed(const Duration(milliseconds: 500));
    return {
      'success': true,
      'camera_id': cameraId ?? 1,
      'detections': [
        {'roiId': 'tray_AA', 'centerX': 0.05, 'confidence': 0.95, 'class': 'bottle'},
        {'roiId': 'tray_AA', 'centerX': 0.55, 'confidence': 0.95, 'class': 'bottle'},
        {'roiId': 'tray_AB', 'centerX': 0.25, 'confidence': 0.95, 'class': 'bottle'},
      ],
      'bottlesDetected': 3,
    };
  }
}

class _MockFailurePythonApiRepository extends PythonApiRepository {
  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    return {
      'success': false,
      'message': 'Hardware camera device not responding',
      'camera_id': cameraId ?? 1,
      'detections': [],
      'bottlesDetected': 0,
    };
  }
}

class _MockExceptionPythonApiRepository extends PythonApiRepository {
  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    await Future.delayed(const Duration(milliseconds: 100));
    throw Exception('Socket connection timeout to backend');
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  const kioskResolutions = [
    Size(1920, 1080), // Standard Full HD 16:9 kiosk
    Size(1920, 1200), // WUXGA 16:10 kiosk
  ];

  for (final resolution in kioskResolutions) {
    final resLabel = '${resolution.width.toInt()}x${resolution.height.toInt()}';

    group('ScanWorkflowDialog Challenge — $resLabel Geometry', () {
      setUp(() async {
        await SqliteService.instance.initDatabase(inMemory: true);
        final db = await SqliteService.instance.database;
        await db.delete('alerts');
        await db.delete('inventory_records');
      });

      testWidgets('Full Shelf Scan: transitions guidance -> scanning -> results cleanly', (tester) async {
        tester.view.physicalSize = resolution;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pythonApiRepositoryProvider.overrideWithValue(_MockSuccessPythonApiRepository()),
              currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(),
              ),
            ),
          ),
        );

        await tester.pump();

        // 1. STAGE: GUIDANCE
        expect(find.text('Full Shelf Scan Readiness'), findsOneWidget);
        expect(find.text('Review pre-scan readiness checklist before initiating full shelf scan.'), findsOneWidget);
        expect(find.text('Instant Automatic Bottle Counter'), findsOneWidget);
        expect(find.text('Full Shelf Scan Pre-Scan Readiness Checklist'), findsOneWidget);

        // Checklist Retail Phrasing assertions
        expect(find.text('Do Not Remove or Restock Bottles During Scan'), findsOneWidget);
        expect(find.text('Keep hands away from shelves while scanning. Do not take or place bottles until the scan completes.'), findsOneWidget);
        expect(find.text('Do Not Cover Perfume Caps or Camera Lenses'), findsOneWidget);
        expect(find.text('Ensure all bottle caps and overhead cameras are fully visible with nothing resting on top of them.'), findsOneWidget);
        expect(find.text('Upright Bottle Caps Facing Upward'), findsOneWidget);
        expect(find.text('Ensure bottles are seated upright in tray slots with caps clean and facing overhead cameras.'), findsOneWidget);

        // Confirm technical jargon elimination
        expect(find.textContaining('OCR'), findsNothing);
        expect(find.textContaining('YOLO'), findsNothing);
        expect(find.textContaining('Bounding Box'), findsNothing);
        expect(find.textContaining('Line of Sight'), findsNothing);
        expect(find.textContaining('Adequate LED'), findsNothing);
        expect(find.textContaining('Glass Door'), findsNothing);

        // Verify start button
        final startBtn = find.text('Start Full Shelf Scan');
        expect(startBtn, findsOneWidget);
        await tester.ensureVisible(startBtn);
        await tester.tap(startBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // 2. STAGE: SCANNING (inProgress)
        expect(find.text('Automatic Bottle Count in Progress'), findsOneWidget);
        expect(find.text('AUTOMATIC BOTTLE COUNTING PIPELINE'), findsOneWidget);
        expect(find.text('Camera Check: Activating camera and capturing shelf view...'), findsOneWidget);
        expect(find.text('Clarity Check: Verifying lighting and image sharpness...'), findsOneWidget);
        expect(find.text('Bottle Counter: Detecting circular bottle caps on shelf...'), findsOneWidget);
        expect(find.text('Slot Mapping: Matching bottles to 100ML and 50ML positions...'), findsOneWidget);
        expect(find.text('Inventory Sync: Updating shelf stock counts in the system...'), findsOneWidget);

        // Verify no uncaught exceptions during progress
        expect(tester.takeException(), isNull);

        // Advance through all 6 cameras with delayed network response
        for (int i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (find.text('Scan Completed Successfully').evaluate().isNotEmpty) break;
        }

        // 3. STAGE: RESULTS (completed)
        expect(find.text('Scan Completed Successfully'), findsOneWidget);
        expect(find.text('Bottles Detected'), findsOneWidget);
        expect(find.text('Low Stock'), findsOneWidget);
        expect(find.text('Shelf Status'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);

        // Ensure no layout overflow or unhandled exceptions
        expect(tester.takeException(), isNull);

        // Drain dialog
        await tester.tap(find.text('Done'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets('Targeted Verification (verifying): guidance -> scanning -> results (both success and fail)', (tester) async {
        tester.view.physicalSize = resolution;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Prepopulate SQLite with slot AA1 having 1 bottle (below threshold 3)
        final alert = AlertModel(
          id: 'alert_low_aa1',
          title: 'Low Stock Alert',
          desc: 'Stock level critical on slot AA1 (1 bottle remaining)',
          branch: 'San Pablo',
          type: 'low_stock',
          perfumeCode: 'AA1',
          isRead: false,
          createdAt: DateTime.now(),
        );
        await SqliteService.instance.saveAlert(alert);

        final initialRec = InventoryRecordModel(
          id: 'inv_aa1',
          perfumeCode: 'AA1',
          name: 'Sauvage Elixir',
          branch: 'San Pablo',
          shelf: 'Tray AA',
          recorded: 5,
          detected: 1,
          status: 'low',
        );
        await SqliteService.instance.saveInventoryRecord(initialRec);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pythonApiRepositoryProvider.overrideWithValue(_MockSuccessPythonApiRepository()),
              currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(
                  isTargetedVerification: true,
                  targetAlert: alert,
                  targetSlotCodes: const ['AA1'],
                  targetTrayCodes: const ['AA'],
                  initialCameraId: 1,
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // 1. GUIDANCE STAGE (Targeted Verification)
        expect(find.text('Targeted Shelf Verification'), findsOneWidget);
        expect(find.text('Verify that the reported scent or tray issue has been resolved.'), findsOneWidget);
        expect(find.textContaining('TARGETED TRAY: Tray AA'), findsOneWidget);
        expect(find.text('Camera 1'), findsOneWidget);
        final verifyBtn = find.text('I Understand, Verify Now');
        expect(verifyBtn, findsOneWidget);

        // 2. SCANNING STAGE
        await tester.ensureVisible(verifyBtn);
        await tester.tap(verifyBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Automatic Bottle Count in Progress'), findsOneWidget);
        expect(find.text('AUTOMATIC BOTTLE COUNTING PIPELINE'), findsOneWidget);

        // Advance through progress timer
        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (find.text('Done').evaluate().isNotEmpty) break;
        }

        // 3. RESULTS / VERIFYING STAGE
        expect(find.text('Done'), findsOneWidget);
        expect(find.textContaining('TRAY AA PERFUME BREAKDOWN'), findsOneWidget);
        expect(find.text('100ML Column'), findsOneWidget);
        expect(find.text('50ML Column'), findsOneWidget);

        expect(tester.takeException(), isNull);

        // Drain dialog
        await tester.tap(find.text('Done'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets('Selective Scan: 30 trays load test and layout responsiveness', (tester) async {
        tester.view.physicalSize = resolution;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Extreme stress case: all 30 trays selected in selective scan
        final all30Trays = [
          'AA', 'AB', 'AC', 'AD', 'AE', 'AF', 'AG', 'AH', 'AJ', 'AK',
          'BA', 'BB', 'BC', 'BD', 'BE', 'BF', 'BG', 'BH', 'BJ', 'BK',
          'CA', 'CB', 'CC', 'CD', 'CE', 'CF', 'CG', 'CH', 'CJ', 'CK',
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pythonApiRepositoryProvider.overrideWithValue(_MockSuccessPythonApiRepository()),
              currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(
                  isTargetedVerification: false,
                  targetTrayCodes: all30Trays,
                  targetCameraIds: const [1, 2, 3, 4, 5, 6],
                ),
              ),
            ),
          ),
        );

        await tester.pump();

        // Check Selective Guidance View
        expect(find.text('Selective Tray Scan Readiness'), findsOneWidget);
        expect(find.text('SELECTIVE SCAN: 30 TRAYS TARGETED'), findsOneWidget);
        expect(find.textContaining('Targeted Trays: AA, AB, AC'), findsOneWidget);
        expect(find.textContaining('Derived Cameras: Cam 1, Cam 2, Cam 3, Cam 4, Cam 5, Cam 6'), findsOneWidget);
        final startSelBtn = find.text('Start Selective Scan');
        expect(startSelBtn, findsOneWidget);

        // Tap start
        await tester.ensureVisible(startSelBtn);
        await tester.tap(startSelBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Automatic Bottle Count in Progress'), findsOneWidget);

        for (int i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (find.text('Done').evaluate().isNotEmpty) break;
        }

        expect(find.text('Scan Completed Successfully'), findsOneWidget);
        expect(find.text('Done'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Drain dialog
        await tester.tap(find.text('Done'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets('Adversarial Error Handling: Camera service failure produces retail message without exception', (tester) async {
        tester.view.physicalSize = resolution;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pythonApiRepositoryProvider.overrideWithValue(_MockFailurePythonApiRepository()),
              currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(),
              ),
            ),
          ),
        );

        await tester.pump();
        final startBtn = find.text('Start Full Shelf Scan');
        await tester.ensureVisible(startBtn);
        await tester.tap(startBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (find.text('Done').evaluate().isNotEmpty) break;
        }

        // Verify friendly retail failure message appears and NO technical jargon
        expect(find.textContaining('Shelf scan failed: Unable to connect to camera system.'), findsOneWidget);
        expect(find.textContaining('edge camera service'), findsNothing);
        expect(find.textContaining('Vision Scan'), findsNothing);
        expect(tester.takeException(), isNull);

        // Drain dialog
        await tester.tap(find.text('Done'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      });

      testWidgets('Adversarial Exception Handling: Backend network exception is caught and displayed cleanly', (tester) async {
        tester.view.physicalSize = resolution;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pythonApiRepositoryProvider.overrideWithValue(_MockExceptionPythonApiRepository()),
              currentBranchProvider.overrideWith((ref) => 'San Pablo'),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(),
              ),
            ),
          ),
        );

        await tester.pump();
        final startBtn = find.text('Start Full Shelf Scan');
        await tester.ensureVisible(startBtn);
        await tester.tap(startBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        for (int i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 250));
          if (find.text('Done').evaluate().isNotEmpty) break;
        }

        expect(find.textContaining('Scan completed with notice: Exception: Socket connection timeout to backend'), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Drain dialog
        await tester.tap(find.text('Done'));
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 500));
      });
    });
  }
}
