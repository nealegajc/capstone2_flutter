import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/models/shelf_region_model.dart';
import '../data/services/sqlite_service.dart';
import 'kiosk_providers.dart';

enum RoiHandleType {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  topEdge,
  bottomEdge,
  leftEdge,
  rightEdge,
  centerBody,
}

class RoiState {
  final int cameraId;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final bool isEditing;

  const RoiState({
    required this.cameraId,
    this.left = 0.05,
    this.top = 0.15,
    this.right = 0.95,
    this.bottom = 0.85,
    this.isEditing = false,
  });

  double get width => (right - left).clamp(0.01, 1.0);
  double get height => (bottom - top).clamp(0.01, 1.0);
  Rect get normalizedRect => Rect.fromLTRB(left, top, right, bottom);

  // Left half for 100ML bottles
  Rect get normalized100mlRect => Rect.fromLTRB(left, top, left + (width / 2), bottom);

  // Right half for 50ML bottles
  Rect get normalized50mlRect => Rect.fromLTRB(left + (width / 2), top, right, bottom);

  RoiState copyWith({
    int? cameraId,
    double? left,
    double? top,
    double? right,
    double? bottom,
    bool? isEditing,
  }) {
    return RoiState(
      cameraId: cameraId ?? this.cameraId,
      left: (left ?? this.left).clamp(0.0, 0.99),
      top: (top ?? this.top).clamp(0.0, 0.99),
      right: (right ?? this.right).clamp(0.01, 1.0),
      bottom: (bottom ?? this.bottom).clamp(0.01, 1.0),
      isEditing: isEditing ?? this.isEditing,
    );
  }

  factory RoiState.fromShelfRegion(ShelfRegionModel region) {
    return RoiState(
      cameraId: region.cameraId,
      left: region.left.clamp(0.0, 0.95),
      top: region.top.clamp(0.0, 0.95),
      right: region.right.clamp(0.05, 1.0),
      bottom: region.bottom.clamp(0.05, 1.0),
    );
  }
}

class RoiNotifier extends StateNotifier<RoiState> {
  final SqliteService _sqlite;
  final Ref _ref;
  final int cameraId;

  RoiNotifier(this._sqlite, this._ref, this.cameraId) : super(RoiState(cameraId: cameraId)) {
    _loadFromDatabase();
  }

  Future<void> _loadFromDatabase() async {
    try {
      final regions = await _sqlite.getShelfRegions('San Pablo');
      final match = regions.where((r) => r.cameraId == cameraId).firstOrNull;
      if (match != null) {
        state = RoiState.fromShelfRegion(match);
      }
    } catch (e) {
      debugPrint('[RoiNotifier] Error loading ROI: $e');
    }
  }

  void setEditing(bool editing) {
    state = state.copyWith(isEditing: editing);
  }

  void toggleEditing() {
    state = state.copyWith(isEditing: !state.isEditing);
  }

  void move(double deltaNormX, double deltaNormY) {
    final w = state.width;
    final h = state.height;

    var newLeft = state.left + deltaNormX;
    var newTop = state.top + deltaNormY;

    if (newLeft < 0.0) newLeft = 0.0;
    if (newTop < 0.0) newTop = 0.0;
    if (newLeft + w > 1.0) newLeft = 1.0 - w;
    if (newTop + h > 1.0) newTop = 1.0 - h;

    state = state.copyWith(
      left: newLeft,
      top: newTop,
      right: newLeft + w,
      bottom: newTop + h,
    );
  }

  void resizeCorner({
    required bool isTop,
    required bool isLeft,
    required double newNormX,
    required double newNormY,
    double minSize = 0.05,
  }) {
    double l = state.left;
    double t = state.top;
    double r = state.right;
    double b = state.bottom;

    if (isLeft) {
      l = newNormX.clamp(0.0, r - minSize);
    } else {
      r = newNormX.clamp(l + minSize, 1.0);
    }

    if (isTop) {
      t = newNormY.clamp(0.0, b - minSize);
    } else {
      b = newNormY.clamp(t + minSize, 1.0);
    }

    state = state.copyWith(left: l, top: t, right: r, bottom: b);
  }

