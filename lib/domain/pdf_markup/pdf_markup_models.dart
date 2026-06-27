import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:equatable/equatable.dart';

enum PageNumberStyle { arabic, romanLower, romanUpper }

/// Known `{variable}` tokens for header/footer templates (DS-HDR-001).
const pdfMarkupTemplateVariables = {
  'title',
  'file',
  'date',
  'page',
  'pages',
};

class PdfMarkupTemplateContext extends Equatable {
  const PdfMarkupTemplateContext({
    required this.file,
    required this.pageIndex1Based,
    required this.pageCount,
    this.documentTitle,
    this.date,
  });

  final LocalFileRef file;
  final int pageIndex1Based;
  final int pageCount;
  final String? documentTitle;
  final DateTime? date;

  String resolve(String template) {
    final d = date ?? DateTime.now();
    final dateStr =
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return template
        .replaceAll('{file}', file.displayName)
        .replaceAll('{title}', documentTitle ?? file.displayName)
        .replaceAll('{date}', dateStr)
        .replaceAll('{page}', '$pageIndex1Based')
        .replaceAll('{pages}', '$pageCount');
  }

  PdfMarkupTemplateContext forPage(int pageIndex1Based) {
    return PdfMarkupTemplateContext(
      file: file,
      pageIndex1Based: pageIndex1Based,
      pageCount: pageCount,
      documentTitle: documentTitle,
      date: date,
    );
  }

  /// Sample context for live template preview in markup tools.
  static PdfMarkupTemplateContext previewSample({LocalFileRef? file}) {
    return PdfMarkupTemplateContext(
      file: file ??
          const LocalFileRef(
            path: '/sample/report.pdf',
            displayName: 'report.pdf',
          ),
      pageIndex1Based: 1,
      pageCount: 12,
      documentTitle: 'Sample document',
      date: DateTime(2026, 9, 27),
    );
  }

  @override
  List<Object?> get props =>
      [file.path, pageIndex1Based, pageCount, documentTitle, date];
}

/// Returns user-facing issues for a header/footer template string.
List<String> validatePdfMarkupTemplate(String template) {
  final issues = <String>[];
  final braceError = _templateBraceError(template);
  if (braceError != null) {
    issues.add(braceError);
    return issues;
  }
  final tokenPattern = RegExp(r'\{([^}]+)\}');
  for (final match in tokenPattern.allMatches(template)) {
    final name = match.group(1)!;
    if (!pdfMarkupTemplateVariables.contains(name)) {
      issues.add('Unknown variable {$name}');
    }
  }
  return issues;
}

String? _templateBraceError(String template) {
  var depth = 0;
  for (final rune in template.runes) {
    final c = String.fromCharCode(rune);
    if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth < 0) return 'Unexpected "}" in template';
    }
  }
  if (depth > 0) return 'Unclosed "{" in template';
  return null;
}

List<String> validateHeaderFooterOptions(HeaderFooterOptions options) {
  final issues = <String>[];
  if (!options.hasContent) {
    issues.add('Enter header or footer text');
  }
  issues.addAll(validatePdfMarkupTemplate(options.headerTemplate));
  issues.addAll(validatePdfMarkupTemplate(options.footerTemplate));
  return issues;
}

/// Preview lines for header/footer templates (first and last sample page).
List<PdfMarkupPreviewLine> previewHeaderFooter(
  HeaderFooterOptions options, {
  PdfMarkupTemplateContext? context,
}) {
  final ctx = context ?? PdfMarkupTemplateContext.previewSample();
  final pageIndices = ctx.pageCount > 1 ? [1, ctx.pageCount] : [1];
  final lines = <PdfMarkupPreviewLine>[];
  for (final page in pageIndices) {
    final pageCtx = ctx.forPage(page);
    if (options.headerTemplate.trim().isNotEmpty) {
      lines.add(
        PdfMarkupPreviewLine(
          label: 'Page $page header',
          text: pageCtx.resolve(options.headerTemplate),
        ),
      );
    }
    if (options.footerTemplate.trim().isNotEmpty) {
      lines.add(
        PdfMarkupPreviewLine(
          label: 'Page $page footer',
          text: pageCtx.resolve(options.footerTemplate),
        ),
      );
    }
  }
  return lines;
}

