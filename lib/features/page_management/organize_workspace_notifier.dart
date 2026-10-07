import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Immutable workspace snapshot for undo/redo.
@immutable
class OrganizeWorkspaceState {
  const OrganizeWorkspaceState({
    this.pages = const [],
    this.selectedIds = const {},
    this.selectionAnchorId,
    this.focusPreviewIndex = 0,
    this.importedFiles = const [],
    this.busy = false,
    this.statusMessage,
    this.progressFraction,
    this.highlightSourcePath,
  });

  final List<OrganizePageRef> pages;
  final Set<String> selectedIds;
  final String? selectionAnchorId;
  final int focusPreviewIndex;
  final List<LocalFileRef> importedFiles;
  final bool busy;
  final String? statusMessage;
  final double? progressFraction;
  final String? highlightSourcePath;

  int get pageCount => pages.length;

  OrganizePageRef? get previewPage {
    if (pages.isEmpty) return null;
    final i = focusPreviewIndex.clamp(0, pages.length - 1);
    return pages[i];
  }

  OrganizeWorkspaceState copyWith({
    List<OrganizePageRef>? pages,
    Set<String>? selectedIds,
    String? selectionAnchorId,
    int? focusPreviewIndex,
    List<LocalFileRef>? importedFiles,
    bool? busy,
    String? statusMessage,
    double? progressFraction,
    String? highlightSourcePath,
    bool clearStatus = false,
    bool clearHighlightSource = false,
  }) {
    return OrganizeWorkspaceState(
      pages: pages ?? this.pages,
      selectedIds: selectedIds ?? this.selectedIds,
      selectionAnchorId: selectionAnchorId ?? this.selectionAnchorId,
      focusPreviewIndex: focusPreviewIndex ?? this.focusPreviewIndex,
      importedFiles: importedFiles ?? this.importedFiles,
      busy: busy ?? this.busy,
      statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
      progressFraction: clearStatus
          ? null
          : (progressFraction ?? this.progressFraction),
      highlightSourcePath: clearHighlightSource
          ? null
          : (highlightSourcePath ?? this.highlightSourcePath),
    );
  }
}

class OrganizeWorkspaceNotifier extends Notifier<OrganizeWorkspaceState> {
  final _undo = <List<OrganizePageRef>>[];
  final _redo = <List<OrganizePageRef>>[];

  @override
  OrganizeWorkspaceState build() => const OrganizeWorkspaceState();

  void reset() {
    _undo.clear();
    _redo.clear();
    state = const OrganizeWorkspaceState();
  }

  void _pushUndo() {
    _undo.add(List.of(state.pages));
    if (_undo.length > 30) _undo.removeAt(0);
    _redo.clear();
  }

  void setBusy(bool busy, {String? message, double? fraction}) {
    state = state.copyWith(
      busy: busy,
      statusMessage: message,
      progressFraction: fraction,
      clearStatus: !busy && message == null,
    );
  }

  void loadPagesFromFile(LocalFileRef file, int pageCount) {
    _pushUndo();
    final refs = [
      for (var p = 1; p <= pageCount; p++)
        OrganizePageRef.fromFilePage(file, p),
    ];
    final imports = [...state.importedFiles];
    if (!imports.any((f) => f.path == file.path)) {
      imports.add(file);
    }
    state = state.copyWith(
      pages: refs,
      importedFiles: imports,
      selectedIds: {},
      selectionAnchorId: null,
      focusPreviewIndex: 0,
      busy: false,
      clearStatus: true,
    );
  }

  void appendAllPagesFromFile(LocalFileRef file, int pageCount) {
    insertPagesFromFileAt(file, pageCount, state.pages.length);
  }

  void insertPagesFromFileAt(LocalFileRef file, int pageCount, int index) {
    _pushUndo();
    final imports = [...state.importedFiles];
    if (!imports.any((f) => f.path == file.path)) {
      imports.add(file);
    }
    final newPages = [
      for (var p = 1; p <= pageCount; p++)
        OrganizePageRef.fromFilePage(file, p),
    ];
    final list = List<OrganizePageRef>.of(state.pages);
    final at = index.clamp(0, list.length);
    list.insertAll(at, newPages);
    state = state.copyWith(
      pages: list,
      importedFiles: imports,
      focusPreviewIndex: at,
      busy: false,
      clearStatus: true,
    );
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    _pushUndo();
    final list = List<OrganizePageRef>.of(state.pages);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    state = state.copyWith(pages: list, clearStatus: true);
  }

