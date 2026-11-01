import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_shelf_linux/data/models/hardware_camera_device.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/providers/system_power_provider.dart';
import 'package:smart_shelf_linux/ui/components/power_options_dialog.dart';
import 'package:smart_shelf_linux/ui/components/system_restart_banner.dart';
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

  void setKioskViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
  }

  Widget buildTestHarness({
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

  group('Adversarial Stress Test: Safety Confirmation Dialogs (Dismiss & Cancel)', () {
    testWidgets(
      'Stress 1.1: Software Relaunch - Dismissing confirmation dialog via modal barrier NEVER calls relaunch',
      (tester) async {
        setKioskViewport(tester);
        int relaunchCalls = 0;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRelaunchApp: () async {
                      relaunchCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open main modal
        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        // Tap Relaunch action card to open confirmation dialog
        await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsOneWidget);

        // Tap barrier (outside dialog) at top-left corner
        await tester.tapAt(const Offset(50, 50));
        await tester.pumpAndSettle();

        // Verify confirmation dialog closed, but callback was NEVER called
        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsNothing);
        expect(relaunchCalls, equals(0));
      },
    );

    testWidgets(
      'Stress 1.2: Software Relaunch - Tapping Cancel button NEVER calls relaunch',
      (tester) async {
        setKioskViewport(tester);
        int relaunchCalls = 0;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRelaunchApp: () async {
                      relaunchCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
        await tester.pumpAndSettle();

        // Tap Cancel button
        await tester.tap(find.byKey(const Key('btn_cancel_relaunch')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsNothing);
        expect(relaunchCalls, equals(0));
      },
    );

    testWidgets(
      'Stress 1.3: Software Relaunch - Navigator.pop (Escape/Back) NEVER calls relaunch',
      (tester) async {
        setKioskViewport(tester);
        int relaunchCalls = 0;
        late BuildContext savedContext;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return Scaffold(
                  body: ElevatedButton(
                    key: const Key('open_dialog'),
                    onPressed: () => PowerOptionsModalDialog.show(
                      ctx,
                      onRelaunchApp: () async {
                        relaunchCalls++;
                      },
                    ),
                    child: const Text('Open'),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_relaunch_software')));
        await tester.pumpAndSettle();

        // Simulate back navigation pop
        Navigator.of(savedContext).pop();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_relaunch')), findsNothing);
        expect(relaunchCalls, equals(0));
      },
    );

    testWidgets(
      'Stress 1.4: Reboot Kiosk OS - Dismissing confirmation dialog via modal barrier NEVER triggers reboot',
      (tester) async {
        setKioskViewport(tester);
        int rebootCalls = 0;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRestartSystem: () {
                      rebootCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_confirm_reboot')), findsOneWidget);

        // Tap barrier at top-left
        await tester.tapAt(const Offset(50, 50));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_reboot')), findsNothing);
        expect(rebootCalls, equals(0));
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 1.5: Reboot Kiosk OS - Tapping Cancel button NEVER triggers reboot',
      (tester) async {
        setKioskViewport(tester);
        int rebootCalls = 0;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRestartSystem: () {
                      rebootCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_cancel_reboot')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_reboot')), findsNothing);
        expect(rebootCalls, equals(0));
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 1.6: Shut Down Kiosk - Dismissing confirmation dialog via modal barrier NEVER triggers shutdown',
      (tester) async {
        setKioskViewport(tester);
        int shutdownCalls = 0;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onShutdownSystem: () {
                      shutdownCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_confirm_shutdown')), findsOneWidget);

        // Tap barrier outside
        await tester.tapAt(const Offset(50, 50));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_shutdown')), findsNothing);
        expect(shutdownCalls, equals(0));
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 1.7: Shut Down Kiosk - Tapping Cancel button NEVER triggers shutdown',
      (tester) async {
        setKioskViewport(tester);
        int shutdownCalls = 0;
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onShutdownSystem: () {
                      shutdownCalls++;
                    },
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('btn_cancel_shutdown')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('dialog_confirm_shutdown')), findsNothing);
        expect(shutdownCalls, equals(0));
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 1.8: Main Power Modal - Barrier dismissal, cancel button, and close X NEVER trigger actions',
      (tester) async {
        setKioskViewport(tester);
        int actionsTriggered = 0;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRelaunchApp: () async => actionsTriggered++,
                    onRestartSystem: () => actionsTriggered++,
                    onShutdownSystem: () => actionsTriggered++,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Dismiss via barrier
        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsOneWidget);
        await tester.tapAt(const Offset(50, 50));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
        expect(actionsTriggered, equals(0));

        // 2. Dismiss via Cancel button
        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_dismiss_power_dialog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
        expect(actionsTriggered, equals(0));

        // 3. Dismiss via close 'X' button
        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('btn_close_power_dialog')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
        expect(actionsTriggered, equals(0));
      },
    );
  });

  group('Adversarial Stress Test: Rapid Tapping & Multi-Tap on Action Cards', () {
    testWidgets(
      'Stress 2.1: Rapid multi-tapping (10x) on Reboot OS card does NOT trigger multiple concurrent countdowns',
      (tester) async {
        setKioskViewport(tester);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        final rebootCard = find.byKey(const Key('action_card_reboot_os'));
        expect(rebootCard, findsOneWidget);

        // Adversarial stress: Rapidly multi-tap the card 10 times with minimal pump in between
        for (int i = 0; i < 10; i++) {
          await tester.tap(rebootCard, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        // Confirmation dialog is shown
        final confirmDialogFinder = find.byKey(const Key('dialog_confirm_reboot'));
        expect(confirmDialogFinder, findsWidgets);

        // Confirm reboot
        await tester.tap(find.byKey(const Key('btn_confirm_reboot')).first);
        await tester.pumpAndSettle();

        // Countdown must be active
        final state = container.read(systemRestartProvider);
        expect(state.isCountingDown, isTrue);
        expect(state.action, equals(SystemPowerAction.restart));
        expect(state.remainingSeconds, equals(15));

        // EMPIRICAL RATE VERIFICATION:
        // Advance clock by exactly 3 seconds.
        // If multiple concurrent timers were active, remainingSeconds would decrease by 6 or more!
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(14));
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(13));
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(12));

        // Exactly 1 second per real second: strictly ONE active timer
        container.read(systemRestartProvider.notifier).cancelCountdown();
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'Stress 2.2: Rapid multi-tapping (10x) on Shutdown card does NOT trigger multiple concurrent countdowns',
      (tester) async {
        setKioskViewport(tester);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        final shutdownCard = find.byKey(const Key('action_card_shutdown_kiosk'));
        expect(shutdownCard, findsOneWidget);

        // Adversarial stress: Rapid multi-tap the card 3 times in immediate frame sequence
        await tester.tap(shutdownCard);
        await tester.tap(shutdownCard, warnIfMissed: false);
        await tester.tap(shutdownCard, warnIfMissed: false);
        await tester.pumpAndSettle();

        final confirmBtnFinder = find.byKey(const Key('btn_confirm_shutdown'));
        expect(confirmBtnFinder, findsWidgets);

        // Confirm shutdown
        await tester.tap(confirmBtnFinder.first);
        await tester.pumpAndSettle();

        final state = container.read(systemRestartProvider);
        expect(state.isCountingDown, isTrue);
        expect(state.action, equals(SystemPowerAction.shutdown));
        expect(state.remainingSeconds, equals(15));

        // Empirical clock rate verification for shutdown
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(14));
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(13));
        await tester.pump(const Duration(seconds: 1));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(12));

        container.read(systemRestartProvider.notifier).cancelCountdown();
        await tester.pump(const Duration(seconds: 5));
      },
    );

    testWidgets(
      'Stress 2.3: Rapid multi-tapping (10x) on Relaunch card executes callback at most once per confirmed cycle',
      (tester) async {
        setKioskViewport(tester);
        int relaunchCalls = 0;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRelaunchApp: () async => relaunchCalls++,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        final relaunchCard = find.byKey(const Key('action_card_relaunch_software'));

        // Tap rapidly in immediate succession
        await tester.tap(relaunchCard);
        await tester.tap(relaunchCard, warnIfMissed: false);
        await tester.tap(relaunchCard, warnIfMissed: false);
        await tester.pumpAndSettle();

        // Confirm
        await tester.tap(find.byKey(const Key('btn_confirm_relaunch')).first);
        await tester.pumpAndSettle();

        // Must have been called once, modal dismissed
        expect(relaunchCalls, equals(1));
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);
      },
    );

    testWidgets(
      'Stress 2.4: Simultaneous/alternating multi-tap across different action cards does not crash and leaves system safe',
      (tester) async {
        setKioskViewport(tester);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(ctx),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        // Rapidly alternate taps across relaunch, reboot, and shutdown
        await tester.tap(find.byKey(const Key('action_card_relaunch_software')), warnIfMissed: false);
        await tester.tap(find.byKey(const Key('action_card_reboot_os')), warnIfMissed: false);
        await tester.tap(find.byKey(const Key('action_card_shutdown_kiosk')), warnIfMissed: false);
        await tester.pumpAndSettle();

        // UI is intact without unhandled exceptions. If any dialog is open, safely dismiss it.
        final cancelBtn = find.text('Cancel');
        while (cancelBtn.evaluate().isNotEmpty) {
          await tester.tap(cancelBtn.first, warnIfMissed: false);
          await tester.pumpAndSettle();
        }

        // System countdown was NEVER triggered without explicit confirmation
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 2.5: Rapid multi-tap (5x) on confirm button inside dialog executes safely',
      (tester) async {
        setKioskViewport(tester);
        int rebootCalls = 0;
        await tester.pumpWidget(
          buildTestHarness(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  key: const Key('open_dialog'),
                  onPressed: () => PowerOptionsModalDialog.show(
                    ctx,
                    onRestartSystem: () => rebootCalls++,
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('open_dialog')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('action_card_reboot_os')));
        await tester.pumpAndSettle();

        final confirmBtn = find.byKey(const Key('btn_confirm_reboot'));
        expect(confirmBtn, findsOneWidget);

        // Rapidly tap confirm 5 times
        for (int i = 0; i < 5; i++) {
          await tester.tap(confirmBtn, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 5));
        }
        await tester.pumpAndSettle();

        // Callback invoked exactly once
        expect(rebootCalls, equals(1));
        expect(find.byKey(const Key('dialog_confirm_reboot')), findsNothing);
        expect(find.byKey(const Key('dialog_power_options')), findsNothing);

        await tester.pump(const Duration(seconds: 5));
      },
    );
  });

  group('Adversarial Stress Test: Concurrent Countdown & Timer Single-Instance Invariants', () {
    testWidgets(
      'Stress 3.1: Calling startCountdown 50 times in rapid succession cancels prior timer and preserves exactly ONE timer',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(systemRestartProvider.notifier);

        // Rapidly call startCountdown 50 times
        for (int i = 0; i < 50; i++) {
          notifier.startCountdown(
            action: i % 2 == 0 ? SystemPowerAction.restart : SystemPowerAction.shutdown,
          );
        }

        expect(container.read(systemRestartProvider).isCountingDown, isTrue);
        expect(container.read(systemRestartProvider).remainingSeconds, equals(15));

        // Advance 1 second at a time, assert exactly 1 second decrement per second
        for (int sec = 14; sec >= 10; sec--) {
          await tester.pump(const Duration(seconds: 1));
          expect(
            container.read(systemRestartProvider).remainingSeconds,
            equals(sec),
            reason: 'Timer leaked or running faster than 1 tick/second at second $sec',
          );
        }

        notifier.cancelCountdown();
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 3.2: Calling cancelCountdown stops all timers completely; no execution after 15+ simulated seconds',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        final notifier = container.read(systemRestartProvider.notifier);
        notifier.startCountdown(action: SystemPowerAction.restart);
        expect(container.read(systemRestartProvider).isCountingDown, isTrue);

        await tester.pump(const Duration(seconds: 2));
        expect(container.read(systemRestartProvider).remainingSeconds, equals(13));

        // Cancel countdown
        notifier.cancelCountdown();
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
        expect(container.read(systemRestartProvider).remainingSeconds, equals(15));

        // Advance simulated time past original expiration (15 seconds)
        await tester.pump(const Duration(seconds: 20));

        // Timer is dead, state remains un-triggered
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 3.3: SystemRestartBanner integration under active countdown and abort',
      (tester) async {
        setKioskViewport(tester);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: const Scaffold(
              body: Column(
                children: [
                  SystemRestartBanner(),
                  Expanded(child: Center(child: Text('Content Area'))),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Banner is hidden initially
        expect(find.text('OPERATING SYSTEM RESTART IN PROGRESS'), findsNothing);

        // Start countdown via provider
        container.read(systemRestartProvider.notifier).startCountdown(
          action: SystemPowerAction.restart,
        );
        await tester.pump();

        // Banner is immediately visible
        expect(find.text('OPERATING SYSTEM RESTART IN PROGRESS'), findsOneWidget);
        expect(find.text('15'), findsOneWidget);

        // Advance 1 second
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('14'), findsOneWidget);

        // Tap Cancel on SystemRestartBanner
        await tester.tap(find.text('Cancel'));
        await tester.pump();

        // Banner hides immediately
        expect(find.text('OPERATING SYSTEM RESTART IN PROGRESS'), findsNothing);
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);

        // Advance past expiration, verify no action
        await tester.pump(const Duration(seconds: 20));
        expect(container.read(systemRestartProvider).isCountingDown, isFalse);
      },
    );

    testWidgets(
      'Stress 3.4: SystemRestartBanner displays Shutdown title and red icon when action is shutdown',
      (tester) async {
        setKioskViewport(tester);
        final container = ProviderContainer();
        addTearDown(container.dispose);

        await tester.pumpWidget(
          buildTestHarness(
            container: container,
            home: const Scaffold(
              body: Column(
                children: [
                  SystemRestartBanner(),
                  Expanded(child: Center(child: Text('Content Area'))),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        container.read(systemRestartProvider.notifier).startCountdown(
          action: SystemPowerAction.shutdown,
        );
        await tester.pump();

        expect(find.text('OPERATING SYSTEM SHUTDOWN IN PROGRESS'), findsOneWidget);
        expect(find.text('Shutdown Now'), findsOneWidget);

        container.read(systemRestartProvider.notifier).cancelCountdown();
        await tester.pump();
      },
    );
  });
}
