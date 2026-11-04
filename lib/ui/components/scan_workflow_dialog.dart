import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_helper.dart';
import '../../data/models/alert_model.dart';
import '../../data/services/sqlite_service.dart';
import '../../providers/auto_lock_provider.dart';
import '../../providers/kiosk_providers.dart';

class ScanWorkflowDialog extends ConsumerStatefulWidget {
  final bool isTargetedVerification;
  final AlertModel? targetAlert;
  final int initialCameraId;
  final List<String>? targetSlotCodes;
  final List<String>? targetTrayCodes;
  final List<int>? targetCameraIds;

  const ScanWorkflowDialog({
    super.key,
    this.isTargetedVerification = false,
    this.targetAlert,
    this.initialCameraId = 1,
    this.targetSlotCodes,
    this.targetTrayCodes,
    this.targetCameraIds,
  });

  static Future<void> show(
    BuildContext context, {
    bool isTargetedVerification = false,
    AlertModel? targetAlert,
    int initialCameraId = 1,
    List<String>? targetSlotCodes,
    List<String>? targetTrayCodes,
    List<int>? targetCameraIds,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScanWorkflowDialog(
        isTargetedVerification: isTargetedVerification,
        targetAlert: targetAlert,
        initialCameraId: initialCameraId,
        targetSlotCodes: targetSlotCodes,
        targetTrayCodes: targetTrayCodes,
        targetCameraIds: targetCameraIds,
      ),
    );
  }

  @override
  ConsumerState<ScanWorkflowDialog> createState() => _ScanWorkflowDialogState();
}

enum _ScanStage { guidance, inProgress, completed }

class _ScanWorkflowDialogState extends ConsumerState<ScanWorkflowDialog> {
  _ScanStage _stage = _ScanStage.guidance;
  String _scanMode = 'full'; // 'full', 'single', or 'selective'
  late int _selectedCameraId;
  String _selectedTray = 'AA';

  // Pipeline phases
  int _currentPhase = 0; // 0 to 4
  double _progressValue = 0.0;
  int _secondsRemaining = 8;
  Timer? _progressTimer;

  // Results
  int _detectedCount = 0;
  int _lowStockCount = 0;
  int _seasonalOffCount = 0;
  bool _verificationSuccess = false;
  bool _isLowLightDetected = false;
  String _statusMessage = '';
  final List<String> _itemizedResults = [];
  Map<String, dynamic>? _singleTrayResult;

  final List<String> _pipelinePhases = [
    'Camera Check: Activating camera and capturing shelf view...',
    'Clarity Check: Verifying lighting and image sharpness...',
    'Bottle Counter: Detecting circular bottle caps on shelf...',
    'Slot Mapping: Matching bottles to 100ML and 50ML positions...',
    'Inventory Sync: Updating shelf stock counts in the system...',
  ];

  String _resolveTargetSlot() {
    if (widget.targetSlotCodes != null && widget.targetSlotCodes!.isNotEmpty) {
      return widget.targetSlotCodes!.first.trim().toUpperCase();
    }
    final code = widget.targetAlert?.perfumeCode.trim().toUpperCase() ?? '';
    if (RegExp(r'^[A-C][A-HJ-K][1-2]$').hasMatch(code)) {
      return code;
    }
    final desc = widget.targetAlert?.desc ?? '';
    final match = RegExp(r'\b([A-C][A-HJ-K][1-2])\b').firstMatch(desc);
    if (match != null) return match.group(1)!.toUpperCase();
    final title = widget.targetAlert?.title ?? '';
    final titleMatch = RegExp(r'\b([A-C][A-HJ-K][1-2])\b').firstMatch(title);
    if (titleMatch != null) return titleMatch.group(1)!.toUpperCase();
    return '';
  }

