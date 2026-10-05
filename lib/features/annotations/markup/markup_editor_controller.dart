import 'package:document_studio/core/settings/app_prefs.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/features/annotations/markup/markup_painter.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_markup_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Writes new PDF bytes into the open document (in place, with undo).
/// Returns false when the write didn't happen (e.g. user cancelled Save As).
typedef MarkupCommitter = Future<bool> Function(Uint8List bytes);

/// Revisions produced by markup saves. The rendered page content doesn't
/// change on those (the viewer draws markup itself), so the viewer skips its
/// reload and nothing blinks.
abstract final class MarkupOwnRevisions {
  static final Map<String, int> _byPath = {};

  static void mark(String path, int revision) => _byPath[path] = revision;

  static bool isOwn(String path, int revision) => _byPath[path] == revision;
}

class _Snapshot {
  const _Snapshot(this.pages, this.deletedForeign);
  final Map<int, List<MarkupObject>> pages;
  final Map<int, Set<int>> deletedForeign;
}

/// State of the on-page markup editor for the active document: objects per
/// page (z-ordered), selection, tools, style, undo/redo, clipboard and
/// autosave into real PDF annotations.
class MarkupEditorController extends ChangeNotifier {
  MarkupEditorController();

  // ------------------------------------------------------------ document

  DocumentSession? _session;
  MarkupCommitter? _commit;
  String? _path;
  int _knownRevision = -1;
  bool _loading = false;
  String? _loadError;
  bool _readOnly = false;
  int _loadSeq = 0;

  final Map<int, List<MarkupObject>> _pages = {};
  final Map<int, PdfPageGeometry> _geometry = {};
  List<ForeignAnnotation> _foreign = const [];
  final Map<int, Set<int>> _adoptedByPage = {};
  final Map<int, Set<int>> _deletedForeign = {};

  String? get path => _path;
  bool get loading => _loading;
  String? get loadError => _loadError;

  /// Encrypted / unparsable PDFs: markup is shown but can't be saved.
  bool get readOnly => _readOnly;
  DocumentSession? get session => _session;

  PdfPageGeometry? geometryOf(int page) => _geometry[page];

  List<MarkupObject> objectsOn(int page) => _pages[page] ?? const [];

  Iterable<int> get pagesWithObjects =>
      _pages.keys.where((p) => _pages[p]!.isNotEmpty);

  List<ForeignAnnotation> get foreign => [
    for (final f in _foreign)
      if (f.refNum == null ||
          !(_deletedForeign[f.page]?.contains(f.refNum) ?? false))
        f,
  ];

  int get objectCount =>
      _pages.values.fold(0, (n, l) => n + l.length) + foreign.length;

  MarkupObject? objectById(String id) {
    for (final list in _pages.values) {
      for (final o in list) {
        if (o.id == id) return _preview[id] ?? o;
      }
    }
    return null;
  }

  /// Binds to [session] (the active viewer tab). Safe to call every build.
  void bind(DocumentSession? session, {required MarkupCommitter commit}) {
    if (!identical(session, _session)) {
      // Pending edits belong to the previous document and its committer.
      final hadPending = _dirtyPages.isNotEmpty || _deletedDirty;
      if (hadPending) unawaited(flush());
    }
    _commit = commit;
    if (identical(session, _session) &&
        session?.file.path == _path &&
        session?.revision == _knownRevision) {
      return;
    }
    if (!identical(session, _session)) {
      _session?.removeListener(_onSessionChanged);
      _session = session;
      session?.addListener(_onSessionChanged);
      _resetForNewDocument();
    }
    if (session == null) {
      _path = null;
      notifyListeners();
      return;
    }
    _onSessionChanged();
  }

  void _resetForNewDocument() {
    _pages.clear();
    _geometry.clear();
    _foreign = const [];
    _adoptedByPage.clear();
    _deletedForeign.clear();
    _undo.clear();
    _redo.clear();
    _selection.clear();
    _editingId = null;
    _preview.clear();
    _dirtyPages.clear();
    _deletedDirty = false;
    _loadError = null;
    _readOnly = false;
    _knownRevision = -1;
  }

  void _onSessionChanged() {
    final s = _session;
    if (s == null) return;
    final pathChanged = s.file.path != _path;
    if (!pathChanged && s.revision == _knownRevision) return;
    if (!pathChanged && MarkupOwnRevisions.isOwn(s.file.path, s.revision)) {
      _knownRevision = s.revision;
      return;
    }
    _path = s.file.path;
    _knownRevision = s.revision;
    unawaited(_reload());
  }

