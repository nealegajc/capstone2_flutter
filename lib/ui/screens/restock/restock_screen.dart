import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';
import '../../components/status_badge.dart';

class RestockScreen extends ConsumerWidget {
  const RestockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final eventsAsync = ref.watch(stockMovementLogsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Restock Management & Delivery Records'),
        actions: [
          ElevatedButton.icon(
            onPressed: () => context.push(AppRoutePaths.createRestock),
            icon: const Icon(Icons.add_rounded, size: 22),
            label: const Text('Log New Restock'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: eventsAsync.when(
        data: (events) {
          final restocks = events.where((e) => e.eventType == 'RESTOCKED' || e.eventType == 'ADDED').toList();

          if (restocks.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: context.textMutedColor),
                  const SizedBox(height: 16),
                  Text(
                    'No Restock Deliveries Logged',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Log New Restock" to record an incoming shipment of perfume bottles.',
                    style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => context.push(AppRoutePaths.createRestock),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Log Restock Batch'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'Recent Restock & Receiving Records',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Track delivered perfume batches and compare physical shipments against automated computer vision shelf detections.',
                style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
              ),
              const SizedBox(height: 20),

              ...restocks.map((r) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildRestockItem(
                    context: context,
                    batchNumber: r.id,
                    product: '${r.productName} (${r.perfumeCode})',
                    roi: r.shelfArea,
                    expectedQty: r.quantity,
                    detectedQty: r.quantity,
                    statusLabel: 'Verified Restock',
                    statusType: StatusBadgeType.synced,
                    timestamp: r.formattedTimestamp,
                    notes: 'Delivery logged and saved into local SQLite database.',
                  ),
                );
              }),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error loading restocks: $err')),
      ),
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
                fontSize: 17,
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
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimaryColor),
                ),
                Text(
                  'Shelf Status: Synced',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.statusGreen),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
