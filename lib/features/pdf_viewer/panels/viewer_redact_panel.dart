import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
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
      final doc = await PdfDocument.openFile(
        widget.handoff.file.path,
        passwordProvider: widget.handoff.password == null
            ? null
            : () async => widget.handoff.password,
      );
      try {
        final idx = math.max(0, widget.handoff.currentPage1 - 1);
        final page = doc.pages[idx.clamp(0, doc.pages.length - 1)];
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

  Future<void> _runSearch() async {
    final query = _searchCtrl.text.trim();
    final live = ref.read(viewerLiveToolSessionProvider);
    if (query.isEmpty) {
      live.clearSearchHighlights();
      setState(() => _searchStatus = null);
      return;
    }
    try {
      final doc = await PdfDocument.openFile(
        widget.handoff.file.path,
        passwordProvider: widget.handoff.password == null
            ? null
            : () async => widget.handoff.password,
      );
      try {
        final idx = math.max(0, widget.handoff.currentPage1 - 1);
        final page = doc.pages[idx.clamp(0, doc.pages.length - 1)];
        final pageText = await page.loadStructuredText();
        final matches = findPageTextMatches(
          pageText: pageText,
          query: query,
          pageWidthPt: page.width,
          pageHeightPt: page.height,
        );
        live.setSearchHighlightRects([for (final m in matches) m.normRect]);

        final ocrText =
            widget.ocrIndex?.textForPage(widget.handoff.currentPage1);
        final ocrHit = pageTextContainsQuery(ocrText, query);
        if (!mounted) return;
        setState(() {
          if (matches.isNotEmpty) {
            _searchStatus =
                '${matches.length} match${matches.length == 1 ? '' : 'es'} on this page';
          } else if (ocrHit) {
            _searchStatus =
                'Found in OCR index (no boxes) — draw boxes manually';
          } else {
            _searchStatus = 'No matches on this page';
          }
        });
      } finally {
        await doc.dispose();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _searchStatus = 'Search failed');
    }
  }

  void _markAllMatches() {
    final live = ref.read(viewerLiveToolSessionProvider);
    final hits = live.searchHighlightRectsNorm;
    if (hits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Search first to find matches')),
      );
      return;
    }
    live.setRedactRects(hits);
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
    final total = widget.pageCount ?? _openedPageCount;
    if (total == null || total < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page count not ready yet')),
      );
      return;
    }
    final live = ref.read(viewerLiveToolSessionProvider);
    final rects = live.redactRectsNorm.isNotEmpty
        ? live.redactRectsNorm
        : (live.dragRectNorm != null ? [live.dragRectNorm!] : <ui.Rect>[]);
    final usable = [
      for (final r in rects)
        if (r.width >= 0.01 && r.height >= 0.01) r,
    ];
    if (usable.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw or mark at least one redaction box')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final pts = redactRectsFromNorm(
        normRects: usable,
        pageWidthPt: _pageWidthPt,
        pageHeightPt: _pageHeightPt,
      );
      final svc = PdfRedactService(
        organize: ref.read(pageOrganizeServiceProvider),
      );
      final bytes = await svc.redactPageToBytes(
        input: session.file,
        pageIndex1Based: widget.handoff.currentPage1,
        rects: pts,
        totalPages: total,
        password: widget.handoff.password ?? session.password,
      );
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage:
            'Redacted page ${widget.handoff.currentPage1} (content removed).',
      );
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
                title: 'Find on page ${widget.handoff.currentPage1}',
                subtitle:
                    'Search this page, then mark matches. You can also drag '
                    'boxes on the page. Apply removes the underlying text.',
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
