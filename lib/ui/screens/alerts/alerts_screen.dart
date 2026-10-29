import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';
import '../../components/scan_workflow_dialog.dart';
import '../reports/record_sale_dialog.dart';

class AlertsScreen extends ConsumerStatefulWidget {
  final String? initialFilter;

  const AlertsScreen({super.key, this.initialFilter});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  late String _selectedFilter;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter ?? 'all';
  }

  @override
  void didUpdateWidget(covariant AlertsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialFilter != null && widget.initialFilter != oldWidget.initialFilter) {
      _selectedFilter = widget.initialFilter!;
    }
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final alertsAsync = ref.watch(liveAlertsProvider(branch));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: alertsAsync.when(
        data: (alerts) {
          final lowStockCount = alerts
              .where((a) => a.type == 'low_stock' || a.type == 'lowStock')
              .length;
          final misplacedCount = alerts
              .where((a) => a.type == 'misplaced')
              .length;
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // In-page command ribbon
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  border: Border(
                    bottom: BorderSide(color: context.borderColor),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.statusRed.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: AppColors.statusRed,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Shelf Alerts & Incidents Center',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              if (alerts.isNotEmpty) ...[
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.statusRed.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.statusRed.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '${alerts.length} ACTIVE',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.statusRed,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Real-time anomaly detection across camera tiers and fragrance stock levels.',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    OutlinedButton.icon(
                      onPressed: alerts.isEmpty
                          ? null
                          : () async {
                              await SqliteService.instance.markAllAlertsRead(
                                null,
                                branch,
                              );
                              ref.invalidate(liveAlertsProvider(branch));
                              ref.invalidate(dashboardStatsProvider(branch));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'All active alerts marked as acknowledged.',
                                    ),
                                    backgroundColor: AppColors.statusGreen,
                                  ),
                                );
                              }
                            },
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: const Text('Acknowledge All'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        side: BorderSide(color: context.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Filter Chips Bar
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: context.surfaceElevatedColor.withValues(alpha: 0.5),
                  border: Border(
                    bottom: BorderSide(color: context.borderColor),
                  ),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip(
                        'all',
                        'All Alerts',
                        alerts.length,
                        AppColors.brandAccent,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'low_stock',
                        'Low Stock',
                        lowStockCount,
                        AppColors.statusRed,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'misplaced',
                        'Misplaced',
                        misplacedCount,
                        AppColors.statusOrange,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'quality',
                        'Needs Verification',
                        qualityCount,
                        AppColors.brandGold,
                      ),
                    ],
                  ),
                ),
              ),

              // Alerts List
              Expanded(
                child: filtered.isEmpty
                    ? _buildAllClearDashboard(context, branch)
                    : ListView.builder(
                        padding: const EdgeInsets.all(20),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final a = filtered[index];
                          final isLow =
                              a.type == 'low_stock' || a.type == 'lowStock';
                          final isMisplaced = a.type == 'misplaced';

                          final statusType = isLow
                              ? StatusBadgeType.lowStock
                              : (isMisplaced
                                    ? StatusBadgeType.misplaced
                                    : StatusBadgeType.good);
                          final statusLabel = isLow
                              ? 'Low Stock'
                              : (isMisplaced ? 'Misplaced' : 'Notice');

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildAlertCard(
                              context: context,
                              title: a.title,
                              description: a.desc,
                              timestamp: a.formattedTime,
                              statusLabel: statusLabel,
                              statusType: statusType,
                              hasPerfumeCode: a.perfumeCode.isNotEmpty,
                              onRecordSale: () async {
                                final sqlite = ref.read(sqliteServiceProvider);
                                final product = await sqlite.getProductByCode(
                                  a.perfumeCode,
                                );
                                if (context.mounted) {
                                  final recorded = await RecordSaleDialog.show(
                                    context,
                                    initialProduct: product,
                                    branch: branch,
                                  );
                                  if (recorded == true) {
                                    await sqlite.markAlertRead(a.id);
                                    ref.invalidate(liveAlertsProvider(branch));
                                    ref.invalidate(
                                      dashboardStatsProvider(branch),
                                    );
                                  }
                                }
                              },
                              actionLabel: isLow
                                  ? 'Restock This Scent'
                                  : (isMisplaced
                                      ? 'Done Fixing, Verify Now'
                                      : 'Inspect Camera View'),
                              onAction: () {
                                if (isLow) {
                                  context.push(AppRoutePaths.createRestock);
                                } else if (isMisplaced) {
                                  ScanWorkflowDialog.show(
                                    context,
                                    isTargetedVerification: true,
                                    targetAlert: a,
                                  );
                                } else {
                                  context.push(AppRoutePaths.cameraMonitor);
                                }
                              },
                              onDismiss: isMisplaced
                                  ? null
                                  : () async {
                                      await SqliteService.instance.markAlertRead(
                                        a.id,
                                      );
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

  Widget _buildFilterChip(
    String value,
    String label,
    int count,
    Color activeColor,
  ) {
    final isSelected = _selectedFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? activeColor.withValues(alpha: 0.15)
              : context.surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : context.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isSelected ? activeColor : context.textPrimaryColor,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? activeColor : context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : context.textSecondaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertCard({
    required BuildContext context,
    required String title,
    required String description,
    required String timestamp,
    required String statusLabel,
    required StatusBadgeType statusType,
    required bool hasPerfumeCode,
    required VoidCallback onRecordSale,
    required String actionLabel,
    required VoidCallback onAction,
    VoidCallback? onDismiss,
  }) {
    Color accentColor;
    switch (statusType) {
      case StatusBadgeType.lowStock:
        accentColor = AppColors.statusRed;
        break;
      case StatusBadgeType.misplaced:
        accentColor = AppColors.statusOrange;
        break;
      default:
        accentColor = AppColors.brandGold;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Colored left accent strip
              Container(width: 5, color: accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      StatusBadge(
                        type: statusType,
                        customLabel: statusLabel,
                        large: true,
                      ),
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
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondaryColor,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time_rounded,
                                  size: 14,
                                  color: context.textMutedColor,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$timestamp • San Pablo Shelf Station',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.textMutedColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Action buttons with touch target (min 44-48dp)
                      if (hasPerfumeCode) ...[
                        SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: onRecordSale,
                            icon: const Icon(
                              Icons.point_of_sale_rounded,
                              size: 18,
                            ),
                            label: const Text('Record Sale'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.statusGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      if (onDismiss != null) ...[
                        Tooltip(
                          message: 'Mark as Resolved',
                          child: SizedBox(
                            height: 44,
                            width: 44,
                            child: OutlinedButton(
                              onPressed: onDismiss,
                              style: OutlinedButton.styleFrom(
                                padding: EdgeInsets.zero,
                                side: BorderSide(color: context.borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: AppColors.statusGreen,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 44,
                        child: OutlinedButton(
                          onPressed: onAction,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            side: BorderSide(color: context.borderColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Text(
                            actionLabel,
                            style: TextStyle(color: context.textPrimaryColor),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllClearDashboard(BuildContext context, String branch) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // All Clear Hero Banner
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.statusGreen.withValues(
                alpha: context.isDark ? 0.12 : 0.08,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.statusGreen.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.statusGreen.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.statusGreen,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Shelf Systems Optimal • Zero Active Incidents',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Automated computer vision and tray sensors verify that all 60 fragrance SKUs across 3 tiers are correctly placed with normal inventory levels.',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutePaths.cameraMonitor),
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Live Camera Inspection'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.statusGreen,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // 3 Shelf Tiers Health Grid
          Row(
            children: [
              _buildTierDiagnosticCard(
                context,
                title: 'Top Shelf (Men\'s Fragrances)',
                subtitle: 'Slots AA to AK • 10 Scents (50ml & 100ml)',
                cameras: 'Cameras 1A & 1B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.maleBlue,
              ),
              const SizedBox(width: 16),
              _buildTierDiagnosticCard(
                context,
                title: 'Middle Shelf (Mixed Fragrances)',
                subtitle: 'Slots BA to BK • 10 Scents (Left Men, Right Women)',
                cameras: 'Cameras 2A & 2B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.brandAccent,
              ),
              const SizedBox(width: 16),
              _buildTierDiagnosticCard(
                context,
                title: 'Bottom Shelf (Women\'s Fragrances)',
                subtitle: 'Slots CA to CK • 10 Scents (50ml & 100ml)',
                cameras: 'Cameras 3A & 3B (Left & Right)',
                status: 'Optimal • 100% In Place',
                color: AppColors.femalePink,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Telemetry & Diagnostic Strip
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildDiagnosticItem(
                  context,
                  Icons.videocam_rounded,
                  '6 / 6 Cameras Active',
                  'All shelf levels calibrated',
                  AppColors.statusGreen,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.radar_rounded,
                  'Vision AI Active',
                  'YOLOv8 + Cap OCR active',
                  AppColors.brandAccent,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.storage_rounded,
                  'SQLite Cache Sync',
                  'Local database verified',
                  AppColors.maleBlue,
                ),
                _buildDiagnosticItem(
                  context,
                  Icons.cloud_done_rounded,
                  'Cloud Telemetry',
                  'Automatic push ready',
                  AppColors.statusGreen,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierDiagnosticCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required String cameras,
    required String status,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shelves, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 6),
            Text(
              cameras,
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.statusGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.statusGreen,
                    size: 14,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppColors.statusGreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
          ],
        ),
      ],
    );
  }
}
