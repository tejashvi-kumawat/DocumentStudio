import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/domain/pdf_stamp/stamp_library_models.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists custom stamp designs, image stamps, and date-stamp prefs.
class SavedStampStore {
  static const _nameKey = 'ds_stamp_user_name_v1';
  static const _designsKey = 'ds_stamp_designs_v1';
  static const _imagesKey = 'ds_stamp_images_v1';
  static const _dateFormatKey = 'ds_stamp_date_format_v1';
  static const _dateColorKey = 'ds_stamp_date_color_v1';

  static String defaultUserName() {
    final env = Platform.environment;
    return env['USER'] ?? env['USERNAME'] ?? 'User';
  }

  Future<String> loadUserName() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_nameKey);
    if (v == null || v.trim().isEmpty) return defaultUserName();
    return v;
  }

  Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name.trim());
  }

  Future<List<StampDesign>> loadDesigns() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_designsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map)
            StampDesign.fromJson(Map<String, Object?>.from(e)),
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveDesign(StampDesign design) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadDesigns();
    final id = design.id.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toRadixString(36)
        : design.id;
    final next = design.copyWith(id: id);
    final out = <StampDesign>[
      for (final d in all)
        if (d.id != next.id) d,
      next,
    ];
    await prefs.setString(
      _designsKey,
      jsonEncode([for (final d in out) d.toJson()]),
    );
  }

  Future<void> removeDesign(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await loadDesigns();
    await prefs.setString(
      _designsKey,
      jsonEncode([
        for (final d in all)
          if (d.id != id) d.toJson(),
      ]),
    );
  }

  Future<Directory> _imageDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'stamps'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<SavedImageStamp>> loadImageStamps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_imagesKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final out = <SavedImageStamp>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['id'];
        final name = e['name'];
        final path = e['path'];
        if (id is! String || name is! String || path is! String) continue;
        final file = File(path);
        if (!await file.exists()) continue;
        out.add(SavedImageStamp(
          id: id,
          name: name,
          bytes: await file.readAsBytes(),
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> addImageStamp(Uint8List png, String name) async {
    final prefs = await SharedPreferences.getInstance();
    final dir = await _imageDir();
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final file = File(p.join(dir.path, 'stamp_$id.png'));
    await file.writeAsBytes(png, flush: true);
    final index = <Map<String, Object?>>[];
    final raw = prefs.getString(_imagesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        for (final e in list) {
          if (e is Map) index.add(Map<String, Object?>.from(e));
        }
      } catch (_) {}
    }
    index.insert(0, {'id': id, 'name': name, 'path': file.path});
    await prefs.setString(_imagesKey, jsonEncode(index));
  }

  Future<void> removeImageStamp(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_imagesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final kept = <Map<String, Object?>>[];
      for (final e in list) {
        if (e is! Map) continue;
        final map = Map<String, Object?>.from(e);
        if (map['id'] == id) {
          final path = map['path'];
          if (path is String) {
            try {
              await File(path).delete();
            } catch (_) {}
          }
        } else {
          kept.add(map);
        }
      }
      await prefs.setString(_imagesKey, jsonEncode(kept));
    } catch (_) {}
  }

  Future<DateStampPrefs> loadDateStampPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return DateStampPrefs(
      format: prefs.getString(_dateFormatKey) ?? kStampDateFormats.first,
      color: prefs.getInt(_dateColorKey) ?? StampColors.blue,
    );
  }

  Future<void> saveDateStampPrefs({String? format, int? color}) async {
    final prefs = await SharedPreferences.getInstance();
    if (format != null) await prefs.setString(_dateFormatKey, format);
    if (color != null) await prefs.setInt(_dateColorKey, color);
  }
}
