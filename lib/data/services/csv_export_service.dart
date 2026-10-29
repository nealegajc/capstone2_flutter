import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../models/inventory_record_model.dart';
import '../models/inventory_event_model.dart';
import '../models/sale_record_model.dart';
import '../models/sync_queue_model.dart';
import '../models/system_log_model.dart';

class CsvExportService {
  static final CsvExportService instance = CsvExportService._();
  CsvExportService._();

  String _escapeCsv(dynamic value) {
    if (value == null) return '""';
    final str = value.toString();
    if (str.contains(',') ||
        str.contains('"') ||
        str.contains('\n') ||
        str.contains('\r')) {
      return '"${str.replaceAll('"', '""')}"';
    }
    return '"$str"';
  }

  Future<File> _writeCsvFile(String prefix, String content) async {
    Directory? exportDir;
    try {
      // Check for ~/Downloads directory on Linux
      final home = Platform.environment['HOME'];
      if (home != null) {
        final downloads = Directory(p.join(home, 'Downloads'));
        if (downloads.existsSync()) {
          exportDir = Directory(p.join(downloads.path, 'OttoScents_Reports'));
        }
      }
    } catch (_) {}

    if (exportDir == null) {
      final appDir = await getApplicationDocumentsDirectory();
      exportDir = Directory(p.join(appDir.path, 'reports'));
    }

    if (!exportDir.existsSync()) {
      exportDir.createSync(recursive: true);
    }

    final timestampStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File(p.join(exportDir.path, '${prefix}_$timestampStr.csv'));
    await file.writeAsString(content);
    return file;
  }

  /// Exports current inventory detection and recorded stock summary
  Future<File> exportInventorySummaryCsv(
    List<InventoryRecordModel> items, {
    String branch = 'San Pablo',
  }) async {
    final buffer = StringBuffer();
    // CSV Header
    buffer.writeln(
      'Perfume Code,Fragrance Name,Category,Branch,Shelf Location,Recorded Units,Detected Units,Stock Status,Unit Price (PHP),Estimated Value (PHP),Last Updated',
    );

    for (final item in items) {
      final value = item.price * item.detected;
      final row = [
        item.perfumeCode,
        item.name,
        item.category,
        item.branch,
        item.shelf,
        item.recorded,
        item.detected,
        item.status.toUpperCase(),
        item.price.toStringAsFixed(2),
        value.toStringAsFixed(2),
        DateFormat('yyyy-MM-dd HH:mm:ss').format(item.lastUpdated),
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return await _writeCsvFile(
      'OttoScents_Inventory_Summary_${branch.replaceAll(' ', '_')}',
      buffer.toString(),
    );
  }

  /// Exports stock movement audit events (Restocked, Removed, Sold)
  Future<File> exportStockMovementCsv(
    List<InventoryEventModel> events, {
    String branch = 'San Pablo',
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(
      'Event ID,Timestamp,Event Type,Fragrance Name,Perfume Code,Shelf Area,Branch,Quantity,Sync Status',
    );

    for (final e in events) {
      final row = [
        e.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(e.timestamp),
        e.eventType,
        e.productName,
        e.perfumeCode,
        e.shelfArea,
        e.branch,
        e.quantity,
        e.syncStatus,
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return await _writeCsvFile(
      'OttoScents_Movement_Audit_${branch.replaceAll(' ', '_')}',
      buffer.toString(),
    );
  }

  /// Exports retail fragrance sales transactions and revenue audit
  Future<File> exportSalesRecordsCsv(
    List<SaleRecordModel> sales, {
    String? branch,
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(
      'Transaction ID,Date & Time,Perfume Code,Fragrance Name,Bottle Size,Quantity Sold,Unit Price (PHP),Total Revenue (PHP),Branch,Sold By,Sync Status',
    );

    double totalRevenue = 0.0;
    int totalUnits = 0;

    for (final s in sales) {
      totalRevenue += s.totalAmount;
      totalUnits += s.quantitySold;
      final row = [
        s.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(s.soldAt),
        s.perfumeCode,
        s.productName,
        s.bottleSize,
        s.quantitySold,
        s.unitPrice.toStringAsFixed(2),
        s.totalAmount.toStringAsFixed(2),
        s.branch,
        s.soldBy,
        s.syncStatus,
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    // Summary row
    buffer.writeln();
    buffer.writeln(
      'SUMMARY TOTALS,,,,,$totalUnits,,${totalRevenue.toStringAsFixed(2)},,,',
    );

    final branchName = branch ?? 'All_Branches';
    return await _writeCsvFile(
      'OttoScents_Sales_Report_${branchName.replaceAll(' ', '_')}',
      buffer.toString(),
    );
  }

  /// Exports offline SQLite sync queue audit
  Future<File> exportSyncAuditCsv(
    List<SyncQueueModel> queue, {
    String branch = 'San Pablo',
  }) async {
    final buffer = StringBuffer();
    buffer.writeln(
      'Queue ID,Pending Event ID,Target Collection,Operation,Retry Count,Status,Branch,Last Attempt',
    );

    for (final q in queue) {
      final row = [
        q.id,
        q.pendingEventId,
        q.targetCollection,
        q.operation,
        q.retryCount,
        q.status,
        q.branch,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(q.lastAttempt),
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return await _writeCsvFile(
      'OttoScents_Sync_Audit_${branch.replaceAll(' ', '_')}',
      buffer.toString(),
    );
  }

  /// Exports system activity audit logs to CSV
  Future<File> exportSystemLogsCsv(
    List<SystemLogModel> logs, {
    String branch = 'San Pablo',
  }) async {
    final buffer = StringBuffer();
    buffer.writeln('Log ID,Timestamp,Type,User,Branch,Description');

    for (final l in logs) {
      final row = [
        l.id,
        DateFormat('yyyy-MM-dd HH:mm:ss').format(l.timestamp),
        l.type,
        l.user,
        l.branch,
        l.description,
      ];
      buffer.writeln(row.map(_escapeCsv).join(','));
    }

    return await _writeCsvFile(
      'OttoScents_Activity_Logs_${branch.replaceAll(' ', '_')}',
      buffer.toString(),
    );
  }
}