  Future<void> _reload() async {
    final s = _session;
    if (s == null) return;
    final seq = ++_loadSeq;
    _loading = true;
    notifyListeners();
    MarkupLoadResult result;
    try {
      final bytes = await s.readCurrentBytes();
      result = await runIsolated(loadMarkupFromPdf, bytes);
    } catch (e) {
      result = MarkupLoadResult.empty('$e');
    }
    if (seq != _loadSeq || !identical(s, _session)) return;
    _loading = false;
    _pages.clear();
    for (final o in result.objects) {
      (_pages[o.page] ??= []).add(o);
    }
    _geometry
      ..clear()
      ..addAll(result.geometry);
    _foreign = result.foreign;
    _adoptedByPage.clear();
    for (final e in result.adoptedRefs.entries) {
      final page = result.objects.firstWhere((o) => o.id == e.key).page;
      (_adoptedByPage[page] ??= {}).add(e.value);
    }
    _deletedForeign.clear();
    _dirtyPages.clear();
    _deletedDirty = false;
    _undo.clear();
    _redo.clear();
    _preview.clear();
    _selection.removeWhere((id) => objectById(id) == null);
    if (_editingId != null && objectById(_editingId!) == null) {
      _editingId = null;
    }
    _loadError = result.error;
    _readOnly = result.error != null;
    _multiplyChanged();
    notifyListeners();
  }

  // ------------------------------------------------------ transient UI

  /// Focus target for editor keyboard shortcuts (requested on page clicks).
  final FocusNode keyboardFocus = FocusNode(debugLabel: 'markupEditor');

  final Set<String> _openNotes = {};
  bool isNoteOpen(String id) => _openNotes.contains(id);

  void setNoteOpen(String id, bool open) {
    final changed = open ? _openNotes.add(id) : _openNotes.remove(id);
    if (changed) notifyListeners();
  }

  /// Image chosen in the panel, placed on the next page click.
  Uint8List? pendingImage;
  double pendingImageAspect = 1;

  void setPendingImage(Uint8List? bytes, double aspect) {
    pendingImage = bytes;
    pendingImageAspect = aspect;
    notifyListeners();
  }

  /// Object to scroll to / flash (Layers panel click).
  final ValueNotifier<String?> reveal = ValueNotifier(null);

  // --------------------------------------------------------------- mode

  bool _editMode = false;
  MarkupTool _tool = MarkupTool.select;

  /// True while the markup panel is open: objects are selectable/editable.
  bool get editMode => _editMode;
  MarkupTool get tool => _tool;

  void enterEditMode([MarkupTool? tool]) {
    _editMode = true;
    if (tool != null) _tool = tool;
    notifyListeners();
  }

  void exitEditMode() {
    if (!_editMode) return;
    commitTextEditing();
    _editMode = false;
    _tool = MarkupTool.select;
    _selection.clear();
    _pendingPoly = null;
    notifyListeners();
    unawaited(flush());
  }

  void setTool(MarkupTool tool) {
    if (_tool == tool && _editMode) return;
    commitTextEditing();
    _tool = tool;
    _editMode = true;
    _pendingPoly = null;
    if (tool != MarkupTool.select) _selection.clear();
    notifyListeners();
  }

  // -------------------------------------------------------------- style

  int strokeColor = 0xFFE53935;
  int? fillColor;
  double strokeWidth = 2;
  double opacity = 1;
  StrokeDash dash = StrokeDash.solid;
  int penColor = 0xFF1E88E5;
  double penWidth = 2;
  int highlighterColor = 0xFFFFEB3B;
  double highlighterWidth = 12;
  int highlightColor = 0xFFFFEB3B;
  int underlineColor = 0xFF1E88E5;
  int strikeColor = 0xFFE53935;
  int squigglyColor = 0xFF43A047;
  int noteColor = 0xFFFFD54F;
  MarkupFontFamily fontFamily = MarkupFontFamily.sans;
  double fontSize = 14;
  bool bold = false;
  bool italic = false;
  bool underline = false;
  bool strike = false;
  double letterSpacing = 0;
  double lineHeight = 1.2;
  int textColor = 0xFF000000;
  MarkupTextAlign textAlign = MarkupTextAlign.left;

  /// Corner drags keep proportions (Shift inverts). Images default to on.
  bool lockImageAspect = true;
  bool lockShapeAspect = false;

  /// Smart guides / snapping while moving and resizing (Alt suspends).
  bool snapEnabled = true;

  bool aspectLockedFor(MarkupObject o) =>
      o is ImageMarkup ? lockImageAspect : lockShapeAspect;

  void toggleAspectLockFor(MarkupObject o) {
    if (o is ImageMarkup) {
      lockImageAspect = !lockImageAspect;
    } else {
      lockShapeAspect = !lockShapeAspect;
    }
    notifyListeners();
  }

  /// Settings → Commenting → Author (falls back to the OS user name).
  String get author => AppPrefs.effectiveAuthor;

  int textMarkupColor(TextMarkupKind kind) => switch (kind) {
    TextMarkupKind.highlight => highlightColor,
    TextMarkupKind.underline => underlineColor,
    TextMarkupKind.strikeout => strikeColor,
    TextMarkupKind.squiggly => squigglyColor,
  };

