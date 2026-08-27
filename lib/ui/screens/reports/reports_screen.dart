import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../providers/kiosk_providers.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  void _exportReport(BuildContext context, String reportType) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exporting $reportType to local CSV report...'),
        backgroundColor: AppColors.statusGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const branch = 'San Pablo';
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final eventsAsync = ref.watch(stockMovementLogsProvider(branch));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Reports & Analytics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Otto Scents Inventory & Audit Reports',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Generate and review operational data for inventory audits, vendor restocking, vision detection accuracy, and cloud synchronization.',
            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
          ),
          const SizedBox(height: 24),

          // 1. Inventory Summary Report
          inventoryAsync.when(
            data: (items) {
              final totalBottles = items.fold<int>(0, (sum, i) => sum + i.detected);
              return _buildReportCard(
                context: context,
                title: 'Current Inventory Summary Report',
                description: 'Comprehensive table of all perfume bottles, current counts across 3 shelf camera layers.',
                icon: Icons.inventory_2_rounded,
                recordsCount: '${items.length} SKUs • $totalBottles Units Detected',
                onExport: () => _exportReport(context, 'Inventory Summary'),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(height: 14),

          // 2. Inventory Events & Movement Report
          eventsAsync.when(
            data: (events) {
              return _buildReportCard(
                context: context,
                title: 'Inventory Movement & Consumption Report',
                description: 'Detailed log of bottles removed, camera vision updates, and restock receipts.',
                icon: Icons.trending_up_rounded,
                recordsCount: '${events.length} Events Logged',
                onExport: () => _exportReport(context, 'Movement Log'),
              );
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
          const SizedBox(height: 14),

          // 3. Vision Detection & PaddleOCR Accuracy Records
          _buildReportCard(
            context: context,
            title: 'Computer Vision & OCR Accuracy Report',
            description: 'YOLOv8 confidence statistics, cap OCR match rates, and image preprocessing retry metrics across 3 cameras.',
            icon: Icons.insights_rounded,
            recordsCount: '3 Fixed Cameras (Layers A, B, C)',
            onExport: () => _exportReport(context, 'Vision Accuracy'),
          ),
          const SizedBox(height: 14),

          // 4. Cloud Synchronization Audit Report
          _buildReportCard(
            context: context,
            title: 'Supabase Cloud Sync Audit Report',
            description: 'Summary of online/offline status intervals, queued SQLite events, and cloud backup timestamps.',
            icon: Icons.cloud_sync_rounded,
            recordsCount: 'Supabase Active',
            onExport: () => _exportReport(context, 'Sync Report'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard({
    required BuildContext context,
    required String title,
    required String description,
    required IconData icon,
    required String recordsCount,
    required VoidCallback onExport,
  }) {
    return Card(
      color: context.surfaceColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.brandAccent, size: 30),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scope: $recordsCount',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.brandAccent),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Export CSV'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
