import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../providers/roi_provider.dart';

class RoiEditorOverlay extends StatefulWidget {
  final RoiState roi;
  final ValueChanged<String?>? onSelectTray;
  final ValueChanged<Offset>? onMove;
  final void Function(String code, Offset deltaNorm)? onMoveTray;
  final void Function(
    bool isTop,
    bool isLeft,
    double newNormX,
    double newNormY,
  )?
  onResizeCorner;
  final void Function(
    String code,
    bool isTop,
    bool isLeft,
    double newNormX,
    double newNormY,
  )?
  onResizeTrayCorner;
  final void Function(RoiHandleType edge, double newNormValue)? onResizeEdge;
  final void Function(String code, RoiHandleType edge, double newNormValue)?
  onResizeTrayEdge;
  final void Function(double scaleFactor, Offset focalPointNorm)? onScale;
  final VoidCallback? onReset;
  final ValueChanged<String>? onResetTray;
  final VoidCallback? onInteractionEnd;
  final bool isInteractive;
  final String cameraName;
  final List<String>
  slotCodes; // e.g. ['A', 'B', 'C', 'D', 'E'] or ['AA', 'AB', 'AC', 'AD', 'AE']

  const RoiEditorOverlay({
    super.key,
    required this.roi,
    this.onSelectTray,
    this.onMove,
    this.onMoveTray,
    this.onResizeCorner,
    this.onResizeTrayCorner,
    this.onResizeEdge,
    this.onResizeTrayEdge,
    this.onScale,
    this.onReset,
    this.onResetTray,
    this.onInteractionEnd,
    this.isInteractive = true,
    this.cameraName = 'Camera 1A',
    this.slotCodes = const ['A', 'B', 'C', 'D', 'E'],
  });

  @override
  State<RoiEditorOverlay> createState() => _RoiEditorOverlayState();
}

class _RoiEditorOverlayState extends State<RoiEditorOverlay> {
  double _baseScale = 1.0;
  // Enhanced touch targets (min 48px for finger touch response)
  static const double _handleTouchSize = 48.0;
  static const double _edgeTouchThickness = 32.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        // 1. Resolve normalized boxes for each detached size slot (e.g. AA1, AA2)
        final resolvedSlotBoxesNorm = widget.roi.getResolvedSlotBoxes(
          widget.slotCodes,
        );
        final Map<String, Rect> resolvedSlotBoxesPx = {};
        resolvedSlotBoxesNorm.forEach((code, normRect) {
          resolvedSlotBoxesPx[code] = Rect.fromLTRB(
            normRect.left * w,
            normRect.top * h,
            normRect.right * w,
            normRect.bottom * h,
          );
        });

        // 2. Resolve normalized envelope boxes for each tray (e.g. AA, AB)
        final resolvedTrayBoxesNorm = widget.roi.getResolvedTrayBoxes(
          widget.slotCodes,
        );
        final Map<String, Rect> resolvedTrayBoxesPx = {};
        resolvedTrayBoxesNorm.forEach((code, normRect) {
          resolvedTrayBoxesPx[code] = Rect.fromLTRB(
            normRect.left * w,
            normRect.top * h,
            normRect.right * w,
            normRect.bottom * h,
          );
        });

        // 3. Compute overall envelope rect
        final overallRect = Rect.fromLTRB(
          widget.roi.left * w,
          widget.roi.top * h,
          widget.roi.right * w,
          widget.roi.bottom * h,
        );

        final selectedCode = widget.roi.selectedTrayCode;
        final selectedRect = selectedCode != null
            ? (resolvedSlotBoxesPx[selectedCode] ?? resolvedTrayBoxesPx[selectedCode])
            : null;