  /// Color swatch for the active tool.
  int get activeColor => switch (_tool) {
    MarkupTool.highlight => highlightColor,
    MarkupTool.underline => underlineColor,
    MarkupTool.strikeout => strikeColor,
    MarkupTool.squiggly => squigglyColor,
    MarkupTool.pen => penColor,
    MarkupTool.highlighter => highlighterColor,
    MarkupTool.note => noteColor,
    MarkupTool.text || MarkupTool.callout => textColor,
    _ => strokeColor,
  };

  void setActiveColor(int argb) {
    switch (_tool) {
      case MarkupTool.highlight:
        highlightColor = argb;
      case MarkupTool.underline:
        underlineColor = argb;
      case MarkupTool.strikeout:
        strikeColor = argb;
      case MarkupTool.squiggly:
        squigglyColor = argb;
      case MarkupTool.pen:
        penColor = argb;
      case MarkupTool.highlighter:
        highlighterColor = argb;
      case MarkupTool.note:
        noteColor = argb;
      case MarkupTool.text:
      case MarkupTool.callout:
        textColor = argb;
      default:
        strokeColor = argb;
    }
    notifyListeners();
  }

  void updateStyle(VoidCallback change) {
    change();
    notifyListeners();
  }

  // ---------------------------------------------------------- selection

  final Set<String> _selection = {};
  String? _editingId;
  bool _editingIsNew = false;
  Set<String> get selection => Set.unmodifiable(_selection);
  bool isSelected(String id) => _selection.contains(id);
  String? get editingId => _editingId;
  bool get editingIsNew => _editingIsNew;

  List<MarkupObject> get selectedObjects => [
    for (final id in _selection) ?objectById(id),
  ];

  /// Page of the (first) selected object, if any.
  int? get selectionPage {
    final objs = selectedObjects;
    return objs.isEmpty ? null : objs.first.page;
  }

  /// [ids] plus every visible member of their groups.
  Set<String> withGroupMates(Iterable<String> ids) {
    final out = <String>{};
    for (final id in ids) {
      final o = objectById(id);
      if (o == null) continue;
      out.add(id);
      final g = o.groupId;
      if (g == null) continue;
      for (final m in objectsOn(o.page)) {
        if (m.groupId == g && !m.hidden) out.add(m.id);
      }
    }
    return out;
  }

  void select(String id, {bool additive = false}) {
    commitTextEditing(keep: id);
    final o = objectById(id);
    if (o == null) return;
    final unit = withGroupMates([id]);
    if (additive) {
      if (_selection.contains(id)) {
        _selection.removeAll(unit);
      } else {
        // Multi-select stays on one page.
        final page = selectionPage;
        if (page != null && page != o.page) _selection.clear();
        _selection.addAll(unit);
      }
    } else {
      _selection
        ..clear()
        ..addAll(unit);
    }
    notifyListeners();
  }

  void selectMany(Iterable<String> ids, {bool additive = false}) {
    commitTextEditing();
    if (!additive) _selection.clear();
    _selection.addAll(withGroupMates(ids));
    notifyListeners();
  }

  // ------------------------------------------------------------ groups

  /// The selection is exactly one group.
  bool get selectionIsGroup {
    final objs = selectedObjects;
    if (objs.length < 2) return false;
    final g = objs.first.groupId;
    return g != null && objs.every((o) => o.groupId == g);
  }

  bool get canGroup {
    final objs = selectedObjects;
    return objs.length >= 2 && !selectionIsGroup && !objs.any((o) => o.locked);
  }

  bool get canUngroup => selectedObjects.any((o) => o.groupId != null);

  void groupSelection() {
    if (!canGroup) return;
    final gid = 'grp-${newId()}';
    replaceObjects([
      for (final o in selectedObjects) o.withCommon(groupId: gid),
    ]);
  }

  void ungroupSelection() {
    final objs = [
      for (final o in selectedObjects)
        if (o.groupId != null) o.withCommon(groupId: null),
    ];
    replaceObjects(objs);
  }

  // ------------------------------------------------------ align/distribute

  /// Selection split into move units (a group moves as one).
  List<List<MarkupObject>> _moveUnits() {
    final byGroup = <String, List<MarkupObject>>{};
    final units = <List<MarkupObject>>[];
    for (final o in selectedObjects) {
      if (o.locked || !o.canMove) continue;
      final g = o.groupId;
      if (g == null) {
        units.add([o]);
      } else {
        final list = byGroup[g];
        if (list == null) {
          units.add(byGroup[g] = [o]);
        } else {
          list.add(o);
        }
      }
    }
    return units;
  }

  static Rect _unionBounds(Iterable<MarkupObject> objs) =>
      objs.map((o) => o.bounds).reduce((a, b) => a.expandToInclude(b));