  void moveByDelta(int index, int delta) {
    final j = index + delta;
    if (j < 0 || j >= state.pages.length) return;
    reorder(index, j);
  }

  void deleteSelected() {
    if (state.selectedIds.isEmpty) return;
    _pushUndo();
    final next = [
      for (final p in state.pages)
        if (!state.selectedIds.contains(p.id)) p,
    ];
    state = state.copyWith(
      pages: next,
      selectedIds: {},
      selectionAnchorId: null,
      focusPreviewIndex: next.isEmpty
          ? 0
          : state.focusPreviewIndex.clamp(0, next.length - 1),
      clearStatus: true,
    );
  }

  void insertBlankAt(int index, LocalFileRef blankTemplate) {
    if (index < 0 || index > state.pages.length) return;
    _pushUndo();
    final blank = OrganizePageRef.fromFilePage(blankTemplate, 1);
    final list = List<OrganizePageRef>.of(state.pages);
    list.insert(index.clamp(0, list.length), blank);
    final imports = [...state.importedFiles];
    if (!imports.any((f) => f.path == blankTemplate.path)) {
      imports.add(blankTemplate);
    }
    state = state.copyWith(
      pages: list,
      importedFiles: imports,
      clearStatus: true,
    );
  }

  void insertBlankAfterSelection(LocalFileRef blankTemplate) {
    if (state.selectedIds.isEmpty) {
      insertBlankAt(state.pages.length, blankTemplate);
      return;
    }
    final lastIndex = state.pages.lastIndexWhere(
      (p) => state.selectedIds.contains(p.id),
    );
    insertBlankAt(lastIndex + 1, blankTemplate);
  }

  void replaceSelectedFromFile(LocalFileRef file, int pageCount) {
    if (state.selectedIds.isEmpty || pageCount < 1) return;
    _pushUndo();
    final selectedIndices = <int>[
      for (var i = 0; i < state.pages.length; i++)
        if (state.selectedIds.contains(state.pages[i].id)) i,
    ];
    final replacementPages = [
      for (var p = 1; p <= pageCount; p++)
        OrganizePageRef.fromFilePage(file, p),
    ];
    final list = List<OrganizePageRef>.of(state.pages);
    for (
      var i = 0;
      i < selectedIndices.length && i < replacementPages.length;
      i++
    ) {
      list[selectedIndices[i]] = replacementPages[i];
    }
    final imports = [...state.importedFiles];
    if (!imports.any((f) => f.path == file.path)) {
      imports.add(file);
    }
    state = state.copyWith(
      pages: list,
      importedFiles: imports,
      selectedIds: {},
      clearStatus: true,
    );
  }

  void duplicateSelected() {
    if (state.selectedIds.isEmpty) return;
    _pushUndo();
    final list = <OrganizePageRef>[];
    for (final p in state.pages) {
      list.add(p);
      if (state.selectedIds.contains(p.id)) {
        list.add(
          OrganizePageRef(
            id: const Uuid().v4(),
            file: p.file,
            pageNumber1Based: p.pageNumber1Based,
            rotationDegrees: p.rotationDegrees,
          ),
        );
      }
    }
    state = state.copyWith(pages: list, clearStatus: true);
  }

  void rotateSelected({required bool clockwise, int degrees = 90}) {
    if (state.selectedIds.isEmpty) return;
    _pushUndo();
    final delta = clockwise ? degrees : -degrees;
    state = state.copyWith(
      pages: [
        for (final p in state.pages)
          if (state.selectedIds.contains(p.id))
            p.copyWith(
              rotationDegrees: ((p.rotationDegrees + delta) % 360 + 360) % 360,
            )
          else
            p,
      ],
      clearStatus: true,
    );
  }

  void reverseAll() {
    if (state.pages.isEmpty) return;
    _pushUndo();
    state = state.copyWith(
      pages: state.pages.reversed.toList(),
      clearStatus: true,
    );
  }

