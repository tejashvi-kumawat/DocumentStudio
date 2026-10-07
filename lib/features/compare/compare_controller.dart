import 'dart:async';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/compare/compare_models.dart';
import 'package:document_studio/domain/compare/compare_runner.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compare/compare_visual_diff.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compare_extractor.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

class CompareSource {
  const CompareSource(this.file, {this.password});

  final LocalFileRef file;
  final String? password;

  CompareSource withPassword(String? password) =>
      CompareSource(file, password: password);
}

enum CompareStage {
  readingOld('Reading original document'),
  readingNew('Reading revised document'),
  analyzing('Aligning pages & diffing words'),
  done('Done'),
  failed('Failed'),
  cancelled('Cancelled');

  const CompareStage(this.label);

  final String label;
}

enum CompareViewMode { sideBySide, overlay }

enum CompareOverlayMode { swipe, onion, heatmap }

/// Orchestrates extraction (pdfrx PDFium worker), analysis (dedicated
/// isolate) and the view state shared by the workspace widgets.
///
/// High-frequency values (progress, overlay slider) live in [ValueNotifier]s
/// so pointer moves don't rebuild the workspace.
class CompareController extends ChangeNotifier {
  CompareController({required this.oldSource, required this.newSource});

  CompareSource oldSource;
  CompareSource newSource;

  CompareStage stage = CompareStage.readingOld;
  final progress = ValueNotifier<double>(0);
  String? error;

  /// Set when a run failed because a document needs a password.
  bool? lockedIsOld;
  CompareResult? result;
  PdfDocument? oldPdf;
  PdfDocument? newPdf;
  CompareVisualDiffer? visual;

  final Set<CompareCategory> filters = CompareCategory.values.toSet();
  int? selectedId;
  CompareViewMode viewMode = CompareViewMode.sideBySide;
  CompareOverlayMode overlayMode = CompareOverlayMode.swipe;

  /// Swipe divider position / onion-skin opacity of the revised page (0..1).
  final overlayMix = ValueNotifier<double>(0.5);
  double zoom = 1;

  /// Row shown in overlay mode.
  int overlayRow = 0;

  CompareCancelToken? _token;
  var _disposed = false;
  List<CompareChange> _visible = const [];
  Map<int, List<CompareChange>> _byRow = const {};

  bool get running =>
      stage == CompareStage.readingOld ||
      stage == CompareStage.readingNew ||
      stage == CompareStage.analyzing;

  List<CompareChange> get visibleChanges => _visible;

  List<CompareChange> changesOnRow(int row) => _byRow[row] ?? const [];

  CompareChange? get selected {
    final id = selectedId;
    final r = result;
    if (id == null || r == null || id >= r.changes.length) return null;
    return r.changes[id];
  }

  int get selectedVisibleIndex {
    final s = selectedId;
    if (s == null) return -1;
    return _visible.indexWhere((c) => c.id == s);
  }

  /// Whether [c] can be detected with the current extraction backend.
  bool categoryAvailable(CompareCategory c) {
    final r = result;
    if (r == null) return true;
    return switch (c) {
      CompareCategory.formatting => r.formattingAvailable,
      CompareCategory.images => r.imagesAvailable,
      _ => true,
    };
  }

  Future<void> run() async {
    _token?.cancel();
    final token = _token = CompareCancelToken();
    _closeDocs();
    result = null;
    error = null;
    lockedIsOld = null;
    selectedId = null;
    overlayRow = 0;
    stage = CompareStage.readingOld;
    progress.value = 0;
    notifyListeners();

    final oldDocFuture = _open(oldSource);
    final newDocFuture = _open(newSource);
    // Keep failures of the display documents from surfacing as unhandled.
    unawaited(oldDocFuture.then((_) {}, onError: (Object _) {}));
    unawaited(newDocFuture.then((_) {}, onError: (Object _) {}));
    try {
      final extractor = PdfCompareExtractor.instance;
      final a = await _extract(extractor, oldSource, true, token);
      token.throwIfCancelled();
      stage = CompareStage.readingNew;
      notifyListeners();
      final b = await _extract(extractor, newSource, false, token);
      token.throwIfCancelled();
      stage = CompareStage.analyzing;
      progress.value = 0.8;
      notifyListeners();
      final res = await runCompareInIsolate(
        a,
        b,
        token: token,
        onProgress: (p) {
          if (!token.isCancelled) progress.value = 0.8 + 0.2 * p;
        },
      );
      final docs = await Future.wait([oldDocFuture, newDocFuture]);
      if (token.isCancelled || _disposed) {
        for (final d in docs) {
          unawaited(d.dispose());
        }
        return;
      }
      oldPdf = docs[0];
      newPdf = docs[1];
      visual = CompareVisualDiffer(docs[0], docs[1]);
      result = res;
      stage = CompareStage.done;
      progress.value = 1;
      _rebuildVisible();
      notifyListeners();
    } on CompareCancelled {
      _disposeLater(oldDocFuture);
      _disposeLater(newDocFuture);
    } catch (e) {
      _disposeLater(oldDocFuture);
      _disposeLater(newDocFuture);
      if (token.isCancelled || _disposed) return;
      stage = CompareStage.failed;
      error = e is DocumentStudioError ? (e.recoveryHint ?? e.message) : '$e';
      notifyListeners();
    }
  }

