import 'package:document_studio/features/office/office_route.dart';
import 'package:document_studio/features/document_lifecycle/document_close_guard.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Current top-most location of [router] (pushed routes included).
String dsRouterLocation(GoRouter router) {
  try {
    return router.state.matchedLocation;
  } catch (_) {
    return '/';
  }
}

bool dsIsShellLocation(String path) =>
    path == '/' ||
    path.startsWith('/workspace') ||
    path == '/tools' ||
    path == '/settings';

/// Picks a PDF and opens it as a document tab, for chrome that sits above the
/// router's pages (title bar, global shortcuts) where [GoRouterState] is not
/// available. [navigatorContext] must be a context of (or under) a Navigator.
Future<void> dsOpenPdfFromChrome({
  required WidgetRef ref,
  required GoRouter router,
  required BuildContext? Function() navigatorContext,
}) async {
  final storage = ref.read(fileStorageProvider);
  try {
    final picked = await storage.pickOpenFile(
      allowedExtensions: const ['pdf', ...officeExtensions],
    );
    if (picked == null) return;
    // Word / PowerPoint open in their editors (in a tab of their own).
    if (isOfficePath(picked.path)) {
      router.go(officeLocation(path: picked.path));
      return;
    }
    await dsOpenPdfTab(
      ref: ref,
      router: router,
      navigatorContext: navigatorContext,
      file: picked,
    );
  } on DocumentStudioError catch (e) {
    final ctx = navigatorContext();
    if (ctx != null && ctx.mounted) showDocumentStudioErrorSnackBar(ctx, e);
  }
}

/// Validates [file] (prompting for a password if needed), records it as
/// recent, opens it as a tab and shows the viewer.
Future<void> dsOpenPdfTab({
  required WidgetRef ref,
  required GoRouter router,
  required BuildContext? Function() navigatorContext,
  required LocalFileRef file,
  String? password,
}) async {
  // Resolve + one viewer open. Do not validateOpenable first (that opened the
  // portal FUSE path and raced a second host open).
  await ref.read(recentsProvider.notifier).addRecent(file);
  await openPdfInDocumentTabs(ref, file, password: password);
  if (dsRouterLocation(router) != '/') router.go('/');
}

/// Keyboard tab commands over the whole strip: pinned Home, page tabs, then
/// documents (Ctrl+W, Ctrl+T, Ctrl+Tab, Ctrl+1…9, Ctrl+Shift+T).
class DsTabCommands {
  DsTabCommands({
    required this.ref,
    required this.router,
    required this.navigatorContext,
  });

  final WidgetRef ref;
  final GoRouter router;
  final BuildContext? Function() navigatorContext;

  DocumentTabsController get _tabs => ref.read(documentTabsControllerProvider);

  bool get _docInFront {
    final t = _tabs;
    return dsRouterLocation(router) == '/' && t.hasTabs && !t.isHomeActive;
  }

  /// ('home'|'page'|'doc', id / index) for every tab, in strip order.
  List<(String, Object)> _entries() {
    final t = _tabs;
    return [
      ('home', ''),
      for (final p in t.pageTabs) ('page', p.id),
      for (var i = 0; i < t.tabs.length; i++) ('doc', i),
    ];
  }

  int _activeEntry() {
    final t = _tabs;
    final e = _entries();
    if (_docInFront)
      return e.indexWhere((x) => x.$1 == 'doc' && x.$2 == t.activeIndex);
    final id = t.activePageId;
    if (id != null) return e.indexWhere((x) => x.$1 == 'page' && x.$2 == id);
    return 0;
  }

  void _activate((String, Object) entry) {
    final t = _tabs;
    switch (entry.$1) {
      case 'home':
        t.activateStartTab();
        router.go('/');
      case 'page':
        final loc = t.activatePage(entry.$2 as String);
        if (loc != null) router.go(loc);
      case 'doc':
        t.activateTab(entry.$2 as int);
        t.showDocument();
        if (dsRouterLocation(router) != '/') router.go('/');
    }
  }

  Future<void> closeActive() async {
    final t = _tabs;
    if (_docInFront) {
      final ctx = navigatorContext();
      if (ctx == null || !ctx.mounted) return;
      // The tab itself, not its index: tabs may open or close meanwhile.
      final tab = t.tabs[t.activeIndex];
      final ok = await confirmCloseDocumentTab(
        context: ctx,
        ref: ref,
        tabs: t,
        index: t.activeIndex,
      );
      final i = t.tabs.indexOf(tab);
      if (ok && i >= 0) t.closeTab(i);
      return;
    }
    final page = t.activePage;
    if (page == null) return;
    final ctx = navigatorContext();
    // No context, no prompt — and no silent loss of unsaved edits.
    if (ctx == null || !ctx.mounted) return;
    if (!await confirmCloseOfficePage(ctx, page.location)) return;
    router.go(t.closePage(page.id));
  }

  void newTab() {
    _tabs.showHome();
    router.go(_tabs.openNewHomeTab());
  }

  Future<void> reopen() async {
    if (!_tabs.canReopen) return;
    await _tabs.reopenLastClosed();
    _tabs.showDocument();
    if (dsRouterLocation(router) != '/') router.go('/');
  }

  void cycle(int delta) {
    final e = _entries();
    if (e.length < 2) return;
    final i = _activeEntry();
    _activate(e[((i < 0 ? 0 : i) + delta) % e.length]);
  }

  void jump(int index) {
    final e = _entries();
    if (e.isEmpty) return;
    _activate(e[index < 0 || index >= e.length ? e.length - 1 : index]);
  }
}
