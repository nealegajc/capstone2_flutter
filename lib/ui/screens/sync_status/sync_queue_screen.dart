import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class SyncQueueScreen extends ConsumerWidget {
  const SyncQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final queueAsync = ref.watch(syncQueueListProvider(branch));
    final syncService = ref.watch(syncServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Synchronization Queue (SQLite)'),
        actions: [
          ElevatedButton.icon(
            onPressed: syncService.isSyncing
                ? null
                : () async {
                    final sync = ref.read(syncServiceProvider);
                    await sync.syncPendingQueue();
                    ref.invalidate(syncQueueListProvider(branch));
                    ref.invalidate(dashboardStatsProvider(branch));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Offline sync queue processed with Supabase.'),
                          backgroundColor: AppColors.statusGreen,
                        ),
                      );
                    }
                  },
            icon: syncService.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.refresh_rounded, size: 20),
            label: Text(syncService.isSyncing ? 'Syncing...' : 'Process Queue'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Queue Summary Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.inventory_rounded, color: AppColors.brandAccent, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Local SQLite Buffer for Offline Resilience',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'When offline, all vision detection logs and inventory modifications are safely buffered in local SQLite and uploaded when network resumes.',
                        style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Dynamic Queue Items
          queueAsync.when(
            data: (queue) {
              if (queue.isEmpty) {
                return Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.cloud_done_rounded, size: 54, color: AppColors.statusGreen.withValues(alpha: 0.8)),
                          const SizedBox(height: 12),
                          Text(
                            'Queue is Clear',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'All local records and events are completely synchronized with Supabase.',
                            style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Column(
                children: queue.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildQueueItemCard(
                      context: context,
                      table: item.targetCollection,
                      operation: item.operation,
                      eventId: item.pendingEventId,
                      retryCount: item.retryCount,
                      timestamp: item.formattedTimestamp,
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(child: Text('Error loading sync queue: $err')),
          ),
        ],
      ),
    );
  }

  Widget _buildQueueItemCard({
    required BuildContext context,
    required String table,
    required String operation,
    required String eventId,
    required int retryCount,
    required String timestamp,
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
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        operation.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.brandAccent,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Table: $table',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: context.textPrimaryColor),
                    ),
                  ],
                ),
                StatusBadge(
                  type: StatusBadgeType.pendingSync,
                  customLabel: retryCount > 0 ? 'Retry #$retryCount' : 'Queued',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Pending Event ID: $eventId',
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor, fontFamily: 'monospace'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Queued at: $timestamp',
              style: TextStyle(fontSize: 11, color: context.textMutedColor),
            ),
          ],
        ),
      ),
    );
  }
}
