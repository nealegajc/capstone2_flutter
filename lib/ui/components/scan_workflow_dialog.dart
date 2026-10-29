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

  const ScanWorkflowDialog({
    super.key,
    this.isTargetedVerification = false,
    this.targetAlert,
    this.initialCameraId = 1,
  });

  static Future<void> show(
    BuildContext context, {
    bool isTargetedVerification = false,
    AlertModel? targetAlert,
    int initialCameraId = 1,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScanWorkflowDialog(
        isTargetedVerification: isTargetedVerification,
        targetAlert: targetAlert,
        initialCameraId: initialCameraId,
      ),
    );
  }

  @override
  ConsumerState<ScanWorkflowDialog> createState() => _ScanWorkflowDialogState();
}

enum _ScanStage { guidance, inProgress, completed }

class _ScanWorkflowDialogState extends ConsumerState<ScanWorkflowDialog> {
  _ScanStage _stage = _ScanStage.guidance;
  String _scanMode = 'full'; // 'full' or 'single'
  late int _selectedCameraId;

  // Pipeline phases
  int _currentPhase = 0; // 0 to 4
  double _progressValue = 0.0;
  int _secondsRemaining = 20;
  Timer? _progressTimer;

  // Results
  int _detectedCount = 0;
  int _misplacedCount = 0;
  bool _verificationSuccess = false;
  String _statusMessage = '';

  final List<String> _pipelinePhases = [
    'Camera Acquisition: Probing sensor & capturing shelf image...',
    'Image Quality Assessment: Verifying lighting, contrast & focus...',
    'YOLO Cap Detection: Locating circular bottle caps...',
    'Multi-Angle OCR: Reading rotational SKU stickers...',
    'Spatial Containment: Mapping tray boundaries & syncing database...',
  ];

  @override
  void initState() {
    super.initState();
    _selectedCameraId = widget.initialCameraId;
    if (widget.isTargetedVerification) {
      _scanMode = 'single';
      // Automatically map targetAlert to camera if possible
      final code = widget.targetAlert?.perfumeCode ?? '';
      if (code.startsWith('A')) {
        _selectedCameraId = 1;
      } else if (code.startsWith('B')) {
        _selectedCameraId = 3;
      } else if (code.startsWith('C')) {
        _selectedCameraId = 5;
      }
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

    setState(() {
      _stage = _ScanStage.inProgress;
      _currentPhase = 0;
      _progressValue = 0.05;
      _secondsRemaining = widget.isTargetedVerification ? 15 : 22;
    });

    _progressTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      if (!mounted) return;
      setState(() {
        if (_progressValue < 0.90) {
          _progressValue += 0.025;
        }
        if (_progressValue > 0.20 && _currentPhase < 1) _currentPhase = 1;
        if (_progressValue > 0.40 && _currentPhase < 2) _currentPhase = 2;
        if (_progressValue > 0.65 && _currentPhase < 3) _currentPhase = 3;
        if (_progressValue > 0.85 && _currentPhase < 4) _currentPhase = 4;
        if (_secondsRemaining > 1) _secondsRemaining--;
      });
    });