  void selectOnly(String id, {bool additive = false}) {
    if (additive) {
      final next = Set<String>.of(state.selectedIds);
      if (next.contains(id)) {
        next.remove(id);
      } else {
        next.add(id);
      }
      state = state.copyWith(selectedIds: next, selectionAnchorId: id);
    } else {
      state = state.copyWith(selectedIds: {id}, selectionAnchorId: id);
    }
    final idx = state.pages.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      state = state.copyWith(focusPreviewIndex: idx);
    }
  }

  void selectRangeTo(String id) {
    final anchor = state.selectionAnchorId;
    if (anchor == null) {
      selectOnly(id);
      return;
    }
    final a = state.pages.indexWhere((p) => p.id == anchor);
    final b = state.pages.indexWhere((p) => p.id == id);
    if (a < 0 || b < 0) return;
    final lo = a < b ? a : b;
    final hi = a < b ? b : a;
    final ids = {for (var i = lo; i <= hi; i++) state.pages[i].id};
    state = state.copyWith(selectedIds: ids, focusPreviewIndex: b);
  }

  void selectAll() {
    state = state.copyWith(
      selectedIds: state.pages.map((p) => p.id).toSet(),
      clearStatus: true,
    );
  }

  void clearSelection() {
    state = state.copyWith(selectedIds: {}, selectionAnchorId: null);
  }

  void applyMarqueeSelection(Set<String> pageIds, {required bool additive}) {
    if (pageIds.isEmpty && !additive) {
      clearSelection();
      return;
    }
    if (additive) {
      final next = Set<String>.of(state.selectedIds)..addAll(pageIds);
      state = state.copyWith(selectedIds: next);
    } else {
      state = state.copyWith(
        selectedIds: Set<String>.of(pageIds),
        selectionAnchorId: pageIds.isEmpty ? null : pageIds.first,
      );
    }
  }

  void setPreviewIndex(int index) {
    state = state.copyWith(focusPreviewIndex: index);
  }

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(List.of(state.pages));
    final prev = _undo.removeLast();
    state = state.copyWith(pages: prev, selectedIds: {}, clearStatus: true);
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(List.of(state.pages));
    final next = _redo.removeLast();
    state = state.copyWith(pages: next, selectedIds: {}, clearStatus: true);
    return true;
  }

  List<OrganizePageRef> pagesForOddEven({required bool odd}) {
    return [
      for (var i = 0; i < state.pages.length; i++)
        if (odd ? i.isOdd : i.isEven) state.pages[i],
    ];
  }

  void clearHighlightSource() {
    state = state.copyWith(clearHighlightSource: true);
  }

  void toggleHighlightSource(String path) {
    if (state.highlightSourcePath == path) {
      clearHighlightSource();
    } else {
      state = state.copyWith(highlightSourcePath: path);
    }
  }

  void selectPagesFromSource(String path) {
    final ids = {
      for (final p in state.pages)
        if (p.file.path == path) p.id,
    };
    state = state.copyWith(
      selectedIds: ids,
      highlightSourcePath: path,
      selectionAnchorId: ids.isEmpty ? null : ids.first,
    );
  }

  void selectPagesFromFileByNumbers(String path, Set<int> pages1Based) {
    final ids = {
      for (final p in state.pages)
        if (p.file.path == path && pages1Based.contains(p.pageNumber1Based))
          p.id,
    };
    state = state.copyWith(
      selectedIds: ids,
      highlightSourcePath: path,
      selectionAnchorId: ids.isEmpty ? null : ids.first,
    );
  }
}

final organizeWorkspaceProvider =
    NotifierProvider<OrganizeWorkspaceNotifier, OrganizeWorkspaceState>(
      OrganizeWorkspaceNotifier.new,
    );

/// Isolated page-list state for Home → Document Workspace (not shared with /organize/* tools).
class DocumentWorkspaceNotifier extends OrganizeWorkspaceNotifier {}

final documentWorkspaceProvider =
    NotifierProvider<DocumentWorkspaceNotifier, OrganizeWorkspaceState>(
      DocumentWorkspaceNotifier.new,
    );
