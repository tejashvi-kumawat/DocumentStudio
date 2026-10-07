import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';

/// Editable on-page objects (text, images, ink, shapes, text markup, notes,
/// links). All coordinates are page *display points* (top-left origin, y
/// down, after `/Rotate`) — see [PdfPageGeometry]. The same values drive the
/// on-screen painter and the PDF annotation writer.
enum MarkupType { text, image, ink, shape, textMarkup, note, link }

enum ShapeKind { rectangle, ellipse, line, arrow, polygon, cloud }

enum TextMarkupKind { highlight, underline, strikeout, squiggly }

enum StrokeDash { solid, dashed, dotted }

enum MarkupTextAlign { left, center, right }

/// Dash pattern (in points) for a given stroke width.
List<double>? dashPatternFor(StrokeDash dash, double width) => switch (dash) {
  StrokeDash.solid => null,
  StrokeDash.dashed => [math.max(3, width * 3), math.max(2, width * 2)],
  StrokeDash.dotted => [math.max(0.8, width), math.max(1.6, width * 1.6)],
};

/// One laid-out line of a text box (frame-local, points).
class MarkupTextLine {
  const MarkupTextLine({
    required this.text,
    required this.left,
    required this.baseline,
    required this.width,
  });

  factory MarkupTextLine.fromJson(Map<String, dynamic> j) => MarkupTextLine(
    text: j['t'] as String,
    left: (j['l'] as num).toDouble(),
    baseline: (j['b'] as num).toDouble(),
    width: (j['w'] as num).toDouble(),
  );

  final String text;
  final double left;
  final double baseline;
  final double width;

  Map<String, dynamic> toJson() => {
    't': text,
    'l': left,
    'b': baseline,
    'w': width,
  };
}

Map<String, dynamic> _off(Offset o) => {'x': o.dx, 'y': o.dy};
Offset _toOff(dynamic j) =>
    Offset((j['x'] as num).toDouble(), (j['y'] as num).toDouble());
Map<String, dynamic> _rect(Rect r) => {
  'l': r.left,
  't': r.top,
  'r': r.right,
  'b': r.bottom,
};
Rect _toRect(dynamic j) => Rect.fromLTRB(
  (j['l'] as num).toDouble(),
  (j['t'] as num).toDouble(),
  (j['r'] as num).toDouble(),
  (j['b'] as num).toDouble(),
);

/// Default for `withCommon(groupId:)` meaning "unchanged" (null ungroups).
const Object _kKeep = Object();

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) =>
    values.firstWhere((v) => v.name == name, orElse: () => fallback);

Offset _rotateAbout(Offset p, Offset c, double rad) {
  final cs = math.cos(rad), sn = math.sin(rad);
  final d = p - c;
  return Offset(c.dx + d.dx * cs - d.dy * sn, c.dy + d.dx * sn + d.dy * cs);
}

Offset _scaleInto(Offset p, Rect from, Rect to) {
  final sx = from.width.abs() < 1e-6 ? 1.0 : to.width / from.width;
  final sy = from.height.abs() < 1e-6 ? 1.0 : to.height / from.height;
  return Offset(
    to.left + (p.dx - from.left) * sx,
    to.top + (p.dy - from.top) * sy,
  );
}

/// Base class. Instances are immutable; edits produce copies.
sealed class MarkupObject {
  const MarkupObject({
    required this.id,
    required this.page,
    this.name = '',
    this.hidden = false,
    this.locked = false,
    this.opacity = 1,
    this.groupId,
  });

  final String id;

  /// 1-based page number.
  final int page;

  /// User label shown in the Layers panel ('' → [defaultLabel]).
  final String name;
  final bool hidden;
  final bool locked;
  final double opacity;

  /// Objects sharing a group id select, move and resize together.
  final String? groupId;

  MarkupType get type;

  /// Display-space axis-aligned bounds of everything drawn.
  Rect get bounds;

  /// Frame + rotation objects rotate about their center; others bake points.
  double get rotation => 0;
  bool get canRotate => true;
  bool get canResize => true;
  bool get canMove => true;

  /// Unrotated frame for frame-based objects, [bounds] otherwise.
  Rect get frame => bounds;

  String get defaultLabel;
  String get label => name.isEmpty ? defaultLabel : name;

  /// Primary color used by the contextual toolbar (ARGB).
  int get color;

  MarkupObject moved(Offset delta);

  /// Scales the object so its [frame] becomes [newFrame] (rotation kept).
  MarkupObject resizedTo(Rect newFrame);

  /// Sets absolute rotation (frame-based) or rotates points by the delta.
  MarkupObject rotatedTo(double degrees);

  MarkupObject recolored(int argb);

