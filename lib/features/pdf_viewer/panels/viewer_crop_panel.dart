import 'package:document_studio/core/pdf/page_loader.dart';
import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_grid_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_page_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Embedded crop tool: pick a margin preset and the pages to keep, then apply
/// to the open session. Thumbnails show the kept region.
class ViewerCropPanel extends ConsumerStatefulWidget {
  const ViewerCropPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerCropPanel> createState() => _ViewerCropPanelState();
}

class _ViewerCropPanelState extends ConsumerState<ViewerCropPanel> {
  PdfPageScopeKind _scopeKind = PdfPageScopeKind.thisPage;
  String _rangeExpression = '';
  String? _rangeError;
  bool _busy = false;
  PdfDocument? _document;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;
  late final ViewerLiveToolSession _live =
      ref.read(viewerLiveToolSessionProvider);

  static const _defaultCrop = Rect.fromLTRB(0.08, 0.08, 0.92, 0.92);

  /// Crop in displayed-page space (0–1, top-left origin). The handles on the
  /// main page edit the same rect through the live tool session.
  Rect get _normCrop => _live.dragRectNorm ?? _defaultCrop;

  int _loadedPage = 0;
  int _thumbGen = 0;

  /// The page the handles are on (falls back to the viewer's current page).
  int get _page {
    final total = widget.pageCount ?? 1;
    final live = _live.pageIndex1Based;
    final p = live >= 1 ? live : widget.handoff.currentPage1;
    return p.clamp(1, total < 1 ? 1 : total);
  }

