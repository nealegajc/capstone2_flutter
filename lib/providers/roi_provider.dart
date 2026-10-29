import 'dart:convert';
import 'dart:math' as math;
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
  final Map<String, Rect> trayBoxes; // code -> normalized Rect
  final String? selectedTrayCode; // null means "All Trays", or 'AA', 'AB', etc.
  final bool isEditing;
  final bool isEnabled;
  final Set<String> disabledCapCodes;

  const RoiState({
    required this.cameraId,
    this.left = 0.05,
    this.top = 0.15,
    this.right = 0.95,
    this.bottom = 0.85,
    this.trayBoxes = const {},
    this.selectedTrayCode,
    this.isEditing = false,
    this.isEnabled = true,
    this.disabledCapCodes = const {},
  });

  double get width => (right - left).clamp(0.01, 1.0);
  double get height => (bottom - top).clamp(0.01, 1.0);
  Rect get normalizedRect => Rect.fromLTRB(left, top, right, bottom);

  /// Resolves the 5 detached Tray ROIs (one per physical tray: AA, AB, AC, AD, AE).
  Map<String, Rect> getResolvedTrayBoxes(List<String> slotCodes) {
    final count = slotCodes.length;
    if (count == 0) return {};

    final Map<String, Rect> result = {};
    const double gap = 0.012; // Gap separating each detached tray
    final double totalGaps = (count - 1) * gap;
    final double availableWidth = (right - left) - totalGaps;
    final double defaultTrayWidth = math.max(0.04, availableWidth / count);

    for (int i = 0; i < count; i++) {
      final code = slotCodes[i];

      // 1. Direct tray box match
      Rect? r = trayBoxes[code];

      // 2. Legacy fallback: union of old separate 100ml (AA1) and 50ml (AA2) boxes
      if (r == null) {
        final r1 = trayBoxes['${code}1'];
        final r2 = trayBoxes['${code}2'];
        if (r1 != null && r2 != null) {
          r = Rect.fromLTRB(
            math.min(r1.left, r2.left),
            math.min(r1.top, r2.top),
            math.max(r1.right, r2.right),
            math.max(r1.bottom, r2.bottom),
          );
        } else if (r1 != null) {
          r = r1;
        } else if (r2 != null) {
          r = r2;
        }
      }

      // 3. Fallback to default evenly spaced slot layout
      if (r == null) {
        final double tLeft = (left + (defaultTrayWidth + gap) * i).clamp(0.0, 0.95);
        final double tRight = (tLeft + defaultTrayWidth).clamp(0.05, 1.0);
        final double tTop = top.clamp(0.0, 0.95);
        final double tBottom = bottom.clamp(0.05, 1.0);
        r = Rect.fromLTRB(tLeft, tTop, tRight, tBottom);
      }

      result[code] = r;
    }
    return result;
  }

  /// Backward-compatibility helper for any legacy references
  Map<String, Rect> getResolvedSlotBoxes(List<String> slotCodes) =>
      getResolvedTrayBoxes(slotCodes);

  RoiState copyWith({
    int? cameraId,
    double? left,
    double? top,
    double? right,
    double? bottom,
    Map<String, Rect>? trayBoxes,
    String? Function()? selectedTrayCode,
    bool? isEditing,
    bool? isEnabled,
    Set<String>? disabledCapCodes,
  }) {
    return RoiState(
      cameraId: cameraId ?? this.cameraId,
      left: (left ?? this.left).clamp(0.0, 0.99),
      top: (top ?? this.top).clamp(0.0, 0.99),
      right: (right ?? this.right).clamp(0.01, 1.0),
      bottom: (bottom ?? this.bottom).clamp(0.01, 1.0),
      trayBoxes: trayBoxes ?? this.trayBoxes,
      selectedTrayCode: selectedTrayCode != null
          ? selectedTrayCode()
          : this.selectedTrayCode,
      isEditing: isEditing ?? this.isEditing,
      isEnabled: isEnabled ?? this.isEnabled,
      disabledCapCodes: disabledCapCodes ?? this.disabledCapCodes,
    );
  }

  factory RoiState.fromShelfRegion(ShelfRegionModel region) {
    return RoiState(
      cameraId: region.cameraId,
      left: region.left.clamp(0.0, 0.95),
      top: region.top.clamp(0.0, 0.95),
      right: region.right.clamp(0.05, 1.0),
      bottom: region.bottom.clamp(0.05, 1.0),
      isEnabled: region.isActive,
    );
  }
}

