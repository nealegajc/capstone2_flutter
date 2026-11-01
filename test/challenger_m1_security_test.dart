// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/services/sqlite_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('CHALLENGE 1: PBKDF2 Test Vectors, Timing Resistance, & Salt Uniqueness', () {
    test('1.1 Standard & Multi-Block PBKDF2-HMAC-SHA256 Test Vectors', () {
      // Test Vector 1: c=1, dkLen=32
      final v1 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 1,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(v1),
        equals('120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b'),
        reason: 'Failed RFC PBKDF2 vector c=1',
      );

      // Test Vector 2: c=2, dkLen=32
      final v2 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 2,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(v2),
        equals('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43'),
        reason: 'Failed RFC PBKDF2 vector c=2',
      );

      // Test Vector 3: c=4096, dkLen=32
      final v3 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 4096,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(v3),
        equals('c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a'),
        reason: 'Failed RFC PBKDF2 vector c=4096',
      );

      // Test Vector 4: Multi-block output (dkLen=40 > 32, requiring 2 HMAC blocks)
      final v4 = Pbkdf2Auth.deriveKey(
        password: 'password',
        salt: utf8.encode('salt'),
        iterations: 2,
        derivedKeyLength: 40,
      );
      expect(
        Pbkdf2Auth.toHex(v4),
        equals('ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43830651afcb5c862f'),
        reason: 'Multi-block derivation (dkLen=40) mismatch',
      );

      // Test Vector 5: Multi-block with long password & salt (dkLen=40, c=4096)
      final v5 = Pbkdf2Auth.deriveKey(
        password: 'passwordPASSWORDpassword',
        salt: utf8.encode('saltSALTsaltSALTsaltSALTsaltSALTsalt'),
        iterations: 4096,
        derivedKeyLength: 40,
      );
      expect(
        Pbkdf2Auth.toHex(v5),
        equals('348c89dbcbd32b2f32d814b8116e84cf2b17347ebc1800181c4e2a1fb8dd53e1c635518c7dac47e9'),
        reason: 'RFC long-input multi-block vector mismatch',
      );

      // Test Vector 6: Production parameters (100,000 iterations, 32-byte key)
      final v6 = Pbkdf2Auth.deriveKey(
        password: '123456',
        salt: utf8.encode('01234567890123456789012345678901'),
        iterations: 100000,
        derivedKeyLength: 32,
      );
      expect(
        Pbkdf2Auth.toHex(v6),
        equals('36113e0d81b709e734dc11a0c9747ec5f1a006329ae9dbc020069d8bd44fed65'),
        reason: 'Production 100,000-iteration reference hash mismatch',
      );
    });

    test('1.2 Salt Uniqueness & Shannon Entropy (1,000 Generated Salts)', () {
      final salts = <String>{};
      final byteCounts = List<int>.filled(256, 0);
      const totalSalts = 1000;
      const saltLength = 32;

      for (int i = 0; i < totalSalts; i++) {
        final salt = Pbkdf2Auth.generateSalt(saltLength);
        expect(salt.length, equals(saltLength));

        final hex = Pbkdf2Auth.toHex(salt);
        expect(hex.length, equals(saltLength * 2));
        salts.add(hex);

        for (final b in salt) {
          byteCounts[b]++;
        }
      }

      // Zero collisions among 1,000 generated salts
      expect(salts.length, equals(totalSalts), reason: 'Salt collision detected!');

      // Compute Shannon entropy across 32,000 bytes
      // H(X) = -sum(P(x) * log2(P(x)))
      final totalBytes = totalSalts * saltLength;
      double entropy = 0.0;
      for (int i = 0; i < 256; i++) {
        if (byteCounts[i] > 0) {
          final p = byteCounts[i] / totalBytes;
          entropy -= p * (log(p) / ln2);
        }
      }

      // Cryptographically secure RNG should have entropy > 7.95 bits/byte (max is 8.0)
      expect(entropy, greaterThan(7.95), reason: 'Insufficient salt entropy: $entropy bits/byte');
    });

    test('1.3 Timing Resistance: PBKDF2 Latency vs Short-Circuit Lockout', () async {
      final service = SqliteService.instance;
      await service.initialize(inMemory: true);
      await service.setInitialOwnerPin('842915');

      // 1. Measure normal verification time (PBKDF2 100,000 iterations)
      final sw1 = Stopwatch()..start();
      final res1 = await service.verifyOwnerPin('842915');
      sw1.stop();
      expect(res1, isTrue);
      final normalTimeMs = sw1.elapsedMilliseconds;

      // 2. Measure incorrect PIN verification time
      final sw2 = Stopwatch()..start();
      final res2 = await service.verifyOwnerPin('842914');
      sw2.stop();
      expect(res2, isFalse);
      final incorrectTimeMs = sw2.elapsedMilliseconds;

      // Both should spend comparable time in PBKDF2 (> 100ms in debug/test VM)
      expect(normalTimeMs, greaterThan(100));
      expect(incorrectTimeMs, greaterThan(100));

      // 3. Trigger 5-attempt lockout
      for (int i = 0; i < 4; i++) {
        await service.verifyOwnerPin('000000');
      }
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // 4. Measure locked out verification time (must short-circuit without computing PBKDF2)
      final swLockout = Stopwatch()..start();
      final resLockout = await service.verifyOwnerPin('842915');
      swLockout.stop();
      expect(resLockout, isFalse);
      final lockedOutTimeMs = swLockout.elapsedMilliseconds;

      // Fast-reject during lockout should be < 50ms (avoiding CPU exhaustion DoS)
      expect(
        lockedOutTimeMs,
        lessThan(50),
        reason: 'Lockout verification failed to short-circuit: took ${lockedOutTimeMs}ms',
      );
    });
  });

  group('CHALLENGE 2: Persistent Lockout Mechanism Stress-Testing', () {
    late String tempDbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp.createTempSync('challenger_lockout_');
      tempDbPath = '${tempDir.path}/persistent_lockout.db';
      await SqliteService.instance.close();
    });

    tearDown(() async {
      try {
        await SqliteService.instance.close();
        final f = File(tempDbPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    });

    test('2.1 Crash/Restart Resilience at every attempt stage (1 to 5)', () async {
      // Initialize on disk
      var service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      await service.setInitialOwnerPin('518294');

      // Fail 1 time -> simulate crash
      await service.verifyOwnerPin('000000');
      await service.close();
      service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      var status = await service.getLockoutStatus();
      expect(status.failedAttempts, equals(1));
      expect(status.isLockedOut, isFalse);

      // Fail 2nd time -> simulate crash
      await service.verifyOwnerPin('000000');
      await service.close();
      service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      status = await service.getLockoutStatus();
      expect(status.failedAttempts, equals(2));
      expect(status.isLockedOut, isFalse);

      // Fail 3rd time -> simulate crash
      await service.verifyOwnerPin('000000');
      await service.close();
      service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      status = await service.getLockoutStatus();
      expect(status.failedAttempts, equals(3));
      expect(status.isLockedOut, isFalse);

      // Fail 4th time -> simulate crash
      await service.verifyOwnerPin('000000');
      await service.close();
      service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      status = await service.getLockoutStatus();
      expect(status.failedAttempts, equals(4));
      expect(status.isLockedOut, isFalse);

      // Fail 5th time -> lockout triggered -> simulate crash
      await service.verifyOwnerPin('000000');
      status = await service.getLockoutStatus();
      expect(status.isLockedOut, isTrue);

      await service.close();
      service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);

      // Verify lockout state survived reboot
      final rebootStatus = await service.getLockoutStatus();
      expect(rebootStatus.isLockedOut, isTrue);
      expect(rebootStatus.failedAttempts, equals(5));
      expect(rebootStatus.remainingSeconds, greaterThan(285));
      expect(rebootStatus.remainingSeconds, lessThanOrEqualTo(300));

      // Valid PIN must still fail while locked out after restart
      expect(await service.verifyOwnerPin('518294'), isFalse);
    });

    test('2.2 Attempt Counter Rollover, Spam During Lockout, & Legitimate Reset', () async {
      final service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      await service.setInitialOwnerPin('729103');

      // Fail 4 times
      for (int i = 0; i < 4; i++) {
        await service.verifyOwnerPin('999999');
      }
      expect((await service.getLockoutStatus()).failedAttempts, equals(4));

      // Enter correct PIN -> counter should reset to 0
      final correctRes = await service.verifyOwnerPin('729103');
      expect(correctRes, isTrue);
      final resetStatus = await service.getLockoutStatus();
      expect(resetStatus.failedAttempts, equals(0));
      expect(resetStatus.isLockedOut, isFalse);

      // Trigger 5-attempt lockout again
      for (int i = 0; i < 5; i++) {
        await service.verifyOwnerPin('999999');
      }
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // Spam 10 additional attempts while locked out:
      // Counter must not rollover into negative numbers or reset
      for (int i = 0; i < 10; i++) {
        final spamRes = await service.verifyOwnerPin('000000');
        expect(spamRes, isFalse);
      }

      final spammedStatus = await service.getLockoutStatus();
      expect(spammedStatus.isLockedOut, isTrue);
      expect(spammedStatus.failedAttempts, equals(5));
    });

    test('2.3 Boundary Times, Epoch Manipulation, & Malformed System Settings', () async {
      final service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      await service.setInitialOwnerPin('445566');

      final now = DateTime.now().millisecondsSinceEpoch;

      // Case A: locked_until_epoch set to 5 seconds in future
      await service.setSystemSetting('locked_until_epoch', (now + 5000).toString(), enqueueSync: false);
      await service.setSystemSetting('failed_pin_attempts', '5', enqueueSync: false);
      var status = await service.getLockoutStatus();
      expect(status.isLockedOut, isTrue);
      expect(status.remainingSeconds, inInclusiveRange(4, 6));

      // Case B: locked_until_epoch expired (1 second in past) -> auto-clears lockout
      await service.setSystemSetting('locked_until_epoch', (now - 1000).toString(), enqueueSync: false);
      status = await service.getLockoutStatus();
      expect(status.isLockedOut, isFalse);
      expect(status.remainingSeconds, equals(0));
      expect(status.failedAttempts, equals(0));

      // Case C: Exact boundary (now)
      await service.setSystemSetting('locked_until_epoch', now.toString(), enqueueSync: false);
      status = await service.getLockoutStatus();
      expect(status.isLockedOut, isFalse);
      expect(status.remainingSeconds, equals(0));

      // Case D: Negative epoch value
      await service.setSystemSetting('locked_until_epoch', '-50000', enqueueSync: false);
      status = await service.getLockoutStatus();
      expect(status.isLockedOut, isFalse);

      // Case E: Non-numeric corrupted strings
      await service.setSystemSetting('locked_until_epoch', 'corrupted_string', enqueueSync: false);
      await service.setSystemSetting('failed_pin_attempts', 'invalid_count', enqueueSync: false);
      status = await service.getLockoutStatus();
      expect(status.isLockedOut, isFalse);
      expect(status.remainingSeconds, equals(0));
      expect(status.failedAttempts, equals(0));

      // Case F: Huge overflow number
      await service.setSystemSetting('failed_pin_attempts', '99999999999999999999999999', enqueueSync: false);
      status = await service.getLockoutStatus();
      expect(status.failedAttempts, equals(0)); // int.tryParse returns null -> defaults to 0
    });

    test('2.4 Concurrency / Multi-Threaded Verification Stress Test', () async {
      final service = SqliteService.instance;
      await service.initialize(customPath: tempDbPath);
      await service.setInitialOwnerPin('128475');

      // Execute 8 concurrent verification requests in parallel
      final futures = List.generate(8, (_) => service.verifyOwnerPin('999999'));
      final results = await Future.wait(futures);

      // All 8 must fail
      for (final res in results) {
        expect(res, isFalse);
      }

      final finalStatus = await service.getLockoutStatus();
      // Print empirical diagnostic
      print('CONCURRENCY TEST RESULT: failedAttempts=${finalStatus.failedAttempts}, isLockedOut=${finalStatus.isLockedOut}');
      
      // Documenting the finding:
      // EXPECTATION for secure lockout: 8 failed attempts >= 5 threshold -> isLockedOut must be true
      // ACTUAL OBSERVED: TOCTOU race causes failedAttempts to record fewer attempts, failing to trigger lockout.
      expect(
        finalStatus.isLockedOut,
        isTrue,
        reason: 'CRITICAL TOCTOU FLAW: 8 concurrent failed attempts resulted in failedAttempts=${finalStatus.failedAttempts} and isLockedOut=false!',
      );
    });
  });

  group('CHALLENGE 3: Bypass Attacks & Input Validation Hardening', () {
    late SqliteService service;

    setUp(() async {
      service = SqliteService.instance;
      await service.initialize(inMemory: true);
    });

    test('3.1 Default & Weak PIN Attacks', () async {
      // 1. Fresh database without PIN configured
      expect(await service.isOwnerPinSet(), isFalse);
      expect(await service.verifyOwnerPin('123456'), isFalse);
      expect(await service.verifyOwnerPin('000000'), isFalse);
      expect(await service.verifyOwnerPin('111111'), isFalse);

      // 2. Set legitimate owner PIN
      await service.setInitialOwnerPin('987123');
      expect(await service.isOwnerPinSet(), isTrue);

      // 3. Fallback PINs strictly fail
      expect(await service.verifyOwnerPin('123456'), isFalse);
      expect(await service.verifyOwnerPin('000000'), isFalse);
      expect(await service.verifyOwnerPin('111111'), isFalse);
      expect(await service.verifyOwnerPin('987123'), isTrue);
    });

    test('3.2 Legacy SHA-256 Migration Bypass Block for 123456', () async {
      // Simulate a legacy pre-PBKDF2 database with sha256('123456')
      await service.database;
      final legacy123456Hash = sha256.convert(utf8.encode('123456')).toString();
      await service.setSystemSetting('owner_pin_hash', legacy123456Hash);

      // Attempting to authenticate with '123456' against legacy hash MUST be blocked
      final bypassAttempt = await service.verifyOwnerPin('123456');
      expect(
        bypassAttempt,
        isFalse,
        reason: 'Legacy SHA-256 fallback migration allowed default 123456 bypass!',
      );

      // Legacy sha256 with non-default PIN ('654321') SHOULD auto-upgrade
      final legacyCustomHash = sha256.convert(utf8.encode('654321')).toString();
      await service.setSystemSetting('owner_pin_hash', legacyCustomHash);
      final customSuccess = await service.verifyOwnerPin('654321');
      expect(customSuccess, isTrue);

      // Verify that the stored hash was upgraded to PBKDF2 (not equal to raw sha256)
      final upgradedHash = await service.getSetting('owner_pin_hash');
      expect(upgradedHash, isNotNull);
      expect(upgradedHash, isNot(equals(legacyCustomHash)));
      expect(upgradedHash!.length, equals(64));
    });

    test('3.3 Illegal PIN Format & Edge-Case Rejection', () async {
      // Setup PIN
      await service.setInitialOwnerPin('246810');

      // Illegal PIN strings for verification
      final illegalPins = [
        '',
        ' ',
        '   ',
        '12345', // 5 digits
        '1234567', // 7 digits
        'abcdef',
        '12345a',
        '-12345',
        '12.345',
        '12\x00456',
        '\u0000\u0000\u0000\u0000\u0000\u0000',
        '123 45',
      ];

      for (final badPin in illegalPins) {
        await service.resetLockout();
        final res = await service.verifyOwnerPin(badPin);
        // None of these should authenticate as '246810'
        expect(res, isFalse, reason: 'Illegal PIN "$badPin" erroneously authenticated');
      }

      // Check leading/trailing whitespace tolerance
      await service.resetLockout();
      final whitespaceRes = await service.verifyOwnerPin(' 246810 ');
      print('WHITESPACE PIN " 246810 " VERIFICATION RESULT: $whitespaceRes');

      // Initial setup must also reject invalid PIN formats
      expect(await service.setInitialOwnerPin(''), isFalse);
      expect(await service.setInitialOwnerPin('123'), isFalse);
      expect(await service.setInitialOwnerPin('1234567'), isFalse);
      expect(await service.setInitialOwnerPin('abcdef'), isFalse);

      // EMPIRICAL FORMAT VULNERABILITY CHECK:
      // Does setInitialOwnerPin accept non-digit strings like '-12345', '+12345', '0x1234'?
      final acceptedNegative = await service.setInitialOwnerPin('-12345');
      final acceptedPositiveSign = await service.setInitialOwnerPin('+12345');
      final acceptedHex = await service.setInitialOwnerPin('0x1234');
      final acceptedHexCap = await service.setInitialOwnerPin('0XABCD');

      print('FORMAT VALIDATION FLAWS IN setInitialOwnerPin:');
      print('  -12345 accepted: $acceptedNegative');
      print('  +12345 accepted: $acceptedPositiveSign');
      print('  0x1234 accepted: $acceptedHex');
      print('  0XABCD accepted: $acceptedHexCap');

      // Assert that all non-digit formats must be rejected
      expect(
        acceptedNegative,
        isFalse,
        reason: 'CRITICAL FORMAT FLAW: setInitialOwnerPin accepted negative integer "-12345"!',
      );
      expect(
        acceptedPositiveSign,
        isFalse,
        reason: 'CRITICAL FORMAT FLAW: setInitialOwnerPin accepted signed integer "+12345"!',
      );
      expect(
        acceptedHex,
        isFalse,
        reason: 'CRITICAL FORMAT FLAW: setInitialOwnerPin accepted hex string "0x1234"!',
      );
      expect(
        acceptedHexCap,
        isFalse,
        reason: 'CRITICAL FORMAT FLAW: setInitialOwnerPin accepted hex string "0XABCD"!',
      );

      // Update PIN must also reject invalid new PIN formats
      expect(await service.updateOwnerPin(oldPin: '246810', newPin: '123'), isFalse);
      expect(await service.updateOwnerPin(oldPin: '246810', newPin: 'abcdef'), isFalse);
      expect(await service.updateOwnerPin(oldPin: 'wrong_old', newPin: '654321'), isFalse);
    });

    test('3.4 SQL Injection Defense on PIN and System Settings', () async {
      await service.setInitialOwnerPin('357911');

      final sqlInjections = [
        "' OR '1'='1",
        "' OR 1=1 --",
        "admin'--",
        "'; DROP TABLE system_settings; --",
        "'; DROP TABLE users; --",
        "' UNION SELECT 1, 'owner_pin_hash', 'injected' --",
        '" OR ""="',
        "' OR ''='",
      ];

      for (final sqli in sqlInjections) {
        // Attempt injection via verifyOwnerPin
        final pinAuthRes = await service.verifyOwnerPin(sqli);
        expect(pinAuthRes, isFalse, reason: 'SQL injection succeeded on PIN auth: $sqli');

        // Attempt injection via verifyEmergencyManagerOverride
        final overrideRes = await service.verifyEmergencyManagerOverride(sqli);
        expect(overrideRes, isFalse, reason: 'SQL injection succeeded on override: $sqli');
      }

      // Verify that database tables were not corrupted or dropped
      final db = await service.database;
      final settings = await db.query('system_settings');
      expect(settings.isNotEmpty, isTrue, reason: 'system_settings table was compromised!');

      final users = await db.query('users');
      expect(users.isNotEmpty, isTrue, reason: 'users table was compromised!');
    });

    test('3.5 Emergency Manager Override Attacks & Key Rotation', () async {
      // Trigger lockout with 5 failed attempts
      await service.setInitialOwnerPin('654987');
      for (int i = 0; i < 5; i++) {
        await service.verifyOwnerPin('000000');
      }
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // 1. Empty, whitespace, or invalid keys fail
      expect(await service.verifyEmergencyManagerOverride(''), isFalse);
      expect(await service.verifyEmergencyManagerOverride('   '), isFalse);
      expect(await service.verifyEmergencyManagerOverride('otto-master-recovery-2026'), isFalse); // wrong case
      expect(await service.verifyEmergencyManagerOverride('OTTO-MASTER-RECOVERY'), isFalse);
      expect(await service.verifyEmergencyManagerOverride('RANDOM-SECRET-12345'), isFalse);

      // Lockout must still be active after failed override attempts
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // 2. Valid default key succeeds
      final overrideSuccess = await service.verifyEmergencyManagerOverride(
        SqliteService.defaultMasterRecoveryKey,
      );
      expect(overrideSuccess, isTrue);

      // Lockout must be cleared
      final statusAfter = await service.getLockoutStatus();
      expect(statusAfter.isLockedOut, isFalse);
      expect(statusAfter.failedAttempts, equals(0));

      // 3. Custom Master Key Rotation: rotate master recovery key to store-specific passphrase
      final saltBytes = await service.getKioskSaltBytes();
      const customKey = 'BRANCH-SAN-PABLO-EMERGENCY-KEY-999';
      final customHash = Pbkdf2Auth.hashPin(customKey, saltBytes);
      await service.setSystemSetting('master_recovery_key_hash', customHash, enqueueSync: false);

      // Lock terminal again
      for (int i = 0; i < 5; i++) {
        await service.verifyOwnerPin('000000');
      }
      expect((await service.getLockoutStatus()).isLockedOut, isTrue);

      // Default key must now FAIL
      expect(
        await service.verifyEmergencyManagerOverride(SqliteService.defaultMasterRecoveryKey),
        isFalse,
        reason: 'Default master recovery key was not superseded by custom key hash!',
      );

      // Custom key must SUCCEED
      expect(await service.verifyEmergencyManagerOverride(customKey), isTrue);
      expect((await service.getLockoutStatus()).isLockedOut, isFalse);
    });

    test('3.6 Salt Tampering & Self-Healing Resilience', () async {
      // 1. Delete salt from system_settings
      final db = await service.database;
      await db.delete('system_settings', where: 'key = ?', whereArgs: ['kiosk_auth_salt']);

      // getKioskSaltBytes should self-heal and generate a fresh 32-byte salt
      final healedSalt = await service.getKioskSaltBytes();
      expect(healedSalt.length, equals(32));
      final storedHex = await service.getSetting('kiosk_auth_salt');
      expect(storedHex, isNotNull);
      expect(storedHex!.length, equals(64));

      // 2. Corrupt salt with invalid non-hex characters
      await service.setSystemSetting('kiosk_auth_salt', '!@#\$%^&*()NOT_HEX', enqueueSync: false);
      final recoveredSalt = await service.getKioskSaltBytes();
      expect(recoveredSalt.length, equals(32));

      // 3. Set salt to truncated hex (< 16 bytes = 32 hex chars)
      await service.setSystemSetting('kiosk_auth_salt', 'aabbccddeeff', enqueueSync: false); // 6 bytes
      final regeneratedSalt = await service.getKioskSaltBytes();
      expect(regeneratedSalt.length, equals(32));
    });
  });
}
