import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';
import 'package:smart_shelf_linux/ui/components/kiosk_numpad.dart';

void main() {
  testWidgets('PinLoginScreen renders branding, title, and touch numpad', (tester) async {
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

    // Verify Brand title & subtitle
    expect(find.text('OTTO SCENTS'), findsOneWidget);
    expect(find.text('Enter Store PIN'), findsOneWidget);

    // Verify Numpad digits are present
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('CLEAR'), findsOneWidget);
    expect(find.text('DELETE'), findsOneWidget);

    // Test entering digits
    await tester.tap(find.text('1'));
    await tester.pump();
    await tester.tap(find.text('2'));
    await tester.pump();

    // Verify CLEAR resets
    await tester.tap(find.text('CLEAR'));
    await tester.pump();
  });
}
