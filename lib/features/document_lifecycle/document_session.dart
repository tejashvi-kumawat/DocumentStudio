import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/core/session/dirty_aware.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Result of attempting to replace the open document on disk.
enum DocumentSaveOutcome {
  /// Working copy updated (Apply) or source file written (Save).
  savedInPlace,

  /// Path is not writable; caller should offer Save As with pending bytes.
  needsSaveAs,

  /// User cancelled a Save As fallback.
  cancelled,
}

/// Per-open-document edit stream: undo/redo snapshots + dirty working copy.
///
/// Owned by a viewer tab. On open we prefer a **hardlink** (or reflink) of the
/// source into a session temp path — never a full byte copy of a large book
/// (that dominated open time and filled disk quota / EDQUOT). Apply writes only
/// the working file after breaking any hardlink so the user's original is
/// unchanged until explicit [save]/[saveAs].
class DocumentSession extends ChangeNotifier implements DirtyAware {
  DocumentSession({
    required LocalFileRef file,
    this._password,
    this.maxUndoLevels = 10,
  })  : _sourcePath = LinuxDocumentPortal.resolveSync(file.path),
        _sourceDisplayName = file.displayName {
    final source = _sourcePath == file.path
        ? file
        : file.copyWithPath(_sourcePath);
    _materializeWorkingLink(source);
  }

  final int maxUndoLevels;

  /// Absolute path of the user's original file (Save target / identity).
  String _sourcePath;
  String _sourceDisplayName;

  late LocalFileRef _file;
  String? _password;
  bool _dirty = false;
  int _revision = 0;
  final List<Uint8List> _undo = [];
  final List<Uint8List> _redo = [];

  Directory? _workingDir;
  String? _workingPath;

  /// True when [_workingPath] shares an inode with [_sourcePath] (hardlink /
  /// successful reflink). Must be cleared before any Apply write.
  bool _workingIsLinked = false;

  /// Bytes from the last Save that could not replace in place.
  Uint8List? pendingReplaceBytes;

  /// User-facing / Save-target path (unchanged by Apply).
  String get sourcePath => _sourcePath;

  /// Stable identity for Recents / thumbnails (never a session temp path).
  LocalFileRef get sourceFile => LocalFileRef(
        path: _sourcePath,
        displayName: _sourceDisplayName,
        sizeBytes: _file.path == _sourcePath ? _file.sizeBytes : null,
        lastModified: _file.path == _sourcePath ? _file.lastModified : null,
      );

  LocalFileRef get file => _file;
  String? get password => _password;
  @override
  bool get isDirty => _dirty;
  int get revision => _revision;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoDepth => _undo.length;
  int get redoDepth => _redo.length;

  /// True when [path] is this session's working file or original source.
  bool sameDocumentPath(String path) =>
      path == _file.path || path == _sourcePath;

  set password(String? value) {
    if (_password == value) return;
    _password = value;
    notifyListeners();
  }

