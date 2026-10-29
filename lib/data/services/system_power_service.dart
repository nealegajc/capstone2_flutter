import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'sqlite_service.dart';

class SystemPowerService {
  static final SystemPowerService instance = SystemPowerService._();
  SystemPowerService._();

  /// Relaunches the Flutter application process in detached mode and exits the current instance.
  Future<void> relaunchApp() async {
    try {
      await SqliteService.instance.logActivity(
        type: 'APP_RELAUNCH',
        description: 'Kiosk application relaunch initiated by operator',
      );
    } catch (_) {}

    try {
      final executable = Platform.resolvedExecutable;
      final args = Platform.executableArguments;
      await Process.start(executable, args, mode: ProcessStartMode.detached);
    } catch (e) {
      debugPrint('Failed to spawn detached process for relaunch: $e');
    }
    exit(0);
  }

  /// Reboots the operating system directly, bypassing GNOME session prompts.
  /// Uses systemd/login1 commands that immediately instruct the init daemon to reboot.
  Future<void> restartSystem() async {
    try {
      await SqliteService.instance.logActivity(
        type: 'SYSTEM_REBOOT',
        description: 'Operating system reboot triggered from kiosk terminal (GNOME prompt bypassed)',
      );
    } catch (_) {}

    // Methods that bypass GNOME's 60-second interactive session-quit dialog:
    final rebootCommands = [
      ['systemctl', 'reboot', '-i'],
      ['sudo', 'systemctl', 'reboot', '-i'],
      ['sudo', 'reboot'],
      [
        'dbus-send',
        '--system',
        '--print-reply',
        '--dest=org.freedesktop.login1',
        '/org/freedesktop/login1',
        'org.freedesktop.login1.Manager.Reboot',
        'boolean:true',
      ],
      ['systemctl', '--no-wall', 'reboot'],
    ];

    for (final cmd in rebootCommands) {
      try {
        final res = await Process.run(cmd.first, cmd.sublist(1));
        if (res.exitCode == 0) return;
      } catch (_) {}
    }
  }

  /// Shuts down the operating system directly, bypassing GNOME session prompts.
  /// Uses systemd/login1 commands that immediately instruct the init daemon to power off.
  Future<void> shutdownSystem() async {
    try {
      await SqliteService.instance.logActivity(
        type: 'SYSTEM_SHUTDOWN',
        description: 'Operating system shutdown triggered from kiosk terminal (GNOME prompt bypassed)',
      );
    } catch (_) {}

    final shutdownCommands = [
      ['systemctl', 'poweroff', '-i'],
      ['sudo', 'systemctl', 'poweroff', '-i'],
      ['sudo', 'poweroff'],
      [
        'dbus-send',
        '--system',
        '--print-reply',
        '--dest=org.freedesktop.login1',
        '/org/freedesktop/login1',
        'org.freedesktop.login1.Manager.PowerOff',
        'boolean:true',
      ],
      ['systemctl', '--no-wall', 'poweroff'],
    ];

    for (final cmd in shutdownCommands) {
      try {
        final res = await Process.run(cmd.first, cmd.sublist(1));
        if (res.exitCode == 0) return;
      } catch (_) {}
    }
  }
}
