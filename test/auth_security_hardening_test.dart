import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/core/theme/app_theme.dart';
import 'package:smart_shelf_linux/data/services/auth_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/ui/screens/auth/pin_login_screen.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Requirement 1.1 — PBKDF2-HMAC-SHA256 & Salt Hardening', () {
    test('Matches standard RFC test vectors for PBKDF2-HMAC-SHA256', () {
      final key1 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 1,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(key1),
        equals(
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
        ),
      );

      final key2 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 2,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(key2),
        equals(
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
        ),
      );

      final key4096 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 4096,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(key4096),
        equals(
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
        ),
      );
    });

    test('Generates cryptographically secure 32-byte salt in system_settings', () async {
      final service = SqliteService.instance;
      await service.initialize(inMemory: true);

      final saltBytes = await service.getKioskSaltBytes();
      expect(saltBytes.length, equals(32));

      final storedSaltHex = await service.getSetting('kiosk_auth_salt');
      expect(storedSaltHex, isNotNull);
      expect(storedSaltHex!.length, equals(64));
      expect(Pbkdf2Auth.toHex(saltBytes), equals(storedSaltHex));
    });

    test('Different salts produce distinct derived keys for identical PINs', () {
      final salt1 = Pbkdf2Auth.generateSalt(32);
      final salt2 = Pbkdf2Auth.generateSalt(32);

      final hash1 = Pbkdf2Auth.hashPin('948201', salt1, iterations: 1000);
      final hash2 = Pbkdf2Auth.hashPin('948201', salt2, iterations: 1000);

      expect(hash1, isNot(equals(hash2)));
    });
  });

  group('Requirement 1.2 — Universal Fallback PIN Elimination & First-Time Setup', () {
    late SqliteService service;

    setUp(() async {
      service = SqliteService.instance;
      await service.initialize(inMemory: true);
    });

    test('Fresh kiosk database has no owner PIN and rejects 123456 fallback', () async {
      expect(await service.isOwnerPinSet(), isFalse);
      expect(await service.verifyOwnerPin('123456'), isFalse);
    });

    test('First-time setup configures PBKDF2 owner PIN, updates users table, and rejects 123456', () async {
      final setupSuccess = await service.setInitialOwnerPin('741852');
      expect(setupSuccess, isTrue);
      expect(await service.isOwnerPinSet(), isTrue);

      // Verify correct PIN passes
      expect(await service.verifyOwnerPin('741852'), isTrue);

      // Verify default 123456 strictly fails
      expect(await service.verifyOwnerPin('123456'), isFalse);

      // Verify admin user passwordHash in SQLite matches PBKDF2 hash
      final adminCreds = await service.getUserWithCredentials('admin@ottoscents.com');
      expect(adminCreds, isNotNull);
      final saltBytes = await service.getKioskSaltBytes();
      final expectedHash = Pbkdf2Auth.hashPin('741852', saltBytes);
      expect(adminCreds!['passwordHash'], equals(expectedHash));
    });
  });

  group('Requirement 1.3 — Persistent Brute-Force Lockout Across Reboots', () {
    late String tempDbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp.createTempSync('kiosk_lockout_test_');
      tempDbPath = '${tempDir.path}/lockout_test.db';
      await SqliteService.instance.close();
    });

    test('5 consecutive failed PIN attempts triggers 300s persistent lockout that survives restart', () async {
      // 1. Open database and setup PIN
      final service1 = SqliteService.instance;
      await service1.initialize(customPath: tempDbPath);
      await service1.setInitialOwnerPin('369258');

      // 2. Perform 4 failed attempts
      for (int i = 0; i < 4; i++) {
        final res = await service1.verifyOwnerPin('000000');
        expect(res, isFalse);
        final status = await service1.getLockoutStatus();
        expect(status.isLockedOut, isFalse);
        expect(status.failedAttempts, equals(i + 1));
      }

      // 3. Perform 5th failed attempt -> triggers 300s lockout
      final res5 = await service1.verifyOwnerPin('000000');
      expect(res5, isFalse);

      final statusAfter5 = await service1.getLockoutStatus();
      expect(statusAfter5.isLockedOut, isTrue);
      expect(statusAfter5.remainingSeconds, greaterThan(290));
      expect(statusAfter5.remainingSeconds, lessThanOrEqualTo(300));
      expect(statusAfter5.failedAttempts, equals(5));

      // Correct PIN must now be rejected while locked out
      expect(await service1.verifyOwnerPin('369258'), isFalse);

      // 4. Simulate application reboot: close database and re-open new instance from disk
      await service1.close();

      // Open new connection to the same SQLite file
      final rawDb = await databaseFactory.openDatabase(tempDbPath);
      final lockoutSetting = await rawDb.query(
        'system_settings',
        where: 'key = ?',
        whereArgs: ['locked_until_epoch'],
      );
      expect(lockoutSetting.isNotEmpty, isTrue);
      final lockedUntilEpoch = int.parse(lockoutSetting.first['value'] as String);
      final now = DateTime.now().millisecondsSinceEpoch;
      expect(lockedUntilEpoch, greaterThan(now));
      await rawDb.close();

      // Re-initialize service against the persisted database
      await service1.initialize(customPath: tempDbPath);
      final persistedStatus = await service1.getLockoutStatus();
      expect(persistedStatus.isLockedOut, isTrue);
      expect(persistedStatus.remainingSeconds, greaterThan(280));
      expect(persistedStatus.failedAttempts, equals(5));

      // 5. Emergency reset clears lockout
      await service1.resetLockout();
      final clearedStatus = await service1.getLockoutStatus();
      expect(clearedStatus.isLockedOut, isFalse);
      expect(clearedStatus.remainingSeconds, equals(0));
      expect(clearedStatus.failedAttempts, equals(0));

      // Login now succeeds with correct PIN
      expect(await service1.verifyOwnerPin('369258'), isTrue);

      await service1.close();
    });
  });

  group('Requirement 1.4 — Emergency Manager Override', () {
    late SqliteService service;

    setUp(() async {
      service = SqliteService.instance;
      await service.initialize(inMemory: true);
      await service.setInitialOwnerPin('112233');
    });

    test('Master recovery key unlocks kiosk during active lockout and logs SECURITY_OVERRIDE', () async {
      // Trigger lockout with 5 failed attempts
      for (int i = 0; i < 5; i++) {
        await service.verifyOwnerPin('999999');
      }
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // Attempt invalid master key
      final invalidSuccess = await service.verifyEmergencyManagerOverride('WRONG-KEY-123');
      expect(invalidSuccess, isFalse);
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // Attempt valid master key
      final validSuccess = await service.verifyEmergencyManagerOverride('OTTO-MASTER-RECOVERY-2026');
      expect(validSuccess, isTrue);

      // Verify lockout is cleared
      final statusAfter = await service.getLockoutStatus();
      expect(statusAfter.isLockedOut, isFalse);
      expect(statusAfter.remainingSeconds, equals(0));
      expect(statusAfter.failedAttempts, equals(0));

      // Verify SECURITY_OVERRIDE was logged in system_logs
      final logs = await service.getSystemLogs(null, limit: 10);
      final overrideLog = logs.firstWhere(
        (l) => l.type == 'SECURITY_OVERRIDE',
        orElse: () => throw Exception('SECURITY_OVERRIDE log missing'),
      );
      expect(overrideLog.user, equals('Store Manager'));
      expect(overrideLog.description, contains('Emergency manager override'));
    });
  });

  group('Requirement 1.5 — Sync Queue Auditing & Phantom HTTP Elimination', () {
    late SqliteService service;
    late AuthService authService;

    setUp(() async {
      service = SqliteService.instance;
      await service.initialize(inMemory: true);
      authService = AuthService();
    });

    test('PIN update enqueues UPSERT to system_settings, users, and system_logs', () async {
      await service.setInitialOwnerPin('556677');
      await service.purgeSyncedQueueItems();

      // Change PIN via AuthService
      final changed = await authService.changePin(oldPin: '556677', newPin: '889900');
      expect(changed, isTrue);

      final pendingItems = await service.getPendingSyncItems(applyBackoff: false);
      expect(pendingItems.isNotEmpty, isTrue);

      final collections = pendingItems.map((item) => item['targetCollection']).toSet();
      expect(collections.contains('system_settings'), isTrue);
      expect(collections.contains('users'), isTrue);
      expect(collections.contains('system_logs'), isTrue);
    });
  });

  group('Requirement 1.6 — PinLoginScreen Widget First-Time Setup & Emergency Override UI', () {
    setUp(() async {
      await SqliteService.instance.close();
    });

    testWidgets('PinLoginScreen displays First-Time Setup badge when owner PIN is not configured', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = SqliteService.instance;
      await service.initialize(inMemory: true);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );

      // Verify title is present
      expect(find.text('Enter Store PIN'), findsOneWidget);
      expect(find.text('OTTO SCENTS'), findsOneWidget);

      // Let post-frame callbacks and auth status resolve
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // In fresh database, first-time setup badge is visible
      expect(find.byKey(const ValueKey('first_time_setup_badge')), findsOneWidget);
      expect(find.text('First-Time Setup: Create Owner PIN'), findsOneWidget);
    });

    testWidgets('PinLoginScreen shows Emergency Manager Override button and dialog unlocks terminal', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final service = SqliteService.instance;
      await service.initialize(inMemory: true);
      await service.setInitialOwnerPin('123987');

      // Trigger lockout
      for (int i = 0; i < 5; i++) {
        await service.verifyOwnerPin('000000');
      }

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkKioskTheme,
            home: const PinLoginScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Lockout state displayed
      expect(find.text('Security Lockout Active'), findsOneWidget);
      expect(find.byKey(const ValueKey('emergency_override_button')), findsOneWidget);

      // Tap Emergency Manager Override
      await tester.tap(find.byKey(const ValueKey('emergency_override_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify dialog is shown
      expect(find.text('Emergency Override'), findsOneWidget);
      expect(find.byKey(const ValueKey('emergency_override_input')), findsOneWidget);

      // Enter valid master recovery key
      await tester.enterText(
        find.byKey(const ValueKey('emergency_override_input')),
        'OTTO-MASTER-RECOVERY-2026',
      );
      await tester.pump();

      // Submit override
      await tester.tap(find.byKey(const ValueKey('emergency_override_submit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Verify dialog dismissed and lockout cleared in SQLite
      expect(find.text('Emergency Override'), findsNothing);
      final lockout = await service.getLockoutStatus();
      expect(lockout.isLockedOut, isFalse);
    });
  });
}

