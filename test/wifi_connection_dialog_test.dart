import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/data/services/network_service.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/components/wifi_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WifiConnectionDialog & NetworkService Widget Tests', () {
    testWidgets('Renders Wi-Fi Toggle Switch and Disconnect button when connected to Wi-Fi',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockStatus = NetworkStatus(
        isOnline: true,
        connectionType: 'WiFi',
        currentSsid: 'Test_Office_WiFi',
        interfaceName: 'wlp2s0',
        ipAddress: '192.168.1.50',
        isWifiEnabled: true,
        availableNetworks: const [
          WifiNetwork(
            ssid: 'Test_Office_WiFi',
            signalStrength: 95,
            isConnected: true,
            isSecure: true,
          ),
          WifiNetwork(
            ssid: 'Guest_WiFi',
            signalStrength: 70,
            isConnected: false,
            isSecure: true,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkStatusProvider.overrideWithValue(mockStatus),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const Scaffold(
              body: WifiConnectionDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify title & connected SSID
      expect(find.text('Network & Connectivity Settings'), findsOneWidget);
      expect(find.text('Wi-Fi: Test_Office_WiFi'), findsOneWidget);

      // Verify Wi-Fi toggle switch is present
      expect(find.byType(Switch), findsOneWidget);
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isTrue);

      // Verify Disconnect button is present
      expect(find.text('Disconnect'), findsOneWidget);

      // Verify networks are displayed
      expect(find.text('Guest_WiFi'), findsOneWidget);
      expect(find.text('2 Networks Found'), findsOneWidget);

      // Tap Disconnect and verify confirmation dialog opens
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(find.text('Disconnect Wi-Fi'), findsOneWidget);
      expect(
        find.text('Are you sure you want to disconnect from "Test_Office_WiFi"?'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Renders disabled state when Wi-Fi is toggled off',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const mockStatus = NetworkStatus(
        isOnline: false,
        connectionType: 'Offline',
        isWifiEnabled: false,
        availableNetworks: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            networkStatusProvider.overrideWithValue(mockStatus),
          ],
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const Scaffold(
              body: WifiConnectionDialog(),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Wi-Fi Switch is OFF
      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, isFalse);

      // Verify "Wi-Fi is turned off" disabled empty state
      expect(find.text('Wi-Fi is turned off'), findsOneWidget);
      expect(find.text('Turn On Wi-Fi'), findsOneWidget);
      expect(
        find.text('Enable Wi-Fi to view and connect to nearby networks.'),
        findsOneWidget,
      );

      // Verify Disconnect button is NOT present
      expect(find.text('Disconnect'), findsNothing);
    });
  });
}