  /// Aligns the selection's edges/centers; a single unit aligns to the page.
  void alignSelection(MarkupAlign align) {
    final units = _moveUnits();
    if (units.isEmpty) return;
    final page = units.first.first.page;
    final geo = _geometry[page];
    final Rect target;
    if (units.length == 1) {
      if (geo == null) return;
      target = Rect.fromLTWH(0, 0, geo.displayWidth, geo.displayHeight);
    } else {
      target = _unionBounds(units.expand((u) => u));
    }
    final moved = <MarkupObject>[];
    for (final u in units) {
      final b = _unionBounds(u);
      final d = switch (align) {
        MarkupAlign.left => Offset(target.left - b.left, 0),
        MarkupAlign.centerH => Offset(target.center.dx - b.center.dx, 0),
        MarkupAlign.right => Offset(target.right - b.right, 0),
        MarkupAlign.top => Offset(0, target.top - b.top),
        MarkupAlign.middle => Offset(0, target.center.dy - b.center.dy),
        MarkupAlign.bottom => Offset(0, target.bottom - b.bottom),
      };
      if (d == Offset.zero) continue;
      moved.addAll(u.map((o) => o.moved(d)));
    }
    replaceObjects(moved);
  }

  bool get canDistribute => _moveUnits().length >= 3;

  /// Equal gaps between units along [axis] (outermost units stay put).
  void distributeSelection(Axis axis) {
    final units = _moveUnits();
    if (units.length < 3) return;
    final h = axis == Axis.horizontal;
    final entries = [for (final u in units) (u, _unionBounds(u))]
      ..sort(
        (a, b) =>
            h ? a.$2.left.compareTo(b.$2.left) : a.$2.top.compareTo(b.$2.top),
      );
    final first = entries.first.$2, last = entries.last.$2;
    final span = h ? last.right - first.left : last.bottom - first.top;
    final sizes = entries.fold<double>(
      0,
      (n, e) => n + (h ? e.$2.width : e.$2.height),
    );
    final gap = (span - sizes) / (entries.length - 1);
    var cursor = h ? first.left : first.top;
    final moved = <MarkupObject>[];
    for (final (u, b) in entries) {
      final d = h ? Offset(cursor - b.left, 0) : Offset(0, cursor - b.top);
      if (d.distance > 1e-6) moved.addAll(u.map((o) => o.moved(d)));
      cursor += (h ? b.width : b.height) + gap;
    }
    replaceObjects(moved);
  }

  void clearSelection() {
    if (_selection.isEmpty && _editingId == null) return;
    commitTextEditing();
    _selection.clear();
    notifyListeners();
  }

  void selectAllOnPage(int page) {
    commitTextEditing();
    _selection
      ..clear()
      ..addAll([
        for (final o in objectsOn(page))
          if (!o.locked && !o.hidden) o.id,
      ]);
    notifyListeners();
  }

  // ------------------------------------------------------- text editing

  final ValueNotifier<int> textEditTick = ValueNotifier(0);

  void startEditing(String id, {bool isNew = false}) {
    if (_editingId == id) return;
    commitTextEditing();
    _editingId = id;
    _editingIsNew = isNew;
    _selection
      ..clear()
      ..add(id);
    notifyListeners();
  }

  /// Live text update while typing (no undo entry per keystroke).
  void updateEditingText(String text) {
    final id = _editingId;
    if (id == null) return;
    final o = objectById(id);
    if (o is! TextBoxMarkup) return;
    _preview[id] = relayoutTextBox(o.copyWith(text: text));
    textEditTick.value++;
    previewTick.value++;
  }

  /// Ends inline editing: commits the text (one undo step) or removes an
  /// empty new box. [keep] leaves that id selected.
  void commitTextEditing({String? keep}) {
    final id = _editingId;
    if (id == null) return;
    if (keep == id) return;
    _editingId = null;
    final edited = _preview.remove(id);
    final original = _objectRaw(id);
    if (original is! TextBoxMarkup) {
      notifyListeners();
      return;
    }
    final next = edited is TextBoxMarkup ? edited : original;
    if (next.text.trim().isEmpty) {
      if (_editingIsNew) {
        _removeSilently(id);
        _selection.remove(id);
        _editingIsNew = false;
        notifyListeners();
      } else {
        deleteObjects({id});
      }
      return;
    }
    if (_editingIsNew) {
      // The pending box never had an undo entry; add it as one step so undo
      // removes it instead of leaving an empty box behind.
      _removeSilently(id);
      _editingIsNew = false;
      addObject(next);
      return;
    }
    if (!identical(next, original)) {
      replaceObjects([next]);
    } else {
      notifyListeners();
    }
    _editingIsNew = false;
  }

  void cancelTextEditing() {
    final id = _editingId;
    if (id == null) return;
    _preview.remove(id);
    _editingId = null;
    if (_editingIsNew) {
      _removeSilently(id);
      _selection.remove(id);
    }
    _editingIsNew = false;
    notifyListeners();
  }

  // ------------------------------------------------------------ preview

  /// Objects being dragged/typed (painted instead of the stored version).
  final Map<String, MarkupObject> _preview = {};

