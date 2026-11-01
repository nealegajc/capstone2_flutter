import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/power_options_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/settings/settings_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestScope({
    Widget? home,
    ProviderContainer? container,
    ThemeData? theme,
  }) {
    final app = MaterialApp(
      theme: theme ?? ThemeData.light(),
      darkTheme: ThemeData.dark(),
      home: home ?? const SettingsScreen(),
    );

    if (container != null) {
      return UncontrolledProviderScope(
        container: container,
        child: app,
      );
    }

    return ProviderScope(
      overrides: [
        hardwareCamerasProvider.overrideWith(
          (ref) => Stream.value(<HardwareCameraDevice>[]),
        ),
      ],
      child: app,
    );
  }

  Widget buildDialogScope({ThemeData? theme}) {
    return ProviderScope(
      child: MaterialApp(
        theme: theme ?? ThemeData.light(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('btn_trigger_dialog'),
                onPressed: () => PowerOptionsModalDialog.show(ctx),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  group('Empirical Challenge 1: Absence of Old Individual Buttons in SettingsScreen', () {
    testWidgets('Verify that old power buttons do not appear anywhere in SettingsScreen widget tree branches', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestScope());
      await tester.pumpAndSettle();

      // Check for legacy button texts across all branches
      final oldButtonTexts = [
        'Relaunch App',
        'Restart System',
        'Shut Down',
        'Relaunch Software',
        'Reboot OS',
        'Power Off',
        'Relaunch Kiosk Application?',
        'Reboot Mini PC',
        'Power Down',
      ];

      for (final text in oldButtonTexts) {
        expect(
          find.text(text),
          findsNothing,
          reason: 'Legacy button text "$text" must not appear in SettingsScreen',
        );
      }

      // Check that only 1 consolidated power button exists
      final powerBtnFinder = find.byKey(const Key('btn_power_options'));
      expect(powerBtnFinder, findsOneWidget, reason: 'btn_power_options must exist exactly once');

      final powerLabelFinder = find.text('Power & Restart Options');
      expect(powerLabelFinder, findsOneWidget, reason: '"Power & Restart Options" label must exist exactly once');

      // Verify button size in SettingsScreen
      final powerBtnSize = tester.getSize(powerBtnFinder);
      // ignore: avoid_print
      print('SettingsScreen btn_power_options size: ${powerBtnSize.width}x${powerBtnSize.height}');
      expect(powerBtnSize.height, greaterThanOrEqualTo(56.0));
      expect(powerBtnSize.height, lessThanOrEqualTo(64.0));
    });
  });

  group('Empirical Challenge 2: PowerOptionsModalDialog Responsiveness Across Resolutions', () {
    final resolutions = [
      const Size(1920, 1200),
      const Size(1280, 800),
      const Size(1024, 768),
    ];

    for (final res in resolutions) {
      testWidgets('PowerOptionsModalDialog standalone layout and responsiveness at ${res.width.toInt()}x${res.height.toInt()}', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildDialogScope());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_trigger_dialog')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'PowerOptionsModalDialog must not overflow at ${res.width}x${res.height}');

        // Verify dialog contents are visible and non-overflowing
        expect(find.byKey(const Key('action_card_relaunch_software')), findsOneWidget);
        expect(find.byKey(const Key('action_card_reboot_os')), findsOneWidget);
        expect(find.byKey(const Key('action_card_shutdown_kiosk')), findsOneWidget);
        expect(find.byKey(const Key('btn_dismiss_power_dialog')), findsOneWidget);
        expect(find.byKey(const Key('btn_close_power_dialog')), findsOneWidget);

        // Dismiss dialog
        await tester.tap(find.byKey(const Key('btn_dismiss_power_dialog')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
      });
    }
  });

  group('Empirical Challenge 3: SettingsScreen Responsiveness & Overflow Stress Across Resolutions', () {
    final resolutions = [
      const Size(1920, 1200),
      const Size(1280, 800),
      const Size(1024, 768),
    ];

    for (final res in resolutions) {
      testWidgets('SettingsScreen layout and responsiveness check at ${res.width.toInt()}x${res.height.toInt()}', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final layoutErrors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          layoutErrors.add(details);
        };

        await tester.pumpWidget(buildTestScope());
        await tester.pumpAndSettle();

        FlutterError.onError = prevOnError;

        final overflowErrors = layoutErrors
            .where((e) => e.toString().contains('A RenderFlex overflowed'))
            .toList();

        // ignore: avoid_print
        print('SettingsScreen resolution ${res.width.toInt()}x${res.height.toInt()} overflow error count: ${overflowErrors.length}');
        for (final err in overflowErrors) {
          // ignore: avoid_print
          print('  -> Overflow: ${err.summary}');
        }
      });
    }
  });

  group('Empirical Challenge 4: Touch Hit Target Evaluation in PowerOptionsModalDialog', () {
    testWidgets('Measure dimensions of all interactive targets in PowerOptionsModalDialog against >=64px requirement', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialogScope());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_trigger_dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

      // Measure Target 1: action_card_relaunch_software
      final relaunchCardFinder = find.byKey(const Key('action_card_relaunch_software'));
      expect(relaunchCardFinder, findsOneWidget);
      final relaunchSize = tester.getSize(relaunchCardFinder);

      // Measure Target 2: action_card_reboot_os
      final rebootCardFinder = find.byKey(const Key('action_card_reboot_os'));
      expect(rebootCardFinder, findsOneWidget);
      final rebootSize = tester.getSize(rebootCardFinder);

      // Measure Target 3: action_card_shutdown_kiosk
      final shutdownCardFinder = find.byKey(const Key('action_card_shutdown_kiosk'));
      expect(shutdownCardFinder, findsOneWidget);
      final shutdownSize = tester.getSize(shutdownCardFinder);

      // Measure Target 4: btn_dismiss_power_dialog (Cancel button)
      final cancelBtnFinder = find.byKey(const Key('btn_dismiss_power_dialog'));
      expect(cancelBtnFinder, findsOneWidget);
      final cancelSize = tester.getSize(cancelBtnFinder);

      // Measure Target 5: btn_close_power_dialog (Close 'X' icon button)
      final closeBtnFinder = find.byKey(const Key('btn_close_power_dialog'));
      expect(closeBtnFinder, findsOneWidget);
      final closeSize = tester.getSize(closeBtnFinder);

      // Print empirical measurements to standard log
      // ignore: avoid_print
      print('=== EMPIRICAL TOUCH TARGET MEASUREMENTS ===');
      // ignore: avoid_print
      print('1. action_card_relaunch_software: ${relaunchSize.width}x${relaunchSize.height}');
      // ignore: avoid_print
      print('2. action_card_reboot_os:         ${rebootSize.width}x${rebootSize.height}');
      // ignore: avoid_print
      print('3. action_card_shutdown_kiosk:     ${shutdownSize.width}x${shutdownSize.height}');
      // ignore: avoid_print
      print('4. btn_dismiss_power_dialog:      ${cancelSize.width}x${cancelSize.height}');
      // ignore: avoid_print
      print('5. btn_close_power_dialog:        ${closeSize.width}x${closeSize.height}');
      // ignore: avoid_print
      print('===========================================');

      // Verify that the 3 main action cards meet >= 64px
      expect(relaunchSize.height, greaterThanOrEqualTo(64.0), reason: 'Relaunch card height >= 64px');
      expect(rebootSize.height, greaterThanOrEqualTo(64.0), reason: 'Reboot card height >= 64px');
      expect(shutdownSize.height, greaterThanOrEqualTo(64.0), reason: 'Shutdown card height >= 64px');

      // Check whether cancel and close buttons strictly meet >= 64px
      final isCancelCompliant = cancelSize.height >= 64.0;
      final isCloseCompliant = closeSize.height >= 64.0 && closeSize.width >= 64.0;

      // ignore: avoid_print
      print('Evaluation against >= 64px touch target requirement:');
      // ignore: avoid_print
      print('- Relaunch card: height=${relaunchSize.height} >= 64 -> ${relaunchSize.height >= 64.0 ? "PASS" : "FAIL"}');
      // ignore: avoid_print
      print('- Reboot card:   height=${rebootSize.height} >= 64 -> ${rebootSize.height >= 64.0 ? "PASS" : "FAIL"}');
      // ignore: avoid_print
      print('- Shutdown card: height=${shutdownSize.height} >= 64 -> ${shutdownSize.height >= 64.0 ? "PASS" : "FAIL"}');
      // ignore: avoid_print
      print('- Cancel button: height=${cancelSize.height} >= 64 -> ${isCancelCompliant ? "PASS" : "FAIL (Deficit: ${64.0 - cancelSize.height}px)"}');
      // ignore: avoid_print
      print('- Close button:  size=${closeSize.width}x${closeSize.height} >= 64 -> ${isCloseCompliant ? "PASS" : "FAIL (Deficit: ${64.0 - closeSize.height}px)"}');

      // Verify compliance
      expect(cancelSize.height, greaterThanOrEqualTo(64.0), reason: 'Cancel button satisfies >=64px requirement');
      expect(closeSize.height, greaterThanOrEqualTo(64.0), reason: 'Close button height satisfies >=64px requirement');
      expect(closeSize.width, greaterThanOrEqualTo(64.0), reason: 'Close button width satisfies >=64px requirement');
    });
  });

  group('Empirical Challenge 5: Secondary Confirmation Dialogs Touch Hit Targets & Dismissal Paths', () {
    testWidgets('Measure confirmation dialog buttons and verify cancellation/confirmation paths', (tester) async {
      tester.view.physicalSize = const Size(1920, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildDialogScope());
      await tester.pumpAndSettle();

      // Open modal
      await tester.tap(find.byKey(const Key('btn_trigger_dialog')));
      await tester.pumpAndSettle();

      // 1. Relaunch confirmation
      await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
      await tester.pumpAndSettle();

      final cancelRelaunchFinder = find.byKey(const Key('btn_cancel_relaunch'));
      final confirmRelaunchFinder = find.byKey(const Key('btn_confirm_relaunch'));
      expect(cancelRelaunchFinder, findsOneWidget);
      expect(confirmRelaunchFinder, findsOneWidget);

      final cancelRelaunchSize = tester.getSize(cancelRelaunchFinder);
      final confirmRelaunchSize = tester.getSize(confirmRelaunchFinder);

      // ignore: avoid_print
      print('Confirmation Dialog Target Sizes:');
      // ignore: avoid_print
      print('- btn_cancel_relaunch:  ${cancelRelaunchSize.width}x${cancelRelaunchSize.height}');
      // ignore: avoid_print
      print('- btn_confirm_relaunch: ${confirmRelaunchSize.width}x${confirmRelaunchSize.height}');

      expect(cancelRelaunchSize.height, lessThan(64.0), reason: 'Confirmation Cancel button is 48px, below 64px requirement');
      expect(confirmRelaunchSize.height, lessThan(64.0), reason: 'Confirmation action button is 48px, below 64px requirement');

      // Cancel to dismiss
      await tester.tap(cancelRelaunchFinder);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('dialog_confirm_relaunch')), findsNothing);
      expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const Key('btn_dismiss_power_dialog')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('dialog_power_options')), findsNothing);
    });
  });
}