  MarkupObject withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  });

  /// Whether [p] (display points) hits the object with [tolerance] points.
  bool hitTest(Offset p, double tolerance);

  Map<String, dynamic> toJson();

  Map<String, dynamic> commonJson() => {
    'type': type.name,
    'id': id,
    'page': page,
    if (name.isNotEmpty) 'name': name,
    if (hidden) 'hidden': true,
    if (locked) 'locked': true,
    'opacity': opacity,
    if (groupId != null) 'grp': groupId,
  };

  /// Rebuilds an object from [toJson] output. [imageBytes] supplies image
  /// data stored outside the JSON.
  static MarkupObject? fromJson(
    Map<String, dynamic> j, {
    Uint8List? imageBytes,
  }) {
    final type = _enum(MarkupType.values, j['type'], MarkupType.shape);
    final id = j['id'] as String? ?? '';
    final page = (j['page'] as num?)?.toInt() ?? 1;
    final name = j['name'] as String? ?? '';
    final hidden = j['hidden'] == true;
    final locked = j['locked'] == true;
    final opacity = (j['opacity'] as num?)?.toDouble() ?? 1;
    final groupId = j['grp'] as String?;
    try {
      switch (type) {
        case MarkupType.text:
          return TextBoxMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            frame: _toRect(j['frame']),
            rotation: (j['rot'] as num?)?.toDouble() ?? 0,
            text: j['text'] as String? ?? '',
            fontFamily: MarkupFontFamily.byName(j['font'] as String?),
            fontSize: (j['size'] as num?)?.toDouble() ?? 14,
            bold: j['bold'] == true,
            italic: j['italic'] == true,
            textColor: (j['color'] as num?)?.toInt() ?? 0xFF000000,
            fillColor: (j['fill'] as num?)?.toInt(),
            borderColor: (j['border'] as num?)?.toInt(),
            borderWidth: (j['bw'] as num?)?.toDouble() ?? 1,
            align: _enum(
              MarkupTextAlign.values,
              j['align'],
              MarkupTextAlign.left,
            ),
            padding: (j['pad'] as num?)?.toDouble() ?? 2,
            lineHeight: (j['lh'] as num?)?.toDouble() ?? 1.2,
            underline: j['ul'] == true,
            strike: j['st'] == true,
            letterSpacing: (j['ls'] as num?)?.toDouble() ?? 0,
            autoWidth: j['aw'] == true,
            lines: [
              for (final l in (j['lines'] as List? ?? const []))
                MarkupTextLine.fromJson(Map<String, dynamic>.from(l as Map)),
            ],
            calloutPoints: [
              for (final p in (j['callout'] as List? ?? const [])) _toOff(p),
            ],
          );
        case MarkupType.image:
          final bytes = imageBytes;
          if (bytes == null) return null;
          return ImageMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            frame: _toRect(j['frame']),
            rotation: (j['rot'] as num?)?.toDouble() ?? 0,
            flipH: j['flipH'] == true,
            flipV: j['flipV'] == true,
            crop: j['crop'] == null ? kFullCrop : _toRect(j['crop']),
            cornerRadius: (j['radius'] as num?)?.toDouble() ?? 0,
            borderColor: (j['border'] as num?)?.toInt(),
            borderWidth: (j['bw'] as num?)?.toDouble() ?? 0,
            bytes: bytes,
          );
        case MarkupType.ink:
          return InkMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            strokes: [
              for (final s in (j['strokes'] as List? ?? const []))
                [for (final p in (s as List)) _toOff(p)],
            ],
            strokeColor: (j['color'] as num?)?.toInt() ?? 0xFF000000,
            strokeWidth: (j['width'] as num?)?.toDouble() ?? 2,
            highlighter: j['hl'] == true,
          );
        case MarkupType.shape:
          return ShapeMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            kind: _enum(ShapeKind.values, j['kind'], ShapeKind.rectangle),
            shapeFrame: j['frame'] == null ? null : _toRect(j['frame']),
            rotation: (j['rot'] as num?)?.toDouble() ?? 0,
            points: [
              for (final p in (j['points'] as List? ?? const [])) _toOff(p),
            ],
            strokeColor: (j['color'] as num?)?.toInt() ?? 0xFFE53935,
            fillColor: (j['fill'] as num?)?.toInt(),
            strokeWidth: (j['width'] as num?)?.toDouble() ?? 2,
            dash: _enum(StrokeDash.values, j['dash'], StrokeDash.solid),
          );
        case MarkupType.textMarkup:
          return TextMarkupMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            kind: _enum(
              TextMarkupKind.values,
              j['kind'],
              TextMarkupKind.highlight,
            ),
            rects: [
              for (final r in (j['rects'] as List? ?? const [])) _toRect(r),
            ],
            markupColor: (j['color'] as num?)?.toInt() ?? 0xFFFFEB3B,
            text: j['text'] as String? ?? '',
          );
        case MarkupType.note:
          return NoteMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            anchor: _toOff(j['anchor']),
            text: j['text'] as String? ?? '',
            noteColor: (j['color'] as num?)?.toInt() ?? 0xFFFFD54F,
            author: j['author'] as String? ?? '',
            open: j['open'] == true,
          );
        case MarkupType.link:
          return LinkMarkup(
            id: id,
            page: page,
            name: name,
            hidden: hidden,
            locked: locked,
            groupId: groupId,
            opacity: opacity,
            linkFrame: _toRect(j['frame']),
            text: j['text'] as String? ?? '',
            uri: j['uri'] as String?,
            destPage: (j['dest'] as num?)?.toInt(),
            showBorder: j['border'] == true,
          );
      }
    } catch (_) {
      return null;
    }
  }

  /// Re-expresses the object for a page whose crop box / rotation changed
  /// since it was saved (e.g. the page was rotated by another tool).
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to);
}