    try {
      final hwService = ref.read(cameraHardwareServiceProvider);
      final pythonApi = ref.read(pythonApiRepositoryProvider);
      final targetNode = '/dev/video${(_selectedCameraId - 1) * 2}';

      // 1. Snapshot hardware
      await hwService.captureFrame(deviceNode: targetNode);

      // 2. Trigger edge backend scan
      final scanResult = await pythonApi.triggerManualScan('San Pablo');
      final bottles = (scanResult['bottlesDetected'] as num?)?.toInt() ?? 0;
      final rawDets = scanResult['detections'];
      final List<Map<String, dynamic>> detectionsList = (rawDets is List)
          ? rawDets.map((d) => Map<String, dynamic>.from(d as Map)).toList()
          : <Map<String, dynamic>>[];

      // 3. Update SQLite
      final topSlotCodes = [
        'AA1', 'AA2', 'AB1', 'AB2', 'AC1', 'AC2', 'AD1', 'AD2', 'AE1', 'AE2'
      ];
      await SqliteService.instance.updateInventoryFromDetections(
        cameraId: _selectedCameraId,
        detections: detectionsList,
        branch: 'San Pablo',
        targetSlotCodes: topSlotCodes,
      );

      // 4. Check results
      final misplacedDets = detectionsList.where(
        (d) => d['matchResult'] == 'misplaced',
      ).toList();

      if (widget.isTargetedVerification) {
        final targetCode = widget.targetAlert?.perfumeCode ?? '';
        final stillMisplaced = misplacedDets.any(
          (d) => (d['recognizedCode'] as String?)?.trim().toUpperCase() == targetCode,
        );

        if (!stillMisplaced) {
          await SqliteService.instance.verifyAndClearMisplacement(
            perfumeCode: targetCode,
            branch: 'San Pablo',
          );
          _verificationSuccess = true;
          _statusMessage = 'Misplacement Verified & Cleared! Shelf is now properly aligned.';
        } else {
          _verificationSuccess = false;
          _statusMessage = 'Bottle is still detected on the incorrect tray. Please check shelf again.';
        }
      } else {
        _statusMessage = 'Shelf Vision Scan successfully completed.';
      }

      _detectedCount = bottles;
      _misplacedCount = misplacedDets.length;

      // Invalidate Riverpod providers to update all screens
      ref.invalidate(liveInventoryProvider);
      ref.invalidate(dashboardStatsProvider);
      ref.invalidate(liveAlertsProvider);
      ref.invalidate(systemActivityLogsProvider);
    } catch (e) {
      _statusMessage = 'Scan completed with notice: $e';
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Padding(
          padding: const EdgeInsets.all(28),
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
                    isTargeted ? 'Targeted Misplacement Verification' : 'Shelf Readiness & Scan Mode',
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
                        ? 'Verify that the misplaced bottle has been returned to its designated slot.'
                        : 'Review shelf conditions and select your scanning preference.',
                    style: TextStyle(fontSize: 13, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (!isTargeted) ...[
          // Scan Mode Selector
          Text(
            'SELECT SCAN MODE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: context.textSecondaryColor,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  title: 'Full Shelf Scan',
                  subtitle: 'Inspects all 5 tray slots on the camera layer',
                  icon: Icons.layers_rounded,
                  isSelected: _scanMode == 'full',
                  onTap: () => setState(() => _scanMode = 'full'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildModeCard(
                  title: 'Single Tray Check',
                  subtitle: 'Spot check a specific scent or tray zone',
                  icon: Icons.crop_free_rounded,
                  isSelected: _scanMode == 'single',
                  onTap: () => setState(() => _scanMode = 'single'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],

        // Pre-Scan Do's & Don'ts Reminders
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
                  const Icon(Icons.checklist_rounded, color: AppColors.brandAccent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Pre-Scan Guidelines (Do\'s & Don\'ts)',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildGuidelineItem(
                icon: Icons.lightbulb_outline_rounded,
                color: AppColors.brandGold,
                title: 'Adequate Illumination',
                desc: 'Ensure kiosk shelf LED lights are on and bottles are not obscured by shadows.',
              ),
              const SizedBox(height: 8),
              _buildGuidelineItem(
                icon: Icons.vertical_align_top_rounded,
                color: AppColors.brandAccent,
                title: 'Upright Cap Stickers',
                desc: 'Confirm caps are firmly closed and circular SKU stickers face upward toward the camera.',
              ),
              const SizedBox(height: 8),
              _buildGuidelineItem(
                icon: Icons.pan_tool_outlined,
                color: AppColors.statusRed,
                title: 'No Foreign Objects',
                desc: 'Remove hands, tester strips, mobile devices, and packaging from the tray area.',
              ),
              const SizedBox(height: 8),
              _buildGuidelineItem(
                icon: Icons.grid_goldenratio_rounded,
                color: AppColors.statusGreen,
                title: 'Within Tray Guides',
                desc: 'Ensure bottles sit squarely inside tray dividers without resting on borders.',
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
                isTargeted ? 'I Understand, Verify Now' : 'I Understand, Proceed to Scan',
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

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brandAccent.withValues(alpha: 0.10) : context.surfaceElevatedColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.brandAccent : context.borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? AppColors.brandAccent : context.textSecondaryColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isSelected ? AppColors.brandAccent : context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuidelineItem({
    required IconData icon,
    required Color color,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: context.textPrimaryColor),
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(text: desc, style: TextStyle(color: context.textSecondaryColor)),
              ],
            ),
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
                    'AI Vision Scan in Progress',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  Text(
                    'Lockscreen watchdog paused • Processing edge models',
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
                'VISION BACKEND PIPELINE PROCESS',
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
                'Misplacements',
                '$_misplacedCount',
                _misplacedCount > 0 ? AppColors.statusRed : AppColors.statusGreen,
              ),
              Container(width: 1, height: 36, color: context.borderColor),
              _buildStatMetric(
                'Shelf Status',
                _misplacedCount > 0 ? 'ATTENTION' : 'VERIFIED',
                _misplacedCount > 0 ? AppColors.statusRed : AppColors.statusGreen,
              ),
            ],
          ),
        ),
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
