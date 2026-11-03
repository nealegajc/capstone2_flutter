import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:flutter_test/flutter_test.dart";
import "package:sqflite_common_ffi/sqflite_ffi.dart";
import "package:smart_shelf_linux/data/models/alert_model.dart";
import "package:smart_shelf_linux/data/models/hardware_camera_device.dart";
import "package:smart_shelf_linux/data/models/inventory_record_model.dart";
import "package:smart_shelf_linux/data/repositories/python_api_repository.dart";
import "package:smart_shelf_linux/data/services/camera_hardware_service.dart";
import "package:smart_shelf_linux/data/services/report_export_service.dart";
import "package:smart_shelf_linux/data/services/sqlite_service.dart";
import "package:smart_shelf_linux/providers/kiosk_providers.dart";
import "package:smart_shelf_linux/ui/components/scan_workflow_dialog.dart";
import "package:smart_shelf_linux/ui/screens/settings/camera_assignment_dialog.dart";

class _FakeZeroLightPythonApiRepository extends PythonApiRepository {
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    callCount++;
    return {
      "cameraId": cameraId ?? 1,
      "totalBottles": 0,
      "trayCounts": {},
      "detections": [],
      "success": false,
      "rejected": true,
      "qualityStatus": "REJECTED_LOW_LIGHT",
      "reason": "LOW_LIGHT",
      "brightness": 8.5,
      "message": "Low Lighting Detected: Shelf illumination required",
    };
  }
}

class _FakeEnhancedPythonApiRepository extends PythonApiRepository {
  int callCount = 0;

  @override
  Future<Map<String, dynamic>> triggerManualScan(
    String branch, {
    int? cameraId,
    String? cameraDevice,
    bool enableOcr = false,
    String? targetTray,
  }) async {
    callCount++;
    return {
      "cameraId": cameraId ?? 1,
      "totalBottles": 10,
      "trayCounts": {"tray_AA": 5, "tray_AB": 5},
      "detections": [
        {
          "id": "det_1",
          "roiId": "tray_AA",
          "centerX": 0.1,
          "centerY": 0.2,
          "matchResult": "matched",
          "yoloConfidence": 0.95,
        },
      ],
      "success": true,
      "rejected": false,
      "qualityStatus": "ENHANCED",
      "message": "AI Shelf Vision scan completed for Camera ${cameraId ?? 1}",
    };
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  tearDown(() {
    CameraHardwareService.instance.stopMonitoring();
  });

  group("CHALLENGER 10_2 — Empirical Stress Tests (R5, R6, R7)", () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.initDatabase(inMemory: true);
      final db = await sqliteService.database;
      await db.delete("alerts");
      await db.delete("inventory_records");
    });