Rect _remapFrame(Rect f, PdfPageGeometry from, PdfPageGeometry to) {
  final c = from.remapTo(to, f.center);
  final swap = from.rotationDeltaTo(to) % 180 == 90;
  final w = swap ? f.height : f.width;
  final h = swap ? f.width : f.height;
  return Rect.fromCenter(center: c, width: w, height: h);
}

// ------------------------------------------------------------------ text box

class TextBoxMarkup extends MarkupObject {
  const TextBoxMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this._frame,
    this.rotation = 0,
    this.text = '',
    this.fontFamily = MarkupFontFamily.sans,
    this.fontSize = 14,
    this.bold = false,
    this.italic = false,
    this.textColor = 0xFF000000,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 1,
    this.align = MarkupTextAlign.left,
    this.padding = 2,
    this.lineHeight = 1.2,
    this.underline = false,
    this.strike = false,
    this.letterSpacing = 0,
    this.autoWidth = false,
    this.lines = const [],
    this.calloutPoints = const [],
  });

  final Rect _frame;
  @override
  final double rotation;
  final String text;
  final MarkupFontFamily fontFamily;
  final double fontSize;
  final bool bold;
  final bool italic;
  final int textColor;
  final int? fillColor;
  final int? borderColor;
  final double borderWidth;
  final MarkupTextAlign align;
  final double padding;
  final double lineHeight;
  final bool underline;
  final bool strike;

  /// Extra advance after every character, in points (PDF `Tc`).
  final double letterSpacing;

  /// Box width follows the longest line instead of wrapping.
  final bool autoWidth;

  /// Layout computed on screen at commit time; the writer places these.
  final List<MarkupTextLine> lines;

  /// Callout leader: [target, knee] in display points (empty = plain box).
  final List<Offset> calloutPoints;

  bool get isCallout => calloutPoints.length >= 2;

  @override
  MarkupType get type => MarkupType.text;
  @override
  Rect get frame => _frame;
  @override
  Rect get bounds {
    final corners = rotatedFrameCorners(_frame, rotation);
    return boundsOfPoints([...corners, ...calloutPoints]);
  }

  @override
  String get defaultLabel {
    if (isCallout) return 'Callout';
    final t = text.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return 'Text';
    return t.length > 28 ? '${t.substring(0, 28)}…' : t;
  }

  @override
  int get color => textColor;

  TextBoxMarkup copyWith({
    Rect? frame,
    double? rotation,
    String? text,
    MarkupFontFamily? fontFamily,
    double? fontSize,
    bool? bold,
    bool? italic,
    int? textColor,
    int? Function()? fillColor,
    int? Function()? borderColor,
    double? borderWidth,
    MarkupTextAlign? align,
    double? padding,
    double? lineHeight,
    bool? underline,
    bool? strike,
    double? letterSpacing,
    bool? autoWidth,
    List<MarkupTextLine>? lines,
    List<Offset>? calloutPoints,
    double? opacity,
  }) => TextBoxMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    frame: frame ?? _frame,
    rotation: rotation ?? this.rotation,
    text: text ?? this.text,
    fontFamily: fontFamily ?? this.fontFamily,
    fontSize: fontSize ?? this.fontSize,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    textColor: textColor ?? this.textColor,
    fillColor: fillColor != null ? fillColor() : this.fillColor,
    borderColor: borderColor != null ? borderColor() : this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
    align: align ?? this.align,
    padding: padding ?? this.padding,
    lineHeight: lineHeight ?? this.lineHeight,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    letterSpacing: letterSpacing ?? this.letterSpacing,
    autoWidth: autoWidth ?? this.autoWidth,
    lines: lines ?? this.lines,
    calloutPoints: calloutPoints ?? this.calloutPoints,
  );

  @override
  TextBoxMarkup moved(Offset delta) => copyWith(
    frame: _frame.shift(delta),
    calloutPoints: [
      for (var i = 0; i < calloutPoints.length; i++)
        // Keep the arrow target pinned; move the knee with the box.
        i == 0 ? calloutPoints[i] : calloutPoints[i] + delta,
    ],
  );

  @override
  TextBoxMarkup resizedTo(Rect newFrame) => copyWith(frame: newFrame);

  @override
  TextBoxMarkup rotatedTo(double degrees) => copyWith(rotation: degrees);

  @override
  TextBoxMarkup recolored(int argb) => copyWith(textColor: argb);

  @override
  TextBoxMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => TextBoxMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    frame: _frame,
    rotation: rotation,
    text: text,
    fontFamily: fontFamily,
    fontSize: fontSize,
    bold: bold,
    italic: italic,
    textColor: textColor,
    fillColor: fillColor,
    borderColor: borderColor,
    borderWidth: borderWidth,
    align: align,
    padding: padding,
    lineHeight: lineHeight,
    underline: underline,
    strike: strike,
    letterSpacing: letterSpacing,
    autoWidth: autoWidth,
    lines: lines,
    calloutPoints: calloutPoints,
  );

  @override
  bool hitTest(Offset p, double tolerance) {
    final local = frameToDisplay(_frame, rotation).inverse().apply(p);
    if (Rect.fromLTWH(
      0,
      0,
      _frame.width,
      _frame.height,
    ).inflate(tolerance).contains(local)) {
      return true;
    }
    if (isCallout) {
      final knee = calloutPoints[1];
      return distanceToSegment(p, calloutPoints[0], knee) <= tolerance + 2 ||
          distanceToSegment(p, knee, _nearestFrameEdgePoint(knee)) <=
              tolerance + 2;
    }
    return false;
  }

  Offset _nearestFrameEdgePoint(Offset p) => Offset(
    p.dx.clamp(_frame.left, _frame.right),
    p.dy.clamp(_frame.top, _frame.bottom),
  );

  /// Where the callout leader meets the box (display points).
  Offset calloutAttachPoint() {
    if (!isCallout) return _frame.center;
    final knee = calloutPoints[1];
    final c = _frame.center;
    final candidates = [
      Offset(_frame.left, c.dy),
      Offset(_frame.right, c.dy),
      Offset(c.dx, _frame.top),
      Offset(c.dx, _frame.bottom),
    ];
    candidates.sort(
      (a, b) =>
          (a - knee).distanceSquared.compareTo((b - knee).distanceSquared),
    );
    return candidates.first;
  }

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'frame': _rect(_frame),
    if (rotation != 0) 'rot': rotation,
    'text': text,
    'font': fontFamily.name,
    'size': fontSize,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    'color': textColor,
    if (fillColor != null) 'fill': fillColor,
    if (borderColor != null) 'border': borderColor,
    'bw': borderWidth,
    'align': align.name,
    'pad': padding,
    'lh': lineHeight,
    if (underline) 'ul': true,
    if (strike) 'st': true,
    if (letterSpacing != 0) 'ls': letterSpacing,
    if (autoWidth) 'aw': true,
    'lines': [for (final l in lines) l.toJson()],
    if (calloutPoints.isNotEmpty)
      'callout': [for (final p in calloutPoints) _off(p)],
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) {
    final delta = from.rotationDeltaTo(to).toDouble();
    // Keep text upright relative to the page content it annotates.
    final nf = _remapFrame(_frame, from, to);
    return copyWith(
      frame: Rect.fromCenter(
        center: nf.center,
        width: _frame.width,
        height: _frame.height,
      ),
      rotation: (rotation + delta) % 360,
      calloutPoints: [for (final p in calloutPoints) from.remapTo(to, p)],
    );
  }
}

