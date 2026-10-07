import 'package:document_studio/core/pdf/page_loader.dart';

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_shape_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

enum MarkupBurnKind { highlight, underline, strikethrough, note }

/// Burn-in page markup (not Acrobat comment threads) via qpdf overlay.
class ViewerMarkupBurnPanel extends ConsumerStatefulWidget {
  const ViewerMarkupBurnPanel({
    super.key,
    required this.handoff,
    this.initialKind = MarkupBurnKind.highlight,
  });

  final PdfViewerDocumentHandoff handoff;
  final MarkupBurnKind initialKind;

  @override
  ConsumerState<ViewerMarkupBurnPanel> createState() =>
      _ViewerMarkupBurnPanelState();
}

class _ViewerMarkupBurnPanelState extends ConsumerState<ViewerMarkupBurnPanel> {
  late MarkupBurnKind _kind;
  final List<ui.Rect> _rects = [];
  ui.Offset? _dragStart;
  ui.Rect? _draft;
  final _noteCtrl = TextEditingController(text: 'Note');
  bool _busy = false;
  PdfDocument? _document;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    unawaited(_loadPage());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    unawaited(_document?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _loadPage() async {
    final prev = _document;
    _document = null;
    await prev?.dispose();
    try {
      final doc = await openPdfLazily(
        widget.handoff.file.path,
        password: widget.handoff.password,
      );
      final idx = math.max(0, widget.handoff.currentPage1 - 1);
      final page =
          await loadPageOnDemand(doc, (idx + 1).clamp(1, doc.pages.length)) ??
          doc.pages.first;
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() {
        _document = doc;
        _pageWidthPt = page.width;
        _pageHeightPt = page.height;
        _rects.clear();
        _draft = null;
      });
    } catch (_) {}
  }

  List<PdfOverlayRect> _toOverlayRects() {
    final out = <PdfOverlayRect>[];
    for (final r in _rects) {
      final left = r.left * _pageWidthPt;
      final right = r.right * _pageWidthPt;
      final topNorm = r.top;
      final bottomNorm = r.bottom;
      final topPt = (1 - topNorm) * _pageHeightPt;
      final bottomPt = (1 - bottomNorm) * _pageHeightPt;
      final y = math.min(bottomPt, topPt);
      final h = (topPt - bottomPt).abs();
      final w = (right - left).abs();
      switch (_kind) {
        case MarkupBurnKind.highlight:
          out.add(
            PdfOverlayRect(
              xPt: left,
              yPt: y,
              widthPt: w,
              heightPt: h,
              fillRgb: const (1.0, 0.95, 0.2),
              fillOpacity: 0.45,
            ),
          );
        case MarkupBurnKind.underline:
          out.add(
            PdfOverlayRect(
              xPt: left,
              yPt: y,
              widthPt: w,
              heightPt: 1.5,
              fillRgb: const (0.89, 0.0, 0.17),
            ),
          );
        case MarkupBurnKind.strikethrough:
          out.add(
            PdfOverlayRect(
              xPt: left,
              yPt: y + h / 2 - 0.75,
              widthPt: w,
              heightPt: 1.5,
              fillRgb: const (0.2, 0.2, 0.2),
            ),
          );
        case MarkupBurnKind.note:
          out.add(
            PdfOverlayRect(
              xPt: left,
              yPt: y,
              widthPt: math.max(w, 48),
              heightPt: math.max(h, 36),
              fillRgb: const (1.0, 0.95, 0.55),
              strokeRgb: const (0.75, 0.65, 0.2),
              strokeWidthPt: 1,
            ),
          );
      }
    }
    return out;
  }

