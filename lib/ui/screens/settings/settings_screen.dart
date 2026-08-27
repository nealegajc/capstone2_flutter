import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/seeds/catalog_seed_data.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/auth_provider.dart';
import '../../components/update_pin_dialog.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk Settings & Owner Profile'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Business Owner Profile Card
            Card(
              color: context.surfaceColor,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Row(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.brandAccent.withValues(alpha: 0.15),
                        border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.4), width: 2),
                      ),
                      child: const Icon(Icons.person_rounded, color: AppColors.brandAccent, size: 36),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Otto Scents — Store Owner',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Administrator Access • San Pablo Main Branch Kiosk #01',
                            style: TextStyle(fontSize: 14, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        ref.read(authNotifierProvider.notifier).logout();
                        context.go(AppRoutePaths.login);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.statusRedBg,
                        foregroundColor: AppColors.statusRed,
                        side: const BorderSide(color: AppColors.statusRed, width: 1.5),
                      ),
                      icon: const Icon(Icons.logout_rounded, size: 20),
                      label: const Text('Lock & Log Out'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 2. PIN Security & Access Control
            Text(
              'Security & PIN Settings',
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
                child: Row(
                  children: [
                    const Icon(Icons.pin_rounded, color: AppColors.brandAccent, size: 28),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '6-Digit Store Owner PIN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          Text(
                            'Assigned PIN to unlock terminal and manage inventory',
                            style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final updated = await UpdatePinDialog.show(context);
                        if (updated == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✓ Store Owner PIN has been successfully updated and saved!'),
                              backgroundColor: AppColors.statusGreen,
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.password_rounded, size: 18),
                      label: const Text('Update PIN'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 3. Vision & 3-Camera Hardware Configuration
            Text(
              'Shelf Cameras & Computer Vision Architecture',
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
                    _buildConfigRow(context, 'Fixed Mounted Cameras', '3 Cameras (1 per Shelf Layer)'),
                    Divider(height: 20, color: context.borderColor),
                    _buildConfigRow(context, '📷 Camera 1 (Top Layer)', '10 Male Scents (#1 to #19) • Codes AA1–AK2'),
                    Divider(height: 20, color: context.borderColor),
                    _buildConfigRow(context, '📷 Camera 2 (Middle Layer)', '5 Male (#21–#29) + 5 Female (#2–#12) • BA1–BK2'),
                    Divider(height: 20, color: context.borderColor),
                    _buildConfigRow(context, '📷 Camera 3 (Bottom Layer)', '10 Female Scents (#14 to #32) • Codes CA1–CK2'),
                    Divider(height: 20, color: context.borderColor),
                    _buildConfigRow(context, 'Bottle Sizes Tracked', '100ML (Size 1) & 50ML (Size 2) — 60 SKUs'),
                    Divider(height: 20, color: context.borderColor),
                    _buildConfigRow(context, 'Tracking Scope', 'Pure Inventory Count (No Sales / Price Free)'),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Seeding 60 Otto Scents SKUs (30 variants × 2 sizes) across 3 shelf camera layers...'),
                              backgroundColor: AppColors.brandAccent,
                            ),
                          );
                          try {
                            final client = Supabase.instance.client;
                            await CatalogSeedData.seedToSupabase(client, branch: 'San Pablo');
                            await SqliteService.instance.seedCatalog(branch: 'San Pablo');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('✓ Successfully seeded 60 Otto Scents SKUs to Supabase & SQLite!'),
                                  backgroundColor: AppColors.statusGreen,
                                ),
                              );
                            }
                          } catch (e) {
                            await SqliteService.instance.seedCatalog(branch: 'San Pablo');
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('✓ Seeded 60 SKUs locally in SQLite ($e)'),
                                  backgroundColor: AppColors.statusGreen,
                                ),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.brandAccent,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.cloud_upload_rounded, size: 22),
                        label: const Text(
                          'SEED / RESET 60 CATALOG SKUs TO SUPABASE & LOCAL DB',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 4. Navigation Shortcuts
            Text(
              'System Configuration Shortcuts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 10),

            Card(
              color: context.surfaceColor,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.schedule_rounded, color: AppColors.brandAccent),
                    title: Text('Camera Monitoring Schedules', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimaryColor)),
                    subtitle: Text('Change interval or specific daily capture times', style: TextStyle(color: context.textSecondaryColor)),
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textMutedColor),
                    onTap: () => context.push(AppRoutePaths.schedule),
                  ),
                  Divider(height: 1, color: context.borderColor),
                  ListTile(
                    leading: const Icon(Icons.grid_view_rounded, color: AppColors.brandAccent),
                    title: Text('Shelf ROI Partition Mapping', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimaryColor)),
                    subtitle: Text('Assign perfume products to shelf zones A, B, C, D', style: TextStyle(color: context.textSecondaryColor)),
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textMutedColor),
                    onTap: () => context.push(AppRoutePaths.inventory),
                  ),
                  Divider(height: 1, color: context.borderColor),
                  ListTile(
                    leading: const Icon(Icons.help_center_rounded, color: AppColors.brandAccent),
                    title: Text('Help & Beginner Guide', style: TextStyle(fontWeight: FontWeight.w700, color: context.textPrimaryColor)),
                    subtitle: Text('Easy FAQ guide for common questions and status badges', style: TextStyle(color: context.textSecondaryColor)),
                    trailing: Icon(Icons.chevron_right_rounded, color: context.textMutedColor),
                    onTap: () => context.push(AppRoutePaths.helpGuide),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: context.textSecondaryColor, fontSize: 14)),
        Text(value, style: TextStyle(color: context.textPrimaryColor, fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}
