import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/roi_provider.dart';

class RoiEditorOverlay extends StatefulWidget {
  final RoiState roi;
  final ValueChanged<Offset>? onMove;
  final void Function(bool isTop, bool isLeft, double newNormX, double newNormY)? onResizeCorner;
  final void Function(RoiHandleType edge, double newNormValue)? onResizeEdge;
  final void Function(double scaleFactor, Offset focalPointNorm)? onScale;
  final VoidCallback? onReset;
  final VoidCallback? onInteractionEnd;
  final bool isInteractive;
  final String cameraName;
  final List<String> slotCodes; // e.g. ['A', 'B', 'C', 'D', 'E']

  const RoiEditorOverlay({
    super.key,
    required this.roi,
    this.onMove,
    this.onResizeCorner,
    this.onResizeEdge,
    this.onScale,
    this.onReset,
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
  static const double _handleTouchSize = 44.0;
  static const double _edgeTouchThickness = 28.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        final roiRect = Rect.fromLTRB(
          widget.roi.left * w,
          widget.roi.top * h,
          widget.roi.right * w,
          widget.roi.bottom * h,
        );

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
              // 1. Shaded backdrop + Grid / Left (100ML) & Right (50ML) Tray Painter
              CustomPaint(
                size: Size(w, h),
                painter: _TrayRoiPainter(
                  roiRect: roiRect,
                  isInteractive: widget.isInteractive,
                  slotCodes: widget.slotCodes,
                ),
              ),

              // 2. Background Multi-touch Pinch Detector for Touchscreen
              if (widget.isInteractive)
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

              // 3. Move Body (Inside the ROI Box)
              if (widget.isInteractive)
                Positioned(
                  left: math.max(0.0, roiRect.left + 16),
                  top: math.max(0.0, roiRect.top + 16),
                  width: math.max(10.0, roiRect.width - 32),
                  height: math.max(10.0, roiRect.height - 32),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: widget.onReset,
                      onPanUpdate: (details) {
                        final deltaNormX = details.delta.dx / w;
                        final deltaNormY = details.delta.dy / h;
                        widget.onMove?.call(Offset(deltaNormX, deltaNormY));
                      },
                      onPanEnd: (_) => widget.onInteractionEnd?.call(),
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                ),

              // 4. Tray Info Badge at Top Left of ROI Box
              Positioned(
                left: math.max(8.0, roiRect.left + 8),
                top: math.max(8.0, roiRect.top - 34 < 8 ? roiRect.top + 8 : roiRect.top - 34),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.90),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.brandAccent, width: 1.5),
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
                      const Icon(Icons.shelves, size: 14, color: AppColors.brandAccent),
                      const SizedBox(width: 6),
                      Text(
                        '${widget.cameraName} Trays • Left: 100ML | Right: 50ML (${(widget.roi.width * 100).toStringAsFixed(0)}% × ${(widget.roi.height * 100).toStringAsFixed(0)}%)',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 5. Interactive Touch Handles (Corners & Edges)
              if (widget.isInteractive) ...[
                // Top-Left Corner
                _buildCornerHandle(
                  center: roiRect.topLeft,
                  cursor: SystemMouseCursors.resizeUpLeft,
                  onPan: (dx, dy) => widget.onResizeCorner?.call(true, true, (roiRect.left + dx) / w, (roiRect.top + dy) / h),
                ),
                // Top-Right Corner
                _buildCornerHandle(
                  center: roiRect.topRight,
                  cursor: SystemMouseCursors.resizeUpRight,
                  onPan: (dx, dy) => widget.onResizeCorner?.call(true, false, (roiRect.right + dx) / w, (roiRect.top + dy) / h),
                ),
                // Bottom-Left Corner
                _buildCornerHandle(
                  center: roiRect.bottomLeft,
                  cursor: SystemMouseCursors.resizeDownLeft,
                  onPan: (dx, dy) => widget.onResizeCorner?.call(false, true, (roiRect.left + dx) / w, (roiRect.bottom + dy) / h),
                ),
                // Bottom-Right Corner
                _buildCornerHandle(
                  center: roiRect.bottomRight,
                  cursor: SystemMouseCursors.resizeDownRight,
                  onPan: (dx, dy) => widget.onResizeCorner?.call(false, false, (roiRect.right + dx) / w, (roiRect.bottom + dy) / h),
                ),
                // Top Edge
                _buildEdgeHandle(
                  rect: Rect.fromLTWH(roiRect.left + _handleTouchSize, roiRect.top - _edgeTouchThickness / 2, roiRect.width - (_handleTouchSize * 2), _edgeTouchThickness),
                  cursor: SystemMouseCursors.resizeUpDown,
                  onPan: (_, dy) => widget.onResizeEdge?.call(RoiHandleType.topEdge, (roiRect.top + dy) / h),
                ),
                // Bottom Edge
                _buildEdgeHandle(
                  rect: Rect.fromLTWH(roiRect.left + _handleTouchSize, roiRect.bottom - _edgeTouchThickness / 2, roiRect.width - (_handleTouchSize * 2), _edgeTouchThickness),
                  cursor: SystemMouseCursors.resizeUpDown,
                  onPan: (_, dy) => widget.onResizeEdge?.call(RoiHandleType.bottomEdge, (roiRect.bottom + dy) / h),
                ),
                // Left Edge
                _buildEdgeHandle(
                  rect: Rect.fromLTWH(roiRect.left - _edgeTouchThickness / 2, roiRect.top + _handleTouchSize, _edgeTouchThickness, roiRect.height - (_handleTouchSize * 2)),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  onPan: (dx, _) => widget.onResizeEdge?.call(RoiHandleType.leftEdge, (roiRect.left + dx) / w),
                ),
                // Right Edge
                _buildEdgeHandle(
                  rect: Rect.fromLTWH(roiRect.right - _edgeTouchThickness / 2, roiRect.top + _handleTouchSize, _edgeTouchThickness, roiRect.height - (_handleTouchSize * 2)),
                  cursor: SystemMouseCursors.resizeLeftRight,
                  onPan: (dx, _) => widget.onResizeEdge?.call(RoiHandleType.rightEdge, (roiRect.right + dx) / w),
                ),
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
      left: center.dx - _handleTouchSize / 2,
      top: center.dy - _handleTouchSize / 2,
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
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.brandAccent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.6),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
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
  final Rect roiRect;
  final bool isInteractive;
  final List<String> slotCodes;

  _TrayRoiPainter({
    required this.roiRect,
    required this.isInteractive,
    required this.slotCodes,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (roiRect.width <= 0 || roiRect.height <= 0) return;

    final fullRect = Offset.zero & size;

    // 1. Dim background outside the ROI
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: isInteractive ? 0.60 : 0.25)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(fullRect)
      ..addRect(roiRect);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, darkPaint);

    // 2. Outer Tray ROI Border
    final borderPaint = Paint()
      ..color = AppColors.brandAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = isInteractive ? 2.5 : 1.8;
    canvas.drawRect(roiRect, borderPaint);

    // 3. Vertical Midline Divider (Splitting Left 100ML & Right 50ML)
    final midX = roiRect.left + (roiRect.width / 2);
    final midLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..strokeWidth = 2.0;
    canvas.drawLine(Offset(midX, roiRect.top), Offset(midX, roiRect.bottom), midLinePaint);

    // 4. Subtle Tint for Left (100ML: Emerald) & Right (50ML: Rose)
    final leftBgPaint = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(roiRect.left, roiRect.top, midX, roiRect.bottom), leftBgPaint);

    final rightBgPaint = Paint()
      ..color = const Color(0xFFEC4899).withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTRB(midX, roiRect.top, roiRect.right, roiRect.bottom), rightBgPaint);