class RoiNotifier extends StateNotifier<RoiState> {
  final SqliteService _sqlite;
  final Ref _ref;
  final int cameraId;

  RoiNotifier(this._sqlite, this._ref, this.cameraId)
    : super(RoiState(cameraId: cameraId)) {
    _loadFromDatabase();
  }

  Future<void> _loadFromDatabase() async {
    try {
      // 1. Check if individual detached tray boxes were saved in system settings
      final settingVal = await _sqlite.getSetting(
        'camera_${cameraId}_tray_rois',
      );
      Map<String, Rect> loadedBoxes = {};
      if (settingVal != null && settingVal.isNotEmpty) {
        try {
          final decoded = jsonDecode(settingVal);
          if (decoded is Map) {
            decoded.forEach((k, v) {
              if (v is Map) {
                final l = (v['left'] as num?)?.toDouble() ?? 0.05;
                final t = (v['top'] as num?)?.toDouble() ?? 0.15;
                final r = (v['right'] as num?)?.toDouble() ?? 0.95;
                final b = (v['bottom'] as num?)?.toDouble() ?? 0.85;
                loadedBoxes[k.toString()] = Rect.fromLTRB(l, t, r, b);
              }
            });

            // Legacy migration: If keys are sub-slots like AA1, AA2, merge into AA
            final Map<String, Rect> unified = {};
            for (final entry in loadedBoxes.entries) {
              final k = entry.key;
              if (k.endsWith('1') || k.endsWith('2')) {
                final baseKey = k.substring(0, k.length - 1);
                if (!loadedBoxes.containsKey(baseKey)) {
                  final otherKey = k.endsWith('1') ? '${baseKey}2' : '${baseKey}1';
                  final other = loadedBoxes[otherKey];
                  if (other != null) {
                    unified[baseKey] = Rect.fromLTRB(
                      math.min(entry.value.left, other.left),
                      math.min(entry.value.top, other.top),
                      math.max(entry.value.right, other.right),
                      math.max(entry.value.bottom, other.bottom),
                    );
                  } else {
                    unified[baseKey] = entry.value;
                  }
                }
              } else {
                unified[k] = entry.value;
              }
            }
            if (unified.isNotEmpty) {
              loadedBoxes = unified;
            }
          }
        } catch (_) {}
      }

      // 2. Load bounding region from shelf_regions
      final regions = await _sqlite.getShelfRegions('San Pablo');
      final match = regions.where((r) => r.cameraId == cameraId).firstOrNull;

      if (match != null) {
        state = RoiState.fromShelfRegion(match)
            .copyWith(trayBoxes: loadedBoxes);
      } else if (loadedBoxes.isNotEmpty) {
        final l = loadedBoxes.values.map((r) => r.left).reduce(math.min);
        final t = loadedBoxes.values.map((r) => r.top).reduce(math.min);
        final r = loadedBoxes.values.map((rect) => rect.right).reduce(math.max);
        final b = loadedBoxes.values
            .map((rect) => rect.bottom)
            .reduce(math.max);
        state = state.copyWith(
          left: l,
          top: t,
          right: r,
          bottom: b,
          trayBoxes: loadedBoxes,
        );
      }
    } catch (e) {
      debugPrint('[RoiNotifier] Error loading ROI: $e');
    }
  }

  void selectTray(String? code) {
    state = state.copyWith(selectedTrayCode: () => code);
  }

