import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/data/models/auth_state.dart';
import 'package:smart_shelf_linux/providers/api_provider.dart';
import 'package:smart_shelf_linux/providers/auth_provider.dart';
import 'package:smart_shelf_linux/ui/components/kiosk_numpad.dart';
import 'package:smart_shelf_linux/ui/components/pin_dots_indicator.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';

class _FakeLockedOutAuthNotifier extends AuthNotifier {
  _FakeLockedOutAuthNotifier(super.authService) {
    state = const AuthState(isLockedOut: true, lockoutRemainingSeconds: 300);
  }

  @override
  Future<void> checkKioskLockout() async {
    state = const AuthState(isLockedOut: true, lockoutRemainingSeconds: 300);
  }
}

class _FakeNormalAuthNotifier extends AuthNotifier {
  _FakeNormalAuthNotifier(super.authService, {String enteredPin = ''}) {
    state = AuthState(enteredPin: enteredPin);
  }

  @override
  Future<void> checkKioskLockout() async {
    // Normal unlocked
  }
}

void main() {
  final targetResolutions = [
    const Size(1920, 1200),
    const Size(1280, 800),
    const Size(1024, 768),
  ];

  group('Milestone 3 Empirical Verification: Sizing, Hitboxes & Responsive Layout', () {
    testWidgets('Numpad key heights >= 88px, digit fontSize == 32px, FontWeight.w800', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkKioskTheme,
          home: Scaffold(
            body: Center(
              child: KioskNumpad(
                onDigitPressed: (_) {},
                onClearPressed: () {},
                onDeletePressed: () {},
              ),
            ),
          ),
        ),
      );

      for (int i = 0; i <= 9; i++) {
        final digitStr = '$i';
        final textFinder = find.text(digitStr);
        expect(textFinder, findsOneWidget);
        final textWidget = tester.widget<Text>(textFinder);
        expect(textWidget.style?.fontSize, equals(32.0), reason: 'Digit $digitStr must have fontSize 32');
        expect(textWidget.style?.fontWeight, equals(FontWeight.w800), reason: 'Digit $digitStr must have FontWeight.w800');

        final keyFinder = find.byKey(ValueKey('numpad_key_$digitStr'));
        final keySize = tester.getSize(keyFinder);
        expect(keySize.height, greaterThanOrEqualTo(88.0), reason: 'Digit $digitStr key height must be >= 88px');
      }
    });

    testWidgets('Action keys: Icons >= 28px, labels == 16px with FontWeight.w800, heights >= 88px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkKioskTheme,
          home: Scaffold(
            body: Center(
              child: KioskNumpad(
                onDigitPressed: (_) {},
                onClearPressed: () {},
                onDeletePressed: () {},
              ),
            ),
          ),
        ),
      );

      // CLEAR
      final clearKeyFinder = find.byKey(const ValueKey('numpad_action_clear'));
      expect(clearKeyFinder, findsOneWidget);
      expect(tester.getSize(clearKeyFinder).height, greaterThanOrEqualTo(88.0));
      final clearText = tester.widget<Text>(find.descendant(of: clearKeyFinder, matching: find.text('CLEAR')));
      expect(clearText.style?.fontSize, equals(16.0));
      expect(clearText.style?.fontWeight, equals(FontWeight.w800));
      final clearIcon = tester.widget<Icon>(find.descendant(of: clearKeyFinder, matching: find.byType(Icon)));
      expect(clearIcon.size, greaterThanOrEqualTo(28.0));

      // DELETE
      final deleteKeyFinder = find.byKey(const ValueKey('numpad_action_delete'));
      expect(deleteKeyFinder, findsOneWidget);
      expect(tester.getSize(deleteKeyFinder).height, greaterThanOrEqualTo(88.0));
      final deleteText = tester.widget<Text>(find.descendant(of: deleteKeyFinder, matching: find.text('DELETE')));
      expect(deleteText.style?.fontSize, equals(16.0));
      expect(deleteText.style?.fontWeight, equals(FontWeight.w800));
      final deleteIcon = tester.widget<Icon>(find.descendant(of: deleteKeyFinder, matching: find.byType(Icon)));
      expect(deleteIcon.size, greaterThanOrEqualTo(28.0));
    });

    testWidgets('PIN dots diameters: unfilled == 28px, filled == 32px', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkKioskTheme,
          home: const Scaffold(
            body: Center(
              child: PinDotsIndicator(
                pinLength: 6,
                enteredLength: 3,
              ),
            ),
          ),
        ),
      );

      final dotContainers = tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: find.byType(PinDotsIndicator),
          matching: find.byType(AnimatedContainer),
        ),
      ).toList();

      expect(dotContainers.length, equals(6));

      // 3 filled dots -> 32px diameter
      for (int i = 0; i < 3; i++) {
        final dot = dotContainers[i];
        expect(dot.constraints?.minWidth, equals(32.0), reason: 'Filled dot minWidth must be 32px');
        expect(dot.constraints?.minHeight, equals(32.0), reason: 'Filled dot minHeight must be 32px');
      }

      // 3 unfilled dots -> 28px diameter
      for (int i = 3; i < 6; i++) {
        final dot = dotContainers[i];
        expect(dot.constraints?.minWidth, equals(28.0), reason: 'Unfilled dot minWidth must be 28px');
        expect(dot.constraints?.minHeight, equals(28.0), reason: 'Unfilled dot minHeight must be 28px');
      }
    });

    for (final res in targetResolutions) {
      testWidgets('Hitbox verification at ${res.width.toInt()}x${res.height.toInt()}: Recovery button & Override button >= 56px', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Test normal state recovery button
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeNormalAuthNotifier(ref.watch(authServiceProvider)),
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
        expect(recoverySize.height, greaterThanOrEqualTo(56.0), reason: 'Recovery button height >= 56px');
        expect(recoverySize.width, greaterThanOrEqualTo(400.0), reason: 'Recovery button width spans card');

        // Test lockout state override button
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeLockedOutAuthNotifier(ref.watch(authServiceProvider)),
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
        expect(overrideSize.height, greaterThanOrEqualTo(56.0), reason: 'Override button height >= 56px');
        expect(overrideSize.width, greaterThanOrEqualTo(400.0), reason: 'Override button width spans card');
      });

      testWidgets('Zero layout overflow verification at ${res.width.toInt()}x${res.height.toInt()} (unlocked and locked)', (tester) async {
        tester.view.physicalSize = res;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        // Normal state
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeNormalAuthNotifier(ref.watch(authServiceProvider)),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final normalException = tester.takeException();
        expect(normalException, isNull, reason: 'RenderFlex must not overflow at resolution $res in normal state');

        // Lockout state
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              authNotifierProvider.overrideWith(
                (ref) => _FakeLockedOutAuthNotifier(ref.watch(authServiceProvider)),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lockoutException = tester.takeException();
        expect(lockoutException, isNull, reason: 'RenderFlex must not overflow at resolution $res in lockout state');
      });
    }
  });
}
