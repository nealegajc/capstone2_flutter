import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class SyncQueueScreen extends StatelessWidget {
  final VoidCallback onBack;

  const SyncQueueScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final queue = provider.syncQueue;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScrollScreen(
      title: 'SQLite Pending Sync Queue',
      subtitle: 'Audit trail of queued local database mutations awaiting cloud replication',
      showBackButton: true,
      onBack: onBack,
      children: [
        if (queue.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  const Icon(Icons.cloud_done_rounded, size: 64, color: AppColors.green),
                  const SizedBox(height: 16),
                  const Text('Sync Queue Empty', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'All local inventory events have been successfully replicated to Supabase.',
                    style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: queue.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = queue[index];
              return AppCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.dataset_rounded, color: AppColors.accent, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Target: ${item.targetCollection} • Event: ${item.pendingEventId}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Branch: ${item.branch} • Retries: ${item.retryCount} • Last attempt: ${item.lastAttempt.formatFullDate()}',
                            style: TextStyle(fontSize: 12, color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(status: item.status),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
