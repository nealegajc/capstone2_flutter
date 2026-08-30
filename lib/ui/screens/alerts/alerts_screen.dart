import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final alertsAsync = ref.watch(liveAlertsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Alerts & Incidents Center'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await SqliteService.instance.markAllAlertsRead([]);
              ref.invalidate(liveAlertsProvider(branch));
              ref.invalidate(dashboardStatsProvider(branch));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('All active alerts marked as acknowledged.'),
                    backgroundColor: AppColors.statusGreen,
                  ),
                );
              }
            },
            icon: const Icon(Icons.done_all_rounded, size: 22),
            label: const Text('Acknowledge All'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: alertsAsync.when(
        data: (alerts) {
          final lowStockCount = alerts.where((a) => a.type == 'low_stock' || a.type == 'lowStock').length;
          final misplacedCount = alerts.where((a) => a.type == 'misplaced').length;
          final qualityCount = alerts.where((a) => a.type == 'quality').length;

          final filtered = alerts.where((a) {
            if (_selectedFilter == 'low_stock') {
              return a.type == 'low_stock' || a.type == 'lowStock';
            } else if (_selectedFilter == 'misplaced') {
              return a.type == 'misplaced';
            } else if (_selectedFilter == 'quality') {
              return a.type == 'quality';
            }
            return true;
          }).toList();

          return Column(
            children: [
              // Top Filter & Summary Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border(bottom: BorderSide(color: context.borderColor)),
                ),
                child: Row(
                  children: [
                    _buildFilterChip('all', 'All Alerts (${alerts.length})', AppColors.brandAccent),
                    const SizedBox(width: 8),
                    _buildFilterChip('low_stock', 'Low Stock ($lowStockCount)', AppColors.statusRed),
                    const SizedBox(width: 8),
                    _buildFilterChip('misplaced', 'Misplaced ($misplacedCount)', AppColors.statusOrange),
                    const SizedBox(width: 8),
                    _buildFilterChip('quality', 'Needs Verification ($qualityCount)', AppColors.brandGold),
                  ],
                ),
              ),

              // Alerts List
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.statusGreen.withValues(alpha: 0.7)),
                            const SizedBox(height: 16),
                            Text(
                              'No Incidents in Selected Category',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All 3 shelf camera layers and fragrance stock levels are optimal.',
                              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final a = filtered[index];
                          final isLow = a.type == 'low_stock' || a.type == 'lowStock';
                          final isMisplaced = a.type == 'misplaced';

                          final statusType = isLow
                              ? StatusBadgeType.lowStock
                              : (isMisplaced ? StatusBadgeType.misplaced : StatusBadgeType.good);
                          final statusLabel = isLow ? 'Low Stock' : (isMisplaced ? 'Misplaced' : 'Notice');

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildAlertCard(
                              context: context,
                              title: a.title,
                              description: a.desc,
                              timestamp: a.formattedTime,
                              statusLabel: statusLabel,
                              statusType: statusType,
                              actionLabel: isLow ? 'Request Restock' : 'Inspect Camera View',
                              onAction: () {
                                if (isLow) {
                                  context.push(AppRoutePaths.createRestock);
                                } else {
                                  context.push(AppRoutePaths.cameraMonitor);
                                }
                              },
                              onDismiss: () async {
                                await SqliteService.instance.markAlertRead(a.id);
                                ref.invalidate(liveAlertsProvider(branch));
                                ref.invalidate(dashboardStatsProvider(branch));
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading alerts: $err')),
      ),
    );
  }

  Widget _buildFilterChip(String value, String label, Color activeColor) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => setState(() => _selectedFilter = value),
      selectedColor: activeColor,
      backgroundColor: context.surfaceElevatedColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : context.textPrimaryColor,
        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isSelected ? activeColor : context.borderColor,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildAlertCard({
    required BuildContext context,
    required String title,
    required String description,
    required String timestamp,
    required String statusLabel,
    required StatusBadgeType statusType,
    required String actionLabel,
    required VoidCallback onAction,
    required VoidCallback onDismiss,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            StatusBadge(type: statusType, customLabel: statusLabel, large: true),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Recorded: $timestamp • San Pablo Kiosk',
                    style: TextStyle(fontSize: 11, color: context.textMutedColor, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.check_circle_outline_rounded, color: context.textMutedColor, size: 24),
              tooltip: 'Mark Resolved',
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}