  /// Bumps while dragging so only the page layers repaint (no rebuilds).
  final ValueNotifier<int> previewTick = ValueNotifier(0);

  /// In-progress freehand / shape / marquee drawn by a page layer.
  final ValueNotifier<MarkupDraft?> draft = ValueNotifier(null);

  /// Alignment guides shown while dragging (page + display-point lines).
  final ValueNotifier<MarkupGuides?> guides = ValueNotifier(null);

  List<Offset>? _pendingPoly;
  int? _pendingPolyPage;
  List<Offset>? get pendingPolygon => _pendingPoly;
  int? get pendingPolygonPage => _pendingPolyPage;

  MarkupObject displayed(MarkupObject o) => _preview[o.id] ?? o;

  void setPreview(Map<String, MarkupObject> objects) {
    _preview
      ..removeWhere((k, _) => k != _editingId)
      ..addAll(objects);
    previewTick.value++;
    if (objects.values.any(markupUsesMultiply)) _multiplyChanged();
  }

  void clearPreview() {
    final hadMultiply = _preview.values.any(markupUsesMultiply);
    _preview.removeWhere((k, _) => k != _editingId);
    previewTick.value++;
    if (hadMultiply) _multiplyChanged();
  }

  /// Commits the current drag preview as one undo step.
  void commitPreview() {
    final objs = [
      for (final e in _preview.entries)
        if (e.key != _editingId) e.value,
    ];
    _preview.removeWhere((k, _) => k != _editingId);
    if (objs.isEmpty) {
      previewTick.value++;
      return;
    }
    replaceObjects(objs);
  }

  // ------------------------------------------------------ polygon tools

  void addPolygonPoint(int page, Offset p) {
    if (_pendingPoly == null || _pendingPolyPage != page) {
      _pendingPoly = [p];
      _pendingPolyPage = page;
    } else {
      _pendingPoly = [..._pendingPoly!, p];
    }
    previewTick.value++;
    notifyListeners();
  }

  void finishPolygon() {
    final pts = _pendingPoly;
    final page = _pendingPolyPage;
    _pendingPoly = null;
    _pendingPolyPage = null;
    if (pts == null || page == null || pts.length < 3) {
      previewTick.value++;
      notifyListeners();
      return;
    }
    final kind = _tool == MarkupTool.cloud
        ? ShapeKind.cloud
        : ShapeKind.polygon;
    addObject(
      ShapeMarkup(
        id: newId(),
        page: page,
        kind: kind,
        points: pts,
        strokeColor: strokeColor,
        fillColor: fillColor,
        strokeWidth: strokeWidth,
        dash: dash,
        opacity: opacity,
      ),
      select: false,
    );
  }

  void cancelPolygon() {
    if (_pendingPoly == null) return;
    _pendingPoly = null;
    _pendingPolyPage = null;
    previewTick.value++;
    notifyListeners();
  }

  // ------------------------------------------------------------- editing

  final List<_Snapshot> _undo = [];
  final List<_Snapshot> _redo = [];
  static const int _maxUndo = 100;

  bool get canUndo => _undo.isNotEmpty || _editingId != null;
  bool get canRedo => _redo.isNotEmpty;

  _Snapshot _snapshot() => _Snapshot(
    {for (final e in _pages.entries) e.key: List.of(e.value)},
    {for (final e in _deletedForeign.entries) e.key: Set.of(e.value)},
  );

