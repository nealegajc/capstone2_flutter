import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class StockMovementLogsScreen extends ConsumerWidget {
  const StockMovementLogsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final logsAsync = ref.watch(stockMovementLogsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movement & Vision Logs'),
        actions: [
          IconButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Exporting stock movement logs as CSV...'),
                  backgroundColor: AppColors.brandAccent,
                ),
              );
            },
            icon: const Icon(Icons.file_download_outlined, size: 28),
            tooltip: 'Export Movement Logs',
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: logsAsync.when(
        data: (logs) {
          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: context.textMutedColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Stock Movement Events',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Camera detections and inventory movements will appear here.',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(24),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isRestock =
                  log.eventType == 'RESTOCKED' || log.eventType == 'ADDED';
              final isRemoved =
                  log.eventType == 'REMOVED' || log.eventType == 'MISSING';

              final badgeType = isRestock
                  ? StatusBadgeType.synced
                  : (isRemoved
                        ? StatusBadgeType.lowStock
                        : StatusBadgeType.good);

              final icon = isRestock
                  ? Icons.add_circle_outline_rounded
                  : (isRemoved
                        ? Icons.remove_circle_outline_rounded
                        : Icons.camera_alt_outlined);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildMovementLogCard(
                  context: context,
                  product: '${log.productName} (${log.perfumeCode})',
                  movement: '${log.eventType}: Qty ${log.quantity}',
                  roi: log.shelfArea,
                  timestamp: log.formattedTimestamp,
                  type: badgeType,
                  icon: icon,
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text('Error loading movement logs: $err')),
      ),
    );
  }

  Widget _buildMovementLogCard({
    required BuildContext context,
    required String product,
    required String movement,
    required String roi,
    required String timestamp,
    required StatusBadgeType type,
    required IconData icon,
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
                color: AppColors.brandAccent.withValues(
                  alpha: context.isDark ? 0.15 : 0.1,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.brandAccent, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                    'Shelf Region: $roi • Logged at: $timestamp',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                StatusBadge(type: type),
                const SizedBox(height: 4),
                Text(
                  movement,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: context.textMutedColor,
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
