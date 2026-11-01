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

void main() {
  group('R3: Login Screen Touch Responsiveness & Zero-Latency Numpad', () {
    testWidgets(
      'Immediate pointer down invocation on raw pointer events (without waiting for pointer up)',
      (tester) async {
        String? pressedDigit;
        bool clearPressed = false;
        bool deletePressed = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (digit) => pressedDigit = digit,
                  onClearPressed: () => clearPressed = true,
                  onDeletePressed: () => deletePressed = true,
                ),
              ),
            ),
          ),
        );

        // 1. Verify digit triggers immediately on PointerDownEvent
        final digit5Finder = find.text('5');
        expect(digit5Finder, findsOneWidget);

        final digitGesture = await tester.startGesture(tester.getCenter(digit5Finder));
        // Crucial: verify BEFORE gesture.up() is called
        expect(
          pressedDigit,
          equals('5'),
          reason: 'Digit must register immediately on pointer down with zero latency',
        );
        await digitGesture.up();
        await tester.pump();

        // 2. Verify CLEAR triggers immediately on PointerDownEvent
        final clearFinder = find.byKey(const ValueKey('numpad_action_clear'));
        expect(clearFinder, findsOneWidget);

        final clearGesture = await tester.startGesture(tester.getCenter(clearFinder));
        expect(
          clearPressed,
          isTrue,
          reason: 'CLEAR action must register immediately on pointer down',
        );
        await clearGesture.up();
        await tester.pump();

        // 3. Verify DELETE triggers immediately on PointerDownEvent
        final deleteFinder = find.byKey(const ValueKey('numpad_action_delete'));
        expect(deleteFinder, findsOneWidget);

        final deleteGesture = await tester.startGesture(tester.getCenter(deleteFinder));
        expect(
          deletePressed,
          isTrue,
          reason: 'DELETE action must register immediately on pointer down',
        );
        await deleteGesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'Pointer move events / touch jitter exceeding touch slop do NOT drop touches',
      (tester) async {
        final pressedDigits = <String>[];
        int clearCount = 0;
        int deleteCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (digit) => pressedDigits.add(digit),
                  onClearPressed: () => clearCount++,
                  onDeletePressed: () => deleteCount++,
                ),
              ),
            ),
          ),
        );

        // Flutter default kTouchSlop is 18.0 logical pixels.
        // Simulate real-world kiosk touchscreen touch: finger squish, centroid drift, or drag > 18px
        final digit8Finder = find.text('8');
        final gesture = await tester.startGesture(tester.getCenter(digit8Finder));

        // Move beyond kTouchSlop (total > 35px drag)
        await gesture.moveBy(const Offset(25, 10));
        await gesture.moveBy(const Offset(-10, 15));

        // Release finger
        await gesture.up();
        await tester.pump();

        expect(
          pressedDigits,
          equals(['8']),
          reason: 'Touch jitter/drag exceeding slop must not drop the touch registration',
        );

        // Also test CLEAR action under slop jitter
        final clearGesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_action_clear'))),
        );
        await clearGesture.moveBy(const Offset(30, -15));
        await clearGesture.up();
        await tester.pump();

        expect(clearCount, equals(1));

        // Also test DELETE action under slop jitter
        final deleteGesture = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_action_delete'))),
        );
        await deleteGesture.moveBy(const Offset(-25, 20));
        await deleteGesture.up();
        await tester.pump();

        expect(deleteCount, equals(1));
      },
    );

    testWidgets(
      'Numpad digit font size (32px bold) and key height (>= 88px)',
      (tester) async {
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

        // Verify digits 0 through 9
        for (int i = 0; i <= 9; i++) {
          final digitStr = '$i';
          final textFinder = find.text(digitStr);
          expect(textFinder, findsOneWidget);

          final Text textWidget = tester.widget<Text>(textFinder);
          expect(
            textWidget.style?.fontSize,
            equals(32.0),
            reason: 'Digit $digitStr must have fontSize 32',
          );
          expect(
            textWidget.style?.fontWeight,
            equals(FontWeight.w800),
            reason: 'Digit $digitStr must have FontWeight.w800 (bold)',
          );

          final keyFinder = find.byKey(ValueKey('numpad_key_$digitStr'));
          final keySize = tester.getSize(keyFinder);
          expect(
            keySize.height,
            greaterThanOrEqualTo(88.0),
            reason: 'Digit $digitStr key height must be >= 88px',
          );
        }
      },
    );

    testWidgets(
      'CLEAR and DELETE labels (16px bold) and icons (>= 28px)',
      (tester) async {
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

        // Verify CLEAR key
        final clearKeyFinder = find.byKey(const ValueKey('numpad_action_clear'));
        expect(clearKeyFinder, findsOneWidget);
        expect(
          tester.getSize(clearKeyFinder).height,
          greaterThanOrEqualTo(88.0),
          reason: 'CLEAR key height must be >= 88px',
        );

        final clearText = tester.widget<Text>(
          find.descendant(of: clearKeyFinder, matching: find.text('CLEAR')),
        );
        expect(clearText.style?.fontSize, equals(16.0));
        expect(clearText.style?.fontWeight, equals(FontWeight.w800));

        final clearIcon = tester.widget<Icon>(
          find.descendant(of: clearKeyFinder, matching: find.byType(Icon)),
        );
        expect(
          clearIcon.size,
          greaterThanOrEqualTo(28.0),
          reason: 'CLEAR icon size must be >= 28px',
        );

        // Verify DELETE key
        final deleteKeyFinder = find.byKey(const ValueKey('numpad_action_delete'));
        expect(deleteKeyFinder, findsOneWidget);
        expect(
          tester.getSize(deleteKeyFinder).height,
          greaterThanOrEqualTo(88.0),
          reason: 'DELETE key height must be >= 88px',
        );

        final deleteText = tester.widget<Text>(
          find.descendant(of: deleteKeyFinder, matching: find.text('DELETE')),
        );
        expect(deleteText.style?.fontSize, equals(16.0));
        expect(deleteText.style?.fontWeight, equals(FontWeight.w800));

        final deleteIcon = tester.widget<Icon>(
          find.descendant(of: deleteKeyFinder, matching: find.byType(Icon)),
        );
        expect(
          deleteIcon.size,
          greaterThanOrEqualTo(28.0),
          reason: 'DELETE icon size must be >= 28px',
        );
      },
    );

    testWidgets(
      'PIN dots indicator dimensions (28–32px) and spacing',
      (tester) async {
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

        final dotContainers = tester.widgetList<AnimatedContainer>(
          find.descendant(
            of: find.byType(PinDotsIndicator),
            matching: find.byType(AnimatedContainer),
          ),
        ).toList();

        expect(dotContainers.length, equals(6));

        // First 2 dots are filled (enteredLength: 2) -> 32px diameter
        for (int i = 0; i < 2; i++) {
          final dot = dotContainers[i];
          expect(dot.constraints?.minWidth ?? 0.0, equals(32.0));
          expect(dot.constraints?.minHeight ?? 0.0, equals(32.0));
          expect(dot.margin, equals(const EdgeInsets.symmetric(horizontal: 12)));

          final decoration = dot.decoration as BoxDecoration;
          expect(decoration.shape, equals(BoxShape.circle));
          final border = decoration.border as Border;
          expect(border.top.width, greaterThanOrEqualTo(2.5));
          expect(border.top.width, lessThanOrEqualTo(3.0));

          // Check enhanced glow shadow on filled dots
          expect(decoration.boxShadow, isNotNull);
          final shadow = decoration.boxShadow!.first;
          expect(shadow.blurRadius, equals(12.0));
          expect(shadow.spreadRadius, equals(1.5));
        }

        // Remaining 4 dots are unfilled -> 28px diameter
        for (int i = 2; i < 6; i++) {
          final dot = dotContainers[i];
          expect(dot.constraints?.minWidth ?? 0.0, equals(28.0));
          expect(dot.constraints?.minHeight ?? 0.0, equals(28.0));
          expect(dot.margin, equals(const EdgeInsets.symmetric(horizontal: 12)));

          final decoration = dot.decoration as BoxDecoration;
          expect(decoration.shape, equals(BoxShape.circle));
          final border = decoration.border as Border;
          expect(border.top.width, greaterThanOrEqualTo(2.5));
          expect(border.top.width, lessThanOrEqualTo(3.0));
        }
      },
    );

    testWidgets(
      'Recovery button touch target (>= 56px height, full width)',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final recoveryButtonFinder = find.byKey(const ValueKey('forgot_pin_button'));
        expect(recoveryButtonFinder, findsOneWidget);

        final recoverySize = tester.getSize(recoveryButtonFinder);
        expect(
          recoverySize.height,
          greaterThanOrEqualTo(56.0),
          reason: 'Recovery button height must be >= 56px',
        );
        expect(
          recoverySize.width,
          greaterThanOrEqualTo(400.0),
          reason: 'Recovery button must expand across full width of card',
        );
      },
    );

    testWidgets(
      'Emergency Override button touch target (>= 56px height, full width)',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

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

        final overrideButtonFinder = find.byKey(const ValueKey('emergency_override_button'));
        expect(overrideButtonFinder, findsOneWidget);

        final overrideSize = tester.getSize(overrideButtonFinder);
        expect(
          overrideSize.height,
          greaterThanOrEqualTo(56.0),
          reason: 'Emergency Override button height must be >= 56px',
        );
        expect(
          overrideSize.width,
          greaterThanOrEqualTo(400.0),
          reason: 'Emergency Override button must expand across full width of card',
        );

        final elevatedBtn = tester.widget<ElevatedButton>(overrideButtonFinder);
        expect(
          elevatedBtn.style?.minimumSize?.resolve({})?.height,
          greaterThanOrEqualTo(58.0),
          reason: 'Emergency Override button minimumSize height must be >= 58px',
        );
      },
    );
  });
}
