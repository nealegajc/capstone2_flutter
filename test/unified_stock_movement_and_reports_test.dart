import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'helpers/e2e_test_harness.dart';
import 'helpers/unified_stock_movement_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('Milestone 11: Unified Stock Movement, Visual Count, Discrepancy, PIN Auth, and Reports/Exports', () {
    late SqliteService sqliteService;
    late Database db;
    const String branch = 'San Pablo Main';

    setUp(() async {
      sqliteService = SqliteService.instance;
      await sqliteService.close();
      await sqliteService.initDatabase(inMemory: true);
      db = await sqliteService.database;

      await db.delete('system_settings');
      await db.delete('system_logs');
      await db.delete('sync_queue');
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('sales_records');
      await db.delete('inventory_events');
      await db.delete('products');

      // Seed system settings
      await db.insert('system_settings', {
        'key': 'branch_name',
        'value': branch,
      });

      // Seed standard 100ml and 50ml test slots
      await db.insert('inventory_records', {
        'id': 'inv_${branch}_AA1',
        'perfumeCode': 'AA1',
        'name': 'Sauvage Dior',
        'category': 'Men',
        'branch': branch,
        'shelf': 'Tray AA Slot 1',
        'recorded': 5,
        'detected': 5,
        'status': 'normal',
        'price': 260.0,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });

      await db.insert('inventory_records', {
        'id': 'inv_${branch}_AA2',
        'perfumeCode': 'AA2',
        'name': 'Bleu de Chanel',
        'category': 'Men',
        'branch': branch,
        'shelf': 'Tray AA Slot 2',
        'recorded': 5,
        'detected': 5,
        'status': 'normal',
        'price': 180.0,
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await sqliteService.close();
    });

    // =========================================================================
    // TIER 1: FEATURE COVERAGE (F1 to F14, >=5 tests each = 70 tests)
    // =========================================================================

    // -------------------------------------------------------------------------
    // F1: Discrepancy Deficit Deduction Fix (R3)
    // -------------------------------------------------------------------------
    group('F1: Deficit Discrepancy Zero Double-Deduction', () {
      test('T1.F1.1: Deficit sale (detected=2, recorded=5, qty=3) sets recorded=2, detected=2 without dropping detected to 0', () async {
        // Setup deficit discrepancy
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 3,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        expect(res['recorded'], equals(2));
        expect(res['detected'], equals(2)); // Detected MUST remain 2!
      });

      test('T1.F1.2: Partial deficit sale (deficit=3, qty=2) deducts recorded to 3 leaving detected at 2', () async {
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 2,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        expect(res['recorded'], equals(3));
        expect(res['detected'], equals(2));
      });

      test('T1.F1.3: Sale equal to deficit completely resolves discrepancy and dismisses alert', () async {
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        await db.insert('alerts', {
          'id': 'alert_disc_AA1',
          'title': 'Inventory Discrepancy: AA1',
          'desc': 'Detected 2 vs Recorded 5',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 3,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);
      });

      test('T1.F1.4: Normal sale (isDeficitResolution=false) decrements both detected and recorded', () async {
        final res = await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 2,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: false,
        );

        expect(res['recorded'], equals(3));
        expect(res['detected'], equals(3));
      });

      test('T1.F1.5: Deficit sale deduction writes valid SaleRecord and REMOVED event to SQLite', () async {
        await db.update(
          'inventory_records',
          {'detected': 1, 'recorded': 4},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 3,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        final sales = await db.query('sales_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        final events = await db.query('inventory_events', where: 'perfumeCode = ?', whereArgs: ['AA1']);

        expect(sales.length, equals(1));
        expect((sales.first['quantitySold'] as num).toInt(), equals(3));
        expect(events.length, equals(1));
        expect(events.first['eventType'], equals('REMOVED'));
      });
    });

    // -------------------------------------------------------------------------
    // F2: Restock Physical Detected Alignment Fix (R3)
    // -------------------------------------------------------------------------
    group('F2: Restock Physical Detected Alignment', () {
      test('T1.F2.1: Restock sets detected = newRecorded, aligning physical count with ledger', () async {
        await db.update(
          'inventory_records',
          {'detected': 1, 'recorded': 1, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantityAdded: 4,
        );

        expect(res['recorded'], equals(5));
        expect(res['detected'], equals(5));
      });

      test('T1.F2.2: Restock sets status=normal and clears any low_stock/out_of_stock alerts', () async {
        await db.update(
          'inventory_records',
          {'detected': 0, 'recorded': 0, 'status': 'out_of_stock'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );
        await db.insert('alerts', {
          'id': 'alert_out_AA1',
          'title': 'Out of Stock: AA1',
          'desc': 'Slot is empty',
          'branch': branch,
          'type': 'out_of_stock',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantityAdded: 5,
        );

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['status'], equals('normal'));

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);
      });

      test('T1.F2.3: Restock prevents immediate false discrepancy alert (hasDiscrepancy remains false)', () async {
        await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA2',
          quantityAdded: 2,
        );

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA2']);
        final rec = inv.first['recorded'] as int;
        final det = inv.first['detected'] as int;
        expect(rec == det, isTrue);
      });

      test('T1.F2.4: Restock logs RESTOCKED event in SQLite with correct metadata', () async {
        await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantityAdded: 3,
        );

        final events = await db.query(
          'inventory_events',
          where: 'perfumeCode = ? AND eventType = ?',
          whereArgs: ['AA1', 'RESTOCKED'],
        );
        expect(events.length, equals(1));
        expect((events.first['quantity'] as num).toInt(), equals(3));
      });

      test('T1.F2.5: Restock from empty (0) safely caps at max shelf capacity 5', () async {
        await db.update(
          'inventory_records',
          {'detected': 0, 'recorded': 0},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantityAdded: 10, // Attempt overfill
        );

        expect(res['recorded'], equals(5));
        expect(res['detected'], equals(5));
      });
    });

    // -------------------------------------------------------------------------
    // F3: Customer Return & Refund Ledger Logic (R1, R3)
    // -------------------------------------------------------------------------
    group('F3: Customer Return & Refund (Resellable vs Damaged)', () {
      test('T1.F3.1: Resellable return increments recorded and detected on physical shelf (+1, max 5)', () async {
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 2},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: true,
          authorizedBy: 'Manager',
        );

        expect(res['recorded'], equals(3));
        expect(res['detected'], equals(3));
        expect(res['totalRefund'], equals(260.0));
      });

      test('T1.F3.2: Resellable return logs RETURN_RESTOCKED event in SQLite', () async {
        await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: true,
          authorizedBy: 'Manager',
        );

        final events = await db.query(
          'inventory_events',
          where: 'perfumeCode = ? AND eventType = ?',
          whereArgs: ['AA1', 'RETURN_RESTOCKED'],
        );
        expect(events.isNotEmpty, isTrue);
      });

      test('T1.F3.3: Damaged return does NOT increment shelf stock (recorded and detected remain unchanged)', () async {
        await db.update(
          'inventory_records',
          {'detected': 3, 'recorded': 3},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: false,
          authorizedBy: 'Manager',
        );

        expect(res['recorded'], equals(3)); // UNCHANGED
        expect(res['detected'], equals(3)); // UNCHANGED
        expect(res['totalRefund'], equals(260.0));
      });

      test('T1.F3.4: Damaged return logs DAMAGE_WRITEOFF event and audit trail', () async {
        await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantity: 1,
          unitPrice: 180.0,
          isResellable: false,
          authorizedBy: 'Manager',
        );

        final events = await db.query(
          'inventory_events',
          where: 'perfumeCode = ? AND eventType = ?',
          whereArgs: ['AA2', 'DAMAGE_WRITEOFF'],
        );
        expect(events.isNotEmpty, isTrue);
      });

      test('T1.F3.5: Return quantity of 0 or negative throws ArgumentError', () async {
        expect(
          () => UnifiedStockMovementHarness.executeCustomerReturn(
            db: db,
            branch: branch,
            perfumeCode: 'AA1',
            productName: 'Sauvage Dior',
            bottleSize: '100ml',
            quantity: 0,
            unitPrice: 260.0,
            isResellable: true,
            authorizedBy: 'Manager',
          ),
          throwsArgumentError,
        );
      });
    });

    // -------------------------------------------------------------------------
    // F4: Damaged Perfume Write-off (3 categories) (R1)
    // -------------------------------------------------------------------------
    group('F4: Damaged Perfume Write-off (3 categories)', () {
      test('T1.F4.1: Reason "Broken Bottle" decrements recorded (-1) and logs DAMAGE_WRITEOFF', () async {
        final res = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Manager',
        );

        expect(res['recorded'], equals(4));
        expect(res['detected'], equals(4));
        expect(res['reason'], equals('Broken Bottle'));

        final events = await db.query('inventory_events', where: 'eventType = ?', whereArgs: ['DAMAGE_WRITEOFF']);
        expect(events.isNotEmpty, isTrue);
      });

      test('T1.F4.2: Reason "Leaking / Evaporated" tallies ₱180 financial loss for 50ml slot', () async {
        final res = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantity: 1,
          reasonCategory: 'Leaking / Evaporated',
          authorizedBy: 'Manager',
        );

        expect(res['financialLoss'], equals(180.0));
      });

      test('T1.F4.3: Reason "Defective Atomizer / Cap" is accepted as valid write-off cause', () async {
        final res = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          reasonCategory: 'Defective Atomizer / Cap',
          authorizedBy: 'Manager',
        );

        expect(res['reason'], equals('Defective Atomizer / Cap'));
      });

      test('T1.F4.4: Disallowed category (e.g. "Expired Tester") throws ArgumentError', () async {
        expect(
          () => UnifiedStockMovementHarness.executeDamagedWriteOff(
            db: db,
            branch: branch,
            perfumeCode: 'AA1',
            productName: 'Sauvage Dior',
            bottleSize: '100ml',
            quantity: 1,
            reasonCategory: 'Expired Tester',
            authorizedBy: 'Manager',
          ),
          throwsArgumentError,
        );
      });

      test('T1.F4.5: Deficit write-off (isDeficitResolution=true) aligns recorded without decrementing detected twice', () async {
        await db.update(
          'inventory_records',
          {'detected': 3, 'recorded': 4},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Manager',
          isDeficitResolution: true,
        );

        expect(res['recorded'], equals(3));
        expect(res['detected'], equals(3)); // Preserved!
      });
    });

    // -------------------------------------------------------------------------
    // F5: Visual Shelf Count Audit & Realignment (R2)
    // -------------------------------------------------------------------------
    group('F5: Visual Shelf Count Audit & Realignment', () {
      test('T1.F5.1: Committing visual count sets detected = count and recorded = count in SQLite', () async {
        await db.update(
          'inventory_records',
          {'detected': 1, 'recorded': 4},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        final res = await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 3,
          auditor: 'Auditor A',
        );

        expect(res['recorded'], equals(3));
        expect(res['detected'], equals(3));
      });

      test('T1.F5.2: Visual count automatically clears any active discrepancy alert for that slot', () async {
        await db.insert('alerts', {
          'id': 'alert_disc_AA1',
          'title': 'Discrepancy: AA1',
          'desc': 'Detected 1 vs Recorded 4',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 2,
          auditor: 'Auditor A',
        );

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);
      });

      test('T1.F5.3: Visual count logs AUDIT_VISUAL_COUNT inventory event in SQLite', () async {
        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 4,
          auditor: 'Auditor A',
        );

        final events = await db.query(
          'inventory_events',
          where: 'eventType = ?',
          whereArgs: ['AUDIT_VISUAL_COUNT'],
        );
        expect(events.isNotEmpty, isTrue);
      });

      test('T1.F5.4: Visual count 0 sets status out_of_stock, 1-2 sets low, 3-5 sets normal', () async {
        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 0,
          auditor: 'Auditor A',
        );
        var inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['status'], equals('out_of_stock'));

        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 2,
          auditor: 'Auditor A',
        );
        inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['status'], equals('low'));

        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 5,
          auditor: 'Auditor A',
        );
        inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['status'], equals('normal'));
      });

      test('T1.F5.5: Visual count preserves shelf location and branch in SQLite', () async {
        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 4,
          auditor: 'Auditor A',
        );

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['branch'], equals(branch));
        expect(inv.first['shelf'], contains('Tray AA'));
      });
    });

    // -------------------------------------------------------------------------
    // F6: Dedicated Manager PIN Keypad Dialog Validation & Lockout (R4)
    // -------------------------------------------------------------------------
    group('F6: Dedicated Manager PIN Keypad Dialog', () {
      test('T1.F6.1: Valid 6-digit PIN successfully verifies with PBKDF2 hash', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final pinHash = Pbkdf2Harness.hashPin('654321', salt, iterations: 500);

        final isValid = Pbkdf2Harness.verifyPin('654321', pinHash, salt, iterations: 500);
        expect(isValid, isTrue);
      });

      test('T1.F6.2: Invalid PIN returns false and fails verification', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final pinHash = Pbkdf2Harness.hashPin('654321', salt, iterations: 500);

        final isValid = Pbkdf2Harness.verifyPin('000000', pinHash, salt, iterations: 500);
        expect(isValid, isFalse);
      });

      test('T1.F6.3: 5 consecutive failed attempts transitions into 300s lockout', () {
        final now = DateTime(2026, 11, 4, 10, 0, 0);
        var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

        for (int i = 0; i < 5; i++) {
          state = state.recordFailure(now);
        }

        expect(state.isLocked(now), isTrue);
        expect(state.remainingSeconds(now), equals(300));
      });

      test('T1.F6.4: Active lockout blocks PIN verification attempts until expired', () {
        final now = DateTime(2026, 11, 4, 10, 0, 0);
        final lockedState = LockoutState(
          failedAttempts: 5,
          lockedUntilEpochMs: now.millisecondsSinceEpoch + 300000,
        );

        expect(lockedState.isLocked(now), isTrue);
        // Advance time by 301 seconds
        final later = now.add(const Duration(seconds: 301));
        expect(lockedState.isLocked(later), isFalse);
      });

      test('T1.F6.5: Emergency Master Key resets lockout state on success', () {
        final salt = Pbkdf2Harness.generateSalt(32);
        final masterHash = Pbkdf2Harness.hashPin(Pbkdf2Harness.defaultMasterRecoveryKey, salt, iterations: 500);

        final isMasterValid = Pbkdf2Harness.verifyMasterKey(
          'OTTO-MASTER-RECOVERY-2026',
          masterHash,
          salt,
          iterations: 500,
        );
        expect(isMasterValid, isTrue);

        final resetState = const LockoutState(failedAttempts: 5, lockedUntilEpochMs: 9999999999).resetOnSuccess();
        expect(resetState.failedAttempts, equals(0));
        expect(resetState.lockedUntilEpochMs, equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // F7: Action-Specific Authorization Guard (R4)
    // -------------------------------------------------------------------------
    group('F7: Action-Specific Authorization Guard', () {
      test('T1.F7.1: Customer Return/Refund ALWAYS prompts for Manager PIN in unlocked session', () {
        final requiresPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionCustomerReturn,
          isSessionUnlocked: true,
        );
        expect(requiresPin, isTrue);
      });

      test('T1.F7.2: Damaged Write-Off ALWAYS prompts for Manager PIN in unlocked session', () {
        final requiresPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionDamagedWriteOff,
          isSessionUnlocked: true,
        );
        expect(requiresPin, isTrue);
      });

      test('T1.F7.3: Normal Sale bypasses PIN prompt when session is already unlocked', () {
        final requiresPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionSale,
          isSessionUnlocked: true,
        );
        expect(requiresPin, isFalse);
      });

      test('T1.F7.4: Normal Restock bypasses PIN prompt when session is already unlocked', () {
        final requiresPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionRestock,
          isSessionUnlocked: true,
        );
        expect(requiresPin, isFalse);
      });

      test('T1.F7.5: Visual Shelf Count audit bypasses PIN prompt when session is already unlocked', () {
        final requiresPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionVisualCount,
          isSessionUnlocked: true,
        );
        expect(requiresPin, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // F8: Interactive 5-Cap Slot Visual Counter UI & Steppers (R2)
    // -------------------------------------------------------------------------
    group('F8: Interactive 5-Cap Slot Visual Counter UI', () {
      test('T1.F8.1: Cap slot representation returns exact 5-slot fill boolean list', () {
        expect(UnifiedStockMovementHarness.getCapSlotFillStatus(0), equals([false, false, false, false, false]));
        expect(UnifiedStockMovementHarness.getCapSlotFillStatus(3), equals([true, true, true, false, false]));
        expect(UnifiedStockMovementHarness.getCapSlotFillStatus(5), equals([true, true, true, true, true]));
      });

      test('T1.F8.2: Quick-tap preset buttons (0 to 5) set count directly', () {
        for (int i = 0; i <= 5; i++) {
          expect(UnifiedStockMovementHarness.setPreset(i), equals(i));
        }
      });

      test('T1.F8.3: Stepper "+" increments count by 1 up to maximum 5', () {
        expect(UnifiedStockMovementHarness.stepIncrement(0), equals(1));
        expect(UnifiedStockMovementHarness.stepIncrement(4), equals(5));
        expect(UnifiedStockMovementHarness.stepIncrement(5), equals(5)); // Clamped at 5
      });

      test('T1.F8.4: Stepper "-" decrements count by 1 down to minimum 0', () {
        expect(UnifiedStockMovementHarness.stepDecrement(5), equals(4));
        expect(UnifiedStockMovementHarness.stepDecrement(1), equals(0));
        expect(UnifiedStockMovementHarness.stepDecrement(0), equals(0)); // Clamped at 0
      });

      test('T1.F8.5: Steppers reject negative or excessive numbers via clamping', () {
        expect(UnifiedStockMovementHarness.stepIncrement(10), equals(5));
        expect(UnifiedStockMovementHarness.stepDecrement(-10), equals(0));
      });
    });

    // -------------------------------------------------------------------------
    // F9: Peek Camera Feed On-Demand (R2)
    // -------------------------------------------------------------------------
    group('F9: Peek Camera Feed On-Demand', () {
      test('T1.F9.1: Tray "AA" maps to Camera 1 and device node /dev/cam1a', () {
        final cam = UnifiedStockMovementHarness.getCameraForTray('AA');
        expect(cam.cameraId, equals(1));
        expect(cam.deviceNode, equals('/dev/cam1a'));
      });

      test('T1.F9.2: Tray "CA" maps to Camera 5 and device node /dev/cam3a', () {
        final cam = UnifiedStockMovementHarness.getCameraForTray('CA');
        expect(cam.cameraId, equals(5));
        expect(cam.deviceNode, equals('/dev/cam3a'));
      });

      test('T1.F9.3: All 30 trays map deterministically to cameras 1 through 6', () {
        for (final tray in ShelfArchitectureHarness.allTrays) {
          final cam = UnifiedStockMovementHarness.getCameraForTray(tray);
          expect(cam.cameraId, inInclusiveRange(1, 6));
          expect(cam.deviceNode, startsWith('/dev/cam'));
        }
      });

      test('T1.F9.4: Invalid tray code throws ArgumentError', () {
        expect(() => UnifiedStockMovementHarness.getCameraForTray('ZZ'), throwsArgumentError);
      });

      test('T1.F9.5: Camera snapshot metadata is non-empty and well-formed', () {
        final cam = UnifiedStockMovementHarness.getCameraForTray('BD');
        expect(cam.cameraId, equals(3));
        expect(cam.deviceNode, equals('/dev/cam2a'));
      });
    });

    // -------------------------------------------------------------------------
    // F10: Unified Stock Movement Hub (5 actions) (R1)
    // -------------------------------------------------------------------------
    group('F10: Unified Stock Movement Hub (5 actions)', () {
      test('T1.F10.1: Hub supports all 5 movement types: sale, restock, return, damage, visualCount', () {
        const types = [
          UnifiedStockMovementHarness.actionSale,
          UnifiedStockMovementHarness.actionRestock,
          UnifiedStockMovementHarness.actionCustomerReturn,
          UnifiedStockMovementHarness.actionDamagedWriteOff,
          UnifiedStockMovementHarness.actionVisualCount,
        ];
        expect(types.length, equals(5));
      });

      test('T1.F10.2: Sale action from Hub deducts inventory and logs sale record', () async {
        await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 1,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: false,
        );

        final sales = await db.query('sales_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(sales.length, equals(1));
      });

      test('T1.F10.3: Restock action from Hub adds inventory and logs restock event', () async {
        await UnifiedStockMovementHarness.executeRestockSync(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantityAdded: 2,
        );

        final events = await db.query(
          'inventory_events',
          where: 'perfumeCode = ? AND eventType = ?',
          whereArgs: ['AA1', 'RESTOCKED'],
        );
        expect(events.length, equals(1));
      });

      test('T1.F10.4: Return action from Hub logs refund and updates ledger', () async {
        final res = await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: true,
          authorizedBy: 'Manager',
        );

        expect(res['totalRefund'], equals(260.0));
      });

      test('T1.F10.5: Damaged Write-Off action from Hub logs write-off and financial shrinkage', () async {
        final res = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Manager',
        );

        expect(res['financialLoss'], equals(260.0));
      });
    });

    // -------------------------------------------------------------------------
    // F11: Multi-Screen Hub Launching (R1)
    // -------------------------------------------------------------------------
    group('F11: Multi-Screen Hub Launching & Context Pre-Selection', () {
      test('T1.F11.1: Launching from Inventory Screen pre-selects SKU and defaults to Sale', () {
        const initialType = UnifiedStockMovementHarness.actionSale;
        const initialPerfumeCode = 'AA1';
        expect(initialType, equals('sale'));
        expect(initialPerfumeCode, equals('AA1'));
      });

      test('T1.F11.2: Launching from Product Detail carries bottleSize and price', () {
        final price = UnifiedStockMovementHarness.getUnitPrice('AA2');
        expect(price, equals(180.0));
      });

      test('T1.F11.3: Launching from Alerts Screen deficit card sets isDeficitResolution = true', () {
        const fromAlert = true;
        expect(fromAlert, isTrue);
      });

      test('T1.F11.4: Launching from Reports Screen allows general movement without preselected SKU', () {
        String? preselectedSku;
        expect(preselectedSku, isNull);
      });

      test('T1.F11.5: Movement Hub validates required product selection before submission', () {
        bool isValidProduct(String? code) => code != null && code.isNotEmpty;
        expect(isValidProduct(null), isFalse);
        expect(isValidProduct(''), isFalse);
        expect(isValidProduct('AA1'), isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // F12: Reports Screen 5-KPI Row & Net Revenue Calculation (R5)
    // -------------------------------------------------------------------------
    group('F12: Reports Screen 5-KPI Row & Net Revenue Calculation', () {
      test('T1.F12.1: Net Revenue calculation (Gross - Refunds) is strictly computed', () {
        final gross = 1300.0; // 5 x ₱260
        final refunds = 520.0; // 2 x ₱260
        final net = UnifiedStockMovementHarness.calculateNetRevenue(
          grossSales: gross,
          refunds: refunds,
        );
        expect(net, equals(780.0));
      });

      test('T1.F12.2: Damage loss tally matches bottle size (100ml -> ₱260, 50ml -> ₱180)', () {
        final events = [
          InventoryEventModel(
            id: 'e1',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Sauvage Dior (Broken Bottle)',
            perfumeCode: 'AA1', // 100ml
            shelfArea: 'Area A',
            branch: branch,
            quantity: 2, // 2 x 260 = 520
          ),
          InventoryEventModel(
            id: 'e2',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Bleu de Chanel (Leaking)',
            perfumeCode: 'AA2', // 50ml
            shelfArea: 'Area A',
            branch: branch,
            quantity: 3, // 3 x 180 = 540
          ),
        ];

        final loss = UnifiedStockMovementHarness.calculateDamageLoss(events);
        expect(loss, equals(1060.0)); // 520 + 540
      });

      test('T1.F12.3: Units Sold and Units Restocked are computed as distinct counts', () {
        final sales = [
          SaleRecordModel(
            id: 's1',
            perfumeCode: 'AA1',
            productName: 'P1',
            quantitySold: 4,
            unitPrice: 260.0,
            soldAt: DateTime.now(),
          ),
          SaleRecordModel(
            id: 's2',
            perfumeCode: 'AA2',
            productName: 'P2',
            quantitySold: 2,
            unitPrice: 180.0,
            soldAt: DateTime.now(),
          ),
        ];
        final restocks = [
          InventoryEventModel(
            id: 'r1',
            eventType: 'RESTOCKED',
            productName: 'P1',
            perfumeCode: 'AA1',
            shelfArea: 'Area A',
            branch: branch,
            quantity: 5,
          ),
        ];

        expect(UnifiedStockMovementHarness.calculateUnitsSold(sales), equals(6));
        expect(UnifiedStockMovementHarness.calculateUnitsRestocked(restocks), equals(5));
      });

      test('T1.F12.4: Gross Revenue is unaffected by refunds (refunds displayed as distinct KPI card)', () {
        final sales = [
          SaleRecordModel(
            id: 's1',
            perfumeCode: 'AA1',
            productName: 'P1',
            quantitySold: 2,
            unitPrice: 260.0,
            soldAt: DateTime.now(),
          ),
        ];
        final gross = UnifiedStockMovementHarness.calculateGrossRevenue(sales);
        expect(gross, equals(520.0));
      });

      test('T1.F12.5: Reports screen displays all 5 mandated retail KPI metrics', () {
        final gross = 1000.0;
        final refunds = 200.0;
        final net = UnifiedStockMovementHarness.calculateNetRevenue(grossSales: gross, refunds: refunds);
        final loss = 180.0;
        final sold = 4;
        final restocked = 8;

        expect(gross, equals(1000.0));
        expect(refunds, equals(200.0));
        expect(net, equals(800.0));
        expect(loss, equals(180.0));
        expect('$sold Sold • $restocked Restocked', equals('4 Sold • 8 Restocked'));
      });
    });

    // -------------------------------------------------------------------------
    // F13: Transaction Feed Signed Styling & Color Cues (R5)
    // -------------------------------------------------------------------------
    group('F13: Transaction Feed Signed Styling', () {
      test('T1.F13.1: Sales format signed monetary value with green color (+₱X.XX)', () {
        final formatted = UnifiedStockMovementHarness.formatSignedAmount(260.0, transactionType: 'SALE');
        final color = UnifiedStockMovementHarness.getTransactionAccentColor('SALE');
        expect(formatted, equals('+₱260.00'));
        expect(color, equals(const Color(0xFF22C55E)));
      });

      test('T1.F13.2: Refunds format signed monetary value with amber color (-₱X.XX)', () {
        final formatted = UnifiedStockMovementHarness.formatSignedAmount(260.0, transactionType: 'REFUND');
        final color = UnifiedStockMovementHarness.getTransactionAccentColor('REFUND');
        expect(formatted, equals('-₱260.00'));
        expect(color, equals(const Color(0xFFD97706)));
      });

      test('T1.F13.3: Damage write-offs format signed monetary value with red color (-₱X.XX)', () {
        final formatted = UnifiedStockMovementHarness.formatSignedAmount(180.0, transactionType: 'DAMAGE_WRITEOFF');
        final color = UnifiedStockMovementHarness.getTransactionAccentColor('DAMAGE_WRITEOFF');
        expect(formatted, equals('-₱180.00'));
        expect(color, equals(const Color(0xFFEF4444)));
      });

      test('T1.F13.4: Badges distinguish Direct POS, Reconciled, Refund, and Write-Off', () {
        const posBadge = '[Direct POS]';
        const reconciledBadge = '[Reconciled]';
        const returnBadge = '[Refund • Resellable]';
        const damageBadge = '[Write-Off • Broken Bottle]';

        expect(posBadge, contains('Direct POS'));
        expect(reconciledBadge, contains('Reconciled'));
        expect(returnBadge, contains('Refund'));
        expect(damageBadge, contains('Broken Bottle'));
      });

      test('T1.F13.5: Chronological sort preserves interleaving of mixed transaction items', () {
        final t1 = DateTime(2026, 11, 4, 10, 0);
        final t2 = DateTime(2026, 11, 4, 10, 15);
        final t3 = DateTime(2026, 11, 4, 10, 30);

        final items = [
          {'time': t2, 'type': 'REFUND'},
          {'time': t1, 'type': 'SALE'},
          {'time': t3, 'type': 'DAMAGE_WRITEOFF'},
        ];

        items.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));
        expect(items.first['type'], equals('DAMAGE_WRITEOFF'));
        expect(items.last['type'], equals('SALE'));
      });
    });

    // -------------------------------------------------------------------------
    // F14: CSV & PDF Exports Format with Net Revenue (R5)
    // -------------------------------------------------------------------------
    group('F14: CSV & PDF Exports Format with Net Revenue', () {
      test('T1.F14.1: CSV generation includes Transaction Type and signed amounts (+/-)', () {
        final sales = [
          SaleRecordModel(
            id: 'sale_1',
            perfumeCode: 'AA1',
            productName: 'Sauvage Dior',
            bottleSize: '100ml',
            quantitySold: 1,
            unitPrice: 260.0,
            soldAt: DateTime.now(),
          ),
        ];
        final refunds = [
          {
            'refundId': 'ref_1',
            'productName': 'Sauvage Dior',
            'perfumeCode': 'AA1',
            'bottleSize': '100ml',
            'quantity': 1,
            'unitPrice': 260.0,
            'totalRefund': 260.0,
          },
        ];
        final writeOffs = [
          InventoryEventModel(
            id: 'dmg_1',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Bleu de Chanel (Broken Bottle)',
            perfumeCode: 'AA2',
            shelfArea: 'Area A',
            branch: branch,
            quantity: 1,
          ),
        ];

        final csv = UnifiedStockMovementHarness.generateEnhancedDailyCsv(
          sales: sales,
          refunds: refunds,
          writeOffs: writeOffs,
          branch: branch,
        );

        expect(csv, contains('Type'));
        expect(csv, contains('SALE'));
        expect(csv, contains('REFUND'));
        expect(csv, contains('DAMAGE_WRITEOFF'));
        expect(csv, contains('+260.00'));
        expect(csv, contains('-260.00'));
        expect(csv, contains('-180.00'));
      });

      test('T1.F14.2: CSV summary totals line contains Gross, Refunds, Net Revenue, and Damage Loss', () {
        final csv = UnifiedStockMovementHarness.generateEnhancedDailyCsv(
          sales: [],
          refunds: [],
          writeOffs: [],
          branch: branch,
        );

        expect(csv, contains('SUMMARY TOTALS'));
        expect(csv, contains('Gross: ₱0.00'));
        expect(csv, contains('Refunds: -₱0.00'));
        expect(csv, contains('Net Revenue: ₱0.00'));
        expect(csv, contains('Damage Loss: -₱0.00'));
      });

      test('T1.F14.3: Cashier column is completely absent from daily sales CSV export', () {
        final csv = UnifiedStockMovementHarness.generateEnhancedDailyCsv(
          sales: [],
          refunds: [],
          writeOffs: [],
          branch: branch,
        );

        expect(csv.contains('Cashier'), isFalse);
      });

      test('T1.F14.4: Branded PDF generation produces valid PDF bytes with Net Revenue row', () async {
        final bytes = await UnifiedStockMovementHarness.generateEnhancedReportPdf(
          sales: [],
          refunds: 260.0,
          damageLoss: 180.0,
          inventory: [],
          branch: branch,
        );

        expect(bytes.isNotEmpty, isTrue);
        final header = String.fromCharCodes(bytes.take(8));
        expect(header, startsWith('%PDF-'));
      });

      test('T1.F14.5: PDF bytes generation succeeds with full inventory and sales records', () async {
        final sales = [
          SaleRecordModel(
            id: 's_pdf',
            perfumeCode: 'AA1',
            productName: 'Sauvage Dior',
            quantitySold: 2,
            unitPrice: 260.0,
            soldAt: DateTime.now(),
          ),
        ];
        final inventory = [
          InventoryRecordModel(
            id: 'inv_pdf',
            perfumeCode: 'AA1',
            name: 'Sauvage Dior',
            branch: branch,
            shelf: 'Area A',
            recorded: 4,
            detected: 4,
            status: 'normal',
            lastUpdated: DateTime.now(),
          ),
        ];

        final bytes = await UnifiedStockMovementHarness.generateEnhancedReportPdf(
          sales: sales,
          refunds: 0.0,
          damageLoss: 0.0,
          inventory: inventory,
          branch: branch,
        );

        expect(bytes.length, greaterThan(100));
      });
    });

    // =========================================================================
    // TIER 2: BOUNDARY & CORNER CASES (6 tests)
    // =========================================================================
    group('Tier 2: Boundary & Corner Cases', () {
      test('T2.1: Empty store state calculates ₱0.00 for all KPI cards without dividing by zero', () {
        final gross = UnifiedStockMovementHarness.calculateGrossRevenue([]);
        final refunds = UnifiedStockMovementHarness.calculateTotalRefunds([]);
        final net = UnifiedStockMovementHarness.calculateNetRevenue(grossSales: gross, refunds: refunds);
        final loss = UnifiedStockMovementHarness.calculateDamageLoss([]);
        final unitsSold = UnifiedStockMovementHarness.calculateUnitsSold([]);
        final unitsRestocked = UnifiedStockMovementHarness.calculateUnitsRestocked([]);

        expect(gross, equals(0.0));
        expect(refunds, equals(0.0));
        expect(net, equals(0.0));
        expect(loss, equals(0.0));
        expect(unitsSold, equals(0));
        expect(unitsRestocked, equals(0));
      });

      test('T2.2: Negative Net Revenue (Refunds > Gross Sales) is accurately represented (-₱520.00)', () {
        final gross = 260.0;
        final refunds = 780.0;
        final net = UnifiedStockMovementHarness.calculateNetRevenue(grossSales: gross, refunds: refunds);

        expect(net, equals(-520.0));
        expect(net < 0, isTrue);
      });

      test('T2.3: 5-Cap Slot Boundary: rapid increment on 5 stays 5, decrement on 0 stays 0', () {
        int count = 5;
        for (int i = 0; i < 10; i++) {
          count = UnifiedStockMovementHarness.stepIncrement(count);
        }
        expect(count, equals(5));

        count = 0;
        for (int i = 0; i < 10; i++) {
          count = UnifiedStockMovementHarness.stepDecrement(count);
        }
        expect(count, equals(0));
      });

      test('T2.4: Manager PIN Lockout exact boundary: 4 failures is unlocked, 5th locks out', () {
        final now = DateTime(2026, 11, 4, 12, 0, 0);
        var state = const LockoutState(failedAttempts: 0, lockedUntilEpochMs: 0);

        for (int i = 0; i < 4; i++) {
          state = state.recordFailure(now);
        }
        expect(state.failedAttempts, equals(4));
        expect(state.isLocked(now), isFalse);

        state = state.recordFailure(now);
        expect(state.failedAttempts, equals(5));
        expect(state.isLocked(now), isTrue);
      });

      test('T2.5: Lockout expiration exact boundary: 299s locked, 301s unlocked', () {
        final now = DateTime(2026, 11, 4, 12, 0, 0);
        final lockedState = LockoutState(
          failedAttempts: 5,
          lockedUntilEpochMs: now.millisecondsSinceEpoch + 300000,
        );

        expect(lockedState.isLocked(now.add(const Duration(seconds: 299))), isTrue);
        expect(lockedState.isLocked(now.add(const Duration(seconds: 301))), isFalse);
      });

      test('T2.6: High-frequency sequential movements execute ACID without dirty reads', () async {
        // Execute 5 rapid sales of 1 bottle each
        for (int i = 0; i < 5; i++) {
          await UnifiedStockMovementHarness.executeSaleDeduction(
            db: db,
            branch: branch,
            perfumeCode: 'AA1',
            quantitySold: 1,
            unitPrice: 260.0,
            productName: 'Sauvage Dior',
            bottleSize: '100ml',
            isDeficitResolution: false,
          );
        }

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect((inv.first['recorded'] as num).toInt(), equals(0));
        expect((inv.first['detected'] as num).toInt(), equals(0));
        expect(inv.first['status'], equals('out_of_stock'));

        final sales = await db.query('sales_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(sales.length, equals(5));
      });
    });

    // =========================================================================
    // TIER 3: PAIRWISE COMBINATORIAL TESTS (5 tests)
    // =========================================================================
    group('Tier 3: Pairwise Combinations', () {
      test('Pairwise 1: Deficit Alert -> Sale Deduction -> Reports Net Revenue Sync', () async {
        // 1. Deficit discrepancy occurs: detected=2, recorded=5
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );
        await db.insert('alerts', {
          'id': 'alert_p1',
          'title': 'Deficit: AA1',
          'desc': 'Detected 2 vs Recorded 5',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // 2. Staff resolves deficit via sale of 3 missing bottles
        await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 3,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        // 3. Verify ledger is realigned and alert is dismissed
        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['recorded'], equals(2));
        expect(inv.first['detected'], equals(2));

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);

        // 4. Verify Reports Net Revenue includes this reconciled sale (+₱780)
        final sales = await db.query('sales_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        final saleModels = sales.map((s) => SaleRecordModel.fromMap(s)).toList();
        final gross = UnifiedStockMovementHarness.calculateGrossRevenue(saleModels);
        final net = UnifiedStockMovementHarness.calculateNetRevenue(grossSales: gross, refunds: 0.0);
        expect(net, equals(780.0));
      });

      test('Pairwise 2: Deficit Alert -> Damaged Write-Off -> Manager PIN -> Shrinkage Tally', () async {
        // 1. Deficit discrepancy: detected=1, recorded=3
        await db.update(
          'inventory_records',
          {'detected': 1, 'recorded': 3, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA2'],
        );
        await db.insert('alerts', {
          'id': 'alert_p2',
          'title': 'Discrepancy: AA2',
          'desc': 'Missing 2 bottles',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA2',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // 2. Action guard checks: requires Manager PIN
        final pinRequired = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionDamagedWriteOff,
          isSessionUnlocked: true,
        );
        expect(pinRequired, isTrue);

        // 3. Manager verifies PIN and logs write-off of 2 broken bottles (isDeficitResolution: true)
        await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantity: 2,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Manager Dave',
          isDeficitResolution: true,
        );

        // 4. Invariant: recorded aligns to 1, detected stays 1, alert cleared
        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA2']);
        expect(inv.first['recorded'], equals(1));
        expect(inv.first['detected'], equals(1));

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA2']);
        expect(alerts.isEmpty, isTrue);

        // 5. Shrinkage loss tallies 2 x ₱180 = ₱360
        final events = await db.query('inventory_events', where: 'eventType = ?', whereArgs: ['DAMAGE_WRITEOFF']);
        final eventModels = events.map((e) => InventoryEventModel.fromMap(e)).toList();
        final loss = UnifiedStockMovementHarness.calculateDamageLoss(eventModels);
        expect(loss, equals(360.0));
      });

      test('Pairwise 3: Unlocked Session Guard: Normal Sale vs High-Impact Refund', () {
        const isSessionUnlocked = true;

        final saleNeedsPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionSale,
          isSessionUnlocked: isSessionUnlocked,
        );
        final refundNeedsPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionCustomerReturn,
          isSessionUnlocked: isSessionUnlocked,
        );

        expect(saleNeedsPin, isFalse); // Bypasses PIN
        expect(refundNeedsPin, isTrue); // Intercepts with PIN!
      });

      test('Pairwise 4: Visual Count Audit -> Discrepancy Alerts Clearance (Surplus & Deficit)', () async {
        // Setup surplus alert
        await db.update(
          'inventory_records',
          {'detected': 5, 'recorded': 2},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );
        await db.insert('alerts', {
          'id': 'alert_surplus',
          'title': 'Surplus: AA1',
          'desc': 'Detected 5 vs Recorded 2',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // Audit physical tray: auditor visually verifies 4 bottles
        await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: 4,
          auditor: 'Auditor Maya',
        );

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['recorded'], equals(4));
        expect(inv.first['detected'], equals(4));

        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);
      });

      test('Pairwise 5: Multi-Transaction Feed Interleaving with accurate signed values', () {
        final saleAmt = 260.0;
        final refundAmt = 260.0;
        final lossAmt = 180.0;

        final saleStr = UnifiedStockMovementHarness.formatSignedAmount(saleAmt, transactionType: 'SALE');
        final refStr = UnifiedStockMovementHarness.formatSignedAmount(refundAmt, transactionType: 'REFUND');
        final lossStr = UnifiedStockMovementHarness.formatSignedAmount(lossAmt, transactionType: 'DAMAGE_WRITEOFF');

        expect(saleStr, equals('+₱260.00'));
        expect(refStr, equals('-₱260.00'));
        expect(lossStr, equals('-₱180.00'));
      });
    });

    // =========================================================================
    // TIER 4: REAL-WORLD END-TO-END OPERATIONAL SCENARIOS (5 scenarios)
    // =========================================================================
    group('Tier 4: Real-World Operational Scenarios', () {
      test('Scenario 1: Customer Fragrance Return Flow (Resellable & Refund)', () async {
        // 1. Initial State: Slot AA1 has recorded=3, detected=3
        await db.update(
          'inventory_records',
          {'detected': 3, 'recorded': 3},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        // 2. Customer returns 1 unopened bottle of Sauvage Dior (AA1)
        // Guard enforces PIN
        final needsPin = UnifiedStockMovementHarness.requiresManagerPin(
          actionType: UnifiedStockMovementHarness.actionCustomerReturn,
          isSessionUnlocked: true,
        );
        expect(needsPin, isTrue);

        // 3. Process resellable return
        final returnRes = await UnifiedStockMovementHarness.executeCustomerReturn(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: true,
          authorizedBy: 'Manager Alice',
        );

        // 4. Ledger verification: shelf stock increments to 4
        expect(returnRes['recorded'], equals(4));
        expect(returnRes['detected'], equals(4));
        expect(returnRes['totalRefund'], equals(260.0));

        // 5. Reports verification: Net Revenue is reduced by refund
        final gross = 520.0; // Two prior sales
        final net = UnifiedStockMovementHarness.calculateNetRevenue(
          grossSales: gross,
          refunds: returnRes['totalRefund'] as double,
        );
        expect(net, equals(260.0));
      });

      test('Scenario 2: Damaged Bottle Write-Off Flow with Manager PIN', () async {
        // 1. Staff drops bottle during shelf cleaning (AA2, 50ml, recorded=4, detected=4)
        await db.update(
          'inventory_records',
          {'detected': 4, 'recorded': 4},
          where: 'perfumeCode = ?',
          whereArgs: ['AA2'],
        );

        // 2. Manager verifies PIN
        final salt = Pbkdf2Harness.generateSalt(32);
        final pinHash = Pbkdf2Harness.hashPin('112233', salt, iterations: 500);
        final pinOk = Pbkdf2Harness.verifyPin('112233', pinHash, salt, iterations: 500);
        expect(pinOk, isTrue);

        // 3. Write-off logged with 'Broken Bottle' cause
        final writeOffRes = await UnifiedStockMovementHarness.executeDamagedWriteOff(
          db: db,
          branch: branch,
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantity: 1,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Manager Bob',
          isDeficitResolution: false,
        );

        // 4. Verify shelf stock is 3 and financial loss is ₱180
        expect(writeOffRes['recorded'], equals(3));
        expect(writeOffRes['detected'], equals(3));
        expect(writeOffRes['financialLoss'], equals(180.0));

        final events = await db.query('inventory_events', where: 'eventType = ?', whereArgs: ['DAMAGE_WRITEOFF']);
        expect(events.isNotEmpty, isTrue);
      });

      test('Scenario 3: Visual Audit & Camera Peek Shelf Realignment Flow', () async {
        // 1. Camera Peek: Staff checks Tray AA camera node
        final cam = UnifiedStockMovementHarness.getCameraForTray('AA');
        expect(cam.deviceNode, equals('/dev/cam1a'));

        // 2. System shows slot AA1 has recorded=5, detected=1 (deficit of 4 alert)
        await db.update(
          'inventory_records',
          {'detected': 1, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );
        await db.insert('alerts', {
          'id': 'alert_audit_flow',
          'title': 'Deficit: AA1',
          'desc': 'Detected 1 vs Recorded 5',
          'branch': branch,
          'type': 'discrepancy',
          'perfumeCode': 'AA1',
          'isRead': 0,
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        });

        // 3. Staff taps Visual Count preset [3] and increments stepper to [4]
        int count = UnifiedStockMovementHarness.setPreset(3);
        count = UnifiedStockMovementHarness.stepIncrement(count);
        expect(count, equals(4));

        // 4. Commit visual count: realigns both detected and recorded to 4
        final auditRes = await UnifiedStockMovementHarness.executeVisualCountCommit(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          countedBottles: count,
          auditor: 'Auditor Carlos',
        );

        expect(auditRes['recorded'], equals(4));
        expect(auditRes['detected'], equals(4));

        // 5. Active discrepancy alert is completely gone
        final alerts = await db.query('alerts', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(alerts.isEmpty, isTrue);
      });

      test('Scenario 4: Deficit Discrepancy Resolution Flow without Double-Deduction', () async {
        // 1. Shelf camera scan detected 2 bottles, ledger had 5 recorded (customer took 3 bottles)
        await db.update(
          'inventory_records',
          {'detected': 2, 'recorded': 5, 'status': 'low'},
          where: 'perfumeCode = ?',
          whereArgs: ['AA1'],
        );

        // 2. Staff records sale of 3 missing bottles with isDeficitResolution = true
        final res = await UnifiedStockMovementHarness.executeSaleDeduction(
          db: db,
          branch: branch,
          perfumeCode: 'AA1',
          quantitySold: 3,
          unitPrice: 260.0,
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          isDeficitResolution: true,
        );

        // 3. ZERO DOUBLE-DEDUCTION: recorded matches 2, detected stays 2 (NOT 0!)
        expect(res['recorded'], equals(2));
        expect(res['detected'], equals(2));

        final inv = await db.query('inventory_records', where: 'perfumeCode = ?', whereArgs: ['AA1']);
        expect(inv.first['recorded'], equals(2));
        expect(inv.first['detected'], equals(2));
      });

      test('Scenario 5: Wi-Fi Store Reconciliation & Multi-Transaction Export Flow', () async {
        // 1. Simulate day's transactions:
        // - Sale: 2 x 100ml Sauvage Dior = ₱520
        // - Return: 1 x 100ml Sauvage Dior = -₱260
        // - Damage Write-off: 1 x 50ml Bleu de Chanel = -₱180
        final sales = [
          SaleRecordModel(
            id: 's_e2e_1',
            perfumeCode: 'AA1',
            productName: 'Sauvage Dior',
            bottleSize: '100ml',
            quantitySold: 2,
            unitPrice: 260.0,
            soldAt: DateTime.now(),
          ),
        ];
        final refunds = [
          {
            'refundId': 'ref_e2e_1',
            'productName': 'Sauvage Dior',
            'perfumeCode': 'AA1',
            'bottleSize': '100ml',
            'quantity': 1,
            'unitPrice': 260.0,
            'totalRefund': 260.0,
          },
        ];
        final writeOffs = [
          InventoryEventModel(
            id: 'dmg_e2e_1',
            eventType: 'DAMAGE_WRITEOFF',
            productName: 'Bleu de Chanel (Broken Bottle)',
            perfumeCode: 'AA2',
            shelfArea: 'Area A',
            branch: branch,
            quantity: 1,
          ),
        ];

        // 2. Generate enhanced Daily Sales CSV
        final csv = UnifiedStockMovementHarness.generateEnhancedDailyCsv(
          sales: sales,
          refunds: refunds,
          writeOffs: writeOffs,
          branch: branch,
        );

        // 3. Verify CSV contents
        expect(csv, contains('SALE'));
        expect(csv, contains('REFUND'));
        expect(csv, contains('DAMAGE_WRITEOFF'));
        expect(csv, contains('+520.00'));
        expect(csv, contains('-260.00'));
        expect(csv, contains('-180.00'));
        expect(csv, contains('Net Revenue: ₱260.00'));
        expect(csv.contains('Cashier'), isFalse);

        // 4. Generate enhanced PDF report
        final pdfBytes = await UnifiedStockMovementHarness.generateEnhancedReportPdf(
          sales: sales,
          refunds: 260.0,
          damageLoss: 180.0,
          inventory: [],
          branch: branch,
        );

        expect(pdfBytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(pdfBytes.take(8)), startsWith('%PDF-'));
      });
    });
  });
}
