import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:smart_shelf_linux/data/models/inventory_event_model.dart';
import 'package:smart_shelf_linux/data/models/inventory_record_model.dart';
import 'package:smart_shelf_linux/data/models/sale_record_model.dart';
import 'e2e_test_harness.dart';

/// Comprehensive Test Harness for Otto Scents Unified Stock Movement,
/// Visual Shelf Counting, Discrepancy Resolution, PIN Authorization,
/// and Financial Reports/Exports (R1 - R5).
class UnifiedStockMovementHarness {
  // ===========================================================================
  // 1. FINANCIAL & RETAIL ACCOUNTING HARNESS (F12, F13, F14)
  // ===========================================================================

  /// Authoritative unit prices by bottle size:
  /// - 100ML (ends with '1'): ₱260.00
  /// - 50ML  (ends with '2'): ₱180.00
  static double getUnitPrice(String perfumeCode) {
    final code = perfumeCode.trim().toUpperCase();
    if (code.endsWith('2')) return 180.0;
    if (code.endsWith('1')) return 260.0;
    return 260.0;
  }

  /// Calculates Gross Sales Revenue from sale records.
  static double calculateGrossRevenue(List<SaleRecordModel> sales) {
    return sales.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
  }

  /// Calculates Total Customer Refunds disbursed.
  static double calculateTotalRefunds(List<Map<String, dynamic>> refunds) {
    return refunds.fold<double>(
      0.0,
      (sum, r) => sum + (r['totalRefund'] as num).toDouble(),
    );
  }

  /// Authoritative Net Revenue calculation: Gross Sales - Customer Refunds.
  static double calculateNetRevenue({
    required double grossSales,
    required double refunds,
  }) {
    return grossSales - refunds;
  }

  /// Calculates Damage & Shrinkage Loss from DAMAGE_WRITEOFF events.
  static double calculateDamageLoss(List<InventoryEventModel> events) {
    return events
        .where((e) => e.eventType == 'DAMAGE_WRITEOFF')
        .fold<double>(0.0, (sum, e) {
          final price = getUnitPrice(e.perfumeCode);
          return sum + (e.quantity * price);
        });
  }

  /// Calculates total physical units sold today.
  static int calculateUnitsSold(List<SaleRecordModel> sales) {
    return sales.fold<int>(0, (sum, s) => sum + s.quantitySold);
  }

  /// Calculates total physical units received/restocked today.
  static int calculateUnitsRestocked(List<InventoryEventModel> events) {
    return events
        .where((e) => e.eventType == 'RESTOCKED')
        .fold<int>(0, (sum, e) => sum + e.quantity);
  }

  /// Formats signed monetary amounts with retail conventions:
  /// - SALE: `+₱X.XX`
  /// - REFUND: `-₱X.XX`
  /// - DAMAGE_WRITEOFF: `-₱X.XX`
  static String formatSignedAmount(double amount, {required String transactionType}) {
    final absVal = amount.abs().toStringAsFixed(2);
    switch (transactionType.toUpperCase()) {
      case 'SALE':
        return '+₱$absVal';
      case 'REFUND':
      case 'CUSTOMER_RETURN':
        return '-₱$absVal';
      case 'DAMAGE_WRITEOFF':
      case 'SHRINKAGE':
        return '-₱$absVal';
      default:
        return '₱$absVal';
    }
  }

  /// Returns retail accent color for feed badges and amounts:
  /// - Green for Sales
  /// - Amber/Gold for Refunds
  /// - Red for Damage Write-Offs
  static Color getTransactionAccentColor(String transactionType) {
    switch (transactionType.toUpperCase()) {
      case 'SALE':
        return const Color(0xFF22C55E); // Green
      case 'REFUND':
      case 'CUSTOMER_RETURN':
        return const Color(0xFFD97706); // Amber / Gold
      case 'DAMAGE_WRITEOFF':
        return const Color(0xFFEF4444); // Red
      default:
        return const Color(0xFF94A3B8); // Muted
    }
  }

