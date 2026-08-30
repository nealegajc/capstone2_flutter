import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  String _scheduleMode = 'interval'; // 'interval' or 'daily'
  String _selectedInterval = '1hour';
  final Map<String, bool> _dailyCaptureTimes = {
    '09:00 AM (Opening Check)': true,
    '12:00 PM (Midday Check)': true,
    '03:00 PM (Afternoon Check)': true,
    '06:00 PM (Closing Check)': true,
  };

  void _saveSchedule() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Monitoring capture schedule updated successfully!'),
        backgroundColor: AppColors.statusGreen,
      ),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shelf Check Schedule Configuration'),
        actions: [
          ElevatedButton.icon(
            onPressed: _saveSchedule,
            icon: const Icon(Icons.save_rounded, size: 22),
            label: const Text('Save Schedule'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Automated Vision Capture Timers',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose how frequently the Otto Scents camera snaps shelf photos for YOLO detection and inventory updating.',
              style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
            ),
            const SizedBox(height: 24),

            // Mode Selector (Interval vs Daily Times)
            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Schedule Type',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildScheduleOptionTile(
                            mode: 'interval',
                            title: 'Interval-Based Monitoring',
                            subtitle: 'Scan every fixed number of minutes/hours (Default: Every 1 Hour)',
                            icon: Icons.timer_outlined,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildScheduleOptionTile(
                            mode: 'daily',
                            title: 'Fixed Daily Times',
                            subtitle: 'Trigger scans at specific business hours (e.g. 9 AM, 12 PM, 3 PM, 6 PM)',
                            icon: Icons.calendar_today_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Detailed Mode Settings
            if (_scheduleMode == 'interval')
              Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Capture Interval Frequency',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      RadioListTile<String>(
                        title: Text('Every 15 Minutes (High Activity)', style: TextStyle(color: context.textPrimaryColor)),
                        value: '15min',
                        groupValue: _selectedInterval,
                        onChanged: (val) => setState(() => _selectedInterval = val!),
                      ),
                      RadioListTile<String>(
                        title: Text('Every 30 Minutes', style: TextStyle(color: context.textPrimaryColor)),
                        value: '30min',
                        groupValue: _selectedInterval,
                        onChanged: (val) => setState(() => _selectedInterval = val!),
                      ),
                      RadioListTile<String>(
                        title: Text('Every 1 Hour (Recommended)', style: TextStyle(color: context.textPrimaryColor)),
                        value: '1hour',
                        groupValue: _selectedInterval,
                        onChanged: (val) => setState(() => _selectedInterval = val!),
                      ),
                      RadioListTile<String>(
                        title: Text('Every 2 Hours', style: TextStyle(color: context.textPrimaryColor)),
                        value: '2hours',
                        groupValue: _selectedInterval,
                        onChanged: (val) => setState(() => _selectedInterval = val!),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                color: context.surfaceColor,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Scheduled Scans',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 14),
                      ..._dailyCaptureTimes.keys.map((timeKey) {
                        return CheckboxListTile(
                          title: Text(timeKey, style: TextStyle(color: context.textPrimaryColor)),
                          value: _dailyCaptureTimes[timeKey],
                          onChanged: (val) {
                            setState(() {
                              _dailyCaptureTimes[timeKey] = val ?? false;
                            });
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleOptionTile({
    required String mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _scheduleMode == mode;
    return InkWell(
      onTap: () => setState(() => _scheduleMode = mode),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandAccent.withValues(alpha: context.isDark ? 0.15 : 0.1)
              : context.surfaceElevatedColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brandAccent : context.borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: isSelected ? AppColors.brandAccent : context.textSecondaryColor, size: 28),
                if (isSelected)
                  const Icon(Icons.check_circle_rounded, color: AppColors.brandAccent, size: 22),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? AppColors.brandAccent : context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
            ),
          ],
        ),
      ),
    );
  }
}