  void resizeEdge({
    required RoiHandleType edge,
    required double newNormValue,
    double minSize = 0.05,
  }) {
    double l = state.left;
    double t = state.top;
    double r = state.right;
    double b = state.bottom;

    switch (edge) {
      case RoiHandleType.topEdge:
        t = newNormValue.clamp(0.0, b - minSize);
        break;
      case RoiHandleType.bottomEdge:
        b = newNormValue.clamp(t + minSize, 1.0);
        break;
      case RoiHandleType.leftEdge:
        l = newNormValue.clamp(0.0, r - minSize);
        break;
      case RoiHandleType.rightEdge:
        r = newNormValue.clamp(l + minSize, 1.0);
        break;
      default:
        return;
    }

    state = state.copyWith(left: l, top: t, right: r, bottom: b);
  }

  void scale(double scaleFactor, {Offset? focalPointNorm}) {
    final focal = focalPointNorm ?? Offset((state.left + state.right) / 2, (state.top + state.bottom) / 2);
    final curW = state.width;
    final curH = state.height;

    final newW = (curW * scaleFactor).clamp(0.08, 1.0);
    final newH = (curH * scaleFactor).clamp(0.08, 1.0);

    final ratioX = (focal.dx - state.left) / curW;
    final ratioY = (focal.dy - state.top) / curH;

    var newLeft = focal.dx - newW * ratioX;
    var newTop = focal.dy - newH * ratioY;
    var newRight = newLeft + newW;
    var newBottom = newTop + newH;

    if (newLeft < 0.0) {
      newRight += (0.0 - newLeft);
      newLeft = 0.0;
    }
    if (newTop < 0.0) {
      newBottom += (0.0 - newTop);
      newTop = 0.0;
    }
    if (newRight > 1.0) {
      newLeft -= (newRight - 1.0);
      newRight = 1.0;
    }
    if (newBottom > 1.0) {
      newTop -= (newBottom - 1.0);
      newBottom = 1.0;
    }

    state = state.copyWith(
      left: newLeft.clamp(0.0, 0.92),
      top: newTop.clamp(0.0, 0.92),
      right: newRight.clamp(0.08, 1.0),
      bottom: newBottom.clamp(0.08, 1.0),
    );
  }

  void reset() {
    state = state.copyWith(
      left: 0.05,
      top: 0.15,
      right: 0.95,
      bottom: 0.85,
    );
    save('San Pablo');
  }

  Future<void> save(String branch) async {
    try {
      final regions = await _sqlite.getShelfRegions(branch);
      final match = regions.where((r) => r.cameraId == cameraId).firstOrNull;
      if (match != null) {
        final updated = match.copyWith(
          left: state.left,
          top: state.top,
          right: state.right,
          bottom: state.bottom,
        );
        await _sqlite.updateShelfRegion(updated);
      } else {
        final newRegion = ShelfRegionModel(
          id: 'roi_${branch}_cam_$cameraId',
          code: 'Camera $cameraId',
          assignedProductId: '',
          assignedProductName: 'Camera $cameraId Region',
          branch: branch,
          cameraId: cameraId,
          left: state.left,
          top: state.top,
          right: state.right,
          bottom: state.bottom,
        );
        await _sqlite.updateShelfRegion(newRegion);
      }
      _ref.invalidate(shelfRegionsProvider(branch));
    } catch (e) {
      debugPrint('[RoiNotifier] Error saving ROI: $e');
    }
  }
}

final cameraRoiProvider = StateNotifierProvider.family<RoiNotifier, RoiState, int>((ref, cameraId) {
  final sqlite = SqliteService.instance;
  return RoiNotifier(sqlite, ref, cameraId);
});