// --------------------------------------------------------------------- image

/// Uncropped [ImageMarkup.crop].
const Rect kFullCrop = Rect.fromLTRB(0, 0, 1, 1);

class ImageMarkup extends MarkupObject {
  const ImageMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this._frame,
    this.rotation = 0,
    this.flipH = false,
    this.flipV = false,
    this.crop = kFullCrop,
    this.cornerRadius = 0,
    this.borderColor,
    this.borderWidth = 0,
    required this.bytes,
  });

  final Rect _frame;
  @override
  final double rotation;
  final bool flipH;
  final bool flipV;

  /// Visible part of the source image, normalized to 0..1.
  final Rect crop;

  /// Rounded corners, in points (clamped to half the shorter side).
  final double cornerRadius;
  final int? borderColor;
  final double borderWidth;

  bool get isCropped => crop != kFullCrop;
  bool get hasBorder => borderColor != null && borderWidth > 0;

  /// Encoded image (PNG/JPEG/...).
  final Uint8List bytes;

  @override
  MarkupType get type => MarkupType.image;
  @override
  Rect get frame => _frame;
  @override
  Rect get bounds => boundsOfPoints(rotatedFrameCorners(_frame, rotation));
  @override
  String get defaultLabel => 'Image';
  @override
  int get color => 0xFF000000;

  ImageMarkup copyWith({
    Rect? frame,
    double? rotation,
    bool? flipH,
    bool? flipV,
    Rect? crop,
    double? cornerRadius,
    int? Function()? borderColor,
    double? borderWidth,
    Uint8List? bytes,
    double? opacity,
  }) => ImageMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    frame: frame ?? _frame,
    rotation: rotation ?? this.rotation,
    flipH: flipH ?? this.flipH,
    flipV: flipV ?? this.flipV,
    crop: crop ?? this.crop,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    borderColor: borderColor != null ? borderColor() : this.borderColor,
    borderWidth: borderWidth ?? this.borderWidth,
    bytes: bytes ?? this.bytes,
  );

  @override
  ImageMarkup moved(Offset delta) => copyWith(frame: _frame.shift(delta));
  @override
  ImageMarkup resizedTo(Rect newFrame) => copyWith(frame: newFrame);
  @override
  ImageMarkup rotatedTo(double degrees) => copyWith(rotation: degrees);
  @override
  ImageMarkup recolored(int argb) => this;

  @override
  ImageMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => ImageMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    frame: _frame,
    rotation: rotation,
    flipH: flipH,
    flipV: flipV,
    crop: crop,
    cornerRadius: cornerRadius,
    borderColor: borderColor,
    borderWidth: borderWidth,
    bytes: bytes,
  );

  @override
  bool hitTest(Offset p, double tolerance) {
    final local = frameToDisplay(_frame, rotation).inverse().apply(p);
    return Rect.fromLTWH(
      0,
      0,
      _frame.width,
      _frame.height,
    ).inflate(tolerance).contains(local);
  }

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'frame': _rect(_frame),
    if (rotation != 0) 'rot': rotation,
    if (flipH) 'flipH': true,
    if (flipV) 'flipV': true,
    if (isCropped) 'crop': _rect(crop),
    if (cornerRadius > 0) 'radius': cornerRadius,
    if (borderColor != null) 'border': borderColor,
    if (borderWidth > 0) 'bw': borderWidth,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) {
    final nf = _remapFrame(_frame, from, to);
    return copyWith(
      frame: Rect.fromCenter(
        center: nf.center,
        width: _frame.width,
        height: _frame.height,
      ),
      rotation: (rotation + from.rotationDeltaTo(to)) % 360,
    );
  }
}