  void setEditing(bool editing) {
    state = state.copyWith(isEditing: editing);
  }

  void toggleEditing() {
    state = state.copyWith(isEditing: !state.isEditing);
  }

  void setEnabled(bool enabled) {
    state = state.copyWith(isEnabled: enabled);
  }

  void toggleEnabled() {
    state = state.copyWith(isEnabled: !state.isEnabled);
  }

  void setDisabledCapCodes(Set<String> codes) {
    state = state.copyWith(disabledCapCodes: codes);
  }

  /// Moves an individual detached tray box (e.g. AA, AB, AC, AD, AE)
  void moveTray(
    String code,
    double deltaNormX,
    double deltaNormY,
    List<String> slotCodes,
  ) {
    final boxes = Map<String, Rect>.from(state.getResolvedTrayBoxes(slotCodes));
    final cur = boxes[code];
    if (cur == null) return;

    final w = cur.width;
    final h = cur.height;
    final double newLeft = (cur.left + deltaNormX)
        .clamp(0.0, math.max(0.0, 1.0 - w))
        .toDouble();
    final double newTop = (cur.top + deltaNormY)
        .clamp(0.0, math.max(0.0, 1.0 - h))
        .toDouble();
    boxes[code] = Rect.fromLTWH(newLeft, newTop, w, h);

    _updateEnvelopeAndState(boxes);
  }

  /// Alias for backward compatibility
  void moveSlot(
    String code,
    double deltaNormX,
    double deltaNormY,
    List<String> slotCodes,
  ) => moveTray(code, deltaNormX, deltaNormY, slotCodes);

  /// Resizes an individual detached tray box from a specific corner
  void resizeTrayCorner({
    required String code,
    required bool isTop,
    required bool isLeft,
    required double newNormX,
    required double newNormY,
    required List<String> slotCodes,
    double minW = 0.03,
    double minH = 0.05,
  }) {
    final boxes = Map<String, Rect>.from(state.getResolvedTrayBoxes(slotCodes));
    final cur = boxes[code];
    if (cur == null) return;

    final double l = isLeft ? newNormX.clamp(0.0, cur.right - minW).toDouble() : cur.left;
    final double r = !isLeft ? newNormX.clamp(cur.left + minW, 1.0).toDouble() : cur.right;
    final double t = isTop ? newNormY.clamp(0.0, cur.bottom - minH).toDouble() : cur.top;
    final double b = !isTop ? newNormY.clamp(cur.top + minH, 1.0).toDouble() : cur.bottom;

    boxes[code] = Rect.fromLTRB(l, t, r, b);
    _updateEnvelopeAndState(boxes);
  }

  /// Alias for backward compatibility
  void resizeSlotCorner({
    required String code,
    required bool isTop,
    required bool isLeft,
    required double newNormX,
    required double newNormY,
    required List<String> slotCodes,
    double minW = 0.03,
    double minH = 0.05,
  }) => resizeTrayCorner(
    code: code,
    isTop: isTop,
    isLeft: isLeft,
    newNormX: newNormX,
    newNormY: newNormY,
    slotCodes: slotCodes,
    minW: minW,
    minH: minH,
  );

  /// Resizes an individual detached tray box along one edge
  void resizeTrayEdge({
    required String code,
    required RoiHandleType edge,
    required double newNormValue,
    required List<String> slotCodes,
    double minW = 0.03,
    double minH = 0.05,
  }) {
    final boxes = Map<String, Rect>.from(state.getResolvedTrayBoxes(slotCodes));
    final cur = boxes[code];
    if (cur == null) return;

    double l = cur.left;
    double t = cur.top;
    double r = cur.right;
    double b = cur.bottom;

    switch (edge) {
      case RoiHandleType.topEdge:
        t = newNormValue.clamp(0.0, b - minH).toDouble();
        break;
      case RoiHandleType.bottomEdge:
        b = newNormValue.clamp(t + minH, 1.0).toDouble();
        break;
      case RoiHandleType.leftEdge:
        l = newNormValue.clamp(0.0, r - minW).toDouble();
        break;
      case RoiHandleType.rightEdge:
        r = newNormValue.clamp(l + minW, 1.0).toDouble();
        break;
      default:
        return;
    }

    boxes[code] = Rect.fromLTRB(l, t, r, b);
    _updateEnvelopeAndState(boxes);
  }