  void _pushUndo() {
    _undo.add(_snapshot());
    if (_undo.length > _maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snapshot s) {
    final before = _snapshot();
    final changed = <int>{...before.pages.keys, ...s.pages.keys}.where((p) {
      final a = before.pages[p] ?? const [];
      final b = s.pages[p] ?? const [];
      if (a.length != b.length) return true;
      for (var i = 0; i < a.length; i++) {
        if (!identical(a[i], b[i])) return true;
      }
      return false;
    });
    final foreignChanged = <int>{
      ...before.deletedForeign.keys,
      ...s.deletedForeign.keys,
    }.where((p) => !setEquals(before.deletedForeign[p], s.deletedForeign[p]));
    _pages
      ..clear()
      ..addAll({for (final e in s.pages.entries) e.key: List.of(e.value)});
    _deletedForeign
      ..clear()
      ..addAll({
        for (final e in s.deletedForeign.entries) e.key: Set.of(e.value),
      });
    _markDirty(changed);
    if (foreignChanged.isNotEmpty) {
      _deletedDirty = true;
      _dirtyPages.addAll(foreignChanged);
    }
    _selection.removeWhere((id) => objectById(id) == null);
    _multiplyChanged();
  }

  /// Returns false when there was nothing to undo (caller falls back to the
  /// document-level undo).
  bool undo() {
    if (_editingId != null) {
      cancelTextEditing();
      return true;
    }
    if (_undo.isEmpty) return false;
    final s = _undo.removeLast();
    _redo.add(_snapshot());
    _restore(s);
    notifyListeners();
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final s = _redo.removeLast();
    _undo.add(_snapshot());
    _restore(s);
    notifyListeners();
    return true;
  }

  int _idSeq = 0;
  String newId() =>
      'ds-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-${_idSeq++}';

  MarkupObject? _objectRaw(String id) {
    for (final list in _pages.values) {
      for (final o in list) {
        if (o.id == id) return o;
      }
    }
    return null;
  }

  void _removeSilently(String id) {
    for (final e in _pages.entries) {
      final before = e.value.length;
      e.value.removeWhere((o) => o.id == id);
      if (e.value.length != before) _markDirty({e.key});
    }
  }

  void addObject(MarkupObject o, {bool select = true, bool edit = false}) {
    if (_readOnly) return;
    _pushUndo();
    (_pages[o.page] ??= []).add(o);
    _markDirty({o.page});
    if (select || edit) {
      _selection
        ..clear()
        ..add(o.id);
    }
    if (edit) {
      _editingId = o.id;
      _editingIsNew = true;
    }
    if (markupUsesMultiply(o)) _multiplyChanged();
    notifyListeners();
  }

  /// Adds without an undo entry (used for the first frame of a new text box,
  /// whose undo step is taken when editing is committed).
  void addPending(MarkupObject o) {
    if (_readOnly) return;
    (_pages[o.page] ??= []).add(o);
    _selection
      ..clear()
      ..add(o.id);
    _editingId = o.id;
    _editingIsNew = true;
    notifyListeners();
  }

  void replaceObjects(List<MarkupObject> objs) {
    if (objs.isEmpty) return;
    if (_readOnly) return;
    _pushUndo();
    var multiply = false;
    for (final n in objs) {
      final list = _pages[n.page];
      if (list == null) continue;
      final i = list.indexWhere((o) => o.id == n.id);
      if (i < 0) continue;
      multiply |= markupUsesMultiply(list[i]) || markupUsesMultiply(n);
      list[i] = n;
      _markDirty({n.page});
    }
    if (_editingIsNew) _editingIsNew = false;
    if (multiply) _multiplyChanged();
    notifyListeners();
  }

  /// Applies [change] to the selection (one undo step). The text box being
  /// edited is updated live and committed with its text.
  void updateSelected(MarkupObject Function(MarkupObject o) change) {
    final editing = _editingId;
    final objs = <MarkupObject>[];
    var editedLive = false;
    for (final o in selectedObjects) {
      if (o.locked) continue;
      final next = change(o);
      if (o.id == editing) {
        _preview[o.id] = next;
        editedLive = true;
      } else {
        objs.add(next);
      }
    }
    if (editedLive) {
      textEditTick.value++;
      previewTick.value++;
    }
    if (objs.isEmpty) {
      if (editedLive) notifyListeners();
      return;
    }
    replaceObjects(objs);
  }

  /// Live preview of [change] on the selection (sliders); finish with
  /// [commitPreview] or [clearPreview].
  void previewSelected(MarkupObject Function(MarkupObject o) change) {
    final editing = _editingId;
    final next = <String, MarkupObject>{};
    for (final o in selectedObjects) {
      if (o.locked) continue;
      if (o.id == editing) {
        _preview[o.id] = change(o);
        textEditTick.value++;
      } else {
        next[o.id] = change(_objectRaw(o.id) ?? o);
      }
    }
    setPreview(next);
  }

  void deleteObjects(Set<String> ids) {
    if (ids.isEmpty || _readOnly) return;
    _pushUndo();
    var multiply = false;
    for (final e in _pages.entries) {
      final before = e.value.length;
      multiply |= e.value.any(
        (o) => ids.contains(o.id) && markupUsesMultiply(o),
      );
      e.value.removeWhere((o) => ids.contains(o.id));
      if (e.value.length != before) _markDirty({e.key});
    }
    _selection.removeAll(ids);
    if (ids.contains(_editingId)) _editingId = null;
    if (multiply) _multiplyChanged();
    notifyListeners();
  }

  void deleteSelected() => deleteObjects({
    for (final o in selectedObjects)
      if (!o.locked) o.id,
  });

  void deleteForeign(ForeignAnnotation f) {
    final ref = f.refNum;
    if (ref == null || _readOnly) return;
    _pushUndo();
    (_deletedForeign[f.page] ??= {}).add(ref);
    _deletedDirty = true;
    _dirtyPages.add(f.page);
    _scheduleAutosave();
    notifyListeners();
  }

  void setHidden(String id, bool hidden) {
    final o = objectById(id);
    if (o == null) return;
    replaceObjects([o.withCommon(hidden: hidden)]);
    if (hidden) _selection.remove(id);
  }

  void setLocked(String id, bool locked) {
    final o = objectById(id);
    if (o == null) return;
    replaceObjects([o.withCommon(locked: locked)]);
  }

  void rename(String id, String name) {
    final o = objectById(id);
    if (o == null) return;
    replaceObjects([o.withCommon(name: name.trim())]);
  }

  /// Layers-panel reorder within a page ([from]/[to] in z-order, 0 = back).
  void reorder(int page, int from, int to) {
    final list = _pages[page];
    if (list == null || from == to) return;
    if (from < 0 || from >= list.length) return;
    _pushUndo();
    final o = list.removeAt(from);
    list.insert(to.clamp(0, list.length), o);
    _markDirty({page});
    _multiplyChanged();
    notifyListeners();
  }

  void bringToFront() => _zMove((list, i) => list.length - 1);
  void sendToBack() => _zMove((list, i) => 0);
  void bringForward() => _zMove((list, i) => math.min(list.length - 1, i + 1));
  void sendBackward() => _zMove((list, i) => math.max(0, i - 1));

  void _zMove(int Function(List<MarkupObject> list, int index) target) {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    _pushUndo();
    for (final o in objs) {
      final list = _pages[o.page]!;
      final i = list.indexWhere((e) => e.id == o.id);
      if (i < 0) continue;
      final t = target(list, i);
      list.removeAt(i);
      list.insert(t.clamp(0, list.length), o);
      _markDirty({o.page});
    }
    _multiplyChanged();
    notifyListeners();
  }

  // -------------------------------------------------------------- images

  /// Shows [crop] of [id]'s source, keeping the on-page scale and the
  /// visible content where it was (so nothing stretches or jumps).
  void cropImage(String id, Rect crop, Size imagePx) {
    final o = objectById(id);
    if (o is! ImageMarkup || o.locked) return;
    final f = o.frame;
    final c0 = o.crop;
    final ptPerPxX = f.width / math.max(1e-6, c0.width * imagePx.width);
    final ptPerPxY = f.height / math.max(1e-6, c0.height * imagePx.height);
    final w = crop.width * imagePx.width * ptPerPxX;
    final h = crop.height * imagePx.height * ptPerPxY;
    final localCenter = Offset(
      (crop.center.dx - c0.left) * imagePx.width * ptPerPxX,
      (crop.center.dy - c0.top) * imagePx.height * ptPerPxY,
    );
    final center = frameToDisplay(
      f,
      o.rotation,
      flipH: o.flipH,
      flipV: o.flipV,
    ).apply(localCenter);
    replaceObjects([
      o.copyWith(
        crop: crop,
        frame: Rect.fromCenter(center: center, width: w, height: h),
      ),
    ]);
  }

  /// Swaps the picture, fitting the new one inside the current frame.
  void replaceImage(String id, Uint8List bytes, double aspect) {
    final o = objectById(id);
    if (o is! ImageMarkup || o.locked) return;
    final f = o.frame;
    var w = f.width, h = w / aspect;
    if (h > f.height) {
      h = f.height;
      w = h * aspect;
    }
    replaceObjects([
      o.copyWith(
        bytes: bytes,
        crop: kFullCrop,
        frame: Rect.fromCenter(center: f.center, width: w, height: h),
      ),
    ]);
  }

  // ----------------------------------------------------------- clipboard

  List<MarkupObject> _clipboard = const [];
  int _pasteCount = 0;

  bool get hasClipboard => _clipboard.isNotEmpty;

  void copySelection() {
    _clipboard = selectedObjects;
    _pasteCount = 0;
    notifyListeners();
  }

  void cutSelection() {
    copySelection();
    deleteSelected();
  }

  void paste({int? page}) {
    if (_clipboard.isEmpty || _readOnly) return;
    _pasteCount++;
    final offset = Offset(12.0 * _pasteCount, 12.0 * _pasteCount);
    _insertCopies(_clipboard, page: page, offset: offset);
  }

  void duplicateSelection() {
    final objs = selectedObjects;
    if (objs.isEmpty) return;
    _insertCopies(objs, offset: const Offset(12, 12));
  }

  void _insertCopies(
    List<MarkupObject> source, {
    int? page,
    required Offset offset,
  }) {
    _pushUndo();
    final ids = <String>[];
    for (final o in source) {
      final target = page ?? o.page;
      var copy = o.withCommon(id: newId(), page: target, locked: false);
      if (copy.canMove) copy = copy.moved(offset);
      (_pages[target] ??= []).add(copy);
      ids.add(copy.id);
      _markDirty({target});
    }
    _selection
      ..clear()
      ..addAll(ids);
    _multiplyChanged();
    notifyListeners();
  }

  // --------------------------------------------------------------- saving

  final Set<int> _dirtyPages = {};
  bool _deletedDirty = false;
  Timer? _autosave;
  bool _saving = false;
  bool _saveAgain = false;
  String? _saveError;
  Completer<void>? _saveDone;

  bool get hasUnsavedChanges => _dirtyPages.isNotEmpty;
  bool get saving => _saving;
  String? get saveError => _saveError;

  static const Duration autosaveDelay = Duration(milliseconds: 900);

  void _markDirty(Iterable<int> pages) {
    if (pages.isEmpty) return;
    _dirtyPages.addAll(pages);
    _scheduleAutosave();
  }

  void _scheduleAutosave() {
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, () => unawaited(flush()));
  }

