import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/data/models/auth_state.dart';
import 'package:smart_shelf_linux/providers/api_provider.dart';
import 'package:smart_shelf_linux/providers/auth_provider.dart';
import 'package:smart_shelf_linux/ui/components/kiosk_numpad.dart';
import 'package:smart_shelf_linux/ui/components/pin_dots_indicator.dart';
import 'package:smart_shelf_linux/ui/components/pin_recovery_dialog.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';

class _FakeAdversarialAuthNotifier extends AuthNotifier {
  _FakeAdversarialAuthNotifier(
    super.authService, {
    bool isLockedOut = false,
    int lockoutRemainingSeconds = 0,
    String enteredPin = '',
    String? errorMessage,
  }) {
    state = AuthState(
      isLockedOut: isLockedOut,
      lockoutRemainingSeconds: lockoutRemainingSeconds,
      enteredPin: enteredPin,
      errorMessage: errorMessage,
    );
  }

  @override
  Future<void> checkKioskLockout() async {}

  @override
  void appendDigit(String digit, {bool autoVerify = true}) {
    if (state.enteredPin.length < 6) {
      state = state.copyWith(enteredPin: state.enteredPin + digit, errorMessage: null);
    }
  }

  @override
  void clearPin() {
    state = state.copyWith(enteredPin: '', errorMessage: null);
  }

  @override
  void deleteDigit() {
    if (state.enteredPin.isNotEmpty) {
      state = state.copyWith(
        enteredPin: state.enteredPin.substring(0, state.enteredPin.length - 1),
        errorMessage: null,
      );
    }
  }

  @override
  void resetLockoutAndState() {
    state = const AuthState();
  }
}