// ----------------------------------------------------------------------- ink

class InkMarkup extends MarkupObject {
  const InkMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this.strokes,
    this.strokeColor = 0xFF000000,
    this.strokeWidth = 2,
    this.highlighter = false,
  });

  final List<List<Offset>> strokes;
  final int strokeColor;
  final double strokeWidth;

  /// Highlighter pen: wide, multiply-blended.
  final bool highlighter;

  @override
  MarkupType get type => MarkupType.ink;
  @override
  Rect get bounds =>
      boundsOfPoints(strokes.expand((s) => s)).inflate(strokeWidth / 2);
  @override
  String get defaultLabel => highlighter ? 'Highlighter' : 'Drawing';
  @override
  int get color => strokeColor;

  InkMarkup copyWith({
    List<List<Offset>>? strokes,
    int? strokeColor,
    double? strokeWidth,
    double? opacity,
  }) => InkMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    strokes: strokes ?? this.strokes,
    strokeColor: strokeColor ?? this.strokeColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    highlighter: highlighter,
  );

  List<List<Offset>> _mapPts(Offset Function(Offset) f) => [
    for (final s in strokes) [for (final p in s) f(p)],
  ];

  @override
  InkMarkup moved(Offset delta) => copyWith(strokes: _mapPts((p) => p + delta));

  @override
  InkMarkup resizedTo(Rect newFrame) {
    final inner = bounds.deflate(strokeWidth / 2);
    final target = newFrame.deflate(strokeWidth / 2);
    return copyWith(strokes: _mapPts((p) => _scaleInto(p, inner, target)));
  }

  @override
  InkMarkup rotatedTo(double degrees) {
    final c = bounds.center;
    final rad = degrees * math.pi / 180;
    return copyWith(strokes: _mapPts((p) => _rotateAbout(p, c, rad)));
  }

  @override
  InkMarkup recolored(int argb) => copyWith(strokeColor: argb);

  @override
  InkMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => InkMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    strokes: strokes,
    strokeColor: strokeColor,
    strokeWidth: strokeWidth,
    highlighter: highlighter,
  );

  @override
  bool hitTest(Offset p, double tolerance) {
    final tol = tolerance + strokeWidth / 2;
    if (!bounds.inflate(tol).contains(p)) return false;
    for (final s in strokes) {
      if (s.length == 1 && (s.first - p).distance <= tol) return true;
      for (var i = 1; i < s.length; i++) {
        if (distanceToSegment(p, s[i - 1], s[i]) <= tol) return true;
      }
    }
    return false;
  }

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'strokes': [
      for (final s in strokes) [for (final p in s) _off(p)],
    ],
    'color': strokeColor,
    'width': strokeWidth,
    if (highlighter) 'hl': true,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) =>
      copyWith(strokes: _mapPts((p) => from.remapTo(to, p)));
}

// --------------------------------------------------------------------- shape

