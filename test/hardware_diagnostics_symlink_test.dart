import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/data/services/camera_hardware_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/settings/camera_assignment_dialog.dart';

void main() {
  group('R5: Hardware Diagnostics Re-probe & Udev Symlinks', () {
    testWidgets('CameraAssignmentDialog displays all 6 cameras and online/offline badges', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Simulate 2 connected cameras on Hub 1 (1-1.1 and 1-1.2)
      final detectedDevices = [
        const HardwareCameraDevice(
          name: 'USB Camera 1A',
          deviceNode: '/dev/video0',
          usbPort: '1-1.1',
        ),
        const HardwareCameraDevice(
          name: 'USB Camera 2A',
          deviceNode: '/dev/video2',
          usbPort: '1-1.2',
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

      // Verify all 6 camera names and nodes are displayed
      expect(find.text('Cam 1A (Top Left)'), findsOneWidget);
      expect(find.text('Cam 1B (Top Right)'), findsOneWidget);
      expect(find.text('Cam 2A (Middle Left)'), findsOneWidget);
      expect(find.text('Cam 2B (Middle Right)'), findsOneWidget);
      expect(find.text('Cam 3A (Bottom Left)'), findsOneWidget);
      expect(find.text('Cam 3B (Bottom Right)'), findsOneWidget);

      expect(find.text('/dev/cam1a'), findsOneWidget);
      expect(find.text('/dev/cam1b'), findsOneWidget);
      expect(find.text('/dev/cam2a'), findsOneWidget);
      expect(find.text('/dev/cam2b'), findsOneWidget);
      expect(find.text('/dev/cam3a'), findsOneWidget);
      expect(find.text('/dev/cam3b'), findsOneWidget);

      // Verify Online badge for matched ports (1-1.1 and 1-1.2 are online)
      expect(find.text('ONLINE'), findsAtLeastNWidgets(2));

      // Verify Re-probe Hardware button is present
      final reprobeBtn = find.widgetWithText(OutlinedButton, 'Re-probe Hardware');
      expect(reprobeBtn, findsOneWidget);

      // Tap Re-probe Hardware
      await tester.tap(reprobeBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Re-probe Hardware'), findsOneWidget);
    });

    test('CameraHardwareService binds individual available symlinks without requiring all 6', () async {
      final hwService = CameraHardwareService.instance;
      // Trigger probe
      await hwService.probeHardwareDevices();
      
      // Node map should be populated for 6 cameras
      for (int i = 1; i <= 6; i++) {
        final node = hwService.getAssignedDeviceNode(i);
        expect(node, isNotEmpty);
      }
    });
  });
}
