import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/sqlite_service.dart';
import 'data/services/sync_service.dart';
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env configuration securely from disk
  try {
    final envFile = File('.env');
    if (envFile.existsSync()) {
      dotenv.testLoad(fileInput: await envFile.readAsString());
    } else {
      await dotenv.load(fileName: '.env');
    }
  } catch (e) {
    debugPrint('Environment configuration notice: $e');
  }

  // Initialize Supabase Cloud Backend
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (e) {
    debugPrint('Supabase initialization warning (running in offline mode): $e');
  }

  // Initialize SQLite FFI for Linux Desktop Standalone Kiosk
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Linux Desktop Window Manager for Kiosk Mode (1920x1080 Landscape Fullscreen)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1920, 1080),
        minimumSize: Size(1280, 720),
        center: true,
        fullScreen: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.hidden,
        title: 'Otto Scents Smart Shelf - Linux Touchscreen Kiosk',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setFullScreen(true);
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }

  // Record kiosk startup in activity logs
  try {
    await SqliteService.instance.initialize();
    SyncService.instance.initialize(enableAutoSync: true);
    await SqliteService.instance.logActivity(
      type: 'SYSTEM_STARTUP',
      description: 'Otto Scents kiosk terminal initialized on host',
      user: 'System',
      branch: 'San Pablo',
    );
  } catch (_) {}

  runApp(const ProviderScope(child: OttoScentsKioskApp()));
}

class OttoScentsKioskApp extends ConsumerWidget {
  const OttoScentsKioskApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'Otto Scents Smart Shelf',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightKioskTheme,
      darkTheme: AppTheme.darkKioskTheme,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