class ShapeMarkup extends MarkupObject {
  const ShapeMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this.kind,
    this.shapeFrame,
    this.rotation = 0,
    this.points = const [],
    this.strokeColor = 0xFFE53935,
    this.fillColor,
    this.strokeWidth = 2,
    this.dash = StrokeDash.solid,
  });

  final ShapeKind kind;

  /// Frame for rectangle / ellipse (with [rotation]).
  final Rect? shapeFrame;
  @override
  final double rotation;

  /// Vertices for line / arrow (2 points), polygon / cloud (≥3 points).
  final List<Offset> points;
  final int strokeColor;
  final int? fillColor;
  final double strokeWidth;
  final StrokeDash dash;

  bool get isFrameBased =>
      kind == ShapeKind.rectangle || kind == ShapeKind.ellipse;
  bool get isClosed => kind != ShapeKind.line && kind != ShapeKind.arrow;

  @override
  MarkupType get type => MarkupType.shape;
  @override
  Rect get frame => isFrameBased ? shapeFrame! : bounds;

  @override
  Rect get bounds {
    final pts = isFrameBased
        ? rotatedFrameCorners(shapeFrame!, rotation)
        : points;
    var pad = strokeWidth / 2;
    if (kind == ShapeKind.arrow) pad += strokeWidth * 3 + 4;
    if (kind == ShapeKind.cloud) pad += cloudRadius();
    return boundsOfPoints(pts).inflate(pad);
  }

  double cloudRadius() => math.max(4, strokeWidth * 3);

  @override
  String get defaultLabel => switch (kind) {
    ShapeKind.rectangle => 'Rectangle',
    ShapeKind.ellipse => 'Ellipse',
    ShapeKind.line => 'Line',
    ShapeKind.arrow => 'Arrow',
    ShapeKind.polygon => 'Polygon',
    ShapeKind.cloud => 'Cloud',
  };

  @override
  int get color => strokeColor;

  ShapeMarkup copyWith({
    Rect? shapeFrame,
    double? rotation,
    List<Offset>? points,
    int? strokeColor,
    int? Function()? fillColor,
    double? strokeWidth,
    StrokeDash? dash,
    double? opacity,
  }) => ShapeMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    kind: kind,
    shapeFrame: shapeFrame ?? this.shapeFrame,
    rotation: rotation ?? this.rotation,
    points: points ?? this.points,
    strokeColor: strokeColor ?? this.strokeColor,
    fillColor: fillColor != null ? fillColor() : this.fillColor,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    dash: dash ?? this.dash,
  );

  Rect get _pointBounds => boundsOfPoints(points);

  @override
  ShapeMarkup moved(Offset delta) => isFrameBased
      ? copyWith(shapeFrame: shapeFrame!.shift(delta))
      : copyWith(points: [for (final p in points) p + delta]);

  @override
  ShapeMarkup resizedTo(Rect newFrame) {
    if (isFrameBased) return copyWith(shapeFrame: newFrame);
    final from = _pointBounds;
    final pad = bounds.width - from.width;
    final to = Rect.fromLTRB(
      newFrame.left + pad / 2,
      newFrame.top + (bounds.height - from.height) / 2,
      newFrame.right - pad / 2,
      newFrame.bottom - (bounds.height - from.height) / 2,
    );
    return copyWith(points: [for (final p in points) _scaleInto(p, from, to)]);
  }

  @override
  ShapeMarkup rotatedTo(double degrees) {
    if (isFrameBased) return copyWith(rotation: degrees);
    final c = _pointBounds.center;
    final rad = degrees * math.pi / 180;
    return copyWith(points: [for (final p in points) _rotateAbout(p, c, rad)]);
  }

  @override
  bool get canRotate => true;

  @override
  ShapeMarkup recolored(int argb) => copyWith(strokeColor: argb);

  @override
  ShapeMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => ShapeMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    kind: kind,
    shapeFrame: shapeFrame,
    rotation: rotation,
    points: points,
    strokeColor: strokeColor,
    fillColor: fillColor,
    strokeWidth: strokeWidth,
    dash: dash,
  );

  @override
  bool hitTest(Offset p, double tolerance) {
    final tol = tolerance + strokeWidth / 2;
    if (isFrameBased) {
      final f = shapeFrame!;
      final local = frameToDisplay(f, rotation).inverse().apply(p);
      final box = Rect.fromLTWH(0, 0, f.width, f.height);
      if (fillColor != null) return box.inflate(tol).contains(local);
      if (kind == ShapeKind.ellipse) {
        final c = box.center;
        final rx = math.max(box.width / 2, 0.5),
            ry = math.max(box.height / 2, 0.5);
        final d = math.sqrt(
          math.pow((local.dx - c.dx) / rx, 2) +
              math.pow((local.dy - c.dy) / ry, 2),
        );
        return (d - 1).abs() * math.min(rx, ry) <= tol;
      }
      return box.inflate(tol).contains(local) &&
          !box.deflate(tol).contains(local);
    }
    final pts = isClosed ? [...points, points.first] : points;
    for (var i = 1; i < pts.length; i++) {
      if (distanceToSegment(p, pts[i - 1], pts[i]) <= tol) return true;
    }
    if (isClosed && fillColor != null) return pointInPolygon(p, points);
    return false;
  }

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'kind': kind.name,
    if (shapeFrame != null) 'frame': _rect(shapeFrame!),
    if (rotation != 0) 'rot': rotation,
    if (points.isNotEmpty) 'points': [for (final p in points) _off(p)],
    'color': strokeColor,
    if (fillColor != null) 'fill': fillColor,
    'width': strokeWidth,
    'dash': dash.name,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) {
    if (isFrameBased) {
      return copyWith(shapeFrame: _remapFrame(shapeFrame!, from, to));
    }
    return copyWith(points: [for (final p in points) from.remapTo(to, p)]);
  }
}

// --------------------------------------------------------------- text markup