  /// Writes pending markup into the PDF now. Call before other tools read the
  /// file and when the viewer closes.
  Future<void> flush() async {
    _autosave?.cancel();
    if (_dirtyPages.isEmpty) return _saveDone?.future ?? Future.value();
    if (_saving) {
      _saveAgain = true;
      return _saveDone?.future ?? Future.value();
    }
    final s = _session;
    final commit = _commit;
    if (s == null || commit == null || _readOnly) return;
    _saving = true;
    _saveDone = Completer<void>();
    final pages = Set.of(_dirtyPages);
    _dirtyPages.clear();
    _deletedDirty = false;
    final objectsByPage = <int, List<MarkupObject>>{
      for (final p in pages)
        p: [
          for (final o in objectsOn(p))
            if (!(o.id == _editingId && _editingIsNew)) o,
        ],
    };
    final removeRefs = <int, Set<int>>{
      for (final p in pages) p: {...?_adoptedByPage[p], ...?_deletedForeign[p]},
    };
    final who = author;
    try {
      final bytes = await s.readCurrentBytes();
      final out = await runIsolated(
        applyMarkupToPdf,
        MarkupSaveRequest(
          bytes: bytes,
          objectsByPage: objectsByPage,
          removeRefsByPage: removeRefs,
          author: who,
        ),
      );
      final expected = s.revision + 1;
      MarkupOwnRevisions.mark(s.file.path, expected);
      final ok = await commit(out);
      if (!identical(s, _session)) {
        if (ok) MarkupOwnRevisions.mark(s.file.path, s.revision);
        return;
      }
      if (ok) {
        _knownRevision = s.revision;
        MarkupOwnRevisions.mark(s.file.path, s.revision);
        for (final p in pages) {
          _adoptedByPage.remove(p);
          final gone = _deletedForeign.remove(p);
          if (gone != null) {
            _foreign = [
              for (final f in _foreign)
                if (!(f.page == p && gone.contains(f.refNum))) f,
            ];
          }
        }
        _saveError = null;
      } else {
        _dirtyPages.addAll(pages);
        _saveError = 'Markup not saved';
      }
    } catch (e) {
      if (identical(s, _session)) _dirtyPages.addAll(pages);
      _saveError = '$e';
      if (e.toString().contains('ncrypted')) _readOnly = true;
    } finally {
      _saving = false;
      final done = _saveDone;
      _saveDone = null;
      done?.complete();
      notifyListeners();
      if (_saveAgain || (_dirtyPages.isNotEmpty && _saveError == null)) {
        _saveAgain = false;
        _scheduleAutosave();
      }
    }
  }

