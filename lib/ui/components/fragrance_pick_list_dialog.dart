import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/models/inventory_record_model.dart';
import '../../data/services/sqlite_service.dart';
import '../../providers/kiosk_providers.dart';
import 'scan_workflow_dialog.dart';

class FragrancePickListDialog extends ConsumerStatefulWidget {
  final String branch;

  const FragrancePickListDialog({
    super.key,
    this.branch = 'San Pablo',
  });

  static Future<void> show(BuildContext context, {String branch = 'San Pablo'}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => FragrancePickListDialog(branch: branch),
    );
  }

  @override
  ConsumerState<FragrancePickListDialog> createState() =>
      _FragrancePickListDialogState();
}

class _FragrancePickListDialogState
    extends ConsumerState<FragrancePickListDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedTier = 'All'; // 'All', 'Layer A', 'Layer B', 'Layer C', 'Low Stock'
  final Set<String> _selectedCodes = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _derivedTrays {
    return _selectedCodes
        .map((c) => c.length >= 2 ? c.substring(0, 2).toUpperCase() : c.toUpperCase())
        .toSet()
        .toList()
      ..sort();
  }

  List<int> get _derivedCameras {
    return _derivedTrays
        .map((tray) => SqliteService.getCameraIdForTray(tray))
        .toSet()
        .toList()
      ..sort();
  }

  List<InventoryRecordModel> _filterItems(List<InventoryRecordModel> allItems) {
    return allItems.where((item) {
      if (item.isSeasonalOff) return false;

      // Filter by tier / layer
      if (_selectedTier == 'Layer A') {
        if (!item.perfumeCode.startsWith('A') && !item.shelf.contains('Layer A')) {
          return false;
        }
      } else if (_selectedTier == 'Layer B') {
        if (!item.perfumeCode.startsWith('B') && !item.shelf.contains('Layer B')) {
          return false;
        }
      } else if (_selectedTier == 'Layer C') {
        if (!item.perfumeCode.startsWith('C') && !item.shelf.contains('Layer C')) {
          return false;
        }
      } else if (_selectedTier == 'Low Stock') {
        if (item.detected > 2) {
          return false;
        }
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesCode = item.perfumeCode.toLowerCase().contains(q);
        final matchesName = item.name.toLowerCase().contains(q);
        final matchesShelf = item.shelf.toLowerCase().contains(q);
        if (!matchesCode && !matchesName && !matchesShelf) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(liveInventoryProvider(widget.branch));

    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: inventoryAsync.when(
            data: (items) => _buildContent(context, items),
            loading: () => const SizedBox(
              height: 300,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (err, _) => SizedBox(
              height: 250,
              child: Center(
                child: Text(
                  'Failed to load fragrance inventory: $err',
                  style: const TextStyle(color: AppColors.statusRed),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<InventoryRecordModel> allItems) {
    final filtered = _filterItems(allItems);
    final derivedTrays = _derivedTrays;
    final derivedCams = _derivedCameras;

    final lowStockItems = allItems.where((i) => !i.isSeasonalOff && i.detected <= 2).toList();
    final countLayerA = allItems.where((i) => !i.isSeasonalOff && (i.perfumeCode.startsWith('A') || i.shelf.contains('Layer A'))).length;
    final countLayerB = allItems.where((i) => !i.isSeasonalOff && (i.perfumeCode.startsWith('B') || i.shelf.contains('Layer B'))).length;
    final countLayerC = allItems.where((i) => !i.isSeasonalOff && (i.perfumeCode.startsWith('C') || i.shelf.contains('Layer C'))).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title & Close Button
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.brandAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.checklist_rounded,
                      color: AppColors.brandAccent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fragrance Pick List & Selective Scan',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: context.textPrimaryColor,
                            letterSpacing: -0.2,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Select fragrances to derive and trigger only targeted shelf cameras',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Search Bar & Filter Chips
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search fragrance name or code (e.g. Dior, AA1, CD)...',
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            filled: true,
            fillColor: context.surfaceElevatedColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: context.borderColor),
            ),
          ),
          onChanged: (val) => setState(() => _searchQuery = val.trim()),
        ),
        const SizedBox(height: 12),

        // Tier Filter Chips & Quick Batch Action Buttons
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildTierChip('All', 'All (${allItems.length})'),
              const SizedBox(width: 8),
              _buildTierChip('Layer A', 'Layer A - Top ($countLayerA)'),
              const SizedBox(width: 8),
              _buildTierChip('Layer B', 'Layer B - Mid ($countLayerB)'),
              const SizedBox(width: 8),
              _buildTierChip('Layer C', 'Layer C - Bot ($countLayerC)'),
              const SizedBox(width: 8),
              _buildTierChip('Low Stock', 'Low Stock ≤2 (${lowStockItems.length})', isWarning: true),
              const SizedBox(width: 14),
              Container(width: 1, height: 24, color: context.borderColor),
              const SizedBox(width: 14),
              OutlinedButton(
                onPressed: filtered.isEmpty
                    ? null
                    : () {
                        setState(() {
                          for (final item in filtered) {
                            _selectedCodes.add(item.perfumeCode);
                          }
                        });
                      },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Select All Filtered', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: lowStockItems.isEmpty
                    ? null
                    : () {
                        setState(() {
                          for (final item in lowStockItems) {
                            _selectedCodes.add(item.perfumeCode);
                          }
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.statusOrange,
                  side: BorderSide(color: AppColors.statusOrange.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: Text(
                  'Low Stock Only (${lowStockItems.length})',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              if (_selectedCodes.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _selectedCodes.clear()),
                  child: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Fragrance List Table Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: context.borderColor),
          ),
          child: const Row(
            children: [
              SizedBox(width: 48),
              Expanded(
                flex: 4,
                child: Text(
                  'FRAGRANCE / CODE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'BOTTLE SIZE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  'SHELF & CAMERA',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  'STOCK LEVEL',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Fragrance List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off_rounded, size: 48, color: context.textSecondaryColor),
                      const SizedBox(height: 12),
                      Text(
                        'No fragrances match your filter criteria.',
                        style: TextStyle(color: context.textSecondaryColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    final isSelected = _selectedCodes.contains(item.perfumeCode);
                    final trayCode = item.perfumeCode.length >= 2
                        ? item.perfumeCode.substring(0, 2).toUpperCase()
                        : '';
                    final camId = SqliteService.getCameraIdForTray(trayCode);
                    final is100ml = item.perfumeCode.endsWith('1');
                    final sizeLabel = is100ml ? '100ML' : '50ML';

                    final stockColor = item.detected == 0
                        ? AppColors.statusRed
                        : (item.detected <= 2 ? AppColors.statusOrange : AppColors.statusGreen);

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedCodes.remove(item.perfumeCode);
                          } else {
                            _selectedCodes.add(item.perfumeCode);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.brandAccent.withValues(alpha: 0.08)
                              : context.surfaceColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.brandAccent.withValues(alpha: 0.5)
                                : context.borderColor,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isSelected,
                              activeColor: AppColors.brandAccent,
                              onChanged: (checked) {
                                setState(() {
                                  if (checked == true) {
                                    _selectedCodes.add(item.perfumeCode);
                                  } else {
                                    _selectedCodes.remove(item.perfumeCode);
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            // Code & Name
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.brandAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      item.perfumeCode,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: AppColors.brandAccent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      item.name.isNotEmpty
                                          ? item.name
                                          : SqliteService.getPerfumeFullName(item.perfumeCode),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: context.textPrimaryColor,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Bottle Size
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: is100ml
                                      ? AppColors.maleBlue.withValues(alpha: 0.12)
                                      : AppColors.femalePink.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  sizeLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: is100ml ? AppColors.maleBlue : AppColors.femalePink,
                                  ),
                                ),
                              ),
                            ),
                            // Shelf & Camera
                            Expanded(
                              flex: 3,
                              child: Text(
                                'Tray $trayCode • Cam $camId',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: context.textSecondaryColor,
                                ),
                              ),
                            ),
                            // Stock Level
                            Expanded(
                              flex: 2,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: stockColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: stockColor.withValues(alpha: 0.4)),
                                    ),
                                    child: Text(
                                      '${item.detected} / 5',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: stockColor,
                                      ),
                                    ),
                                  ),
                                  if (item.detected <= 2) ...[
                                    const SizedBox(width: 6),
                                    Icon(Icons.warning_amber_rounded, size: 16, color: stockColor),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 16),

        // Bottom Derivation and Trigger Bar
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Derivation Summary
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        text: '${_selectedCodes.length} Fragrances Selected ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: context.textPrimaryColor,
                        ),
                        children: [
                          TextSpan(
                            text: '(${derivedTrays.length} Trays)',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Target Cameras: ',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.textSecondaryColor,
                          ),
                        ),
                        Expanded(
                          child: derivedCams.isEmpty
                              ? Text(
                                  'None (Select fragrances to derive cameras)',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.textSecondaryColor,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                )
                              : SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: derivedCams.map((cam) {
                                      return Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.brandAccent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: AppColors.brandAccent.withValues(alpha: 0.4),
                                            ),
                                          ),
                                          child: Text(
                                            'Cam $cam',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.brandAccent,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Action Buttons
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _selectedCodes.isEmpty
                        ? null
                        : () {
                            final targetSlots = _selectedCodes.toList();
                            final targetTrays = _derivedTrays;
                            final targetCameras = _derivedCameras;

                            Navigator.of(context).pop();

                            ScanWorkflowDialog.show(
                              context,
                              targetSlotCodes: targetSlots,
                              targetTrayCodes: targetTrays,
                              targetCameraIds: targetCameras,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brandAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.radar_rounded, size: 20),
                    label: Text(
                      derivedCams.isEmpty
                          ? 'Select Fragrances'
                          : 'Scan Selected (${derivedCams.length} Camera${derivedCams.length == 1 ? '' : 's'})',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTierChip(String tierKey, String label, {bool isWarning = false}) {
    final isSelected = _selectedTier == tierKey;
    final color = isWarning ? AppColors.statusOrange : AppColors.brandAccent;

    return InkWell(
      onTap: () => setState(() => _selectedTier = tierKey),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.18)
              : context.surfaceElevatedColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : context.borderColor,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected ? color : context.textPrimaryColor,
          ),
        ),
      ),
    );
  }
}
