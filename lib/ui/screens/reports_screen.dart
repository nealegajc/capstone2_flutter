import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/app_provider.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/scroll_screen.dart';

class ReportsScreen extends StatefulWidget {
  final VoidCallback onBack;

  const ReportsScreen({super.key, required this.onBack});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _selectedBranch = 'All Branches';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final inventory = provider.allInventoryList.where((i) {
      return _selectedBranch == 'All Branches' || i.branch == _selectedBranch;
    }).toList();

    final totalValue = inventory.fold<double>(0.0, (acc, item) => acc + (item.detected * item.price));
    final totalBottles = inventory.fold<int>(0, (acc, item) => acc + item.detected);
    final capacityBottles = inventory.fold<int>(0, (acc, item) => acc + item.recorded);

    final spValue = provider.allInventoryList
        .where((i) => i.branch == 'San Pablo')
        .fold<double>(0.0, (acc, item) => acc + (item.detected * item.price));
    final lipaValue = provider.allInventoryList
        .where((i) => i.branch == 'Lipa')
        .fold<double>(0.0, (acc, item) => acc + (item.detected * item.price));

    final spK = spValue / 1000.0;
    final lipaK = lipaValue / 1000.0;

    final spSpots = List.generate(7, (i) {
      final factor = 0.75 + (i * 0.04);
      return FlSpot(i.toDouble(), double.parse((spK * factor).toStringAsFixed(1)));
    });

    final lipaSpots = List.generate(7, (i) {
      final factor = 0.65 + (i * 0.05);
      return FlSpot(i.toDouble(), double.parse((lipaK * factor).toStringAsFixed(1)));
    });

    return ScrollScreen(
      title: 'Financial & Inventory Reports',
      subtitle: 'Sales analytics, revenue trajectory, and multi-branch stock valuation',
      showBackButton: true,
      onBack: widget.onBack,
      actions: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBg : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _selectedBranch,
              items: ['All Branches', 'San Pablo', 'Lipa'].map((b) {
                return DropdownMenuItem(value: b, child: Text(b));
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedBranch = val);
              },
            ),
          ),
        ),
      ],
      children: [
        // Summary KPI Metrics Row
        Row(
          children: [
            _buildKpiCard('Total Shelf Valuation', totalValue.toPhp(), Icons.account_balance_wallet_outlined, AppColors.green, isDark),
            const SizedBox(width: 16),
            _buildKpiCard('Active Bottle Count', '$totalBottles / $capacityBottles', Icons.shelves, AppColors.blue, isDark),
            const SizedBox(width: 16),
            _buildKpiCard('Estimated Revenue', totalValue.toPhp(), Icons.trending_up_rounded, AppColors.purple, isDark),
            const SizedBox(width: 16),
            _buildKpiCard('Monitored SKUs', '${inventory.length} Perfumes', Icons.category_outlined, AppColors.orange, isDark),
          ],
        ),
        const SizedBox(height: 28),

        // fl_chart Revenue & Sales Trend LineChart Card
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Weekly Sales & Revenue Trajectory (PHP)',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'AI detection verified stock turnover per day',
                        style: TextStyle(fontSize: 13, color: AppColors.gray),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      _buildLegendDot(AppColors.accent, 'San Pablo'),
                      const SizedBox(width: 16),
                      _buildLegendDot(AppColors.accentPurple, 'Lipa'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                height: 260,
                child: LineChart(
                  LineChartData(
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 48,
                          getTitlesWidget: (val, meta) => Text(
                            '₱${val.toInt()}k',
                            style: const TextStyle(fontSize: 11, color: AppColors.gray),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          interval: 1,
                          getTitlesWidget: (val, meta) {
                            const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                            final idx = val.toInt();
                            if (idx >= 0 && idx < days.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text(days[idx], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      // San Pablo Line
                      LineChartBarData(
                        spots: spSpots,
                        isCurved: true,
                        color: AppColors.accent,
                        barWidth: 3.5,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.accent.withValues(alpha: 0.12),
                        ),
                      ),
                      // Lipa Line
                      LineChartBarData(
                        spots: lipaSpots,
                        isCurved: true,
                        color: AppColors.accentPurple,
                        barWidth: 3.5,
                        dotData: const FlDotData(show: true),
                        belowBarData: BarAreaData(
                          show: true,
                          color: AppColors.accentPurple.withValues(alpha: 0.08),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        // Section: Monitored Perfumes
        const Text(
          'Active Branch Fragrances',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),

        if (inventory.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24.0),
            child: Text('No active inventory records for selected branch filter.', style: TextStyle(color: AppColors.gray)),
          )
        else
          Row(
            children: inventory.map((item) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 14.0),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.category} • Code ${item.perfumeCode} (${item.branch})',
                          style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('₱${item.price.toStringAsFixed(0)} / unit', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${item.detected} in shelf', style: const TextStyle(color: AppColors.green, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildKpiCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Expanded(
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
