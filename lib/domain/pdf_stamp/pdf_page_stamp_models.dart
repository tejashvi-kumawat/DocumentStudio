import 'package:equatable/equatable.dart';

/// Corner / edge presets for a stamp on one page (PDF points, origin bottom-left).
enum PdfPageStampPlacement {
  bottomRight,
  bottomLeft,
  center,
}

/// Size of a stamp as a fraction of the shorter page edge.
///
/// When [absoluteRect] is set (drag-place), presets are ignored for images.
/// When [absoluteXPt]/[absoluteYPt] are set, typed text uses that baseline.
class PdfPageStampLayout extends Equatable {
  const PdfPageStampLayout({
    this.placement = PdfPageStampPlacement.bottomRight,
    this.maxWidthFraction = 0.35,
    this.marginPt = 36,
    this.textFontSizePt = 28,
    this.absoluteRect,
    this.absoluteXPt,
    this.absoluteYPt,
  });

  final PdfPageStampPlacement placement;
  final double maxWidthFraction;
  final double marginPt;
  final double textFontSizePt;

  /// Drag-placed image box in PDF user space (bottom-left origin).
  final PdfStampRect? absoluteRect;

  /// Drag-placed text baseline in PDF user space.
  final double? absoluteXPt;
  final double? absoluteYPt;

  @override
  List<Object?> get props => [
        placement,
        maxWidthFraction,
        marginPt,
        textFontSizePt,
        absoluteRect,
        absoluteXPt,
        absoluteYPt,
      ];
}

/// Axis-aligned stamp box in PDF user space (points, bottom-left origin).
class PdfStampRect extends Equatable {
  const PdfStampRect({
    required this.xPt,
    required this.yPt,
    required this.widthPt,
    required this.heightPt,
  });

  final double xPt;
  final double yPt;
  final double widthPt;
  final double heightPt;

  @override
  List<Object?> get props => [xPt, yPt, widthPt, heightPt];
}

/// Computes stamp rectangle on a page for an image aspect ratio (width / height).
PdfStampRect computeImageStampRect({
  required double pageWidthPt,
  required double pageHeightPt,
  required double imageAspectWidthOverHeight,
  PdfPageStampLayout layout = const PdfPageStampLayout(),
}) {
  if (pageWidthPt <= 0 || pageHeightPt <= 0) {
    throw ArgumentError('Page size must be positive');
  }
  if (imageAspectWidthOverHeight <= 0) {
    throw ArgumentError('Image aspect must be positive');
  }
  final absolute = layout.absoluteRect;
  if (absolute != null) {
    return PdfStampRect(
      xPt: absolute.xPt.clamp(0, pageWidthPt),
      yPt: absolute.yPt.clamp(0, pageHeightPt),
      widthPt: absolute.widthPt.clamp(1, pageWidthPt),
      heightPt: absolute.heightPt.clamp(1, pageHeightPt),
    );
  }
  final shortEdge = pageWidthPt < pageHeightPt ? pageWidthPt : pageHeightPt;
  var widthPt = (shortEdge * layout.maxWidthFraction).clamp(24.0, pageWidthPt);
  var heightPt = widthPt / imageAspectWidthOverHeight;
  if (heightPt > pageHeightPt * layout.maxWidthFraction) {
    heightPt = pageHeightPt * layout.maxWidthFraction;
    widthPt = heightPt * imageAspectWidthOverHeight;
  }
  final m = layout.marginPt;
  final (x, y) = switch (layout.placement) {
    PdfPageStampPlacement.bottomRight => (
        pageWidthPt - m - widthPt,
        m,
      ),
    PdfPageStampPlacement.bottomLeft => (
        m,
        m,
      ),
    PdfPageStampPlacement.center => (
        (pageWidthPt - widthPt) / 2,
        (pageHeightPt - heightPt) / 2,
      ),
  };
  return PdfStampRect(
    xPt: x.clamp(0, pageWidthPt),
    yPt: y.clamp(0, pageHeightPt),
    widthPt: widthPt,
    heightPt: heightPt,
  );
}

/// Text signature anchor (baseline) from [layout] on [pageWidthPt] × [pageHeightPt].
({double xPt, double yPt, double fontSizePt}) typedSignatureTextAnchor({
  required double pageWidthPt,
  required double pageHeightPt,
  required String text,
  PdfPageStampLayout layout = const PdfPageStampLayout(),
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('Signature text required');
  }
  final fontSize = layout.textFontSizePt;
  if (layout.absoluteXPt != null && layout.absoluteYPt != null) {
    return (
      xPt: layout.absoluteXPt!.clamp(0, pageWidthPt),
      yPt: layout.absoluteYPt!.clamp(0, pageHeightPt),
      fontSizePt: fontSize,
    );
  }
  final estWidth = trimmed.length * fontSize * 0.45;
  final m = layout.marginPt;
  final (x, y) = switch (layout.placement) {
    PdfPageStampPlacement.bottomRight => (
        pageWidthPt - m - estWidth,
        m + fontSize,
      ),
    PdfPageStampPlacement.bottomLeft => (
        m,
        m + fontSize,
      ),
    PdfPageStampPlacement.center => (
        (pageWidthPt - estWidth) / 2,
        pageHeightPt / 2,
      ),
  };
  return (
    xPt: x.clamp(0, pageWidthPt),
    yPt: y.clamp(0, pageHeightPt),
    fontSizePt: fontSize,
  );
}

List<String> validateImageStampPageRequest({
  required int targetPage1Based,
  required int pageCount,
}) {
  final issues = <String>[];
  if (pageCount < 1) {
    issues.add('Document has no pages');
  } else if (targetPage1Based < 1 || targetPage1Based > pageCount) {
    issues.add('Choose a valid page');
  }
  return issues;
}

List<String> validateTypedSignatureRequest(String text) {
  if (text.trim().isEmpty) {
    return ['Enter your name or signature text'];
  }
  return [];
}
