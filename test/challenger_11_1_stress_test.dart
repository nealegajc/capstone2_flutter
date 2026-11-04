import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/services/auth_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'package:smart_shelf_linux/providers/auth_provider.dart';
import 'package:smart_shelf_linux/ui/components/manager_pin_dialog.dart';
import 'package:smart_shelf_linux/ui/components/stock_movement_hub_dialog.dart';
import 'package:smart_shelf_linux/ui/components/visual_shelf_counter.dart';

class TestAuthNotifier extends AuthNotifier {
  TestAuthNotifier({bool isAuthenticated = true})
      : super(AuthService()) {
    state = state.copyWith(isAuthenticated: isAuthenticated);
  }

  void forceAuthenticated(bool auth) {
    state = state.copyWith(isAuthenticated: auth);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('CHALLENGER 11.1 EMPIRICAL STRESS TEST SUITE (R1, R2, R4)', () {
    const testBranch = 'San Pablo Main';
    late SqliteService sqlite;
    late Database db;

    setUp(() async {
      sqlite = SqliteService.instance;
      await sqlite.close();
      await sqlite.initDatabase(inMemory: true);
      db = await sqlite.database;

      await db.delete('system_settings');
      await db.delete('system_logs');
      await db.delete('sync_queue');
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('sales_records');
      await db.delete('inventory_events');
      await db.delete('products');

      await db.insert('system_settings', {
        'key': 'branch_name',
        'value': testBranch,
      });

      // Seed test product and inventory
      await db.insert('products', {
        'id': 'prod_AA1',
        'perfumeCode': 'AA1',
        'name': 'Sauvage Dior',
        'brand': 'Dior',
        'category': 'Men',
        'bottleSize': '100ml',
        'shelfLayer': 'Tray AA Slot 1',
        'slotPosition': 1,
        'price': 260.0,
        'status': 'active',
      });

      await db.insert('inventory_records', {
        'id': 'inv_${testBranch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Sauvage Dior',
        'category': 'Men',
        'branch': testBranch,
        'shelf': 'Tray AA Slot 1',
        'recorded': 5,
        'detected': 5,
        'status': 'normal',
        'price': 260.0,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      // Setup owner PIN: '123456'
      final saltBytes = await sqlite.getKioskSaltBytes();
      final pinHash = Pbkdf2Auth.hashPin('123456', saltBytes);
      await db.insert('system_settings', {
        'key': 'owner_pin_hash',
        'value': pinHash,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    tearDown(() async {
      await sqlite.close();
    });

    // =========================================================================
    // 1. RAPID STEPPER CLICKING & BOUNDARY CLAMPING
    // =========================================================================
    group('1. Rapid Stepper Clicking & Boundary Clamping (VisualShelfCounter)', () {
      testWidgets('1.1 Out-of-bounds initialCount clamping to [0, 5]', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Test below 0 with unique key
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  key: Key('counter_negative'),
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: -15, // Out of bounds negative
                  trayCode: 'AA',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Count: 0 / 5 Bottles (0%)'), findsOneWidget);

        // Test above 5 with unique key
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  key: Key('counter_positive'),
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 99, // Out of bounds positive
                  trayCode: 'AA',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Count: 5 / 5 Bottles (100%)'), findsOneWidget);
      });

      testWidgets('1.2 Rapid increment clicking past 5 is clamped and disabled', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int currentCount = 3;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 3,
                  trayCode: 'AA',
                  onCountChanged: (c) => currentCount = c,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final incFinder = find.byKey(const ValueKey('visual_counter_increment'));
        expect(incFinder, findsOneWidget);

        // Increment to 4
        await tester.tap(incFinder);
        await tester.pumpAndSettle();
        expect(currentCount, 4);
        expect(find.text('Count: 4 / 5 Bottles (80%)'), findsOneWidget);

        // Increment to 5
        await tester.tap(incFinder);
        await tester.pumpAndSettle();
        expect(currentCount, 5);
        expect(find.text('Count: 5 / 5 Bottles (100%)'), findsOneWidget);

        // Spam increment 10 times while at 5
        for (int i = 0; i < 10; i++) {
          await tester.tap(incFinder, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        // Must still strictly be 5
        expect(currentCount, 5);
        expect(find.text('Count: 5 / 5 Bottles (100%)'), findsOneWidget);

        // Verify button is disabled
        final incBtn = tester.widget<IconButton>(incFinder);
        expect(incBtn.onPressed, isNull);
      });

      testWidgets('1.3 Rapid decrement clicking below 0 is clamped and disabled', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int currentCount = 2;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 2,
                  trayCode: 'AA',
                  onCountChanged: (c) => currentCount = c,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final decFinder = find.byKey(const ValueKey('visual_counter_decrement'));
        expect(decFinder, findsOneWidget);

        // Decrement to 1
        await tester.tap(decFinder);
        await tester.pumpAndSettle();
        expect(currentCount, 1);
        expect(find.text('Count: 1 / 5 Bottles (20%)'), findsOneWidget);

        // Decrement to 0
        await tester.tap(decFinder);
        await tester.pumpAndSettle();
        expect(currentCount, 0);
        expect(find.text('Count: 0 / 5 Bottles (0%)'), findsOneWidget);

        // Spam decrement 10 times while at 0
        for (int i = 0; i < 10; i++) {
          await tester.tap(decFinder, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pumpAndSettle();

        // Must still strictly be 0
        expect(currentCount, 0);
        expect(find.text('Count: 0 / 5 Bottles (0%)'), findsOneWidget);

        // Verify button is disabled
        final decBtn = tester.widget<IconButton>(decFinder);
        expect(decBtn.onPressed, isNull);
      });

      testWidgets('1.4 Direct preset buttons (0-5) and slot circles toggle accurately', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        int count = 1;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 1,
                  trayCode: 'AA',
                  onCountChanged: (c) => count = c,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tap preset 4
        await tester.tap(find.byKey(const ValueKey('visual_counter_preset_4')));
        await tester.pumpAndSettle();
        expect(count, 4);
        expect(find.text('Count: 4 / 5 Bottles (80%)'), findsOneWidget);

        // Tap preset 0
        await tester.tap(find.byKey(const ValueKey('visual_counter_preset_0')));
        await tester.pumpAndSettle();
        expect(count, 0);
        expect(find.text('Count: 0 / 5 Bottles (0%)'), findsOneWidget);

        // Tap preset 5
        await tester.tap(find.byKey(const ValueKey('visual_counter_preset_5')));
        await tester.pumpAndSettle();
        expect(count, 5);
        expect(find.text('Count: 5 / 5 Bottles (100%)'), findsOneWidget);

        // Use find.descendant to uniquely target slot circle 3
        final slot3 = find.descendant(
          of: find.byType(GestureDetector),
          matching: find.text('3'),
        ).first;

        await tester.tap(slot3);
        await tester.pumpAndSettle();
        expect(count, 3);
        expect(find.text('Count: 3 / 5 Bottles (60%)'), findsOneWidget);

        // Tap slot circle '3' again: toggles count to pos - 1 = 2
        await tester.tap(slot3);
        await tester.pumpAndSettle();
        expect(count, 2);
        expect(find.text('Count: 2 / 5 Bottles (40%)'), findsOneWidget);
      });
    });

    // =========================================================================
    // 2. CAMERA PEEK FALLBACK WHEN NODE IS ABSENT
    // =========================================================================
    group('2. Camera Peek Fallback When Device Node is Absent', () {
      testWidgets('2.1 Peek camera gracefully displays fallback UI when device node is missing', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  perfumeCode: 'AA1', // 100ml partition avoids 50ml text overflow
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 2,
                  trayCode: 'ZZ', // Non-existent camera
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final peekBtn = find.byKey(const ValueKey('peek_camera_feed_button'));
        expect(peekBtn, findsOneWidget);

        // Tap peek camera feed inside runAsync so real OS subprocess completes
        await tester.runAsync(() async {
          await tester.tap(peekBtn);
          await Future.delayed(const Duration(seconds: 2));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify camera snapshot header appears
        expect(find.text('Shelf Camera Snapshot (Tray ZZ)'), findsOneWidget);

        // Verify graceful fallback message appears without crash
        expect(
          find.text('Live camera preview ready on physical terminal.'),
          findsOneWidget,
        );

        // Dismiss peek panel via close icon
        final closeBtn = find.byIcon(Icons.close_rounded);
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pump(const Duration(milliseconds: 100));

        // Panel should be hidden
        expect(find.text('Shelf Camera Snapshot (Tray ZZ)'), findsNothing);
      });
    });

    // =========================================================================
    // 3. MANAGER PIN LOCKOUT ENFORCEMENT & PERSISTENCE
    // =========================================================================
    group('3. Manager PIN Lockout Enforcement & Persistence Across Re-opens', () {
      test('3.1 4 consecutive failed attempts increment count without triggering lockout', () async {
        for (int i = 1; i <= 4; i++) {
          final res = await sqlite.verifyOwnerPin('999999');
          expect(res, isFalse);
          final status = await sqlite.getLockoutStatus();
          expect(status.isLockedOut, isFalse);
          expect(status.failedAttempts, i);
          expect(status.remainingSeconds, 0);
        }
      });

      test('3.2 5th consecutive failed attempt triggers exactly 300s lockout', () async {
        // Run 5th failed attempt
        for (int i = 1; i <= 4; i++) {
          await sqlite.verifyOwnerPin('999999');
        }

        final fifthRes = await sqlite.verifyOwnerPin('999999');
        expect(fifthRes, isFalse);

        final lockout = await sqlite.getLockoutStatus();
        expect(lockout.isLockedOut, isTrue);
        expect(lockout.failedAttempts, 5);
        expect(lockout.remainingSeconds, inInclusiveRange(295, 300));

        // Submitting even the CORRECT PIN during lockout must be strictly rejected
        final duringLockoutAttempt = await sqlite.verifyOwnerPin('123456');
        expect(duringLockoutAttempt, isFalse);
      });

      testWidgets('3.3 ManagerPinDialog enforces lockout UI and disables keypad', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Put system in lockout in SQLite
        for (int i = 0; i < 5; i++) {
          await sqlite.verifyOwnerPin('000000');
        }

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ManagerPinDialog(
                actionTitle: 'Authorize Refund',
                actionDescription: 'Testing Lockout UI',
              ),
            ),
          ),
        );
        // Note: pump with duration, avoiding pumpAndSettle because Timer.periodic is running
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify lockout message displayed
        expect(find.textContaining('Security Lockout: Too many failed attempts'), findsOneWidget);

        // Verify numpad key taps are completely ignored
        final key1 = find.byKey(const ValueKey('numpad_key_1'));
        expect(key1, findsOneWidget);
        await tester.tap(key1);
        await tester.pump(const Duration(milliseconds: 50));

        // PIN should still be empty / disabled
        expect(find.textContaining('Security Lockout: Too many failed attempts'), findsOneWidget);
      });

      testWidgets('3.4 Lockout persists across closing and re-opening ManagerPinDialog', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Trigger 300s lockout
        for (int i = 0; i < 5; i++) {
          await sqlite.verifyOwnerPin('000000');
        }

        // Open dialog #1
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => ManagerPinDialog.show(
                    context,
                    actionTitle: 'First Attempt',
                    actionDescription: 'Desc 1',
                  ),
                  child: const Text('Open Dialog 1'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.tap(find.text('Open Dialog 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Confirm locked out
        expect(find.textContaining('Security Lockout'), findsOneWidget);

        // Cancel authorization to dismiss dialog
        await tester.tap(find.text('Cancel Authorization'));
        await tester.pumpAndSettle();

        expect(find.textContaining('Security Lockout'), findsNothing);

        // Open dialog #2 (re-open)
        await tester.tap(find.text('Open Dialog 1'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Must still be locked out from persisted SQLite state!
        expect(find.textContaining('Security Lockout'), findsOneWidget);

        // Ensure lockout is reported by SQLite service
        final lockoutStatus = await sqlite.getLockoutStatus();
        expect(lockoutStatus.isLockedOut, isTrue);
      });
    });

    // =========================================================================
    // 4. EMERGENCY MASTER RECOVERY KEY OVERRIDE
    // =========================================================================
    group('4. Emergency Master Recovery Key Override Unlocking', () {
      test('4.1 Invalid emergency recovery key does NOT clear lockout', () async {
        // Lockout system
        for (int i = 0; i < 5; i++) {
          await sqlite.verifyOwnerPin('000000');
        }
        expect((await sqlite.getLockoutStatus()).isLockedOut, isTrue);

        // Try invalid override key
        final overrideResult = await sqlite.verifyEmergencyManagerOverride('WRONG-OVERRIDE-KEY');
        expect(overrideResult, isFalse);

        // System must remain locked out
        final status = await sqlite.getLockoutStatus();
        expect(status.isLockedOut, isTrue);
        expect(status.failedAttempts, 5);
      });

      test('4.2 Master recovery key clears lockout and resets failed attempts', () async {
        // Lockout system
        for (int i = 0; i < 5; i++) {
          await sqlite.verifyOwnerPin('000000');
        }
        expect((await sqlite.getLockoutStatus()).isLockedOut, isTrue);

        // Apply emergency override with authoritative key
        final overrideResult = await sqlite.verifyEmergencyManagerOverride(
          SqliteService.defaultMasterRecoveryKey,
        );
        expect(overrideResult, isTrue);

        // System must now be completely unlocked
        final status = await sqlite.getLockoutStatus();
        expect(status.isLockedOut, isFalse);
        expect(status.failedAttempts, 0);
        expect(status.remainingSeconds, 0);

        // Correct PIN now succeeds
        final pinResult = await sqlite.verifyOwnerPin('123456');
        expect(pinResult, isTrue);
      });

      testWidgets('4.3 Reopened ManagerPinDialog after emergency override allows unlocking', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Lockout system
        for (int i = 0; i < 5; i++) {
          await sqlite.verifyOwnerPin('000000');
        }

        // Clear via emergency override
        final cleared = await sqlite.verifyEmergencyManagerOverride(
          SqliteService.defaultMasterRecoveryKey,
        );
        expect(cleared, isTrue);

        bool? authSuccess;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () async {
                    authSuccess = await ManagerPinDialog.show(
                      context,
                      actionTitle: 'Authorize Write-Off',
                      actionDescription: 'Post Override Test',
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // No lockout banner
        expect(find.textContaining('Security Lockout'), findsNothing);

        // Enter correct PIN: 1 2 3 4 5 6
        for (final digit in ['1', '2', '3', '4', '5', '6']) {
          await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        // Dialog pops with true
        expect(authSuccess, isTrue);
      });
    });

    // =========================================================================
    // 5. ACTIVE SESSION VERIFICATION (SALES/RESTOCKS vs REFUND/DAMAGE PIN PROMPT)
    // =========================================================================
    group('5. Active Session PIN Bypass vs Unconditional Refund & Damage Auth', () {
      testWidgets('5.1 Active session allows normal Sale submission without PIN prompt', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Suppress RenderFlex overflow error thrown by StockMovementHubDialog header
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!details.toString().contains('overflowed')) {
            originalOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        final authNotifier = TestAuthNotifier(isAuthenticated: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith((ref) => authNotifier),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StockMovementHubDialog(
                  initialPerfumeCode: 'AA1',
                  initialType: StockMovementType.sale,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify on Sale tab
        expect(find.text('Record Sale (₱260.00)'), findsOneWidget);

        // Submit sale
        await tester.tap(find.byKey(const ValueKey('submit_stock_movement_button')));
        await tester.pumpAndSettle();

        // Verify VerificationMethodDialog is shown and choose Computer Vision
        expect(find.byKey(const ValueKey('verification_choice_vision')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('verification_choice_vision')));
        await tester.pumpAndSettle();

        // Verify ManagerPinDialog was NOT shown
        expect(find.text('Authorize Customer Return & Refund'), findsNothing);
        expect(find.text('Authorize Damaged Write-Off'), findsNothing);

        // Verify sale was persisted in SQLite
        final sales = await sqlite.getSalesRecords(testBranch);
        expect(sales.length, 1);
        expect(sales.first.perfumeCode, 'AA1');
        expect(sales.first.quantitySold, 1);
        expect(sales.first.totalAmount, 260.0);

        // Verify inventory was decremented
        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 4);
        expect(inv?.detected, 4);
      });

      testWidgets('5.2 Active session allows normal Restock submission without PIN prompt', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!details.toString().contains('overflowed')) {
            originalOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        // Set recorded = 3, detected = 3 first
        await db.update(
          'inventory_records',
          {'recorded': 3, 'detected': 3},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final authNotifier = TestAuthNotifier(isAuthenticated: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith((ref) => authNotifier),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StockMovementHubDialog(
                  initialPerfumeCode: 'AA1',
                  initialType: StockMovementType.restock,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Commit Restock (+1 Bottles)'), findsOneWidget);

        // Submit restock
        await tester.tap(find.byKey(const ValueKey('submit_stock_movement_button')));
        await tester.pumpAndSettle();

        // Verify VerificationMethodDialog is shown and choose Computer Vision
        expect(find.byKey(const ValueKey('verification_choice_vision')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('verification_choice_vision')));
        await tester.pumpAndSettle();

        // Verify ManagerPinDialog was NOT shown
        expect(find.text('Authorize Customer Return & Refund'), findsNothing);

        // Verify inventory incremented to 4 and detected synced to 4
        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 4);
        expect(inv?.detected, 4);
      });

      testWidgets('5.3 Customer Return UNCONDITIONALLY prompts for Manager PIN even in active session', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!details.toString().contains('overflowed')) {
            originalOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        final authNotifier = TestAuthNotifier(isAuthenticated: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith((ref) => authNotifier),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StockMovementHubDialog(
                  initialPerfumeCode: 'AA1',
                  initialType: StockMovementType.customerReturn,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Authorize Refund (-₱260.00)'), findsOneWidget);

        // Tap submit refund
        await tester.tap(find.byKey(const ValueKey('submit_stock_movement_button')));
        await tester.pumpAndSettle();

        // Manager PIN keypad dialog MUST appear!
        expect(find.text('Authorize Customer Return & Refund'), findsOneWidget);
        expect(find.textContaining('Authorization required for customer return'), findsOneWidget);

        // If staff cancels authorization
        await tester.tap(find.text('Cancel Authorization'));
        await tester.pumpAndSettle();

        // No refund record saved
        final sales = await sqlite.getSalesRecords(testBranch);
        expect(sales.isEmpty, isTrue);
      });

      testWidgets('5.4 Damaged Write-Off UNCONDITIONALLY prompts for Manager PIN even in active session', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!details.toString().contains('overflowed')) {
            originalOnError?.call(details);
          }
        };
        addTearDown(() => FlutterError.onError = originalOnError);

        final authNotifier = TestAuthNotifier(isAuthenticated: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith((ref) => authNotifier),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StockMovementHubDialog(
                  initialPerfumeCode: 'AA1',
                  initialType: StockMovementType.damagedWriteOff,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Authorize Write-Off (-₱260.00)'), findsOneWidget);

        // Tap submit write-off
        await tester.tap(find.byKey(const ValueKey('submit_stock_movement_button')));
        await tester.pumpAndSettle();

        // Manager PIN keypad dialog MUST appear!
        expect(find.text('Authorize Damaged Write-Off'), findsOneWidget);

        // Authenticate with valid PIN: 123456
        for (final digit in ['1', '2', '3', '4', '5', '6']) {
          await tester.tap(find.byKey(ValueKey('numpad_key_$digit')));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();

        // Write-off must now be persisted in SQLite
        final events = await sqlite.getInventoryEvents(testBranch);
        final damageEvt = events.where((e) => e.eventType == 'DAMAGE_WRITEOFF').firstOrNull;
        expect(damageEvt, isNotNull);
        expect(damageEvt!.perfumeCode, 'AA1');
        expect(damageEvt.quantity, 1);
        expect(damageEvt.reason, 'Broken Bottle');

        // Inventory recorded decremented from 5 to 4
        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 4);
      });
    });

    // =========================================================================
    // 6. VISUAL COUNT COMMIT REALIGNING SQLITE & CLEARING DISCREPANCY ALERTS
    // =========================================================================
    group('6. Visual Count Commit Realigning SQLite Records & Clearing Discrepancy Alerts', () {
      test('6.1 Deficit discrepancy realignment: sets recorded=4, detected=4, clears discrepancy & low_stock alerts', () async {
        // Setup deficit discrepancy: recorded = 5, detected = 2
        await db.update(
          'inventory_records',
          {'recorded': 5, 'detected': 2, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        // Insert unread discrepancy alert
        await db.insert('alerts', {
          'id': 'alt_disc_001',
          'title': 'Discrepancy Alert',
          'desc': 'Discrepancy: detected 2 vs recorded 5',
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'branch': testBranch,
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Insert unread low_stock alert
        await db.insert('alerts', {
          'id': 'alt_low_001',
          'title': 'Low Stock Alert',
          'desc': 'Low stock: 2 bottles remaining',
          'type': 'low_stock',
          'perfumeCode': 'AA1',
          'branch': testBranch,
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Execute visual count audit committing 4 bottles
        await sqlite.recordVisualCountAudit(
          perfumeCode: 'AA1',
          countedBottles: 4,
          shelfArea: 'Tray AA Slot 1',
          auditor: 'Store Staff Tester',
          branch: testBranch,
        );

        // 1. Verify inventory records: both recorded and detected aligned to 4, status is normal
        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 4);
        expect(inv?.detected, 4);
        expect(inv?.status, 'normal');

        // 2. Verify discrepancy alert is cleared (isRead = 1)
        final discAlert = await db.query(
          'alerts',
          where: 'id = ?',
          whereArgs: ['alt_disc_001'],
        );
        expect(discAlert.first['isRead'], 1);

        // 3. Verify low stock alert is cleared since count 4 > lowThreshold 2
        final lowAlert = await db.query(
          'alerts',
          where: 'id = ?',
          whereArgs: ['alt_low_001'],
        );
        expect(lowAlert.first['isRead'], 1);

        // 4. Verify AUDIT_VISUAL_COUNT event was logged
        final events = await sqlite.getInventoryEvents(testBranch);
        final auditEvt = events.where((e) => e.eventType == 'AUDIT_VISUAL_COUNT').firstOrNull;
        expect(auditEvt, isNotNull);
        expect(auditEvt!.quantity, 4);
        expect(auditEvt.reason, contains('Store Staff Tester'));
      });

      test('6.2 Surplus discrepancy realignment: sets recorded=5, detected=5, clears discrepancy alert', () async {
        // Setup surplus discrepancy: recorded = 1, detected = 5
        await db.update(
          'inventory_records',
          {'recorded': 1, 'detected': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        await db.insert('alerts', {
          'id': 'alt_surplus_001',
          'title': 'Discrepancy Alert',
          'desc': 'Surplus: detected 5 vs recorded 1',
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'branch': testBranch,
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Audit committing 5 bottles
        await sqlite.recordVisualCountAudit(
          perfumeCode: 'AA1',
          countedBottles: 5,
          shelfArea: 'Tray AA Slot 1',
          auditor: 'Auditor X',
          branch: testBranch,
        );

        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 5);
        expect(inv?.detected, 5);
        expect(inv?.status, 'normal');

        final discAlert = await db.query(
          'alerts',
          where: 'id = ?',
          whereArgs: ['alt_surplus_001'],
        );
        expect(discAlert.first['isRead'], 1);
      });

      test('6.3 Visual count audit 0 bottles sets out_of_stock status and clears discrepancy alert', () async {
        await db.insert('alerts', {
          'id': 'alt_disc_zero',
          'title': 'Discrepancy Alert',
          'desc': 'Discrepancy: detected 0 vs recorded 3',
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'branch': testBranch,
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        await sqlite.recordVisualCountAudit(
          perfumeCode: 'AA1',
          countedBottles: 0,
          shelfArea: 'Tray AA Slot 1',
          auditor: 'Auditor Zero',
          branch: testBranch,
        );

        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 0);
        expect(inv?.detected, 0);
        expect(inv?.status, 'out_of_stock');

        final discAlert = await db.query(
          'alerts',
          where: 'id = ?',
          whereArgs: ['alt_disc_zero'],
        );
        expect(discAlert.first['isRead'], 1);
      });

      testWidgets('6.4 VisualShelfCounter commit button invokes recordVisualCountAudit and updates DB', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Setup initial deficit
        await db.update(
          'inventory_records',
          {'recorded': 5, 'detected': 1},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: VisualShelfCounter(
                  perfumeCode: 'AA1',
                  productName: 'Sauvage Dior',
                  bottleSize: '100ml',
                  initialCount: 1,
                  trayCode: 'AA',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Select preset 3
        await tester.tap(find.byKey(const ValueKey('visual_counter_preset_3')));
        await tester.pumpAndSettle();

        // Tap commit visual count button
        final commitBtn = find.byKey(const ValueKey('commit_visual_count_button'));
        expect(commitBtn, findsOneWidget);
        await tester.tap(commitBtn);
        await tester.pumpAndSettle();

        // Verify SQLite was realigned to 3 recorded and 3 detected
        final inv = await sqlite.getInventoryRecord('AA1', testBranch);
        expect(inv?.recorded, 3);
        expect(inv?.detected, 3);
      });

      // =======================================================================
      // ADVERSARIAL EDGE CASE EVIDENCE TESTS (BUG CONFIRMATIONS)
      // =======================================================================
      testWidgets('7.1 ADVERSARIAL DISCOVERY: VisualShelfCounter 50ML slot circle layout overflow verification', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final capturedErrors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          capturedErrors.add(details);
        };
        addTearDown(() => FlutterError.onError = prevOnError);

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: VisualShelfCounter(
                perfumeCode: 'AA2',
                productName: 'Bleu de Chanel',
                bottleSize: '50ml', // 50ml slot partition has 44px diameter
                initialCount: 2,
                trayCode: 'AA',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        FlutterError.onError = prevOnError;

        // Assert that the 50ml slot circle renders cleanly with ZERO RenderFlex overflow exceptions
        final overflowErrors = capturedErrors.where(
          (e) => e.toString().contains('overflowed') || e.toString().contains('RenderFlex'),
        );
        expect(overflowErrors, isEmpty, reason: 'VisualShelfCounter must render 50ml slot circles cleanly with ZERO RenderFlex overflow');
        expect(tester.takeException(), isNull);
        expect(find.byType(VisualShelfCounter), findsOneWidget);
      });

      testWidgets('7.2 ADVERSARIAL DISCOVERY: StockMovementHubDialog unconstrained header layout overflow verification', (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final capturedErrors = <FlutterErrorDetails>[];
        final prevOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          capturedErrors.add(details);
        };
        addTearDown(() => FlutterError.onError = prevOnError);

        final authNotifier = TestAuthNotifier(isAuthenticated: true);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authNotifierProvider.overrideWith((ref) => authNotifier),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: StockMovementHubDialog(
                  initialPerfumeCode: 'AA1',
                  initialType: StockMovementType.sale,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        FlutterError.onError = prevOnError;

        // Assert that header row renders cleanly with ZERO RenderFlex overflow exceptions in dialog
        final overflowErrors = capturedErrors.where(
          (e) => e.toString().contains('overflowed') || e.toString().contains('RenderFlex'),
        );
        expect(overflowErrors, isEmpty, reason: 'StockMovementHubDialog header must render cleanly with ZERO RenderFlex overflow');
        expect(tester.takeException(), isNull);
        expect(find.byType(StockMovementHubDialog), findsOneWidget);
      });
    });
  });
}