  // ===========================================================================
  // 2. DISCREPANCY DEFICIT & RESTOCK INVARIANT LOGIC (F1, F2)
  // ===========================================================================

  /// Executes sale deduction against SQLite ledger.
  /// INVARIANT (F1): When isDeficitResolution == true (detected < recorded),
  /// recorded is decremented to match detected, while detected remains unchanged.
  static Future<Map<String, int>> executeSaleDeduction({
    required Database db,
    required String branch,
    required String perfumeCode,
    required int quantitySold,
    required double unitPrice,
    required String productName,
    required String bottleSize,
    required bool isDeficitResolution,
    String soldBy = 'staff',
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    int finalRecorded = 0;
    int finalDetected = 0;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      int currentRecorded = 5;
      int currentDetected = 5;
      String shelf = 'Area A';

      if (rows.isNotEmpty) {
        currentRecorded = (rows.first['recorded'] as num).toInt();
        currentDetected = (rows.first['detected'] as num).toInt();
        shelf = rows.first['shelf'] as String? ?? 'Area A';
      }

      if (isDeficitResolution) {
        // Zero double-deduction: Only deduct recorded to align with reality!
        finalRecorded = (currentRecorded - quantitySold).clamp(0, 5);
        finalDetected = currentDetected; // UNCHANGED
      } else {
        // Regular sale: both recorded and detected are decremented
        finalRecorded = (currentRecorded - quantitySold).clamp(0, 5);
        finalDetected = (currentDetected - quantitySold).clamp(0, 5);
      }

      final status = finalDetected == 0
          ? 'out_of_stock'
          : (finalDetected <= 2 ? 'low' : 'normal');

      // Update inventory record
      await txn.update(
        'inventory_records',
        {
          'recorded': finalRecorded,
          'detected': finalDetected,
          'status': status,
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      // Insert sale record
      final saleId = 'sale_${now.millisecondsSinceEpoch}_$perfumeCode';
      await txn.insert('sales_records', {
        'id': saleId,
        'perfumeCode': perfumeCode,
        'productName': productName,
        'bottleSize': bottleSize,
        'quantitySold': quantitySold,
        'unitPrice': unitPrice,
        'totalAmount': unitPrice * quantitySold,
        'branch': branch,
        'soldBy': soldBy,
        'soldAt': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      // Insert inventory event
      await txn.insert('inventory_events', {
        'id': 'evt_$saleId',
        'eventType': 'REMOVED',
        'productName': productName,
        'perfumeCode': perfumeCode,
        'shelfArea': shelf,
        'branch': branch,
        'quantity': quantitySold,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      // If discrepancy resolved (recorded == detected), clear discrepancy alert
      if (finalRecorded == finalDetected) {
        await txn.delete(
          'alerts',
          where: 'perfumeCode = ? AND branch = ? AND type = ?',
          whereArgs: [perfumeCode, branch, 'discrepancy'],
        );
      }
    });

    return {'recorded': finalRecorded, 'detected': finalDetected};
  }

  /// Executes restock synchronization against SQLite ledger.
  /// INVARIANT (F2): When adding received bottles to shelf, both recorded and
  /// detected increase simultaneously (detected = newRecorded), preventing false alerts.
  static Future<Map<String, int>> executeRestockSync({
    required Database db,
    required String branch,
    required String perfumeCode,
    required int quantityAdded,
    String? productName,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    int finalRecorded = 0;
    int finalDetected = 0;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      int currentRecorded = 0;
      String shelf = 'Area A';
      String name = productName ?? 'Fragrance $perfumeCode';

      if (rows.isNotEmpty) {
        currentRecorded = (rows.first['recorded'] as num).toInt();
        shelf = rows.first['shelf'] as String? ?? 'Area A';
        name = rows.first['name'] as String? ?? name;
      }

      finalRecorded = (currentRecorded + quantityAdded).clamp(0, 5);
      finalDetected = finalRecorded; // Synchronized!

      await txn.update(
        'inventory_records',
        {
          'recorded': finalRecorded,
          'detected': finalDetected,
          'status': 'normal',
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      // Insert restock event
      final evtId = 'evt_restock_${now.millisecondsSinceEpoch}_$perfumeCode';
      await txn.insert('inventory_events', {
        'id': evtId,
        'eventType': 'RESTOCKED',
        'productName': name,
        'perfumeCode': perfumeCode,
        'shelfArea': shelf,
        'branch': branch,
        'quantity': quantityAdded,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      // Clear discrepancy and low/out-of-stock alerts for this SKU
      await txn.delete(
        'alerts',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );
    });

    return {'recorded': finalRecorded, 'detected': finalDetected};
  }

  // ===========================================================================
  // 3. CUSTOMER RETURN & REFUND LOGIC (F3)
  // ===========================================================================

  /// Processes Customer Return & Refund with condition distinction:
  /// - 'Resellable': Returns bottle to shelf (+1 recorded, +1 detected, max 5, RETURN_RESTOCKED)
  /// - 'Damaged': Does NOT restock shelf; logs refund and write-off
  static Future<Map<String, dynamic>> executeCustomerReturn({
    required Database db,
    required String branch,
    required String perfumeCode,
    required String productName,
    required String bottleSize,
    required int quantity,
    required double unitPrice,
    required bool isResellable,
    required String authorizedBy,
    DateTime? timestamp,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('Return quantity must be greater than zero');
    }

    final now = timestamp ?? DateTime.now();
    int finalRecorded = 0;
    int finalDetected = 0;
    final totalRefund = unitPrice * quantity;
    final refundId = 'ref_${now.millisecondsSinceEpoch}_$perfumeCode';

    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      int currentRecorded = 0;
      int currentDetected = 0;
      String shelf = 'Area A';

      if (rows.isNotEmpty) {
        currentRecorded = (rows.first['recorded'] as num).toInt();
        currentDetected = (rows.first['detected'] as num).toInt();
        shelf = rows.first['shelf'] as String? ?? 'Area A';
      }

      if (isResellable) {
        // Place back onto physical shelf
        finalRecorded = min(5, currentRecorded + quantity);
        finalDetected = min(5, currentDetected + quantity);
      } else {
        // Defective/damaged return: shelf stock does not increase
        finalRecorded = currentRecorded;
        finalDetected = currentDetected;
      }

      final status = finalDetected == 0
          ? 'out_of_stock'
          : (finalDetected <= 2 ? 'low' : 'normal');

      await txn.update(
        'inventory_records',
        {
          'recorded': finalRecorded,
          'detected': finalDetected,
          'status': status,
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      // Log event
      final eventType = isResellable ? 'RETURN_RESTOCKED' : 'DAMAGE_WRITEOFF';
      await txn.insert('inventory_events', {
        'id': 'evt_$refundId',
        'eventType': eventType,
        'productName': productName,
        'perfumeCode': perfumeCode,
        'shelfArea': shelf,
        'branch': branch,
        'quantity': quantity,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      // Ensure refund table or system_logs entry
      await txn.insert('system_logs', {
        'id': refundId,
        'type': 'CUSTOMER_REFUND',
        'description': jsonEncode({
          'refundId': refundId,
          'perfumeCode': perfumeCode,
          'productName': productName,
          'bottleSize': bottleSize,
          'quantity': quantity,
          'unitPrice': unitPrice,
          'totalRefund': totalRefund,
          'condition': isResellable ? 'resellable' : 'damaged',
          'authorizedBy': authorizedBy,
        }),
        'user': authorizedBy,
        'branch': branch,
        'timestamp': now.millisecondsSinceEpoch,
      });
    });

    return {
      'refundId': refundId,
      'totalRefund': totalRefund,
      'isResellable': isResellable,
      'recorded': finalRecorded,
      'detected': finalDetected,
    };
  }

  // ===========================================================================
  // 4. DAMAGED PERFUME WRITE-OFF LOGIC (F4)
  // ===========================================================================

  /// Permitted damage write-off categories (excluding expired/tester).
  static const List<String> allowedDamageCategories = [
    'Broken Bottle',
    'Leaking / Evaporated',
    'Defective Atomizer / Cap',
  ];

  static bool isValidDamageCategory(String reason) {
    return allowedDamageCategories.contains(reason.trim());
  }

  /// Processes Damaged Fragrance Write-Off with category reason validation.
  static Future<Map<String, dynamic>> executeDamagedWriteOff({
    required Database db,
    required String branch,
    required String perfumeCode,
    required String productName,
    required String bottleSize,
    required int quantity,
    required String reasonCategory,
    required String authorizedBy,
    bool isDeficitResolution = false,
    DateTime? timestamp,
  }) async {
    if (!isValidDamageCategory(reasonCategory)) {
      throw ArgumentError(
        'Invalid damage category: $reasonCategory. Permitted: $allowedDamageCategories',
      );
    }
    if (quantity <= 0) {
      throw ArgumentError('Write-off quantity must be greater than zero');
    }

    final now = timestamp ?? DateTime.now();
    int finalRecorded = 0;
    int finalDetected = 0;
    final writeOffId = 'dmg_${now.millisecondsSinceEpoch}_$perfumeCode';
    final unitPrice = getUnitPrice(perfumeCode);
    final financialLoss = unitPrice * quantity;

    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      int currentRecorded = 0;
      int currentDetected = 0;
      String shelf = 'Area A';

      if (rows.isNotEmpty) {
        currentRecorded = (rows.first['recorded'] as num).toInt();
        currentDetected = (rows.first['detected'] as num).toInt();
        shelf = rows.first['shelf'] as String? ?? 'Area A';
      }

      finalRecorded = (currentRecorded - quantity).clamp(0, 5);
      if (isDeficitResolution) {
        // Physical bottle was already broken/removed from shelf
        finalDetected = currentDetected;
      } else {
        finalDetected = (currentDetected - quantity).clamp(0, 5);
      }

      final status = finalDetected == 0
          ? 'out_of_stock'
          : (finalDetected <= 2 ? 'low' : 'normal');

      await txn.update(
        'inventory_records',
        {
          'recorded': finalRecorded,
          'detected': finalDetected,
          'status': status,
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      // Log damage event with reason
      await txn.insert('inventory_events', {
        'id': 'evt_$writeOffId',
        'eventType': 'DAMAGE_WRITEOFF',
        'productName': '$productName ($reasonCategory)',
        'perfumeCode': perfumeCode,
        'shelfArea': shelf,
        'branch': branch,
        'quantity': quantity,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      if (isDeficitResolution && finalRecorded == finalDetected) {
        await txn.delete(
          'alerts',
          where: 'perfumeCode = ? AND branch = ? AND type = ?',
          whereArgs: [perfumeCode, branch, 'discrepancy'],
        );
      }
    });

    return {
      'writeOffId': writeOffId,
      'recorded': finalRecorded,
      'detected': finalDetected,
      'financialLoss': financialLoss,
      'reason': reasonCategory,
    };
  }

  // ===========================================================================
  // 5. VISUAL SHELF COUNTING & CAMERA PEEK (F5, F8, F9, F10)
  // ===========================================================================

  /// Represents the 5 bottle cap visual slots on physical tray.
  static List<bool> getCapSlotFillStatus(int count) {
    final clamped = count.clamp(0, 5);
    return List<bool>.generate(5, (idx) => idx < clamped);
  }

  /// Stepper helpers
  static int stepIncrement(int current) => (current + 1).clamp(0, 5);
  static int stepDecrement(int current) => (current - 1).clamp(0, 5);
  static int setPreset(int preset) => preset.clamp(0, 5);

  /// Resolves camera mapping for tray code (e.g. 'AA', 'CA').
  static ({int cameraId, String deviceNode}) getCameraForTray(String trayCode) {
    final camId = ShelfArchitectureHarness.getCameraIdForTray(trayCode);
    final device = ShelfArchitectureHarness.getCameraDevice(camId);
    return (cameraId: camId, deviceNode: device);
  }

  /// Commits manual/visual audit count to SQLite ledger.
  /// INVARIANT: Sets both detected and recorded to count, realigns status,
  /// clears discrepancy alerts, and logs AUDIT_VISUAL_COUNT.
  static Future<Map<String, int>> executeVisualCountCommit({
    required Database db,
    required String branch,
    required String perfumeCode,
    required int countedBottles,
    required String auditor,
    DateTime? timestamp,
  }) async {
    final now = timestamp ?? DateTime.now();
    final count = countedBottles.clamp(0, 5);

    await db.transaction((txn) async {
      final rows = await txn.query(
        'inventory_records',
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      String shelf = 'Area A';
      String name = 'Fragrance $perfumeCode';
      if (rows.isNotEmpty) {
        shelf = rows.first['shelf'] as String? ?? 'Area A';
        name = rows.first['name'] as String? ?? name;
      }

      final status = count == 0 ? 'out_of_stock' : (count <= 2 ? 'low' : 'normal');

      await txn.update(
        'inventory_records',
        {
          'recorded': count,
          'detected': count,
          'status': status,
          'lastUpdated': now.millisecondsSinceEpoch,
        },
        where: 'perfumeCode = ? AND branch = ?',
        whereArgs: [perfumeCode, branch],
      );

      // Insert visual count audit event
      final auditId = 'audit_${now.millisecondsSinceEpoch}_$perfumeCode';
      await txn.insert('inventory_events', {
        'id': 'evt_$auditId',
        'eventType': 'AUDIT_VISUAL_COUNT',
        'productName': name,
        'perfumeCode': perfumeCode,
        'shelfArea': shelf,
        'branch': branch,
        'quantity': count,
        'timestamp': now.millisecondsSinceEpoch,
        'syncStatus': 'synced',
      });

      // Clear any discrepancy alert
      await txn.delete(
        'alerts',
        where: 'perfumeCode = ? AND branch = ? AND type = ?',
        whereArgs: [perfumeCode, branch, 'discrepancy'],
      );
    });

    return {'recorded': count, 'detected': count};
  }

  // ===========================================================================
  // 6. MANAGER PIN SECURITY & AUTHORIZATION GUARD (F6, F7)
  // ===========================================================================

  /// Stock movement action types
  static const String actionSale = 'sale';
  static const String actionRestock = 'restock';
  static const String actionCustomerReturn = 'customerReturn';
  static const String actionDamagedWriteOff = 'damagedWriteOff';
  static const String actionVisualCount = 'visualCount';

  /// INVARIANT (F7): Refund and Damaged Write-Off ALWAYS require Manager PIN.
  /// Normal Sales, Restocks, and Visual Counts do NOT require PIN if session is unlocked.
  static bool requiresManagerPin({
    required String actionType,
    required bool isSessionUnlocked,
  }) {
    if (actionType == actionCustomerReturn || actionType == actionDamagedWriteOff) {
      return true; // High-impact financial/inventory action
    }
    // Normal operational workflows
    return !isSessionUnlocked;
  }

  // ===========================================================================
  // 7. EXPORT FORMATTING & REPORT GENERATION (F14)
  // ===========================================================================

  /// Generates enhanced daily sales and stock movement CSV including
  /// transaction type, signed amounts, and Net Revenue summary totals.
  static String generateEnhancedDailyCsv({
    required List<SaleRecordModel> sales,
    required List<Map<String, dynamic>> refunds,
    required List<InventoryEventModel> writeOffs,
    required String branch,
  }) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Transaction ID,Time,Type,Fragrance Name,Perfume Code,Bottle Size,Qty,Unit Price (PHP),Total Amount (PHP),Sync Status',
    );

    double grossSales = 0.0;
    int soldUnits = 0;
    for (final s in sales) {
      grossSales += s.totalAmount;
      soldUnits += s.quantitySold;
      final row = [
        s.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(s.soldAt),
        'SALE',
        '"${s.productName.replaceAll('"', '""')}"',
        s.perfumeCode,
        s.bottleSize,
        s.quantitySold,
        s.unitPrice.toStringAsFixed(2),
        '+${s.totalAmount.toStringAsFixed(2)}',
        s.syncStatus,
      ];
      buffer.writeln(row.join(','));
    }

    double totalRefunds = 0.0;
    int refundUnits = 0;
    for (final r in refunds) {
      final refundAmt = (r['totalRefund'] as num).toDouble();
      totalRefunds += refundAmt;
      final qty = (r['quantity'] as num).toInt();
      refundUnits += qty;
      final row = [
        r['refundId'] ?? 'REF_00',
        DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()),
        'REFUND',
        '"${r['productName'] ?? ''}"',
        r['perfumeCode'] ?? '',
        r['bottleSize'] ?? '100ml',
        qty,
        ((r['unitPrice'] as num?)?.toDouble() ?? 260.0).toStringAsFixed(2),
        '-${refundAmt.toStringAsFixed(2)}',
        'synced',
      ];
      buffer.writeln(row.join(','));
    }

    double totalDamageLoss = 0.0;
    int damageUnits = 0;
    for (final w in writeOffs.where((e) => e.eventType == 'DAMAGE_WRITEOFF')) {
      final price = getUnitPrice(w.perfumeCode);
      final loss = price * w.quantity;
      totalDamageLoss += loss;
      damageUnits += w.quantity;
      final row = [
        w.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(w.timestamp),
        'DAMAGE_WRITEOFF',
        '"${w.productName.replaceAll('"', '""')}"',
        w.perfumeCode,
        w.perfumeCode.endsWith('2') ? '50ml' : '100ml',
        w.quantity,
        price.toStringAsFixed(2),
        '-${loss.toStringAsFixed(2)}',
        w.syncStatus,
      ];
      buffer.writeln(row.join(','));
    }

    final netRevenue = calculateNetRevenue(
      grossSales: grossSales,
      refunds: totalRefunds,
    );

    buffer.writeln();
    buffer.writeln(
      'SUMMARY TOTALS,,,,,$soldUnits Sold / $refundUnits Returned / $damageUnits Written Off,,Gross: ₱${grossSales.toStringAsFixed(2)} | Refunds: -₱${totalRefunds.toStringAsFixed(2)} | Net Revenue: ₱${netRevenue.toStringAsFixed(2)} | Damage Loss: -₱${totalDamageLoss.toStringAsFixed(2)},',
    );
    return buffer.toString();
  }

  /// Generates PDF report bytes with branded KPI cards including Net Revenue.
  static Future<Uint8List> generateEnhancedReportPdf({
    required List<SaleRecordModel> sales,
    required double refunds,
    required double damageLoss,
    required List<InventoryRecordModel> inventory,
    required String branch,
  }) async {
    final pdf = pw.Document();
    final gross = calculateGrossRevenue(sales);
    final net = calculateNetRevenue(grossSales: gross, refunds: refunds);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('OTTO SCENTS - FINANCIAL & STOCK REPORT',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Text('Branch: $branch | Date: ${DateTime.now().toIso8601String().substring(0, 10)}'),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('Gross Sales: PHP ${gross.toStringAsFixed(2)}'),
                  pw.Text('Refunds: -PHP ${refunds.toStringAsFixed(2)}'),
                  pw.Text('Net Revenue: PHP ${net.toStringAsFixed(2)}',
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('Damage Loss: -PHP ${damageLoss.toStringAsFixed(2)}'),
                ],
              ),
              pw.SizedBox(height: 15),
              pw.Text('Active Inventory Slots: ${inventory.length}'),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }
}