  Future<void> _apply() async {
    if (_rects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drag at least one region on the page')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final page = widget.handoff.currentPage1;
      final temp = await ref
          .read(fileStorageProvider)
          .createTempFile(prefix: 'markup-burn', suffix: '.pdf');
      var workingPath = temp;
      await ref
          .read(pdfOverlayServiceProvider)
          .applyMarkupRectsOnPage(
            input: widget.handoff.file,
            outputPath: workingPath,
            pageIndex1Based: page,
            rects: _toOverlayRects(),
            password: widget.handoff.password,
          );

      if (_kind == MarkupBurnKind.note && _noteCtrl.text.trim().isNotEmpty) {
        final noteTemp = await ref
            .read(fileStorageProvider)
            .createTempFile(prefix: 'markup-note', suffix: '.pdf');
        final r = _rects.first;
        final xPt = r.left * _pageWidthPt + 6;
        final yPt = (1 - r.bottom) * _pageHeightPt + 8;
        final builder = PdfOverlayTextBuilder();
        // Load page count from open doc
        final pageCount = _document?.pages.length ?? 1;
        final overlay = builder.build(
          pageCount: pageCount,
          pageWidthPt: (_) => _pageWidthPt,
          pageHeightPt: (_) => _pageHeightPt,
          linesForPage: (p) {
            if (p != page) return const [];
            return [
              PdfOverlayTextLine(
                text: _noteCtrl.text.trim(),
                xPt: xPt,
                yPt: yPt,
                fontSizePt: 9,
              ),
            ];
          },
        );
        final overlayPath = '$noteTemp.overlay.pdf';
        await File(overlayPath).writeAsBytes(overlay, flush: true);
        // Re-use overlay service path via watermark-like apply: write through qpdf
        // by applying typed signature style — use applyMarkup then text via
        // applyTypedSignature is wrong. Use overlay service private path via
        // applyTextWatermark with custom anchor for first rect only.
        await ref
            .read(pdfOverlayServiceProvider)
            .applyTextWatermark(
              input: LocalFileRef(path: workingPath, displayName: 'tmp.pdf'),
              outputPath: noteTemp,
              options: WatermarkOptions(
                textTemplate: _noteCtrl.text.trim(),
                fontSizePt: 9,
                opacity: 1,
                placement: WatermarkPlacement.topLeft,
                pages1Based: {page},
                anchorLeftNorm: r.left + 0.02,
                anchorTopNorm: r.top + 0.08,
              ),
              password: widget.handoff.password,
            );
        workingPath = noteTemp;
      }

      final bytes = await File(workingPath).readAsBytes();
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session != null &&
          session.sameDocumentPath(widget.handoff.file.path)) {
        await commitBytesToSession(
          context: context,
          storage: ref.read(fileStorageProvider),
          tabs: ref.read(documentTabsControllerProvider),
          session: session,
          bytes: Uint8List.fromList(bytes),
          successMessage: 'Markup burned onto page.',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = widget.handoff.currentPage1;

    return ColoredBox(
      color: const Color(0xFFF4F4F4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Burns visible marks onto the page (not a comment thread). '
              'Saved in place and undoable.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.md),
            Text(
              'Mark type',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.xs),
            SegmentedButton<MarkupBurnKind>(
              segments: const [
                ButtonSegment(
                  value: MarkupBurnKind.highlight,
                  label: Text('Highlight'),
                  tooltip: 'Yellow highlight band',
                ),
                ButtonSegment(
                  value: MarkupBurnKind.underline,
                  label: Text('Underline'),
                  tooltip: 'Underline stroke',
                ),
                ButtonSegment(
                  value: MarkupBurnKind.strikethrough,
                  label: Text('Strike'),
                  tooltip: 'Strikethrough stroke',
                ),
                ButtonSegment(
                  value: MarkupBurnKind.note,
                  label: Text('Note'),
                  tooltip: 'Sticky note appearance',
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() {
                _kind = v.first;
                _rects.clear();
              }),
            ),
            if (_kind == MarkupBurnKind.note) ...[
              const SizedBox(height: DsSpacing.sm),
              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(
                  labelText: 'Note text',
                  labelStyle: TextStyle(fontSize: 13),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ],
            const SizedBox(height: DsSpacing.md),
            Text(
              'Drag on page $page',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.xs),
            AspectRatio(
              aspectRatio: _pageWidthPt / math.max(_pageHeightPt, 1),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black26),
                  color: Colors.white,
                ),
                child: _document == null
                    ? const Center(child: CircularProgressIndicator())
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            onPanStart: (d) {
                              final n = Offset(
                                d.localPosition.dx / constraints.maxWidth,
                                d.localPosition.dy / constraints.maxHeight,
                              );
                              setState(() {
                                _dragStart = n;
                                _draft = Rect.fromPoints(n, n);
                              });
                            },
                            onPanUpdate: (d) {
                              if (_dragStart == null) return;
                              final n = Offset(
                                (d.localPosition.dx / constraints.maxWidth)
                                    .clamp(0.0, 1.0),
                                (d.localPosition.dy / constraints.maxHeight)
                                    .clamp(0.0, 1.0),
                              );
                              setState(() {
                                _draft = Rect.fromPoints(_dragStart!, n);
                              });
                            },
                            onPanEnd: (_) {
                              final draft = _draft;
                              if (draft != null &&
                                  draft.width > 0.01 &&
                                  draft.height > 0.005) {
                                setState(() {
                                  _rects.add(draft);
                                  _draft = null;
                                  _dragStart = null;
                                });
                              } else {
                                setState(() {
                                  _draft = null;
                                  _dragStart = null;
                                });
                              }
                            },
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                PdfPageView(
                                  document: _document!,
                                  pageNumber: page,
                                  maximumDpi: 96,
                                ),
                                CustomPaint(
                                  painter: _MarkupPainter(
                                    rects: [..._rects, ?_draft],
                                    kind: _kind,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: DsSpacing.md),
            Tooltip(
              message: 'Burn marks onto the page and save in place',
              child: DsPrimaryButton(
                key: const Key('viewer_markup_burn_apply'),
                onPressed: _busy ? null : _apply,
                label: _busy ? 'Working…' : 'Apply markup',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkupPainter extends CustomPainter {
  _MarkupPainter({required this.rects, required this.kind});

  final List<ui.Rect> rects;
  final MarkupBurnKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in rects) {
      final rect = Rect.fromLTRB(
        r.left * size.width,
        r.top * size.height,
        r.right * size.width,
        r.bottom * size.height,
      );
      switch (kind) {
        case MarkupBurnKind.highlight:
          canvas.drawRect(rect, Paint()..color = const Color(0x73FFF200));
        case MarkupBurnKind.underline:
          canvas.drawLine(
            Offset(rect.left, rect.bottom),
            Offset(rect.right, rect.bottom),
            Paint()
              ..color = const Color(0xFFE4002B)
              ..strokeWidth = 2,
          );
        case MarkupBurnKind.strikethrough:
          canvas.drawLine(
            Offset(rect.left, rect.center.dy),
            Offset(rect.right, rect.center.dy),
            Paint()
              ..color = Colors.black87
              ..strokeWidth = 2,
          );
        case MarkupBurnKind.note:
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(2)),
            Paint()..color = const Color(0xE6FFF59D),
          );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MarkupPainter oldDelegate) => true;
}