  /// Alias for backward compatibility
  void resizeSlotEdge({
    required String code,
    required RoiHandleType edge,
    required double newNormValue,
    required List<String> slotCodes,
    double minW = 0.03,
    double minH = 0.05,
  }) => resizeTrayEdge(
    code: code,
    edge: edge,
    newNormValue: newNormValue,
    slotCodes: slotCodes,
    minW: minW,
    minH: minH,
  );

  /// Moves all trays simultaneously, or the active individual tray if one is selected
  void move(double deltaNormX, double deltaNormY, [List<String>? slotCodes]) {
    if (state.selectedTrayCode != null && slotCodes != null) {
      moveTray(state.selectedTrayCode!, deltaNormX, deltaNormY, slotCodes);
      return;
    }

    if (slotCodes != null && slotCodes.isNotEmpty) {
      final boxes = state.getResolvedTrayBoxes(slotCodes);
      final newBoxes = <String, Rect>{};
      for (final entry in boxes.entries) {
        final r = entry.value;
        final double newLeft = (r.left + deltaNormX)
            .clamp(0.0, 1.0 - r.width)
            .toDouble();
        final double newTop = (r.top + deltaNormY)
            .clamp(0.0, 1.0 - r.height)
            .toDouble();
        newBoxes[entry.key] = Rect.fromLTWH(newLeft, newTop, r.width, r.height);
      }
      _updateEnvelopeAndState(newBoxes);
    } else {
      final w = state.width;
      final h = state.height;
      final double newLeft = (state.left + deltaNormX)
          .clamp(0.0, 1.0 - w)
          .toDouble();
      final double newTop = (state.top + deltaNormY)
          .clamp(0.0, 1.0 - h)
          .toDouble();
      state = state.copyWith(
        left: newLeft,
        top: newTop,
        right: newLeft + w,
        bottom: newTop + h,
      );
    }
  }

  /// Resizes corner of active tray, slot, or outer bounds
  void resizeCorner({
    required bool isTop,
    required bool isLeft,
    required double newNormX,
    required double newNormY,
    List<String>? slotCodes,
    double minSize = 0.05,
  }) {
    if (state.selectedTrayCode != null && slotCodes != null) {
      resizeSlotCorner(
        code: state.selectedTrayCode!,
        isTop: isTop,
        isLeft: isLeft,
        newNormX: newNormX,
        newNormY: newNormY,
        slotCodes: slotCodes,
      );
      return;
    }

    double l = state.left;
    double t = state.top;
    double r = state.right;
    double b = state.bottom;

    if (isLeft) {
      l = newNormX.clamp(0.0, r - minSize).toDouble();
    } else {
      r = newNormX.clamp(l + minSize, 1.0).toDouble();
    }

    if (isTop) {
      t = newNormY.clamp(0.0, b - minSize).toDouble();
    } else {
      b = newNormY.clamp(t + minSize, 1.0).toDouble();
    }

    state = state.copyWith(left: l, top: t, right: r, bottom: b);
  }