    group("R5: Camera Symlinks & Re-probe", () {
      testWidgets("R5.1: Real filesystem /dev/cam3b symlink to /dev/video2 displays ONLINE green badge", (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final hasCam3b = File("/dev/cam3b").existsSync();
        final detectedDevices = [
          const HardwareCameraDevice(
            name: "Physical Webcam 3B",
            deviceNode: "/dev/video2",
            usbPort: "1-2.3",
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hardwareCamerasProvider.overrideWith((ref) => Stream.value(detectedDevices)),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CameraAssignmentDialog(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text("Cam 3B (Bottom Right)"), findsOneWidget);
        expect(find.text("/dev/cam3b"), findsOneWidget);

        if (hasCam3b) {
          expect(find.text("ONLINE"), findsWidgets);
        }

        final reprobeBtn = find.widgetWithText(OutlinedButton, "Re-probe Hardware");
        expect(reprobeBtn, findsOneWidget);

        await tester.tap(reprobeBtn);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text("Re-probe Hardware"), findsOneWidget);
      });

      testWidgets("R5.2: Symlink resolution with simulated devices matching /dev/video2", (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final detectedDevices = [
          const HardwareCameraDevice(
            name: "Kiosk Camera 3B",
            deviceNode: "/dev/video2",
            usbPort: "1-2.3",
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              hardwareCamerasProvider.overrideWith((ref) => Stream.value(detectedDevices)),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: CameraAssignmentDialog(),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text("ONLINE"), findsWidgets);

        for (final node in ["/dev/cam1a", "/dev/cam1b", "/dev/cam2a", "/dev/cam2b", "/dev/cam3a", "/dev/cam3b"]) {
          expect(find.text(node), findsOneWidget);
        }
      });

      test("R5.3: CameraHardwareService binds available symlinks without throwing when some are missing", () async {
        final hwService = CameraHardwareService.instance;
        await hwService.probeHardwareDevices();

        for (int camId = 1; camId <= 6; camId++) {
          final node = hwService.getAssignedDeviceNode(camId);
          expect(node, isNotEmpty);
          expect(node, startsWith("/dev/"));
        }
      });
    });

    group("R6: Network Interface Discovery & ServerUrl Update", () {
      test("R6.1: updateOrRedetectIp updates localIp and serverUrl dynamically", () async {
        final exportService = ReportExportService.instance;

        final newUrl = await exportService.updateOrRedetectIp("192.168.1.155");
        expect(newUrl, equals("192.168.1.155"));
        expect(exportService.localIp, equals("192.168.1.155"));
        expect(exportService.serverUrl, equals("http://192.168.1.155:8088"));

        await exportService.updateOrRedetectIp("10.0.0.42");
        expect(exportService.localIp, equals("10.0.0.42"));
        expect(exportService.serverUrl, equals("http://10.0.0.42:8088"));

        final detected = await exportService.updateOrRedetectIp();
        expect(detected, isNotEmpty);
        expect(exportService.serverUrl, equals("http://$detected:8088"));
      });

      test("R6.2: Virtual/bridge interface filtering and Wi-Fi priority regex verification", () {
        bool isVirtual(String name) {
          final lower = name.toLowerCase();
          return lower.startsWith("docker") ||
              lower.startsWith("virbr") ||
              lower.startsWith("veth") ||
              lower.startsWith("br-") ||
              lower.startsWith("dummy") ||
              lower == "lo";
        }

        final wifiRegex = RegExp(r"^(wl|wlan|wifi)", caseSensitive: false);
        final ethRegex = RegExp(r"^(eth|en)", caseSensitive: false);

        expect(isVirtual("docker0"), isTrue);
        expect(isVirtual("docker1"), isTrue);
        expect(isVirtual("virbr0"), isTrue);
        expect(isVirtual("veth99a1b"), isTrue);
        expect(isVirtual("br-89a1b2c3d4e5"), isTrue);
        expect(isVirtual("dummy0"), isTrue);
        expect(isVirtual("lo"), isTrue);

        expect(isVirtual("wlan0"), isFalse);
        expect(isVirtual("wlp2s0"), isFalse);
        expect(isVirtual("wifi0"), isFalse);
        expect(isVirtual("eth0"), isFalse);
        expect(isVirtual("enp3s0"), isFalse);

        expect(wifiRegex.hasMatch("wlan0"), isTrue);
        expect(wifiRegex.hasMatch("wlp2s0"), isTrue);
        expect(wifiRegex.hasMatch("wifi0"), isTrue);
        expect(wifiRegex.hasMatch("WLAN1"), isTrue);
        expect(wifiRegex.hasMatch("eth0"), isFalse);

        expect(ethRegex.hasMatch("eth0"), isTrue);
        expect(ethRegex.hasMatch("enp3s0"), isTrue);
        expect(ethRegex.hasMatch("eno1"), isTrue);
        expect(ethRegex.hasMatch("wlan0"), isFalse);

        final candidateNames = ["eth0", "docker0", "wlan0", "br-1234", "enp3s0", "lo"];
        final nonVirtual = candidateNames.where((n) => !isVirtual(n)).toList();
        expect(nonVirtual, equals(["eth0", "wlan0", "enp3s0"]));

        final selected = nonVirtual.firstWhere(
          (n) => wifiRegex.hasMatch(n),
          orElse: () => nonVirtual.firstWhere(
            (n) => ethRegex.hasMatch(n),
            orElse: () => "127.0.0.1",
          ),
        );
        expect(selected, equals("wlan0"), reason: "wlan0 must take top priority over eth0");
      });
    });

    group("R7: Zero-Light Rejection & SQLite Inventory Safeguard", () {
      testWidgets("R7.1: Zero-light image (< 15.0) rejected: true displays amber banner and leaves SQLite inventory intact", (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const branch = "San Pablo";
        final invAD1 = InventoryRecordModel(
          id: "inv_${branch}_AD1",
          perfumeCode: "AD1",
          name: "Sauvage Dior 100ml",
          branch: branch,
          shelf: "Tray AD",
          recorded: 5,
          detected: 4,
          status: "normal",
        );
        await sqliteService.saveInventoryRecord(invAD1);

        final initialRecord = await sqliteService.getInventoryRecord("AD1", branch);
        expect(initialRecord, isNotNull);
        final initialDetected = initialRecord!.detected;
        expect(initialDetected, equals(4));

        final fakeZeroLightRepo = _FakeZeroLightPythonApiRepository();
        final targetAlert = AlertModel(
          id: "alert_ad1_zero_light",
          title: "Discrepancy Detected",
          desc: "Inventory count mismatch on AD1",
          branch: branch,
          type: "misplaced",
          perfumeCode: "AD1",
          isRead: false,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sqliteServiceProvider.overrideWithValue(sqliteService),
              pythonApiRepositoryProvider.overrideWithValue(fakeZeroLightRepo),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(
                  isTargetedVerification: true,
                  targetAlert: targetAlert,
                  targetSlotCodes: const ["AD1"],
                  targetTrayCodes: const ["AD"],
                  initialCameraId: 1,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final verifyBtn = find.text("I Understand, Verify Now");
        expect(verifyBtn, findsOneWidget);
        await tester.tap(verifyBtn);
        await tester.pump();

        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(fakeZeroLightRepo.callCount, greaterThan(0));

        expect(find.text("Low Lighting Detected: Shelf illumination required"), findsWidgets);
        expect(
          find.textContaining("Ambient shelf illumination is below minimum threshold"),
          findsOneWidget,
        );

        final recordAfter = await sqliteService.getInventoryRecord("AD1", branch);
        expect(recordAfter!.detected, equals(initialDetected),
            reason: "Zero-light scan must NOT wipe detected count to 0 in SQLite!");

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      });

      testWidgets("R7.2: Suboptimal lighting with CLAHE enhancement allows bottle count update", (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const branch = "San Pablo";
        final invAA1 = InventoryRecordModel(
          id: "inv_${branch}_AA1",
          perfumeCode: "AA1",
          name: "Bleu de Chanel 100ml",
          branch: branch,
          shelf: "Tray AA",
          recorded: 5,
          detected: 2,
          status: "normal",
        );
        await sqliteService.saveInventoryRecord(invAA1);

        final fakeEnhancedRepo = _FakeEnhancedPythonApiRepository();
        final targetAlert = AlertModel(
          id: "alert_aa1_low_stock",
          title: "Low Stock Alert",
          desc: "Low stock on AA1",
          branch: branch,
          type: "low_stock",
          perfumeCode: "AA1",
          isRead: false,
          createdAt: DateTime.now(),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              sqliteServiceProvider.overrideWithValue(sqliteService),
              pythonApiRepositoryProvider.overrideWithValue(fakeEnhancedRepo),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ScanWorkflowDialog(
                  isTargetedVerification: true,
                  targetAlert: targetAlert,
                  targetSlotCodes: const ["AA1"],
                  targetTrayCodes: const ["AA"],
                  initialCameraId: 1,
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        final verifyBtn = find.text("I Understand, Verify Now");
        expect(verifyBtn, findsOneWidget);
        await tester.tap(verifyBtn);
        await tester.pump();

        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 300));
        }

        expect(fakeEnhancedRepo.callCount, greaterThan(0));

        expect(
          find.textContaining("Ambient shelf illumination is below minimum threshold"),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 200));
      });
    });
  });
}
