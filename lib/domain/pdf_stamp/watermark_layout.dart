import 'dart:math' as math;

import 'package:document_studio/domain/pdf_markup/header_footer/hf_font_metrics.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';

/// Where a single (non-tiled) watermark sits on the page.
enum WatermarkPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Everything that determines how a watermark looks on a page.
///
/// Geometry is expressed in the page's *display* space (what the viewer
/// shows, i.e. after `/Rotate` and the crop box). [rotationDegrees] is
/// counter-clockwise as seen on screen, so 45 is the classic diagonal rising
/// from bottom-left to top-right.
class WatermarkSpec {
  const WatermarkSpec({
    this.text = 'CONFIDENTIAL',
    this.imageAspect,
    this.fontSizePt = defaultFontSizePt,
    this.font = defaultFont,
    this.imageHeightFrac = defaultImageHeightFrac,
    this.rotationDegrees = defaultRotationDegrees,
    this.opacity = defaultOpacity,
    this.colorRgb = defaultColorRgb,
    this.tiled = false,
    this.position = WatermarkPosition.center,
  });

  static const double defaultFontSizePt = 72;
  static const HfFont defaultFont = HfFont.helveticaBold;
  static const double defaultImageHeightFrac = 0.3;
  static const double defaultRotationDegrees = 45;
  static const double defaultOpacity = 0.3;
  static const (double, double, double) defaultColorRgb = (0.5, 0.5, 0.5);

  /// Text template (may contain `{page}` etc.). Ignored for image marks.
  final String text;

  /// Width / height of the watermark image; `null` means a text watermark.
  final double? imageAspect;
  final double fontSizePt;

  /// Standard-14 font (previews draw it with the metric-compatible DS font).
  final HfFont font;

  /// Image mark height as a fraction of the page height.
  final double imageHeightFrac;
  final double rotationDegrees;
  final double opacity;

  /// Fill color, components 0–1.
  final (double, double, double) colorRgb;
  final bool tiled;
  final WatermarkPosition position;

  bool get isImage => imageAspect != null;

  double get clampedOpacity => opacity.clamp(0.05, 1.0).toDouble();