  /// Resizes edge of active tray, slot, or outer bounds
  void resizeEdge({
    required RoiHandleType edge,
    required double newNormValue,
    List<String>? slotCodes,
    double minSize = 0.05,
  }) {
    if (state.selectedTrayCode != null && slotCodes != null) {
      resizeSlotEdge(
        code: state.selectedTrayCode!,
        edge: edge,
        newNormValue: newNormValue,
        slotCodes: slotCodes,
      );
      return;
    }

    double l = state.left;
    double t = state.top;
    double r = state.right;
    double b = state.bottom;

    switch (edge) {
      case RoiHandleType.topEdge:
        t = newNormValue.clamp(0.0, b - minSize).toDouble();
        break;
      case RoiHandleType.bottomEdge:
        b = newNormValue.clamp(t + minSize, 1.0).toDouble();
        break;
      case RoiHandleType.leftEdge:
        l = newNormValue.clamp(0.0, r - minSize).toDouble();
        break;
      case RoiHandleType.rightEdge:
        r = newNormValue.clamp(l + minSize, 1.0).toDouble();
        break;
      default:
        return;
    }

    state = state.copyWith(left: l, top: t, right: r, bottom: b);
  }

  void scale(
    double scaleFactor, {
    Offset? focalPointNorm,
    List<String>? slotCodes,
  }) {
    final focal =
        focalPointNorm ??
        Offset((state.left + state.right) / 2, (state.top + state.bottom) / 2);
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

  /// Resets a single detached size slot (e.g. AA1) or whole tray back to default
  void resetTray(String code, List<String> slotCodes) {
    final boxes = Map<String, Rect>.from(state.trayBoxes);
    if (code.endsWith('1') || code.endsWith('2')) {
      boxes.remove(code);
    } else {
      boxes.remove(code);
      boxes.remove('${code}1');
      boxes.remove('${code}2');
    }
    _updateEnvelopeAndState(boxes);
  }

  /// Resets all detached trays back to aligned defaults
  void reset([List<String>? slotCodes]) {
    state = state.copyWith(
      left: 0.05,
      top: 0.15,
      right: 0.95,
      bottom: 0.85,
      trayBoxes: {},
      selectedTrayCode: () => null,
    );
    save('San Pablo', slotCodes: slotCodes);
  }

  void _updateEnvelopeAndState(Map<String, Rect> newBoxes) {
    if (newBoxes.isEmpty) {
      state = state.copyWith(trayBoxes: newBoxes);
      return;
    }
    final l = newBoxes.values.map((r) => r.left).reduce(math.min);
    final t = newBoxes.values.map((r) => r.top).reduce(math.min);
    final r = newBoxes.values.map((rect) => rect.right).reduce(math.max);
    final b = newBoxes.values.map((rect) => rect.bottom).reduce(math.max);

    state = state.copyWith(
      left: l,
      top: t,
      right: r,
      bottom: b,
      trayBoxes: newBoxes,
    );
  }

  Future<void> save(String branch, {List<String>? slotCodes}) async {
    try {
      // 1. Save 5 detached tray boxes JSON to system_settings
      final Map<String, dynamic> toSave = {};
      final resolved = slotCodes != null
          ? state.getResolvedTrayBoxes(slotCodes)
          : state.trayBoxes;
      resolved.forEach((k, r) {
        toSave[k] = {
          'left': r.left,
          'top': r.top,
          'right': r.right,
          'bottom': r.bottom,
        };
      });
      await _sqlite.setSystemSetting(
        'camera_${cameraId}_tray_rois',
        jsonEncode(toSave),
      );

      // 2. Save outer envelope to shelf_regions
      final regions = await _sqlite.getShelfRegions(branch);
      final match = regions.where((r) => r.cameraId == cameraId).firstOrNull;
      final status = state.isEnabled ? 'active' : 'seasonal_off';
      if (match != null) {
        final updated = match.copyWith(
          left: state.left,
          top: state.top,
          right: state.right,
          bottom: state.bottom,
          status: status,
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
          status: status,
        );
        await _sqlite.updateShelfRegion(newRegion);
      }
      _ref.invalidate(shelfRegionsProvider(branch));
    } catch (e) {
      debugPrint('[RoiNotifier] Error saving ROI: $e');
    }
  }
}

final cameraRoiProvider =
    StateNotifierProvider.family<RoiNotifier, RoiState, int>((ref, cameraId) {
      final sqlite = SqliteService.instance;
      return RoiNotifier(sqlite, ref, cameraId);
    });