class PdfMarkupPreviewLine {
  const PdfMarkupPreviewLine({required this.label, required this.text});

  final String label;
  final String text;
}

/// DS-PGN-002 stub — fixed-width Bates-style label (full feature not wired).
String formatBatesNumber(
  int sequence, {
  String prefix = '',
  int minWidth = 6,
}) {
  if (sequence < 1) return '$prefix$sequence';
  return '$prefix${sequence.toString().padLeft(minWidth, '0')}';
}

String formatPageNumber(int n, PageNumberStyle style) {
  switch (style) {
    case PageNumberStyle.arabic:
      return '$n';
    case PageNumberStyle.romanLower:
      return _toRoman(n).toLowerCase();
    case PageNumberStyle.romanUpper:
      return _toRoman(n);
  }
}

String _toRoman(int n) {
  if (n <= 0 || n > 3999) return '$n';
  const table = [
    (1000, 'M'),
    (900, 'CM'),
    (500, 'D'),
    (400, 'CD'),
    (100, 'C'),
    (90, 'XC'),
    (50, 'L'),
    (40, 'XL'),
    (10, 'X'),
    (9, 'IX'),
    (5, 'V'),
    (4, 'IV'),
    (1, 'I'),
  ];
  var v = n;
  final buf = StringBuffer();
  for (final (value, numeral) in table) {
    while (v >= value) {
      buf.write(numeral);
      v -= value;
    }
  }
  return buf.toString();
}

class HeaderFooterOptions extends Equatable {
  const HeaderFooterOptions({
    this.headerTemplate = '',
    this.footerTemplate = '',
    this.fontSizePt = 10,
    this.alignment = HeaderFooterAlignment.center,
    this.pages1Based,
  });

  final String headerTemplate;
  final String footerTemplate;
  final double fontSizePt;
  final HeaderFooterAlignment alignment;

  /// When null, apply to all pages.
  final Set<int>? pages1Based;

  bool get hasContent =>
      headerTemplate.trim().isNotEmpty || footerTemplate.trim().isNotEmpty;

  @override
  List<Object?> get props =>
      [headerTemplate, footerTemplate, fontSizePt, alignment, pages1Based];
}

enum HeaderFooterAlignment { left, center, right }

class PageNumberOptions extends Equatable {
  const PageNumberOptions({
    this.startAt = 1,
    this.style = PageNumberStyle.arabic,
    this.prefix = '',
    this.suffix = '',
    this.fontSizePt = 10,
    this.vertical = PageNumberVertical.bottom,
    this.alignment = HeaderFooterAlignment.center,
    this.format = PageNumberFormat.pageN,
    this.pages1Based,
  });

  final int startAt;
  final PageNumberStyle style;
  final String prefix;
  final String suffix;
  final double fontSizePt;
  final PageNumberVertical vertical;
  final HeaderFooterAlignment alignment;
  final PageNumberFormat format;

  /// When null, apply to all pages.
  final Set<int>? pages1Based;

  String labelForPage(int pageIndex1Based, {int? pageCount}) {
    final n = startAt + pageIndex1Based - 1;
    final body = formatPageNumber(n, style);
    if (prefix.isNotEmpty || suffix.isNotEmpty) {
      return '$prefix$body$suffix';
    }
    return switch (format) {
      PageNumberFormat.pageN => 'Page $body',
      PageNumberFormat.nOfM => '$body of ${pageCount ?? pageIndex1Based}',
    };
  }

  @override
  List<Object?> get props => [
        startAt,
        style,
        prefix,
        suffix,
        fontSizePt,
        vertical,
        alignment,
        format,
        pages1Based,
      ];
}

enum PageNumberVertical { top, bottom }

enum PageNumberFormat { pageN, nOfM }

/// Placement presets for text watermarks (DS-WTM-001).
enum WatermarkPlacement {
  diagonalCenter,
  center,
  bottomRight,
  topLeft,
}

