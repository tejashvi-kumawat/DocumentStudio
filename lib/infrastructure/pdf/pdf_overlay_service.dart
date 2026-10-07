import 'package:document_studio/infrastructure/pdf/edit/pdf_page_stamp.dart';
import 'package:flutter/foundation.dart' show compute;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/domain/pdf_stamp/pdf_page_stamp_models.dart';
import 'package:document_studio/domain/pdf_stamp/stamp_label_layout.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_image_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_ink_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_shape_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:document_studio/infrastructure/pdf/pdf_stamp_image_prep.dart';
import 'package:document_studio/infrastructure/pdf/pdf_watermark_overlay_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Applies text overlays via generated PDF + qpdf `--overlay` (DS-HDR-001, DS-PGN-001).
class PdfOverlayService {
  PdfOverlayService({required this._render, QpdfCliRunner? cli})
    : _cli = cli ?? QpdfCliRunner();

  final PdfRenderPort _render;
  final QpdfCliRunner _cli;

  Future<LocalFileRef> applyHeaderFooter({
    required LocalFileRef input,
    required String outputPath,
    required HeaderFooterOptions options,
    String? password,
  }) async {
    if (!options.hasContent) {
      throw ArgumentError('Header or footer text required');
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pages = options.pages1Based;
    return _applyOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      linesForPage: (page, ctx) {
        if (pages != null && !pages.contains(page)) return [];
        final (w, h) = sizes[page - 1];
        final lines = <PdfOverlayTextLine>[];
        final x = switch (options.alignment) {
          HeaderFooterAlignment.left => 54.0,
          HeaderFooterAlignment.center => w / 2,
          HeaderFooterAlignment.right => w - 54.0,
        };
        final center = options.alignment == HeaderFooterAlignment.center;
        if (options.headerTemplate.trim().isNotEmpty) {
          lines.add(
            PdfOverlayTextLine(
              text: ctx.resolve(options.headerTemplate),
              xPt: x,
              yPt: h - 36,
              fontSizePt: options.fontSizePt,
              centerAtAnchor: center,
            ),
          );
        }
        if (options.footerTemplate.trim().isNotEmpty) {
          lines.add(
            PdfOverlayTextLine(
              text: ctx.resolve(options.footerTemplate),
              xPt: x,
              yPt: 36,
              fontSizePt: options.fontSizePt,
              centerAtAnchor: center,
            ),
          );
        }
        return lines;
      },
    );
  }

