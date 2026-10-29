import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class ShelfCheckHistoryScreen extends ConsumerWidget {
  const ShelfCheckHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final logsAsync = ref.watch(systemActivityLogsProvider(branch));

    return Scaffold(
      appBar: AppBar(title: const Text('Shelf Check History')),
      body: logsAsync.when(
        data: (allLogs) {
          final scanLogs = allLogs
              .where(
                (l) =>
                    l.type.toUpperCase().contains('SCAN') ||
                    l.type.toUpperCase().contains('VISION') ||
                    l.type.toUpperCase().contains('CAMERA'),
              )
              .toList();

          if (scanLogs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      size: 64,
                      color: context.textMutedColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No Shelf Check History Yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap "Check Shelf Now" on the Store Overview to record live bottle counts.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: scanLogs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final log = scanLogs[index];
              final isAuto = log.type.contains('AUTO');

              return Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.brandAccent.withValues(
                            alpha: context.isDark ? 0.15 : 0.1,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.camera_alt_outlined,
                          color: AppColors.brandAccent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.formattedTimestamp,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              log.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textSecondaryColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Triggered by ${log.user} • ${log.branch}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppColors.statusGreen,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      StatusBadge(
                        type: isAuto
                            ? StatusBadgeType.synced
                            : StatusBadgeType.good,
                        customLabel: isAuto ? 'Automated' : 'Verified',
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) =>
            Center(child: Text('Error loading scan history: $err')),
      ),
    );
  }
}