  WatermarkSpec copyWith({
    String? text,
    double? imageAspect,
    bool clearImage = false,
    double? fontSizePt,
    HfFont? font,
    double? imageHeightFrac,
    double? rotationDegrees,
    double? opacity,
    (double, double, double)? colorRgb,
    bool? tiled,
    WatermarkPosition? position,
  }) {
    return WatermarkSpec(
      text: text ?? this.text,
      imageAspect: clearImage ? null : (imageAspect ?? this.imageAspect),
      fontSizePt: fontSizePt ?? this.fontSizePt,
      font: font ?? this.font,
      imageHeightFrac: imageHeightFrac ?? this.imageHeightFrac,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      opacity: opacity ?? this.opacity,
      colorRgb: colorRgb ?? this.colorRgb,
      tiled: tiled ?? this.tiled,
      position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is WatermarkSpec &&
      other.text == text &&
      other.imageAspect == imageAspect &&
      other.fontSizePt == fontSizePt &&
      other.font == font &&
      other.imageHeightFrac == imageHeightFrac &&
      other.rotationDegrees == rotationDegrees &&
      other.opacity == opacity &&
      other.colorRgb == colorRgb &&
      other.tiled == tiled &&
      other.position == position;

  @override
  int get hashCode => Object.hash(
    text,
    imageAspect,
    fontSizePt,
    font,
    imageHeightFrac,
    rotationDegrees,
    opacity,
    colorRgb,
    tiled,
    position,
  );
}

/// Cap height / descender (em) used to box and vertically center text marks.
const double watermarkCapHeightEm = 0.718;
const double watermarkDescentEm = 0.207;

/// One placed watermark instance on a page.
class WatermarkMark {
  const WatermarkMark({
    required this.centerXNorm,
    required this.centerYNorm,
    required this.widthPt,
    required this.heightPt,
    required this.rotationDegrees,
    this.text = '',
    this.fontSizePt = 0,
    this.font = WatermarkSpec.defaultFont,
  });

  /// Center of the mark, 0–1, top-left origin (display space).
  final double centerXNorm;
  final double centerYNorm;

  /// Unrotated mark box size in points (text: advance width × cap box).
  final double widthPt;
  final double heightPt;

  /// Counter-clockwise rotation about the center, degrees.
  final double rotationDegrees;

  /// Sanitized (WinAnsi-safe) text; empty for image marks.
  final String text;
  final double fontSizePt;
  final HfFont font;

  /// Text baseline start relative to the mark center, in the mark's own
  /// rotated frame with y pointing *down* (screen convention).
  double get baselineStartXPt => -widthPt / 2;
  double get baselineYDownPt =>
      fontSizePt * (watermarkCapHeightEm - watermarkDescentEm) / 2;
}

const double _positionMarginPt = 36;

/// Single source of truth for watermark geometry — used by the live preview
/// painter, the thumbnail strip and the PDF stamp writer.
///
/// Returns exactly one mark per placement (one per tile when tiled).
List<WatermarkMark> layoutWatermark({
  required WatermarkSpec spec,
  required double pageWidthPt,
  required double pageHeightPt,
  String resolvedText = '',
}) {
  final pw = math.max(pageWidthPt, 1.0);
  final ph = math.max(pageHeightPt, 1.0);

  late final double w;
  late final double h;
  var text = '';
  var fontSize = 0.0;
  final aspect = spec.imageAspect;
  if (aspect != null) {
    h = ph * spec.imageHeightFrac.clamp(0.03, 1.0);
    w = h * aspect.clamp(0.02, 50.0);
  } else {
    text = hfSanitize(resolvedText.replaceAll('\n', ' ')).trim();
    if (text.isEmpty) return const [];
    fontSize = spec.fontSizePt.clamp(4.0, 400.0).toDouble();
    w = hfTextWidthPt(text, spec.font, fontSize);
    h = (watermarkCapHeightEm + watermarkDescentEm) * fontSize;
  }

  final rad = spec.rotationDegrees * math.pi / 180;
  final c = math.cos(rad).abs();
  final s = math.sin(rad).abs();
  final bboxW = w * c + h * s;
  final bboxH = w * s + h * c;

  WatermarkMark mark(double cx, double cy) => WatermarkMark(
    centerXNorm: cx,
    centerYNorm: cy,
    widthPt: w,
    heightPt: h,
    rotationDegrees: spec.rotationDegrees,
    text: text,
    fontSizePt: fontSize,
    font: spec.font,
  );

  if (spec.tiled) {
    final gap = aspect != null ? h * 0.6 : fontSize * 1.2;
    final cols = (pw / (bboxW + gap)).floor().clamp(1, 12);
    final rows = (ph / (bboxH + gap)).floor().clamp(1, 16);
    return [
      for (var r = 0; r < rows; r++)
        for (var col = 0; col < cols; col++)
          mark((col + 0.5) / cols, (r + 0.5) / rows),
    ];
  }

  double axis(int slot, double pageExtent, double bboxExtent) {
    final half = bboxExtent / 2;
    if (slot == 1 || bboxExtent + 2 * _positionMarginPt >= pageExtent) {
      return 0.5;
    }
    final pt = slot == 0
        ? _positionMarginPt + half
        : pageExtent - _positionMarginPt - half;
    return pt / pageExtent;
  }

  final (col, row) = switch (spec.position) {
    WatermarkPosition.topLeft => (0, 0),
    WatermarkPosition.topCenter => (1, 0),
    WatermarkPosition.topRight => (2, 0),
    WatermarkPosition.centerLeft => (0, 1),
    WatermarkPosition.center => (1, 1),
    WatermarkPosition.centerRight => (2, 1),
    WatermarkPosition.bottomLeft => (0, 2),
    WatermarkPosition.bottomCenter => (1, 2),
    WatermarkPosition.bottomRight => (2, 2),
  };
  return [mark(axis(col, pw, bboxW), axis(row, ph, bboxH))];
}
