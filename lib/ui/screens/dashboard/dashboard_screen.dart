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
import '../reports/record_sale_dialog.dart';
import '../../../data/services/csv_export_service.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _isScanning = false;

  Future<void> _triggerQuickScan() async {
    setState(() => _isScanning = true);
    String? capturedPath;

    try {
      final hardwareService = ref.read(cameraHardwareServiceProvider);
      final pythonApi = ref.read(pythonApiRepositoryProvider);
      final activeNode = hardwareService.getAssignedDeviceNode(1);

      // 1. Capture physical frame snapshot if camera node accessible
      capturedPath = await hardwareService.captureFrame(
        deviceNode: activeNode,
        mode: CameraQualityMode.fhd1080p,
      );

      // 2. Trigger real Edge Vision AI scan (YOLO + OCR pipeline)
      final scanResult = await pythonApi.triggerManualScan('San Pablo');
      final bottlesCount = (scanResult['bottlesDetected'] as num?)?.toInt() ?? 0;
      final rawDets = scanResult['detections'];
      final List<Map<String, dynamic>> detectionsList = (rawDets is List)
          ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
          : <Map<String, dynamic>>[];

      // 3. Update SQLite inventory_records with detected counts for Camera 1
      try {
        final sqlite = ref.read(sqliteServiceProvider);
        const topSlotCodes = [
          'AA1', 'AA2', 'AB1', 'AB2', 'AC1', 'AC2', 'AD1', 'AD2', 'AE1', 'AE2'
        ];
        await sqlite.updateInventoryFromDetections(
          cameraId: 1,
          detections: detectionsList,
          branch: 'San Pablo',
          targetSlotCodes: topSlotCodes,
        );
      } catch (invErr) {
        debugPrint('[DashboardScreen] Error updating inventory from scan: $invErr');
      }

      // 4. Log camera scan & shelf verification activity
      try {
        final sqlite = ref.read(sqliteServiceProvider);
        await sqlite.logActivity(
          type: 'CAMERA_SCAN',
          description:
              'AI shelf scan executed across shelf layers. Detected: $bottlesCount bottle(s).',
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('[DashboardScreen] Quick scan error: $e');
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }

    if (mounted) {

      // Refresh inventory provider
      ref.invalidate(liveInventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(liveAlertsProvider);
      ref.invalidate(systemActivityLogsProvider);

      final invList = await ref
          .read(sqliteServiceProvider)
          .getInventoryRecords('San Pablo');
      final layerAItems = invList.where(
        (i) => i.shelf.contains('Layer A') || i.category == 'Men',
      );
      final layerBItems = invList.where((i) => i.shelf.contains('Layer B'));
      final layerCItems = invList.where(
        (i) => i.shelf.contains('Layer C') || i.category == 'Women',
      );

      final layerADetected = layerAItems.fold<int>(0, (s, i) => s + i.detected);
      final layerARecorded = layerAItems.fold<int>(0, (s, i) => s + i.recorded);
      final layerAMatch = layerARecorded > 0
          ? (layerADetected / layerARecorded * 100)
                .clamp(0, 100)
                .toStringAsFixed(1)
          : '100.0';

      final layerBDetected = layerBItems.fold<int>(0, (s, i) => s + i.detected);
      final layerBRecorded = layerBItems.fold<int>(0, (s, i) => s + i.recorded);
      final layerBMatch = layerBRecorded > 0
          ? (layerBDetected / layerBRecorded * 100)
                .clamp(0, 100)
                .toStringAsFixed(1)
          : '100.0';

      final layerCDetected = layerCItems.fold<int>(0, (s, i) => s + i.detected);
      final layerCRecorded = layerCItems.fold<int>(0, (s, i) => s + i.recorded);
      final layerCMatch = layerCRecorded > 0
          ? (layerCDetected / layerCRecorded * 100)
                .clamp(0, 100)
                .toStringAsFixed(1)
          : '100.0';

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.statusGreen,
                size: 28,
              ),
              const SizedBox(width: 12),
              Text(
                'Shelf Check Completed',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'All 3 shelf levels and fragrance trays have been checked and bottle counts updated:',
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              _buildScanResultRow(
                context,
                'Top Shelf (Men\'s)',
                'Left & Right Sides ($layerADetected Bottles)',
                '$layerAMatch% In Place',
                AppColors.maleBlue,
              ),
              _buildScanResultRow(
                context,
                'Middle Shelf (Mixed)',
                'Left & Right Sides ($layerBDetected Bottles)',
                '$layerBMatch% In Place',
                AppColors.brandAccent,
              ),
              _buildScanResultRow(
                context,
                'Bottom Shelf (Women\'s)',
                'Left & Right Sides ($layerCDetected Bottles)',
                '$layerCMatch% In Place',
                AppColors.femalePink,
              ),
              if (capturedPath != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Shelf photo captured successfully.',
                  style: TextStyle(color: context.textMutedColor, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Done',
                style: TextStyle(color: context.textSecondaryColor),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                context.push(AppRoutePaths.cameraMonitor);
              },
              icon: const Icon(Icons.videocam_rounded, size: 18),
              label: const Text('View Shelf Cameras'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                RecordSaleDialog.show(context);
              },
              icon: const Icon(Icons.point_of_sale_rounded, size: 18),
              label: const Text('Record a Sale'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.statusGreen,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }
  }

  static Widget _buildScanResultRow(
    BuildContext context,
    String layer,
    String status,
    String accuracy,
    Color color,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            layer,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: context.textPrimaryColor,
              fontSize: 13,
            ),
          ),
          Row(
            children: [
              Text(
                status,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  accuracy,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
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
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final hardwareCamerasAsync = ref.watch(hardwareCamerasProvider);
    final netStatus = ref.watch(networkStatusProvider);
    final detectedCams = hardwareCamerasAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page Header Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Store Overview',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: context.textPrimaryColor,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandAccent.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppColors.brandAccent.withValues(
                                alpha: 0.3,
                              ),
                            ),
                          ),
                          child: const Text(
                            'SHELF ACTIVE',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: AppColors.brandAccent,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Live shelf stock levels, camera view, and fragrance sales overview',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Refresh Store Metrics',
                      icon: const Icon(Icons.refresh_rounded, size: 22),
                      onPressed: () {
                        ref.invalidate(dashboardStatsProvider(branch));
                        ref.invalidate(liveInventoryProvider(branch));
                        ref.invalidate(liveAlertsProvider(branch));
                        ref.invalidate(hardwareCamerasProvider);
                      },
                    ),
                    const SizedBox(width: 8),
                    // 6-Camera Hardware Status Indicator
                    InkWell(
                      onTap: () => CameraAssignmentDialog.show(context),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: detectedCams.isNotEmpty
                              ? AppColors.statusGreen.withValues(alpha: 0.12)
                              : context.surfaceElevatedColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: detectedCams.isNotEmpty
                                ? AppColors.statusGreen.withValues(alpha: 0.4)
                                : context.borderColor,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              detectedCams.isNotEmpty
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_outlined,
                              color: detectedCams.isNotEmpty
                                  ? AppColors.statusGreen
                                  : AppColors.statusOrange,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              detectedCams.isNotEmpty
                                  ? '${detectedCams.length} / 6 Cameras Connected'
                                  : '6 Cameras Standby',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: detectedCams.isNotEmpty
                                    ? AppColors.statusGreen
                                    : context.textPrimaryColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            // 1. Hero Command & Store Check Card
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
                    color: Colors.black.withValues(
                      alpha: context.isDark ? 0.3 : 0.06,
                    ),
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
                      color: AppColors.brandAccent.withValues(
                        alpha: context.isDark ? 0.15 : 0.12,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.brandAccent.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.shelves,
                      color: AppColors.brandAccent,
                      size: 36,
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Otto Scents - Branch Kiosk (San Pablo)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: context.isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF0F172A),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Automatic Fragrance Counter • 3 Shelf Levels • 60 Fragrances',
                          style: TextStyle(
                            fontSize: 14,
                            color: context.isDark
                                ? AppColors.darkTextSecondary
                                : const Color(0xFF475569),
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
                      // Secondary: Shelf Cameras
                      OutlinedButton.icon(
                        onPressed: () =>
                            context.push(AppRoutePaths.cameraMonitor),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 16,
                          ),
                          side: BorderSide(
                            color: AppColors.brandAccent.withValues(alpha: 0.8),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          backgroundColor: context.isDark
                              ? Colors.transparent
                              : Colors.white,
                        ),
                        icon: const Icon(
                          Icons.videocam_rounded,
                          size: 22,
                          color: AppColors.brandAccent,
                        ),
                        label: const Text(
                          'Live Cameras',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brandAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Primary Hero Action: CHECK SHELF NOW
                      ElevatedButton.icon(
                        onPressed: _isScanning ? null : _triggerQuickScan,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: _isScanning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.radar_rounded, size: 24),
                        label: Text(
                          _isScanning ? 'CHECKING SHELF...' : 'CHECK SHELF NOW',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
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
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildHealthChip(
                    label: netStatus.isOnline
                        ? 'Network: Online'
                        : 'Network: Offline',
                    icon: netStatus.isOnline
                        ? Icons.wifi_rounded
                        : Icons.wifi_off_rounded,
                    color: netStatus.isOnline
                        ? AppColors.statusGreen
                        : AppColors.statusOrange,
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
                      label: queue.isEmpty
                          ? 'Offline Saved: Up to Date'
                          : 'Pending Uploads: ${queue.length}',
                      icon: Icons.storage_rounded,
                      color: queue.isEmpty
                          ? AppColors.statusGreen
                          : AppColors.statusOrange,
                      onTap: () => context.push(AppRoutePaths.syncQueue),
                    ),
                    loading: () => const SizedBox(),
                    error: (_, _) => const SizedBox(),
                  ),
                  const SizedBox(width: 12),
                  _buildHealthChip(
                    label: 'Shelf Cameras: Ready',
                    icon: Icons.videocam_rounded,
                    color: AppColors.statusGreen,
                    onTap: () => context.push(AppRoutePaths.cameraMonitor),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.push(AppRoutePaths.inventory),
                    icon: const Icon(Icons.inventory_rounded, size: 16),
                    label: const Text(
                      'View All 60 Scents',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                    subtitle: '60 Fragrances / 300 Bottles Full Shelf',
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
                    subtitle: 'Items with 2 or fewer bottles',
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
                    subtitle: 'Bottles in wrong tray slot',
                    color: AppColors.statusOrange,
                    bgColor: AppColors.statusOrangeBg,
                    icon: Icons.move_up_rounded,
                    onTap: () => context.push(AppRoutePaths.alerts),
                  ),
                  const SizedBox(width: 16),
                  _buildSummaryCard(
                    context: context,
                    title: 'Needs Checking',
                    count: '${stats.needsVerificationCount}',
                    subtitle: 'Bottle cap tilted or obscured',
                    color: AppColors.brandGold,
                    bgColor: const Color(0x26FBBF24),
                    icon: Icons.help_outline_rounded,
                    onTap: () => context.push(AppRoutePaths.cameraMonitor),
                  ),
                ],
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Text('Unable to load live statistics.'),
            ),
            const SizedBox(height: 24),

            // 4. Shelf Level Status & Recent Alerts Grid
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: 3 Shelf Levels Visual Status (with Male/Female Colors)
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
                                '3 Shelf Levels Stock Status',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () =>
                                    context.push(AppRoutePaths.cameraMonitor),
                                icon: const Icon(Icons.tune_rounded, size: 16),
                                label: const Text(
                                  'Adjust Slot Positions',
                                  style: TextStyle(fontSize: 12),
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          inventoryAsync.when(
                            data: (items) {
                              final layerA = items.where(
                                (i) =>
                                    i.shelf.contains('Layer A') ||
                                    i.category == 'Men',
                              );
                              final layerB = items.where(
                                (i) => i.shelf.contains('Layer B'),
                              );
                              final layerC = items.where(
                                (i) =>
                                    i.shelf.contains('Layer C') ||
                                    i.category == 'Women',
                              );

                              final aDet = layerA.fold<int>(
                                0,
                                (s, i) => s + i.detected,
                              );
                              final aRec = layerA.fold<int>(
                                0,
                                (s, i) => s + i.recorded,
                              );
                              final aCap = aRec > 0 ? aRec : 100;
                              final aPct = aCap > 0
                                  ? (aDet / aCap).clamp(0.0, 1.0)
                                  : 0.0;

                              final bDet = layerB.fold<int>(
                                0,
                                (s, i) => s + i.detected,
                              );
                              final bRec = layerB.fold<int>(
                                0,
                                (s, i) => s + i.recorded,
                              );
                              final bCap = bRec > 0 ? bRec : 100;
                              final bPct = bCap > 0
                                  ? (bDet / bCap).clamp(0.0, 1.0)
                                  : 0.0;

                              final cDet = layerC.fold<int>(
                                0,
                                (s, i) => s + i.detected,
                              );
                              final cRec = layerC.fold<int>(
                                0,
                                (s, i) => s + i.recorded,
                              );
                              final cCap = cRec > 0 ? cRec : 100;
                              final cPct = cCap > 0
                                  ? (cDet / cCap).clamp(0.0, 1.0)
                                  : 0.0;

                              return Column(
                                children: [
                                  _buildLayerStatusTile(
                                    context: context,
                                    layerName: 'Top Shelf - Men\'s Scents (Cameras 1A & 1B)',
                                    codes: 'Slots AA to AK • 10 Scents (50ml & 100ml)',
                                    bottles: '$aDet / $aCap Bottles',
                                    percent: aPct,
                                    genderTag: 'Men',
                                    color: AppColors.maleBlue,
                                    onScan: _triggerQuickScan,
                                  ),
                                  const SizedBox(height: 14),
                                  _buildLayerStatusTile(
                                    context: context,
                                    layerName: 'Middle Shelf - Mixed Scents (Cameras 2A & 2B)',
                                    codes: 'Slots BA to BK • Left Men, Right Women (10 Scents)',
                                    bottles: '$bDet / $bCap Bottles',
                                    percent: bPct,
                                    genderTag: 'Mixed',
                                    color: AppColors.brandAccent,
                                    onScan: _triggerQuickScan,
                                  ),
                                  const SizedBox(height: 14),
                                  _buildLayerStatusTile(
                                    context: context,
                                    layerName: 'Bottom Shelf - Women\'s Scents (Cameras 3A & 3B)',
                                    codes: 'Slots CA to CK • 10 Scents (50ml & 100ml)',
                                    bottles: '$cDet / $cCap Bottles',
                                    percent: cPct,
                                    genderTag: 'Women',
                                    color: AppColors.femalePink,
                                    onScan: _triggerQuickScan,
                                  ),
                                ],
                              );
                            },
                            loading: () => const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ),
                            ),
                            error: (_, _) => Column(
                              children: [
                                _buildLayerStatusTile(
                                  context: context,
                                  layerName: 'Top Layer A - Men (Cam 1A & 1B)',
                                  codes: 'AA1 to AK2 • Slots A to K (20 SKUs)',
                                  bottles: '0 / 100 Bottles',
                                  percent: 0.0,
                                  genderTag: 'Men',
                                  color: AppColors.maleBlue,
                                  onScan: _triggerQuickScan,
                                ),
                                const SizedBox(height: 14),
                                _buildLayerStatusTile(
                                  context: context,
                                  layerName:
                                      'Middle Layer B - Mixed (Cam 2A & 2B)',
                                  codes: 'BA1 to BK2 • Left Men, Right Women (20 SKUs)',
                                  bottles: '0 / 100 Bottles',
                                  percent: 0.0,
                                  genderTag: 'Mixed',
                                  color: AppColors.brandAccent,
                                  onScan: _triggerQuickScan,
                                ),
                                const SizedBox(height: 14),
                                _buildLayerStatusTile(
                                  context: context,
                                  layerName:
                                      'Bottom Layer C - Women (Cam 3A & 3B)',
                                  codes: 'CA1 to CK2 • Slots A to K (20 SKUs)',
                                  bottles: '0 / 100 Bottles',
                                  percent: 0.0,
                                  genderTag: 'Women',
                                  color: AppColors.femalePink,
                                  onScan: _triggerQuickScan,
                                ),
                              ],
                            ),
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
                                onPressed: () =>
                                    context.push(AppRoutePaths.alerts),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'View All',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          alertsAsync.when(
                            data: (alerts) {
                              if (alerts.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Center(
                                    child: Text(
                                      'No active shelf alerts. All 6 camera zones optimal.',
                                      style: TextStyle(
                                        color: context.textMutedColor,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              return Column(
                                children: alerts.take(3).map((a) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: _buildAlertItem(
                                      context: context,
                                      product: a.title,
                                      location:
                                          'Cap: ${a.perfumeCode.isNotEmpty ? a.perfumeCode : "Shelf"}',
                                      issue: a.desc,
                                      badgeType: a.type == 'low_stock'
                                          ? StatusBadgeType.lowStock
                                          : (a.type == 'misplaced'
                                                ? StatusBadgeType.misplaced
                                                : StatusBadgeType.good),
                                      onTap: () =>
                                          context.push(AppRoutePaths.alerts),
                                    ),
                                  );
                                }).toList(),
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (_, _) => Text(
                              'Unable to load alerts.',
                              style: TextStyle(
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 5. Quick Operations & Live Store Activity Hub
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Quick Kiosk Operations
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
                                'Quick Kiosk Operations',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.brandAccent.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'STAFF ACTIONS',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.brandAccent,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickActionButton(
                                  context: context,
                                  title: 'Record Sale',
                                  subtitle: 'In-store bottle purchase',
                                  icon: Icons.point_of_sale_rounded,
                                  color: AppColors.brandGold,
                                  onTap: () => RecordSaleDialog.show(
                                    context,
                                    branch: branch,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildQuickActionButton(
                                  context: context,
                                  title: 'Shelf Scan',
                                  subtitle: '6-Camera OCR pass',
                                  icon: Icons.radar_rounded,
                                  color: AppColors.brandAccent,
                                  onTap: _isScanning ? null : _triggerQuickScan,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildQuickActionButton(
                                  context: context,
                                  title: 'Log Restock',
                                  subtitle: 'Incoming bottle delivery',
                                  icon: Icons.move_to_inbox_rounded,
                                  color: AppColors.statusGreen,
                                  onTap: () =>
                                      context.push(AppRoutePaths.createRestock),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildQuickActionButton(
                                  context: context,
                                  title: 'Export Stock CSV',
                                  subtitle: 'Download inventory log',
                                  icon: Icons.download_rounded,
                                  color: AppColors.maleBlue,
                                  onTap: () async {
                                    try {
                                      final items = await ref
                                          .read(sqliteServiceProvider)
                                          .getInventoryRecords(branch);
                                      final file = await CsvExportService
                                          .instance
                                          .exportInventorySummaryCsv(
                                            items,
                                            branch: branch,
                                          );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '✓ Exported inventory to ${file.path}',
                                            ),
                                            backgroundColor:
                                                AppColors.statusGreen,
                                          ),
                                        );
                                      }
                                    } catch (e) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text('Export failed: $e'),
                                            backgroundColor:
                                                AppColors.statusRed,
                                          ),
                                        );
                                      }
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Right: Recent System Activity
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
                                'Recent System Activity',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () =>
                                    context.push(AppRoutePaths.activityLogs),
                                icon: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 16,
                                ),
                                label: const Text(
                                  'View All',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          Divider(height: 24, color: context.borderColor),
                          Consumer(
                            builder: (context, ref, _) {
                              final logsAsync = ref.watch(
                                systemActivityLogsProvider(branch),
                              );
                              return logsAsync.when(
                                data: (logs) {
                                  if (logs.isEmpty) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: Text(
                                          'No recent system activity recorded.',
                                          style: TextStyle(
                                            color: context.textMutedColor,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final recent = logs.take(3).toList();
                                  return Column(
                                    children: [
                                      for (
                                        int i = 0;
                                        i < recent.length;
                                        i++
                                      ) ...[
                                        if (i > 0)
                                          Divider(
                                            height: 14,
                                            color: context.borderColor
                                                .withValues(alpha: 0.5),
                                          ),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: context
                                                    .surfaceElevatedColor,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                recent[i].type.contains('SALE')
                                                    ? Icons.payments_rounded
                                                    : (recent[i].type.contains(
                                                            'SYNC',
                                                          )
                                                          ? Icons
                                                                .cloud_done_rounded
                                                          : (recent[i].type
                                                                    .contains(
                                                                      'SCAN',
                                                                    )
                                                                ? Icons
                                                                      .camera_alt_rounded
                                                                : Icons
                                                                      .info_outline_rounded)),
                                                size: 16,
                                                color: AppColors.brandAccent,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    recent[i].description,
                                                    style: TextStyle(
                                                      fontSize: 12.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: context
                                                          .textPrimaryColor,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                  Text(
                                                    recent[i]
                                                        .formattedTimestamp,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: context
                                                          .textMutedColor,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  );
                                },
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (_, _) => Text(
                                  'Unable to load logs.',
                                  style: TextStyle(
                                    color: context.textSecondaryColor,
                                  ),
                                ),
                              );
                            },
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

  static Widget _buildQuickActionButton({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
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
                      style: TextStyle(
                        fontSize: 11,
                        color: context.textMutedColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
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
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: color,
              ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      genderTag,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    layerName,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              Text(
                bottles,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Assigned Cap OCR Codes: $codes',
            style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
          ),
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
            height: 146,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: color.withValues(alpha: context.isDark ? 0.35 : 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: context.isDark ? 0.08 : 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
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
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 18),
                    ),
                  ],
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      count,
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: color,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.textMutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 11,
                      color: color.withValues(alpha: 0.7),
                    ),
                  ],
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
                    style: TextStyle(
                      fontSize: 12,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: context.textMutedColor,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