  static String _safeFileName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^\w.\- ]+'), '_').trim();
    if (cleaned.isEmpty) return 'document.pdf';
    return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
  }

  /// Session open: link the source into `ds_sess_*` when possible.
  ///
  /// Why link instead of copy: a full `File.copy` of a large PDF before first
  /// paint made open feel multi-second and burned user disk quota (EDQUOT). A
  /// hardlink (same filesystem) or `cp --reflink=always` is O(1) metadata; the
  /// viewer still gets a distinct working path for Apply/Save. If both fail we
  /// view the source until the first mutation, then copy bytes once.
  void _materializeWorkingLink(LocalFileRef source) {
    Directory? dir;
    try {
      dir = Directory.systemTemp.createTempSync('ds_sess_');
      final workPath = p.join(dir.path, _safeFileName(source.displayName));
      final linked = _tryHardlink(source.path, workPath) ||
          _tryReflink(source.path, workPath);
      if (linked) {
        final st = File(workPath).statSync();
        _workingDir = dir;
        _workingPath = workPath;
        _workingIsLinked = true;
        _file = LocalFileRef(
          path: workPath,
          displayName: source.displayName,
          sizeBytes: st.size,
          lastModified: st.modified,
        );
        return;
      }
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
      _workingDir = null;
      _workingPath = null;
      _workingIsLinked = false;
      _file = source;
    } catch (_) {
      try {
        dir?.deleteSync(recursive: true);
      } catch (_) {}
      _workingDir = null;
      _workingPath = null;
      _workingIsLinked = false;
      _file = source;
    }
  }

  /// Same-filesystem hardlink (`ln` / `mklink /H`). Instant; Apply must
  /// [_breakWorkingLink] first so writes do not mutate the original inode.
  static bool _tryHardlink(String src, String dest) {
    try {
      if (Platform.isWindows) {
        final r = Process.runSync('cmd', ['/c', 'mklink', '/H', dest, src]);
        return r.exitCode == 0 && File(dest).existsSync();
      }
      final r = Process.runSync('ln', [src, dest]);
      return r.exitCode == 0 && File(dest).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Linux CoW clone when the FS supports it (`cp --reflink=always`). Fails
  /// closed instead of silently full-copying (`--reflink=auto`).
  static bool _tryReflink(String src, String dest) {
    if (!Platform.isLinux) return false;
    try {
      final r = Process.runSync('cp', ['--reflink=always', src, dest]);
      return r.exitCode == 0 && File(dest).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Creates the session temp on first mutation when open used the source
  /// path, or detaches a hardlink/reflink so Apply cannot overwrite source.
  Future<void> _ensureWorkingPath() async {
    if (_workingPath != null) {
      if (_workingIsLinked) await _breakWorkingLink();
      return;
    }
    final dir = await Directory.systemTemp.createTemp('ds_sess_');
    final workPath = p.join(dir.path, _safeFileName(_sourceDisplayName));
    await File(_file.path).copy(workPath);
    _workingDir = dir;
    _workingPath = workPath;
    _workingIsLinked = false;
  }

  /// Copy-on-write: replace a hardlinked working file with its own inode.
  Future<void> _breakWorkingLink() async {
    final work = _workingPath;
    if (work == null || !_workingIsLinked) return;
    final tmp = '$work.${DateTime.now().microsecondsSinceEpoch}.cow';
    try {
      await File(work).copy(tmp);
      await File(work).delete();
      await File(tmp).rename(work);
    } catch (_) {
      try {
        await File(tmp).delete();
      } catch (_) {}
      // Last resort: rewrite bytes to force a new inode.
      final bytes = await File(work).readAsBytes();
      await File(work).writeAsBytes(bytes, flush: true);
    }
    _workingIsLinked = false;
  }

  /// Rebinds the session to a different on-disk path (Save As success).
  void rebindFile(LocalFileRef file, {String? password}) {
    _disposeWorkingDir();
    final resolved = LinuxDocumentPortal.resolveSync(file.path);
    _sourcePath = resolved;
    _sourceDisplayName = file.displayName;
    if (password != null) _password = password;
    final source =
        resolved == file.path ? file : file.copyWithPath(resolved);
    _materializeWorkingLink(source);
    _dirty = false;
    pendingReplaceBytes = null;
    _revision++;
    notifyListeners();
  }

  Future<Uint8List> _readCurrentBytes() async {
    try {
      return await File(_file.path).readAsBytes();
    } on FileSystemException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.fileNotFound,
        message: 'Could not read $_sourceDisplayName',
        cause: e,
        recoveryHint: 'Re-open the file and try again.',
      );
    }
  }

  /// Public read of the current working (or source) document bytes.
  Future<Uint8List> readCurrentBytes() => _readCurrentBytes();

  void _pushUndoBytes(Uint8List bytes) {
    _undo.add(bytes);
    while (_undo.length > maxUndoLevels) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  Future<bool> _canReplacePath(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      final raf = await f.open(mode: FileMode.append);
      await raf.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBytesToPath(String path, Uint8List bytes) async {
    final dir = p.dirname(path);
    await Directory(dir).create(recursive: true);
    final tempPath = p.join(
      dir,
      '.${p.basename(path)}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    try {
      await File(tempPath).writeAsBytes(bytes, flush: true);
      try {
        await File(tempPath).rename(path);
      } on FileSystemException {
        await File(path).writeAsBytes(bytes, flush: true);
        try {
          await File(tempPath).delete();
        } catch (_) {}
      }
    } catch (e) {
      try {
        await File(tempPath).delete();
      } catch (_) {}
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.permissionDenied,
        message: 'Could not write to $path',
        cause: e,
        recoveryHint: 'The file may be read-only. Use Save As.',
      );
    }
  }

  Future<void> _refreshFileMeta() async {
    try {
      final st = await File(_file.path).stat();
      _file = LocalFileRef(
        path: _file.path,
        displayName: _sourceDisplayName,
        sizeBytes: st.size,
        lastModified: st.modified,
      );
    } catch (_) {}
  }

  Future<void> _writeWorkingBytes(Uint8List bytes) async {
    await _ensureWorkingPath();
    final work = _workingPath!;
    await _writeBytesToPath(work, bytes);
    _file = LocalFileRef(
      path: work,
      displayName: _sourceDisplayName,
      sizeBytes: bytes.length,
      lastModified: DateTime.now(),
    );
  }

  /// Snapshot current bytes, apply [bytes] to the working copy. Marks dirty.
  ///
  /// Never writes [sourcePath]. Soft-reload the viewer from [file] afterward.
  Future<DocumentSaveOutcome> commitBytes(Uint8List bytes) async {
    final prior = await _readCurrentBytes();
    try {
      await _writeWorkingBytes(bytes);
    } on DocumentStudioError {
      pendingReplaceBytes = bytes;
      return DocumentSaveOutcome.needsSaveAs;
    }
    _pushUndoBytes(prior);
    pendingReplaceBytes = null;
    _dirty = true;
    _revision++;
    await _refreshFileMeta();
    notifyListeners();
    return DocumentSaveOutcome.savedInPlace;
  }

  /// Snapshot current file, then replace working copy with contents of [tempPath].
  Future<DocumentSaveOutcome> commitTempFile(String tempPath) async {
    final bytes = Uint8List.fromList(await File(tempPath).readAsBytes());
    final outcome = await commitBytes(bytes);
    try {
      await File(tempPath).delete();
    } catch (_) {}
    return outcome;
  }

  /// Clears dirty after the user confirms Save (bytes already on source).
  void markSaved() {
    if (!_dirty && pendingReplaceBytes == null) return;
    _dirty = false;
    pendingReplaceBytes = null;
    notifyListeners();
  }

  /// Explicit Save: write working bytes to [sourcePath] and clear dirty.
  Future<DocumentSaveOutcome> save() async {
    final pending = pendingReplaceBytes;
    final bytes = pending ?? (_dirty ? await _readCurrentBytes() : null);
    if (bytes == null) return DocumentSaveOutcome.savedInPlace;

    final writable = await _canReplacePath(_sourcePath);
    if (!writable) {
      pendingReplaceBytes = bytes;
      return DocumentSaveOutcome.needsSaveAs;
    }
    try {
      await _writeBytesToPath(_sourcePath, bytes);
    } on DocumentStudioError {
      pendingReplaceBytes = bytes;
      return DocumentSaveOutcome.needsSaveAs;
    }
    markSaved();
    return DocumentSaveOutcome.savedInPlace;
  }

  /// Save As: write current (or pending) bytes to a new path and rebind.
  Future<LocalFileRef?> saveAs(
    FileStoragePort storage, {
    String? suggestedName,
  }) async {
    final bytes = pendingReplaceBytes ?? await _readCurrentBytes();
    final priorForUndo =
        pendingReplaceBytes != null ? await _readCurrentBytes() : null;
    final savePath = await storage.pickSavePath(
      suggestedName: suggestedName ?? _sourceDisplayName,
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (savePath == null) return null;
    await storage.writeAtomic(
      destinationPath: savePath,
      writeToTemp: (temp) async {
        await File(temp).writeAsBytes(bytes, flush: true);
      },
    );
    if (priorForUndo != null) {
      _pushUndoBytes(priorForUndo);
    }
    final ref = LocalFileRef(
      path: savePath,
      displayName: p.basename(savePath),
    );
    rebindFile(ref);
    return ref;
  }

  Future<bool> undo() async {
    if (_undo.isEmpty) return false;
    final current = await _readCurrentBytes();
    final prior = _undo.removeLast();
    _redo.add(current);
    await _writeWorkingBytes(prior);
    _dirty = _undo.isNotEmpty;
    pendingReplaceBytes = null;
    _revision++;
    await _refreshFileMeta();
    notifyListeners();
    return true;
  }

  Future<bool> redo() async {
    if (_redo.isEmpty) return false;
    final current = await _readCurrentBytes();
    final next = _redo.removeLast();
    _undo.add(current);
    while (_undo.length > maxUndoLevels) {
      _undo.removeAt(0);
    }
    await _writeWorkingBytes(next);
    _dirty = true;
    pendingReplaceBytes = null;
    _revision++;
    await _refreshFileMeta();
    notifyListeners();
    return true;
  }

  void _disposeWorkingDir() {
    final dir = _workingDir;
    _workingDir = null;
    _workingPath = null;
    _workingIsLinked = false;
    if (dir == null) return;
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// Drops the working-copy temp directory. Call when the tab closes.
  @override
  void dispose() {
    _disposeWorkingDir();
    super.dispose();
  }
}
