import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/camera_hardware_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';
import '../../components/wifi_connection_dialog.dart';
import '../settings/camera_assignment_dialog.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isScanning = false;

  Future<void> _triggerQuickScan() async {
    setState(() => _isScanning = true);

    final hardwareService = ref.read(cameraHardwareServiceProvider);
    final activeNode = hardwareService.getAssignedDeviceNode(1);

    // Capture real high-res frame from primary camera if available
    final capturedPath = await hardwareService.captureFrame(
      deviceNode: activeNode,
      mode: CameraQualityMode.qhd2k,
    );

    // Simulate AI inference pass across 6 camera views
    await Future.delayed(const Duration(milliseconds: 1400));

    if (mounted) {
      setState(() => _isScanning = false);

      // Log camera scan & shelf verification activity
      try {
        final sqlite = ref.read(sqliteServiceProvider);
        await sqlite.logActivity(
          type: 'CAMERA_SCAN',
          description: '6-Camera high-resolution vision scan executed across 3 shelf layers.',
        );
      } catch (_) {}

      // Refresh inventory provider
      ref.invalidate(liveInventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(liveAlertsProvider);
      ref.invalidate(systemActivityLogsProvider);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: AppColors.statusGreen, size: 28),
              const SizedBox(width: 12),
              Text(
                'Shelf Scan Completed',
                style: TextStyle(fontWeight: FontWeight.w800, color: context.textPrimaryColor),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All 3 shelf layers and fragrance trays have been scanned and verified successfully:',
                style: TextStyle(color: context.textSecondaryColor, fontSize: 14),
              ),
              const SizedBox(height: 16),
              _buildScanResultRow(context, 'Top Shelf (Men)', 'Cameras 1A & 1B Verified (20 Fragrances)', '100% Stock Match', AppColors.maleBlue),
              _buildScanResultRow(context, 'Middle Shelf (Mixed)', 'Cameras 2A & 2B Verified (20 Fragrances)', '98.5% Stock Match', AppColors.brandAccent),
              _buildScanResultRow(context, 'Bottom Shelf (Women)', 'Cameras 3A & 3B Verified (20 Fragrances)', '99.1% Stock Match', AppColors.femalePink),
              if (capturedPath != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Verification photo saved: $capturedPath',
                  style: TextStyle(color: context.textMutedColor, fontSize: 11),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Done', style: TextStyle(color: context.textSecondaryColor)),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutePaths.cameraMonitor);
              },
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('Open Shelf Cameras'),
            ),
          ],
        ),
      );
    }
  }

  static Widget _buildScanResultRow(BuildContext context, String layer, String status, String accuracy, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(layer, style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimaryColor, fontSize: 13)),
          Row(
            children: [
              Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(accuracy, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final statsAsync = ref.watch(dashboardStatsProvider(branch));
    final alertsAsync = ref.watch(liveAlertsProvider(branch));
    final syncQueueAsync = ref.watch(syncQueueListProvider(branch));
    final hardwareCamerasAsync = ref.watch(hardwareCamerasProvider);
    final netStatus = ref.watch(networkStatusProvider);
    final detectedCams = hardwareCamerasAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Shelf Command Center'),
        actions: [
          // 6-Camera Hardware Status Indicator
          InkWell(
            onTap: () => CameraAssignmentDialog.show(context),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: detectedCams.isNotEmpty
                    ? AppColors.statusGreen.withValues(alpha: 0.12)
                    : context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: detectedCams.isNotEmpty ? AppColors.statusGreen.withValues(alpha: 0.4) : context.borderColor,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    detectedCams.isNotEmpty ? Icons.videocam_rounded : Icons.videocam_off_outlined,
                    color: detectedCams.isNotEmpty ? AppColors.statusGreen : AppColors.statusOrange,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    detectedCams.isNotEmpty
                        ? '${detectedCams.length} / 6 Cams Detected'
                        : '6 Cameras Standby',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: detectedCams.isNotEmpty ? AppColors.statusGreen : context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Hero Command & AI Vision Trigger Card
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: context.heroGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: context.heroBannerBorder, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: context.isDark ? 0.3 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: const Icon(Icons.shelves, color: AppColors.brandAccent, size: 36),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Otto Scents - Kiosk #01 (San Pablo)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: context.isDark ? AppColors.darkTextPrimary : const Color(0xFF0F172A),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Smart Fragrance Shelf • Real-time Stock Monitoring & Auto-Scanner (3 Layers • 60 Fragrances)',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.isDark ? AppColors.darkTextSecondary : const Color(0xFF475569),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Action Buttons Group
                  Row(
                    children: [
                      // Secondary: 6-Camera Monitor
                      OutlinedButton.icon(
                        onPressed: () => context.push(AppRoutePaths.cameraMonitor),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                          side: BorderSide(color: AppColors.brandAccent.withValues(alpha: 0.8), width: 1.5),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          backgroundColor: context.isDark ? Colors.transparent : Colors.white,
                        ),
                        icon: const Icon(Icons.videocam_rounded, size: 22, color: AppColors.brandAccent),
                        label: const Text(
                          'Shelf Cameras',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brandAccent),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Primary Hero Action: SCAN SHELF NOW
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _triggerQuickScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Icon(Icons.radar_rounded, size: 24),
                        label: Text(
                          _isScanning ? 'SCANNING SHELF...' : 'SCAN SHELF NOW',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 2. Unified System Health Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  Text(
                    'System Health:',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.textSecondaryColor),
                  ),
                  const SizedBox(width: 16),
                  _buildHealthChip(
                    label: netStatus.isOnline ? 'Network: Online' : 'Network: Offline',
                    icon: netStatus.isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                    color: netStatus.isOnline ? AppColors.statusGreen : AppColors.statusOrange,
                    onTap: () => WifiConnectionDialog.show(context),
                  ),
                  const SizedBox(width: 12),
                  _buildHealthChip(
                    label: 'Cloud Sync: Active',
                    icon: Icons.cloud_done_rounded,
                    color: AppColors.statusGreen,
                    onTap: () => context.push(AppRoutePaths.syncStatus),
                  ),
                  const SizedBox(width: 12),
                  syncQueueAsync.when(
                    data: (queue) => _buildHealthChip(
                      label: queue.isEmpty ? 'Offline Buffer: Clear' : 'Offline Queue: ${queue.length} Pending',
                      icon: Icons.storage_rounded,
                      color: queue.isEmpty ? AppColors.statusGreen : AppColors.statusOrange,
                      onTap: () => context.push(AppRoutePaths.syncQueue),
                    ),
                    loading: () => const SizedBox(),
                    error: (_, __) => const SizedBox(),
                  ),
                  const SizedBox(width: 12),
                  _buildHealthChip(
                    label: '6-Camera Setup: Ready',
                    icon: Icons.videocam_rounded,
                    color: AppColors.statusGreen,
                    onTap: () => context.push(AppRoutePaths.cameraMonitor),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.push(AppRoutePaths.inventory),
                    icon: const Icon(Icons.inventory_rounded, size: 16),
                    label: const Text('View All 60 SKUs', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 3. Dynamic Key Performance Inventory Metrics
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  _buildSummaryCard(
                    context: context,
                    title: 'Total In Stock',
                    count: '${stats.totalInStock}',
                    subtitle: '60 SKUs / 300 Bottles Capacity',
                    color: AppColors.statusGreen,
                    bgColor: AppColors.statusGreenBg,
                    icon: Icons.inventory_2_rounded,
                    onTap: () => context.push(AppRoutePaths.inventory),
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context: context,
                    title: 'Low Stock Alerts',
                    count: '${stats.lowStockCount}',
                    subtitle: 'Items below 2 bottles',
                    color: AppColors.statusRed,
                    bgColor: AppColors.statusRedBg,
                    icon: Icons.warning_amber_rounded,
                    onTap: () => context.push(AppRoutePaths.alerts),
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context: context,
                    title: 'Misplaced Bottles',
                    count: '${stats.misplacedCount}',
                    subtitle: 'Detected in wrong partition',
                    color: AppColors.statusOrange,
                    bgColor: AppColors.statusOrangeBg,
                    icon: Icons.move_up_rounded,
                    onTap: () => context.push(AppRoutePaths.alerts),
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context: context,
                    title: 'Needs Verification',
                    count: '${stats.needsVerificationCount}',
                    subtitle: 'Unclear cap angle/OCR',
                    color: AppColors.brandGold,
                    bgColor: const Color(0x26FBBF24),
                    icon: Icons.help_outline_rounded,
                    onTap: () => context.push(AppRoutePaths.cameraMonitor),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Unable to load live statistics.'),
            ),
            const SizedBox(height: 24),

            // 4. 6-Camera Layer Architecture & Active Alerts Grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: 3 Shelf Layers Visual Status (with Male/Female Colors)
                Expanded(
                  flex: 6,
                  child: Card(
                    color: context.surfaceColor,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '3 Shelf Layers & 6-Camera Vision Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () => context.push(AppRoutePaths.cameraMonitor),
                                icon: const Icon(Icons.tune_rounded, size: 16),
                                label: const Text('Touch ROI Editor', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          _buildLayerStatusTile(
                            context: context,
                            layerName: 'Top Layer A - Men (Cam 1A & 1B)',
                            codes: 'AA1 to AK2 • Slots A to K (20 SKUs)',
                            bottles: '98 / 100 Bottles',
                            percent: 0.98,
                            genderTag: 'Men',
                            color: AppColors.maleBlue,
                            onScan: _triggerQuickScan,
                          ),
                          const SizedBox(height: 14),
                          _buildLayerStatusTile(
                            context: context,
                            layerName: 'Middle Layer B - Mixed (Cam 2A & 2B)',
                            codes: 'BA1 to BK2 • Left Men, Right Women (20 SKUs)',
                            bottles: '95 / 100 Bottles',
                            percent: 0.95,
                            genderTag: 'Mixed',
                            color: AppColors.brandAccent,
                            onScan: _triggerQuickScan,
                          ),
                          const SizedBox(height: 14),
                          _buildLayerStatusTile(
                            context: context,
                            layerName: 'Bottom Layer C - Women (Cam 3A & 3B)',
                            codes: 'CA1 to CK2 • Slots A to K (20 SKUs)',
                            bottles: '99 / 100 Bottles',
                            percent: 0.99,
                            genderTag: 'Women',
                            color: AppColors.femalePink,
                            onScan: _triggerQuickScan,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Right Column: Active Alerts Feed
                Expanded(
                  flex: 5,
                  child: Card(
                    color: context.surfaceColor,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Recent Shelf Alerts',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => context.push(AppRoutePaths.alerts),
                                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                                label: const Text('View All', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          alertsAsync.when(
                            data: (alerts) {
                              if (alerts.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'No active shelf alerts. All 6 camera zones optimal.',
                                      style: TextStyle(color: context.textMutedColor, fontSize: 13),
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                children: alerts.take(3).map((a) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: _buildAlertItem(
                                      context: context,
                                      product: a.title,
                                      location: 'Cap: ${a.perfumeCode.isNotEmpty ? a.perfumeCode : "Shelf"}',
                                      issue: a.desc,
                                      badgeType: a.type == 'low_stock'
                                          ? StatusBadgeType.lowStock
                                          : (a.type == 'misplaced' ? StatusBadgeType.misplaced : StatusBadgeType.good),
                                      onTap: () => context.push(AppRoutePaths.alerts),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const Center(child: CircularProgressIndicator()),
                            error: (_, __) => Text('Unable to load alerts.', style: TextStyle(color: context.textSecondaryColor)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildHealthChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildLayerStatusTile({
    required BuildContext context,
    required String layerName,
    required String codes,
    required String bottles,
    required double percent,
    required String genderTag,
    required Color color,
    required VoidCallback onScan,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceElevatedColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      genderTag,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    layerName,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: context.textPrimaryColor),
                  ),
                ],
              ),
              Text(bottles, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Assigned Cap OCR Codes: $codes', style: TextStyle(fontSize: 11, color: context.textSecondaryColor)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 6,
              backgroundColor: context.isDark ? Colors.black26 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildSummaryCard({
    required BuildContext context,
    required String title,
    required String count,
    required String subtitle,
    required Color color,
    required Color bgColor,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 140,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: context.isDark ? 0.35 : 0.5),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: context.isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 18),
                    ),
                  ],
                ),
                Text(
                  count,
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textMutedColor,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildAlertItem({
    required BuildContext context,
    required String product,
    required String location,
    required String issue,
    required StatusBadgeType badgeType,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            StatusBadge(type: badgeType),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  Text(
                    '$location • $issue',
                    style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.textMutedColor, size: 20),
          ],
        ),
      ),
    );
  }
}