  // ------------------------------------------------ page-canvas repaint

  /// Set by the viewer: repaints the page canvas (multiply-blended markup).
  VoidCallback? onMultiplyChanged;

  void _multiplyChanged() => onMultiplyChanged?.call();

  /// pdfrx page paint callback for multiply-blended markup.
  void paintMultiply(Canvas canvas, Rect pageRect, int page) {
    final list = _pages[page];
    if (list == null || list.isEmpty) return;
    final geo = _geometry[page];
    if (geo == null) return;
    final scale = pageRect.width / geo.displayWidth;
    canvas.save();
    canvas.translate(pageRect.left, pageRect.top);
    canvas.scale(scale);
    for (final o in list) {
      if (!markupUsesMultiply(o)) continue;
      paintMarkupObject(canvas, displayed(o), multiply: true);
    }
    canvas.restore();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _session?.removeListener(_onSessionChanged);
    previewTick.dispose();
    textEditTick.dispose();
    keyboardFocus.dispose();
    reveal.dispose();
    draft.dispose();
    guides.dispose();
    super.dispose();
  }
}

enum MarkupAlign { left, centerH, right, top, middle, bottom }

/// Snap lines to draw while dragging, in page display points.
class MarkupGuides {
  const MarkupGuides({
    required this.page,
    this.vertical = const [],
    this.horizontal = const [],
    this.label,
    this.labelAt,
  });

  final int page;

  /// x positions (full-height guides) and y positions (full-width guides).
  final List<double> vertical;
  final List<double> horizontal;

  /// Size / angle badge (e.g. "120 × 80", "45°") shown near [labelAt].
  final String? label;
  final Offset? labelAt;

  bool get isEmpty => vertical.isEmpty && horizontal.isEmpty && label == null;
}

/// Transient drawing feedback (not yet an object).
class MarkupDraft {
  const MarkupDraft({
    required this.page,
    this.object,
    this.marquee,
    this.eraserAt,
  });

  final int page;
  final MarkupObject? object;
  final Rect? marquee;
  final Offset? eraserAt;
}
