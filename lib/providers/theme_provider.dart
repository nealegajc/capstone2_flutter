import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/theme_repository.dart';
import '../data/services/sqlite_service.dart';

final themeRepositoryProvider = Provider<ThemeRepository>(
  (ref) => ThemeRepository(),
);

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  final repo = ref.watch(themeRepositoryProvider);
  return ThemeModeNotifier(repo);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._repo) : super(ThemeMode.dark) {
    _loadTheme();
  }

  final ThemeRepository _repo;

  Future<void> _loadTheme() async {
    try {
      final isDark = await _repo.loadDarkMode();
      state = isDark ? ThemeMode.dark : ThemeMode.light;
    } catch (_) {
      state = ThemeMode.dark;
    }
  }

  Future<void> toggleTheme() async {
    final newMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = newMode;
    try {
      await _repo.saveDarkMode(newMode == ThemeMode.dark);
      await SqliteService.instance.logActivity(
        type: 'THEME_SWITCH',
        description:
            'Kiosk display theme changed to ${newMode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode'}.',
      );
    } catch (_) {}
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    try {
      await _repo.saveDarkMode(mode == ThemeMode.dark);
      await SqliteService.instance.logActivity(
        type: 'THEME_SWITCH',
        description:
            'Kiosk display theme set to ${mode == ThemeMode.dark ? 'Dark Mode' : 'Light Mode'}.',
      );
    } catch (_) {}
  }
}