class WatermarkOptions extends Equatable {
  const WatermarkOptions({
    this.textTemplate = 'CONFIDENTIAL',
    this.fontSizePt = 48,
    this.opacity = 0.2,
    this.placement = WatermarkPlacement.diagonalCenter,
    this.rotationDegrees,
    this.anchorLeftNorm,
    this.anchorTopNorm,
    this.pages1Based,
    this.fillRgb,
    this.tiled = false,
    this.behindContent = false,
    this.position = WatermarkPosition.center,
  });

  final String textTemplate;
  final double fontSizePt;
  final double opacity;
  final WatermarkPlacement placement;

  /// Counter-clockwise as seen on the page. When null, [placement] supplies a
  /// default angle (45° rising diagonal).
  final double? rotationDegrees;

  /// Optional drag placement (0–1, top-left origin). When both set, overrides
  /// [placement] presets.
  final double? anchorLeftNorm;
  final double? anchorTopNorm;

  /// When non-null, only these 1-based pages receive the watermark.
  final Set<int>? pages1Based;

  /// Optional RGB fill (0–1). When set, overrides gray [opacity] fill.
  final (double r, double g, double b)? fillRgb;

  /// Repeat the mark across the page instead of a single centered stamp.
  final bool tiled;

  /// When true, qpdf `--underlay` (behind page content); otherwise `--overlay`.
  final bool behindContent;

  /// Anchor of a single (non-tiled) diagonal/center watermark.
  final WatermarkPosition position;

  bool get hasContent => textTemplate.trim().isNotEmpty;

  bool get hasCustomAnchor =>
      anchorLeftNorm != null && anchorTopNorm != null;

  double get effectiveRotationDegrees {
    final explicit = rotationDegrees;
    if (explicit != null) return explicit;
    if (hasCustomAnchor) return 0;
    switch (placement) {
      case WatermarkPlacement.diagonalCenter:
        return 45;
      case WatermarkPlacement.center:
      case WatermarkPlacement.bottomRight:
      case WatermarkPlacement.topLeft:
        return 0;
    }
  }

  @override
  List<Object?> get props => [
        textTemplate,
        fontSizePt,
        opacity,
        placement,
        rotationDegrees,
        anchorLeftNorm,
        anchorTopNorm,
        pages1Based,
        fillRgb,
        tiled,
        behindContent,
        position,
      ];
}

List<String> validateWatermarkOptions(WatermarkOptions options) {
  final issues = <String>[];
  if (!options.hasContent) {
    issues.add('Enter watermark text');
  }
  if (options.fontSizePt < 6 || options.fontSizePt > 200) {
    issues.add('Font size must be between 6 and 200 pt');
  }
  if (options.opacity <= 0 || options.opacity > 1) {
    issues.add('Opacity must be between 0 and 1');
  }
  issues.addAll(validatePdfMarkupTemplate(options.textTemplate));
  return issues;
}

List<PdfMarkupPreviewLine> previewWatermark(
  WatermarkOptions options, {
  PdfMarkupTemplateContext? context,
}) {
  final ctx = context ?? PdfMarkupTemplateContext.previewSample();
  final text = ctx.resolve(options.textTemplate);
  return [
    PdfMarkupPreviewLine(
      label: 'Sample page 1',
      text: '$text · ${options.placement.name} · '
          '${(options.opacity * 100).round()}% opacity',
    ),
  ];
}

List<String> validatePageNumberOptions(PageNumberOptions options) {
  final issues = <String>[];
  if (options.startAt < 1) {
    issues.add('Start page must be at least 1');
  }
  if (options.style != PageNumberStyle.arabic && options.startAt > 3999) {
    issues.add('Roman numerals only support start values 1–3999');
  }
  return issues;
}

/// Preview footer labels on sample first/last pages.
List<PdfMarkupPreviewLine> previewPageNumbers(
  PageNumberOptions options, {
  int samplePageCount = 12,
}) {
  final indices =
      samplePageCount > 1 ? [1, samplePageCount] : [1];
  return [
    for (final page in indices)
      PdfMarkupPreviewLine(
        label: 'Page $page',
        text: options.labelForPage(page, pageCount: samplePageCount),
      ),
  ];
}
