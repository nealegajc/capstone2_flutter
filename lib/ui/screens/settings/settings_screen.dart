import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/seeds/catalog_seed_data.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../data/services/system_power_service.dart';
import '../../../providers/auto_lock_provider.dart';
import '../../../providers/kiosk_providers.dart';
import '../../../providers/system_power_provider.dart';
import '../../components/wifi_connection_dialog.dart';
import '../../components/update_pin_dialog.dart';
import 'camera_assignment_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final netStatus = ref.watch(networkStatusProvider);
    final hardwareCamerasAsync = ref.watch(hardwareCamerasProvider);
    final detectedCams = hardwareCamerasAsync.valueOrNull ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // In-page command ribbon
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(bottom: BorderSide(color: context.borderColor)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.brandAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.settings_outlined,
                    color: AppColors.brandAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store & System Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: context.textPrimaryColor,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hardware camera links, terminal security, store metadata, and catalog sync.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Settings Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Store Information, Security PIN & Inactivity, Hardware Power
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Store Location & Kiosk Info Card
                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.brandAccent.withValues(
                                          alpha: context.isDark ? 0.15 : 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.storefront_rounded,
                                        color: AppColors.brandAccent,
                                        size: 28,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Store Information',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800,
                                            color: context.textPrimaryColor,
                                          ),
                                        ),
                                        Text(
                                          'Physical location details & store branch metadata',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: context.textSecondaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Divider(height: 24, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Store Name',
                                  'Otto Scents Retail Kiosk',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Assigned Branch',
                                  'San Pablo Branch (Kiosk #01)',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Operating System',
                                  'Linux Touchscreen Retail Terminal',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Data Backup',
                                  'Continuous Cloud Sync with Offline Storage Protection',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 2. Security & Access Control (PIN & Auto-Lock) Card
                        Text(
                          'Security & Access Control',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // PIN row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.pin_rounded,
                                          color: AppColors.brandAccent,
                                          size: 24,
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Manager Security PIN',
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: context.textPrimaryColor,
                                              ),
                                            ),
                                            Text(
                                              '6-digit PIN required for manager access',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    context.textSecondaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        final updated =
                                            await UpdatePinDialog.show(context);
                                        if (updated == true &&
                                            context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Security PIN has been successfully updated and saved.',
                                                  ),
                                                  backgroundColor:
                                                      AppColors.statusGreen,
                                                ),
                                              );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.password_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Change PIN'),
                                      style: OutlinedButton.styleFrom(
                                        side: BorderSide(
                                          color: context.borderColor,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Divider(height: 24, color: context.borderColor),

                                // Inactivity Auto-Lock row
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.timer_outlined,
                                                color: AppColors.brandAccent,
                                                size: 22,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                'Terminal Inactivity Auto-Lock',
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w800,
                                                  color:
                                                      context.textPrimaryColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Locks terminal and returns to PIN login when idle.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.textSecondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Consumer(
                                      builder: (context, ref, _) {
                                        final autoLockState = ref.watch(
                                          autoLockProvider,
                                        );
                                        final notifier = ref.read(
                                          autoLockProvider.notifier,
                                        );

                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: context.surfaceElevatedColor,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: context.borderColor,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<int>(
                                              value:
                                                  autoLockState.timeoutMinutes,
                                              dropdownColor:
                                                  context.surfaceElevatedColor,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: context.textPrimaryColor,
                                              ),
                                              icon: const Icon(
                                                Icons.arrow_drop_down_rounded,
                                                color: AppColors.brandAccent,
                                              ),
                                              items: const [
                                                DropdownMenuItem(
                                                  value: 1,
                                                  child: Text('1 Minute'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 2,
                                                  child: Text('2 Minutes'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 3,
                                                  child: Text(
                                                    '3 Min (Default)',
                                                  ),
                                                ),
                                                DropdownMenuItem(
                                                  value: 5,
                                                  child: Text('5 Minutes'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 10,
                                                  child: Text('10 Minutes'),
                                                ),
                                                DropdownMenuItem(
                                                  value: 0,
                                                  child: Text('Disabled'),
                                                ),
                                              ],
                                              onChanged: (newMinutes) async {
                                                if (newMinutes != null) {
                                                  await notifier
                                                      .setTimeoutMinutes(
                                                        newMinutes,
                                                      );
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          newMinutes > 0
                                                              ? 'Inactivity auto-lock timeout updated to $newMinutes min(s).'
                                                              : 'Inactivity auto-lock disabled.',
                                                        ),
                                                        backgroundColor:
                                                            AppColors
                                                                .statusGreen,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 3. Hardware Power & Terminal Maintenance Card
                        Text(
                          'Hardware Power & Management',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.statusRed.withValues(
                                          alpha: context.isDark ? 0.15 : 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.power_settings_new_rounded,
                                        color: AppColors.statusRed,
                                        size: 26,
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Terminal Power Controls',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: context.textPrimaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Relaunch software process, reboot OS, or safely power off kiosk.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context.textSecondaryColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Row(
                                                  children: [
                                                    Icon(
                                                      Icons.restart_alt_rounded,
                                                      color:
                                                          AppColors.brandAccent,
                                                    ),
                                                    SizedBox(width: 8),
                                                    Text(
                                                      'Relaunch Kiosk Application?',
                                                    ),
                                                  ],
                                                ),
                                                content: const Text(
                                                  'This will restart the Otto Scents kiosk software process immediately.',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    style:
                                                        ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              AppColors
                                                                  .brandAccent,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                    child: const Text(
                                                      'Relaunch Now',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await SystemPowerService.instance
                                                  .relaunchApp();
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.restart_alt_rounded,
                                            size: 20,
                                          ),
                                          label: const Text(
                                            'Relaunch App',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(
                                              color: context.borderColor,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            ref
                                                .read(
                                                  systemRestartProvider
                                                      .notifier,
                                                )
                                                .startCountdown(
                                                  action:
                                                      SystemPowerAction.restart,
                                                );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Reboot countdown active. See 15-second banner at top of screen.',
                                                ),
                                                backgroundColor:
                                                    AppColors.statusOrange,
                                                duration: Duration(seconds: 4),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.sync_rounded,
                                            size: 20,
                                            color: AppColors.statusOrange,
                                          ),
                                          label: const Text(
                                            'Restart System',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.statusOrange,
                                            ),
                                          ),
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                              color: AppColors.statusOrange,
                                              width: 1.5,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: SizedBox(
                                        height: 48,
                                        child: ElevatedButton.icon(
                                          onPressed: () {
                                            ref
                                                .read(
                                                  systemRestartProvider
                                                      .notifier,
                                                )
                                                .startCountdown(
                                                  action: SystemPowerAction
                                                      .shutdown,
                                                );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Shutdown countdown active. See 15-second banner at top of screen.',
                                                ),
                                                backgroundColor:
                                                    AppColors.statusRed,
                                                duration: Duration(seconds: 4),
                                              ),
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.power_settings_new_rounded,
                                            size: 20,
                                          ),
                                          label: const Text(
                                            'Shut Down',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                AppColors.statusRed,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 24),

                  // Right Column: Network & Wi-Fi Connectivity, Shelf Cameras & Vision Setup
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 4. Wi-Fi & Internet Connectivity Section
                        Text(
                          'Network & Connectivity',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 10),

                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          netStatus.isOnline
                                              ? Icons.wifi_rounded
                                              : Icons.wifi_off_rounded,
                                          color: netStatus.isOnline
                                              ? AppColors.statusGreen
                                              : AppColors.statusOrange,
                                          size: 26,
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              netStatus.isOnline
                                                  ? 'Internet Connected'
                                                  : 'Offline Mode',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: context.textPrimaryColor,
                                              ),
                                            ),
                                            Text(
                                              netStatus.isOnline
                                                  ? '${netStatus.currentSsid ?? "LAN"} (${netStatus.ipAddress ?? "Online"})'
                                                  : 'Local database active.',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    context.textSecondaryColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () =>
                                          WifiConnectionDialog.show(context),
                                      icon: const Icon(
                                        Icons.wifi_find_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Manage Wi-Fi'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Divider(height: 20, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Sync Protocol',
                                  'Supabase Realtime WebSockets + REST API',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Offline Persistence',
                                  'Local SQLite 3 Cache (Instant Fallback)',
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 5. Vision & 6-Camera Hardware Configuration
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Shelf Cameras & Catalog Setup',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: context.textPrimaryColor,
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  CameraAssignmentDialog.show(context),
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              label: const Text('Connect Webcams'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: context.borderColor),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Card(
                          color: context.surfaceColor,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildConfigRow(
                                  context,
                                  'Camera Layout',
                                  '6 Cameras across 3 Shelf Layers (2 per Layer)',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Top Layer (Men)',
                                  'Cameras 1A & 1B (Slots A–K • 20 Fragrances)',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Middle Layer (Mixed)',
                                  'Cameras 2A & 2B (Men A–E, Women F–K • 20 Fragrances)',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Bottom Layer (Women)',
                                  'Cameras 3A & 3B (Slots A–K • 20 Fragrances)',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Total Fragrances & Capacity',
                                  '60 Fragrance SKUs • 300 Bottles Capacity',
                                ),
                                Divider(height: 18, color: context.borderColor),
                                _buildConfigRow(
                                  context,
                                  'Connected Cameras',
                                  '${detectedCams.length} Devices Connected',
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  height: 52,
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'Restoring 60 Otto Scents fragrances (30 scents x 2 sizes)...',
                                              ),
                                              backgroundColor:
                                                  AppColors.brandAccent,
                                            ),
                                          );
                                      try {
                                        final client = Supabase.instance.client;
                                        await CatalogSeedData.seedToSupabase(
                                          client,
                                          branch: 'San Pablo',
                                        );
                                        await SqliteService.instance
                                            .seedCatalog(branch: 'San Pablo');
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Successfully restored 60 Otto Scents fragrances.',
                                                  ),
                                                  backgroundColor:
                                                      AppColors.statusGreen,
                                                ),
                                              );
                                        }
                                      } catch (e) {
                                        await SqliteService.instance
                                            .seedCatalog(branch: 'San Pablo');
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Restored 60 fragrances locally ($e)',
                                              ),
                                              backgroundColor:
                                                  AppColors.statusGreen,
                                            ),
                                          );
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.cloud_upload_rounded,
                                      size: 22,
                                    ),
                                    label: const Text(
                                      'Restore & Reset 60 Fragrance Catalog',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.brandAccent,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.textSecondaryColor,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
