import 'dart:convert';
import 'dart:io';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One folder the user granted via Android Storage Access Framework.
class PersistedFolderGrant {
  const PersistedFolderGrant({
    required this.treeUri,
    required this.displayName,
  });

  final String treeUri;
  final String displayName;

  Map<String, String> toJson() => {'uri': treeUri, 'name': displayName};

  static PersistedFolderGrant? fromJson(Map<String, dynamic> map) {
    final uri = map['uri'] as String?;
    final name = map['name'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return PersistedFolderGrant(
      treeUri: uri,
      displayName: (name == null || name.isEmpty) ? 'Granted folder' : name,
    );
  }
}

/// Remembers Android tree URIs (persistable) and lists PDFs without copying them.
class PersistedDocumentAccess {
  PersistedDocumentAccess._();

  static const _channel = MethodChannel('document_studio/saf');
  static const _prefsKey = 'persisted_saf_folders_v1';

  static Future<List<PersistedFolderGrant>> loadGrants() async {
    if (!Platform.isAndroid) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? const [];
    final out = <PersistedFolderGrant>[];
    for (final e in raw) {
      try {
        final map = jsonDecode(e) as Map<String, dynamic>;
        final g = PersistedFolderGrant.fromJson(map);
        if (g != null) out.add(g);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> saveGrants(List<PersistedFolderGrant> grants) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefsKey,
      grants.map((g) => jsonEncode(g.toJson())).toList(),
    );
  }

  /// Opens the system folder picker and takes persistable URI permission.
  static Future<PersistedFolderGrant?> pickPersistableFolder() async {
    if (!Platform.isAndroid) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'pickPersistableFolder',
      );
      if (result == null) return null;
      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return PersistedFolderGrant(
        treeUri: uri,
        displayName: (result['name'] as String?)?.trim().isNotEmpty == true
            ? result['name'] as String
            : 'Granted folder',
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Lists PDF documents under a previously granted tree URI (paths = content URIs).
  static Future<List<LocalFileRef>> listPdfsInFolder(String treeUri) async {
    if (!Platform.isAndroid) return const [];
    try {
      final rows = await _channel.invokeListMethod<dynamic>(
        'listPdfsInFolder',
        {'uri': treeUri},
      );
      if (rows == null) return const [];
      final out = <LocalFileRef>[];
      for (final row in rows) {
        if (row is! Map) continue;
        final uri = row['uri']?.toString();
        final name = row['name']?.toString();
        if (uri == null || uri.isEmpty) continue;
        out.add(
          LocalFileRef(
            path: uri,
            displayName: (name == null || name.isEmpty) ? 'document.pdf' : name,
            contentUri: uri,
          ),
        );
      }
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Copies a content:// PDF into app cache and returns a filesystem [LocalFileRef].
  ///
  /// Call this only when opening for edit/render — listing keeps the URI only.
  static Future<LocalFileRef?> materializeForOpen(LocalFileRef ref) async {
    final uri =
        ref.contentUri ?? (ref.path.startsWith('content://') ? ref.path : null);
    if (uri == null) return ref;
    if (!Platform.isAndroid) return ref;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'copyContentUriToCache',
        {'uri': uri, 'name': ref.displayName},
      );
      final path = result?['path'] as String?;
      if (path == null || path.isEmpty) return null;
      return LocalFileRef(
        path: path,
        displayName: ref.displayName,
        contentUri: uri,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}

class PersistedDocumentGrantsNotifier
    extends AsyncNotifier<List<PersistedFolderGrant>> {
  @override
  Future<List<PersistedFolderGrant>> build() =>
      PersistedDocumentAccess.loadGrants();

  Future<void> addGrant(PersistedFolderGrant grant) async {
    final current = List<PersistedFolderGrant>.of(
      state.asData?.value ?? await PersistedDocumentAccess.loadGrants(),
    );
    current.removeWhere((g) => g.treeUri == grant.treeUri);
    current.insert(0, grant);
    await PersistedDocumentAccess.saveGrants(current);
    state = AsyncData(current);
  }

  Future<void> removeGrant(String treeUri) async {
    final current = List<PersistedFolderGrant>.of(
      state.asData?.value ?? await PersistedDocumentAccess.loadGrants(),
    )..removeWhere((g) => g.treeUri == treeUri);
    await PersistedDocumentAccess.saveGrants(current);
    state = AsyncData(current);
  }
}

final persistedDocumentGrantsProvider =
    AsyncNotifierProvider<
      PersistedDocumentGrantsNotifier,
      List<PersistedFolderGrant>
    >(PersistedDocumentGrantsNotifier.new);
