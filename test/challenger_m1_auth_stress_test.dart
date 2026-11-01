import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/auth_provider.dart';
import 'package:smart_shelf_linux/providers/kiosk_providers.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Challenge Suite 1: First-Time Setup Flow Adversarial Stress Tests', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initialize(inMemory: true);
    });

    testWidgets('1.1 Mismatched confirmation PIN displays error and resets setup cleanly', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Track layout overflow errors to capture RenderFlex overflow finding
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Step 1: Create Owner PIN badge is visible
      expect(find.text('First-Time Setup: Create Owner PIN'), findsOneWidget);

      // Enter first PIN: 1-2-3-4-5-6
      for (final digit in ['1', '2', '3', '4', '5', '6']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pump();

      // Step 2 indicator must now be shown
      expect(find.text('Step 2: Confirm 6-digit PIN'), findsOneWidget);
      expect(find.text('First-Time Setup: Confirm Owner PIN'), findsOneWidget);

      // Enter mismatched second PIN: 1-2-3-4-5-0
      for (final digit in ['1', '2', '3', '4', '5', '0']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pump();

      // Verify mismatch error is displayed in UI
      expect(find.text('PINs do not match. Please start over.'), findsOneWidget);
      // Badge resets to Step 1
      expect(find.text('First-Time Setup: Create Owner PIN'), findsOneWidget);

      // Verify RenderFlex overflow is resolved (Flexible wraps Text)
      FlutterError.onError = originalOnError;
      final hasOverflowError = errors.any(
        (e) => e.toString().contains('A RenderFlex overflowed'),
      );
      expect(hasOverflowError, isFalse, reason: 'RenderFlex overflow defect detected when error text rendered');

      // Owner PIN must still NOT be set in database
      expect(await sqliteService.isOwnerPinSet(), isFalse);

      // Now enter matching PINs: 9-8-7-6-5-4
      for (final digit in ['9', '8', '7', '6', '5', '4']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pump();

      expect(find.text('Step 2: Confirm 6-digit PIN'), findsOneWidget);

      // Confirm matching PIN
      for (final digit in ['9', '8', '7', '6', '5', '4']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Owner PIN is now committed to SQLite
      expect(await sqliteService.isOwnerPinSet(), isTrue);
      expect(await sqliteService.verifyOwnerPin('987654'), isTrue);
      expect(await sqliteService.verifyOwnerPin('123456'), isFalse);
    });

    testWidgets('1.2 Non-numeric physical keyboard inputs are strictly ignored by UI', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Send non-numeric keys: A, B, Space, Enter, Exclamation
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      // Entered PIN should remain empty
      expect(container.read(authNotifierProvider).enteredPin, isEmpty);

      // Numeric keys should work
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.pump();
      expect(container.read(authNotifierProvider).enteredPin, equals('5'));
    });

    test('1.3 Programmatic non-numeric and malformed PIN validation on SqliteService', () async {
      // Must be strictly 6 digits
      expect(await sqliteService.setInitialOwnerPin('abcdef'), isFalse);
      expect(await sqliteService.setInitialOwnerPin('12a456'), isFalse);
      expect(await sqliteService.setInitialOwnerPin('12345'), isFalse);
      expect(await sqliteService.setInitialOwnerPin('1234567'), isFalse);
      expect(await sqliteService.setInitialOwnerPin('      '), isFalse);
      expect(await sqliteService.setInitialOwnerPin(''), isFalse);
      expect(await sqliteService.isOwnerPinSet(), isFalse);
    });

    testWidgets('1.4 Clear button during Step 2 resets setup state back to Step 1', (
      tester,
    ) async {
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

      // Enter step 1
      for (final digit in ['2', '4', '6', '8', '1', '3']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pump();
      expect(find.text('Step 2: Confirm 6-digit PIN'), findsOneWidget);

      // Hit CLEAR button
      await tester.tap(find.byKey(const ValueKey('numpad_action_clear')));
      await tester.pump();

      // Setup state must reset back to Step 1
      expect(find.text('First-Time Setup: Create Owner PIN'), findsOneWidget);
      expect(find.text('Step 2: Confirm 6-digit PIN'), findsNothing);
    });

    testWidgets('1.5 Rapid multi-tapping does not overflow maximum PIN length', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Rapidly tap digit 1 ten times
      for (int i = 0; i < 10; i++) {
        await tester.tap(find.byKey(const ValueKey('numpad_key_1')));
      }
      await tester.pump();

      // After 6 digits, step 1 finishes, enteredPin cleared for step 2, no overflow
      final entered = container.read(authNotifierProvider).enteredPin;
      expect(entered.length, lessThanOrEqualTo(6));
    });
  });

  group('Challenge Suite 2: Lockout UI & Wall-Clock Persistence Stress Tests', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initialize(inMemory: true);
      await sqliteService.setInitialOwnerPin('555555');
    });

    testWidgets('2.1 Numpad and keyboard inputs are completely disabled during 300s lockout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Trigger 5 failed attempts
      for (int i = 0; i < 5; i++) {
        await sqliteService.verifyOwnerPin('000000');
      }

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(() {
        container.read(authNotifierProvider.notifier).resetLockoutAndState();
        container.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Security Lockout Active'), findsOneWidget);
      expect(container.read(authNotifierProvider).isLockedOut, isTrue);

      // Attempt to tap all digits 0-9
      for (int d = 0; d <= 9; d++) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$d')));
        await tester.pump();
      }
      // Attempt CLEAR and DELETE
      await tester.tap(find.byKey(const ValueKey('numpad_action_clear')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('numpad_action_delete')));
      await tester.pump();

      // Entered pin must strictly remain empty
      expect(container.read(authNotifierProvider).enteredPin, isEmpty);

      // Attempt keyboard inputs
      await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit8);
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(container.read(authNotifierProvider).enteredPin, isEmpty);

      // Clean up timer before finishing test
      container.read(authNotifierProvider.notifier).resetLockoutAndState();
      await tester.pumpAndSettle();
    });

    testWidgets('2.2 Countdown timer accurately decrements and automatically lifts lockout', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set lockout for 5 seconds in SQLite for fast test execution
      final now = DateTime.now().millisecondsSinceEpoch;
      await sqliteService.setSystemSetting('failed_pin_attempts', '5', enqueueSync: false);
      await sqliteService.setSystemSetting('locked_until_epoch', (now + 5000).toString(), enqueueSync: false);

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(() {
        container.read(authNotifierProvider.notifier).resetLockoutAndState();
        container.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(container.read(authNotifierProvider).isLockedOut, isTrue);
      final initialSecs = container.read(authNotifierProvider).lockoutRemainingSeconds;
      expect(initialSecs, greaterThanOrEqualTo(4));

      // Advance by 1 second in Flutter virtual clock
      await tester.pump(const Duration(seconds: 1));
      expect(
        container.read(authNotifierProvider).lockoutRemainingSeconds,
        equals(initialSecs - 1),
      );

      // Advance past remaining time to complete countdown
      await tester.pump(Duration(seconds: initialSecs + 1));
      await tester.pumpAndSettle();

      // In-memory lockout in AuthNotifier is automatically lifted
      expect(container.read(authNotifierProvider).isLockedOut, isFalse);
      expect(find.text('Security Lockout Active'), findsNothing);
      expect(find.text('Enter your 6-digit PIN to unlock the terminal'), findsOneWidget);

      // Sync simulated real time to SQLite so verifyPin passes
      await sqliteService.resetLockout();

      // Can now enter digits and login successfully
      for (final digit in ['5', '5', '5', '5', '5', '5']) {
        await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(container.read(authNotifierProvider).isAuthenticated, isTrue);
    });

    testWidgets('2.3 Lockout survives screen reconstruction and maintains accurate time', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Set lockout for 120 seconds in SQLite
      final now = DateTime.now().millisecondsSinceEpoch;
      await sqliteService.setSystemSetting('failed_pin_attempts', '5', enqueueSync: false);
      await sqliteService.setSystemSetting('locked_until_epoch', (now + 120000).toString(), enqueueSync: false);

      final container = ProviderContainer(
        overrides: [
          sqliteServiceProvider.overrideWithValue(sqliteService),
        ],
      );
      addTearDown(() {
        container.read(authNotifierProvider.notifier).resetLockoutAndState();
        container.dispose();
      });

      // 1. First mount of PinLoginScreen
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Security Lockout Active'), findsOneWidget);
      expect(container.read(authNotifierProvider).isLockedOut, isTrue);

      // 2. Unmount PinLoginScreen (simulate navigation to another screen)
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: Text('Another Screen')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Another Screen'), findsOneWidget);

      // Simulate 10 seconds elapsed in SQLite and advance virtual clock
      await sqliteService.setSystemSetting('locked_until_epoch', (now + 110000).toString(), enqueueSync: false);
      await tester.pump(const Duration(seconds: 10));

      // 3. Remount PinLoginScreen
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Lockout is still active and remaining seconds reflects elapsed time
      expect(find.text('Security Lockout Active'), findsOneWidget);
      expect(container.read(authNotifierProvider).isLockedOut, isTrue);
      expect(container.read(authNotifierProvider).lockoutRemainingSeconds, inInclusiveRange(105, 110));

      container.read(authNotifierProvider.notifier).resetLockoutAndState();
      await tester.pumpAndSettle();
    });

    test('2.4 SQLite wall-clock persistence across app restarts', () async {
      final tempDir = Directory.systemTemp.createTempSync('kiosk_reboot_test_');
      final dbPath = '${tempDir.path}/reboot_test.db';

      // Ensure prior singleton connection is closed
      final svc1 = SqliteService.instance;
      await svc1.close();

      // Instance 1: Trigger lockout
      await svc1.initialize(customPath: dbPath);
      await svc1.setInitialOwnerPin('123456');

      for (int i = 0; i < 5; i++) {
        await svc1.verifyOwnerPin('999999');
      }
      final status1 = await svc1.getLockoutStatus();
      expect(status1.isLockedOut, isTrue);
      expect(status1.remainingSeconds, inInclusiveRange(290, 300));

      // Close instance 1
      await svc1.close();

      // Instance 2: Simulate app restart after 100 seconds
      final rawDb = await databaseFactory.openDatabase(dbPath);
      final now = DateTime.now().millisecondsSinceEpoch;
      await rawDb.update(
        'system_settings',
        {'value': (now + 80000).toString()}, // 80 seconds remaining
        where: 'key = ?',
        whereArgs: ['locked_until_epoch'],
      );
      await rawDb.close();

      await svc1.initialize(customPath: dbPath);
      final status2 = await svc1.getLockoutStatus();
      expect(status2.isLockedOut, isTrue);
      expect(status2.remainingSeconds, inInclusiveRange(75, 82));
      await svc1.close();

      // Instance 3: Simulate app restart after lockout expired
      final rawDb2 = await databaseFactory.openDatabase(dbPath);
      await rawDb2.update(
        'system_settings',
        {'value': (now - 1000).toString()}, // expired in the past
        where: 'key = ?',
        whereArgs: ['locked_until_epoch'],
      );
      await rawDb2.close();

      await svc1.initialize(customPath: dbPath);
      final status3 = await svc1.getLockoutStatus();
      expect(status3.isLockedOut, isFalse);
      expect(status3.remainingSeconds, equals(0));
      expect(status3.failedAttempts, equals(0));

      await svc1.close();
      tempDir.deleteSync(recursive: true);
    });
  });

  group('Challenge Suite 3: Emergency Manager Override Adversarial Tests', () {
    late SqliteService sqliteService;

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initialize(inMemory: true);
      await sqliteService.setInitialOwnerPin('789123');
      // Trigger lockout
      for (int i = 0; i < 5; i++) {
        await sqliteService.verifyOwnerPin('000000');
      }
      expect((await sqliteService.getLockoutStatus()).isLockedOut, isTrue);
      await sqliteService.purgeSyncedQueueItems();
    });

    test('3.1 Whitespace trimming on master recovery key succeeds', () async {
      // Key with leading and trailing spaces and tabs
      final result = await sqliteService.verifyEmergencyManagerOverride(
        '  \t OTTO-MASTER-RECOVERY-2026 \t  \n',
      );
      expect(result, isTrue);

      final status = await sqliteService.getLockoutStatus();
      expect(status.isLockedOut, isFalse);
      expect(status.failedAttempts, equals(0));
    });

    test('3.2 Master recovery key is strictly case-sensitive', () async {
      // Lowercase attempt
      final lowerResult = await sqliteService.verifyEmergencyManagerOverride(
        'otto-master-recovery-2026',
      );
      expect(lowerResult, isFalse);
      expect((await sqliteService.getLockoutStatus()).isLockedOut, isTrue);

      // Mixed case attempt
      final mixedResult = await sqliteService.verifyEmergencyManagerOverride(
        'Otto-Master-Recovery-2026',
      );
      expect(mixedResult, isFalse);
      expect((await sqliteService.getLockoutStatus()).isLockedOut, isTrue);
    });

    test('3.3 Repeated invalid master recovery keys maintain lockout and log OVERRIDE_FAILURE', () async {
      final invalidKeys = [
        'INVALID-1',
        'INCORRECT-KEY-2',
        'WRONG-PASSPHRASE-3',
        '',
        '   ',
      ];

      for (final key in invalidKeys) {
        final res = await sqliteService.verifyEmergencyManagerOverride(key);
        expect(res, isFalse);
        expect((await sqliteService.getLockoutStatus()).isLockedOut, isTrue);
      }

      // Check system_logs for OVERRIDE_FAILURE entries
      final logs = await sqliteService.getSystemLogs(null, limit: 20);
      final failureLogs = logs.where((l) => l.type == 'OVERRIDE_FAILURE').toList();
      // Keys with non-empty trimmed text log OVERRIDE_FAILURE
      expect(failureLogs.length, equals(3));
      for (final l in failureLogs) {
        expect(l.user, equals('Store Manager'));
        expect(l.description, contains('Invalid emergency manager override'));
      }

      // Verify sync_queue contains OVERRIDE_FAILURE entries
      final pending = await sqliteService.getPendingSyncItems(applyBackoff: false);
      final logSyncs = pending.where((p) => p['targetCollection'] == 'system_logs').toList();
      final failureSyncs = logSyncs.where((p) {
        final payload = p['payload'];
        final map = payload is String ? jsonDecode(payload) : payload;
        return map['type'] == 'OVERRIDE_FAILURE';
      }).toList();
      expect(failureSyncs.length, equals(3));
    });

    test('3.4 Successful override creates SECURITY_OVERRIDE audit in SQLite and sync_queue', () async {
      final result = await sqliteService.verifyEmergencyManagerOverride(
        'OTTO-MASTER-RECOVERY-2026',
      );
      expect(result, isTrue);

      // 1. Verify lockout cleared
      final status = await sqliteService.getLockoutStatus();
      expect(status.isLockedOut, isFalse);
      expect(status.failedAttempts, equals(0));

      // 2. Verify SQLite system_logs contains SECURITY_OVERRIDE
      final logs = await sqliteService.getSystemLogs(null, limit: 10);
      final overrideLog = logs.firstWhere(
        (l) => l.type == 'SECURITY_OVERRIDE',
        orElse: () => throw Exception('SECURITY_OVERRIDE missing from system_logs'),
      );
      expect(overrideLog.user, equals('Store Manager'));
      expect(overrideLog.description, contains('Emergency manager override key utilized'));

      // 3. Verify sync_queue contains SECURITY_OVERRIDE
      final pending = await sqliteService.getPendingSyncItems(applyBackoff: false);
      final overrideSync = pending.firstWhere((p) {
        if (p['targetCollection'] != 'system_logs') return false;
        final payload = p['payload'];
        final map = payload is String ? jsonDecode(payload) : payload;
        return map['type'] == 'SECURITY_OVERRIDE';
      }, orElse: () => throw Exception('SECURITY_OVERRIDE missing from sync_queue'));

      expect(overrideSync['operation'], equals('UPSERT'));
      final payload = overrideSync['payload'] is String
          ? jsonDecode(overrideSync['payload'] as String)
          : overrideSync['payload'];
      expect(payload['user'], equals('Store Manager'));
    });
  });
}
