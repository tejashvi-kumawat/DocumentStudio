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
      'system' => ThemeMode.system,
      // First launch: light, as the brand design intends.
      _ => ThemeMode.light,
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

  static const _zoomKey = 'viewer_default_zoom_v1';
  static const _displayKey = 'viewer_default_display_v1';

  /// `fitWidth`, `fitPage` or `actual`.
  String get defaultZoom => _prefs.getString(_zoomKey) ?? 'fitWidth';

  Future<void> setDefaultZoom(String value) =>
      _prefs.setString(_zoomKey, value);

  /// `continuous`, `singlePage` or `twoPage`.
  String get defaultPageDisplay => _prefs.getString(_displayKey) ?? 'continuous';

  Future<void> setDefaultPageDisplay(String value) =>
      _prefs.setString(_displayKey, value);

  static const _qualityKey = 'render_quality_v1';
  static const _textFamilyKey = 'new_text_family_v1';
  static const _textSizeKey = 'new_text_size_v1';

  /// `auto`, `high` or `fast`.
  String get renderQuality => _prefs.getString(_qualityKey) ?? 'auto';
  Future<void> setRenderQuality(String v) => _prefs.setString(_qualityKey, v);

  /// `sans`, `serif` or `mono` — font of newly added text.
  String get newTextFamily => _prefs.getString(_textFamilyKey) ?? 'sans';
  Future<void> setNewTextFamily(String v) => _prefs.setString(_textFamilyKey, v);

  double get newTextSize => _prefs.getDouble(_textSizeKey) ?? 14;
  Future<void> setNewTextSize(double v) => _prefs.setDouble(_textSizeKey, v);

  /// Cache disk budget in GB; 0 = automatic (20% of free space, 1–7 GB).
  int get cacheBudgetGb => _prefs.getInt('cache_budget_gb_v1') ?? 0;
  Future<void> setCacheBudgetGb(int v) => _prefs.setInt('cache_budget_gb_v1', v);
}