        return Listener(
          onPointerSignal: (pointerSignal) {
            if (!widget.isInteractive) return;
            if (pointerSignal is PointerScrollEvent) {
              final scrollDelta = pointerSignal.scrollDelta.dy;
              final scaleDelta = scrollDelta < 0 ? 1.05 : 0.95;
              final focalNorm = Offset(
                (pointerSignal.localPosition.dx / w).clamp(0.0, 1.0),
                (pointerSignal.localPosition.dy / h).clamp(0.0, 1.0),
              );
              widget.onScale?.call(scaleDelta, focalNorm);
              widget.onInteractionEnd?.call();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. Shaded backdrop + Detached Tray & Size Slot Painter
              CustomPaint(
                size: Size(w, h),
                painter: _TrayRoiPainter(
                  resolvedSlotBoxes: resolvedSlotBoxesPx,
                  resolvedTrayBoxes: resolvedTrayBoxesPx,
                  overallRect: overallRect,
                  selectedCode: selectedCode,
                  isInteractive: widget.isInteractive,
                  isEnabled: widget.roi.isEnabled,
                  disabledCapCodes: widget.roi.disabledCapCodes,
                  slotCodes: widget.slotCodes,
                ),
              ),

              // 2. Background Multi-touch Pinch Detector for Touchscreen
              if (widget.isInteractive && widget.roi.isEnabled)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: (_) => _baseScale = 1.0,
                    onScaleUpdate: (details) {
                      if (details.pointerCount >= 2 && widget.onScale != null) {
                        final scaleRatio = details.scale / _baseScale;
                        _baseScale = details.scale;
                        final focalNorm = Offset(
                          details.localFocalPoint.dx / w,
                          details.localFocalPoint.dy / h,
                        );
                        widget.onScale?.call(scaleRatio, focalNorm);
                      }
                    },
                    onScaleEnd: (_) {
                      _baseScale = 1.0;
                      widget.onInteractionEnd?.call();
                    },
                  ),
                ),

              // 3. Move Body for EACH individual Detached Size Slot (100ML and 50ML)
              if (widget.isInteractive && widget.roi.isEnabled)
                ...resolvedSlotBoxesPx.entries.map((entry) {
                  final code = entry.key;
                  final box = entry.value;
                  final isThisSelected = selectedCode == code;

                  return Positioned(
                    left: math.max(0.0, box.left),
                    top: math.max(0.0, box.top),
                    width: math.max(10.0, box.width),
                    height: math.max(10.0, box.height),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          // Tapping selects this specific size slot
                          widget.onSelectTray?.call(
                            isThisSelected ? null : code,
                          );
                        },
                        onPanStart: (_) {
                          if (!isThisSelected) {
                            widget.onSelectTray?.call(code);
                          }
                        },
                        onPanUpdate: (details) {
                          final deltaNormX = details.delta.dx / w;
                          final deltaNormY = details.delta.dy / h;
                          if (widget.onMoveTray != null) {
                            widget.onMoveTray!(
                              code,
                              Offset(deltaNormX, deltaNormY),
                            );
                          } else {
                            widget.onMove?.call(Offset(deltaNormX, deltaNormY));
                          }
                        },
                        onPanEnd: (_) => widget.onInteractionEnd?.call(),
                        onDoubleTap: () => widget.onResetTray?.call(code),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  );
                }),

