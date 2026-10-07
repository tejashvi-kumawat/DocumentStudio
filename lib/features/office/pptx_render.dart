import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/features/office/office_fonts.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Decoded pictures by package path, so slides paint synchronously
/// (thumbnails, slideshow, offscreen export).
class PptxImages {
  static final _cache = <String, ui.Image>{};
  static final _loading = <String, Future<void>>{};
  static final changes = ValueNotifier<int>(0);

  static ui.Image? get(PptxDocument doc, String path) {
    final img = _cache[_key(doc, path)];
    if (img == null) unawaitedLoad(doc, path);
    return img;
  }

  static String _key(PptxDocument doc, String path) =>
      '${identityHashCode(doc.files[path])}:$path';

  static Future<void> unawaitedLoad(PptxDocument doc, String path) {
    final k = _key(doc, path);
    return _loading.putIfAbsent(k, () async {
      final bytes = doc.files[path];
      if (bytes == null) return;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _cache[k] = frame.image;
        changes.value++;
      } catch (_) {}
    });
  }

  static Future<void> preload(PptxDocument doc) async {
    final media = {
      for (final s in doc.slides)
        for (final sh in s.shapes) ?sh.media,
    };
    await Future.wait(media.map((m) => unawaitedLoad(doc, m)));
  }
}

/// Every font a deck uses, loaded before drawing it offscreen.
Set<String> pptxFonts(PptxDocument doc) => {
  doc.theme.major,
  doc.theme.minor,
  for (final s in doc.slides)
    for (final sh in s.shapes)
      for (final para in sh.paras)
        for (final r in para.runs) doc.fontName(r.font, title: sh.titleFont),
};

/// One slide drawn at [width] logical pixels.
class PptxSlideView extends StatelessWidget {
  const PptxSlideView({
    super.key,
    required this.doc,
    required this.slide,
    required this.width,
    this.overlayBuilder,
    this.hideShape,
    this.showPrompts = false,
    this.decorate,
  });

  /// Wraps each object (slideshow animations).
  final Widget Function(PptxShape shape, Rect rect, Widget child)? decorate;

  final PptxDocument doc;
  final PptxSlide slide;
  final double width;

  /// Extra layer per shape (selection handles, editors) in slide pixels.
  final Widget? Function(PptxShape shape, Rect rect)? overlayBuilder;

  /// A shape drawn by the overlay instead (being edited).
  final PptxShape? hideShape;

  /// "Click to add title" in empty placeholders (editing view only).
  final bool showPrompts;

  double get scale => width / doc.width; // px per EMU

  Rect rectOf(PptxShape s) =>
      Rect.fromLTWH(s.x * scale, s.y * scale, s.w * scale, s.h * scale);

