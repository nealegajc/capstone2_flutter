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

class ReceivingVerificationScreen extends ConsumerStatefulWidget {
  const ReceivingVerificationScreen({super.key});

  @override
  ConsumerState<ReceivingVerificationScreen> createState() =>
      _ReceivingVerificationScreenState();
}

class _ReceivingVerificationScreenState
    extends ConsumerState<ReceivingVerificationScreen> {
  final Set<String> _confirmedBatchIds = {};

  Future<void> _confirmBatch(RestockRecordModel record) async {
    await SqliteService.instance.updateRestockStatus(record.id, 'verified');
    setState(() {
      _confirmedBatchIds.add(record.id);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Delivery batch #${record.id} confirmed and marked as verified.',
          ),
          backgroundColor: AppColors.statusGreen,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Delivered Stock'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => context.push(AppRoutePaths.createRestock),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: const Text('New Delivery Batch'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<List<RestockRecordModel>>(
        future: SqliteService.instance.getRestockRecords(branch),
        builder: (context, snapshot) {
          final restocks = snapshot.data ?? [];

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
                      onPressed: () =>
                          context.push(AppRoutePaths.createRestock),
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
                      onConfirm: () => _confirmBatch(r),
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
    required VoidCallback onConfirm,
  }) {
    final statusLabel = isConfirmed
        ? 'Verified Batch'
        : (isMatch ? 'Quantity Match' : 'Discrepancy (Detected $detectedQty)');

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
                ElevatedButton.icon(
                  onPressed: isConfirmed ? null : onConfirm,
                  icon: const Icon(
                    Icons.check_circle_outline_rounded,
                    size: 18,
                  ),
                  label: Text(isConfirmed ? 'Verified' : 'Confirm Stock'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConfirmed
                        ? Colors.grey
                        : AppColors.statusGreen,
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
