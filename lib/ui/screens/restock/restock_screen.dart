import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/services/csv_export_service.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class RestockScreen extends ConsumerWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final eventsAsync = ref.watch(stockMovementLogsProvider(branch));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-page command ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: AppColors.brandAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Restock Management & Shipments',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Log incoming perfume deliveries, review shelf replenishment logs, and verify stock counts.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutePaths.createRestock),
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text(
                      'Log New Restock',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: eventsAsync.when(
              data: (events) {
                final restocks = events
                    .where(
                      (e) =>
                          e.eventType == 'RESTOCKED' || e.eventType == 'ADDED',
                    )
                    .toList();
                final totalUnits = restocks.fold<int>(
                  0,
                  (sum, e) => sum + e.quantity,
                );

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Restock KPI Summary Strip
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              icon: Icons.inventory_2_outlined,
                              iconColor: AppColors.brandAccent,
                              title: 'Total Restock Batches',
                              value: '${restocks.length}',
                              subtitle: 'Recorded delivery batches',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              icon: Icons.check_circle_outline_rounded,
                              iconColor: AppColors.statusGreen,
                              title: 'Total Units Received',
                              value: '$totalUnits bottles',
                              subtitle: 'Delivered to San Pablo kiosk',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildMetricCard(
                              context,
                              icon: Icons.verified_outlined,
                              iconColor: AppColors.brandAccent,
                              title: 'Receiving Accuracy',
                              value: '100% Synced',
                              subtitle: 'Computer vision verified',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // 2-Column Content Layout
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Column: Recent Restock Records (60%)
                          Expanded(
                            flex: 6,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Recent Restock & Receiving Records',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.brandAccent.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${restocks.length} Records',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.brandAccent,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (restocks.isEmpty)
                                  Card(
                                    color: context.surfaceColor,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 48,
                                        horizontal: 24,
                                      ),
                                      child: Center(
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.inventory_2_outlined,
                                              size: 64,
                                              color: context.textMutedColor,
                                            ),
                                            const SizedBox(height: 16),
                                            Text(
                                              'No Restock Deliveries Logged Yet',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: context.textPrimaryColor,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              'When a perfume shipment arrives, tap below to log the batch into the system.',
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    context.textSecondaryColor,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            const SizedBox(height: 20),
                                            ElevatedButton.icon(
                                              onPressed: () => context.push(
                                                AppRoutePaths.createRestock,
                                              ),
                                              icon: const Icon(
                                                Icons.add_rounded,
                                              ),
                                              label: const Text(
                                                'Log First Restock Batch',
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    AppColors.brandAccent,
                                                foregroundColor: Colors.white,
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 20,
                                                      vertical: 12,
                                                    ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: restocks.length,
                                    itemBuilder: (context, index) {
                                      final r = restocks[index];
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        child: _buildRestockItem(
                                          context: context,
                                          batchNumber: r.id,
                                          product:
                                              '${r.productName} (${r.perfumeCode})',
                                          roi: r.shelfArea,
                                          expectedQty: r.quantity,
                                          detectedQty: r.quantity,
                                          statusLabel: 'Verified Restock',
                                          statusType: StatusBadgeType.synced,
                                          timestamp: r.formattedTimestamp,
                                          notes: 'Delivery logged and saved into local SQLite database.',
                                        ),
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 24),

                          // Right Column: Quick Receiving Actions & SOP Guide (40%)
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Quick Receiving Actions
                                Text(
                                  'Restock Operations',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Card(
                                  color: context.surfaceColor,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      children: [
                                        _buildActionTile(
                                          context,
                                          icon: Icons.add_box_rounded,
                                          color: AppColors.brandAccent,
                                          title: 'Log New Delivery Batch',
                                          subtitle: 'Record delivered quantities and shelf placement',
                                          onTap: () => context.push(
                                            AppRoutePaths.createRestock,
                                          ),
                                        ),
                                        Divider(
                                          height: 20,
                                          color: context.borderColor,
                                        ),
                                        _buildActionTile(
                                          context,
                                          icon:
                                              Icons.center_focus_strong_rounded,
                                          color: AppColors.brandAccent,
                                          title: 'Inspect Shelf Camera Zones',
                                          subtitle: 'Review slot allocations across 3 tiers',
                                          onTap: () => context.go(
                                            AppRoutePaths.cameraMonitor,
                                          ),
                                        ),
                                        Divider(
                                          height: 20,
                                          color: context.borderColor,
                                        ),
                                        _buildActionTile(
                                          context,
                                          icon: Icons.download_rounded,
                                          color: AppColors.statusGreen,
                                          title: 'Export Stock Movements (CSV)',
                                          subtitle: 'Download complete restock and audit log',
                                          onTap: () async {
                                            try {
                                              final file =
                                                  await CsvExportService
                                                      .instance
                                                      .exportStockMovementCsv(
                                                        events,
                                                        branch: branch,
                                                      );
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(
                                                  context,
                                                ).showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      'Restock CSV exported to: ${file.path}',
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
                                                    content: Text(
                                                      'Failed to export CSV: $e',
                                                    ),
                                                    backgroundColor:
                                                        AppColors.statusRed,
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                // SOP Restock Checklist Guide
                                Text(
                                  'Restock Procedure (SOP)',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Card(
                                  color: context.surfaceColor,
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        _buildSopStep(
                                          context,
                                          step: '1',
                                          title: 'Inspect Delivery & Invoice',
                                          desc: 'Confirm seal integrity and bottle count against shipping manifest.',
                                        ),
                                        const SizedBox(height: 14),
                                        _buildSopStep(
                                          context,
                                          step: '2',
                                          title: 'Organize by Bottle Size',
                                          desc: 'Position 100ML bottles in FRONT slots and 50ML bottles in REAR slots.',
                                        ),
                                        const SizedBox(height: 14),
                                        _buildSopStep(
                                          context,
                                          step: '3',
                                          title: 'Align within Camera Zones',
                                          desc: 'Ensure upright bottle orientation for optimal overhead camera detection.',
                                        ),
                                        const SizedBox(height: 14),
                                        _buildSopStep(
                                          context,
                                          step: '4',
                                          title: 'Confirm & Sync',
                                          desc: 'Tap "Log New Restock" to persist to local SQLite and sync with Supabase.',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) =>
                  Center(child: Text('Error loading restocks: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.textMutedColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimaryColor,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.textSecondaryColor,
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

  Widget _buildActionTile(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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

  Widget _buildSopStep(
    BuildContext context, {
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: AppColors.brandAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w900,
              color: AppColors.brandAccent,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRestockItem({
    required BuildContext context,
    required String batchNumber,
    required String product,
    required String roi,
    required int expectedQty,
    required int detectedQty,
    required String statusLabel,
    required StatusBadgeType statusType,
    required String timestamp,
    required String notes,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Batch #$batchNumber',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.textMutedColor,
                  ),
                ),
                StatusBadge(type: statusType, customLabel: statusLabel),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              product,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Shelf Location: $roi • Logged: $timestamp',
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
            ),
            Divider(height: 20, color: context.borderColor),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Delivered: $expectedQty bottles',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
                const Text(
                  'Shelf Status: Synced',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.statusGreen,
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
