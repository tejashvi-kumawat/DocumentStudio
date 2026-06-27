import 'dart:convert';

import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user-defined header/footer templates (plus the last used spec).
class HfTemplateStore {
  static const _key = 'hf_custom_templates_v1';
  static const _lastKey = 'hf_last_spec_v1';

  Future<List<HfTemplate>> loadCustom() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final item in list)
          if (item is Map) ?HfTemplate.fromJson(item.cast<String, Object?>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<HfTemplate>> saveCustom({
    required String name,
    required HeaderFooterSpec spec,
    String? replaceId,
  }) async {
    final existing = await loadCustom();
    final id = replaceId ?? 'custom-${DateTime.now().microsecondsSinceEpoch}';
    final template = HfTemplate(
      id: id,
      name: name.trim().isEmpty ? 'Untitled template' : name.trim(),
      description: 'Saved ${_today()}',
      category: 'My templates',
      spec: spec,
      builtIn: false,
    );
    final next = [
      template,
      for (final t in existing)
        if (t.id != id) t,
    ];
    await _write(next);
    return next;
  }

  Future<List<HfTemplate>> delete(String id) async {
    final next = [
      for (final t in await loadCustom())
        if (t.id != id) t,
    ];
    await _write(next);
    return next;
  }

  Future<HeaderFooterSpec?> loadLast({String scope = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_lastKey$scope');
    if (raw == null) return null;
    try {
      return HeaderFooterSpec.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLast(HeaderFooterSpec spec, {String scope = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_lastKey$scope', jsonEncode(spec.toJson()));
  }

  /// Last spec applied to [filePath] (fallback when the PDF lost its
  /// embedded settings, e.g. after another tool rewrote it).
  Future<HeaderFooterSpec?> loadForFile(String kind, String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_fileKeyPrefix$kind:$filePath');
    if (raw == null) return null;
    try {
      return HeaderFooterSpec.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveForFile(
    String kind,
    String filePath,
    HeaderFooterSpec? spec,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_fileKeyPrefix$kind:$filePath';
    if (spec == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(spec.toJson()));
    }
  }

  static const _fileKeyPrefix = 'hf_file_spec_v1:';

  Future<void> _write(List<HfTemplate> templates) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final t in templates) t.toJson()]),
    );
  }

  static String _today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
