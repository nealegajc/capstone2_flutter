import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_helper.dart';
import '../../../data/models/shelf_region_model.dart';
import '../../../data/services/sqlite_service.dart';
import '../../../providers/kiosk_providers.dart';

class ShelfAreaDetailScreen extends ConsumerStatefulWidget {
  const ShelfAreaDetailScreen({super.key});

  @override
  ConsumerState<ShelfAreaDetailScreen> createState() =>
      _ShelfAreaDetailScreenState();
}

class _ShelfAreaDetailScreenState extends ConsumerState<ShelfAreaDetailScreen> {
  int _selectedTierIndex = 0;
  bool _isReviewed = false;

  static const List<Map<String, dynamic>> _shelfTiers = [
    {
      'title': 'Top Shelf (Men\'s Fragrances)',
      'layer': 'Layer A (Top)',
      'gender': 'Men',
      'cam': 'Cam 1A & 1B',
      'color': AppColors.maleBlue,
      'slots': ['AA', 'AB', 'AC', 'AD', 'AE'],
      'scents': [
        'Bvlgari Extreme (AA1/AA2)',
        'Bvlgari Aqua (AB1/AB2)',
        'Clinique Happy Men (AC1/AC2)',
        'Christian Dior Sauvage (AD1/AD2)',
        'Polo Black (AE1/AE2)',
      ],
    },
    {
      'title': 'Middle Shelf (Mixed Fragrances)',
      'layer': 'Layer B (Middle)',
      'gender': 'Mixed',
      'cam': 'Cam 2A & 2B',
      'color': AppColors.brandAccent,
      'slots': ['BA', 'BB', 'BC', 'BD', 'BE'],
      'scents': [
        'Lacoste Red (BA1/BA2)',
        'Lacoste White (BB1/BB2)',
        'Invictus Paco Rabanne (BC1/BC2)',
        'Polo Sport (BD1/BD2)',
        'Tommy Boy (BE1/BE2)',
      ],
    },
    {
      'title': 'Bottom Shelf (Women\'s Fragrances)',
      'layer': 'Layer C (Bottom)',
      'gender': 'Women',
      'cam': 'Cam 3A & 3B',
      'color': AppColors.femalePink,
      'slots': ['CA', 'CB', 'CC', 'CD', 'CE'],
      'scents': [
        'Light Blue D&G (CA1/CA2)',
        'Green Tea Arden (CB1/CB2)',
        'Chanel Coco (CC1/CC2)',
        'Estee Lauder Pleasures (CD1/CD2)',
        'Incanto Shine (CE1/CE2)',
      ],
    },
  ];

