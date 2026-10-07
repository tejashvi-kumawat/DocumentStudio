import 'dart:convert';
import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

class RecentFilesRepository {
  RecentFilesRepository(this._prefs);

  static const _key = 'recent_files_v1';
  static const maxRecents = 30;

  final SharedPreferences _prefs;

  static Future<RecentFilesRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return RecentFilesRepository(prefs);
  }

  /// Session working copies live under `…/ds_sess_<id>/name.pdf` (app temp).
  /// Those must never appear in Recents — only the user's real source file.
  static bool isSessionWorkingCopyPath(String path) {
    final normalized = path.replaceAll(r'\', '/');
    return normalized.contains('/ds_sess_');
  }

  /// Identity when paths differ (portal vs host vs leftover aliases):
  /// lowercased basename + size + mtime millis.
  static Future<String?> contentIdentityKey(String path) async {
    try {
      final st = await File(path).stat();
      final name = p.basename(path).toLowerCase();
      return '$name|${st.size}|${st.modified.millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }

  /// Keeps list order (newest first). Drops session temps. Collapses entries
  /// that share a [path] or the same [contentIdentityKey].
  static Future<List<LocalFileRef>> collapseDuplicates(
    List<LocalFileRef> input,
  ) async {
    final seenPaths = <String>{};
    final seenContent = <String>{};
    final out = <LocalFileRef>[];
    for (final f in input) {
      if (isSessionWorkingCopyPath(f.path)) continue;
      if (!seenPaths.add(f.path)) continue;
      final contentKey = await contentIdentityKey(f.path);
      if (contentKey != null && !seenContent.add(contentKey)) continue;
      out.add(f);
    }
    if (out.length > maxRecents) {
      return out.sublist(0, maxRecents);
    }
    return out;
  }

  List<LocalFileRef> load() {
    final raw = _prefs.getStringList(_key) ?? [];
    return raw
        .map((e) {
          try {
            final map = jsonDecode(e) as Map<String, dynamic>;
            return LocalFileRef(
              path: map['path'] as String,
              displayName: map['name'] as String,
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<LocalFileRef>()
        .toList();
  }

  Future<void> add(LocalFileRef ref) async {
    if (isSessionWorkingCopyPath(ref.path)) return;
    final contentKey = await contentIdentityKey(ref.path);
    final list = load();
    final kept = <LocalFileRef>[];
    for (final f in list) {
      if (f.path == ref.path) continue;
      if (isSessionWorkingCopyPath(f.path)) continue;
      if (contentKey != null) {
        final otherKey = await contentIdentityKey(f.path);
        if (otherKey != null && otherKey == contentKey) continue;
      }
      kept.add(f);
    }
    kept.insert(0, ref);
    if (kept.length > maxRecents) {
      kept.removeRange(maxRecents, kept.length);
    }
    await _save(kept);
  }

  Future<void> remove(String path) async {
    final contentKey = await contentIdentityKey(path);
    final kept = <LocalFileRef>[];
    for (final f in load()) {
      if (f.path == path) continue;
      if (contentKey != null) {
        final otherKey = await contentIdentityKey(f.path);
        if (otherKey != null && otherKey == contentKey) continue;
      }
      kept.add(f);
    }
    await _save(kept);
  }

  Future<void> clear() => _prefs.remove(_key);

  Future<void> replaceAll(List<LocalFileRef> list) => _save(list);

  Future<void> _save(List<LocalFileRef> list) async {
    await _prefs.setStringList(
      _key,
      list
          .map((f) => jsonEncode({'path': f.path, 'name': f.displayName}))
          .toList(),
    );
  }
}
