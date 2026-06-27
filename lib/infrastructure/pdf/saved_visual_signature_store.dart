import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SavedSignatureKind { signature, initials }

/// One reusable signature / initials appearance persisted as a PNG file.
class SavedSignature {
  const SavedSignature({
    required this.id,
    required this.path,
    required this.bytes,
    required this.created,
    this.kind = SavedSignatureKind.signature,
    this.width = 0,
    this.height = 0,
  });

  final String id;
  final String path;
  final Uint8List bytes;
  final DateTime created;
  final SavedSignatureKind kind;

  /// Pixel size of [bytes] (0 when unknown, e.g. legacy entries).
  final int width;
  final int height;

  bool get isInitials => kind == SavedSignatureKind.initials;

  double get aspect => width > 0 && height > 0 ? width / height : 3.0;
}

SavedSignatureKind _kindOf(Object? v) => v == 'initials'
    ? SavedSignatureKind.initials
    : SavedSignatureKind.signature;

(int, int) _pngSize(Uint8List png) {
  if (png.length < 24 || png[0] != 0x89 || png[1] != 0x50) return (0, 0);
  int be(int o) =>
      (png[o] << 24) | (png[o + 1] << 16) | (png[o + 2] << 8) | png[o + 3];
  return (be(16), be(20));
}

/// Persists up to [maxSaved] signatures and initials (PNG files in
/// `<app support>/signatures/`, index in shared_preferences). Newest first.
class SavedVisualSignatureStore {
  static const maxSaved = 24;
  static const _legacyKey = 'ds_saved_visual_signature_path_v1';
  static const _indexKey = 'ds_saved_visual_signatures_v2';

  static Future<void> _lock = Future.value();

  Future<T> _serialized<T>(Future<T> Function() op) {
    final next = _lock.then((_) => op());
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'signatures'));
  }

  Future<File> _legacyDefaultFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'saved_visual_signature.png'));
  }

  List<Map<String, Object?>> _readIndex(SharedPreferences prefs) {
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map) Map<String, Object?>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeIndex(
    SharedPreferences prefs,
    List<Map<String, Object?>> index,
  ) =>
      prefs.setString(_indexKey, jsonEncode(index));

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<Map<String, Object?>> _writeEntry(
    Uint8List png, [
    SavedSignatureKind kind = SavedSignatureKind.signature,
  ]) async {
    final dir = await _dir();
    await dir.create(recursive: true);
    final id = _newId();
    final file = File(p.join(dir.path, 'sig_$id.png'));
    await file.writeAsBytes(png, flush: true);
    return {
      'id': id,
      'path': file.path,
      'created': DateTime.now().millisecondsSinceEpoch,
      'kind': kind.name,
    };
  }

  Future<void> _migrateLegacy(
    SharedPreferences prefs,
    List<Map<String, Object?>> index,
  ) async {
    final legacyPath = prefs.getString(_legacyKey);
    final legacy = legacyPath != null && legacyPath.isNotEmpty
        ? File(legacyPath)
        : await _legacyDefaultFile();
    if (!await legacy.exists()) {
      if (legacyPath != null) await prefs.remove(_legacyKey);
      return;
    }
    final bytes = await legacy.readAsBytes();
    if (bytes.isNotEmpty) {
      final entry = await _writeEntry(bytes);
      entry['created'] =
          (await legacy.lastModified()).millisecondsSinceEpoch;
      index.add(entry);
      await _writeIndex(prefs, index);
    }
    await prefs.remove(_legacyKey);
    try {
      await legacy.delete();
    } catch (_) {}
  }

  Future<List<SavedSignature>> _loadAllUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    final index = _readIndex(prefs);
    await _migrateLegacy(prefs, index);
    final out = <SavedSignature>[];
    final kept = <Map<String, Object?>>[];
    for (final e in index) {
      final id = e['id'];
      final path = e['path'];
      if (id is! String || path is! String) continue;
      final file = File(path);
      try {
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        final created = e['created'];
        final (w, h) = _pngSize(bytes);
        out.add(
          SavedSignature(
            id: id,
            path: path,
            bytes: bytes,
            created: DateTime.fromMillisecondsSinceEpoch(
              created is int ? created : 0,
            ),
            kind: _kindOf(e['kind']),
            width: w,
            height: h,
          ),
        );
        kept.add(e);
      } catch (_) {}
    }
    if (kept.length != index.length) await _writeIndex(prefs, kept);
    return out;
  }

  /// All saved signatures, newest first.
  Future<List<SavedSignature>> loadAll() async {
    try {
      return await _serialized(_loadAllUnlocked);
    } catch (_) {
      return const [];
    }
  }

  /// Saves [png] as the newest signature, trimming the list to [maxSaved].
  Future<SavedSignature> add(
    Uint8List png, {
    SavedSignatureKind kind = SavedSignatureKind.signature,
  }) =>
      _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final index = _readIndex(prefs);
        await _migrateLegacy(prefs, index);
        final entry = await _writeEntry(png, kind);
        index.insert(0, entry);
        while (index.length > maxSaved) {
          final dropped = index.removeLast();
          final path = dropped['path'];
          if (path is String) {
            try {
              await File(path).delete();
            } catch (_) {}
          }
        }
        await _writeIndex(prefs, index);
        return SavedSignature(
          id: entry['id']! as String,
          path: entry['path']! as String,
          bytes: png,
          created: DateTime.fromMillisecondsSinceEpoch(entry['created']! as int),
          kind: kind,
          width: _pngSize(png).$1,
          height: _pngSize(png).$2,
        );
      });

  Future<void> remove(String id) => _serialized(() async {
        final prefs = await SharedPreferences.getInstance();
        final index = _readIndex(prefs);
        final i = index.indexWhere((e) => e['id'] == id);
        if (i < 0) return;
        final path = index.removeAt(i)['path'];
        await _writeIndex(prefs, index);
        if (path is String) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      });

  /// Most recent saved signature PNG, or null if none.
  Future<Uint8List?> load() async {
    final all = await loadAll();
    return all.isEmpty ? null : all.first.bytes;
  }

  /// Adds [pngBytes] as the newest reusable signature.
  Future<void> save(Uint8List pngBytes) async {
    await add(pngBytes);
  }

  /// Removes every saved signature (including the legacy single file).
  Future<void> clear() => _serialized(() async {
        try {
          final prefs = await SharedPreferences.getInstance();
          for (final e in _readIndex(prefs)) {
            final path = e['path'];
            if (path is String) {
              try {
                await File(path).delete();
              } catch (_) {}
            }
          }
          await prefs.remove(_indexKey);
          final legacyPath = prefs.getString(_legacyKey);
          await prefs.remove(_legacyKey);
          final legacy = legacyPath != null && legacyPath.isNotEmpty
              ? File(legacyPath)
              : await _legacyDefaultFile();
          if (await legacy.exists()) await legacy.delete();
        } catch (_) {}
      });
}
