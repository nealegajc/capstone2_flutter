import 'package:shared_preferences/shared_preferences.dart';

class ThemeRepository {
  static const String _keyDarkMode = 'is_dark_mode';

  Future<bool> loadDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyDarkMode) ?? true; // Default to dark mode for kiosk display
  }

  Future<void> saveDarkMode(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDarkMode, isDark);
  }
}
