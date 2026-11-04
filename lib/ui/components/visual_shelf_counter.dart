import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/services/camera_hardware_service.dart';
import '../../data/services/sqlite_service.dart';

class VisualShelfCounter extends StatefulWidget {
  final String perfumeCode;
  final String productName;
  final String bottleSize; // '100ml' or '50ml'
  final int initialCount; // 0..5
  final String trayCode; // e.g. 'AA'
  final ValueChanged<int>? onCountChanged;
  final Future<void> Function(int committedCount)? onCommitCount;

  const VisualShelfCounter({
    super.key,
    required this.perfumeCode,
    required this.productName,
    this.bottleSize = '100ml',
    this.initialCount = 0,
    required this.trayCode,
    this.onCountChanged,
    this.onCommitCount,
  });

  @override
  State<VisualShelfCounter> createState() => _VisualShelfCounterState();
}

class _VisualShelfCounterState extends State<VisualShelfCounter> {
  late int _count;
  bool _isCommitting = false;
  bool _isCapturing = false;
  String? _snapshotPath;
  bool _showCameraPeek = false;

  bool get _is100ml => widget.bottleSize.toLowerCase().contains('100');

  @override
  void initState() {
    super.initState();
    _count = widget.initialCount.clamp(0, 5);
  }

  void _updateCount(int newCount) {
    final clamped = newCount.clamp(0, 5);
    setState(() => _count = clamped);
    widget.onCountChanged?.call(clamped);
  }

  Future<void> _peekCamera() async {
    setState(() {
      _isCapturing = true;
      _showCameraPeek = true;
    });

    try {
      final effectiveTray = widget.trayCode.isNotEmpty
          ? widget.trayCode
          : (widget.perfumeCode.length >= 2
              ? widget.perfumeCode.substring(0, 2).toUpperCase()
              : 'AA');
      final camId = SqliteService.getCameraIdForTray(effectiveTray);
      final node = CameraHardwareService.instance.getAssignedDeviceNode(camId);

      final path = await CameraHardwareService.instance.captureFrame(
        deviceNode: node,
      );

      if (mounted) {
        setState(() {
          _snapshotPath = path;
          _isCapturing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _commit() async {
    if (_isCommitting) return;
    setState(() => _isCommitting = true);

    try {
      if (widget.onCommitCount != null) {
        await widget.onCommitCount!(_count);
      } else {
        await SqliteService.instance.recordVisualCountAudit(
          perfumeCode: widget.perfumeCode,
          countedBottles: _count,
          shelfArea: 'Tray ${widget.trayCode}',
          auditor: 'Store Staff',
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Visual count of $_count bottle(s) committed for ${widget.productName} (${widget.perfumeCode}). Discrepancy alerts resolved.',
            ),
            backgroundColor: AppColors.statusGreen,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCommitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final capDiameter = _is100ml ? 54.0 : 44.0;
    final accentColor = _is100ml ? AppColors.brandAccent : AppColors.brandGold;

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.visibility_rounded,
                          color: AppColors.brandGold,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Visual Shelf Count Audit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.productName} (${widget.perfumeCode}) • ${_is100ml ? "100ML Front Partition" : "50ML Back Partition"} • Tray ${widget.trayCode}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('peek_camera_feed_button'),
                onPressed: _peekCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 16),
                label: const Text('Peek Camera Feed'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brandAccent,
                  side: BorderSide(
                    color: AppColors.brandAccent.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Camera Peek Panel if open
          if (_showCameraPeek) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.brandAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.videocam_rounded,
                            size: 16,
                            color: AppColors.brandAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Shelf Camera Snapshot (Tray ${widget.trayCode})',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brandAccent,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _showCameraPeek = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isCapturing)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(strokeWidth: 2),
                            SizedBox(height: 8),
                            Text(
                              'Acquiring frame from shelf camera...',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_snapshotPath != null &&
                      File(_snapshotPath!).existsSync())
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_snapshotPath!),
                        height: 160,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      height: 100,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_rounded, size: 32, color: Colors.grey),
                          SizedBox(height: 6),
                          Text(
                            'Live camera preview ready on physical terminal.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],

          // 5-Cap Slot Visual Layout (Tray Representation)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                Text(
                  'Physical Slot Layout (Front to Back Positions 1 – 5)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(5, (index) {
                    final pos = index + 1;
                    final isFilled = index < _count;

                    return GestureDetector(
                      onTap: () {
                        if (pos == _count) {
                          _updateCount(pos - 1);
                        } else {
                          _updateCount(pos);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: capDiameter,
                        height: capDiameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled
                              ? accentColor.withValues(alpha: 0.25)
                              : Colors.transparent,
                          border: Border.all(
                            color: isFilled ? accentColor : context.borderColor,
                            width: isFilled ? 2.5 : 1.5,
                          ),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$pos',
                                    style: TextStyle(
                                      fontSize: _is100ml ? 16 : 13,
                                      fontWeight: FontWeight.w900,
                                      color: isFilled
                                          ? accentColor
                                          : context.textSecondaryColor,
                                    ),
                                  ),
                                  Text(
                                    isFilled ? 'FILLED' : 'EMPTY',
                                    style: TextStyle(
                                      fontSize: _is100ml ? 8 : 7,
                                      fontWeight: FontWeight.bold,
                                      color: isFilled
                                          ? accentColor
                                          : context.textMutedColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stepper & Quick Preset Controls
          Row(
            children: [
              // Stepper Adjuster
              IconButton.filledTonal(
                key: const ValueKey('visual_counter_decrement'),
                onPressed: _count > 0 ? () => _updateCount(_count - 1) : null,
                icon: const Icon(Icons.remove_rounded),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.surfaceElevatedColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Text(
                    'Count: $_count / 5 Bottles (${_count * 20}%)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('visual_counter_increment'),
                onPressed: _count < 5 ? () => _updateCount(_count + 1) : null,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick Presets [0] [1] [2] [3] [4] [5]
          Row(
            children: List.generate(6, (preset) {
              final isSelected = _count == preset;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    key: ValueKey('visual_counter_preset_$preset'),
                    onPressed: () => _updateCount(preset),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isSelected
                          ? accentColor.withValues(alpha: 0.2)
                          : Colors.transparent,
                      side: BorderSide(
                        color: isSelected ? accentColor : context.borderColor,
                        width: isSelected ? 2 : 1,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      '$preset',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w900 : FontWeight.bold,
                        color: isSelected
                            ? accentColor
                            : context.textPrimaryColor,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),

          // Commit Count Button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              key: const ValueKey('commit_visual_count_button'),
              onPressed: _isCommitting ? null : _commit,
              icon: _isCommitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 20),
              label: Text(
                _isCommitting
                    ? 'Committing Visual Count...'
                    : 'Commit Visual Count ($_count Bottles)',
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
