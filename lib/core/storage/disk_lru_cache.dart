import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:document_studio/core/storage/storage_paths.dart';
import 'package:path/path.dart' as p;

/// Stable 64-bit FNV-1a hex digest (cache file names; not for security).
String storageKeyHash(String s) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
  }
  final hi = (h >>> 32).toRadixString(16).padLeft(8, '0');
  final lo = (h & 0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
  return '$hi$lo';
}

/// Size-capped file cache in one [StorageArea], evicting least recently used
/// entries (mtime is bumped on every hit).
class DiskLruCache {
  DiskLruCache(this.area, {required this.maxBytes, this.extension = 'bin'});

  final StorageArea area;
  final int maxBytes;
  final String extension;

  int _writtenSinceTrim = 0;
  bool _trimming = false;

  Directory? get _dir => StoragePaths.maybeInstance?.dir(area);

  File? _file(String key) {
    final dir = _dir;
    if (dir == null) return null;
    return File(p.join(dir.path, '${storageKeyHash(key)}.$extension'));
  }

  Future<Uint8List?> read(String key) async {
    final f = _file(key);
    if (f == null) return null;
    try {
      final bytes = await f.readAsBytes();
      unawaited(f.setLastModified(DateTime.now()).catchError((Object _) {}));
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    final f = _file(key);
    if (f == null) return;
    final tmp = File('${f.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    try {
      await f.parent.create(recursive: true);
      await tmp.writeAsBytes(bytes);
      await tmp.rename(f.path);
    } catch (_) {
      try {
        await tmp.delete();
      } catch (_) {}
      return;
    }
    _writtenSinceTrim += bytes.length;
    if (_writtenSinceTrim > maxBytes ~/ 10) {
      _writtenSinceTrim = 0;
      unawaited(trim());
    }
  }

  /// Deletes oldest entries until the area is under 80% of [maxBytes].
  Future<int> trim() async {
    final dir = _dir;
    if (dir == null || _trimming) return 0;
    _trimming = true;
    try {
      return await trimDirectoryLru(dir.path, maxBytes);
    } finally {
      _trimming = false;
    }
  }
}

/// LRU-trims [dirPath] to 80% of [maxBytes] in a background isolate.
/// Returns freed bytes.
Future<int> trimDirectoryLru(String dirPath, int maxBytes) {
  return Isolate.run(() {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return 0;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      try {
        final st = e.statSync();
        files.add((e, st.size, st.modified));
        total += st.size;
      } catch (_) {}
    }
    if (total <= maxBytes) return 0;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    final target = (maxBytes * 0.8).round();
    var freed = 0;
    for (final (file, size, _) in files) {
      if (total - freed <= target) break;
      try {
        file.deleteSync();
        freed += size;
      } catch (_) {}
    }
    return freed;
  });
}
