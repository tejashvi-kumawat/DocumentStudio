import 'dart:convert';

import 'package:document_studio/features/home/home_pdf_open_mode.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePdfOpenModeRepository {
  HomePdfOpenModeRepository(this._prefs);

  static const _key = 'home_pdf_open_mode_v1';

  final SharedPreferences _prefs;

  static Future<HomePdfOpenModeRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return HomePdfOpenModeRepository(prefs);
  }

  Map<String, HomePdfOpenMode> loadAll() {
    final raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in map.entries)
          e.key:
              HomePdfOpenMode.fromStorage(e.value as String?) ??
              HomePdfOpenMode.read,
      };
    } catch (_) {
      return {};
    }
  }

  HomePdfOpenMode modeForPath(
    String path, {
    HomePdfOpenMode fallback = HomePdfOpenMode.read,
  }) {
    return loadAll()[path] ?? fallback;
  }

  Future<void> setMode(String path, HomePdfOpenMode mode) async {
    final all = loadAll()..[path] = mode;
    await _prefs.setString(
      _key,
      jsonEncode({for (final e in all.entries) e.key: e.value.name}),
    );
  }
}
