import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/system_power_provider.dart';

class SystemRestartBanner extends ConsumerWidget {
  const SystemRestartBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(systemRestartProvider);

    if (!state.isCountingDown) {
      return const SizedBox.shrink();
    }

    final progress = (state.remainingSeconds / 15.0).clamp(0.0, 1.0);

    final isShutdown = state.action == SystemPowerAction.shutdown;
    final title = isShutdown
        ? 'OPERATING SYSTEM SHUTDOWN IN PROGRESS'
        : 'OPERATING SYSTEM RESTART IN PROGRESS';
    final subtitle = isShutdown
        ? 'Powering off kiosk terminal hardware in ${state.remainingSeconds} seconds. Tap Cancel to abort.'
        : 'Rebooting kiosk terminal hardware in ${state.remainingSeconds} seconds. Tap Cancel to abort.';
    final actionLabel = isShutdown ? 'Shutdown Now' : 'Restart Now';
    final actionIcon = isShutdown
        ? Icons.power_settings_new_rounded
        : Icons.restart_alt_rounded;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFB91C1C), // Vivid Warning Crimson
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${state.remainingSeconds}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(actionIcon, color: Colors.white, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'GNOME Prompt Bypassed',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                OutlinedButton.icon(
                  onPressed: () {
                    ref.read(systemRestartProvider.notifier).cancelCountdown();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Cancel',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 1.5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.read(systemRestartProvider.notifier).executeNow();
                  },
                  icon: Icon(
                    actionIcon,
                    size: 18,
                    color: const Color(0xFFB91C1C),
                  ),
                  label: Text(
                    actionLabel,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFFB91C1C),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 4,
          ),
        ],
      ),
    );
  }
}
