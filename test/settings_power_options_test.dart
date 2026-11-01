import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_shelf_linux/core/theme/app_colors.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/system_power_provider.dart';
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

  Widget buildTestApp({
    Widget? home,
    ProviderContainer? container,
  }) {
    final app = MaterialApp(
      theme: ThemeData.light(),
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

  group('Milestone 2 (R2): Consolidated Power Controls in Settings', () {
    testWidgets(
      'SettingsScreen displays single prominent Power & Restart Options button (60-64px, AppColors.statusRed) and old buttons are removed',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
        await tester.pumpAndSettle();

        // 1. Verify old individual power buttons are completely absent
        expect(find.text('Relaunch App'), findsNothing);
        expect(find.text('Restart System'), findsNothing);
        expect(find.text('Shut Down'), findsNothing);
        expect(find.text('Relaunch Software'), findsNothing);
        expect(find.text('Reboot OS'), findsNothing);
        expect(find.text('Power Off'), findsNothing);

        // 2. Verify single prominent button is present
        final powerBtnFinder = find.byKey(const Key('btn_power_options'));
        expect(powerBtnFinder, findsOneWidget);
        expect(find.text('Power & Restart Options'), findsOneWidget);

        // 3. Verify button height is 60–64px
        final btnSize = tester.getSize(powerBtnFinder);
        expect(btnSize.height, greaterThanOrEqualTo(60.0));
        expect(btnSize.height, lessThanOrEqualTo(64.0));

        // 4. Verify button style (AppColors.statusRed, power icon)
        final elevatedBtn = tester.widget<ElevatedButton>(powerBtnFinder);
        final bg = elevatedBtn.style?.backgroundColor?.resolve({});
        expect(bg, equals(AppColors.statusRed));

        expect(find.byIcon(Icons.power_settings_new_rounded), findsWidgets);
      },
    );

    testWidgets(
      'Tapping Power & Restart Options opens modal dialog with 3 touch-friendly action cards (min height >= 64px)',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestApp(home: const SettingsScreen()));
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.byKey(const Key('btn_power_options')));
        await tester.pumpAndSettle();

        // Verify dialog is visible
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);
        expect(
          find.text('Select an action below. All actions require confirmation.'),
          findsOneWidget,
        );

        // Verify 3 distinct action cards
        final relaunchCard = find.byKey(const Key('action_card_relaunch_software'));
        final rebootCard = find.byKey(const Key('action_card_reboot_os'));
        final shutdownCard = find.byKey(const Key('action_card_shutdown_kiosk'));

        expect(relaunchCard, findsOneWidget);
        expect(rebootCard, findsOneWidget);
        expect(shutdownCard, findsOneWidget);

        expect(find.text('Relaunch Software Process'), findsOneWidget);
        expect(find.text('Reboot Kiosk OS'), findsOneWidget);
        expect(find.text('Shut Down Kiosk'), findsOneWidget);

        // Verify touch-friendly action card dimensions (min height >= 64px, specifically 72px)
        final relaunchSize = tester.getSize(relaunchCard);
        final rebootSize = tester.getSize(rebootCard);
        final shutdownSize = tester.getSize(shutdownCard);

        expect(relaunchSize.height, greaterThanOrEqualTo(64.0));
        expect(rebootSize.height, greaterThanOrEqualTo(64.0));
        expect(shutdownSize.height, greaterThanOrEqualTo(64.0));
      },
    );

    testWidgets(
      'Action 1 (Relaunch Software Process): Protected by secondary safety confirmation before executing',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool relaunchCalled = false;

        await tester.pumpWidget(
          buildTestApp(
            home: SettingsScreen(
              onRelaunchApp: () async {
                relaunchCalled = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open modal
        await tester.tap(find.byKey(const Key('btn_power_options')));
        await tester.pumpAndSettle();

        // 1. Tap Relaunch Software Process
        await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsOneWidget);
        expect(find.text('Confirm Software Relaunch'), findsOneWidget);
        expect(relaunchCalled, isFalse);

        // Cancel confirmation
        await tester.tap(find.byKey(const Key('btn_cancel_relaunch')));
        await tester.pumpAndSettle();

        // Verify cancelled: dialog gone, callback NOT invoked, modal still present
        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsNothing);
        expect(relaunchCalled, isFalse);
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

        // 2. Tap Relaunch Software Process again and confirm
        await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_relaunch')));
        await tester.pumpAndSettle();

        // Verify confirmed: callback executed and modal dismissed
        expect(relaunchCalled, isTrue);
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
      },
    );

    testWidgets(
      'Action 2 (Reboot Kiosk OS): Protected by secondary safety confirmation before calling service',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool rebootCalled = false;

        await tester.pumpWidget(
          buildTestApp(
            home: SettingsScreen(
              onRestartSystem: () {
                rebootCalled = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open modal
        await tester.tap(find.byKey(const Key('btn_power_options')));
        await tester.pumpAndSettle();

        // 1. Tap Reboot Kiosk OS
        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.byKey(const Key('dialog_confirm_reboot')), findsOneWidget);
        expect(find.text('Confirm System Reboot'), findsOneWidget);
        expect(rebootCalled, isFalse);

        // Cancel confirmation
        await tester.tap(find.byKey(const Key('btn_cancel_reboot')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_reboot')), findsNothing);
        expect(rebootCalled, isFalse);
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

        // 2. Tap Reboot Kiosk OS again and confirm
        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_reboot')));
        await tester.pumpAndSettle();

        expect(rebootCalled, isTrue);
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
        expect(
          find.text('Reboot countdown active. See 15-second banner at top of screen.'),
          findsOneWidget,
        );

        // Advance SnackBar timer so no timers remain pending
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'Action 3 (Shut Down Kiosk): Protected by secondary safety confirmation before calling service',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool shutdownCalled = false;

        await tester.pumpWidget(
          buildTestApp(
            home: SettingsScreen(
              onShutdownSystem: () {
                shutdownCalled = true;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open modal
        await tester.tap(find.byKey(const Key('btn_power_options')));
        await tester.pumpAndSettle();

        // 1. Tap Shut Down Kiosk
        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')));
        await tester.pumpAndSettle();

        // Confirmation dialog appears
        expect(find.byKey(const Key('dialog_confirm_shutdown')), findsOneWidget);
        expect(find.text('Confirm Kiosk Shutdown'), findsOneWidget);
        expect(shutdownCalled, isFalse);

        // Cancel confirmation
        await tester.tap(find.byKey(const Key('btn_cancel_shutdown')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_shutdown')), findsNothing);
        expect(shutdownCalled, isFalse);
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

        // 2. Tap Shut Down Kiosk again and confirm
        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_shutdown')));
        await tester.pumpAndSettle();

        expect(shutdownCalled, isTrue);
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
        expect(
          find.text('Shutdown countdown active. See 15-second banner at top of screen.'),
          findsOneWidget,
        );

        // Advance SnackBar timer so no timers remain pending
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'PowerOptionsModalDialog triggers systemRestartProvider countdown for reboot and shutdown when default handlers are used',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            hardwareCamerasProvider.overrideWith(
              (ref) => Stream.value(<HardwareCameraDevice>[]),
            ),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestApp(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => PowerOptionsModalDialog.show(ctx),
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Verify initial restart provider state
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);

        // Test Reboot path
        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_reboot')));
        await tester.pumpAndSettle();

        // Countdown is active with SystemPowerAction.restart
        expect(container.read(systemRestartProvider).isCountingDown, isTrue);
        expect(
          container.read(systemRestartProvider).action,
          equals(SystemPowerAction.restart),
        );

        // Reset countdown for shutdown test
        container.read(systemRestartProvider.notifier).cancelCountdown();
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);

        // Reopen dialog
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // Test Shutdown path
        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_confirm_shutdown')));
        await tester.pumpAndSettle();

        // Countdown is active with SystemPowerAction.shutdown
        expect(container.read(systemRestartProvider).isCountingDown, isTrue);
        expect(
          container.read(systemRestartProvider).action,
          equals(SystemPowerAction.shutdown),
        );

        // Cancel countdown and advance SnackBar timer before test completes
        container.read(systemRestartProvider.notifier).cancelCountdown();
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'Modal dialog dismisses cleanly via Cancel button and Close icon button',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => PowerOptionsModalDialog.show(ctx),
                    child: const Text('Open Dialog'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Open and dismiss with Cancel button
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_dismiss_power_dialog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);

        // 2. Open and dismiss with close 'X' icon
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);

        await tester.tap(find.byKey(const Key('btn_close_power_dialog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
      },
    );
  });
}
