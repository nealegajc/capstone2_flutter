import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class ShelfCheckHistoryScreen extends StatelessWidget {
  final VoidCallback onBack;

  const ShelfCheckHistoryScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final checkLogs = provider.systemLogs
        .where((l) => l.type == 'shelf_check' || l.type == 'sync' || l.type == 'calibration')
        .toList();

    return ScrollScreen(
      title: 'Shelf AI Check History',
      subtitle: 'Timeline of automated and manual camera inspection cycles',
      showBackButton: true,
      onBack: onBack,
      children: [
        if (checkLogs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48.0),
              child: Column(
                children: [
                  Icon(Icons.history_rounded, size: 48, color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No shelf inspection records yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: checkLogs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final log = checkLogs[index];
              final status = log.type == 'shelf_check' ? 'Completed' : 'Synced';

              return AppCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.camera_indoor_rounded, color: AppColors.accent, size: 26),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${log.branch} • ${log.type.toUpperCase().replaceAll('_', ' ')}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            log.description,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            log.timestamp.formatFullDate(),
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(status: status),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