  void _markReviewed(String regionName) {
    setState(() => _isReviewed = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$regionName verified & reviewed!'),
        backgroundColor: AppColors.statusGreen,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const branch = 'San Pablo';
    final inventoryAsync = ref.watch(liveInventoryProvider(branch));
    final currentTier = _shelfTiers[_selectedTierIndex];
    final tierColor = currentTier['color'] as Color;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Shelf Zones & Slot Layout'),
        actions: [
          ElevatedButton.icon(
            onPressed: _isReviewed
                ? null
                : () => _markReviewed(currentTier['title'] as String),
            icon: const Icon(Icons.check_circle_outline_rounded, size: 20),
            label: Text(_isReviewed ? 'Zone Checked' : 'Mark as Checked'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.statusGreen,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: FutureBuilder<List<ShelfRegionModel>>(
        future: SqliteService.instance.getShelfRegions(branch),
        builder: (context, snapshot) {
          final invList = inventoryAsync.valueOrNull ?? [];
          final matchingInv = invList
              .where(
                (i) =>
                    i.shelf.contains(currentTier['layer'] as String) ||
                    i.category == currentTier['gender'],
              )
              .toList();
          final totalDetected = matchingInv.fold<int>(
            0,
            (s, i) => s + i.detected,
          );
          final totalRecorded = matchingInv.fold<int>(
            0,
            (s, i) => s + i.recorded,
          );
          final matchRate = totalRecorded > 0
              ? (totalDetected / totalRecorded * 100)
                    .clamp(0, 100)
                    .toStringAsFixed(1)
              : '100.0';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Tier Selection Ribbon
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    children: List.generate(_shelfTiers.length, (idx) {
                      final tier = _shelfTiers[idx];
                      final isSelected = _selectedTierIndex == idx;
                      final color = tier['color'] as Color;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: InkWell(
                            onTap: () =>
                                setState(() => _selectedTierIndex = idx),
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                vertical: 14,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? color
                                      : Colors.transparent,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.shelves,
                                    color: isSelected
                                        ? color
                                        : context.textSecondaryColor,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    tier['title'] as String,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: isSelected
                                          ? context.textPrimaryColor
                                          : context.textSecondaryColor,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 18),

                // 2. Active Tier Header Card
                Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: tierColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: tierColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.grid_view_rounded,
                            color: tierColor,
                            size: 36,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    currentTier['title'] as String,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: tierColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${currentTier['cam']}',
                                      style: TextStyle(
                                        color: tierColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '5 Trays (10 Scents) • 100ML Front & 50ML Back Partitions • 50 Bottles Max Capacity',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.statusGreen.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppColors.statusGreen.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                          child: Text(
                            '$matchRate% In Place',
                            style: const TextStyle(
                              color: AppColors.statusGreen,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Slot Position vs Quantities Grid
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Slot Position Details & Visual Tray Grid
                    Expanded(
                      flex: 6,
                      child: Container(
                        height: 340,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: context.borderColor),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.videocam_rounded,
                                      color: tierColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${currentTier['cam']} — Shelf Tray Partitions',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white12,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '100ML Front | 50ML Back',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Visual Trays Representation
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: (currentTier['slots'] as List<String>)
                                  .map((slotCode) {
                                    return Container(
                                      width: 78,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        color: Colors.black45,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: tierColor.withValues(
                                            alpha: 0.6,
                                          ),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 4,
                                            ),
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: tierColor.withValues(
                                                alpha: 0.25,
                                              ),
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(8),
                                                  ),
                                            ),
                                            child: Text(
                                              'TRAY $slotCode',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                                color: tierColor,
                                              ),
                                            ),
                                          ),
                                          Expanded(
                                            child: Column(
                                              children: [
                                                Expanded(
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.05,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${slotCode}1\n100ML',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          color: Colors.white70,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Container(
                                                    margin:
                                                        const EdgeInsets.all(4),
                                                    decoration: BoxDecoration(
                                                      color: tierColor
                                                          .withValues(
                                                            alpha: 0.1,
                                                          ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            6,
                                                          ),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        '${slotCode}2\n50ML',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: TextStyle(
                                                          color: tierColor,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  })
                                  .toList(),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),

                    // Right: Quantities & Stock Breakdown
                    Expanded(
                      flex: 5,
                      child: Card(
                        color: context.surfaceColor,
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Live Stock & Shelf Quantities',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: context.textPrimaryColor,
                                ),
                              ),
                              Divider(height: 24, color: context.borderColor),
                              _buildQuantityRow(
                                context,
                                'Expected Recorded Count',
                                '$totalRecorded Bottles',
                              ),
                              _buildQuantityRow(
                                context,
                                'Current Detected Count',
                                '$totalDetected Bottles',
                                isGreen: totalDetected >= totalRecorded,
                              ),
                              _buildQuantityRow(
                                context,
                                'Partition Layout',
                                '100ML Front / 50ML Back',
                              ),
                              _buildQuantityRow(
                                context,
                                'Camera Coverage',
                                currentTier['cam'] as String,
                              ),
                              _buildQuantityRow(
                                context,
                                'Assigned Scents',
                                '${(currentTier['scents'] as List).length} Fragrances',
                              ),
                              const SizedBox(height: 20),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => context.push(
                                        AppRoutePaths.createRestock,
                                      ),
                                      icon: const Icon(
                                        Icons.add_shopping_cart_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Log Restock'),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => context.push(
                                        AppRoutePaths.cameraMonitor,
                                      ),
                                      icon: const Icon(
                                        Icons.videocam_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Camera Feed'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: tierColor,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
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
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 4. Assigned Fragrances Card
                Card(
                  color: context.surfaceColor,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assigned Fragrance Allocations',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        Divider(height: 20, color: context.borderColor),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: (currentTier['scents'] as List<String>).map(
                            (scent) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: context.surfaceElevatedColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: context.borderColor,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 16,
                                      color: tierColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      scent,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: context.textPrimaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuantityRow(
    BuildContext context,
    String label,
    String value, {
    bool isGreen = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: context.textSecondaryColor, fontSize: 13),
          ),
          Text(
            value,
            style: TextStyle(
              color: isGreen ? AppColors.statusGreen : context.textPrimaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
