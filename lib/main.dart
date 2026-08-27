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
import 'providers/theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env configuration
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // If .env file is missing or unreadable, fallback to hardcoded constants in SupabaseConfig
  }

  // Initialize Supabase Cloud Backend
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  } catch (e) {
    debugPrint('Supabase initialization warning (running in offline mode): $e');
  }

  // Initialize SQLite FFI for Linux Desktop Standalone Kiosk
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Initialize Linux Desktop Window Manager for Kiosk Mode (1920x1080 Landscape)
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    try {
      await windowManager.ensureInitialized();
      const windowOptions = WindowOptions(
        size: Size(1920, 1080),
        minimumSize: Size(1280, 720),
        center: true,
        backgroundColor: Colors.transparent,
        skipTaskbar: false,
        titleBarStyle: TitleBarStyle.normal,
        title: 'Otto Scents Smart Shelf - Linux Touchscreen Kiosk',
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (_) {}
  }

  runApp(
    const ProviderScope(
      child: OttoScentsKioskApp(),
    ),
  );
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
