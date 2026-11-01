import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';

import '../../../data/services/sqlite_service.dart';
import '../../../data/services/kiosk_scheduler_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  String _scheduleMode = 'daily'; // 'interval' or 'daily'
  String _selectedInterval = '1hour';
  final Map<String, bool> _dailyCaptureTimes = {
    '09:00': true,
    '14:00': true,
    '21:00': true,
  };

  static const Map<String, String> _checkpointLabels = {
    '09:00': '09:00 AM (Store Opening Check)',
    '14:00': '02:00 PM (Shift Change Check)',
    '21:00': '09:00 PM (Store Closing Check)',
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final mode = await SqliteService.instance.getSetting('schedule_mode');
      final interval = await SqliteService.instance.getSetting(
        'schedule_interval',
      );
      final dailyTimesJson = await SqliteService.instance.getSetting(
        'schedule_daily_times',
      );
      if (mounted) {
        setState(() {
          if (mode != null && mode.isNotEmpty) _scheduleMode = mode;
          if (interval != null && interval.isNotEmpty) {
            _selectedInterval = interval;
          }
          if (dailyTimesJson != null && dailyTimesJson.isNotEmpty) {
            final decoded = jsonDecode(dailyTimesJson);
            if (decoded is Map<String, dynamic>) {
              for (final entry in decoded.entries) {
                final key = entry.key.contains(':')
                    ? entry.key.substring(0, 5)
                    : entry.key;
                if (_dailyCaptureTimes.containsKey(key)) {
                  _dailyCaptureTimes[key] = entry.value == true ||
                      entry.value == 1 ||
                      entry.value == 'true';
                }
              }
            }
          }
        });
      }
    } catch (_) {}
  }

  void _saveSchedule() async {
    try {
      final branch = await SqliteService.instance.getBranchName();
      await SqliteService.instance.setSystemSetting(
        'schedule_mode',
        _scheduleMode,
      );
      await SqliteService.instance.setSystemSetting(
        'schedule_interval',
        _selectedInterval,
      );
      await SqliteService.instance.setSystemSetting(
        'schedule_daily_times',
        jsonEncode(_dailyCaptureTimes),
      );
      await KioskSchedulerService.instance.reloadSchedule();
      final activeLabels = _dailyCaptureTimes.entries
          .where((e) => e.value)
          .map((e) => _checkpointLabels[e.key] ?? e.key)
          .join(', ');
      await SqliteService.instance.logActivity(
        type: 'SCAN_SCHEDULE',
        description:
            'Vision capture schedule set to $_scheduleMode ($_selectedInterval). Active checkpoints: $activeLabels.',
        branch: branch,
      );
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Monitoring capture schedule updated and saved to system!',
          ),
          backgroundColor: AppColors.statusGreen,
        ),
      );
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatic Shelf Check Schedule'),
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
              'Automatic Shelf Recount Times',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose how often the cameras take photos to automatically recount bottles and update stock numbers.',
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
                            subtitle:
                                'Trigger scans at specific business checkpoints (09:00 AM, 02:00 PM, 09:00 PM)',
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
                      RadioGroup<String>(
                        groupValue: _selectedInterval,
                        onChanged: (val) =>
                            setState(() => _selectedInterval = val!),
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              title: Text(
                                'Every 15 Minutes (High Activity)',
                                style: TextStyle(
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              value: '15min',
                            ),
                            RadioListTile<String>(
                              title: Text(
                                'Every 30 Minutes',
                                style: TextStyle(
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              value: '30min',
                            ),
                            RadioListTile<String>(
                              title: Text(
                                'Every 1 Hour (Recommended)',
                                style: TextStyle(
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              value: '1hour',
                            ),
                            RadioListTile<String>(
                              title: Text(
                                'Every 2 Hours',
                                style: TextStyle(
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              value: '2hours',
                            ),
                          ],
                        ),
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
                        final label = _checkpointLabels[timeKey] ?? timeKey;
                        return CheckboxListTile(
                          title: Text(
                            label,
                            style: TextStyle(color: context.textPrimaryColor),
                          ),
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
              ? AppColors.brandAccent.withValues(
                  alpha: context.isDark ? 0.15 : 0.1,
                )
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
                Icon(
                  icon,
                  color: isSelected
                      ? AppColors.brandAccent
                      : context.textSecondaryColor,
                  size: 28,
                ),
                if (isSelected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.brandAccent,
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected
                    ? AppColors.brandAccent
                    : context.textPrimaryColor,
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
