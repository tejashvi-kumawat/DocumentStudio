import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_page_box.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Change MediaBox/CropBox page size on the open document, commits in place.
class ViewerResizePanel extends ConsumerStatefulWidget {
  const ViewerResizePanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerResizePanel> createState() => _ViewerResizePanelState();
}

class _ViewerResizePanelState extends ConsumerState<ViewerResizePanel> {
  PdfPageScopeKind _scopeKind = PdfPageScopeKind.thisPage;
  String _rangeExpression = '';
  String? _rangeError;
  bool _busy = false;
  PdfDocument? _document;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;
  PdfPaperSize _paperSize = PdfPaperSize.letter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPage());
    });
  }

  @override
  void didUpdateWidget(covariant ViewerResizePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.handoff.file.path != widget.handoff.file.path ||
        oldWidget.handoff.currentPage1 != widget.handoff.currentPage1 ||
        oldWidget.handoff.password != widget.handoff.password) {
      unawaited(_loadPage());
    }
  }

  @override
  void dispose() {
    unawaited(_document?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _loadPage() async {
    final prev = _document;
    _document = null;
    await prev?.dispose();
    try {
      final doc = await PdfDocument.openFile(
        widget.handoff.file.path,
        passwordProvider: widget.handoff.password == null
            ? null
            : () async => widget.handoff.password,
      );
      final pageIndex = math.max(0, widget.handoff.currentPage1 - 1);
      final page = doc.pages[pageIndex.clamp(0, doc.pages.length - 1)];
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _document = doc;
        _pageWidthPt = page.width;
        _pageHeightPt = page.height;
      });
    } catch (_) {}
  }

  Set<int>? _resolvePages() {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return null;
    }
    final resolved = resolvePdfPageScope(
      kind: _scopeKind,
      currentPage1: widget.handoff.currentPage1,
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

  String get _sizePreview {
    final (tw, th) = _paperSize.mediaBoxPt;
    final wMm = tw * 25.4 / 72;
    final hMm = th * 25.4 / 72;
    final curWMm = _pageWidthPt * 25.4 / 72;
    final curHMm = _pageHeightPt * 25.4 / 72;
    return 'Current page ≈ ${curWMm.toStringAsFixed(1)} × '
        '${curHMm.toStringAsFixed(1)} mm\n'
        'Resulting page ≈ ${wMm.toStringAsFixed(1)} × '
        '${hMm.toStringAsFixed(1)} mm '
        '(${tw.toStringAsFixed(0)} × ${th.toStringAsFixed(0)} pt)';
  }

  /// Sets MediaBox and CropBox on the open session. Android writes the boxes
  /// in Dart; desktop prefers qpdf. Content is not scaled or rasterized.
  Future<void> _apply() async {
    final pages = _resolvePages();
    if (pages == null || pages.isEmpty) return;

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
      final LocalFileRef out;
      final useQpdf = !kIsWeb &&
          !Platform.isAndroid &&
          await isQpdfCliPageBoxEditAvailable();
      if (useQpdf) {
        final organize = ref.read(pageOrganizeServiceProvider);
        out = await organize.setPageSizeToTemp(
          input: input,
          pageNumbers1Based: pages,
          paperSize: _paperSize,
          passwordsByPath: password == null || password.isEmpty
              ? null
              : {input.path: password},
        );
      } else {
        final temp = await ref.read(fileStorageProvider).createTempFile(
              prefix: 'resize',
              suffix: '.pdf',
            );
        out = await DartPdfPageBox.setPageSize(
          input: input,
          pageNumbers1Based: pages,
          paperSize: _paperSize,
          outputPath: temp,
          password: password,
        );
      }
      final bytes = await File(out.path).readAsBytes();
      unawaited(File(out.path).delete().catchError((_) => File(out.path)));
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: tabs,
        session: session,
        bytes: bytes,
        successMessage: 'Page size updated.',
      );
      if (mounted) unawaited(_loadPage());
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (tw, th) = _paperSize.mediaBoxPt;
    final previewAspect = tw / math.max(th, 1);

    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_resize_apply'),
      primaryLabel: _busy ? 'Applying…' : 'Apply',
      primaryIcon: Icons.aspect_ratio,
      primaryEnabled: !_busy,
      primaryBusy: _busy,
      onPrimary: _busy ? null : _apply,
      children: [
            PdfPageScopeField(
              kind: _scopeKind,
              onKindChanged: (k) => setState(() => _scopeKind = k),
              rangeExpression: _rangeExpression,
              onRangeExpressionChanged: (v) =>
                  setState(() => _rangeExpression = v),
              selectedPageCount: widget.selectedPages1Based.length,
              rangeError: _rangeError,
            ),
            const SizedBox(height: DsSpacing.md),
            Text(
              'Paper size',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in PdfPaperSize.values)
                  ChoiceChip(
                    label: Text(
                      s.name.toUpperCase(),
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: _paperSize == s,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected: _busy
                        ? null
                        : (selected) {
                            if (selected) setState(() => _paperSize = s);
                          },
                  ),
              ],
            ),
            const SizedBox(height: DsSpacing.sm),
            Text(
              'Sets MediaBox and CropBox. Page content is not scaled or deleted.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.md),
            Text(
              'Size preview',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.xs),
            Text(_sizePreview, style: theme.textTheme.bodySmall),
            const SizedBox(height: DsSpacing.sm),
            SizedBox(
              height: 140,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: DsColors.groupedBackgroundLight,
                  border: Border.all(color: DsColors.borderLight),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_document != null)
                      Opacity(
                        opacity: 0.35,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _pageWidthPt,
                            height: _pageHeightPt,
                            child: PdfPageView(
                              document: _document!,
                              pageNumber: widget.handoff.currentPage1,
                              maximumDpi: 72,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Center(
                      child: AspectRatio(
                        aspectRatio: previewAspect,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFFE4002B),
                              width: 2,
                            ),
                            color: Colors.white.withValues(alpha: 0.15),
                          ),
                          child: Center(
                            child: Text(
                              _paperSize.name.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: const Color(0xFFE4002B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
    );
  }
}
