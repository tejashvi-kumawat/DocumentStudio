import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/foundation.dart';

/// One open document in the viewer tab strip.
@immutable
class PdfViewerTab {
  PdfViewerTab({
    required this.id,
    required LocalFileRef file,
    String? password,
    DocumentSession? session,
  }) : session = session ??
            DocumentSession(
              file: file,
              password: password,
            );

  final String id;
  final DocumentSession session;

  LocalFileRef get file => session.file;
  String? get password => session.password;
}

/// Tracks multiple open PDFs within the viewer feature.
class DocumentTabsController extends ChangeNotifier {
  final List<PdfViewerTab> _tabs = [];
  int _activeIndex = 0;
  bool _homeActive = true;
  ViewerToolId? _pendingViewerToolPanel;

  List<PdfViewerTab> get tabs => List.unmodifiable(_tabs);
  int get activeIndex => _activeIndex;
  bool get isHomeActive => _homeActive;
  ViewerToolId? get pendingViewerToolPanel => _pendingViewerToolPanel;

  PdfViewerTab? get activeTab =>
      _tabs.isEmpty || _activeIndex < 0 || _activeIndex >= _tabs.length
          ? null
          : _tabs[_activeIndex];

  DocumentSession? get activeSession => activeTab?.session;

  bool get hasTabs => _tabs.isNotEmpty;

  void showHome() {
    if (_homeActive) return;
    _homeActive = true;
    notifyListeners();
  }

  void showDocument() {
    if (!_homeActive || _tabs.isEmpty) return;
    _homeActive = false;
    notifyListeners();
  }

  void queueViewerToolPanel(ViewerToolId tool) {
    _pendingViewerToolPanel = tool;
    notifyListeners();
  }

  ViewerToolId? takePendingViewerToolPanel() {
    final pending = _pendingViewerToolPanel;
    _pendingViewerToolPanel = null;
    return pending;
  }

  /// After session file/meta change, refresh the active tab without remounting
  /// the viewer when only the working-copy revision changes.
  void syncActiveTabFromSession() {
    if (_tabs.isEmpty) return;
    final index = _activeIndex;
    final tab = _tabs[index];
    final session = tab.session;
    // Keep a stable id so PdfViewer ValueKeys (and scroll/zoom) survive
    // Apply / undo / autosave. Path may be a working temp; soft-reload handles
    // byte changes. Save As still updates file via didUpdateWidget.
    _tabs[index] = PdfViewerTab(
      id: tab.id,
      file: session.file,
      password: session.password,
      session: session,
    );
    _homeActive = false;
    notifyListeners();
  }

  /// Replaces the active tab’s file (e.g. **Try another file** on the error panel).
  Future<void> replaceActiveDocument(LocalFileRef file, {String? password}) async {
    if (_tabs.isEmpty) {
      await openDocument(file, password: password);
      return;
    }
    final index = _activeIndex;
    _tabs[index].session.dispose();
    var resolvedPath = LinuxDocumentPortal.resolveSync(file.path);
    if (LinuxDocumentPortal.isPortalPath(resolvedPath)) {
      resolvedPath = await LinuxDocumentPortal.resolve(file.path);
    }
    final resolved =
        resolvedPath == file.path ? file : file.copyWithPath(resolvedPath);
    _tabs[index] = PdfViewerTab(
      id: '${resolved.path}#${DateTime.now().millisecondsSinceEpoch}',
      file: resolved,
      password: password,
    );
    _homeActive = false;
    notifyListeners();
  }

  /// Opens [file] or activates an existing tab for the same path.
  ///
  /// Portal FUSE paths are resolved to the host file before [DocumentSession]
  /// / [PdfDocumentRefKey] exist. Prefer awaiting this from UI entry points
  /// ([openPdfInDocumentTabs]); sync callers still resolve via [resolveSync].
  Future<void> openDocument(
    LocalFileRef file, {
    String? password,
    ViewerToolId? openToolPanel,
  }) async {
    var resolvedPath = LinuxDocumentPortal.resolveSync(file.path);
    if (LinuxDocumentPortal.isPortalPath(resolvedPath)) {
      resolvedPath = await LinuxDocumentPortal.resolve(file.path);
    }
    final resolved = resolvedPath == file.path
        ? file
        : file.copyWithPath(resolvedPath);
    final existing = _tabs.indexWhere(
      (t) =>
          t.session.sourcePath == resolved.path ||
          t.file.path == resolved.path ||
          t.session.sameDocumentPath(resolved.path) ||
          LinuxDocumentPortal.sameFileSync(t.session.sourcePath, resolved.path),
    );
    if (existing >= 0) {
      if (password != null &&
          password.isNotEmpty &&
          (_tabs[existing].password == null ||
              _tabs[existing].password!.isEmpty)) {
        _tabs[existing].session.password = password;
      }
      _activeIndex = existing;
      _homeActive = false;
      if (openToolPanel != null) {
        _pendingViewerToolPanel = openToolPanel;
      }
      notifyListeners();
      return;
    }
    _tabs.add(
      PdfViewerTab(
        id: '${resolved.path}#${_tabs.length}',
        file: resolved,
        password: password,
      ),
    );
    _activeIndex = _tabs.length - 1;
    _homeActive = false;
    if (openToolPanel != null) {
      _pendingViewerToolPanel = openToolPanel;
    }
    notifyListeners();
  }

  void activateTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    if (index == _activeIndex && !_homeActive) return;
    _activeIndex = index;
    _homeActive = false;
    notifyListeners();
  }

  void closeTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    final removed = _tabs.removeAt(index);
    // Drop the working-copy temp after the tab is gone.
    removed.session.dispose();
    if (_tabs.isEmpty) {
      _activeIndex = 0;
      _homeActive = true;
    } else if (_activeIndex >= _tabs.length) {
      _activeIndex = _tabs.length - 1;
    } else if (index < _activeIndex) {
      _activeIndex -= 1;
    }
    notifyListeners();
  }

  void closeActiveTab() => closeTab(_activeIndex);

  /// Moves the tab at [from] so it ends up at index [to]; keeps the active tab.
  void moveTab(int from, int to) {
    if (from < 0 || from >= _tabs.length) return;
    final target = to.clamp(0, _tabs.length - 1);
    if (from == target) return;
    final active = activeTab;
    final tab = _tabs.removeAt(from);
    _tabs.insert(target, tab);
    if (active != null) _activeIndex = _tabs.indexOf(active);
    notifyListeners();
  }

  void clearAll() {
    for (final tab in _tabs) {
      tab.session.dispose();
    }
    _tabs.clear();
    _activeIndex = 0;
    _homeActive = true;
    _pendingViewerToolPanel = null;
    notifyListeners();
  }
}
