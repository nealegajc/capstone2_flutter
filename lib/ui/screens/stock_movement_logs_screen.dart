import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class StockMovementLogsScreen extends StatelessWidget {
  final VoidCallback onBack;

  const StockMovementLogsScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logs = provider.movementLogs;

    return ScrollScreen(
      title: 'Stock Movement Audit History',
      subtitle: 'Chronological log of physical bottle removals, returns, and restocks',
      showBackButton: true,
      onBack: onBack,
      children: [
        if (logs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Text(
                'No stock movement events recorded yet.',
                style: TextStyle(color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
              ),
            ),
          )
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: logs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final log = logs[index];
              final isRemoval = log.eventType == 'REMOVED';

              return AppCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isRemoval ? AppColors.red : AppColors.green).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isRemoval ? Icons.remove_circle_outline_rounded : Icons.add_circle_outline_rounded,
                        color: isRemoval ? AppColors.red : AppColors.green,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${log.productName} (${log.perfumeCode}) • ${log.quantity} Bottle(s)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${log.branch} • Shelf ${log.shelfArea} • Event Type: ${log.eventType}',
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
                    StatusChip(status: log.eventType),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
