import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/ui/components/kiosk_numpad.dart';
import 'package:smart_shelf_linux/ui/components/pin_dots_indicator.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';

void main() {
  group('Empirical Challenger M3.6.1: Login Screen Touch Responsiveness Stress Tests', () {
    // ------------------------------------------------------------------------
    // CHALLENGE 1: Zero-latency PointerDown on all 10 digits and action buttons
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 1: All 10 digits and action buttons trigger callback immediately on down() before up()',
      (tester) async {
        final registeredEvents = <String>[];
        int clearCount = 0;
        int deleteCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (d) => registeredEvents.add('digit_$d'),
                  onClearPressed: () => clearCount++,
                  onDeletePressed: () => deleteCount++,
                ),
              ),
            ),
          ),
        );

        // Test every digit '0' through '9'
        for (int i = 0; i <= 9; i++) {
          final digitStr = '$i';
          final keyFinder = find.byKey(ValueKey('numpad_key_$digitStr'));
          expect(keyFinder, findsOneWidget);

          final gesture = await tester.startGesture(tester.getCenter(keyFinder));

          // Empirical verification: assert BEFORE gesture.up()
          expect(
            registeredEvents.contains('digit_$digitStr'),
            isTrue,
            reason: 'Digit $digitStr MUST fire callback on pointer down before pointer up',
          );

          await gesture.up();
          await tester.pump();
        }

        expect(registeredEvents.length, equals(10));

        // Test CLEAR action key
        final clearFinder = find.byKey(const ValueKey('numpad_action_clear'));
        final clearGesture = await tester.startGesture(tester.getCenter(clearFinder));
        expect(
          clearCount,
          equals(1),
          reason: 'CLEAR MUST fire callback on pointer down before pointer up',
        );
        await clearGesture.up();
        await tester.pump();

        // Test DELETE action key
        final deleteFinder = find.byKey(const ValueKey('numpad_action_delete'));
        final deleteGesture = await tester.startGesture(tester.getCenter(deleteFinder));
        expect(
          deleteCount,
          equals(1),
          reason: 'DELETE MUST fire callback on pointer down before pointer up',
        );
        await deleteGesture.up();
        await tester.pump();
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 2: Finger movement exceeding kTouchSlop (50px, 80px, 120px drags)
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 2: Finger drags exceeding kTouchSlop (50px-120px) do NOT drop or cancel digits',
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
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () => clearCount++,
                  onDeletePressed: () => deleteCount++,
                ),
              ),
            ),
          ),
        );

        // Case A: 50px horizontal drag on digit '4' (Flutter kTouchSlop is 18px)
        final key4Finder = find.byKey(const ValueKey('numpad_key_4'));
        final gesture4 = await tester.startGesture(tester.getCenter(key4Finder));
        await gesture4.moveBy(const Offset(50, 0));
        await gesture4.up();
        await tester.pump();

        expect(
          pressedDigits,
          equals(['4']),
          reason: '50px horizontal drag must not drop digit 4 or cause duplicates',
        );

        // Case B: 80px diagonal drag on digit '8' (cross-row movement)
        final key8Finder = find.byKey(const ValueKey('numpad_key_8'));
        final gesture8 = await tester.startGesture(tester.getCenter(key8Finder));
        await gesture8.moveBy(const Offset(50, -60)); // total > 78px
        await gesture8.up();
        await tester.pump();

        expect(
          pressedDigits,
          equals(['4', '8']),
          reason: '80px diagonal drag must not drop digit 8 or cause duplicates',
        );

        // Case C: 120px drag across neighboring keys and outside numpad
        // Down on '7', drag horizontally across '8' and '9' and release
        final key7Finder = find.byKey(const ValueKey('numpad_key_7'));
        final gesture7 = await tester.startGesture(tester.getCenter(key7Finder));
        await gesture7.moveBy(const Offset(120, 0));
        await gesture7.up();
        await tester.pump();

        expect(
          pressedDigits,
          equals(['4', '8', '7']),
          reason: '120px drag starting on 7 must register 7 and MUST NOT falsely trigger keys 8 or 9',
        );

        // Case D: 50px drag on CLEAR button
        final clearFinder = find.byKey(const ValueKey('numpad_action_clear'));
        final clearGesture = await tester.startGesture(tester.getCenter(clearFinder));
        await clearGesture.moveBy(const Offset(35, 35)); // 50px diagonal drag
        await clearGesture.up();
        await tester.pump();

        expect(
          clearCount,
          equals(1),
          reason: '50px drag on CLEAR must not cancel action',
        );

        // Case E: 60px vertical drag on DELETE button
        final deleteFinder = find.byKey(const ValueKey('numpad_action_delete'));
        final deleteGesture = await tester.startGesture(tester.getCenter(deleteFinder));
        await deleteGesture.moveBy(const Offset(0, -60));
        await deleteGesture.up();
        await tester.pump();

        expect(
          deleteCount,
          equals(1),
          reason: '60px vertical drag on DELETE must not cancel action',
        );
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 3: Multi-finger rapid sequential & interleaved taps (Two-Thumb Entry)
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 3: Multi-finger rapid sequential and overlapping taps register accurately without dropped digits',
      (tester) async {
        final pressedDigits = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () {},
                  onDeletePressed: () {},
                ),
              ),
            ),
          ),
        );

        // Simulate high-speed cashier entry where Finger 2 touches down
        // BEFORE Finger 1 is lifted (interleaved / overlapping touches):
        // 1. Pointer 1 down on '1'
        final p1 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_1'))),
          pointer: 1,
        );
        expect(pressedDigits, equals(['1']));

        // 2. Pointer 2 down on '2' while Pointer 1 is still down!
        final p2 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_2'))),
          pointer: 2,
        );
        expect(pressedDigits, equals(['1', '2']));

        // 3. Pointer 1 lifts, Pointer 3 downs on '3' while Pointer 2 is still down
        await p1.up();
        final p3 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_3'))),
          pointer: 3,
        );
        expect(pressedDigits, equals(['1', '2', '3']));

        // 4. Pointer 2 lifts, Pointer 4 downs on '4' while Pointer 3 is still down
        await p2.up();
        final p4 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_4'))),
          pointer: 4,
        );
        expect(pressedDigits, equals(['1', '2', '3', '4']));

        // Clean up remaining touches
        await p3.up();
        await p4.up();
        await tester.pump();

        expect(
          pressedDigits,
          equals(['1', '2', '3', '4']),
          reason: 'Interleaved multi-finger touches must register every single digit with zero drops',
        );

        // Rapid 6-digit burst sequence: '9', '8', '7', '6', '5', '4'
        pressedDigits.clear();
        final burstDigits = ['9', '8', '7', '6', '5', '4'];
        TestGesture? previousPointer;

        for (int i = 0; i < burstDigits.length; i++) {
          final digit = burstDigits[i];
          final currentPointer = await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey('numpad_key_$digit'))),
            pointer: 10 + i,
          );
          // Overlap: release previous pointer only after next pointer is down
          if (previousPointer != null) {
            await previousPointer.up();
          }
          previousPointer = currentPointer;
        }
        if (previousPointer != null) {
          await previousPointer.up();
        }
        await tester.pump();

        expect(
          pressedDigits,
          equals(burstDigits),
          reason: '6-digit high-speed burst entry with overlapping touches must register all digits',
        );
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 4: Simultaneous concurrent multi-touch down (same frame)
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 4: Simultaneous concurrent multi-touch down events register both digits',
      (tester) async {
        final pressedDigits = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () {},
                  onDeletePressed: () {},
                ),
              ),
            ),
          ),
        );

        // Two fingers hit screen simultaneously on '3' and '7'
        final f1 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_3'))),
          pointer: 101,
        );
        final f2 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_7'))),
          pointer: 102,
        );

        await f1.up();
        await f2.up();
        await tester.pump();

        expect(pressedDigits.length, equals(2));
        expect(pressedDigits.contains('3'), isTrue);
        expect(pressedDigits.contains('7'), isTrue);
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 5: PointerCancelEvent resilience (OS/Framework gesture cancel)
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 5: PointerCancelEvent does not revert registered digits and resets pressed state',
      (tester) async {
        final pressedDigits = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () {},
                  onDeletePressed: () {},
                ),
              ),
            ),
          ),
        );

        final key6Finder = find.byKey(const ValueKey('numpad_key_6'));
        final gesture = await tester.startGesture(tester.getCenter(key6Finder));

        expect(pressedDigits, equals(['6']));

        // OS sends PointerCancelEvent (e.g. system gesture conflict or palm rejection)
        await gesture.cancel();
        await tester.pump();

        // Digit must remain registered!
        expect(
          pressedDigits,
          equals(['6']),
          reason: 'Pointer cancel must not remove or revert registered digit',
        );
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 6: PinLoginScreen End-to-End Real-World Touch Slop & Zero Latency
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 6: PinLoginScreen dots indicator updates immediately on down() and survives 50px drag',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: AppTheme.darkKioskTheme,
              home: const PinLoginScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initial state: 0 dots entered
        expect(
          tester.widget<PinDotsIndicator>(find.byType(PinDotsIndicator)).enteredLength,
          equals(0),
        );

        // 1. Touch down on digit '1'
        final key1 = find.byKey(const ValueKey('numpad_key_1'));
        final g1 = await tester.startGesture(tester.getCenter(key1));
        await tester.pump();

        // Must update to 1 dot BEFORE pointer up
        expect(
          tester.widget<PinDotsIndicator>(find.byType(PinDotsIndicator)).enteredLength,
          equals(1),
          reason: 'Indicator dots must reflect pressed digit immediately on down',
        );

        // 2. Drag 50px while holding down
        await g1.moveBy(const Offset(50, 0));
        await tester.pump();

        expect(
          tester.widget<PinDotsIndicator>(find.byType(PinDotsIndicator)).enteredLength,
          equals(1),
          reason: '50px drag must not cancel or drop entered dot',
        );

        await g1.up();
        await tester.pump();

        // 3. Enter digits 2, 3, 4, 5, 6 with rapid sequential touches
        final remainingDigits = ['2', '3', '4', '5', '6'];
        for (int i = 0; i < remainingDigits.length; i++) {
          final d = remainingDigits[i];
          final g = await tester.startGesture(
            tester.getCenter(find.byKey(ValueKey('numpad_key_$d'))),
            pointer: 200 + i,
          );
          await g.up();
          await tester.pump();
        }

        // Full 6 digits entered
        expect(
          tester.widget<PinDotsIndicator>(find.byType(PinDotsIndicator)).enteredLength,
          equals(6),
          reason: 'All 6 digits entered successfully without any dropped digits',
        );
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 7: Interleaved Multi-Finger DELETE and CLEAR Actions
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 7: Multi-finger simultaneous digit hold and DELETE/CLEAR triggers accurately',
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
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () => clearCount++,
                  onDeletePressed: () => deleteCount++,
                ),
              ),
            ),
          ),
        );

        // Finger 1 touches and holds '9'
        final f1 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_key_9'))),
          pointer: 1,
        );
        expect(pressedDigits, equals(['9']));

        // Finger 2 taps DELETE while Finger 1 is still holding '9'
        final f2 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_action_delete'))),
          pointer: 2,
        );
        expect(deleteCount, equals(1));
        await f2.up();

        // Finger 2 taps CLEAR while Finger 1 is still holding '9'
        final f3 = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('numpad_action_clear'))),
          pointer: 3,
        );
        expect(clearCount, equals(1));
        await f3.up();

        await f1.up();
        await tester.pump();
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 8: Disabled State (Lockout/Loading) Absolute Immunity
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 8: Disabled numpad completely rejects pointer down, 50px drags, and multi-touch',
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
                  isEnabled: false, // Disabled during lockout or verifying
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () => clearCount++,
                  onDeletePressed: () => deleteCount++,
                ),
              ),
            ),
          ),
        );

        // Attempt pointer down on key '5'
        final key5 = find.byKey(const ValueKey('numpad_key_5'));
        final g = await tester.startGesture(tester.getCenter(key5));
        await g.moveBy(const Offset(50, 0));
        await g.up();

        // Attempt action keys
        final clearKey = find.byKey(const ValueKey('numpad_action_clear'));
        final gClear = await tester.startGesture(tester.getCenter(clearKey));
        await gClear.up();

        final deleteKey = find.byKey(const ValueKey('numpad_action_delete'));
        final gDelete = await tester.startGesture(tester.getCenter(deleteKey));
        await gDelete.up();

        await tester.pump();

        expect(pressedDigits, isEmpty, reason: 'Disabled numpad must not register any digits');
        expect(clearCount, equals(0), reason: 'Disabled numpad must not trigger CLEAR');
        expect(deleteCount, equals(0), reason: 'Disabled numpad must not trigger DELETE');
      },
    );

    // ------------------------------------------------------------------------
    // CHALLENGE 9: Boundary & Corner Hit-Testing Resilience
    // ------------------------------------------------------------------------
    testWidgets(
      'Adversarial 9: Corner edge touches within 88px key boundary trigger immediately',
      (tester) async {
        final pressedDigits = <String>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: Scaffold(
              body: Center(
                child: KioskNumpad(
                  onDigitPressed: (d) => pressedDigits.add(d),
                  onClearPressed: () {},
                  onDeletePressed: () {},
                ),
              ),
            ),
          ),
        );

        final key5 = find.byKey(const ValueKey('numpad_key_5'));
        final rect = tester.getRect(key5);

        // Tap top-left edge (+10, +10 inside key container)
        final topLeft = rect.topLeft + const Offset(10, 10);
        final g1 = await tester.startGesture(topLeft);
        expect(pressedDigits, equals(['5']));
        await g1.up();
        await tester.pump();

        // Tap bottom-right edge (-10, -10 inside key container)
        final bottomRight = rect.bottomRight - const Offset(10, 10);
        final g2 = await tester.startGesture(bottomRight);
        expect(pressedDigits, equals(['5', '5']));
        await g2.up();
        await tester.pump();
      },
    );
  });
}
