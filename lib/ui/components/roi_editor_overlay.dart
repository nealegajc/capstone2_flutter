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

        // 1. Resolve normalized 5 detached Tray boxes (one per physical tray: AA, AB, AC, AD, AE)
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

        // 2. Compute overall envelope rect
        final overallRect = Rect.fromLTRB(
          widget.roi.left * w,
          widget.roi.top * h,
          widget.roi.right * w,
          widget.roi.bottom * h,
        );

        final selectedCode = widget.roi.selectedTrayCode;
        final selectedRect = selectedCode != null
            ? resolvedTrayBoxesPx[selectedCode]
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
              // 1. Shaded backdrop + 5 Detached Physical Tray Boxes Painter
              CustomPaint(
                size: Size(w, h),
                painter: _TrayRoiPainter(
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

              // 3. Move Body for EACH of the 5 Detached Physical Trays
              if (widget.isInteractive && widget.roi.isEnabled)
                ...widget.slotCodes.map((code) {
                  final box = resolvedTrayBoxesPx[code];
                  if (box == null || box.width <= 0 || box.height <= 0) {
                    return const SizedBox.shrink();
                  }
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

              // 4. Interactive Touch Handles (Attached to the Selected Tray, or to All Trays if None Selected)
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
  final Map<String, Rect> resolvedTrayBoxes;
  final Rect overallRect;
  final String? selectedCode;
  final bool isInteractive;
  final bool isEnabled;
  final Set<String> disabledCapCodes;
  final List<String> slotCodes;

  _TrayRoiPainter({
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
    if (resolvedTrayBoxes.isEmpty &&
        (overallRect.width <= 0 || overallRect.height <= 0)) {
      return;
    }

    final fullRect = Offset.zero & size;

    // 1. Dim background outside the detached tray boxes
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: isInteractive ? 0.60 : 0.25)
      ..style = PaintingStyle.fill;

    final path = Path()..addRect(fullRect);
    for (final box in resolvedTrayBoxes.values) {
      if (box.width > 0 && box.height > 0) {
        path.addRRect(RRect.fromRectAndRadius(box, const Radius.circular(10)));
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

      for (final box in resolvedTrayBoxes.values) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          disabledBgPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
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

    // 2. 5 Detached Physical Tray Boxes (one per acrylic tray: AA, AB, AC, AD, AE)
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final code in slotCodes) {
      final box = resolvedTrayBoxes[code];
      if (box == null || box.width <= 0 || box.height <= 0) continue;

      final isTraySelected = selectedCode == code;

      // Check if slot or variant is disabled in disabledCapCodes
      final isOff = disabledCapCodes.any((c) {
        final upper = c.trim().toUpperCase();
        return upper == code.toUpperCase();
      });

      // Background fill
      final fillPaint = Paint()
        ..color = isOff
            ? const Color(0xFF1C1308).withValues(alpha: 0.85)
            : (isTraySelected
                ? AppColors.brandAccent.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06))
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(10)),
        fillPaint,
      );

      // Border outline
      if (isTraySelected && isInteractive) {
        final glowPaint = Paint()
          ..color = AppColors.brandAccent.withValues(alpha: 0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          glowPaint,
        );

        final selectedBorderPaint = Paint()
          ..color = AppColors.brandAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          selectedBorderPaint,
        );
      } else {
        final normalBorderPaint = Paint()
          ..color = (isOff ? AppColors.statusOrange : Colors.white)
              .withValues(alpha: 0.70)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8;
        canvas.drawRRect(
          RRect.fromRectAndRadius(box, const Radius.circular(10)),
          normalBorderPaint,
        );
      }

      // Tray Header Pill (drawn outside/at top of tray)
      final pillCenterX = box.center.dx;
      final pillCenterY = math.max(10.0, box.top + 10);
      final tagWidth = math.min(80.0, box.width * 0.85);
      final tagRect = Rect.fromCenter(
        center: Offset(pillCenterX, pillCenterY),
        width: tagWidth,
        height: 18,
      );

      final tagBgPaint = Paint()
        ..color = isTraySelected
            ? AppColors.brandAccent
            : Colors.black.withValues(alpha: 0.85)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(9)),
        tagBgPaint,
      );

      textPainter.text = TextSpan(
        text: 'TRAY $code',
        style: TextStyle(
          color: isTraySelected ? Colors.black : Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
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

      // Center Scent Watermark / Label
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '$code\n',
            style: TextStyle(
              color: isOff
                  ? const Color(0xFFF59E0B)
                  : (isTraySelected
                      ? AppColors.brandAccent
                      : Colors.white.withValues(alpha: 0.85)),
              fontSize: 16,
              fontWeight: FontWeight.w900,
              decoration: isOff ? TextDecoration.lineThrough : null,
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
            text: isOff ? 'PAUSED' : 'ALL SIZES',
            style: TextStyle(
              color: isOff
                  ? const Color(0xFFF59E0B)
                  : (isTraySelected
                      ? AppColors.brandAccent.withValues(alpha: 0.8)
                      : Colors.white54),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
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
          box.center.dx - (textPainter.width / 2),
          box.center.dy - (textPainter.height / 2),
        ),
      );
    }

    // 3. Corner L-Shapes for Selected Tray Target (or overallRect if none selected)
    if (isInteractive && isEnabled) {
      final activeTarget = (selectedCode != null
              ? resolvedTrayBoxes[selectedCode!]
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
    return old.resolvedTrayBoxes != resolvedTrayBoxes ||
        old.overallRect != overallRect ||
        old.selectedCode != selectedCode ||
        old.isInteractive != isInteractive ||
        old.isEnabled != isEnabled ||
        old.disabledCapCodes != disabledCapCodes ||
        old.slotCodes != slotCodes;
  }
}

/// Standalone Tray Selector Bar for placement outside the camera video feed.
class TraySelectorBar extends StatelessWidget {
  final List<String> slotCodes;
  final String? selectedCode;
  final ValueChanged<String?> onSelectTray;
  final ValueChanged<String>? onResetTray;

  const TraySelectorBar({
    super.key,
    required this.slotCodes,
    required this.selectedCode,
    required this.onSelectTray,
    this.onResetTray,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildChip(
            label: 'All Trays',
            isSelected: selectedCode == null,
            icon: Icons.select_all_rounded,
            onTap: () => onSelectTray(null),
          ),
          const SizedBox(width: 8),
          ...slotCodes.map((code) {
            final isSel = selectedCode == code;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildChip(
                label: 'Tray $code',
                isSelected: isSel,
                onTap: () {
                  final isCurrentlyThis = selectedCode == code;
                  onSelectTray(isCurrentlyThis ? null : code);
                },
              ),
            );
          }),
          if (selectedCode != null && onResetTray != null) ...[
            Container(
              height: 20,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
            ),
            InkWell(
              onTap: () => onResetTray!(selectedCode!),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
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
                      size: 14,
                      color: AppColors.statusOrange,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Reset Tray $selectedCode',
                      style: const TextStyle(
                        fontSize: 11,
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
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.brandAccent
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.brandAccent.withValues(alpha: 0.45),
                    blurRadius: 6,
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
}