class TextMarkupMarkup extends MarkupObject {
  const TextMarkupMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this.kind,
    required this.rects,
    this.markupColor = 0xFFFFEB3B,
    this.text = '',
  });

  final TextMarkupKind kind;

  /// One rect per text line (display points).
  final List<Rect> rects;
  final int markupColor;

  /// The marked-up text (stored in `/Contents`).
  final String text;

  @override
  MarkupType get type => MarkupType.textMarkup;
  @override
  Rect get bounds => rects.isEmpty
      ? Rect.zero
      : rects.skip(1).fold(rects.first, (a, b) => a.expandToInclude(b));
  @override
  bool get canRotate => false;
  @override
  bool get canResize => false;
  @override
  bool get canMove => false;

  @override
  String get defaultLabel => switch (kind) {
    TextMarkupKind.highlight => 'Highlight',
    TextMarkupKind.underline => 'Underline',
    TextMarkupKind.strikeout => 'Strikethrough',
    TextMarkupKind.squiggly => 'Squiggly',
  };

  @override
  String get label {
    if (name.isNotEmpty) return name;
    final t = text.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return defaultLabel;
    return '$defaultLabel: ${t.length > 22 ? '${t.substring(0, 22)}…' : t}';
  }

  @override
  int get color => markupColor;

  TextMarkupMarkup copyWith({
    TextMarkupKind? kind,
    List<Rect>? rects,
    int? markupColor,
    double? opacity,
  }) => TextMarkupMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    kind: kind ?? this.kind,
    rects: rects ?? this.rects,
    markupColor: markupColor ?? this.markupColor,
    text: text,
  );

  @override
  TextMarkupMarkup moved(Offset delta) => this;
  @override
  TextMarkupMarkup resizedTo(Rect newFrame) => this;
  @override
  TextMarkupMarkup rotatedTo(double degrees) => this;
  @override
  TextMarkupMarkup recolored(int argb) => copyWith(markupColor: argb);

  @override
  TextMarkupMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => TextMarkupMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    kind: kind,
    rects: rects,
    markupColor: markupColor,
    text: text,
  );

  @override
  bool hitTest(Offset p, double tolerance) =>
      rects.any((r) => r.inflate(tolerance).contains(p));

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'kind': kind.name,
    'rects': [for (final r in rects) _rect(r)],
    'color': markupColor,
    if (text.isNotEmpty) 'text': text,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) => copyWith(
    rects: [
      for (final r in rects)
        Rect.fromPoints(
          from.remapTo(to, r.topLeft),
          from.remapTo(to, r.bottomRight),
        ),
    ],
  );
}

// ---------------------------------------------------------------------- note

/// Sticky-note icon size (display points).
const double kNoteIconSize = 22;

class NoteMarkup extends MarkupObject {
  const NoteMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this.anchor,
    this.text = '',
    this.noteColor = 0xFFFFD54F,
    this.author = '',
    this.open = false,
  });

  /// Icon top-left (display points).
  final Offset anchor;
  final String text;
  final int noteColor;
  final String author;
  final bool open;

  @override
  MarkupType get type => MarkupType.note;
  @override
  Rect get bounds =>
      Rect.fromLTWH(anchor.dx, anchor.dy, kNoteIconSize, kNoteIconSize);
  @override
  bool get canResize => false;
  @override
  bool get canRotate => false;

  @override
  String get defaultLabel {
    final t = text.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return 'Note';
    return 'Note: ${t.length > 24 ? '${t.substring(0, 24)}…' : t}';
  }

  @override
  int get color => noteColor;

  NoteMarkup copyWith({
    Offset? anchor,
    String? text,
    int? noteColor,
    bool? open,
    double? opacity,
  }) => NoteMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity ?? this.opacity,
    anchor: anchor ?? this.anchor,
    text: text ?? this.text,
    noteColor: noteColor ?? this.noteColor,
    author: author,
    open: open ?? this.open,
  );

  @override
  NoteMarkup moved(Offset delta) => copyWith(anchor: anchor + delta);
  @override
  NoteMarkup resizedTo(Rect newFrame) => copyWith(anchor: newFrame.topLeft);
  @override
  NoteMarkup rotatedTo(double degrees) => this;
  @override
  NoteMarkup recolored(int argb) => copyWith(noteColor: argb);

  @override
  NoteMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => NoteMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    anchor: anchor,
    text: text,
    noteColor: noteColor,
    author: author,
    open: open,
  );

  @override
  bool hitTest(Offset p, double tolerance) =>
      bounds.inflate(tolerance).contains(p);

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'anchor': _off(anchor),
    'text': text,
    'color': noteColor,
    if (author.isNotEmpty) 'author': author,
    if (open) 'open': true,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) {
    final c = from.remapTo(to, bounds.center);
    return copyWith(
      anchor: c - const Offset(kNoteIconSize / 2, kNoteIconSize / 2),
    );
  }
}

// ---------------------------------------------------------------------- link

class LinkMarkup extends MarkupObject {
  const LinkMarkup({
    required super.id,
    required super.page,
    super.name,
    super.hidden,
    super.locked,
    super.groupId,
    super.opacity,
    required this.linkFrame,
    this.text = '',
    this.uri,
    this.destPage,
    this.showBorder = false,
  });

  final Rect linkFrame;

  /// Visible words drawn inside [linkFrame] (underlined blue link style).
  final String text;
  final String? uri;

  /// 1-based go-to page (when [uri] is null).
  final int? destPage;
  final bool showBorder;

  bool get isUri => uri != null && uri!.trim().isNotEmpty;

  /// Font size used when painting / burning link text.
  static const double textFontSize = 12;

  @override
  MarkupType get type => MarkupType.link;
  @override
  Rect get frame => linkFrame;
  @override
  Rect get bounds => linkFrame;
  @override
  bool get canRotate => false;

  @override
  String get defaultLabel {
    final label = text.trim();
    if (label.isNotEmpty) {
      return label.length > 28 ? '${label.substring(0, 28)}…' : label;
    }
    return isUri
        ? 'Link: ${uri!.length > 26 ? '${uri!.substring(0, 26)}…' : uri}'
        : 'Link → page ${destPage ?? '?'}';
  }

  @override
  int get color => 0xFF1E6FD9;

  /// URL normalized for launching / writing.
  String? get normalizedUri {
    if (!isUri) return null;
    final u = uri!.trim();
    if (u.contains('://') || u.startsWith('mailto:') || u.startsWith('tel:')) {
      return u;
    }
    if (RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(u)) return 'mailto:$u';
    return 'https://$u';
  }

