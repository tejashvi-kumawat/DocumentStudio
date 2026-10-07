import 'dart:convert';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pinned documents for home favorites ([DS-READ-001-C] partial — paths only, no SAF URI).
class FavoriteFilesRepository {
  FavoriteFilesRepository(this._prefs);

  static const _key = 'favorite_files_v1';
  static const maxFavorites = 50;

  final SharedPreferences _prefs;

  static Future<FavoriteFilesRepository> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FavoriteFilesRepository(prefs);
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

  bool isFavorite(String path) {
    return load().any((f) => f.path == path);
  }

  Future<void> toggle(LocalFileRef ref) async {
    final list = load();
    final index = list.indexWhere((f) => f.path == ref.path);
    if (index >= 0) {
      list.removeAt(index);
    } else {
      list.insert(0, ref);
      if (list.length > maxFavorites) {
        list.removeRange(maxFavorites, list.length);
      }
    }
    await _prefs.setStringList(
      _key,
      list
          .map((f) => jsonEncode({'path': f.path, 'name': f.displayName}))
          .toList(),
    );
  }
}