  @override
  Widget build(BuildContext context) {
    final height = width / doc.aspect;
    final ptToPx = width / (doc.width / emuPerPt);
    return ListenableBuilder(
      listenable: Listenable.merge([PptxImages.changes, OfficeFonts.instance]),
      builder: (context, _) => SizedBox(
        width: width,
        height: height,
        child: ClipRect(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: doc.resolve(slide.background) ?? Colors.white,
                ),
              ),
              for (final s in slide.shapes)
                if (!identical(s, hideShape))
                  Positioned.fromRect(
                    rect: rectOf(s),
                    child: () {
                      final w = Transform.rotate(
                        angle: s.rotation * math.pi / 180,
                        child: PptxShapeView(
                          doc: doc,
                          shape: s,
                          ptToPx: ptToPx,
                          showPrompt: showPrompts,
                        ),
                      );
                      return decorate == null ? w : decorate!(s, rectOf(s), w);
                    }(),
                  ),
              if (overlayBuilder != null)
                for (final s in slide.shapes) ?overlayBuilder!(s, rectOf(s)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One object of a slide (without position; fills its box).
class PptxShapeView extends StatelessWidget {
  const PptxShapeView({
    super.key,
    required this.doc,
    required this.shape,
    required this.ptToPx,
    this.showPrompt = false,
  });
  final PptxDocument doc;
  final PptxShape shape;
  final double ptToPx;
  final bool showPrompt;

  @override
  Widget build(BuildContext context) {
    final s = shape;
    switch (s.kind) {
      case PptxShapeKind.picture:
        final img = s.media == null ? null : PptxImages.get(doc, s.media!);
        final border = doc.resolve(s.line);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: border == null
                ? null
                : Border.all(
                    color: border,
                    width: math.max(
                      1,
                      (s.lineWidth ?? 12700) / emuPerPt * ptToPx,
                    ),
                  ),
          ),
          child: img == null
              ? const ColoredBox(color: Color(0x11000000))
              : RawImage(image: img, fit: BoxFit.fill),
        );
      case PptxShapeKind.table:
        return _table(s);
      case PptxShapeKind.other:
        return DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x0A000000),
            border: Border.all(color: const Color(0x33000000)),
          ),
          child: Center(
            child: Text(
              s.label,
              style: TextStyle(fontSize: 12 * ptToPx, color: Colors.black45),
            ),
          ),
        );
      case PptxShapeKind.text:
        final fill = doc.resolve(s.fill);
        final line = s.line == 'none' ? null : doc.resolve(s.line);
        final lw = math.max(0.75, (s.lineWidth ?? 9525) / emuPerPt * ptToPx);
        final empty = s.plainText.trim().isEmpty;
        final prompt = showPrompt && empty && s.placeholder != null;
        return CustomPaint(
          painter: s.geom == null && fill == null && line == null && !prompt
              ? null
              : PptxGeomPainter(
                  geom: s.geom ?? 'rect',
                  fill: fill,
                  line: line ?? (prompt ? const Color(0x55808080) : null),
                  lineWidth: line == null && prompt ? 1 : lw,
                  dashed: prompt && line == null,
                  flipH: s.flipH,
                  flipV: s.flipV,
                  arrow: s.arrowEnd,
                ),
          child: s.geom == 'line'
              ? const SizedBox.expand()
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 7.2 * ptToPx,
                    vertical: 3.6 * ptToPx,
                  ),
                  child: Align(
                    alignment: switch (s.anchor) {
                      'ctr' => Alignment.center,
                      'b' => Alignment.bottomCenter,
                      _ => Alignment.topCenter,
                    },
                    child: prompt ? _prompt(s) : pptxParagraphs(doc, s, ptToPx),
                  ),
                ),
        );
    }
  }

  Widget _prompt(PptxShape s) {
    final text = switch (s.placeholder) {
      'title' || 'ctrTitle' => 'Click to add title',
      'subTitle' => 'Click to add subtitle',
      _ => 'Click to add text',
    };
    return Text(
      text,
      textAlign: s.isTitle || s.placeholder == 'subTitle'
          ? TextAlign.center
          : TextAlign.left,
      style: TextStyle(
        fontSize: s.sizeForLevel(0) * ptToPx * 0.8,
        color: const Color(0xFF8A8A8A),
        fontFamily: OfficeFonts.instance.familyFor(
          s.isTitle ? doc.theme.major : doc.theme.minor,
        ),
      ),
    );
  }

  Widget _table(PptxShape s) {
    final cells = s.cells ?? const [];
    if (cells.isEmpty) return const SizedBox.shrink();
    final cols = cells.fold<int>(1, (m, r) => math.max(m, r.length));
    final accent = doc.resolve('@accent1') ?? const Color(0xFF4472C4);
    final band = Color.alphaBlend(accent.withValues(alpha: 0.18), Colors.white);
    final light = Color.alphaBlend(
      accent.withValues(alpha: 0.08),
      Colors.white,
    );
    final font = OfficeFonts.instance.familyFor(doc.theme.minor);
    final fs = 14 * ptToPx;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: s.w / emuPerPt * ptToPx,
        child: Table(
          border: TableBorder.symmetric(
            inside: const BorderSide(color: Colors.white, width: 1),
          ),
          children: [
            for (var r = 0; r < cells.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r == 0 ? accent : (r.isOdd ? band : light),
                ),
                children: [
                  for (var c = 0; c < cols; c++)
                    Container(
                      constraints: BoxConstraints(
                        minHeight: s.h / cells.length / emuPerPt * ptToPx,
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 7 * ptToPx,
                        vertical: 4 * ptToPx,
                      ),
                      alignment: Alignment.centerLeft,
                      child: Text(
                        c < cells[r].length ? cells[r][c] : '',
                        style: TextStyle(
                          fontSize: fs,
                          fontFamily: font,
                          color: r == 0 ? Colors.white : Colors.black87,
                          fontWeight: r == 0 ? FontWeight.w700 : null,
                          height: 1.2,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// The text of a shape, styled as PowerPoint draws it.
Widget pptxParagraphs(PptxDocument doc, PptxShape s, double ptToPx) {
  final counters = <int, int>{};
  final defColor = doc.resolve(s.fontColor ?? '@tx1') ?? Colors.black;
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final para in s.paras)
        () {
          final base = s.sizeForLevel(para.level) * s.fontScale;
          String? marker;
          if (para.numbered && para.text.isNotEmpty) {
            final n = (counters[para.level] ?? 0) + 1;
            counters[para.level] = n;
            marker = '$n.  ';
          } else {
            counters.remove(para.level);
            if (para.bullet && para.text.isNotEmpty) marker = '•  ';
          }
          final firstRun = para.runs
              .where((r) => r.text.isNotEmpty)
              .firstOrNull;
          TextStyle style(PptxRun? r) => TextStyle(
            fontFamily: OfficeFonts.instance.familyFor(
              doc.fontName(r?.font, title: s.titleFont),
            ),
            fontSize:
                ((r?.sizePt ?? s.sizeForLevel(para.level)) * s.fontScale) *
                ptToPx,
            fontWeight: r?.bold == true ? FontWeight.w700 : FontWeight.w400,
            fontStyle: r?.italic == true ? FontStyle.italic : FontStyle.normal,
            decoration: TextDecoration.combine([
              if (r?.underline == true) TextDecoration.underline,
              if (r?.strike == true) TextDecoration.lineThrough,
            ]),
            color: doc.resolve(r?.color) ?? defColor,
            height: 1.18 * (para.lineSpacing ?? 1.0),
          );
          return Padding(
            padding: EdgeInsets.only(left: para.level * 28 * ptToPx),
            child: RichText(
              textAlign: switch (para.align ?? s.defaultAlign) {
                'ctr' => TextAlign.center,
                'r' => TextAlign.right,
                'just' => TextAlign.justify,
                _ => TextAlign.left,
              },
              text: TextSpan(
                style: style(firstRun).copyWith(fontSize: base * ptToPx),
                children: [
                  if (marker != null)
                    TextSpan(text: marker, style: style(firstRun)),
                  for (final r in para.runs)
                    TextSpan(
                      text: r.text == '\v' ? '\n' : r.text,
                      style: style(r),
                    ),
                  if (para.text.isEmpty)
                    TextSpan(text: ' ', style: style(firstRun)),
                ],
              ),
            ),
          );
        }(),
    ],
  );
}

/// Preset geometries of DrawingML (the common ones; others fall back to a
/// rectangle).
class PptxGeomPainter extends CustomPainter {
  PptxGeomPainter({
    required this.geom,
    this.fill,
    this.line,
    this.lineWidth = 1,
    this.dashed = false,
    this.flipH = false,
    this.flipV = false,
    this.arrow = false,
  });

  final String geom;
  final Color? fill, line;
  final double lineWidth;
  final bool dashed, flipH, flipV, arrow;

  static Path pathFor(String geom, Size size) {
    final w = size.width, h = size.height;
    final r = Rect.fromLTWH(0, 0, w, h);
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);
    switch (geom) {
      case 'ellipse' || 'flowChartConnector':
        return Path()..addOval(r);
      case 'roundRect' || 'flowChartAlternateProcess':
        return Path()..addRRect(
          RRect.fromRectAndRadius(r, Radius.circular(math.min(w, h) * 0.1667)),
        );
      case 'triangle':
        return poly([Offset(w / 2, 0), Offset(w, h), Offset(0, h)]);
      case 'rtTriangle':
        return poly([Offset.zero, Offset(w, h), Offset(0, h)]);
      case 'diamond' || 'flowChartDecision':
        return poly([
          Offset(w / 2, 0),
          Offset(w, h / 2),
          Offset(w / 2, h),
          Offset(0, h / 2),
        ]);
      case 'parallelogram' || 'flowChartInputOutput':
        return poly([
          Offset(w * 0.25, 0),
          Offset(w, 0),
          Offset(w * 0.75, h),
          Offset(0, h),
        ]);
      case 'trapezoid':
        return poly([
          Offset(w * 0.25, 0),
          Offset(w * 0.75, 0),
          Offset(w, h),
          Offset(0, h),
        ]);
      case 'pentagon' || 'homePlate':
        return geom == 'homePlate'
            ? poly([
                Offset.zero,
                Offset(w * 0.8, 0),
                Offset(w, h / 2),
                Offset(w * 0.8, h),
                Offset(0, h),
              ])
            : poly([for (var i = 0; i < 5; i++) _polar(w, h, -90 + i * 72.0)]);
      case 'hexagon':
        return poly([
          Offset(w * 0.25, 0),
          Offset(w * 0.75, 0),
          Offset(w, h / 2),
          Offset(w * 0.75, h),
          Offset(w * 0.25, h),
          Offset(0, h / 2),
        ]);
      case 'octagon':
        final k = math.min(w, h) * 0.29;
        return poly([
          Offset(k, 0),
          Offset(w - k, 0),
          Offset(w, k),
          Offset(w, h - k),
          Offset(w - k, h),
          Offset(k, h),
          Offset(0, h - k),
          Offset(0, k),
        ]);
      case 'star5' || 'star4' || 'star6' || 'star8':
        final n = int.parse(geom.substring(4));
        final inner = n == 4 ? 0.25 : 0.42;
        return poly([
          for (var i = 0; i < n * 2; i++)
            _polar(w, h, -90 + i * 180 / n, i.isOdd ? inner : 1),
        ]);
      case 'rightArrow':
        return poly([
          Offset(0, h * 0.25),
          Offset(w * 0.7, h * 0.25),
          Offset(w * 0.7, 0),
          Offset(w, h / 2),
          Offset(w * 0.7, h),
          Offset(w * 0.7, h * 0.75),
          Offset(0, h * 0.75),
        ]);
      case 'leftArrow':
        return poly([
          Offset(w, h * 0.25),
          Offset(w * 0.3, h * 0.25),
          Offset(w * 0.3, 0),
          Offset(0, h / 2),
          Offset(w * 0.3, h),
          Offset(w * 0.3, h * 0.75),
          Offset(w, h * 0.75),
        ]);
      case 'upArrow':
        return poly([
          Offset(w * 0.25, h),
          Offset(w * 0.25, h * 0.3),
          Offset(0, h * 0.3),
          Offset(w / 2, 0),
          Offset(w, h * 0.3),
          Offset(w * 0.75, h * 0.3),
          Offset(w * 0.75, h),
        ]);
      case 'downArrow':
        return poly([
          Offset(w * 0.25, 0),
          Offset(w * 0.25, h * 0.7),
          Offset(0, h * 0.7),
          Offset(w / 2, h),
          Offset(w, h * 0.7),
          Offset(w * 0.75, h * 0.7),
          Offset(w * 0.75, 0),
        ]);
      case 'leftRightArrow':
        return poly([
          Offset(0, h / 2),
          Offset(w * 0.2, 0),
          Offset(w * 0.2, h * 0.25),
          Offset(w * 0.8, h * 0.25),
          Offset(w * 0.8, 0),
          Offset(w, h / 2),
          Offset(w * 0.8, h),
          Offset(w * 0.8, h * 0.75),
          Offset(w * 0.2, h * 0.75),
          Offset(w * 0.2, h),
        ]);
      case 'chevron':
        return poly([
          Offset.zero,
          Offset(w * 0.75, 0),
          Offset(w, h / 2),
          Offset(w * 0.75, h),
          Offset(0, h),
          Offset(w * 0.25, h / 2),
        ]);
      case 'plus' || 'mathPlus':
        final a = w / 3, b = h / 3;
        return poly([
          Offset(a, 0),
          Offset(2 * a, 0),
          Offset(2 * a, b),
          Offset(w, b),
          Offset(w, 2 * b),
          Offset(2 * a, 2 * b),
          Offset(2 * a, h),
          Offset(a, h),
          Offset(a, 2 * b),
          Offset(0, 2 * b),
          Offset(0, b),
          Offset(a, b),
        ]);
      case 'heart':
        return Path()
          ..moveTo(w / 2, h * 0.25)
          ..cubicTo(w * 0.5, 0, 0, 0, 0, h * 0.3)
          ..cubicTo(0, h * 0.6, w * 0.4, h * 0.8, w / 2, h)
          ..cubicTo(w * 0.6, h * 0.8, w, h * 0.6, w, h * 0.3)
          ..cubicTo(w, 0, w * 0.5, 0, w / 2, h * 0.25)
          ..close();
      case 'wedgeRectCallout' || 'wedgeRoundRectCallout':
        return Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(0, 0, w, h * 0.8),
              Radius.circular(
                geom == 'wedgeRectCallout' ? 0 : math.min(w, h) * 0.1,
              ),
            ),
          )
          ..addPolygon([
            Offset(w * 0.2, h * 0.79),
            Offset(w * 0.15, h),
            Offset(w * 0.4, h * 0.79),
          ], true);
      case 'snip1Rect':
        final k = math.min(w, h) * 0.17;
        return poly([
          Offset.zero,
          Offset(w - k, 0),
          Offset(w, k),
          Offset(w, h),
          Offset(0, h),
        ]);
      case 'cloud' || 'cloudCallout':
        return Path()
          ..addOval(Rect.fromLTWH(0, h * 0.25, w * 0.5, h * 0.6))
          ..addOval(Rect.fromLTWH(w * 0.25, 0, w * 0.5, h * 0.65))
          ..addOval(Rect.fromLTWH(w * 0.5, h * 0.2, w * 0.5, h * 0.65))
          ..addOval(Rect.fromLTWH(w * 0.2, h * 0.4, w * 0.6, h * 0.6));
      default:
        return Path()..addRect(r);
    }
  }

  static Offset _polar(double w, double h, double deg, [double k = 1]) {
    final a = deg * math.pi / 180;
    return Offset(
      w / 2 + w / 2 * k * math.cos(a),
      h / 2 + h / 2 * k * math.sin(a),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (geom == 'line' ||
        geom == 'straightConnector1' ||
        geom.startsWith('bentConnector') ||
        geom.startsWith('curvedConnector')) {
      final a = Offset(flipH ? size.width : 0, flipV ? size.height : 0);
      final b = Offset(flipH ? 0 : size.width, flipV ? 0 : size.height);
      final paint = Paint()
        ..color = line ?? Colors.black
        ..strokeWidth = lineWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(a, b, paint);
      if (arrow) {
        final dir = (b - a);
        final len = dir.distance;
        if (len > 0) {
          final u = dir / len;
          final n = Offset(-u.dy, u.dx);
          final head = math.max(lineWidth * 3.5, 8.0);
          canvas.drawPath(
            Path()..addPolygon([
              b,
              b - u * head + n * head * 0.5,
              b - u * head - n * head * 0.5,
            ], true),
            Paint()..color = paint.color,
          );
        }
      }
      return;
    }
    final path = pathFor(geom, size);
    if (fill != null) canvas.drawPath(path, Paint()..color = fill!);
    if (line != null && lineWidth > 0) {
      final paint = Paint()
        ..color = line!
        ..style = PaintingStyle.stroke
        ..strokeWidth = lineWidth;
      if (dashed) {
        for (final m in path.computeMetrics()) {
          for (var d = 0.0; d < m.length; d += 8) {
            canvas.drawPath(m.extractPath(d, math.min(d + 4, m.length)), paint);
          }
        }
      } else {
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(PptxGeomPainter old) =>
      old.geom != geom ||
      old.fill != fill ||
      old.line != line ||
      old.lineWidth != lineWidth ||
      old.dashed != dashed ||
      old.flipH != flipH ||
      old.flipV != flipV ||
      old.arrow != arrow;
}

/// Draws [slide] offscreen to PNG at [widthPx] (export, print).
Future<Uint8List> renderSlidePng(
  PptxDocument doc,
  PptxSlide slide,
  double widthPx, {
  double pixelRatio = 1,
}) async {
  final boundary = RenderRepaintBoundary();
  final view =
      WidgetsBinding.instance.platformDispatcher.implicitView ??
      WidgetsBinding.instance.platformDispatcher.views.first;
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(
        Size(widthPx, widthPx / doc.aspect),
      ),
    ),
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: PptxSlideView(doc: doc, slide: slide, width: widthPx),
      ),
    ),
  ).attachToRenderTree(buildOwner);
  buildOwner
    ..buildScope(root)
    ..finalizeTree();
  pipeline
    ..flushLayout()
    ..flushCompositingBits()
    ..flushPaint();
  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
      .attachToRenderTree(buildOwner, root);
  buildOwner.finalizeTree();
  return bytes!.buffer.asUint8List();
}

/// Every visible slide as one PDF page (slide size), drawn exactly as on
/// screen — fonts, theme colours, shapes and pictures.
Future<Uint8List> pptxToPdf(
  PptxDocument doc, {
  bool includeHidden = false,
}) async {
  await Future.wait([
    PptxImages.preload(doc),
    OfficeFonts.instance.ensure(pptxFonts(doc)),
  ]);
  final pdf = pw.Document(creator: 'Document Studio');
  final wPt = doc.width / emuPerPt, hPt = doc.height / emuPerPt;
  for (final slide in doc.slides) {
    if (slide.hidden && !includeHidden) continue;
    final png = await renderSlidePng(doc, slide, 1280, pixelRatio: 1.5);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(wPt, hPt),
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.fill),
      ),
    );
  }
  return pdf.save();
}