              // 3b. Header Pill Tap Targets to Select and Move ENTIRE Tray Group
              if (widget.isInteractive && widget.roi.isEnabled)
                ...widget.slotCodes.map((code) {
                  final trayBox = resolvedTrayBoxesPx[code];
                  if (trayBox == null) return const SizedBox.shrink();
                  final isTraySelected = selectedCode == code;
                  final tagWidth = math.min(75.0, trayBox.width * 0.7);

                  return Positioned(
                    left: trayBox.center.dx - (tagWidth / 2),
                    top: trayBox.top,
                    width: tagWidth,
                    height: 22,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        widget.onSelectTray?.call(
                          isTraySelected ? null : code,
                        );
                      },
                      onPanStart: (_) {
                        if (!isTraySelected) {
                          widget.onSelectTray?.call(code);
                        }
                      },
                      onPanUpdate: (details) {
                        final deltaNormX = details.delta.dx / w;
                        final deltaNormY = details.delta.dy / h;
                        widget.onMoveTray?.call(
                          code,
                          Offset(deltaNormX, deltaNormY),
                        );
                      },
                      onPanEnd: (_) => widget.onInteractionEnd?.call(),
                      onDoubleTap: () => widget.onResetTray?.call(code),
                      child: Container(color: Colors.transparent),
                    ),
                  );
                }),

              // 4. Tray Info Badge at Top Left of ROI Box (or Top Left corner)
              Positioned(
                left: math.max(8.0, overallRect.left + 8),
                top: math.max(
                  8.0,
                  overallRect.top - 36 < 8
                      ? overallRect.top + 8
                      : overallRect.top - 36,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: widget.roi.isEnabled
                          ? AppColors.brandAccent
                          : AppColors.statusOrange,
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.roi.isEnabled
                            ? Icons.shelves
                            : Icons.wb_sunny_outlined,
                        size: 14,
                        color: widget.roi.isEnabled
                            ? AppColors.brandAccent
                            : AppColors.statusOrange,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.roi.isEnabled
                            ? (selectedCode != null
                                  ? (selectedCode.endsWith('1')
                                        ? '${widget.cameraName} • Slot $selectedCode (100ML) Selected — Drag handles to align'
                                        : (selectedCode.endsWith('2')
                                              ? '${widget.cameraName} • Slot $selectedCode (50ML) Selected — Drag handles to align'
                                              : '${widget.cameraName} • Tray $selectedCode (Both Sizes) Selected'))
                                  : '${widget.cameraName} • Tap any 100ML or 50ML slot to align independently')
                            : '${widget.cameraName} SCANNER PAUSED (SEASONAL)',
                        style: TextStyle(
                          color: widget.roi.isEnabled
                              ? Colors.white
                              : AppColors.statusOrange,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Interactive Touch Tray & Size Selector Bar
              if (widget.isInteractive && widget.roi.isEnabled)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.88),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Row 1: Primary Tray Selector Chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildTraySelectorChip(
                                label: 'All Trays',
                                isSelected: selectedCode == null,
                                icon: Icons.select_all_rounded,
                                onTap: () => widget.onSelectTray?.call(null),
                              ),
                              const SizedBox(width: 6),
                              ...widget.slotCodes.map((code) {
                                final isSel = selectedCode == code ||
                                    (selectedCode != null &&
                                        selectedCode.startsWith(code));
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: _buildTraySelectorChip(
                                    label: 'Tray $code',
                                    isSelected: isSel,
                                    onTap: () {
                                      final isCurrentlyThis = selectedCode == code;
                                      widget.onSelectTray?.call(
                                        isCurrentlyThis ? null : code,
                                      );
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),

                        // Row 2: Secondary Contextual Size Chips (Shown when a Tray or Slot is Selected)
                        if (selectedCode != null) ...[
                          const SizedBox(height: 6),
                          () {
                            final trayPrefix = selectedCode.length >= 2
                                ? selectedCode.substring(0, 2)
                                : selectedCode;
                            final isBoth = selectedCode == trayPrefix;
                            final is100 = selectedCode == '${trayPrefix}1';
                            final is50 = selectedCode == '${trayPrefix}2';

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Both Sizes
                                _buildSubChip(
                                  label: '$trayPrefix (Both)',
                                  isSelected: isBoth,
                                  onTap: () => widget.onSelectTray?.call(trayPrefix),
                                ),
                                const SizedBox(width: 4),
                                // 100ML Slot
                                _buildSubChip(
                                  label: '${trayPrefix}1 (100ML)',
                                  isSelected: is100,
                                  accentColor: const Color(0xFF10B981),
                                  onTap: () => widget.onSelectTray?.call('${trayPrefix}1'),
                                ),
                                const SizedBox(width: 4),
                                // 50ML Slot
                                _buildSubChip(
                                  label: '${trayPrefix}2 (50ML)',
                                  isSelected: is50,
                                  accentColor: const Color(0xFFEC4899),
                                  onTap: () => widget.onSelectTray?.call('${trayPrefix}2'),
                                ),
                                const SizedBox(width: 6),
                                // Reset button for active selection
                                InkWell(
                                  onTap: () => widget.onResetTray?.call(selectedCode),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusOrange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.statusOrange.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.restart_alt_rounded,
                                          size: 11,
                                          color: AppColors.statusOrange,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          'Reset $selectedCode',
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            color: AppColors.statusOrange,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }(),
                        ],
                      ],
                    ),
                  ),
                ),

              // 6. Interactive Touch Handles (Attached to the Selected Tray, or to All Trays if None Selected)
              if (widget.isInteractive && widget.roi.isEnabled) ...[
                () {
                  final activeRect = selectedRect ?? overallRect;
                  return Stack(
                    children: [
                      // Top-Left Corner
                      _buildCornerHandle(
                        center: activeRect.topLeft,
                        cursor: SystemMouseCursors.resizeUpLeft,
                        onPan: (dx, dy) {
                          final newX = (activeRect.left + dx) / w;
                          final newY = (activeRect.top + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayCorner != null) {
                            widget.onResizeTrayCorner!(
                              selectedCode,
                              true,
                              true,
                              newX,
                              newY,
                            );
                          } else {
                            widget.onResizeCorner?.call(true, true, newX, newY);
                          }
                        },
                      ),
                      // Top-Right Corner
                      _buildCornerHandle(
                        center: activeRect.topRight,
                        cursor: SystemMouseCursors.resizeUpRight,
                        onPan: (dx, dy) {
                          final newX = (activeRect.right + dx) / w;
                          final newY = (activeRect.top + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayCorner != null) {
                            widget.onResizeTrayCorner!(
                              selectedCode,
                              true,
                              false,
                              newX,
                              newY,
                            );
                          } else {
                            widget.onResizeCorner?.call(
                              true,
                              false,
                              newX,
                              newY,
                            );
                          }
                        },
                      ),
                      // Bottom-Left Corner
                      _buildCornerHandle(
                        center: activeRect.bottomLeft,
                        cursor: SystemMouseCursors.resizeDownLeft,
                        onPan: (dx, dy) {
                          final newX = (activeRect.left + dx) / w;
                          final newY = (activeRect.bottom + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayCorner != null) {
                            widget.onResizeTrayCorner!(
                              selectedCode,
                              false,
                              true,
                              newX,
                              newY,
                            );
                          } else {
                            widget.onResizeCorner?.call(
                              false,
                              true,
                              newX,
                              newY,
                            );
                          }
                        },
                      ),
                      // Bottom-Right Corner
                      _buildCornerHandle(
                        center: activeRect.bottomRight,
                        cursor: SystemMouseCursors.resizeDownRight,
                        onPan: (dx, dy) {
                          final newX = (activeRect.right + dx) / w;
                          final newY = (activeRect.bottom + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayCorner != null) {
                            widget.onResizeTrayCorner!(
                              selectedCode,
                              false,
                              false,
                              newX,
                              newY,
                            );
                          } else {
                            widget.onResizeCorner?.call(
                              false,
                              false,
                              newX,
                              newY,
                            );
                          }
                        },
                      ),
                      // Top Edge
                      _buildEdgeHandle(
                        rect: Rect.fromLTWH(
                          activeRect.left + _handleTouchSize,
                          activeRect.top - _edgeTouchThickness / 2,
                          math.max(
                            10.0,
                            activeRect.width - (_handleTouchSize * 2),
                          ),
                          _edgeTouchThickness,
                        ),
                        cursor: SystemMouseCursors.resizeUpDown,
                        onPan: (_, dy) {
                          final newY = (activeRect.top + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayEdge != null) {
                            widget.onResizeTrayEdge!(
                              selectedCode,
                              RoiHandleType.topEdge,
                              newY,
                            );
                          } else {
                            widget.onResizeEdge?.call(
                              RoiHandleType.topEdge,
                              newY,
                            );
                          }
                        },
                      ),
                      // Bottom Edge
                      _buildEdgeHandle(
                        rect: Rect.fromLTWH(
                          activeRect.left + _handleTouchSize,
                          activeRect.bottom - _edgeTouchThickness / 2,
                          math.max(
                            10.0,
                            activeRect.width - (_handleTouchSize * 2),
                          ),
                          _edgeTouchThickness,
                        ),
                        cursor: SystemMouseCursors.resizeUpDown,
                        onPan: (_, dy) {
                          final newY = (activeRect.bottom + dy) / h;
                          if (selectedCode != null &&
                              widget.onResizeTrayEdge != null) {
                            widget.onResizeTrayEdge!(
                              selectedCode,
                              RoiHandleType.bottomEdge,
                              newY,
                            );
                          } else {
                            widget.onResizeEdge?.call(
                              RoiHandleType.bottomEdge,
                              newY,
                            );
                          }
                        },
                      ),
                      // Left Edge
                      _buildEdgeHandle(
                        rect: Rect.fromLTWH(
                          activeRect.left - _edgeTouchThickness / 2,
                          activeRect.top + _handleTouchSize,
                          _edgeTouchThickness,
                          math.max(
                            10.0,
                            activeRect.height - (_handleTouchSize * 2),
                          ),
                        ),
                        cursor: SystemMouseCursors.resizeLeftRight,
                        onPan: (dx, _) {
                          final newX = (activeRect.left + dx) / w;
                          if (selectedCode != null &&
                              widget.onResizeTrayEdge != null) {
                            widget.onResizeTrayEdge!(
                              selectedCode,
                              RoiHandleType.leftEdge,
                              newX,
                            );
                          } else {
                            widget.onResizeEdge?.call(
                              RoiHandleType.leftEdge,
                              newX,
                            );
                          }
                        },
                      ),
                      // Right Edge
                      _buildEdgeHandle(
                        rect: Rect.fromLTWH(
                          activeRect.right - _edgeTouchThickness / 2,
                          activeRect.top + _handleTouchSize,
                          _edgeTouchThickness,
                          math.max(
                            10.0,
                            activeRect.height - (_handleTouchSize * 2),
                          ),
                        ),
                        cursor: SystemMouseCursors.resizeLeftRight,
                        onPan: (dx, _) {
                          final newX = (activeRect.right + dx) / w;
                          if (selectedCode != null &&
                              widget.onResizeTrayEdge != null) {
                            widget.onResizeTrayEdge!(
                              selectedCode,
                              RoiHandleType.rightEdge,
                              newX,
                            );
                          } else {
                            widget.onResizeEdge?.call(
                              RoiHandleType.rightEdge,
                              newX,
                            );
                          }
                        },
                      ),
                    ],
                  );
                }(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildTraySelectorChip({
    required String label,
    required bool isSelected,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandAccent
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandAccent.withValues(alpha: 0.5),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: isSelected ? Colors.black : Colors.white,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubChip({
    required String label,
    required bool isSelected,
    Color? accentColor,
    required VoidCallback onTap,
  }) {
    final effectiveColor = accentColor ?? AppColors.brandAccent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? effectiveColor
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : effectiveColor.withValues(alpha: 0.4),
            width: isSelected ? 1.4 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: effectiveColor.withValues(alpha: 0.4),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
            color: isSelected ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildCornerHandle({
    required Offset center,
    required MouseCursor cursor,
    required void Function(double dx, double dy) onPan,
  }) {
    return Positioned(
      left: center.dx - (_handleTouchSize / 2),
      top: center.dy - (_handleTouchSize / 2),
      width: _handleTouchSize,
      height: _handleTouchSize,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onPan(details.delta.dx, details.delta.dy),
          onPanEnd: (_) => widget.onInteractionEnd?.call(),
          child: Center(
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: widget.roi.isEnabled
                    ? AppColors.brandAccent
                    : AppColors.statusOrange,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeHandle({
    required Rect rect,
    required MouseCursor cursor,
    required void Function(double dx, double dy) onPan,
  }) {
    if (rect.width <= 0 || rect.height <= 0) return const SizedBox.shrink();
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: MouseRegion(
        cursor: cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => onPan(details.delta.dx, details.delta.dy),
          onPanEnd: (_) => widget.onInteractionEnd?.call(),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
}

class _TrayRoiPainter extends CustomPainter {
  final Map<String, Rect> resolvedSlotBoxes;
  final Map<String, Rect> resolvedTrayBoxes;
  final Rect overallRect;
  final String? selectedCode;
  final bool isInteractive;
  final bool isEnabled;
  final Set<String> disabledCapCodes;
  final List<String> slotCodes;

  _TrayRoiPainter({
    required this.resolvedSlotBoxes,
    required this.resolvedTrayBoxes,
    required this.overallRect,
    required this.selectedCode,
    required this.isInteractive,
    required this.isEnabled,
    required this.disabledCapCodes,
    required this.slotCodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (resolvedSlotBoxes.isEmpty &&
        (overallRect.width <= 0 || overallRect.height <= 0)) {
      return;
    }

    final fullRect = Offset.zero & size;

    // 1. Dim background outside the detached slot boxes
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: isInteractive ? 0.60 : 0.25)
      ..style = PaintingStyle.fill;

    final path = Path()..addRect(fullRect);
    for (final box in resolvedSlotBoxes.values) {
      if (box.width > 0 && box.height > 0) {
        path.addRRect(RRect.fromRectAndRadius(box, const Radius.circular(8)));
      }
    }
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, darkPaint);

    // If whole ROI is disabled:
    if (!isEnabled) {
      final disabledBgPaint = Paint()
        ..color = const Color(0xFF1F1A14).withValues(alpha: 0.70)
        ..style = PaintingStyle.fill;
      final disabledBorderPaint = Paint()
        ..color = AppColors.statusOrange.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      for (final box in resolvedSlotBoxes.values) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(8)),
          disabledBgPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(8)),
          disabledBorderPaint,
        );
      }

      final textPainter = TextPainter(
        text: const TextSpan(
          children: [
            TextSpan(
              text: '🔒 SHELF DETECTION ZONE PAUSED\n',
              style: TextStyle(
                color: AppColors.statusOrange,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
            TextSpan(
              text: 'Seasonal rotation paused • Tap "Resume Shelf Zone" to start scanning',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 3)],
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          overallRect.center.dx - (textPainter.width / 2),
          overallRect.center.dy - (textPainter.height / 2),
        ),
      );
      return;
    }

    // 2. Detached Individual Size Slot Boxes
    final emeraldBgPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    final roseBgPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.16)
      ..style = PaintingStyle.fill;

    final offBgPaint = Paint()
      ..color = const Color(0xFF1C1308).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final code in slotCodes) {
      final slotPrefix = code.toUpperCase();
      final leftCode = '${slotPrefix}1';
      final rightCode = '${slotPrefix}2';

      final box100 = resolvedSlotBoxes[leftCode];
      final box50 = resolvedSlotBoxes[rightCode];
      if (box100 == null || box50 == null || box100.width <= 0 || box50.width <= 0) {
        continue;
      }

      final is100Selected = selectedCode == leftCode;
      final is50Selected = selectedCode == rightCode;
      final isTraySelected = selectedCode == code;

      // Check if slot or variant is disabled in disabledCapCodes
      final isLeftOff = disabledCapCodes.any((c) {
        final upper = c.trim().toUpperCase();
        return upper == leftCode || upper == slotPrefix;
      });

      final isRightOff = disabledCapCodes.any((c) {
        final upper = c.trim().toUpperCase();
        return upper == rightCode || upper == slotPrefix;
      });

      // A. Draw 100ML Box (Fully Detached)
      canvas.drawRRect(
        RRect.fromRectAndRadius(box100, const Radius.circular(8)),
        isLeftOff ? offBgPaint : emeraldBgPaint,
      );

      if (is100Selected && isInteractive) {
        final glowPaint = Paint()
          ..color = AppColors.brandAccent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box100, const Radius.circular(8)),
          glowPaint,
        );

        final selectedBorderPaint = Paint()
          ..color = AppColors.brandAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box100, const Radius.circular(8)),
          selectedBorderPaint,
        );
      } else {
        final normalBorderPaint = Paint()
          ..color = (isTraySelected ? AppColors.brandAccent : Colors.white)
              .withValues(alpha: isTraySelected ? 0.85 : 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isTraySelected ? 2.0 : 1.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box100, const Radius.circular(8)),
          normalBorderPaint,
        );
      }

      // 100ML Text
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '$leftCode\n',
            style: TextStyle(
              color: isLeftOff ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              decoration: isLeftOff ? TextDecoration.lineThrough : null,
              height: 1.1,
              shadows: const [
                Shadow(
                  color: Colors.black,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          TextSpan(
            text: isLeftOff ? 'OFF' : '100ML',
            style: TextStyle(
              color: isLeftOff ? const Color(0xFFF59E0B) : const Color(0xFF6EE7B7),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ],
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          box100.center.dx - (textPainter.width / 2),
          box100.center.dy - (textPainter.height / 2),
        ),
      );

      // B. Draw 50ML Box (Fully Detached)
      canvas.drawRRect(
        RRect.fromRectAndRadius(box50, const Radius.circular(8)),
        isRightOff ? offBgPaint : roseBgPaint,
      );

      if (is50Selected && isInteractive) {
        final glowPaint = Paint()
          ..color = AppColors.brandAccent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box50, const Radius.circular(8)),
          glowPaint,
        );

        final selectedBorderPaint = Paint()
          ..color = AppColors.brandAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box50, const Radius.circular(8)),
          selectedBorderPaint,
        );
      } else {
        final normalBorderPaint = Paint()
          ..color = (isTraySelected ? AppColors.brandAccent : Colors.white)
              .withValues(alpha: isTraySelected ? 0.85 : 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = isTraySelected ? 2.0 : 1.5;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box50, const Radius.circular(8)),
          normalBorderPaint,
        );
      }

      // 50ML Text
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '$rightCode\n',
            style: TextStyle(
              color: isRightOff ? const Color(0xFFF59E0B) : const Color(0xFFEC4899),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              decoration: isRightOff ? TextDecoration.lineThrough : null,
              height: 1.1,
              shadows: const [
                Shadow(
                  color: Colors.black,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
          TextSpan(
            text: isRightOff ? 'OFF' : '50ML',
            style: TextStyle(
              color: isRightOff ? const Color(0xFFF59E0B) : const Color(0xFFF472B6),
              fontSize: 9,
              fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ],
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          box50.center.dx - (textPainter.width / 2),
          box50.center.dy - (textPainter.height / 2),
        ),
      );

      // C. Header Pill Tag (at top center of tray)
      final pillCenterX = (box100.left + box50.right) / 2;
      final pillCenterY = math.min(box100.top, box50.top) + 8;
      final tagWidth = math.min(65.0, (box50.right - box100.left) * 0.7);
      final tagRect = Rect.fromCenter(
        center: Offset(pillCenterX, pillCenterY),
        width: tagWidth,
        height: 16,
      );
      final tagBgPaint = Paint()
        ..color = isTraySelected
            ? AppColors.brandAccent
            : Colors.black.withValues(alpha: 0.75)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(8)),
        tagBgPaint,
      );

      textPainter.text = TextSpan(
        text: 'TRAY $code',
        style: TextStyle(
          color: isTraySelected ? Colors.black : Colors.white,
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          pillCenterX - (textPainter.width / 2),
          tagRect.center.dy - (textPainter.height / 2),
        ),
      );
    }

    // 3. Corner L-Shapes for Selected Target (or overallRect if none selected)
    if (isInteractive && isEnabled) {
      final activeTarget = (selectedCode != null
              ? (resolvedSlotBoxes[selectedCode!] ??
                  resolvedTrayBoxes[selectedCode!])
              : null) ??
          overallRect;

      if (activeTarget.width > 0 && activeTarget.height > 0) {
        final cornerPaint = Paint()
          ..color = AppColors.brandAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.square;

        const cornerLen = 14.0;

        // Top-Left
        canvas.drawLine(
          activeTarget.topLeft,
          Offset(activeTarget.left + cornerLen, activeTarget.top),
          cornerPaint,
        );
        canvas.drawLine(
          activeTarget.topLeft,
          Offset(activeTarget.left, activeTarget.top + cornerLen),
          cornerPaint,
        );

        // Top-Right
        canvas.drawLine(
          activeTarget.topRight,
          Offset(activeTarget.right - cornerLen, activeTarget.top),
          cornerPaint,
        );
        canvas.drawLine(
          activeTarget.topRight,
          Offset(activeTarget.right, activeTarget.top + cornerLen),
          cornerPaint,
        );

        // Bottom-Left
        canvas.drawLine(
          activeTarget.bottomLeft,
          Offset(activeTarget.left + cornerLen, activeTarget.bottom),
          cornerPaint,
        );
        canvas.drawLine(
          activeTarget.bottomLeft,
          Offset(activeTarget.left, activeTarget.bottom - cornerLen),
          cornerPaint,
        );

        // Bottom-Right
        canvas.drawLine(
          activeTarget.bottomRight,
          Offset(activeTarget.right - cornerLen, activeTarget.bottom),
          cornerPaint,
        );
        canvas.drawLine(
          activeTarget.bottomRight,
          Offset(activeTarget.right, activeTarget.bottom - cornerLen),
          cornerPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrayRoiPainter old) {
    return old.resolvedSlotBoxes != resolvedSlotBoxes ||
        old.resolvedTrayBoxes != resolvedTrayBoxes ||
        old.overallRect != overallRect ||
        old.selectedCode != selectedCode ||
        old.isInteractive != isInteractive ||
        old.isEnabled != isEnabled ||
        old.disabledCapCodes != disabledCapCodes ||
        old.slotCodes != slotCodes;
  }
}