  LinkMarkup copyWith({
    Rect? linkFrame,
    String? text,
    String? Function()? uri,
    int? Function()? destPage,
    bool? showBorder,
  }) => LinkMarkup(
    id: id,
    page: page,
    name: name,
    hidden: hidden,
    locked: locked,
    groupId: groupId,
    opacity: opacity,
    linkFrame: linkFrame ?? this.linkFrame,
    text: text ?? this.text,
    uri: uri != null ? uri() : this.uri,
    destPage: destPage != null ? destPage() : this.destPage,
    showBorder: showBorder ?? this.showBorder,
  );

  @override
  LinkMarkup moved(Offset delta) => copyWith(linkFrame: linkFrame.shift(delta));
  @override
  LinkMarkup resizedTo(Rect newFrame) => copyWith(linkFrame: newFrame);
  @override
  LinkMarkup rotatedTo(double degrees) => this;
  @override
  LinkMarkup recolored(int argb) => this;

  @override
  LinkMarkup withCommon({
    String? id,
    int? page,
    String? name,
    bool? hidden,
    bool? locked,
    double? opacity,
    Object? groupId = _kKeep,
  }) => LinkMarkup(
    id: id ?? this.id,
    page: page ?? this.page,
    name: name ?? this.name,
    hidden: hidden ?? this.hidden,
    locked: locked ?? this.locked,
    groupId: identical(groupId, _kKeep) ? this.groupId : groupId as String?,
    opacity: opacity ?? this.opacity,
    linkFrame: linkFrame,
    text: text,
    uri: uri,
    destPage: destPage,
    showBorder: showBorder,
  );

  @override
  bool hitTest(Offset p, double tolerance) =>
      linkFrame.inflate(tolerance).contains(p);

  @override
  Map<String, dynamic> toJson() => {
    ...commonJson(),
    'frame': _rect(linkFrame),
    if (text.isNotEmpty) 'text': text,
    if (uri != null) 'uri': uri,
    if (destPage != null) 'dest': destPage,
    if (showBorder) 'border': true,
  };

  @override
  MarkupObject remapped(PdfPageGeometry from, PdfPageGeometry to) => copyWith(
    linkFrame: Rect.fromPoints(
      from.remapTo(to, linkFrame.topLeft),
      from.remapTo(to, linkFrame.bottomRight),
    ),
  );
}

// ------------------------------------------------------------------- helpers

double distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.distanceSquared;
  if (len2 < 1e-9) return (p - a).distance;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / len2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Chaikin-style smoothing + light decimation for freehand strokes.
List<Offset> smoothStroke(List<Offset> raw, {double minDistance = 0.8}) {
  if (raw.length < 3) return List.of(raw);
  final pts = <Offset>[raw.first];
  for (final p in raw.skip(1)) {
    if ((p - pts.last).distance >= minDistance) pts.add(p);
  }
  if (pts.last != raw.last) pts.add(raw.last);
  if (pts.length < 3) return pts;
  var cur = pts;
  for (var iter = 0; iter < 2; iter++) {
    final next = <Offset>[cur.first];
    for (var i = 0; i < cur.length - 1; i++) {
      final a = cur[i], b = cur[i + 1];
      next.add(Offset(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25));
      next.add(Offset(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
    }
    next.add(cur.last);
    cur = next;
  }
  return cur;
}

/// Scalloped cloud outline for a closed polygon (display points).
///
/// Returns a list of arcs as (start, control, end) quadratic segments so the
/// painter and PDF writer draw exactly the same bumps.
List<(Offset, Offset, Offset)> cloudArcs(List<Offset> poly, double radius) {
  final out = <(Offset, Offset, Offset)>[];
  if (poly.length < 3) return out;
  final area = _signedArea(poly);
  final outward = area > 0 ? -1.0 : 1.0; // y-down orientation
  for (var i = 0; i < poly.length; i++) {
    final a = poly[i], b = poly[(i + 1) % poly.length];
    final len = (b - a).distance;
    if (len < 1e-3) continue;
    final n = math.max(1, (len / (radius * 1.6)).round());
    final dir = (b - a) / len;
    final normal = Offset(-dir.dy, dir.dx) * outward;
    for (var k = 0; k < n; k++) {
      final s = a + (b - a) * (k / n);
      final e = a + (b - a) * ((k + 1) / n);
      final mid = (s + e) / 2;
      final bump = (e - s).distance * 0.55;
      out.add((s, mid + normal * bump, e));
    }
  }
  return out;
}

double _signedArea(List<Offset> poly) {
  var a = 0.0;
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i], q = poly[(i + 1) % poly.length];
    a += p.dx * q.dy - q.dx * p.dy;
  }
  return a / 2;
}

/// Arrowhead triangle (tip, left, right) for a line ending at [tip].
List<Offset> arrowHead(Offset from, Offset tip, double strokeWidth) {
  final len = math.max(8.0, strokeWidth * 4 + 6);
  final d = tip - from;
  final dist = d.distance;
  if (dist < 1e-6) return [tip, tip, tip];
  final u = d / dist;
  final back = tip - u * len;
  final n = Offset(-u.dy, u.dx) * (len * 0.45);
  return [tip, back + n, back - n];
}
