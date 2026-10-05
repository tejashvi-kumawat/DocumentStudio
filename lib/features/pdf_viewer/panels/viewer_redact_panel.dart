import 'package:document_studio/core/pdf/page_loader.dart';
import 'package:document_studio/core/pdf/large_doc_policy.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_text_match.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/infrastructure/ocr/pdf_background_ocr_index.dart';
import 'package:document_studio/infrastructure/pdf/pdf_redact_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Find matches, mark redaction boxes, Apply flattens so text cannot be extracted.
class ViewerRedactPanel extends ConsumerStatefulWidget {
  const ViewerRedactPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.ocrIndex,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final PdfBackgroundOcrIndex? ocrIndex;

  @override
  ConsumerState<ViewerRedactPanel> createState() => _ViewerRedactPanelState();
}

class _ViewerRedactPanelState extends ConsumerState<ViewerRedactPanel> {
  final _searchCtrl = TextEditingController();
  bool _busy = false;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;
  int? _openedPageCount;
  String? _searchStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(viewerLiveToolSessionProvider).activate(
            ViewerToolId.redact,
            pageIndex1Based: widget.handoff.currentPage1,
          );
    });
    unawaited(_primePageSize());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _primePageSize() async {
    try {
      final doc = await openPdfLazily(widget.handoff.file.path, password: widget.handoff.password);
      try {
        final idx = math.max(0, widget.handoff.currentPage1 - 1);
        final page = await loadPageOnDemand(
              doc,
              (idx + 1).clamp(1, doc.pages.length),
            ) ??
            doc.pages.first;
        if (!mounted) return;
        setState(() {
          _openedPageCount = doc.pages.length;
          _pageWidthPt = page.width;
          _pageHeightPt = page.height;
        });
      } finally {
        await doc.dispose();
      }
    } catch (_) {}
  }

  /// Boxes marked on pages other than the one on screen (page → boxes).
  final Map<int, List<ui.Rect>> _docMarks = {};
  final Map<int, List<ui.Rect>> _hits = {};

  int? _shownPage;

  /// Keeps marks per page: when the viewer moves to another page, stash the
  /// boxes of the old one and show the boxes / matches of the new one.
  void _syncPage(ViewerLiveToolSession live) {
    final page = live.pageIndex1Based;
    final prev = _shownPage;
    if (prev == page) return;
    _shownPage = page;
    if (prev == null) return;
    final leaving = live.redactRectsNorm;
    if (leaving.isNotEmpty) {
      _docMarks[prev] = List.of(leaving);
    } else {
      _docMarks.remove(prev);
    }
    final next = List<ui.Rect>.of(_docMarks[page] ?? const []);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      live.setRedactRects(next);
      _showHitsForPage(live, page);
    });
  }

  /// Searches the whole document (not just the open page).
  Future<void> _runSearch() async {
    final query = _searchCtrl.text.trim();
    final live = ref.read(viewerLiveToolSessionProvider);
    _hits.clear();
    if (query.isEmpty) {
      live.clearSearchHighlights();
      setState(() => _searchStatus = null);
      return;
    }
    setState(() => _searchStatus = 'Searching…');
    try {
      final doc = await openPdfLazily(
        widget.handoff.file.path,
        password: widget.handoff.password,
      );
      try {
        // Measure all pages in small slices (renders keep interleaving).
        unawaited(doc.loadPagesProgressively(
          loadUnitDuration: const Duration(milliseconds: 40),
        ));
        var total = 0;
        for (var i = 0; i < doc.pages.length; i++) {
          final page = await doc.pages[i]
              .waitForLoaded(timeout: const Duration(seconds: 30));
          if (page == null) continue;
          final pageText = await page.loadStructuredText();
          final matches = findPageTextMatches(
            pageText: pageText,
            query: query,
            pageWidthPt: page.width,
            pageHeightPt: page.height,
          );
          if (matches.isNotEmpty) {
            _hits[i + 1] = [for (final m in matches) m.normRect];
            total += matches.length;
          }
          if (!mounted) return;
        }
        _showHitsForPage(live, live.pageIndex1Based);
        if (!mounted) return;
        setState(() {
          _searchStatus = total == 0
              ? 'No matches in the document'
              : '$total match${total == 1 ? '' : 'es'} on '
                  '${_hits.length} page${_hits.length == 1 ? '' : 's'}';
        });
      } finally {
        await doc.dispose();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchStatus = 'Search failed');
    }
  }

  void _showHitsForPage(ViewerLiveToolSession live, int page) {
    live.setSearchHighlightRects(_hits[page] ?? const []);
  }

  void _markAllMatches() {
    final live = ref.read(viewerLiveToolSessionProvider);
    if (_hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search first to find matches')),
      );
      return;
    }
    final current = live.pageIndex1Based;
    _hits.forEach((page, rects) {
      if (page != current) _docMarks[page] = List.of(rects);
    });
    live.setRedactRects(_hits[current] ?? const []);
    setState(() {});
  }

  Future<void> _apply() async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Open a PDF before redacting.')),
      );
      return;
    }
    final live = ref.read(viewerLiveToolSessionProvider);
    final current = live.pageIndex1Based;
    final onScreen = live.redactRectsNorm.isNotEmpty
        ? live.redactRectsNorm
        : (live.dragRectNorm != null ? [live.dragRectNorm!] : <ui.Rect>[]);
    final marks = <int, List<ui.Rect>>{
      for (final e in _docMarks.entries)
        if (e.key != current) e.key: e.value,
      if (onScreen.isNotEmpty) current: onScreen,
    };
    for (final k in marks.keys.toList()) {
      marks[k] = [
        for (final r in marks[k]!)
          if (r.width >= 0.005 && r.height >= 0.005) r,
      ];
      if (marks[k]!.isEmpty) marks.remove(k);
    }
    if (marks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw or mark at least one redaction box')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final storage = ref.read(fileStorageProvider);
      final svc = PdfRedactService(
        organize: ref.read(pageOrganizeServiceProvider),
      );
      final read = await LargeDocPolicy.readBounded(session);
      if (read == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(LargeDocPolicy.message)),
          );
        }
        return;
      }
      var bytes = read;
      var flattened = 0;
      for (final page in marks.keys.toList()..sort()) {
        final rects = marks[page]!;
        final fast = redactPageVector(bytes, page, rects);
        if (fast != null && !fast.imagesTouched) {
          bytes = fast.bytes;
          continue;
        }
        // A picture is under a box: flatten just this page.
        final geo = PdfEditDocument.open(bytes).pageGeometry(page);
        final tmp = await storage.createTempFile(prefix: 'redact', suffix: '.pdf');
        await File(tmp).writeAsBytes(bytes, flush: true);
        final total = PdfEditDocument.open(bytes).pageCount;
        bytes = await svc.redactPageToBytes(
          input: LocalFileRef(path: tmp, displayName: 'redact.pdf'),
          pageIndex1Based: page,
          rects: redactRectsFromNorm(
            normRects: rects,
            pageWidthPt: geo.displayWidth,
            pageHeightPt: geo.displayHeight,
          ),
          totalPages: total,
          password: widget.handoff.password ?? session.password,
        );
        flattened++;
        await storage.deleteIfExists(tmp);
      }
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: storage,
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage: marks.length == 1
            ? 'Redacted page ${marks.keys.first} (content removed).'
            : 'Redacted ${marks.length} pages (content removed'
                '${flattened > 0 ? ', $flattened flattened' : ''}).',
      );
      _docMarks.clear();
      _hits.clear();
      live.clearSearchHighlights();
      live.setRedactRects(const []);
      live.deactivate();
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.recoveryHint ?? e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _stackedActions(List<Widget> actions) {
    return Wrap(
      spacing: DsSpacing.sm,
      runSpacing: DsSpacing.xs,
      children: [
        for (final action in actions)
          action,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.watch(viewerLiveToolSessionProvider);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ListenableBuilder(
        listenable: live,
        builder: (context, _) {
          _syncPage(live);
          final count = live.redactRectsNorm.length;
          return ViewerToolFormScaffold(
            primaryLabel: _busy ? 'Redacting…' : 'Apply',
            primaryIcon: Icons.hide_source,
            primaryEnabled: !_busy,
            primaryBusy: _busy,
            onPrimary: _apply,
            children: [
              ViewerToolFormSection(
                first: true,
                title: 'Find in document',
                subtitle:
                    'Search every page, then mark all matches. You can also drag boxes '
                    'on the page. Apply removes the underlying text for good.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      key: const Key('viewer_redact_search'),
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Text to find',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => unawaited(_runSearch()),
                    ),
                    const SizedBox(height: DsSpacing.md),
                    _stackedActions([
                      OutlinedButton(
                        onPressed: () => unawaited(_runSearch()),
                        child: const Text('Find'),
                      ),
                      OutlinedButton(
                        onPressed: _markAllMatches,
                        child: const Text('Mark all matches'),
                      ),
                    ]),
                    if (_searchStatus != null) ...[
                      const SizedBox(height: DsSpacing.md),
                      Text(
                        _searchStatus!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ],
                ),
              ),
              ViewerToolFormSection(
                title: 'Marked boxes',
                subtitle: count == 0
                    ? 'No boxes yet. Search, or add one and adjust it on the page.'
                    : '$count box${count == 1 ? '' : 'es'} on this page.',
                child: _stackedActions([
                  OutlinedButton(
                    onPressed: () {
                      live.addRedactRect(
                        const ui.Rect.fromLTRB(0.2, 0.2, 0.8, 0.35),
                      );
                      setState(() {});
                    },
                    child: const Text('Add box'),
                  ),
                  OutlinedButton(
                    onPressed: count == 0
                        ? null
                        : () {
                            live.removeActiveRedactRect();
                            setState(() {});
                          },
                    child: const Text('Remove selected box'),
                  ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}
