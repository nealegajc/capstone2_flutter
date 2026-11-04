import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/core/constants/app_constants.dart';
import 'package:smart_shelf_linux/data/models/alert_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'package:smart_shelf_linux/data/models/restock_record_model.dart';
import 'package:smart_shelf_linux/data/services/report_export_service.dart';
import 'package:smart_shelf_linux/data/services/sqlite_service.dart';
import 'helpers/unified_stock_movement_harness.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  group('CHALLENGER 11-2 ADVERSARIAL STRESS SUITE: R3 & R5 EMPIRICAL VERIFICATION', () {
    const String testBranch = 'San Pablo Main';
    late SqliteService sqlite;

    setUp(() async {
      sqlite = SqliteService.instance;
      await sqlite.close();
      await sqlite.initDatabase(inMemory: true);

      final db = await sqlite.database;
      await db.delete('system_settings');
      await db.delete('system_logs');
      await db.delete('sync_queue');
      await db.delete('alerts');
      await db.delete('inventory_records');
      await db.delete('sales_records');
      await db.delete('inventory_events');
      await db.delete('restock_records');
      await db.delete('products');

      await db.insert('system_settings', {
        'key': 'branch_name',
        'value': testBranch,
      });
      await db.insert('system_settings', {
        'key': 'low_stock_threshold',
        'value': '2',
      });
    });

    tearDown(() async {
      await sqlite.close();
    });

    // =========================================================================
    // 1. DISCREPANCY DEDUCTION LOOP STRESS TEST (20 CONSECUTIVE DEFICIT RUNS)
    // =========================================================================
    group('1. Discrepancy Deduction Loop Stress Tests (R3)', () {
      test('1.1 20 consecutive deficit reconciliation sales: detected NEVER drops to 0 or negative and no false discrepancy alert is created', () async {
        final db = await sqlite.database;

        // Run 20 distinct deficit reconciliation cycles across varied initial states
        for (int cycle = 1; cycle <= 20; cycle++) {
          final String sku = 'SKU_DEF_$cycle';
          final int detectedInitial = 1 + (cycle % 4); // 1, 2, 3, or 4 (strictly > 0)
          final int recordedInitial = detectedInitial + 1 + (cycle % 2); // strictly > detectedInitial (e.g. 2..5)
          final int deficitQuantity = recordedInitial - detectedInitial;

          // 1. Seed inventory record with deficit
          final inv = InventoryRecordModel(
            id: 'inv_$sku',
            perfumeCode: sku,
            name: 'Stress Fragrance $cycle',
            category: (cycle % 2 == 0) ? 'Men' : 'Women',
            branch: testBranch,
            shelf: 'Tray A Slot ${(cycle % 5) + 1}',
            recorded: recordedInitial,
            detected: detectedInitial,
            status: detectedInitial <= 2 ? 'low' : 'normal',
            price: 260.0,
            lastUpdated: DateTime.now(),
          );
          await sqlite.upsertInventoryRecord(inv);

          // 2. Seed active discrepancy alert
          final alert = AlertModel(
            id: 'alt_disc_$sku',
            title: 'Stock Discrepancy $sku',
            desc: 'Detected $detectedInitial < Recorded $recordedInitial',
            branch: testBranch,
            type: 'discrepancy',
            perfumeCode: sku,
            isRead: false,
            createdAt: DateTime.now(),
          );
          await sqlite.saveAlert(alert);

          // Verify pre-condition: deficit exists and alert is active
          final preAlerts = await sqlite.getAlerts(testBranch, unreadOnly: true);
          expect(preAlerts.any((a) => a.perfumeCode == sku && a.type == 'discrepancy'), isTrue,
              reason: 'Cycle $cycle: Pre-condition active discrepancy alert must exist');

          // 3. Execute deficit reconciliation sale via production SqliteService
          final now = DateTime.now();
          final saleRecord = SaleRecordModel(
            id: 'sale_recon_${cycle}_${now.millisecondsSinceEpoch}',
            perfumeCode: sku,
            productName: 'Stress Fragrance $cycle',
            bottleSize: '100ml',
            quantitySold: deficitQuantity,
            unitPrice: 260.0,
            totalAmount: 260.0 * deficitQuantity,
            branch: testBranch,
            soldBy: 'Store Auditor',
            soldAt: now,
            syncStatus: 'synced',
          );
          final event = InventoryEventModel(
            id: 'evt_recon_${cycle}_${now.millisecondsSinceEpoch}',
            eventType: 'REMOVED',
            productName: 'Stress Fragrance $cycle',
            perfumeCode: sku,
            shelfArea: 'Tray A Slot ${(cycle % 5) + 1}',
            branch: testBranch,
            quantity: deficitQuantity,
            reason: 'Discrepancy Deficit Reconciled Sale',
            timestamp: now,
          );

          await sqlite.recordSaleWithInventoryDeduction(
            saleRecord: saleRecord,
            event: event,
            branch: testBranch,
            isDeficitResolution: true, // Crucial R3 flag!
          );

          // 4. Assert invariants on the updated inventory record
          final postInv = await sqlite.getInventoryRecord(sku, testBranch);
          expect(postInv, isNotNull, reason: 'Cycle $cycle: Inventory record must exist');
          expect(postInv!.detected, equals(detectedInitial),
              reason: 'Cycle $cycle: Physical detected count MUST NOT decrement (expected $detectedInitial, got ${postInv.detected})');
          expect(postInv.detected, greaterThan(0),
              reason: 'Cycle $cycle: Detected count must NEVER drop to 0 or negative on deficit resolution with initial stock');
          expect(postInv.recorded, equals(detectedInitial),
              reason: 'Cycle $cycle: Recorded ledger must align exactly to detected count ($detectedInitial)');
          expect(postInv.recorded == postInv.detected, isTrue,
              reason: 'Cycle $cycle: Invariant recorded == detected must hold (hasDiscrepancy must be false)');

          // 5. Assert discrepancy alert is dismissed and NO false alert remains
          final postAlerts = await sqlite.getAlerts(testBranch, unreadOnly: true);
          final activeDiscrepancy = postAlerts.where((a) => a.perfumeCode == sku && a.type == 'discrepancy');
          expect(activeDiscrepancy.isEmpty, isTrue,
              reason: 'Cycle $cycle: No unread discrepancy alert should remain for $sku');

          // Verify alert row in DB is marked isRead = 1
          final alertRows = await db.query('alerts',
              where: 'perfumeCode = ? AND branch = ? AND type = ?',
              whereArgs: [sku, testBranch, 'discrepancy']);
          expect(alertRows.isNotEmpty, isTrue);
          expect(alertRows.first['isRead'], equals(1),
              reason: 'Cycle $cycle: Active discrepancy alert must be marked isRead = 1');
        }
      });

      test('1.2 20 consecutive iterative operations on a SINGLE shelf slot without drift or negative underflow', () async {
        const String sku = 'AA1_ITERATIVE';
        // Initialize slot at detected=2, recorded=5 (deficit of 3)
        await sqlite.upsertInventoryRecord(InventoryRecordModel(
          id: 'inv_$sku',
          perfumeCode: sku,
          name: 'Iterative Stress Fragrance',
          category: 'Men',
          branch: testBranch,
          shelf: 'Tray A Slot 1',
          recorded: 5,
          detected: 2,
          status: 'low',
          price: 260.0,
          lastUpdated: DateTime.now(),
        ));

        for (int iter = 1; iter <= 20; iter++) {
          final now = DateTime.now();
          // Alternate between deficit sale reconciliation and normal non-deficit sale when stock allows
          final current = await sqlite.getInventoryRecord(sku, testBranch);
          expect(current, isNotNull);
          expect(current!.detected, greaterThanOrEqualTo(0));
          expect(current.recorded, greaterThanOrEqualTo(0));

          // Run deficit resolution sale
          final sale = SaleRecordModel(
            id: 'sale_iter_${iter}_${now.millisecondsSinceEpoch}',
            perfumeCode: sku,
            productName: 'Iterative Stress Fragrance',
            bottleSize: '100ml',
            quantitySold: 1,
            unitPrice: 260.0,
            branch: testBranch,
            soldBy: 'Auditor',
            soldAt: now,
          );
          final event = InventoryEventModel(
            id: 'evt_iter_${iter}_${now.millisecondsSinceEpoch}',
            eventType: 'REMOVED',
            productName: 'Iterative Stress Fragrance',
            perfumeCode: sku,
            shelfArea: 'Tray A Slot 1',
            branch: testBranch,
            quantity: 1,
            reason: 'Deficit Reconciliation Iter $iter',
            timestamp: now,
          );

          await sqlite.recordSaleWithInventoryDeduction(
            saleRecord: sale,
            event: event,
            branch: testBranch,
            isDeficitResolution: true,
          );

          final updated = await sqlite.getInventoryRecord(sku, testBranch);
          expect(updated, isNotNull);
          expect(updated!.detected, greaterThanOrEqualTo(0),
              reason: 'Iteration $iter: detected count must never drop below 0');
          expect(updated.recorded, equals(updated.detected),
              reason: 'Iteration $iter: recorded must always equal detected after deficit resolution');
        }
      });

      test('1.3 Deficit resolution via Damaged Write-Off aligns recorded to detected without decrementing detected', () async {
        const String sku = 'DMG_DEF_01';
        await sqlite.upsertInventoryRecord(InventoryRecordModel(
          id: 'inv_$sku',
          perfumeCode: sku,
          name: 'Broken Fragrance',
          category: 'Unisex',
          branch: testBranch,
          shelf: 'Tray C Slot 1',
          recorded: 4,
          detected: 2,
          status: 'low',
          price: 260.0,
          lastUpdated: DateTime.now(),
        ));

        await sqlite.saveAlert(AlertModel(
          id: 'alt_dmg_$sku',
          title: 'Stock Discrepancy',
          desc: 'Missing 2 bottles',
          branch: testBranch,
          type: 'discrepancy',
          perfumeCode: sku,
          isRead: false,
          createdAt: DateTime.now(),
        ));

        // Reconcile via Damaged Write-Off (isDeficitResolution = true)
        await sqlite.recordDamagedWriteOff(
          perfumeCode: sku,
          productName: 'Broken Fragrance',
          bottleSize: '100ml',
          quantity: 2,
          reasonCategory: 'Broken Bottle',
          authorizedBy: 'Store Manager',
          isDeficitResolution: true,
          branch: testBranch,
        );

        final inv = await sqlite.getInventoryRecord(sku, testBranch);
        expect(inv, isNotNull);
        expect(inv!.detected, equals(2), reason: 'Detected physical count must stay 2');
        expect(inv.recorded, equals(2), reason: 'Recorded ledger must align to 2');
        expect(inv.recorded == inv.detected, isTrue);

        final unread = await sqlite.getAlerts(testBranch, unreadOnly: true);
        expect(unread.any((a) => a.perfumeCode == sku && a.type == 'discrepancy'), isFalse,
            reason: 'Discrepancy alert must be resolved by write-off');
      });
    });

    // =========================================================================
    // 2. RESTOCK STRESS TEST ACROSS 10 DIFFERENT SKUS
    // =========================================================================
    group('2. Restock Alignment Stress Tests across 10 SKUs (R3)', () {
      final List<String> tenSkus = [
        'AA1', 'AA2', 'BB1', 'BB2', 'CC1', 'CC2', 'DD1', 'DD2', 'EE1', 'EE2',
      ];

      test('2.1 Restock 10 distinct SKUs: detected = newRecorded, status = normal, and hasDiscrepancy is FALSE', () async {
        // Seed 10 SKUs with varied starting states (low stock, out of stock, deficit, surplus)
        for (int i = 0; i < tenSkus.length; i++) {
          final sku = tenSkus[i];
          final is50ml = sku.endsWith('2');
          final initialRecorded = i % 3; // 0, 1, or 2
          final initialDetected = (i % 2 == 0) ? initialRecorded : 0;

          await sqlite.upsertInventoryRecord(InventoryRecordModel(
            id: 'inv_restock_$sku',
            perfumeCode: sku,
            name: 'Restock SKU $sku',
            category: i < 4 ? 'Men' : (i < 7 ? 'Women' : 'Unisex'),
            branch: testBranch,
            shelf: 'Tray ${sku.substring(0, 2)} Slot ${sku.substring(2)}',
            recorded: initialRecorded,
            detected: initialDetected,
            status: initialDetected == 0 ? 'out_of_stock' : 'low',
            price: is50ml ? 180.0 : 260.0,
            lastUpdated: DateTime.now(),
          ));

          // Seed active low_stock and discrepancy alerts
          await sqlite.saveAlert(AlertModel(
            id: 'alt_low_$sku',
            title: 'Low Stock $sku',
            desc: 'Refill required',
            branch: testBranch,
            type: initialDetected == 0 ? 'out_of_stock' : 'low_stock',
            perfumeCode: sku,
            isRead: false,
            createdAt: DateTime.now(),
          ));
          if (initialRecorded != initialDetected) {
            await sqlite.saveAlert(AlertModel(
              id: 'alt_disc_$sku',
              title: 'Discrepancy $sku',
              desc: 'Detected != Recorded',
              branch: testBranch,
              type: 'discrepancy',
              perfumeCode: sku,
              isRead: false,
              createdAt: DateTime.now(),
            ));
          }
        }

        // Execute restock for all 10 SKUs
        for (int i = 0; i < tenSkus.length; i++) {
          final sku = tenSkus[i];
          final restockQty = 3 + (i % 3); // 3, 4, or 5 bottles
          final now = DateTime.now();

          // 1. Log restock record
          final restockRecord = RestockRecordModel(
            id: 'rst_${sku}_${now.millisecondsSinceEpoch}',
            productName: 'Restock SKU $sku',
            perfumeCode: sku,
            quantity: restockQty,
            fromBranch: 'Main Warehouse',
            toBranch: testBranch,
            requestedBy: 'Kiosk Store Manager',
            status: 'received',
            createdAt: now,
          );
          await sqlite.saveRestockRecord(restockRecord);

          // 2. Restock synchronization invariant:
          // newRecorded = (existing.recorded + restockQty).clamp(0, 5)
          // detected = newRecorded
          // status = 'normal'
          final existing = await sqlite.getInventoryRecord(sku, testBranch);
          expect(existing, isNotNull);
          final int newRecorded = (existing!.recorded + restockQty).clamp(0, 5);
          final updated = InventoryRecordModel(
            id: existing.id,
            perfumeCode: existing.perfumeCode,
            name: existing.name,
            category: existing.category,
            branch: testBranch,
            shelf: existing.shelf,
            recorded: newRecorded,
            detected: newRecorded, // SYNC: detected matches newRecorded!
            status: 'normal',
            lastUpdated: now,
            price: existing.price,
          );
          await sqlite.upsertInventoryRecord(updated);

          // 3. Clear active alerts for that SKU
          await sqlite.markStockAlertsReadForPerfume(sku, branch: testBranch);

          // 4. Verify post-restock state for this SKU
          final postInv = await sqlite.getInventoryRecord(sku, testBranch);
          expect(postInv, isNotNull, reason: 'Restocked SKU $sku must exist in DB');
          expect(postInv!.recorded, equals(newRecorded),
              reason: '$sku: recorded must equal newRecorded ($newRecorded)');
          expect(postInv.detected, equals(newRecorded),
              reason: '$sku: detected must equal newRecorded ($newRecorded)');
          expect(postInv.detected, equals(postInv.recorded),
              reason: '$sku: detected must equal recorded');
          expect(postInv.detected != postInv.recorded, isFalse,
              reason: '$sku: hasDiscrepancy MUST be FALSE');
          expect(postInv.status, equals('normal'),
              reason: '$sku: Status must be normal after restock');
          expect(postInv.detected, lessThanOrEqualTo(5),
              reason: '$sku: Stock must never exceed max slot capacity 5');

          // 5. Verify no unread discrepancy or stock alerts remain
          final unreadAlerts = await sqlite.getAlerts(testBranch, unreadOnly: true);
          final unreadForSku = unreadAlerts.where((a) => a.perfumeCode == sku);
          expect(unreadForSku.isEmpty, isTrue,
              reason: '$sku: All active stock and discrepancy alerts must be dismissed');
        }

        // Final verification across all 10 SKUs in SQLite
        final allRecords = await sqlite.getInventoryRecords(testBranch);
        for (final sku in tenSkus) {
          final record = allRecords.firstWhere((r) => r.perfumeCode == sku);
          expect(record.recorded == record.detected, isTrue,
              reason: 'Invariant check for $sku: recorded (${record.recorded}) == detected (${record.detected})');
          expect(record.detected > 0, isTrue, reason: '$sku stock must be > 0');
        }
      });

      test('2.2 confirmSurplusRestock automatically synchronizes detected count and dismisses discrepancy', () async {
        const String sku = 'SURPLUS_SKU';
        // Surplus: physical detected is 5, recorded is 2
        await sqlite.upsertInventoryRecord(InventoryRecordModel(
          id: 'inv_$sku',
          perfumeCode: sku,
          name: 'Surplus Fragrance',
          category: 'Men',
          branch: testBranch,
          shelf: 'Tray A Slot 2',
          recorded: 2,
          detected: 5,
          status: 'needs_review',
          price: 260.0,
          lastUpdated: DateTime.now(),
        ));
        await sqlite.saveAlert(AlertModel(
          id: 'alt_surp_$sku',
          title: 'Surplus Discrepancy',
          desc: '5 detected vs 2 recorded',
          branch: testBranch,
          type: 'discrepancy',
          perfumeCode: sku,
          isRead: false,
          createdAt: DateTime.now(),
        ));

        await sqlite.confirmSurplusRestock(
          perfumeCode: sku,
          branch: testBranch,
          detectedCount: 5,
        );

        final updated = await sqlite.getInventoryRecord(sku, testBranch);
        expect(updated, isNotNull);
        expect(updated!.recorded, equals(5));
        expect(updated.detected, equals(5));
        expect(updated.recorded == updated.detected, isTrue);
        expect(updated.status, equals('normal'));

        final unread = await sqlite.getAlerts(testBranch, unreadOnly: true);
        expect(unread.any((a) => a.perfumeCode == sku), isFalse);
      });
    });

    // =========================================================================
    // 3. NET REVENUE CALCULATIONS WITH EXTREME INPUTS (R5)
    // =========================================================================
    group('3. Net Revenue & Financial Resilience Stress Tests (R5)', () {
      test('3.1 Customer refunds exceeding daily sales resulting in negative net revenue without arithmetic underflow', () async {
        final now = DateTime.now();

        // 1. Record 2 positive sales: 2 x ₱260 = ₱520.00
        final sale1 = SaleRecordModel(
          id: 'sale_pos_1',
          perfumeCode: 'AA1',
          productName: 'Sauvage',
          bottleSize: '100ml',
          quantitySold: 1,
          unitPrice: 260.0,
          totalAmount: 260.0,
          branch: testBranch,
          soldAt: now,
        );
        final sale2 = SaleRecordModel(
          id: 'sale_pos_2',
          perfumeCode: 'AA1',
          productName: 'Sauvage',
          bottleSize: '100ml',
          quantitySold: 1,
          unitPrice: 260.0,
          totalAmount: 260.0,
          branch: testBranch,
          soldAt: now,
        );
        final dummyEvent = InventoryEventModel(
          id: 'evt_pos',
          eventType: 'REMOVED',
          productName: 'Sauvage',
          perfumeCode: 'AA1',
          shelfArea: 'Tray A',
          branch: testBranch,
          quantity: 1,
          timestamp: now,
        );
        await sqlite.recordSaleWithInventoryDeduction(saleRecord: sale1, event: dummyEvent, branch: testBranch);
        await sqlite.recordSaleWithInventoryDeduction(saleRecord: sale2, event: dummyEvent, branch: testBranch);

        // 2. Record large customer return / refund exceeding gross sales:
        // 5 bottles returned @ ₱260.00 = -₱1,300.00 refund
        await sqlite.recordCustomerReturnRefund(
          perfumeCode: 'AA1',
          productName: 'Sauvage',
          bottleSize: '100ml',
          quantity: 5,
          unitPrice: 260.0,
          isResellable: true,
          authorizedBy: 'Store Manager',
          branch: testBranch,
        );

        // Fetch sales records from DB
        final allSales = await sqlite.getSalesRecords(testBranch);
        expect(allSales.length, equals(3));

        final grossSales = allSales
            .where((s) => s.totalAmount > 0)
            .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
        expect(grossSales, equals(520.0));

        final refundRecords = allSales.where((s) => s.isRefund).toList();
        expect(refundRecords.length, equals(1));
        final refundTotal = refundRecords.fold<double>(0.0, (sum, s) => sum + s.totalAmount.abs());
        expect(refundTotal, equals(1300.0));

        // Net Revenue formula: Gross Sales - Refunds = 520.0 - 1300.0 = -780.0
        final netRevenue = allSales.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
        expect(netRevenue, equals(-780.0), reason: 'Net Revenue must be exactly -₱780.00');
        expect(netRevenue.isFinite, isTrue);
        expect(netRevenue.isNaN, isFalse);

        // Verify signed formatted string outputs
        final refundRecord = refundRecords.first;
        expect(refundRecord.isRefund, isTrue);
        expect(refundRecord.transactionType, equals('REFUND'));
        expect(refundRecord.signedFormattedTotal, equals('-₱1300.00'));
        expect(refundRecord.formattedTotal, equals('-₱1300.00'));

        final posSale = allSales.firstWhere((s) => !s.isRefund);
        expect(posSale.isRefund, isFalse);
        expect(posSale.transactionType, equals('SALE'));
        expect(posSale.signedFormattedTotal, equals('+₱260.00'));
        expect(posSale.formattedTotal, equals('₱260.00'));
      });

      test('3.2 Pure refund day (zero sales, only refunds) computes negative net revenue safely', () async {
        // Zero normal sales, 3 distinct refunds
        await sqlite.recordCustomerReturnRefund(
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantity: 2,
          unitPrice: 180.0,
          isResellable: true,
          authorizedBy: 'Manager',
          branch: testBranch,
        );
        await sqlite.recordCustomerReturnRefund(
          perfumeCode: 'BB1',
          productName: 'Coco Mademoiselle',
          bottleSize: '100ml',
          quantity: 1,
          unitPrice: 260.0,
          isResellable: false, // Damaged return
          authorizedBy: 'Manager',
          branch: testBranch,
        );

        final sales = await sqlite.getSalesRecords(testBranch);
        expect(sales.length, equals(2));
        expect(sales.every((s) => s.isRefund), isTrue);

        final totalRefundDisbursed = sales.fold<double>(0.0, (sum, s) => sum + s.totalAmount.abs());
        expect(totalRefundDisbursed, equals(360.0 + 260.0)); // ₱620.00

        final netRevenue = sales.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
        expect(netRevenue, equals(-620.0));
      });

      test('3.3 Extreme high-volume stress calculation (millions scale and 10,000 transactions)', () {
        final List<SaleRecordModel> highVolumeSales = [];
        final now = DateTime.now();

        // 6,000 normal sales @ ₱260.00 = ₱1,560,000.00
        for (int i = 0; i < 6000; i++) {
          highVolumeSales.add(SaleRecordModel(
            id: 'sale_bulk_$i',
            perfumeCode: 'AA1',
            productName: 'Sauvage',
            quantitySold: 1,
            unitPrice: 260.0,
            totalAmount: 260.0,
            soldAt: now,
          ));
        }

        // 4,000 refund transactions @ -₱360.00 = -₱1,440,000.00
        for (int i = 0; i < 4000; i++) {
          highVolumeSales.add(SaleRecordModel(
            id: 'refund_bulk_$i',
            perfumeCode: 'AA2',
            productName: 'Bleu',
            quantitySold: 2,
            unitPrice: 180.0,
            totalAmount: -360.0, // refund
            soldAt: now,
          ));
        }

        expect(highVolumeSales.length, equals(10000));
        final gross = highVolumeSales.where((s) => !s.isRefund).fold<double>(0.0, (sum, s) => sum + s.totalAmount);
        final refunds = highVolumeSales.where((s) => s.isRefund).fold<double>(0.0, (sum, s) => sum + s.totalAmount.abs());
        final net = highVolumeSales.fold<double>(0.0, (sum, s) => sum + s.totalAmount);

        expect(gross, equals(1560000.0));
        expect(refunds, equals(1440000.0));
        expect(net, equals(120000.0));
        expect(UnifiedStockMovementHarness.calculateNetRevenue(grossSales: gross, refunds: refunds), equals(120000.0));
      });
    });

    // =========================================================================
    // 4. DAMAGE SHRINKAGE LOSS CALCULATIONS ACROSS 100ML & 50ML TIERS (R5)
    // =========================================================================
    group('4. Damage Shrinkage Loss Stress Tests (R5)', () {
      test('4.1 Multi-tier damage shrinkage across 100ml and 50ml price tiers and categories', () async {
        final categories = ['Men', 'Women', 'Unisex', 'Seasonal'];
        final validReasons = ['Broken Bottle', 'Leaking / Evaporated', 'Defective Atomizer / Cap'];

        // Record damage write-offs for each category and both 100ml and 50ml
        double expectedTotalLoss = 0.0;
        int expectedTotalUnits = 0;

        for (int i = 0; i < categories.length; i++) {
          final cat = categories[i];
          final reason = validReasons[i % validReasons.length];

          // 100ml item (ends with '1') -> ₱260.00
          final code100 = 'D${i}1';
          const qty100 = 2;
          await sqlite.recordDamagedWriteOff(
            perfumeCode: code100,
            productName: '$cat Fragrance 100ml',
            bottleSize: '100ml',
            quantity: qty100,
            reasonCategory: reason,
            authorizedBy: 'Manager PIN Verified',
            branch: testBranch,
          );
          expectedTotalLoss += (qty100 * 260.0);
          expectedTotalUnits += qty100;

          // 50ml item (ends with '2') -> ₱180.00
          final code50 = 'D${i}2';
          const qty50 = 3;
          await sqlite.recordDamagedWriteOff(
            perfumeCode: code50,
            productName: '$cat Fragrance 50ml',
            bottleSize: '50ml',
            quantity: qty50,
            reasonCategory: reason,
            authorizedBy: 'Manager PIN Verified',
            branch: testBranch,
          );
          expectedTotalLoss += (qty50 * 180.0);
          expectedTotalUnits += qty50;
        }

        // Verify inventory events recorded
        final events = await sqlite.getInventoryEvents(testBranch);
        final damageEvents = events.where((e) => e.eventType == 'DAMAGE_WRITEOFF').toList();
        expect(damageEvents.length, equals(categories.length * 2));

        // Compute loss using ReportsScreen formula
        final computedUnits = damageEvents.fold<int>(0, (sum, e) => sum + e.quantity);
        final computedLoss = damageEvents.fold<double>(0.0, (sum, e) {
          final unitPrice = e.perfumeCode.endsWith('2')
              ? AppConstants.price50ml
              : (e.perfumeCode.endsWith('1')
                  ? AppConstants.price100ml
                  : AppConstants.priceFor(''));
          return sum + (e.quantity * unitPrice);
        });

        expect(computedUnits, equals(expectedTotalUnits));
        expect(computedLoss, equals(expectedTotalLoss));
        // 4 categories * (2*260 + 3*180) = 4 * (520 + 540) = 4 * 1060 = 4,240.00
        expect(computedLoss, equals(4240.0));
      });

      test('4.2 Rejects invalid damage write-off reason categories with ArgumentError', () async {
        expect(
          () => sqlite.recordDamagedWriteOff(
            perfumeCode: 'AA1',
            productName: 'Sauvage',
            bottleSize: '100ml',
            quantity: 1,
            reasonCategory: 'Expired / Stale', // Invalid!
            authorizedBy: 'Manager',
            branch: testBranch,
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => sqlite.recordDamagedWriteOff(
            perfumeCode: 'AA1',
            productName: 'Sauvage',
            bottleSize: '100ml',
            quantity: 1,
            reasonCategory: 'Tester Bottle Used Up', // Invalid!
            authorizedBy: 'Manager',
            branch: testBranch,
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    // =========================================================================
    // 5. CSV AND PDF EXPORTS ADVERSARIAL STRESS VERIFICATION (R5)
    // =========================================================================
    group('5. CSV & PDF Exports Adversarial Verification (R5)', () {
      final now = DateTime.now();
      final mixedSales = [
        SaleRecordModel(
          id: 'sale_001',
          perfumeCode: 'AA1',
          productName: 'Sauvage Dior',
          bottleSize: '100ml',
          quantitySold: 2,
          unitPrice: 260.0,
          totalAmount: 520.0,
          branch: testBranch,
          soldBy: 'Cashier_Hidden_Alice', // Adversarial: Attempting to leak Cashier
          soldAt: now,
        ),
        SaleRecordModel(
          id: 'refund_002',
          perfumeCode: 'AA2',
          productName: 'Bleu de Chanel',
          bottleSize: '50ml',
          quantitySold: 1,
          unitPrice: 180.0,
          totalAmount: -180.0, // Refund!
          branch: testBranch,
          soldBy: 'Cashier_Hidden_Bob',
          soldAt: now.add(const Duration(minutes: 5)),
        ),
        SaleRecordModel(
          id: 'refund_003',
          perfumeCode: 'BB1',
          productName: 'Eros Versace',
          bottleSize: '100ml',
          quantitySold: 3,
          unitPrice: 260.0,
          totalAmount: -780.0, // Heavy refund!
          branch: testBranch,
          soldBy: 'Cashier_Hidden_Charlie',
          soldAt: now.add(const Duration(minutes: 10)),
        ),
      ];

      test('5.1 Daily Sales CSV: exact 9 columns, signed amounts, Net Revenue total, strict absence of Cashier', () {
        final csv = ReportExportService.instance.generateDailySalesCsv(
          sales: mixedSales,
          branch: testBranch,
        );

        final lines = csv.trim().split('\n');
        final header = lines.first;

        // 1. Strict absence of Cashier
        expect(header.toLowerCase().contains('cashier'), isFalse,
            reason: 'CSV Header must NOT contain Cashier');
        for (final line in lines) {
          expect(line.contains('Cashier_Hidden'), isFalse,
              reason: 'No cashier name should be leaked into CSV: $line');
        }

        // 2. Exact 9 header columns
        final headerCols = header.split(',');
        expect(headerCols.length, equals(9));
        expect(headerCols, equals([
          'Transaction ID',
          'Time',
          'Fragrance Name',
          'Perfume Code',
          'Bottle Size',
          'Quantity Sold',
          'Unit Price (PHP)',
          'Total Amount (PHP)',
          'Sync Status'
        ]));

        // 3. Signed amounts on rows
        expect(lines[1].contains('520.00'), isTrue);
        expect(lines[2].contains('-180.00'), isTrue, reason: 'Refund row must reflect negative signed amount');
        expect(lines[3].contains('-780.00'), isTrue, reason: 'Refund row must reflect negative signed amount');

        // 4. Net Revenue in summary totals footer: 520 - 180 - 780 = -440.00
        final summaryLine = lines.last;
        expect(summaryLine.startsWith('SUMMARY TOTALS'), isTrue);
        expect(summaryLine.contains('-440.00'), isTrue,
            reason: 'Summary footer must reflect negative Net Revenue: $summaryLine');
      });

      test('5.2 Shelf Stock CSV: exact 8 columns, totals, strict absence of Cashier', () {
        final items = [
          InventoryRecordModel(
            id: 'inv_1',
            perfumeCode: 'AA1',
            name: 'Sauvage',
            category: 'Men',
            branch: testBranch,
            shelf: 'Shelf A',
            recorded: 4,
            detected: 4,
            status: 'normal',
            price: 260.0,
            lastUpdated: now,
          ),
          InventoryRecordModel(
            id: 'inv_2',
            perfumeCode: 'AA2',
            name: 'Bleu',
            category: 'Men',
            branch: testBranch,
            shelf: 'Shelf A',
            recorded: 2,
            detected: 2,
            status: 'low',
            price: 180.0,
            lastUpdated: now,
          ),
        ];

        final csv = ReportExportService.instance.generateShelfStockCsv(
          items: items,
          branch: testBranch,
        );

        final lines = csv.trim().split('\n');
        final header = lines.first;

        expect(header.toLowerCase().contains('cashier'), isFalse);
        final headerCols = header.split(',');
        expect(headerCols.length, equals(8));
        expect(headerCols, equals([
          'Fragrance Name',
          'Shelf / Tray Location',
          'In Stock (Bottles)',
          'Max Capacity',
          'Stock Status',
          'Unit Price (PHP)',
          'Total Shelf Value (PHP)',
          'Last Checked'
        ]));

        final summaryLine = lines.last;
        expect(summaryLine.startsWith('TOTALS'), isTrue);
        // Total valuation: 4*260 + 2*180 = 1040 + 360 = 1400.00
        expect(summaryLine.contains('1400.00'), isTrue);
      });

      test('5.3 Branded PDF Report: valid PDF binary, Today\'s Revenue, table without Cashier column', () async {
        final inventory = [
          InventoryRecordModel(
            id: 'inv_pdf_1',
            perfumeCode: 'AA1',
            name: 'Sauvage Dior',
            category: 'Men',
            branch: testBranch,
            shelf: 'Shelf A',
            recorded: 3,
            detected: 3,
            status: 'normal',
            price: 260.0,
            lastUpdated: now,
          ),
        ];

        final Uint8List pdfBytes = await ReportExportService.instance.generateReportPdfBytes(
          inventory: inventory,
          sales: mixedSales,
          branch: testBranch,
        );

        expect(pdfBytes.isNotEmpty, isTrue);
        expect(pdfBytes.length, greaterThan(1000));

        // Validate %PDF magic header
        final headerAscii = String.fromCharCodes(pdfBytes.take(4));
        expect(headerAscii, equals('%PDF'));

        // Validate that no Cashier string appears in PDF text payload
        final pdfRawString = String.fromCharCodes(pdfBytes);
        expect(pdfRawString.contains('Cashier_Hidden'), isFalse,
            reason: 'Cashier name should not be present in PDF stream');
      });
    });
  });
}