void main() {
  const mandatedResolutions = [
    Size(1920, 1200),
    Size(1280, 800),
    Size(1024, 768),
  ];

  const extendedResolutions = [
    Size(1920, 1080),
    Size(1366, 768),
    Size(1024, 600),
    Size(800, 600),
    Size(1080, 1920), // portrait kiosk
    Size(800, 1280),  // portrait tablet
  ];

  group('M3.6 Remediation Adversarial Suite: Resolution & Overflow Stress Testing', () {
    for (final res in mandatedResolutions) {
      testWidgets('Zero layout overflow at mandated resolution ${res.width.toInt()}x${res.height.toInt()} in all states', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // 1. Normal State (Empty PIN)
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(ref.watch(authServiceProvider)),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Must not overflow in normal empty state at $res');

        // 2. Normal State with Error Banner
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(
                  ref.watch(authServiceProvider),
                  errorMessage: 'Incorrect PIN. 4 attempts remaining before system lockout.',
                  enteredPin: '1234',
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Must not overflow in error state at $res');

        // 3. Lockout State
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(
                  ref.watch(authServiceProvider),
                  isLockedOut: true,
                  lockoutRemainingSeconds: 300,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Must not overflow in lockout state at $res');
      });
    }

    for (final res in extendedResolutions) {
      testWidgets('Zero layout overflow at extended resolution ${res.width.toInt()}x${res.height.toInt()}', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(
                  ref.watch(authServiceProvider),
                  errorMessage: 'Incorrect PIN. Please re-enter credentials.',
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'Must not overflow at $res');
      });
    }

    testWidgets('Zero layout overflow under high accessibility text scaling (textScaleFactor: 1.35) at 1024x768', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authNotifierProvider.overrideWith(
              (ref) => _FakeAdversarialAuthNotifier(
                ref.watch(authServiceProvider),
                errorMessage: 'Incorrect PIN. 3 attempts remaining.',
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(1024, 768),
                textScaler: TextScaler.linear(1.35),
              ),
              child: const PinLoginScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Must absorb high text scale without layout overflow');
    });
  });

  group('M3.6 Remediation Adversarial Suite: Touch Target Sizing & Hitbox Verification', () {
    testWidgets('Empirically verify all numpad key heights are strictly >= 88px and width >= 88px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkKioskTheme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 480,
                child: KioskNumpad(
                  onDigitPressed: (_) {},
                  onClearPressed: () {},
                  onDeletePressed: () {},
                ),
              ),
            ),
          ),
        ),
      );

      // Check all 10 digits
      for (int i = 0; i <= 9; i++) {
        final keyFinder = find.byKey(ValueKey('numpad_key_$i'));
        expect(keyFinder, findsOneWidget);
        final size = tester.getSize(keyFinder);
        expect(size.height, greaterThanOrEqualTo(88.0), reason: 'Key $i height >= 88px');
        expect(size.width, greaterThanOrEqualTo(88.0), reason: 'Key $i width >= 88px');
      }

      // Check CLEAR and DELETE
      final clearFinder = find.byKey(const ValueKey('numpad_action_clear'));
      final deleteFinder = find.byKey(const ValueKey('numpad_action_delete'));
      expect(tester.getSize(clearFinder).height, greaterThanOrEqualTo(88.0));
      expect(tester.getSize(clearFinder).width, greaterThanOrEqualTo(88.0));
      expect(tester.getSize(deleteFinder).height, greaterThanOrEqualTo(88.0));
      expect(tester.getSize(deleteFinder).width, greaterThanOrEqualTo(88.0));
    });

    testWidgets('Empirically verify action button touch targets in normal & lockout states >= 56px height', (tester) async {
      for (final res in mandatedResolutions) {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Normal: forgot_pin_button
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(ref.watch(authServiceProvider)),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final recoveryFinder = find.byKey(const ValueKey('forgot_pin_button'));
        expect(recoveryFinder, findsOneWidget);
        final recoverySize = tester.getSize(recoveryFinder);
        expect(recoverySize.height, greaterThanOrEqualTo(56.0), reason: 'Forgot PIN height >= 56px at $res');
        expect(recoverySize.width, greaterThanOrEqualTo(400.0), reason: 'Forgot PIN width spans card at $res');

        // Lockout: emergency_override_button
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeAdversarialAuthNotifier(
                  ref.watch(authServiceProvider),
                  isLockedOut: true,
                  lockoutRemainingSeconds: 300,
                ),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final overrideFinder = find.byKey(const ValueKey('emergency_override_button'));
        expect(overrideFinder, findsOneWidget);
        final overrideSize = tester.getSize(overrideFinder);
        expect(overrideSize.height, greaterThanOrEqualTo(56.0), reason: 'Emergency Override height >= 56px at $res');
        expect(overrideSize.width, greaterThanOrEqualTo(400.0), reason: 'Emergency Override width spans card at $res');
      }
    });

    testWidgets('PIN dots sizing: unfilled 28px, filled 32px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkKioskTheme,
          home: const Scaffold(
            body: Center(
              child: PinDotsIndicator(
                pinLength: 6,
                enteredLength: 2,
              ),
            ),
          ),
        ),
      );

      final containers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PinDotsIndicator),
          matching: find.byType(AnimatedContainer),
        ),
      ).toList();

      expect(containers.length, equals(6));
      expect(containers[0].constraints?.minWidth, equals(32.0));
      expect(containers[0].constraints?.minHeight, equals(32.0));
      expect(containers[1].constraints?.minWidth, equals(32.0));
      expect(containers[1].constraints?.minHeight, equals(32.0));
      expect(containers[2].constraints?.minWidth, equals(28.0));
      expect(containers[2].constraints?.minHeight, equals(28.0));
    });
  });

  group('M3.6 Remediation Adversarial Suite: In-Screen Interaction & Scroll Usability', () {
    testWidgets('On 1024x768 display, operator can enter PIN via numpad with zero drops', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      late _FakeAdversarialAuthNotifier notifier;

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authNotifierProvider.overrideWith((ref) {
              notifier = _FakeAdversarialAuthNotifier(ref.watch(authServiceProvider));
              return notifier;
            }),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter 1 2 3 4 5 6 (these keys are at Y < 700, so visible without scroll)
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        final keyFinder = find.byKey(ValueKey('numpad_key_$digit'));
        final gesture = await tester.startGesture(tester.getCenter(keyFinder));
        await gesture.up();
        await tester.pump();
      }

      expect(notifier.state.enteredPin, equals('123456'));

      // On 1024x768, the bottom row (CLEAR, 0, DELETE) is at Y ~804.
      // Scroll up by 150px to bring the bottom row cleanly into the visible viewport
      await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -150));
      await tester.pumpAndSettle();

      // Test DELETE
      final deleteFinder = find.byKey(const ValueKey('numpad_action_delete'));
      final deleteGesture = await tester.startGesture(tester.getCenter(deleteFinder));
      await deleteGesture.up();
      await tester.pump();
      expect(notifier.state.enteredPin, equals('12345'));

      // Test CLEAR
      final clearFinder = find.byKey(const ValueKey('numpad_action_clear'));
      final clearGesture = await tester.startGesture(tester.getCenter(clearFinder));
      await clearGesture.up();
      await tester.pump();
      expect(notifier.state.enteredPin, equals(''));
    });

    testWidgets('On compact display 1024x768, scrolling vertically reveals action buttons and allows tap', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authNotifierProvider.overrideWith(
              (ref) => _FakeAdversarialAuthNotifier(ref.watch(authServiceProvider)),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SingleChildScrollView);
      expect(scrollFinder, findsOneWidget);

      // Drag up on scroll view to ensure bottom button is visible
      await tester.drag(scrollFinder, const Offset(0, -300));
      await tester.pumpAndSettle();

      final recoveryFinder = find.byKey(const ValueKey('forgot_pin_button'));
      expect(recoveryFinder, findsOneWidget);

      // Tap recovery button
      await tester.tap(recoveryFinder);
      await tester.pumpAndSettle();

      // PinRecoveryDialog should appear
      expect(find.byType(PinRecoveryDialog), findsOneWidget);
    });

    testWidgets('On compact display in lockout state, scrolling reveals Emergency Override button and opens dialog', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            authNotifierProvider.overrideWith(
              (ref) => _FakeAdversarialAuthNotifier(
                ref.watch(authServiceProvider),
                isLockedOut: true,
                lockoutRemainingSeconds: 300,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollFinder = find.byType(SingleChildScrollView);
      await tester.drag(scrollFinder, const Offset(0, -250));
      await tester.pumpAndSettle();

      final overrideFinder = find.byKey(const ValueKey('emergency_override_button'));
      expect(overrideFinder, findsOneWidget);

      await tester.tap(overrideFinder);
      await tester.pumpAndSettle();

      // Emergency Override dialog should appear
      expect(find.text('Emergency Override'), findsOneWidget);
      expect(find.byKey(const ValueKey('emergency_override_input')), findsOneWidget);
      expect(find.byKey(const ValueKey('emergency_override_submit')), findsOneWidget);
    });
  });
}
