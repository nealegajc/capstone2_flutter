import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/restock_record_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';
import '../../components/scan_workflow_dialog.dart';

class ReceivingVerificationScreen extends ConsumerStatefulWidget {
  const ReceivingVerificationScreen({super.key});

  @override
  ConsumerState<ReceivingVerificationScreen> createState() =>
      _ReceivingVerificationScreenState();
}

class _ReceivingVerificationScreenState
    extends ConsumerState<ReceivingVerificationScreen> {
  final Set<String> _confirmedBatchIds = {};

  Future<void> _scanAllShelves() async {
    const branch = 'San Pablo';
    await ScanWorkflowDialog.show(context);
    ref.invalidate(liveInventoryProvider(branch));
    ref.invalidate(restockRecordsProvider(branch));
  }

  Future<void> _scanTray(RestockRecordModel record) async {
    const branch = 'San Pablo';
    final trayCode = record.perfumeCode.length >= 2
        ? record.perfumeCode.substring(0, 2).toUpperCase()
        : record.perfumeCode.toUpperCase();
    final camId = SqliteService.getCameraIdForTray(trayCode);

    await ScanWorkflowDialog.show(
      context,
      targetSlotCodes: [record.perfumeCode],
      targetTrayCodes: [trayCode],
      targetCameraIds: [camId],
      initialCameraId: camId,
    );
    ref.invalidate(liveInventoryProvider(branch));
    ref.invalidate(restockRecordsProvider(branch));
  }

  Future<void> _confirmBatch(RestockRecordModel record, int detectedQty) async {
    // Strict verification guard: require detected shelf count >= expected invoice quantity
    if (detectedQty < record.quantity) {
      _showDiscrepancyDialog(record, detectedQty);
      return;
    }

    const branch = 'San Pablo';
    await SqliteService.instance.resolveRestockDelivery(
      restockId: record.id,
      perfumeCode: record.perfumeCode,
      verifiedQuantity: detectedQty,
      branch: branch,
    );

    // Invalidate Riverpod providers to update entire kiosk state
    ref.invalidate(liveInventoryProvider(branch));
    ref.invalidate(liveAlertsProvider(branch));
    ref.invalidate(resolvedAlertsHistoryProvider(branch));
    ref.invalidate(dashboardStatsProvider(branch));
    ref.invalidate(restockRecordsProvider(branch));
    ref.invalidate(stockMovementLogsProvider(branch));

    setState(() {
      _confirmedBatchIds.add(record.id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delivery batch #${record.id} confirmed and marked as verified. Restocked event logged and alerts cleared.',
          ),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  void _showDiscrepancyDialog(RestockRecordModel record, int detectedQty) {
    final deficit = record.quantity - detectedQty;
    final trayCode = record.perfumeCode.length >= 2
        ? record.perfumeCode.substring(0, 2).toUpperCase()
        : record.perfumeCode.toUpperCase();
    final camId = SqliteService.getCameraIdForTray(trayCode);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.statusRed.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: AppColors.statusRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Stock Verification Discrepancy',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cannot confirm delivery batch #${record.id} due to an inventory shortfall.',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              ),
              child: Column(
                children: [
                  _buildDiscrepancyRow('Item', '${record.productName} (${record.perfumeCode})'),
                  const SizedBox(height: 8),
                  _buildDiscrepancyRow('Assigned Shelf', 'Tray $trayCode (Camera $camId)'),
                  const SizedBox(height: 8),
                  _buildDiscrepancyRow('Expected (Invoice)', '${record.quantity} Bottles'),
                  const SizedBox(height: 8),
                  _buildDiscrepancyRow('Detected (Shelf)', '$detectedQty Bottles', valueColor: AppColors.statusRed),
                  const Divider(height: 16),
                  _buildDiscrepancyRow(
                    'Shortfall / Deficit',
                    '-$deficit Bottles',
                    valueColor: AppColors.statusRed,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Correction Required:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '1. Ensure all delivered bottles are placed onto Tray $trayCode in the designated slot.\n'
              '2. Verify bottles are facing forward and not obscured.\n'
              '3. Run "Scan Tray" to re-verify the shelf count before completing confirmation.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Dismiss'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _scanTray(record);
            },
            icon: const Icon(Icons.qr_code_scanner, size: 18),
            label: const Text('Scan Tray Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandAccent,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscrepancyRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final restocksAsync = ref.watch(restockRecordsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Delivered Stock'),
        actions: [
          // Top Header Action: Scan All Shelves (6 Cameras)
          ElevatedButton.icon(
            onPressed: _scanAllShelves,
            icon: const Icon(Icons.document_scanner_outlined, size: 20),
            label: const Text('Scan All Shelves'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brandPrimary,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => context.push(AppRoutePaths.createRestock),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New Delivery Batch'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: restocksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Error loading restocks: $err')),
        data: (restocks) {
          if (restocks.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 64,
                      color: context.textMutedColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Deliveries Awaiting Verification',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'When a new restock is logged, physical invoice amounts will be compared here against live computer vision shelf detections.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () => context.push(AppRoutePaths.createRestock),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Log Incoming Restock'),
                    ),
                  ],
                ),
              ),
            );
          }

          final invMap = {
            for (final item in (inventoryAsync.valueOrNull ?? []))
              item.perfumeCode: item,
          };

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Instructions Card
                Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: const BoxDecoration(
                            color: AppColors.statusGreenBg,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.fact_check_rounded,
                            color: AppColors.statusGreen,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Delivery Verification & Stock Auditing',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Compare physical invoice restock quantities against actual shelf detected inventory counts.',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                ...restocks.map((r) {
                  final liveInv = invMap[r.perfumeCode];
                  final detected = liveInv?.detected ?? 0;
                  final isMatch = detected >= r.quantity;
                  final isConfirmed =
                      _confirmedBatchIds.contains(r.id) ||
                      r.status == 'verified';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _buildVerificationCard(
                      context: context,
                      record: r,
                      detectedQty: detected,
                      isMatch: isMatch,
                      isConfirmed: isConfirmed,
                      onScanTray: () => _scanTray(r),
                      onConfirm: () => _confirmBatch(r, detected),
                      onShowDiscrepancy: () => _showDiscrepancyDialog(r, detected),
                    ),
                  );
                }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVerificationCard({
    required BuildContext context,
    required RestockRecordModel record,
    required int detectedQty,
    required bool isMatch,
    required bool isConfirmed,
    required VoidCallback onScanTray,
    required VoidCallback onConfirm,
    required VoidCallback onShowDiscrepancy,
  }) {
    final statusLabel = isConfirmed
        ? 'Verified Batch'
        : (isMatch ? 'Quantity Match' : 'Discrepancy (Detected $detectedQty, Need ${record.quantity})');

    final statusType = isConfirmed
        ? StatusBadgeType.synced
        : (isMatch ? StatusBadgeType.good : StatusBadgeType.lowStock);

    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${record.productName} (${record.perfumeCode})',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
                StatusBadge(type: statusType, customLabel: statusLabel),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Batch #${record.id} • From ${record.fromBranch} to ${record.toBranch}',
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
            ),
            Divider(height: 24, color: context.borderColor),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Expected on Invoice',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textMutedColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${record.quantity} Bottles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Camera Vision Count',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textMutedColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$detectedQty Bottles',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isMatch
                              ? AppColors.statusGreen
                              : AppColors.statusRed,
                        ),
                      ),
                    ],
                  ),
                ),
                // In-Place 'Scan Tray' Action
                OutlinedButton.icon(
                  onPressed: isConfirmed ? null : onScanTray,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan Tray'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brandAccent,
                    side: const BorderSide(color: AppColors.brandAccent),
                  ),
                ),
                const SizedBox(width: 8),
                // Strict Confirmation Action
                ElevatedButton.icon(
                  onPressed: isConfirmed
                      ? null
                      : (isMatch ? onConfirm : onShowDiscrepancy),
                  icon: Icon(
                    isConfirmed
                        ? Icons.check_circle_rounded
                        : (isMatch
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded),
                    size: 18,
                  ),
                  label: Text(
                    isConfirmed
                        ? 'Verified'
                        : (isMatch ? 'Confirm Stock' : 'Discrepancy Details'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConfirmed
                        ? Colors.grey
                        : (isMatch
                            ? AppColors.statusGreen
                            : AppColors.statusRed),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
