import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk Settings & PIN'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // PIN Security Section
            const Text(
              'Security & Access Control',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.pin_rounded, color: AppColors.brandAccent, size: 28),
                        const SizedBox(width: 16),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Store Owner 6-Digit PIN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.darkTextPrimary,
                                ),
                              ),
                              Text(
                                'Required to unlock and configure this kiosk terminal',
                                style: TextStyle(fontSize: 13, color: AppColors.darkTextSecondary),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {},
                          child: const Text('Change PIN'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Vision Scan Schedule
            const Text(
              'Automated Vision Monitoring Schedules',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.darkTextPrimary,
              ),
            ),
            const SizedBox(height: 12),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildSettingSwitchRow(
                      title: 'Continuous Background Scanning',
                      subtitle: 'Run YOLO computer vision detection cycle every 10 minutes',
                      value: true,
                    ),
                    const Divider(height: 24),
                    _buildSettingSwitchRow(
                      title: 'Low Stock Instant Alerts',
                      subtitle: 'Show on-screen popups when inventory falls below minimum threshold',
                      value: true,
                    ),
                    const Divider(height: 24),
                    _buildSettingSwitchRow(
                      title: 'Automatic Cloud Backup',
                      subtitle: 'Sync scan snapshots and logs whenever internet is available',
                      value: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: AppColors.darkTextSecondary),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: AppColors.brandAccent,
          onChanged: (val) {},
        ),
      ],
    );
  }
}
