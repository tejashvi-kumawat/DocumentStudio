import 'package:document_studio/features/home/home_screen.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_screen.dart';
import 'package:document_studio/features/pdf_viewer/viewer_shortcut_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Home shell branch body: Home dashboard or the embedded PDF viewer.
///
/// Document tabs live in the window title bar ([DsWindowFrame]) or the
/// compact shell chrome — this widget only swaps the page content.
///
/// Recently used document viewers stay mounted (offstage, tickers paused,
/// focus excluded) so switching tabs keeps scroll position, zoom, open panels
/// and rendered pages instead of reloading the PDF.
class DsDocumentTabShell extends ConsumerStatefulWidget {
  const DsDocumentTabShell({super.key});

  /// Viewers kept alive besides the active one; older ones are rebuilt on
  /// demand to bound memory on large documents.
  static const maxLiveViewers = 5;

  @override
  ConsumerState<DsDocumentTabShell> createState() => _DsDocumentTabShellState();
}

class _DsDocumentTabShellState extends ConsumerState<DsDocumentTabShell> {
  DocumentTabsController? _tabs;

  /// Most recently used first.
  final List<String> _live = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tabs = ref.read(documentTabsControllerProvider);
      _tabs!.addListener(_onTabsChanged);
      _onTabsChanged();
    });
  }

  @override
  void dispose() {
    _tabs?.removeListener(_onTabsChanged);
    super.dispose();
  }

  void _onTabsChanged() {
    _scheduleClearViewerShortcutsWhenHome();
    if (mounted) setState(() {});
  }

  void _scheduleClearViewerShortcutsWhenHome() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tabs = ref.read(documentTabsControllerProvider);
      if (tabs.isHomeActive || !tabs.hasTabs) {
        ref.read(viewerShortcutActionsProvider.notifier).clear();
      }
    });
  }

  void _syncLive(DocumentTabsController tabs) {
    final open = {for (final t in tabs.tabs) t.id};
    _live.removeWhere((id) => !open.contains(id));
    final active = tabs.activeTab?.id;
    if (active != null) {
      _live
        ..remove(active)
        ..insert(0, active);
    }
    if (_live.length > DsDocumentTabShell.maxLiveViewers) {
      _live.removeRange(DsDocumentTabShell.maxLiveViewers, _live.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tabs = ref.watch(documentTabsControllerProvider);

    return ListenableBuilder(
      listenable: tabs,
      builder: (context, _) {
        _syncLive(tabs);
        final showHome = tabs.isHomeActive || !tabs.hasTabs;
        final activeId = showHome ? null : tabs.activeTab?.id;
        // Stable order (by tab id) so reordering MRU never remounts a viewer.
        final ids = [..._live]..sort();
        final index = activeId == null ? 0 : ids.indexOf(activeId) + 1;

        return IndexedStack(
          index: index,
          sizing: StackFit.expand,
          children: [
            _Pane(
              key: const ValueKey<String>('pane_home'),
              visible: showHome,
              child: const HomeScreen(),
            ),
            for (final id in ids)
              _Pane(
                key: ValueKey<String>('pane_$id'),
                visible: id == activeId,
                child: PdfViewerScreen.shellEmbedded(
                  key: ValueKey<String>('viewer_$id'),
                  tabId: id,
                  foreground: id == activeId,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Pane extends StatelessWidget {
  const _Pane({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: visible,
      child: ExcludeFocus(
        excluding: !visible,
        child: HeroMode(enabled: visible, child: child),
      ),
    );
  }
}
