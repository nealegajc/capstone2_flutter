import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/ui/components/update_pin_dialog.dart';

void main() {
  testWidgets('UpdatePinDialog renders 3-step wizard and touch numpad', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkKioskTheme,
        home: const Scaffold(
          body: ProviderScope(
            child: UpdatePinDialog(),
          ),
        ),
      ),
    );

    // Verify dialog header & step indicator
    expect(find.text('Update Owner PIN'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.text('New PIN'), findsOneWidget);
    expect(find.text('Confirm'), findsOneWidget);

    // Verify initial prompt
    expect(find.text('Enter Current Owner PIN'), findsOneWidget);

    // Verify keypad keys
    expect(find.widgetWithText(ElevatedButton, '1'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '9'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '0'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });
}