  /// Burns a text or image watermark laid out by [layoutWatermark] — the same
  /// geometry the live preview paints — onto [pages1Based] (all when null).
  Future<LocalFileRef> applyWatermark({
    required LocalFileRef input,
    required String outputPath,
    required WatermarkSpec spec,
    Uint8List? imageBytes,
    Set<int>? pages1Based,
    bool behindContent = false,
    String? password,
  }) async {
    final sizes = await _loadPageSizes(input, password: password);
    PdfMarkImageData? image;
    var effective = spec;
    if (spec.isImage) {
      final bytes = imageBytes;
      image = bytes == null ? null : PdfMarkImageData.fromEncoded(bytes);
      if (image == null) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.invalidFile,
          message: 'Unsupported or corrupt image',
        );
      }
      effective = spec.copyWith(imageAspect: image.aspect);
    } else if (spec.text.trim().isEmpty) {
      throw ArgumentError('Watermark text required');
    }
    final targets = pages1Based;
    if (targets != null) {
      for (final page in targets) {
        final issues = validateImageStampPageRequest(
          targetPage1Based: page,
          pageCount: sizes.length,
        );
        if (issues.isNotEmpty) throw ArgumentError(issues.first);
      }
    }
    String? title;
    if (!effective.isImage && effective.text.contains('{title}')) {
      title = (await _render.loadInfo(input, password: password)).title;
    }
    final overlayBytes = PdfWatermarkOverlayBuilder().build(
      pageCount: sizes.length,
      pageSizePt: (page) => sizes[page - 1],
      image: image,
      marksForPage: (page) {
        if (targets != null && !targets.contains(page)) {
          return const PdfMarkPage();
        }
        final (w, h) = sizes[page - 1];
        final ctx = PdfMarkupTemplateContext(
          file: input,
          pageIndex1Based: page,
          pageCount: sizes.length,
          documentTitle: title,
        );
        return watermarkMarksToPdf(
          layoutWatermark(
            spec: effective,
            pageWidthPt: w,
            pageHeightPt: h,
            resolvedText: effective.isImage ? '' : ctx.resolve(effective.text),
          ),
          spec: effective,
          pageWidthPt: w,
          pageHeightPt: h,
        );
      },
    );
    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
      underlay: behindContent,
    );
  }

  Future<LocalFileRef> applyTextWatermark({
    required LocalFileRef input,
    required String outputPath,
    required WatermarkOptions options,
    String? password,
  }) async {
    if (!options.hasContent) {
      throw ArgumentError('Watermark text required');
    }
    final centered =
        !options.hasCustomAnchor &&
        (options.tiled ||
            options.placement == WatermarkPlacement.diagonalCenter ||
            options.placement == WatermarkPlacement.center);
    if (centered) {
      return applyWatermark(
        input: input,
        outputPath: outputPath,
        spec: WatermarkSpec(
          text: options.textTemplate,
          fontSizePt: options.fontSizePt,
          opacity: options.opacity,
          rotationDegrees: options.effectiveRotationDegrees,
          colorRgb: options.fillRgb ?? WatermarkSpec.defaultColorRgb,
          tiled: options.tiled,
          position: options.position,
        ),
        pages1Based: options.pages1Based,
        behindContent: options.behindContent,
        password: password,
      );
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pages = options.pages1Based;
    return _applyOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      underlay: options.behindContent,
      linesForPage: (page, ctx) {
        if (pages != null && !pages.contains(page)) return [];
        final text = ctx.resolve(options.textTemplate);
        final (w, h) = sizes[page - 1];
        return [_watermarkLine(text, options, pageWidthPt: w, pageHeightPt: h)];
      },
    );
  }

  /// Image watermark (centered or tiled); [rotationDegrees] is counter-clockwise.
  Future<LocalFileRef> applyImageWatermark({
    required LocalFileRef input,
    required String outputPath,
    required Uint8List imageBytes,
    required double opacity,
    required double rotationDegrees,
    required double heightFrac,
    required bool tiled,
    Set<int>? pages1Based,
    bool behindContent = false,
    String? password,
  }) {
    return applyWatermark(
      input: input,
      outputPath: outputPath,
      spec: WatermarkSpec(
        imageAspect: 1,
        opacity: opacity,
        rotationDegrees: rotationDegrees,
        imageHeightFrac: heightFrac,
        tiled: tiled,
      ),
      imageBytes: imageBytes,
      pages1Based: pages1Based,
      behindContent: behindContent,
      password: password,
    );
  }

  PdfOverlayTextLine _watermarkLine(
    String text,
    WatermarkOptions options, {
    required double pageWidthPt,
    required double pageHeightPt,
  }) {
    final w = pageWidthPt;
    final h = pageHeightPt;
    final fill = options.fillRgb;
    if (options.hasCustomAnchor) {
      final left = options.anchorLeftNorm!.clamp(0.0, 1.0);
      final top = options.anchorTopNorm!.clamp(0.0, 1.0);
      final x = left * w;
      final y = (1 - top) * h - options.fontSizePt * 0.35;
      return PdfOverlayTextLine(
        text: text,
        xPt: x,
        yPt: y.clamp(0.0, h),
        fontSizePt: options.fontSizePt,
        opacity: options.opacity,
        rotationDegrees: options.effectiveRotationDegrees,
        centerAtAnchor: false,
        fillRgb: fill,
      );
    }
    final (x, y, center) = switch (options.placement) {
      WatermarkPlacement.diagonalCenter => (w / 2, h / 2, true),
      WatermarkPlacement.center => (w / 2, h / 2, true),
      WatermarkPlacement.bottomRight => (w - 72, 72.0, false),
      WatermarkPlacement.topLeft => (72.0, h - 72, false),
    };
    return PdfOverlayTextLine(
      text: text,
      xPt: x,
      yPt: y,
      fontSizePt: options.fontSizePt,
      opacity: options.opacity,
      rotationDegrees: options.effectiveRotationDegrees,
      centerAtAnchor: center,
      fillRgb: fill,
    );
  }

  /// Typed visual signature text on a single page (qpdf overlay).
  Future<LocalFileRef> applyTypedSignatureOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required String signatureText,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
  }) async {
    final issues = validateTypedSignatureRequest(signatureText);
    if (issues.isNotEmpty) {
      throw ArgumentError(issues.first);
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pageIssues = validateImageStampPageRequest(
      targetPage1Based: pageIndex1Based,
      pageCount: sizes.length,
    );
    if (pageIssues.isNotEmpty) {
      throw ArgumentError(pageIssues.first);
    }
    final idx = pageIndex1Based - 1;
    final (w, h) = sizes[idx];
    final anchor = typedSignatureTextAnchor(
      pageWidthPt: w,
      pageHeightPt: h,
      text: signatureText,
      layout: layout,
    );
    return _applyOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      linesForPage: (page, ctx) {
        if (page != pageIndex1Based) return [];
        return [
          PdfOverlayTextLine(
            text: signatureText.trim(),
            xPt: anchor.xPt,
            yPt: anchor.yPt,
            fontSizePt: anchor.fontSizePt,
          ),
        ];
      },
    );
  }

  /// Arbitrary text lines burned onto one page (form fill flatten, etc.).
  Future<LocalFileRef> applyTextLinesOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required List<PdfOverlayTextLine> lines,
    String? password,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('At least one text line is required');
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pageIssues = validateImageStampPageRequest(
      targetPage1Based: pageIndex1Based,
      pageCount: sizes.length,
    );
    if (pageIssues.isNotEmpty) {
      throw ArgumentError(pageIssues.first);
    }
    return _applyOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      linesForPage: (page, ctx) {
        if (page != pageIndex1Based) return [];
        return lines;
      },
    );
  }

  /// JPEG/PNG image stamp on one or more pages (qpdf overlay).
  Future<LocalFileRef> applyImageStampOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required List<int> imageBytes,
    PdfPageStampLayout layout = const PdfPageStampLayout(),
    String? password,
    Set<int>? pages1Based,
    double opacity = 1,
    double rotationDegrees = 0,
  }) async {
    final sizes = await _loadPageSizes(input, password: password);
    final targets = pages1Based ?? {pageIndex1Based};
    for (final page in targets) {
      final pageIssues = validateImageStampPageRequest(
        targetPage1Based: page,
        pageCount: sizes.length,
      );
      if (pageIssues.isNotEmpty) {
        throw ArgumentError(pageIssues.first);
      }
    }
    final raster = img.decodeImage(Uint8List.fromList(imageBytes));
    if (raster == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Unsupported or corrupt image',
      );
    }
    final source = Uint8List.fromList(imageBytes);
    return _applyImageOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      imagesForPage: (page) {
        if (!targets.contains(page)) return [];
        final (w, h) = sizes[page - 1];
        final rect = defaultImageStampRect(
          pageWidthPt: w,
          pageHeightPt: h,
          imageWidthPx: raster.width,
          imageHeightPx: raster.height,
          layout: layout,
        );
        return [
          buildImageStampOverlayLine(
            sourceBytes: source,
            rect: rect,
            opacity: opacity,
            rotationDegrees: rotationDegrees,
          ),
        ];
      },
    );
  }

  /// Burns rubber-stamp label boxes (normalized, top-left origin boxes) onto
  /// [pageIndex1Based] in one pass, using [layoutStampLabel] like the preview.
  Future<LocalFileRef> applyStampLabelsOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required List<({Rect boxNorm, String label, (double, double, double) rgb})>
    stamps,
    String? password,
  }) async {
    if (stamps.isEmpty) throw ArgumentError('Place at least one stamp');
    final sizes = await _loadPageSizes(input, password: password);
    final pageIssues = validateImageStampPageRequest(
      targetPage1Based: pageIndex1Based,
      pageCount: sizes.length,
    );
    if (pageIssues.isNotEmpty) throw ArgumentError(pageIssues.first);
    final (w, h) = sizes[pageIndex1Based - 1];
    final rects = <PdfMarkRect>[];
    final texts = <PdfMarkText>[];
    for (final s in stamps) {
      final layout = layoutStampLabel(
        leftNorm: s.boxNorm.left,
        topNorm: s.boxNorm.top,
        rightNorm: s.boxNorm.right,
        bottomNorm: s.boxNorm.bottom,
        pageWidthPt: w,
        pageHeightPt: h,
        label: s.label,
      );
      final marks = stampLabelToPdf(
        layout,
        rgb: s.rgb,
        pageWidthPt: w,
        pageHeightPt: h,
      );
      rects.addAll(marks.rects);
      texts.addAll(marks.texts);
    }
    final overlayBytes = PdfWatermarkOverlayBuilder().build(
      pageCount: sizes.length,
      pageSizePt: (page) => sizes[page - 1],
      marksForPage: (page) => page == pageIndex1Based
          ? PdfMarkPage(rects: rects, texts: texts)
          : const PdfMarkPage(),
    );
    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
    );
  }

  /// Burns ink strokes onto [pageIndex1Based] via a vector overlay PDF + qpdf.
  Future<LocalFileRef> applyInkStrokesOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required List<PdfInkStroke> strokes,
    String? password,
  }) async {
    if (strokes.isEmpty) {
      throw ArgumentError('Draw at least one stroke');
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pageIssues = validateImageStampPageRequest(
      targetPage1Based: pageIndex1Based,
      pageCount: sizes.length,
    );
    if (pageIssues.isNotEmpty) {
      throw ArgumentError(pageIssues.first);
    }
    final builder = PdfOverlayInkBuilder();
    final overlayBytes = builder.build(
      pageCount: sizes.length,
      pageWidthPt: (page) => sizes[page - 1].$1,
      pageHeightPt: (page) => sizes[page - 1].$2,
      strokesForPage: (page) {
        if (page != pageIndex1Based) return const [];
        return strokes;
      },
    );
    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
    );
  }

  /// Burns filled/stroked rectangles onto [pageIndex1Based] (survives reload).
  Future<LocalFileRef> applyMarkupRectsOnPage({
    required LocalFileRef input,
    required String outputPath,
    required int pageIndex1Based,
    required List<PdfOverlayRect> rects,
    String? password,
  }) async {
    if (rects.isEmpty) {
      throw ArgumentError('Draw at least one markup shape');
    }
    final sizes = await _loadPageSizes(input, password: password);
    final pageIssues = validateImageStampPageRequest(
      targetPage1Based: pageIndex1Based,
      pageCount: sizes.length,
    );
    if (pageIssues.isNotEmpty) {
      throw ArgumentError(pageIssues.first);
    }
    final builder = PdfOverlayShapeBuilder();
    final overlayBytes = builder.build(
      pageCount: sizes.length,
      pageWidthPt: (page) => sizes[page - 1].$1,
      pageHeightPt: (page) => sizes[page - 1].$2,
      rectsForPage: (page) {
        if (page != pageIndex1Based) return const [];
        return rects;
      },
    );
    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
    );
  }

  Future<LocalFileRef> applyPageNumbers({
    required LocalFileRef input,
    required String outputPath,
    required PageNumberOptions options,
    String? password,
  }) async {
    final sizes = await _loadPageSizes(input, password: password);
    final pages = options.pages1Based;
    return _applyOverlay(
      input: input,
      outputPath: outputPath,
      password: password,
      pageSizes: sizes,
      linesForPage: (page, ctx) {
        if (pages != null && !pages.contains(page)) return [];
        final (w, h) = sizes[page - 1];
        final x = switch (options.alignment) {
          HeaderFooterAlignment.left => 54.0,
          HeaderFooterAlignment.center => w / 2,
          HeaderFooterAlignment.right => w - 54.0,
        };
        final y = options.vertical == PageNumberVertical.top ? h - 36.0 : 36.0;
        return [
          PdfOverlayTextLine(
            text: options.labelForPage(page, pageCount: sizes.length),
            xPt: x,
            yPt: y,
            fontSizePt: options.fontSizePt,
            centerAtAnchor: options.alignment == HeaderFooterAlignment.center,
          ),
        ];
      },
    );
  }

  Future<LocalFileRef> _applyOverlay({
    required LocalFileRef input,
    required String outputPath,
    required List<PdfOverlayTextLine> Function(
      int pageIndex1Based,
      PdfMarkupTemplateContext ctx,
    )
    linesForPage,
    String? password,
    List<(double widthPt, double heightPt)>? pageSizes,
    bool underlay = false,
  }) async {
    final info = await _render.loadInfo(input, password: password);
    final sizes = pageSizes ?? await _loadPageSizes(input, password: password);
    final builder = PdfOverlayTextBuilder();
    final overlayBytes = builder.build(
      pageCount: info.pageCount,
      pageWidthPt: (page) => sizes[page - 1].$1,
      pageHeightPt: (page) => sizes[page - 1].$2,
      linesForPage: (page) {
        final ctx = PdfMarkupTemplateContext(
          file: input,
          pageIndex1Based: page,
          pageCount: info.pageCount,
          documentTitle: info.title,
        );
        return linesForPage(page, ctx);
      },
    );

    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
      underlay: underlay,
    );
  }

  Future<LocalFileRef> _applyImageOverlay({
    required LocalFileRef input,
    required String outputPath,
    required List<PdfOverlayImageLine> Function(int pageIndex1Based)
    imagesForPage,
    String? password,
    required List<(double widthPt, double heightPt)> pageSizes,
    bool underlay = false,
  }) async {
    final builder = PdfOverlayImageBuilder();
    final overlayBytes = builder.build(
      pageCount: pageSizes.length,
      pageWidthPt: (page) => pageSizes[page - 1].$1,
      pageHeightPt: (page) => pageSizes[page - 1].$2,
      imagesForPage: imagesForPage,
    );

    return _overlayBytesOntoInput(
      input: input,
      outputPath: outputPath,
      overlayBytes: overlayBytes,
      password: password,
      underlay: underlay,
    );
  }

  /// Stamping needs no external tool: pure Dart, one incremental save.
  /// qpdf is only the fallback for files our editor cannot open.
  Future<void> _requireQpdf() async {
    if (!await isQpdfCliAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'This PDF cannot be edited without the qpdf engine (it may be encrypted or damaged).',
        recoveryHint: 'Unlock the PDF first, or install the engines (see Settings → Document tools).',
      );
    }
  }

  Future<LocalFileRef> _overlayBytesOntoInput({
    required LocalFileRef input,
    required String outputPath,
    required List<int> overlayBytes,
    String? password,
    bool underlay = false,
  }) async {
    // Pure Dart first (any size our parser takes; milliseconds, no process).
    if (password == null || password.isEmpty) {
      final inputBytes = await File(input.path).readAsBytes();
      final stamped = await compute(_stampInIsolate, (
        inputBytes,
        Uint8List.fromList(overlayBytes),
        underlay,
      ));
      if (stamped != null) {
        await File(outputPath).parent.create(recursive: true);
        await File(outputPath).writeAsBytes(stamped, flush: true);
        return LocalFileRef(
          path: outputPath,
          displayName: p.basename(outputPath),
        );
      }
    }
    await _requireQpdf();
    final tempDir = Directory.systemTemp;
    final overlayPath = p.join(
      tempDir.path,
      'ds-overlay-${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await File(overlayPath).writeAsBytes(overlayBytes, flush: true);

    try {
      await _cli.overlayPdf(
        inputPath: input.path,
        overlayPath: overlayPath,
        outputPath: outputPath,
        password: password,
        underlay: underlay,
      );
    } finally {
      try {
        await File(overlayPath).delete();
      } catch (_) {}
    }

    return LocalFileRef(path: outputPath, displayName: p.basename(outputPath));
  }

  Future<List<(double widthPt, double heightPt)>> _loadPageSizes(
    LocalFileRef input, {
    String? password,
  }) async {
    try {
      final doc = await PdfDocument.openFile(
        input.path,
        passwordProvider: password == null ? null : () async => password,
      );
      try {
        return [for (final page in doc.pages) (page.width, page.height)];
      } finally {
        await doc.dispose();
      }
    } catch (e) {
      throw documentStudioErrorFromPdfrxOpen(e, password: password);
    }
  }
}

Uint8List? _stampInIsolate((Uint8List, Uint8List, bool) a) =>
    stampOverlayPages(a.$1, a.$2, underlay: a.$3);
