import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../data/models/inventory_record_model.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/app_button.dart';
import '../components/status_chip.dart';
import '../components/scroll_screen.dart';

class HomeScreen extends StatelessWidget {
  final ValueChanged<int> onNavigateTab;
  final VoidCallback onOpenReports;
  final VoidCallback onOpenProductForm;
  final VoidCallback onOpenSyncStatus;
  final VoidCallback onOpenImageQuality;

  const HomeScreen({
    super.key,
    required this.onNavigateTab,
    required this.onOpenReports,
    required this.onOpenProductForm,
    required this.onOpenSyncStatus,
    required this.onOpenImageQuality,
  });

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final user = provider.currentUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final spItems = provider.allInventoryList.where((i) => i.branch == 'San Pablo').toList();
    final lipaItems = provider.allInventoryList.where((i) => i.branch == 'Lipa').toList();

    final unreadAlerts = provider.alertsList.where((a) => !a.isRead).length;
    final lowStockCount = provider.allInventoryList.where((i) => i.isLowStock).length;

    return ScrollScreen(
      title: 'Smart Shelf Dashboard',
      subtitle: 'Overview of automated shelf monitoring and branch inventory',
      actions: [
        StatusChip(
          status: provider.isEdgeConnected ? 'active' : 'offline',
          customLabel: provider.isEdgeConnected ? 'AI Vision Active' : 'Offline',
        ),
        const SizedBox(width: 14),
        AppButton(
          text: 'Scan Shelf Now',
          icon: Icons.camera_enhance_rounded,
          onPressed: () => provider.triggerManualScan(user?.branch ?? 'San Pablo'),
          height: 48,
          fontSize: 14,
        ),
      ],
      children: [
        // Welcome Card
        AppCard(
          backgroundColor: isDark ? const Color(0xFF131B2E) : const Color(0xFFF1F5F9),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.storefront_rounded, color: AppColors.accent, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Hello, ${user?.email ?? 'User'}',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: user?.isAdmin == true ? AppColors.redBg : AppColors.blueBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            (user?.role ?? 'staff').toUpperCase(),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: user?.isAdmin == true ? AppColors.red : AppColors.blue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Assigned Branch: ${user?.branch ?? 'San Pablo'} • Kiosk Mode Ready',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onOpenSyncStatus,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(
                  provider.lastSyncTime != null
                      ? 'Synced ${provider.lastSyncTime!.hour}:${provider.lastSyncTime!.minute.toString().padLeft(2, '0')}'
                      : 'Sync Status',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Section: Branch Stock Overview Cards (Landscape Grid)
        const Text(
          'Branch Shelf Inventory',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // San Pablo Branch Card
            Expanded(
              child: AppCard(
                onTap: () {
                  provider.setInventoryBranchFilter('San Pablo');
                  onNavigateTab(1); // Go to inventory tab
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'San Pablo Branch (Main)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        StatusChip(
                          status: 'normal',
                          customLabel: '${spItems.length} SKUs',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...spItems.map((item) => _buildStockRow(item, isDark)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Lipa Branch Card
            Expanded(
              child: AppCard(
                onTap: () {
                  provider.setInventoryBranchFilter('Lipa');
                  onNavigateTab(1); // Go to inventory tab
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Lipa Branch (Secondary)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                        ),
                        StatusChip(
                          status: lipaItems.any((i) => i.isOutOfStock) ? 'critical' : 'normal',
                          customLabel: '${lipaItems.length} SKUs',
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...lipaItems.map((item) => _buildStockRow(item, isDark)),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Quick Stats & Actions Grid
        Row(
          children: [
            // Active Alerts Card
            Expanded(
              child: AppCard(
                onTap: () => onNavigateTab(3), // Alerts tab
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: unreadAlerts > 0 ? AppColors.orangeBg : AppColors.greenBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.notifications_active_rounded,
                        color: unreadAlerts > 0 ? AppColors.orange : AppColors.green,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$unreadAlerts Unread Alerts',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            lowStockCount > 0
                                ? '$lowStockCount products low on stock'
                                : 'All inventory levels healthy',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),

            // Image Quality Card (Thesis feature)
            Expanded(
              child: AppCard(
                onTap: onOpenImageQuality,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.blueBg,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: AppColors.blue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Image Quality & AI Logs',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Quality: ${provider.imageQualityLog?.status ?? 'ACCEPTED'} (${provider.imageQualityLog?.brightness.toStringAsFixed(0) ?? '78'}% Brightness)',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Quick Actions Row
        const Text(
          'Quick Operations',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AppCard(
                onTap: () => onNavigateTab(2), // Shelf AI Tab
                child: const Column(
                  children: [
                    Icon(Icons.center_focus_strong_rounded, color: AppColors.accent, size: 36),
                    SizedBox(height: 12),
                    Text('Shelf & ROI Calibration', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: AppCard(
                onTap: () => onNavigateTab(1), // Inventory Tab
                child: const Column(
                  children: [
                    Icon(Icons.inventory_2_rounded, color: AppColors.green, size: 36),
                    SizedBox(height: 12),
                    Text('Browse Inventory', style: TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            if (user?.isAdmin == true) ...[
              Expanded(
                child: AppCard(
                  onTap: onOpenReports,
                  child: const Column(
                    children: [
                      Icon(Icons.insights_rounded, color: AppColors.purple, size: 36),
                      SizedBox(height: 12),
                      Text('Financial Reports', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AppCard(
                  onTap: onOpenProductForm,
                  child: const Column(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, color: AppColors.orange, size: 36),
                      SizedBox(height: 12),
                      Text('Register Product', style: TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildStockRow(InventoryRecordModel item, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                item.perfumeCode,
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '${item.detected}/${item.recorded}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: item.isLowStock
                  ? AppColors.orange
                  : (item.isOutOfStock ? AppColors.red : AppColors.green),
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(
            status: item.status,
            fontSize: 10,
          ),
        ],
      ),
    );
  }
}
