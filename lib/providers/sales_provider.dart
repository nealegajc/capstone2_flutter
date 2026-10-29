import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../data/models/sale_record_model.dart';
import 'kiosk_providers.dart';

class TopSellerEntry {
  final String perfumeCode;
  final String productName;
  final String bottleSize;
  final int unitsSold;
  final double totalRevenue;

  const TopSellerEntry({
    required this.perfumeCode,
    required this.productName,
    required this.bottleSize,
    required this.unitsSold,
    required this.totalRevenue,
  });
}

class DailySalesEntry {
  final String dayLabel; // e.g. "Mon", "Tue"
  final String dateString; // e.g. "2026-09-02"
  final double revenue;
  final int units;

  const DailySalesEntry({
    required this.dayLabel,
    required this.dateString,
    required this.revenue,
    required this.units,
  });
}

class SalesAnalytics {
  final double totalRevenue;
  final int totalUnitsSold;
  final double revenue100ml;
  final double revenue50ml;
  final int units100ml;
  final int units50ml;
  final List<DailySalesEntry> last7DaysSales;
  final List<TopSellerEntry> topSellers;
  final List<SaleRecordModel> recentSales;

  const SalesAnalytics({
    required this.totalRevenue,
    required this.totalUnitsSold,
    required this.revenue100ml,
    required this.revenue50ml,
    required this.units100ml,
    required this.units50ml,
    required this.last7DaysSales,
    required this.topSellers,
    required this.recentSales,
  });

  factory SalesAnalytics.fromSales(List<SaleRecordModel> sales) {
    double totalRev = 0.0;
    int totalUnits = 0;
    double rev100 = 0.0;
    double rev50 = 0.0;
    int u100 = 0;
    int u50 = 0;

    final Map<String, _ProductAggregate> productMap = {};

    // Grouping for last 7 days
    final now = DateTime.now();
    final Map<String, _DayAggregate> dayMap = {};
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(d);
      final label = DateFormat('E').format(d);
      dayMap[dateKey] = _DayAggregate(
        label: label,
        dateString: dateKey,
        revenue: 0,
        units: 0,
      );
    }

    for (final s in sales) {
      totalRev += s.totalAmount;
      totalUnits += s.quantitySold;

      final is100 = s.bottleSize.toLowerCase().contains('100');
      if (is100) {
        rev100 += s.totalAmount;
        u100 += s.quantitySold;
      } else {
        rev50 += s.totalAmount;
        u50 += s.quantitySold;
      }

      // Aggregate by product
      final key = '${s.perfumeCode}_${s.bottleSize}';
      if (!productMap.containsKey(key)) {
        productMap[key] = _ProductAggregate(
          perfumeCode: s.perfumeCode,
          productName: s.productName,
          bottleSize: s.bottleSize,
        );
      }
      productMap[key]!.units += s.quantitySold;
      productMap[key]!.revenue += s.totalAmount;

      // Aggregate by day (if within last 7 days)
      final dateKey = DateFormat('yyyy-MM-dd').format(s.soldAt);
      if (dayMap.containsKey(dateKey)) {
        dayMap[dateKey]!.revenue += s.totalAmount;
        dayMap[dateKey]!.units += s.quantitySold;
      }
    }

    final topSellersList = productMap.values.map((p) {
      return TopSellerEntry(
        perfumeCode: p.perfumeCode,
        productName: p.productName,
        bottleSize: p.bottleSize,
        unitsSold: p.units,
        totalRevenue: p.revenue,
      );
    }).toList()..sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final dailyList = dayMap.values.map((d) {
      return DailySalesEntry(
        dayLabel: d.label,
        dateString: d.dateString,
        revenue: d.revenue,
        units: d.units,
      );
    }).toList();

    return SalesAnalytics(
      totalRevenue: totalRev,
      totalUnitsSold: totalUnits,
      revenue100ml: rev100,
      revenue50ml: rev50,
      units100ml: u100,
      units50ml: u50,
      last7DaysSales: dailyList,
      topSellers: topSellersList.take(5).toList(),
      recentSales: sales.take(50).toList(),
    );
  }
}

class _ProductAggregate {
  final String perfumeCode;
  final String productName;
  final String bottleSize;
  int units = 0;
  double revenue = 0.0;

  _ProductAggregate({
    required this.perfumeCode,
    required this.productName,
    required this.bottleSize,
  });
}

class _DayAggregate {
  final String label;
  final String dateString;
  double revenue = 0;
  int units = 0;

  _DayAggregate({
    required this.label,
    required this.dateString,
    required this.revenue,
    required this.units,
  });
}

/// Dynamic Live Sales Records Provider
final salesRecordsProvider = FutureProvider.autoDispose
    .family<List<SaleRecordModel>, String?>((ref, branch) async {
      final sqlite = ref.watch(sqliteServiceProvider);
      return await sqlite.getSalesRecords(branch);
    });

/// Dynamic Computed Sales Analytics Provider
final salesAnalyticsProvider = FutureProvider.autoDispose
    .family<SalesAnalytics, String?>((ref, branch) async {
      final sales = await ref.watch(salesRecordsProvider(branch).future);
      return SalesAnalytics.fromSales(sales);
    });
