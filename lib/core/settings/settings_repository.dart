import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsRepository {
  SettingsRepository(this._prefs);

  static const _themeKey = 'theme_mode_v1';
  static const _strictOfflineKey = 'strict_offline_v1';

  final SharedPreferences _prefs;

  static Future<SettingsRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsRepository(prefs);
  }

  ThemeMode get themeMode {
    final v = _prefs.getString(_themeKey);
    return switch (v) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _prefs.setString(_themeKey, v);
  }

  bool get strictOffline => _prefs.getBool(_strictOfflineKey) ?? true;

  Future<void> setStrictOffline(bool value) async {
    await _prefs.setBool(_strictOfflineKey, value);
  }
}