  Future<CompareDocData> _extract(
    PdfCompareExtractor extractor,
    CompareSource source,
    bool isOld,
    CompareCancelToken token,
  ) async {
    try {
      return await extractor.extract(
        source.file.path,
        password: source.password,
        token: token,
        onProgress: (d, t) {
          if (token.isCancelled) return;
          final f = t <= 0 ? 1.0 : d / t;
          progress.value = isOld ? f * 0.4 : 0.4 + f * 0.4;
        },
      );
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired) {
        lockedIsOld = isOld;
      }
      rethrow;
    }
  }

  void _disposeLater(Future<PdfDocument> f) {
    unawaited(f.then((d) => d.dispose(), onError: (Object _) {}));
  }

  /// Retries after the user entered a password for the locked document.
  Future<void> unlock(String password) {
    if (lockedIsOld ?? true) {
      oldSource = oldSource.withPassword(password);
    } else {
      newSource = newSource.withPassword(password);
    }
    return run();
  }

  void cancel() {
    if (!running) return;
    _token?.cancel();
    stage = CompareStage.cancelled;
    notifyListeners();
  }

  Future<PdfDocument> _open(CompareSource s) => PdfDocument.openFile(
    s.file.path,
    passwordProvider: s.password == null ? null : () => s.password,
  );

  Future<void> swap() async {
    final t = oldSource;
    oldSource = newSource;
    newSource = t;
    await run();
  }

  void toggleFilter(CompareCategory c) {
    if (filters.contains(c)) {
      if (filters.length == 1) {
        filters.addAll(CompareCategory.values);
      } else {
        filters.remove(c);
      }
    } else {
      filters.add(c);
    }
    _rebuildVisible();
    notifyListeners();
  }

  void showOnly(CompareCategory c) {
    filters
      ..clear()
      ..add(c);
    _rebuildVisible();
    notifyListeners();
  }

  void showAll() {
    filters.addAll(CompareCategory.values);
    _rebuildVisible();
    notifyListeners();
  }

  void select(int? id) {
    selectedId = id;
    final c = selected;
    if (c != null) overlayRow = rowForChange(c);
    notifyListeners();
  }

  /// Row to reveal for [c]: the old-side row unless the change only exists
  /// in the revised document.
  int rowForChange(CompareChange c) {
    final r = result;
    if (r == null) return c.row;
    final useOld = c.aRects.isNotEmpty && c.kind != CompareChangeKind.inserted;
    final page = useOld
        ? c.aRects.keys.first
        : (c.bRects.isNotEmpty ? c.bRects.keys.first : null);
    if (page == null) return c.row;
    return (useOld ? r.rowOfA[page] : r.rowOfB[page]) ?? c.row;
  }

  /// Selects the next (+1) / previous (-1) visible change, wrapping around.
  CompareChange? step(int delta) {
    if (_visible.isEmpty) return null;
    final i = selectedVisibleIndex;
    final n = _visible.length;
    final next = i < 0 ? (delta > 0 ? 0 : n - 1) : ((i + delta) % n + n) % n;
    final c = _visible[next];
    select(c.id);
    return c;
  }

  void setViewMode(CompareViewMode m) {
    if (viewMode == m) return;
    viewMode = m;
    notifyListeners();
  }

  void setOverlayMode(CompareOverlayMode m) {
    if (overlayMode == m) return;
    overlayMode = m;
    notifyListeners();
  }

  void setOverlayRow(int row) {
    final r = result;
    if (r == null || r.rows.isEmpty) return;
    final next = row.clamp(0, r.rows.length - 1);
    if (next == overlayRow) return;
    overlayRow = next;
    notifyListeners();
  }

  void setZoom(double z) {
    final next = z.clamp(0.5, 4.0);
    if ((next - zoom).abs() < 0.001) return;
    zoom = next;
    notifyListeners();
  }

  void _rebuildVisible() {
    final r = result;
    if (r == null) {
      _visible = const [];
      _byRow = const {};
      return;
    }
    _visible = [
      for (final c in r.changes)
        if (filters.contains(c.category)) c,
    ];
    final byRow = <int, List<CompareChange>>{};
    for (final c in _visible) {
      final rows = <int>{c.row};
      for (final p in c.aRects.keys) {
        final row = r.rowOfA[p];
        if (row != null) rows.add(row);
      }
      for (final p in c.bRects.keys) {
        final row = r.rowOfB[p];
        if (row != null) rows.add(row);
      }
      for (final row in rows) {
        (byRow[row] ??= []).add(c);
      }
    }
    _byRow = byRow;
    if (selectedId != null && !_visible.any((c) => c.id == selectedId)) {
      selectedId = null;
    }
  }

  void _closeDocs() {
    visual?.dispose();
    visual = null;
    final a = oldPdf;
    final b = newPdf;
    oldPdf = null;
    newPdf = null;
    if (a != null) unawaited(a.dispose());
    if (b != null) unawaited(b.dispose());
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _token?.cancel();
    _closeDocs();
    progress.dispose();
    overlayMix.dispose();
    super.dispose();
  }
}
