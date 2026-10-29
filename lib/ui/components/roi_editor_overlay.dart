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

        // 1. Resolve normalized boxes for each detached tray
        final resolvedBoxesNorm = widget.roi.getResolvedTrayBoxes(
          widget.slotCodes,
        );
        final Map<String, Rect> resolvedBoxesPx = {};
        resolvedBoxesNorm.forEach((code, normRect) {
          resolvedBoxesPx[code] = Rect.fromLTRB(
            normRect.left * w,
            normRect.top * h,
            normRect.right * w,
            normRect.bottom * h,
          );
        });

        // 2. Compute overall envelope rect
        final overallRect = Rect.fromLTRB(
          widget.roi.left * w,
          widget.roi.top * h,
          widget.roi.right * w,
          widget.roi.bottom * h,
        );

        final selectedCode = widget.roi.selectedTrayCode;
        final selectedRect = selectedCode != null
            ? resolvedBoxesPx[selectedCode]
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
              // 1. Shaded backdrop + Detached Tray Boxes Painter
              CustomPaint(
                size: Size(w, h),
                painter: _TrayRoiPainter(
                  resolvedBoxes: resolvedBoxesPx,
                  overallRect: overallRect,
                  selectedTrayCode: selectedCode,
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

              // 3. Move Body for EACH individual Detached Tray Box
              if (widget.isInteractive && widget.roi.isEnabled)
                ...resolvedBoxesPx.entries.map((entry) {
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
                          // Tapping a tray selects it for individual editing
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
                                  ? '${widget.cameraName} • Tray $selectedCode Selected (Resize handles active)'
                                  : '${widget.cameraName} • Tap any Tray to resize individually')
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

              // 5. Interactive Touch Tray Selector Bar (Quick Selection Chips on Touchscreen)
              if (widget.isInteractive && widget.roi.isEnabled)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "All Trays" chip
                          _buildTraySelectorChip(
                            label: 'All Trays',
                            isSelected: selectedCode == null,
                            icon: Icons.select_all_rounded,
                            onTap: () => widget.onSelectTray?.call(null),
                          ),
                          const SizedBox(width: 6),
                          // Individual tray chips (e.g. AA, AB, AC, AD, AE)
                          ...widget.slotCodes.map((code) {
                            final isSel = selectedCode == code;
                            return Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _buildTraySelectorChip(
                                label: 'Tray $code',
                                isSelected: isSel,
                                onTap: () => widget.onSelectTray?.call(
                                  isSel ? null : code,
                                ),
                              ),
                            );
                          }),
                          if (selectedCode != null) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () =>
                                  widget.onResetTray?.call(selectedCode),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.statusOrange.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.statusOrange.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.restart_alt_rounded,
                                      size: 12,
                                      color: AppColors.statusOrange,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reset $selectedCode',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.statusOrange,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
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
  final Map<String, Rect> resolvedBoxes;
  final Rect overallRect;
  final String? selectedTrayCode;
  final bool isInteractive;
  final bool isEnabled;
  final Set<String> disabledCapCodes;
  final List<String> slotCodes;

  _TrayRoiPainter({
    required this.resolvedBoxes,
    required this.overallRect,
    required this.selectedTrayCode,
    required this.isInteractive,
    required this.isEnabled,
    required this.disabledCapCodes,
    required this.slotCodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (resolvedBoxes.isEmpty &&
        (overallRect.width <= 0 || overallRect.height <= 0)) {
      return;
    }

    final fullRect = Offset.zero & size;

    // 1. Dim background outside the detached ROI boxes
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: isInteractive ? 0.60 : 0.25)
      ..style = PaintingStyle.fill;

    final path = Path()..addRect(fullRect);
    for (final box in resolvedBoxes.values) {
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

      for (final box in resolvedBoxes.values) {
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

    // 2. Detached Individual Tray Boxes
    final emeraldBgPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final roseBgPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    final offBgPaint = Paint()
      ..color = const Color(0xFF1C1308).withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;

    final internalSplitPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1.2;

    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final code in slotCodes) {
      final trayBox = resolvedBoxes[code];
      if (trayBox == null || trayBox.width <= 0 || trayBox.height <= 0) {
        continue;
      }

      final isSelected = selectedTrayCode == code;
      final trayMidX = trayBox.left + (trayBox.width / 2);
      final slotPrefix = code.toUpperCase();
      final leftCode = '${slotPrefix}1';
      final rightCode = '${slotPrefix}2';

      // Check if slot or variant is disabled in disabledCapCodes
      final isLeftOff = disabledCapCodes.any((c) {
        final upper = c.trim().toUpperCase();
        return upper == leftCode || upper == slotPrefix;
      });

      final isRightOff = disabledCapCodes.any((c) {
        final upper = c.trim().toUpperCase();
        return upper == rightCode || upper == slotPrefix;
      });

      final leftRect = Rect.fromLTRB(
        trayBox.left,
        trayBox.top,
        trayMidX,
        trayBox.bottom,
      );
      final rightRect = Rect.fromLTRB(
        trayMidX,
        trayBox.top,
        trayBox.right,
        trayBox.bottom,
      );

      // A. Left Half Background (100ML)
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          leftRect,
          topLeft: const Radius.circular(8),
          bottomLeft: const Radius.circular(8),
        ),
        isLeftOff ? offBgPaint : emeraldBgPaint,
      );

      // B. Right Half Background (50ML)
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rightRect,
          topRight: const Radius.circular(8),
          bottomRight: const Radius.circular(8),
        ),
        isRightOff ? offBgPaint : roseBgPaint,
      );

      // C. Internal Midline for this Tray (Splitting Left 100ML & Right 50ML)
      canvas.drawLine(
        Offset(trayMidX, trayBox.top),
        Offset(trayMidX, trayBox.bottom),
        internalSplitPaint,
      );

      // D. Draw Detached Outer Border for this specific Tray Box
      if (isSelected && isInteractive) {
        // Glowing halo for selected tray
        final glowPaint = Paint()
          ..color = AppColors.brandAccent.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(trayBox, const Radius.circular(8)),
          glowPaint,
        );

        final selectedBorderPaint = Paint()
          ..color = AppColors.brandAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(trayBox, const Radius.circular(8)),
          selectedBorderPaint,
        );
      } else {
        final normalBorderPaint = Paint()
          ..color = isInteractive
              ? AppColors.brandAccent.withValues(alpha: 0.70)
              : Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(trayBox, const Radius.circular(8)),
          normalBorderPaint,
        );
      }

      // E. Tray Code Header Pill Tag (at top of each individual box)
      final tagWidth = math.min(60.0, trayBox.width * 0.7);
      final tagRect = Rect.fromCenter(
        center: Offset(trayMidX, trayBox.top + 8),
        width: tagWidth,
        height: 16,
      );
      final tagBgPaint = Paint()
        ..color = isSelected
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
          color: isSelected ? Colors.black : Colors.white,
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
          trayMidX - (textPainter.width / 2),
          tagRect.center.dy - (textPainter.height / 2),
        ),
      );

      // F. Left Half Text: 100ML (${slotPrefix}1)
      final centerY = trayBox.top + (trayBox.height / 2) + 4;
      final left100CenterX = (trayBox.left + trayMidX) / 2;
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '$leftCode\n',
            style: TextStyle(
              color: isLeftOff
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF10B981),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              decoration: isLeftOff ? TextDecoration.lineThrough : null,
              decorationColor: const Color(0xFFF59E0B),
              decorationThickness: 2.5,
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
              color: isLeftOff
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFF6EE7B7),
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
          left100CenterX - (textPainter.width / 2),
          centerY - (textPainter.height / 2),
        ),
      );

      // G. Right Half Text: 50ML (${slotPrefix}2)
      final right50CenterX = (trayMidX + trayBox.right) / 2;
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '$rightCode\n',
            style: TextStyle(
              color: isRightOff
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEC4899),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              decoration: isRightOff ? TextDecoration.lineThrough : null,
              decorationColor: const Color(0xFFF59E0B),
              decorationThickness: 2.5,
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
              color: isRightOff
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFF472B6),
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
          right50CenterX - (textPainter.width / 2),
          centerY - (textPainter.height / 2),
        ),
      );
    }

    // 3. Corner L-Shapes for Selected Tray (or overallRect if none selected)
    if (isInteractive && isEnabled) {
      final activeTarget =
          (selectedTrayCode != null
              ? resolvedBoxes[selectedTrayCode!]
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
    return old.resolvedBoxes != resolvedBoxes ||
        old.overallRect != overallRect ||
        old.selectedTrayCode != selectedTrayCode ||
        old.isInteractive != isInteractive ||
        old.isEnabled != isEnabled ||
        old.disabledCapCodes != disabledCapCodes ||
        old.slotCodes != slotCodes;
  }
}
