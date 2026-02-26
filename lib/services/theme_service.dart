import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service untuk menyimpan preferensi tema (terang/gelap) secara manual.
/// Default: terang. Geser kanan = gelap, geser kiri = terang.
class ThemeService {
  ThemeService._();

  static const _keyThemeMode = 'app_theme_mode';

  static ThemeMode _current = ThemeMode.light;
  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(_current);

  static ThemeMode get current => _current;

  /// Inisialisasi: baca preferensi dari SharedPreferences.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_keyThemeMode);
      if (stored != null) {
        _current = stored == 'dark' ? ThemeMode.dark : ThemeMode.light;
        themeModeNotifier.value = _current;
      }
    } catch (_) {
      _current = ThemeMode.light;
    }
  }

  /// Set tema dan simpan ke SharedPreferences.
  static Future<void> setThemeMode(ThemeMode mode) async {
    if (_current == mode) return;
    _current = mode;
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyThemeMode, mode == ThemeMode.dark ? 'dark' : 'light');
    } catch (_) {}
  }

  /// Toggle: terang <-> gelap.
  static Future<void> toggle() async {
    await setThemeMode(
      _current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