  String _resolveTargetTray() {
    final slot = _resolveTargetSlot();
    if (slot.length >= 2) return slot.substring(0, 2);
    if (widget.targetTrayCodes != null && widget.targetTrayCodes!.isNotEmpty) {
      return widget.targetTrayCodes!.first.trim().toUpperCase();
    }
    final desc = widget.targetAlert?.desc ?? '';
    final trayMatch = RegExp(r'Tray ([A-C][A-HJ-K])', caseSensitive: false).firstMatch(desc);
    if (trayMatch != null) return trayMatch.group(1)!.toUpperCase();
    return _selectedTray;
  }

  @override
  void initState() {
    super.initState();
    _selectedCameraId = widget.initialCameraId;
    if (widget.isTargetedVerification) {
      _scanMode = 'single';
      final foundTray = _resolveTargetTray();
      if (foundTray.isNotEmpty && ['A', 'B', 'C'].contains(foundTray[0])) {
        _selectedTray = foundTray;
        _selectedCameraId = SqliteService.getCameraIdForTray(foundTray);
      }
      _stage = _ScanStage.guidance;
    } else if (widget.targetTrayCodes != null && widget.targetTrayCodes!.isNotEmpty) {
      _scanMode = 'selective';
      _stage = _ScanStage.guidance;
    } else {
      _scanMode = 'full';
      _stage = _ScanStage.guidance;
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  void _startScan() async {
    // Pause auto-lock inactivity timer during scan
    ref.read(autoLockProvider.notifier).pauseTimer();
    final effectiveBranch = ref.read(currentBranchProvider).value ?? await SqliteService.instance.getBranchName();

    final bool isSingle = (_scanMode == 'single' || widget.isTargetedVerification);
    final bool isSelective = (_scanMode == 'selective');
    _itemizedResults.clear();
    _singleTrayResult = null;
    _lowStockCount = 0;
    _seasonalOffCount = 0;

    final List<int> camerasToScan = isSelective
        ? (widget.targetCameraIds != null
            ? (List<int>.from(widget.targetCameraIds!)..sort())
            : (widget.targetTrayCodes!
                .map((t) => SqliteService.getCameraIdForTray(t))
                .toSet()
                .toList()
              ..sort()))
        : (isSingle
            ? [SqliteService.getCameraIdForTray(_selectedTray)]
            : [1, 2, 3, 4, 5, 6]);

    setState(() {
      _stage = _ScanStage.inProgress;
      _currentPhase = 0;
      _progressValue = 0.05;
      _secondsRemaining = isSingle ? 2 : (isSelective ? (camerasToScan.length * 2) : 6);
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (!mounted) return;
      setState(() {
        if (_progressValue < 0.90) {
          _progressValue += isSingle ? 0.12 : (isSelective ? 0.08 : 0.04);
        }
        if (_progressValue > 0.20 && _currentPhase < 1) _currentPhase = 1;
        if (_progressValue > 0.40 && _currentPhase < 2) _currentPhase = 2;
        if (_progressValue > 0.65 && _currentPhase < 3) _currentPhase = 3;
        if (_progressValue > 0.85 && _currentPhase < 4) _currentPhase = 4;
        if (_secondsRemaining > 1) _secondsRemaining--;
      });
    });

    int succeededCams = 0;

    try {
      final hwService = ref.read(cameraHardwareServiceProvider);
      final pythonApi = ref.read(pythonApiRepositoryProvider);

      // 1. Release camera stream if currently previewing to avoid device lock
      if (hwService.isStreaming) {
        await hwService.stopLiveStream();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      int totalBottlesAcrossCams = 0;
      final List<Map<String, dynamic>> allMisplacedDets = [];

      for (int i = 0; i < camerasToScan.length; i++) {
        final camId = camerasToScan[i];
        final targetNode = hwService.getAssignedDeviceNode(camId);
        final seasonalOffSlots = await SqliteService.instance.getSeasonalOffSlotCodes(branch: effectiveBranch);

        if (mounted && camerasToScan.length > 1) {
          setState(() {
            _statusMessage = 'Scanning shelf zone $camId of 6...';
          });
        }

        // Trigger edge backend pure YOLO scan
        final scanResult = await pythonApi.triggerManualScan(
          effectiveBranch,
          cameraId: camId,
          cameraDevice: targetNode,
          enableOcr: false,
          targetTray: isSingle ? _selectedTray : null,
        );
        final isRejected = scanResult['rejected'] == true ||
            scanResult['qualityStatus'] == 'REJECTED_LOW_LIGHT' ||
            scanResult['message']?.toString().contains('Low Lighting') == true;

        if (isRejected || scanResult['success'] == false) {
          if (isRejected) {
            _isLowLightDetected = true;
            _statusMessage = 'Low Lighting Detected: Shelf illumination required';
          }
          debugPrint('[ScanWorkflow] Warning on camera $camId: ${scanResult['message']}');
          continue;
        }

        succeededCams++;

        final rawDets = scanResult['detections'];
        final List<Map<String, dynamic>> detectionsList = (rawDets is List)
            ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
            : <Map<String, dynamic>>[];

        if (isSelective) {
          // Update SQLite ONLY for the selected trays/slots on this camera
          final traysOnThisCam = widget.targetTrayCodes!
              .where((t) => SqliteService.getCameraIdForTray(t) == camId)
              .toList();

          final counts = await SqliteService.instance.updateInventoryFromDetections(
            cameraId: camId,
            detections: detectionsList,
            branch: effectiveBranch,
            targetTrayCodes: traysOnThisCam,
            targetSlotCodes: widget.targetSlotCodes,
          );

          int activeInTrays = 0;
          for (final entry in counts.entries) {
            final slot = entry.key;
            final isOff = seasonalOffSlots.contains(slot);
            if (isOff) {
              _seasonalOffCount++;
              _itemizedResults.add('${SqliteService.formatPerfumeItem(0, slot)} [Seasonal / Off (Skipped)]');
            } else {
              activeInTrays += entry.value;
              _itemizedResults.add(SqliteService.formatPerfumeItem(entry.value, slot));
              if (entry.value <= 2) {
                _lowStockCount++;
              }
            }
          }
          totalBottlesAcrossCams += activeInTrays;
        } else if (isSingle) {
          // Update SQLite ONLY for this targeted tray
          final trayCounts = await SqliteService.instance.updateTrayInventoryFromDetections(
            cameraId: camId,
            trayCode: _selectedTray,
            detections: detectionsList,
            branch: effectiveBranch,
          );
          final slot1 = '${_selectedTray}1';
          final slot2 = '${_selectedTray}2';
          final isOff1 = seasonalOffSlots.contains(slot1);
          final isOff2 = seasonalOffSlots.contains(slot2);
          if (isOff1) _seasonalOffCount++;
          if (isOff2) _seasonalOffCount++;

          final c100 = isOff1 ? 0 : (trayCounts[slot1] ?? 0);
          final c50 = isOff2 ? 0 : (trayCounts[slot2] ?? 0);
          totalBottlesAcrossCams += (c100 + c50);

          if (!isOff1 && c100 <= 2) _lowStockCount++;
          if (!isOff2 && c50 <= 2) _lowStockCount++;

          final item1 = isOff1
              ? '${SqliteService.formatPerfumeItem(0, slot1)} [Seasonal / Off (Skipped)]'
              : SqliteService.formatPerfumeItem(c100, slot1);
          final item2 = isOff2
              ? '${SqliteService.formatPerfumeItem(0, slot2)} [Seasonal / Off (Skipped)]'
              : SqliteService.formatPerfumeItem(c50, slot2);
          _itemizedResults.add(item1);
          _itemizedResults.add(item2);

          final misplacedInTray = detectionsList.where(
            (d) => d['roiId'] == 'tray_$_selectedTray' && d['matchResult'] == 'misplaced',
          ).toList();
          allMisplacedDets.addAll(misplacedInTray);

          final trayActiveCap = (isOff1 ? 0 : 5) + (isOff2 ? 0 : 5);
          _singleTrayResult = {
            'trayCode': _selectedTray,
            'trayTitle': SqliteService.getTrayTitle(_selectedTray),
            'c100': c100,
            'c50': c50,
            'item1': item1,
            'item2': item2,
            'total': c100 + c50,
            'capacity': trayActiveCap,
            'misplaced': misplacedInTray.length,
          };
        } else {
          // Update SQLite for all slots on this camera
          final cameraSlotCodes = SqliteService.getSlotCodesForCamera(camId);
          final counts = await SqliteService.instance.updateInventoryFromDetections(
            cameraId: camId,
            detections: detectionsList,
            branch: effectiveBranch,
            targetSlotCodes: cameraSlotCodes,
          );

          int activeBottlesOnCam = 0;
          for (final slot in cameraSlotCodes) {
            final isOff = seasonalOffSlots.contains(slot);
            if (isOff) {
              _seasonalOffCount++;
              _itemizedResults.add('${SqliteService.formatPerfumeItem(0, slot)} [Seasonal / Off (Skipped)]');
            } else {
              final count = counts[slot] ?? 0;
              activeBottlesOnCam += count;
              _itemizedResults.add(SqliteService.formatPerfumeItem(count, slot));
              if (count <= 2) {
                _lowStockCount++;
              }
            }
          }
          totalBottlesAcrossCams += activeBottlesOnCam;

          final misplacedDets = detectionsList.where(
            (d) => d['matchResult'] == 'misplaced',
          ).toList();
          allMisplacedDets.addAll(misplacedDets);
        }
      }

      if (succeededCams == 0 && camerasToScan.isNotEmpty) {
        if (_isLowLightDetected) {
          _statusMessage = 'Low Lighting Detected: Shelf illumination required';
        } else {
          _statusMessage = 'Shelf scan failed: Unable to connect to camera system.';
        }
        _verificationSuccess = false;
        _lowStockCount = 1;
        if (widget.isTargetedVerification) {
          try {
            final camList = camerasToScan.join(', ');
            final extraDesc = ' while verifying Tray $_selectedTray (${_resolveTargetSlot()}).';
            unawaited(SqliteService.instance.saveAlert(
              AlertModel(
                id: 'alert_system_cam_${DateTime.now().millisecondsSinceEpoch}',
                title: 'Camera Scan Service Unavailable',
                desc: 'Failed to communicate with camera system for Camera(s): $camList$extraDesc',
                branch: effectiveBranch,
                type: 'system',
                createdAt: DateTime.now(),
              ),
            ).then((_) {
              ref.invalidate(liveAlertsProvider);
              ref.invalidate(resolvedAlertsHistoryProvider);
              ref.invalidate(dashboardStatsProvider);
            }).catchError((_) {}));
          } catch (_) {}
        }
      } else if (widget.isTargetedVerification) {
        final targetCode = _resolveTargetSlot();
        final alertType = widget.targetAlert?.type ?? '';

        if (alertType == 'misplaced') {
          final stillMisplaced = allMisplacedDets.any(
            (d) => (d['recognizedCode'] as String?)?.trim().toUpperCase() == targetCode,
          );

          _detectedCount = totalBottlesAcrossCams;
          if (!stillMisplaced) {
            await SqliteService.instance.verifyAndClearMisplacement(
              perfumeCode: targetCode,
              branch: effectiveBranch,
            );
            if (widget.targetAlert != null) {
              await SqliteService.instance.markAlertRead(widget.targetAlert!.id);
            }
            _verificationSuccess = true;
            _statusMessage = 'Misplacement Verified & Cleared! Shelf is now properly aligned.';
          } else {
            _verificationSuccess = false;
            _statusMessage = 'Bottle is still detected on the incorrect tray. Please check shelf again.';
          }
        } else {
          // Low stock or out of stock alert verification (requires >= 3 bottles in the specific fragrance slot to resolve)
          if (targetCode.isNotEmpty) {
            final slotCount = await SqliteService.instance.getDetectedCountForSlot(
              targetCode,
              branch: effectiveBranch,
            );
            final fullName = SqliteService.getPerfumeFullName(targetCode);
            final label = fullName.isNotEmpty ? '$targetCode - $fullName' : targetCode;

            if (slotCount >= 3) {
              if (widget.targetAlert != null) {
                await SqliteService.instance.markAlertRead(widget.targetAlert!.id);
              }
              await SqliteService.instance.markStockAlertsReadForPerfume(
                targetCode,
                branch: effectiveBranch,
              );
              // Synchronize ledger recorded count to verified detected count and log restock
              await SqliteService.instance.confirmSurplusRestock(
                perfumeCode: targetCode,
                branch: effectiveBranch,
                detectedCount: slotCount,
              );

              _verificationSuccess = true;
              _detectedCount = slotCount;
              _lowStockCount = 0;
              _statusMessage = 'Restock Verified! $label now has sufficient stock ($slotCount / 5 bottles). Ledger updated and alerts resolved.';
            } else {
              _verificationSuccess = false;
              _detectedCount = slotCount;
              _lowStockCount = 1;
              final deficit = 3 - slotCount;
              final missingToCapacity = 5 - slotCount;
              _statusMessage = 'Stock is still below threshold for $label: only $slotCount bottle(s) detected '
                  '(Deficit: $deficit more needed for threshold, $missingToCapacity to full capacity). Alert remains active.';
            }
          } else {
            final c100 = await SqliteService.instance.getDetectedCountForSlot('${_selectedTray}1', branch: effectiveBranch);
            final c50 = await SqliteService.instance.getDetectedCountForSlot('${_selectedTray}2', branch: effectiveBranch);
            if (c100 >= 3 && c50 >= 3) {
              if (widget.targetAlert != null) {
                await SqliteService.instance.markAlertRead(widget.targetAlert!.id);
              }
              await SqliteService.instance.confirmSurplusRestock(
                perfumeCode: '${_selectedTray}1',
                branch: effectiveBranch,
                detectedCount: c100,
              );
              await SqliteService.instance.confirmSurplusRestock(
                perfumeCode: '${_selectedTray}2',
                branch: effectiveBranch,
                detectedCount: c50,
              );
              _verificationSuccess = true;
              _detectedCount = c100 + c50;
              _lowStockCount = 0;
              _statusMessage = 'Restock Verified! Tray $_selectedTray: Slot 1 ($c100 / 5) and Slot 2 ($c50 / 5) have sufficient stock. Ledger updated and alerts resolved.';
            } else {
              _verificationSuccess = false;
              _detectedCount = c100 + c50;
              final d1 = (3 - c100).clamp(0, 3);
              final d2 = (3 - c50).clamp(0, 3);
              _statusMessage = 'Stock below threshold for Tray $_selectedTray: '
                  'Slot 1: $c100 / 5 (Deficit: $d1), Slot 2: $c50 / 5 (Deficit: $d2). Alert remains active.';
              _lowStockCount = (c100 <= 2 ? 1 : 0) + (c50 <= 2 ? 1 : 0);
            }
          }
        }
      } else {
        if (isSingle) {
          _statusMessage = 'Tray $_selectedTray Shelf Check completed.';
        } else if (isSelective) {
          _statusMessage = 'Selective Scan completed: ${widget.targetTrayCodes?.length ?? 0} tray(s) updated across $succeededCams camera(s).';
        } else if (succeededCams < camerasToScan.length) {
          _statusMessage = 'Partial scan completed: $succeededCams of ${camerasToScan.length} cameras scanned.';
        } else {
          _statusMessage = 'Shelf Bottle Count successfully completed.';
        }
      }

      if (!widget.isTargetedVerification) {
        _detectedCount = totalBottlesAcrossCams;
      }

      // Invalidate Riverpod providers to update all screens
      ref.invalidate(liveInventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(liveAlertsProvider);
      ref.invalidate(resolvedAlertsHistoryProvider);
      ref.invalidate(activeMisplacementsProvider);
      ref.invalidate(hasActiveMisplacementProvider);
      ref.invalidate(systemActivityLogsProvider);
    } catch (e, st) {
      debugPrint('[ScanWorkflow] ERROR IN SCAN: $e\n$st');
      _statusMessage = 'Scan completed with notice: $e';
      _verificationSuccess = false;
      if (widget.isTargetedVerification && succeededCams == 0 && camerasToScan.isNotEmpty) {
        try {
          unawaited(SqliteService.instance.saveAlert(
            AlertModel(
              id: 'alert_system_err_${DateTime.now().millisecondsSinceEpoch}',
              title: 'Camera Scan Error',
              desc: 'Shelf scan failed with error: $e for Camera(s): ${camerasToScan.join(", ")}.',
              branch: effectiveBranch,
              type: 'system',
              createdAt: DateTime.now(),
            ),
          ).then((_) {
            ref.invalidate(liveAlertsProvider);
            ref.invalidate(resolvedAlertsHistoryProvider);
            ref.invalidate(dashboardStatsProvider);
          }).catchError((_) {}));
        } catch (_) {}
      }
    } finally {
      _progressTimer?.cancel();
      // Resume auto-lock watchdog
      ref.read(autoLockProvider.notifier).resumeTimer();

      if (mounted) {
        setState(() {
          _progressValue = 1.0;
          _currentPhase = 4;
          _stage = _ScanStage.completed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.surfaceColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(26),
          child: switch (_stage) {
            _ScanStage.guidance => _buildGuidanceView(context),
            _ScanStage.inProgress => _buildInProgressView(context),
            _ScanStage.completed => _buildCompletedView(context),
          },
        ),
      ),
    );
  }

  Widget _buildGuidanceView(BuildContext context) {
    final isTargeted = widget.isTargetedVerification;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isTargeted ? AppColors.statusOrange : AppColors.brandAccent)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isTargeted ? Icons.published_with_changes_rounded : Icons.camera_alt_outlined,
                color: isTargeted ? AppColors.statusOrange : AppColors.brandAccent,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isTargeted
                        ? 'Targeted Shelf Verification'
                        : (_scanMode == 'selective'
                            ? 'Selective Tray Scan Readiness'
                            : 'Full Shelf Scan Readiness'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimaryColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isTargeted
                        ? 'Verify that the reported scent or tray issue has been resolved.'
                        : (_scanMode == 'selective'
                            ? 'Review pre-scan readiness checklist for targeted shelf zones.'
                            : 'Review pre-scan readiness checklist before initiating full shelf scan.'),
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        if (isTargeted) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.statusOrange.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.statusOrange.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_searching_rounded, color: AppColors.statusOrange, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TARGETED TRAY: Tray $_selectedTray (${SqliteService.getTrayTitle(_selectedTray)})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: AppColors.statusOrange,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.targetAlert?.desc ?? 'Spot-checking tray alignment on Camera $_selectedCameraId',
                        style: TextStyle(fontSize: 12, color: context.textPrimaryColor),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.statusOrange,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Camera $_selectedCameraId',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
        ],

        if (_scanMode == 'selective') ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.brandAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.checklist_rounded, color: AppColors.brandAccent, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'SELECTIVE SCAN: ${widget.targetTrayCodes?.length ?? 0} TRAYS TARGETED',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Targeted Trays: ${widget.targetTrayCodes?.join(', ') ?? 'None'}\n'
                  'Derived Cameras: ${(widget.targetCameraIds ?? widget.targetTrayCodes?.map((t) => SqliteService.getCameraIdForTray(t)).toSet().toList() ?? []).map((c) => 'Cam $c').join(', ')}\n'
                  'Only the derived cameras will be triggered. Unselected trays in SQLite remain unchanged.',
                  style: TextStyle(fontSize: 12, color: context.textPrimaryColor, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Instant Automatic Bottle Counter Info Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.brandAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.brandAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded, color: AppColors.brandAccent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Instant Automatic Bottle Counter',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Fast bottle count scan with automatic detection for 100ML (left) and 50ML (right) shelf slots.',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Full Shelf Scan Pre-Scan Readiness Checklist
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_rounded, color: AppColors.brandAccent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Full Shelf Scan Pre-Scan Readiness Checklist',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _buildChecklistItem(
                icon: Icons.pan_tool_rounded,
                color: AppColors.statusOrange,
                title: 'Do Not Remove or Restock Bottles During Scan',
                desc: 'Keep hands away from shelves while scanning. Do not take or place bottles until the scan completes.',
              ),
              const SizedBox(height: 10),
              _buildChecklistItem(
                icon: Icons.visibility_rounded,
                color: AppColors.brandAccent,
                title: 'Do Not Cover Perfume Caps or Camera Lenses',
                desc: 'Ensure all bottle caps and overhead cameras are fully visible with nothing resting on top of them.',
              ),
              const SizedBox(height: 10),
              _buildChecklistItem(
                icon: Icons.vertical_align_top_rounded,
                color: AppColors.statusGreen,
                title: 'Upright Bottle Caps Facing Upward',
                desc: 'Ensure bottles are seated upright in tray slots with caps clean and facing overhead cameras.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Actions
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: context.textSecondaryColor, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 14),
            ElevatedButton.icon(
              onPressed: _startScan,
              icon: const Icon(Icons.play_arrow_rounded, size: 22),
              label: Text(
                isTargeted
                    ? 'I Understand, Verify Now'
                    : (_scanMode == 'selective'
                        ? 'Start Selective Scan'
                        : 'Start Full Shelf Scan'),
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isTargeted ? AppColors.statusOrange : AppColors.brandAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChecklistItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 11,
                  color: context.textSecondaryColor,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInProgressView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.brandAccent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Automatic Bottle Count in Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  Text(
                    _statusMessage.isNotEmpty ? _statusMessage : 'Scanning shelf zones • Automatic bottle count in progress',
                    style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.surfaceElevatedColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: context.borderColor),
              ),
              child: Text(
                '~${_secondsRemaining}s remaining',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brandAccent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: _progressValue,
            minHeight: 10,
            backgroundColor: context.borderColor,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.brandAccent),
          ),
        ),
        const SizedBox(height: 20),

        // Live Pipeline Phase Stepper Window
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AUTOMATIC BOTTLE COUNTING PIPELINE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: context.textSecondaryColor,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < _pipelinePhases.length; i++) ...[
                _buildPhaseRow(
                  title: _pipelinePhases[i],
                  isDone: _currentPhase > i,
                  isActive: _currentPhase == i,
                ),
                if (i < _pipelinePhases.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPhaseRow({
    required String title,
    required bool isDone,
    required bool isActive,
  }) {
    Color iconColor;
    IconData iconData;

    if (isDone) {
      iconColor = AppColors.statusGreen;
      iconData = Icons.check_circle_rounded;
    } else if (isActive) {
      iconColor = AppColors.brandAccent;
      iconData = Icons.motion_photos_on_rounded;
    } else {
      iconColor = context.textSecondaryColor.withValues(alpha: 0.4);
      iconData = Icons.radio_button_unchecked_rounded;
    }

    return Row(
      children: [
        Icon(iconData, color: iconColor, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
              color: isActive
                  ? context.textPrimaryColor
                  : (isDone ? context.textPrimaryColor : context.textSecondaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompletedView(BuildContext context) {
    final isTargeted = widget.isTargetedVerification;
    final isSuccess = !isTargeted || _verificationSuccess;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isSuccess ? AppColors.statusGreen : AppColors.statusRed)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                color: isSuccess ? AppColors.statusGreen : AppColors.statusRed,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isSuccess ? 'Scan Completed Successfully' : 'Verification Incomplete',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimaryColor,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _statusMessage,
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (_isLowLightDetected) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber, width: 1.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, color: Colors.amber, size: 28),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Low Lighting Detected: Shelf illumination required',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Ambient shelf illumination is below minimum threshold (< 15.0). Shelf lighting must be activated to complete inventory verification.',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_seasonalOffCount > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.pause_circle_filled_rounded,
                  color: Color(0xFFF59E0B),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_seasonalOffCount Fragrance${_seasonalOffCount == 1 ? '' : 's'} Seasonal / Off (Skipped)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PAUSED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],

        // Summary Stats Strip
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.surfaceElevatedColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatMetric('Bottles Detected', '$_detectedCount', AppColors.brandAccent),
              Container(width: 1, height: 36, color: context.borderColor),
              _buildStatMetric(
                'Low Stock',
                '$_lowStockCount',
                _lowStockCount > 0 ? AppColors.statusOrange : AppColors.statusGreen,
              ),
              Container(width: 1, height: 36, color: context.borderColor),
              _buildStatMetric(
                'Shelf Status',
                _lowStockCount > 0 ? 'RESTOCK NEEDED' : 'OPTIMAL',
                _lowStockCount > 0 ? AppColors.statusOrange : AppColors.statusGreen,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Itemized Perfume Results formatted strictly as [how many] [code] [perfume name]
        if (_singleTrayResult != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TRAY ${_singleTrayResult!['trayCode']} PERFUME BREAKDOWN',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: context.textSecondaryColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      '${_singleTrayResult!['total']} / ${_singleTrayResult!['capacity'] ?? 10} Bottles Present',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brandAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildSkuCountCard(
                  context,
                  formattedString: _singleTrayResult!['item1'] as String,
                  count: _singleTrayResult!['c100'] as int,
                  maxCapacity: 5,
                  sizeLabel: '100ML Column',
                ),
                const SizedBox(height: 8),
                _buildSkuCountCard(
                  context,
                  formattedString: _singleTrayResult!['item2'] as String,
                  count: _singleTrayResult!['c50'] as int,
                  maxCapacity: 5,
                  sizeLabel: '50ML Column',
                ),
              ],
            ),
          ),
        ] else if (_itemizedResults.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceElevatedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    Text(
                      'SHELF DETECTION & STOCK SUMMARY',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: context.textSecondaryColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    Text(
                      '${_itemizedResults.length} Fragrances Monitored',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _itemizedResults.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 6),
                    itemBuilder: (ctx, idx) {
                      final item = _itemizedResults[idx];
                      final isSkipped = item.contains('[Seasonal / Off (Skipped)]');
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSkipped
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.08)
                              : context.surfaceColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSkipped
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.4)
                                : context.borderColor,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSkipped
                                  ? Icons.pause_circle_outline_rounded
                                  : Icons.sanitizer_rounded,
                              size: 16,
                              color: isSkipped
                                  ? const Color(0xFFF59E0B)
                                  : AppColors.brandAccent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isSkipped
                                      ? const Color(0xFFF59E0B)
                                      : context.textPrimaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSkuCountCard(
    BuildContext context, {
    required String formattedString,
    required int count,
    required int maxCapacity,
    required String sizeLabel,
  }) {
    final bool isSkipped = formattedString.contains('[Seasonal / Off (Skipped)]');
    final bool isLow = !isSkipped && count < 2;
    final Color statusColor = isSkipped
        ? AppColors.statusAmber
        : (isLow ? AppColors.statusOrange : AppColors.brandAccent);
    final Color badgeColor = isSkipped
        ? AppColors.statusAmber
        : (isLow ? AppColors.statusOrange : AppColors.statusGreen);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSkipped
              ? AppColors.statusAmber.withValues(alpha: 0.5)
              : (isLow ? AppColors.statusOrange.withValues(alpha: 0.5) : context.borderColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isSkipped ? Icons.pause_circle_filled_rounded : Icons.sanitizer_rounded,
              color: statusColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formattedString,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: isSkipped ? AppColors.statusAmber : context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isSkipped ? '$sizeLabel • Paused' : sizeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSkipped
                        ? AppColors.statusAmber.withValues(alpha: 0.8)
                        : context.textSecondaryColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: badgeColor,
              ),
            ),
            child: Text(
              isSkipped ? 'PAUSED' : '$count / $maxCapacity',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: badgeColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textSecondaryColor),
        ),
      ],
    );
  }
}