    // 5. Horizontal Partition Lines for the 5 Slot Rows
    final slotCount = slotCodes.length;
    final slotHeight = roiRect.height / slotCount;
    final horizLinePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;

    for (int i = 1; i < slotCount; i++) {
      final y = roiRect.top + (slotHeight * i);
      canvas.drawLine(Offset(roiRect.left, y), Offset(roiRect.right, y), horizLinePaint);
    }

    // 6. Draw 100ML (Left Half) & 50ML (Right Half) Badges and Labels
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final leftCenterX = roiRect.left + (roiRect.width / 4);
    final rightCenterX = midX + (roiRect.width / 4);

    for (int i = 0; i < slotCount; i++) {
      final slotTop = roiRect.top + (slotHeight * i);
      final slotCenterY = slotTop + (slotHeight / 2);
      final letter = slotCodes[i];

      // Left Half: 100ML (Size 1) in Emerald Cyan (#10B981)
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '${letter}1\n',
            style: const TextStyle(
              color: Color(0xFF10B981), // Emerald Cyan
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.1,
              shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
          const TextSpan(
            text: '100ML',
            style: TextStyle(
              color: Color(0xFF6EE7B7),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ],
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(leftCenterX - (textPainter.width / 2), slotCenterY - (textPainter.height / 2)),
      );

      // Right Half: 50ML (Size 2) in Rose Pink (#EC4899)
      textPainter.text = TextSpan(
        children: [
          TextSpan(
            text: '${letter}2\n',
            style: const TextStyle(
              color: Color(0xFFEC4899), // Rose Pink
              fontSize: 14,
              fontWeight: FontWeight.w900,
              height: 1.1,
              shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1))],
            ),
          ),
          const TextSpan(
            text: '50ML',
            style: TextStyle(
              color: Color(0xFFF472B6),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black, blurRadius: 3)],
            ),
          ),
        ],
      );
      textPainter.textAlign = TextAlign.center;
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(rightCenterX - (textPainter.width / 2), slotCenterY - (textPainter.height / 2)),
      );
    }

    // 7. Corner L-Shapes when Interactive
    if (isInteractive) {
      final cornerPaint = Paint()
        ..color = AppColors.brandAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.square;

      const cornerLen = 16.0;

      // Top-Left
      canvas.drawLine(roiRect.topLeft, Offset(roiRect.left + cornerLen, roiRect.top), cornerPaint);
      canvas.drawLine(roiRect.topLeft, Offset(roiRect.left, roiRect.top + cornerLen), cornerPaint);

      // Top-Right
      canvas.drawLine(roiRect.topRight, Offset(roiRect.right - cornerLen, roiRect.top), cornerPaint);
      canvas.drawLine(roiRect.topRight, Offset(roiRect.right, roiRect.top + cornerLen), cornerPaint);

      // Bottom-Left
      canvas.drawLine(roiRect.bottomLeft, Offset(roiRect.left + cornerLen, roiRect.bottom), cornerPaint);
      canvas.drawLine(roiRect.bottomLeft, Offset(roiRect.left, roiRect.bottom - cornerLen), cornerPaint);

      // Bottom-Right
      canvas.drawLine(roiRect.bottomRight, Offset(roiRect.right - cornerLen, roiRect.bottom), cornerPaint);
      canvas.drawLine(roiRect.bottomRight, Offset(roiRect.right, roiRect.bottom - cornerLen), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrayRoiPainter old) {
    return old.roiRect != roiRect ||
        old.isInteractive != isInteractive ||
        old.slotCodes != slotCodes;
  }
}
