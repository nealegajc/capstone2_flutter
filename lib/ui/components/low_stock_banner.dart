import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_names.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/kiosk_providers.dart';

class LowStockBanner extends ConsumerWidget {
  const LowStockBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branch = ref.watch(currentBranchProvider).valueOrNull ?? 'San Pablo';
    final statsAsync = ref.watch(dashboardStatsProvider(branch));

    return statsAsync.when(
      data: (stats) {
        final totalNeeded = stats.restockNeededCount > 0
            ? stats.restockNeededCount
            : (stats.lowStockCount + stats.outOfStockCount);

        if (totalNeeded <= 0) {
          return const SizedBox.shrink();
        }

        final bool hasOutOfStock = stats.outOfStockCount > 0;
        final String titleText = hasOutOfStock
            ? 'OUT OF STOCK DETECTED: $totalNeeded Fragrances Require Refill'
            : 'LOW STOCK DETECTED: $totalNeeded Fragrances Require Refill';

        final String subtitleText =
            '$totalNeeded fragrance slot(s) running low (≤ 2 bottles). Tap View Details to inspect alerts.';

        final bannerColor = hasOutOfStock ? AppColors.statusRed : AppColors.statusOrange;

        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: bannerColor.withValues(alpha: 0.95),
            boxShadow: [
              BoxShadow(
                color: bannerColor.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasOutOfStock ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titleText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton.icon(
                onPressed: () => context.push(AppRoutePaths.alerts),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: const Text(
                  'View Details',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  elevation: 2,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
