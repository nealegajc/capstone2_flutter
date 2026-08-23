import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../data/models/alert_model.dart';
import '../../core/extensions.dart';
import '../theme/app_theme.dart';
import '../components/app_card.dart';
import '../components/scroll_screen.dart';

class AlertsScreen extends StatefulWidget {
  final ValueChanged<AlertModel> onSelectAlert;

  const AlertsScreen({
    super.key,
    required this.onSelectAlert,
  });

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final filterOptions = ['All', 'Inventory', 'Connection', 'Cloud'];

    final filteredAlerts = provider.alertsList.where((a) {
      if (_selectedFilter == 'Inventory') {
        return a.type == 'low_stock' || a.type == 'out_of_stock' || a.type == 'misplaced' || a.type == 'restock';
      } else if (_selectedFilter == 'Connection') {
        return a.type == 'connection';
      } else if (_selectedFilter == 'Cloud') {
        return a.type == 'cloud';
      }
      return true;
    }).toList();

    return ScrollScreen(
      title: 'Alert Notifications',
      subtitle: 'System alerts for inventory thresholds, misplacements, and hardware events',
      actions: [
        TextButton.icon(
          onPressed: provider.markAllAlertsRead,
          icon: const Icon(Icons.mark_email_read_rounded, size: 18),
          label: const Text('Mark All Read'),
        ),
        const SizedBox(width: 8),
        TextButton.icon(
          onPressed: provider.deleteAllReadAlerts,
          icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: AppColors.red),
          label: const Text('Clear Read', style: TextStyle(color: AppColors.red)),
        ),
      ],
      children: [
        // Filter Tabs
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: filterOptions.map((filter) {
              final isSelected = _selectedFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: FilterChip(
                  label: Text(filter),
                  selected: isSelected,
                  onSelected: (_) => setState(() => _selectedFilter = filter),
                  selectedColor: AppColors.accent.withOpacity(0.2),
                  checkmarkColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 20),

        if (filteredAlerts.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(48.0),
              child: Column(
                children: [
                  const Icon(Icons.notifications_off_outlined, size: 64, color: AppColors.gray),
                  const SizedBox(height: 16),
                  const Text('No Alerts in this category', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    'Your smart shelf operations are running normally.',
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
            itemCount: filteredAlerts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final alert = filteredAlerts[index];
              return Dismissible(
                key: Key(alert.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                    color: AppColors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 28),
                ),
                onDismissed: (_) => provider.deleteAlert(alert.id),
                child: _buildAlertCard(alert, provider, isDark),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAlertCard(AlertModel alert, AppProvider provider, bool isDark) {
    Color accentColor;
    IconData icon;

    switch (alert.type.toLowerCase()) {
      case 'low_stock':
        accentColor = AppColors.orange;
        icon = Icons.warning_amber_rounded;
        break;
      case 'out_of_stock':
        accentColor = AppColors.red;
        icon = Icons.error_outline_rounded;
        break;
      case 'misplaced':
        accentColor = AppColors.purple;
        icon = Icons.swap_horiz_rounded;
        break;
      case 'restock':
        accentColor = AppColors.green;
        icon = Icons.inventory_2_outlined;
        break;
      default:
        accentColor = AppColors.blue;
        icon = Icons.info_outline_rounded;
    }

    return AppCard(
      onTap: () {
        if (!alert.isRead) provider.markAlertRead(alert.id);
        widget.onSelectAlert(alert);
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accentColor, size: 26),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: alert.isRead ? FontWeight.bold : FontWeight.w900,
                      ),
                    ),
                    if (!alert.isRead) ...[
                      const SizedBox(width: 8),
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  alert.desc,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${alert.branch} Branch • ${alert.createdAt.formatTimeAgo()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),
          if (!alert.isRead)
            TextButton(
              onPressed: () => provider.markAlertRead(alert.id),
              child: const Text('Mark Read'),
            ),
        ],
      ),
    );
  }
}