  @override
  void initState() {
    super.initState();
    _live.overlayListenable.addListener(_onLive);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPage());
    });
  }

  @override
  void didUpdateWidget(covariant ViewerCropPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handoff.file.path != widget.handoff.file.path ||
        oldWidget.handoff.currentPage1 != widget.handoff.currentPage1 ||
        oldWidget.handoff.password != widget.handoff.password) {
      unawaited(_loadPage());
    }
  }

  @override
  void dispose() {
    _live.overlayListenable.removeListener(_onLive);
    unawaited(_document?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  void _onLive() {
    if (!mounted) return;
    final doc = _document;
    setState(() {
      if (doc != null && _page != _loadedPage) {
        final pg = doc.pages[(_page - 1).clamp(0, doc.pages.length - 1)];
        _loadedPage = _page;
        _pageWidthPt = pg.width;
        _pageHeightPt = pg.height;
      }
    });
  }

  Future<void> _loadPage() async {
    final prev = _document;
    _document = null;
    await prev?.dispose();
    try {
      final doc = await openPdfLazily(widget.handoff.file.path, password: widget.handoff.password);
      _loadedPage = _page;
      final page = await loadPageOnDemand(doc, _page.clamp(1, doc.pages.length)) ??
          doc.pages.first;
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _document = doc;
        _pageWidthPt = page.width;
        _pageHeightPt = page.height;
      });
    } catch (_) {
      if (mounted) setState(() => _document = null);
    }
  }

  String get _sizeLabel {
    final wPt = _normCrop.width * _pageWidthPt;
    final hPt = _normCrop.height * _pageHeightPt;
    String mm(double pt) => (pt * 25.4 / 72).toStringAsFixed(0);
    return '${mm(wPt)} × ${mm(hPt)} mm  ·  '
        '${wPt.toStringAsFixed(0)} × ${hPt.toStringAsFixed(0)} pt';
  }

  Set<int>? _resolvePages() {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return null;
    }
    final resolved = resolvePdfPageScope(
      kind: _scopeKind,
      currentPage1: _page,
      selectedPages1Based: widget.selectedPages1Based,
      totalPages: total,
      rangeExpression: _rangeExpression,
    );
    if (!resolved.isOk) {
      setState(() => _rangeError = resolved.error);
      return null;
    }
    setState(() => _rangeError = null);
    return resolved.pages;
  }

  void _setCrop(Rect r) => _live.setDragRectNorm(r);

  PdfVisibleFraction get _fraction => PdfVisibleFraction(
        left: _normCrop.left,
        top: _normCrop.top,
        right: _normCrop.right,
        bottom: _normCrop.bottom,
      );

  /// Crops the open session working copy (undoable). Does not write the
  /// original file. Matching pages use one qpdf CropBox; pages whose own
  /// rectangles differ each get that page's CropBox.
  Future<void> _apply() async {
    if (_live.dragRectNorm == null) {
      _snack('Drag a rectangle on the page around the area to keep.');
      return;
    }
    final pages = _resolvePages();
    if (pages == null) return;
    if (!_fraction.isUsable) {
      _snack('Crop rectangle is too small.');
      return;
    }
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (session == null) {
      _snack('No open document to update.');
      return;
    }
    final input = session.file;
    final password = session.password ?? widget.handoff.password;
    setState(() => _busy = true);
    try {
      final organize = ref.read(pageOrganizeServiceProvider);
      final out = await organize.cropVisibleFractionToTemp(
        input: input,
        pageNumbers1Based: pages,
        fraction: _fraction,
        passwordsByPath: password == null || password.isEmpty
            ? null
            : {input.path: password},
      );
      final bytes = await File(out.path).readAsBytes();
      unawaited(File(out.path).delete().catchError((_) => File(out.path)));
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: bytes,
        successMessage: pages.length == 1
            ? 'Cropped page ${pages.first}.'
            : 'Cropped ${pages.length} pages.',
      );
      _live.setDragRectNorm(_defaultCrop);
      if (!mounted) return;
      setState(() => _thumbGen++);
      unawaited(_loadPage());
    } on DocumentStudioError catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Set<int> _previewPages(int total) {
    final resolved = resolvePdfPageScope(
      kind: _scopeKind,
      currentPage1: _page,
      selectedPages1Based: widget.selectedPages1Based,
      totalPages: total,
      rangeExpression: _rangeExpression,
    );
    final pages = resolved.pages;
    if (pages == null) return const {};
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = widget.pageCount;
    final ready = total != null && total >= 1;
    final inScope = ready ? _previewPages(total) : const <int>{};
    final crop = _normCrop;

    return ViewerPageGridScaffold(
      applyKey: const Key('viewer_crop_apply'),
      applyLabel: _busy ? 'Cropping…' : 'Crop',
      onApply: _busy || !ready ? null : _apply,
      toolbar: [
        for (final (label, rect) in const [
          ('Full page', Rect.fromLTRB(0, 0, 1, 1)),
          ('Small margins', Rect.fromLTRB(0.04, 0.04, 0.96, 0.96)),
          ('Wide margins', Rect.fromLTRB(0.1, 0.08, 0.9, 0.92)),
          ('Top half', Rect.fromLTRB(0, 0, 1, 0.5)),
          ('Bottom half', Rect.fromLTRB(0, 0.5, 1, 1)),
        ])
          viewerPageToolButton(
            icon: Icons.crop,
            label: label,
            onPressed: _busy ? null : () => _setCrop(rect),
          ),
      ],
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.md,
          DsSpacing.sm,
          DsSpacing.md,
          0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _sizeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            PdfPageScopeField(
              title: 'Apply to',
              kind: _scopeKind,
              onKindChanged: (k) => setState(() => _scopeKind = k),
              rangeExpression: _rangeExpression,
              onRangeExpressionChanged: (v) =>
                  setState(() => _rangeExpression = v),
              selectedPageCount: widget.selectedPages1Based.length,
              rangeError: _rangeError,
              enabled: !_busy,
            ),
          ],
        ),
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator.adaptive())
          : ViewerPageThumbnailGrid(
              itemCount: total,
              itemBuilder: (context, i) {
                final page = i + 1;
                final marked = inScope.contains(page);
                return ViewerPageThumbTile(
                  label: '$page',
                  selected: marked,
                  onTap: _busy
                      ? null
                      : () {
                          _live.setPage(page);
                          setState(() => _scopeKind = PdfPageScopeKind.thisPage);
                        },
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      OrganizeCachedPageThumbnail(
                        key: ValueKey(
                          '${widget.handoff.file.path}#$page#$_thumbGen',
                        ),
                        file: widget.handoff.file,
                        pageNumber1Based: page,
                        password: widget.handoff.password,
                      ),
                      if (marked)
                        _CropFrame(crop: crop),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Hairline frame for the kept region. Does not clip the thumbnail.
class _CropFrame extends StatelessWidget {
  const _CropFrame({required this.crop});

  final Rect crop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;
        if (!w.isFinite || !h.isFinite || w <= 0 || h <= 0) {
          return const SizedBox.shrink();
        }
        return Stack(
          children: [
            Positioned(
              left: crop.left * w,
              top: crop.top * h,
              width: crop.width * w,
              height: crop.height * h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: DsColors.primary, width: 1.5),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
