import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color, HSLColor;

import 'package:archive/archive.dart';
import 'package:document_studio/features/office/pptx_animation.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _relNs = 'http://schemas.openxmlformats.org/package/2006/relationships';
const _ctNs = 'http://schemas.openxmlformats.org/package/2006/content-types';
const _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const emuPerPt = 12700.0;

/// Elements from an XML fragment (prefixes a:, p:, r: declared).
List<XmlElement> _frag(String inner) =>
    XmlDocument.parse('<x xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">$inner</x>')
        .rootElement
        .childElements
        .map((e) => e.copy())
        .toList();

XmlElement _el(String xml) => _frag(xml).single;

String _esc(String t) => t
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Colours are kept as written: `RRGGBB`, or a theme colour `@accent1`
/// with optional luminance changes `@accent1/75000/25000` (lumMod/lumOff),
/// so a deck keeps following its theme after editing.
String? _readColor(XmlElement? holder) {
  if (holder == null) return null;
  for (final c in holder.childElements) {
    switch (c.name.local) {
      case 'srgbClr':
        return c.getAttribute('val')?.toUpperCase();
      case 'sysClr':
        return c.getAttribute('lastClr')?.toUpperCase();
      case 'prstClr':
        return const {
          'black': '000000',
          'white': 'FFFFFF',
          'red': 'FF0000',
          'blue': '0000FF',
          'green': '008000',
        }[c.getAttribute('val')];
      case 'schemeClr':
        final mod = c
            .getElement('lumMod', namespaceUri: _a)
            ?.getAttribute('val');
        final off = c
            .getElement('lumOff', namespaceUri: _a)
            ?.getAttribute('val');
        final v = c.getAttribute('val');
        if (v == null || v == 'phClr') return null;
        return mod == null && off == null
            ? '@$v'
            : '@$v/${mod ?? 100000}/${off ?? 0}';
    }
  }
  return null;
}

String _colorXml(String c) {
  if (!c.startsWith('@')) return '<a:srgbClr val="$c"/>';
  final parts = c.substring(1).split('/');
  if (parts.length == 1) return '<a:schemeClr val="${parts[0]}"/>';
  return '<a:schemeClr val="${parts[0]}"><a:lumMod val="${parts[1]}"/>${parts[2] == '0' ? '' : '<a:lumOff val="${parts[2]}"/>'}</a:schemeClr>';
}

/// Fill of a shape properties element: colour, 'none', or null (inherit).
String? _readFill(XmlElement? spPr) {
  if (spPr == null) return null;
  for (final c in spPr.childElements) {
    switch (c.name.local) {
      case 'noFill':
        return 'none';
      case 'solidFill':
        return _readColor(c);
      case 'gradFill':
        return _readColor(
          c.findAllElements('gs', namespaceUri: _a).firstOrNull,
        );
    }
  }
  return null;
}

class PptxRun {
  PptxRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.sizePt,
    this.color,
    this.font,
    this.rPr,
  });
  String text;
  bool bold, italic, underline, strike;
  double? sizePt;

  /// `RRGGBB` or `@scheme…` (see [_readColor]); null = inherited.
  String? color;

  /// Latin typeface; `+mj-lt` / `+mn-lt` are the theme's heading/body fonts.
  String? font;

  /// The original run properties (spacing, language, effects…) kept on save.
  XmlElement? rPr;

  PptxRun copyWith({String? text}) => PptxRun(
    text ?? this.text,
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    sizePt: sizePt,
    color: color,
    font: font,
    rPr: rPr?.copy(),
  );
}

class PptxPara {
  PptxPara(
    this.runs, {
    this.align,
    this.level = 0,
    this.bullet = false,
    this.numbered = false,
    this.lineSpacing,
    this.pPr,
    this.inheritedBullet = false,
  });
  List<PptxRun> runs;
  String? align; // l ctr r just
  int level;
  bool bullet;
  bool numbered;

  /// Line spacing as a multiple (1.0 = single); null inherits.
  double? lineSpacing;

  /// Original paragraph properties, kept on save.
  XmlElement? pPr;

  /// Bullets the placeholder gives this level without saying so here.
  bool inheritedBullet;
  String get text => runs.map((r) => r.text).join();
}

enum PptxShapeKind { text, picture, table, other }

/// One object on a slide: text box / placeholder / drawn shape (optional
/// text), picture, table, or something shown as a box (chart, SmartArt…).
class PptxShape {
  PptxShape({
    required this.kind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.node,
    this.paras = const [],
    this.media,
    this.fill,
    this.line,
    this.lineWidth,
    this.geom,
    this.label = '',
    this.defaultSizePt = 18,
    this.anchor = 't',
    this.rotation = 0,
    this.placeholder,
    this.fontColor,
    this.fontScale = 1,
    this.cells,
    this.flipH = false,
    this.flipV = false,
    this.arrowEnd = false,
    this.levelSizes = const [],
    this.defaultAlign,
    this.titleFont = false,
  });

  final PptxShapeKind kind;
  double x, y, w, h; // EMU
  XmlElement? node;
  List<PptxPara> paras;
  String? media; // package path of the picture
  String? fill; // colour, 'none' or null
  String? line;
  double? lineWidth; // EMU
  /// Preset geometry (`rect`, `ellipse`, `roundRect`, `line`…); null for a
  /// plain text box.
  String? geom;
  String label;
  double defaultSizePt;
  String anchor; // t ctr b
  double rotation; // degrees
  String? placeholder; // title ctrTitle body subTitle …
  String? fontColor; // default text colour (shape style / master)
  double fontScale; // normAutofit
  List<List<String>>? cells; // table text
  bool flipH, flipV, arrowEnd;

  /// Inherited text size per paragraph level (points).
  List<double> levelSizes;
  String? defaultAlign;

  /// Text uses the theme heading font by default.
  bool titleFont;

  bool dirtyGeometry = false;
  bool dirtyText = false;
  bool dirtyStyle = false;
  bool isNew = false;

  /// Inside a group: shown, but not moved on its own.
  bool get locked => node == null && !isNew;

  bool get isTitle => placeholder == 'title' || placeholder == 'ctrTitle';

  double sizeForLevel(int level) => levelSizes.isEmpty
      ? defaultSizePt
      : levelSizes[level.clamp(0, levelSizes.length - 1)];

  String get plainText => paras.map((e) => e.text).join('\n');
}

class PptxLayout {
  PptxLayout(this.path, this.name, this.type);
  final String path;
  final String name;
  final String? type;
}

/// Theme colours and fonts (Design tab).
class PptxTheme {
  PptxTheme({
    required this.colors,
    required this.major,
    required this.minor,
    this.name = 'Office',
  });
  Map<String, String> colors; // dk1 lt1 dk2 lt2 accent1…6 hlink folHlink
  String major, minor;
  String name;

  PptxTheme copy() =>
      PptxTheme(colors: Map.of(colors), major: major, minor: minor, name: name);
}

class PptxSlide {
  PptxSlide({
    required this.path,
    required this.xml,
    required this.shapes,
    this.background,
  });
  String path; // ppt/slides/slide1.xml
  XmlDocument xml;
  List<PptxShape> shapes;

  /// Background shown (own, layout's or master's).
  String? background;

  /// The slide sets its own background (Format Background).
  bool ownBackground = false;
  bool dirtyBackground = false;

  String? layoutPath;

  /// Transition into this slide: fade, push, wipe, split, cover, pull,
  /// cut, randomBar, dissolve, circle, zoom… (null = none).
  String? transition;
  String? transitionDir; // l u r d
  String transitionSpeed = 'med'; // fast med slow
  int? advanceAfterMs;
  bool dirtyTransition = false;

  bool hidden = false;
  bool dirtyHidden = false;

  String notes = '';
  String? notesPath;
  bool notesDirty = false;

  bool orderDirty = false;

  /// `p:sldId/@id` in presentation.xml (kept on save: sections and custom
  /// shows refer to it); null for new slides.
  int? sldId;

  /// Object animations in play order (Motion panel).
  List<PptxAnim> animations = [];
  bool dirtyAnimations = false;
  final removed = <XmlElement>[];
}

/// Undo point: slide XML (one slide or all) plus deck-wide parts.
class PptxSnapshot {
  PptxSnapshot._(this.slides, this.order, this.parts, this.width, this.height);
  final Map<String, String> slides;
  final List<String> order;
  final Map<String, Uint8List>? parts; // whole package for deck-wide edits
  final double width, height;
}

/// An opened .pptx: slides as editable objects plus the untouched package.
class PptxDocument {
  PptxDocument({
    required this.files,
    required this.width,
    required this.height,
    required this.slides,
  });

  /// Every part of the package by path (edited parts are replaced on save).
  final Map<String, Uint8List> files;
  double width, height; // EMU
  final List<PptxSlide> slides;

  PptxTheme theme = PptxTheme(
    colors: Map.of(_officeColors),
    major: 'Calibri Light',
    minor: 'Calibri',
  );
  Map<String, String> clrMap = const {
    'bg1': 'lt1',
    'tx1': 'dk1',
    'bg2': 'lt2',
    'tx2': 'dk2',
  };
  String? themePath;
  bool dirtyTheme = false;
  bool dirtySize = false;
  List<PptxLayout> layouts = [];

  double get aspect => width / height;

  Uint8List? mediaBytes(String path) => files[path];

  static const _officeColors = {
    'dk1': '000000',
    'lt1': 'FFFFFF',
    'dk2': '44546A',
    'lt2': 'E7E6E6',
    'accent1': '4472C4',
    'accent2': 'ED7D31',
    'accent3': 'A5A5A5',
    'accent4': 'FFC000',
    'accent5': '5B9BD5',
    'accent6': '70AD47',
    'hlink': '0563C1',
    'folHlink': '954F72',
  };

  /// A stored colour → ARGB, through the theme.
  Color? resolve(String? c) {
    if (c == null || c == 'none') return null;
    if (!c.startsWith('@')) {
      return c.length == 6
          ? Color(0xFF000000 | (int.tryParse(c, radix: 16) ?? 0))
          : null;
    }
    final parts = c.substring(1).split('/');
    final name = clrMap[parts[0]] ?? parts[0];
    final hex = theme.colors[name];
    if (hex == null) return null;
    var color = Color(0xFF000000 | (int.tryParse(hex, radix: 16) ?? 0));
    if (parts.length == 3) {
      final mod = (int.tryParse(parts[1]) ?? 100000) / 100000;
      final off = (int.tryParse(parts[2]) ?? 0) / 100000;
      final hsl = HSLColor.fromColor(color);
      color = hsl
          .withLightness((hsl.lightness * mod + off).clamp(0.0, 1.0))
          .toColor();
    }
    return color;
  }

  /// `+mj-lt` / `+mn-lt` → theme fonts.
  String fontName(String? f, {bool title = false}) {
    if (f == null || f.isEmpty) return title ? theme.major : theme.minor;
    if (f.startsWith('+mj')) return theme.major;
    if (f.startsWith('+mn')) return theme.minor;
    return f;
  }

  // -------------------------------------------------------------- reading

  static PptxDocument read(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{
      for (final f in archive.files)
        if (f.isFile) f.name: Uint8List.fromList(f.content as List<int>),
    };
    if (!files.containsKey('ppt/presentation.xml')) {
      throw const FormatException(
        'Not a PowerPoint file (ppt/presentation.xml missing)',
      );
    }
    final doc = PptxDocument(
      files: files,
      width: 12192000,
      height: 6858000,
      slides: [],
    );
    doc._load();
    return doc;
  }

  XmlDocument _xml(String path) =>
      XmlDocument.parse(utf8.decode(files[path]!, allowMalformed: true));

  // Layouts and masters are shared by many slides and never edited in
  // place: parse each once (re-parsed only when its bytes change).
  final _roCache = <String, (Uint8List, XmlDocument)>{};
  XmlDocument _ro(String path) {
    final b = files[path]!;
    final c = _roCache[path];
    if (c != null && identical(c.$1, b)) return c.$2;
    final d = XmlDocument.parse(utf8.decode(b, allowMalformed: true));
    _roCache[path] = (b, d);
    return d;
  }

  final _relsCache = <String, (Uint8List?, Map<String, String>)>{};
  Map<String, String> _relsOf(String part) {
    final b = files[_relPath(part)];
    final c = _relsCache[part];
    if (c != null && identical(c.$1, b)) return c.$2;
    final r = _rels(files, part);
    _relsCache[part] = (b, r);
    return r;
  }

  /// Placeholders of a layout/master by type and idx (built once).
  static final _phIndex = Expando<List<(String, String?, XmlElement)>>();
  static List<(String, String?, XmlElement)> _placeholders(XmlDocument d) =>
      _phIndex[d] ??= [
        for (final sp in d.findAllElements('sp', namespaceUri: _p))
          if (sp.findAllElements('ph', namespaceUri: _p).firstOrNull
              case final ph?)
            (ph.getAttribute('type') ?? 'body', ph.getAttribute('idx'), sp),
      ];

  static final _txStyles = Expando<List<XmlElement>>();
  static XmlElement? _txStylesOf(XmlDocument d) =>
      (_txStyles[d] ??= d
              .findAllElements('txStyles', namespaceUri: _p)
              .take(1)
              .toList())
          .firstOrNull;

  /// (Re)reads presentation, theme, layouts and every slide from [files].
  void _load({List<String>? order}) {
    final pres = _xml('ppt/presentation.xml');
    final sz = pres.findAllElements('sldSz', namespaceUri: _p).firstOrNull;
    width = double.tryParse(sz?.getAttribute('cx') ?? '') ?? 12192000;
    height = double.tryParse(sz?.getAttribute('cy') ?? '') ?? 6858000;
    final presRels = _relsOf('ppt/presentation.xml');
    // Master → theme, colour map, layouts.
    String? masterPath;
    for (final e in presRels.entries) {
      if (e.value.contains('slideMaster'))
        masterPath ??= _resolve('ppt/presentation.xml', e.value);
    }
    layouts = [];
    if (masterPath != null && files.containsKey(masterPath)) {
      final master = _ro(masterPath);
      final cm = master.findAllElements('clrMap', namespaceUri: _p).firstOrNull;
      if (cm != null) {
        clrMap = {for (final at in cm.attributes) at.name.local: at.value};
      }
      final mRels = _relsOf(masterPath);
      for (final e in mRels.entries) {
        if (e.value.contains('theme'))
          themePath = _resolve(masterPath, e.value);
      }
      for (final id in master.findAllElements(
        'sldLayoutId',
        namespaceUri: _p,
      )) {
        final t = mRels[id.getAttribute('id', namespaceUri: _r)];
        if (t == null) continue;
        final lp = _resolve(masterPath, t);
        if (!files.containsKey(lp)) continue;
        final l = _ro(lp);
        layouts.add(
          PptxLayout(
            lp,
            l
                    .findAllElements('cSld', namespaceUri: _p)
                    .firstOrNull
                    ?.getAttribute('name') ??
                p.posix.basenameWithoutExtension(lp),
            l.rootElement.getAttribute('type'),
          ),
        );
      }
    }
    if (themePath != null && files.containsKey(themePath)) {
      final t = _xml(themePath!);
      final scheme = t
          .findAllElements('clrScheme', namespaceUri: _a)
          .firstOrNull;
      final colors = Map.of(_officeColors);
      for (final c in scheme?.childElements ?? const <XmlElement>[]) {
        final v = _readColor(c);
        if (v != null && !v.startsWith('@')) colors[c.name.local] = v;
      }
      String font(String kind, String fallback) =>
          t
              .findAllElements(kind, namespaceUri: _a)
              .firstOrNull
              ?.getElement('latin', namespaceUri: _a)
              ?.getAttribute('typeface') ??
          fallback;
      theme = PptxTheme(
        colors: colors,
        major: font('majorFont', 'Calibri Light'),
        minor: font('minorFont', 'Calibri'),
        name: t.rootElement.getAttribute('name') ?? 'Office',
      );
    }
    slides.clear();
    final paths =
        order ??
        [
          for (final id in pres.findAllElements('sldId', namespaceUri: _p))
            if (presRels[id.getAttribute('id', namespaceUri: _r)] case final t?)
              p.posix.normalize(p.posix.join('ppt', t)),
        ];
    final sldIds = <String, int>{
      for (final id in pres.findAllElements('sldId', namespaceUri: _p))
        if (presRels[id.getAttribute('id', namespaceUri: _r)] case final t?)
          p.posix.normalize(p.posix.join('ppt', t)):
              int.tryParse(id.getAttribute('id') ?? '') ?? 0,
    };
    for (final path in paths) {
      if (!files.containsKey(path)) continue;
      slides.add(_readSlide(path, _xml(path))..sldId = sldIds[path]);
    }
  }

  static Map<String, String> _rels(Map<String, Uint8List> files, String part) {
    final data = files[_relPath(part)];
    if (data == null) return const {};
    final out = <String, String>{};
    for (final r in XmlDocument.parse(
      utf8.decode(data),
    ).findAllElements('Relationship')) {
      out[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
    return out;
  }

  static String _relPath(String part) => p.posix.join(
    p.posix.dirname(part),
    '_rels',
    '${p.posix.basename(part)}.rels',
  );

  static String _resolve(String part, String target) =>
      p.posix.normalize(p.posix.join(p.posix.dirname(part), target));

  PptxSlide _readSlide(String path, XmlDocument doc) {
    final rels = _relsOf(path);
    String? layoutPath, notesPath;
    for (final e in rels.entries) {
      if (e.value.contains('slideLayout')) layoutPath = _resolve(path, e.value);
      if (e.value.contains('notesSlide')) notesPath = _resolve(path, e.value);
    }
    XmlDocument? layout, master;
    if (layoutPath != null && files.containsKey(layoutPath)) {
      layout = _ro(layoutPath);
      for (final e in _relsOf(layoutPath).entries) {
        if (e.value.contains('slideMaster')) {
          final mp = _resolve(layoutPath, e.value);
          if (files.containsKey(mp)) master = _ro(mp);
        }
      }
    }

    XmlElement? placeholderIn(XmlDocument? d, String? type, String? idx) {
      if (d == null) return null;
      XmlElement? byType;
      for (final (t, i, sp) in _placeholders(d)) {
        if (idx != null && i == idx) return sp;
        if (type != null && t == type) byType ??= sp;
      }
      return byType;
    }

    String styleKind(String? phType) => switch (phType) {
      'title' || 'ctrTitle' => 'titleStyle',
      null || 'dt' || 'ftr' || 'sldNum' => 'otherStyle',
      _ => 'bodyStyle',
    };

    XmlElement? masterLvl(String? phType, int level) =>
        (master == null ? null : _txStylesOf(master))
            ?.getElement(styleKind(phType), namespaceUri: _p)
            ?.getElement('lvl${level + 1}pPr', namespaceUri: _a);

    // Inheritance chain of a placeholder: itself, layout, master.
    List<XmlElement> chainOf(XmlElement el, String? phType, String? phIdx) {
      if (phType == null) return [el];
      final general = phType == 'ctrTitle'
          ? 'title'
          : (phType == 'subTitle' ? 'body' : phType);
      return [
        el,
        ?placeholderIn(layout, phType, phIdx),
        ?placeholderIn(master, general, null),
      ];
    }

    XmlElement? lvlIn(XmlElement sp, int level) => sp
        .getElement('txBody', namespaceUri: _p)
        ?.getElement('lstStyle', namespaceUri: _a)
        ?.getElement('lvl${level + 1}pPr', namespaceUri: _a);

    T? inherit<T>(
      List<XmlElement> chain,
      String? phType,
      int level,
      T? Function(XmlElement lvlPPr) f,
    ) {
      for (final sp in chain) {
        final l = lvlIn(sp, level);
        final v = l == null ? null : f(l);
        if (v != null) return v;
      }
      final m = masterLvl(phType, level);
      return m == null ? null : f(m);
    }

    final shapes = <PptxShape>[];

    void walk(XmlElement tree, List<double> groupMap) {
      // groupMap: [offX, offY, scaleX, scaleY, chOffX, chOffY]
      for (final el in tree.childElements) {
        final name = el.name.local;
        if (name == 'AlternateContent') {
          final choice =
              el.childElements
                  .where((c) => c.name.local == 'Fallback')
                  .firstOrNull ??
              el.childElements.firstOrNull;
          if (choice != null) walk(choice, groupMap);
          continue;
        }
        if (name == 'grpSp') {
          final xfrm = el
              .getElement('grpSpPr', namespaceUri: _p)
              ?.getElement('xfrm', namespaceUri: _a);
          var map = groupMap;
          if (xfrm != null) {
            final off = _pt(xfrm, 'off'), ext = _pt(xfrm, 'ext');
            final chOff = _pt(xfrm, 'chOff'), chExt = _pt(xfrm, 'chExt');
            if (off != null &&
                ext != null &&
                chOff != null &&
                chExt != null &&
                chExt.$1 > 0 &&
                chExt.$2 > 0) {
              map = [
                groupMap[0] + (off.$1 - groupMap[4]) * groupMap[2],
                groupMap[1] + (off.$2 - groupMap[5]) * groupMap[3],
                ext.$1 / chExt.$1 * groupMap[2],
                ext.$2 / chExt.$2 * groupMap[3],
                chOff.$1,
                chOff.$2,
              ];
            }
          }
          walk(el, map);
          continue;
        }
        if (name != 'sp' &&
            name != 'pic' &&
            name != 'graphicFrame' &&
            name != 'cxnSp')
          continue;
        final ph = el.findAllElements('ph', namespaceUri: _p).firstOrNull;
        final phType = ph == null ? null : (ph.getAttribute('type') ?? 'body');
        final phIdx = ph?.getAttribute('idx');
        final chain = chainOf(el, phType, phIdx);
        XmlElement? xfrm;
        for (final c in chain) {
          xfrm =
              (c.getElement('spPr', namespaceUri: _p) ?? c).getElement(
                'xfrm',
                namespaceUri: _a,
              ) ??
              c.getElement('xfrm', namespaceUri: _p);
          if (xfrm != null) break;
        }
        final off = xfrm == null ? null : _pt(xfrm, 'off');
        final ext = xfrm == null ? null : _pt(xfrm, 'ext');
        if (off == null || ext == null) continue;
        final rot =
            (int.tryParse(xfrm?.getAttribute('rot') ?? '') ?? 0) / 60000;
        double gx(double v) => groupMap[0] + (v - groupMap[4]) * groupMap[2];
        double gy(double v) => groupMap[1] + (v - groupMap[5]) * groupMap[3];
        final x = gx(off.$1),
            y = gy(off.$2),
            w = ext.$1 * groupMap[2],
            h = ext.$2 * groupMap[3];
        final inGroup =
            groupMap[2] != 1 ||
            groupMap[3] != 1 ||
            groupMap[0] != 0 ||
            groupMap[1] != 0;
        final node = inGroup ? null : el;

        if (name == 'pic') {
          final blip = el.findAllElements('blip', namespaceUri: _a).firstOrNull;
          final rid = blip?.getAttribute('embed', namespaceUri: _r);
          final target = rid == null ? null : rels[rid];
          shapes.add(
            PptxShape(
              kind: PptxShapeKind.picture,
              x: x,
              y: y,
              w: w,
              h: h,
              node: node,
              media: target == null ? null : _resolve(path, target),
              label: 'Picture',
              rotation: rot,
              line: _readColor(
                el
                    .getElement('spPr', namespaceUri: _p)
                    ?.getElement('ln', namespaceUri: _a)
                    ?.getElement('solidFill', namespaceUri: _a),
              ),
            ),
          );
          continue;
        }
        if (name == 'graphicFrame') {
          final tbl = el.findAllElements('tbl', namespaceUri: _a).firstOrNull;
          if (tbl != null) {
            final cells = [
              for (final tr in tbl.findElements('tr', namespaceUri: _a))
                [
                  for (final tc in tr.findElements('tc', namespaceUri: _a))
                    tc
                        .findAllElements('p', namespaceUri: _a)
                        .map(
                          (pp) => pp
                              .findAllElements('t', namespaceUri: _a)
                              .map((t) => t.innerText)
                              .join(),
                        )
                        .join('\n'),
                ],
            ];
            shapes.add(
              PptxShape(
                kind: PptxShapeKind.table,
                x: x,
                y: y,
                w: w,
                h: h,
                node: node,
                cells: cells,
                label: 'Table',
                defaultSizePt: 18,
              ),
            );
          } else {
            shapes.add(
              PptxShape(
                kind: PptxShapeKind.other,
                x: x,
                y: y,
                w: w,
                h: h,
                node: node,
                label: 'Chart / diagram',
                defaultSizePt: 14,
              ),
            );
          }
          continue;
        }
        final spPr = el.getElement('spPr', namespaceUri: _p);
        final style = el.getElement('style', namespaceUri: _p);
        String? styleColor(String ref) {
          final r = style?.getElement(ref, namespaceUri: _a);
          if (r == null || r.getAttribute('idx') == '0') return null;
          return _readColor(r);
        }

        var fill = _readFill(spPr) ?? styleColor('fillRef');
        final ln = spPr?.getElement('ln', namespaceUri: _a);
        var line = ln == null ? null : _readFill(ln);
        line ??= styleColor('lnRef');
        if (name == 'cxnSp') fill = 'none';
        final lineW = double.tryParse(ln?.getAttribute('w') ?? '');
        final prst =
            spPr
                ?.getElement('prstGeom', namespaceUri: _a)
                ?.getAttribute('prst') ??
            (spPr?.getElement('custGeom', namespaceUri: _a) != null
                ? 'rect'
                : null);
        final txBox =
            el
                .findAllElements('cNvSpPr', namespaceUri: _p)
                .firstOrNull
                ?.getAttribute('txBox') ==
            '1';
        final txBody = el.getElement('txBody', namespaceUri: _p);
        final bodyPr = txBody?.getElement('bodyPr', namespaceUri: _a);
        String? anchor;
        for (final c in chain) {
          anchor = c
              .getElement('txBody', namespaceUri: _p)
              ?.getElement('bodyPr', namespaceUri: _a)
              ?.getAttribute('anchor');
          if (anchor != null) break;
        }
        anchor ??= phType == 'title' || phType == 'ctrTitle'
            ? 'ctr'
            : (txBody != null && !txBox && phType == null && prst != null
                  ? 'ctr'
                  : 't');
        final autofit = bodyPr?.getElement('normAutofit', namespaceUri: _a);
        final fontScale =
            (int.tryParse(autofit?.getAttribute('fontScale') ?? '') ?? 100000) /
            100000;

        final levelSizes = [
          for (var lv = 0; lv < 5; lv++)
            inherit<double>(chain, phType, lv, (l) {
                  final sz = l
                      .getElement('defRPr', namespaceUri: _a)
                      ?.getAttribute('sz');
                  return sz == null ? null : int.parse(sz) / 100;
                }) ??
                (phType == 'title' || phType == 'ctrTitle' ? 44 : 18),
        ];
        final defaultAlign = inherit<String>(
          chain,
          phType,
          0,
          (l) => l.getAttribute('algn'),
        );
        final fontColor =
            styleColor('fontRef') ??
            inherit<String>(
              chain,
              phType,
              0,
              (l) => _readColor(
                l
                    .getElement('defRPr', namespaceUri: _a)
                    ?.getElement('solidFill', namespaceUri: _a),
              ),
            );

        final paras = <PptxPara>[];
        for (final para
            in txBody?.findElements('p', namespaceUri: _a) ??
                const <XmlElement>[]) {
          final pPr = para.getElement('pPr', namespaceUri: _a);
          final level = int.tryParse(pPr?.getAttribute('lvl') ?? '') ?? 0;
          bool? bulletIn(XmlElement? l) {
            if (l == null) return null;
            if (l.getElement('buNone', namespaceUri: _a) != null) return false;
            if (l.getElement('buChar', namespaceUri: _a) != null ||
                l.getElement('buAutoNum', namespaceUri: _a) != null)
              return true;
            return null;
          }

          final inherited =
              phType == 'title' || phType == 'ctrTitle' || phType == 'subTitle'
              ? false
              : (inherit<bool>(chain, phType, level, bulletIn) ?? false);
          final own = bulletIn(pPr);
          final numbered =
              pPr?.getElement('buAutoNum', namespaceUri: _a) != null;
          final lnPct = pPr
              ?.getElement('lnSpc', namespaceUri: _a)
              ?.getElement('spcPct', namespaceUri: _a)
              ?.getAttribute('val');
          final runs = <PptxRun>[];
          for (final r in para.childElements) {
            if (r.name.local == 'br') {
              runs.add(PptxRun('\v'));
              continue;
            }
            if (r.name.local != 'r' && r.name.local != 'fld') continue;
            final rPr = r.getElement('rPr', namespaceUri: _a);
            final sz = rPr?.getAttribute('sz');
            runs.add(
              PptxRun(
                r.getElement('t', namespaceUri: _a)?.innerText ?? '',
                bold:
                    rPr?.getAttribute('b') == '1' ||
                    rPr?.getAttribute('b') == 'true',
                italic:
                    rPr?.getAttribute('i') == '1' ||
                    rPr?.getAttribute('i') == 'true',
                underline: (rPr?.getAttribute('u') ?? 'none') != 'none',
                strike:
                    (rPr?.getAttribute('strike') ?? 'noStrike') != 'noStrike',
                sizePt: sz == null ? null : int.parse(sz) / 100,
                color: _readColor(
                  rPr?.getElement('solidFill', namespaceUri: _a),
                ),
                font: rPr
                    ?.getElement('latin', namespaceUri: _a)
                    ?.getAttribute('typeface'),
                rPr: rPr?.copy(),
              ),
            );
          }
          paras.add(
            PptxPara(
              runs,
              align: pPr?.getAttribute('algn'),
              level: level,
              bullet: own ?? inherited,
              numbered: numbered,
              lineSpacing: lnPct == null ? null : int.parse(lnPct) / 100000,
              pPr: pPr?.copy(),
              inheritedBullet: inherited,
            ),
          );
        }
        final isTitle = phType == 'title' || phType == 'ctrTitle';
        shapes.add(
          PptxShape(
            kind: txBody == null && prst == null
                ? PptxShapeKind.other
                : PptxShapeKind.text,
            x: x,
            y: y,
            w: w,
            h: h,
            node: node,
            paras: paras,
            fill: fill,
            line: line,
            lineWidth: lineW,
            geom: txBox || (phType != null && prst == null)
                ? null
                : (prst ?? (phType == null ? 'rect' : null)),
            label: isTitle
                ? 'Title'
                : (phType != null
                      ? 'Placeholder'
                      : (name == 'cxnSp'
                            ? 'Line'
                            : (txBox ? 'Text Box' : _geomName(prst)))),
            defaultSizePt: levelSizes.first,
            levelSizes: levelSizes,
            anchor: anchor,
            rotation: rot,
            placeholder: phType,
            fontColor: fontColor,
            fontScale: fontScale,
            flipH: xfrm?.getAttribute('flipH') == '1',
            flipV: xfrm?.getAttribute('flipV') == '1',
            arrowEnd:
                ln
                        ?.getElement('tailEnd', namespaceUri: _a)
                        ?.getAttribute('type') !=
                    null &&
                ln
                        ?.getElement('tailEnd', namespaceUri: _a)
                        ?.getAttribute('type') !=
                    'none',
            defaultAlign: defaultAlign,
            titleFont: isTitle,
          ),
        );
      }
    }

    final tree = doc.findAllElements('spTree', namespaceUri: _p).firstOrNull;
    if (tree != null) walk(tree, [0, 0, 1, 1, 0, 0]);

    String? bgOf(XmlDocument? d) {
      final bg = d?.findAllElements('bg', namespaceUri: _p).firstOrNull;
      if (bg == null) return null;
      final bgPr = bg.getElement('bgPr', namespaceUri: _p);
      if (bgPr != null) return _readFill(bgPr);
      return _readColor(bg.getElement('bgRef', namespaceUri: _p));
    }

    final own = bgOf(doc);
    final slide =
        PptxSlide(
            path: path,
            xml: doc,
            shapes: shapes,
            background: own ?? bgOf(layout) ?? bgOf(master) ?? '@bg1',
          )
          ..ownBackground = own != null
          ..layoutPath = layoutPath
          ..hidden = doc.rootElement.getAttribute('show') == '0'
          ..notesPath = notesPath;

    // Transition (also inside mc:AlternateContent written by PowerPoint 2010+).
    final tr =
        doc.findAllElements('transition', namespaceUri: _p).firstOrNull ??
        doc.rootElement.descendantElements
            .where((e) => e.name.local == 'transition')
            .firstOrNull;
    if (tr != null) {
      final kind = tr.childElements.firstOrNull;
      slide
        ..transition = kind?.name.local
        ..transitionDir = kind?.getAttribute('dir')
        ..transitionSpeed = tr.getAttribute('spd') ?? 'med'
        ..advanceAfterMs = int.tryParse(tr.getAttribute('advTm') ?? '');
    }
    slide.animations = readPptxAnimations(doc, shapes);
    if (notesPath != null && files.containsKey(notesPath)) {
      final n = _xml(notesPath);
      for (final sp in n.findAllElements('sp', namespaceUri: _p)) {
        if (sp
                .findAllElements('ph', namespaceUri: _p)
                .firstOrNull
                ?.getAttribute('type') !=
            'body')
          continue;
        slide.notes = sp
            .findAllElements('p', namespaceUri: _a)
            .map(
              (pp) => pp
                  .findAllElements('t', namespaceUri: _a)
                  .map((t) => t.innerText)
                  .join(),
            )
            .join('\n')
            .trimRight();
      }
    }
    return slide;
  }

  static String _geomName(String? prst) => switch (prst) {
    null || 'rect' => 'Rectangle',
    'ellipse' => 'Oval',
    'roundRect' => 'Rounded Rectangle',
    'triangle' => 'Triangle',
    'line' || 'straightConnector1' => 'Line',
    'rightArrow' => 'Arrow',
    'star5' => 'Star',
    'diamond' => 'Diamond',
    'hexagon' => 'Hexagon',
    _ => 'Shape',
  };

  static (double, double)? _pt(XmlElement xfrm, String tag) {
    final e = xfrm.getElement(tag, namespaceUri: _a);
    if (e == null) return null;
    final ext = tag == 'ext' || tag == 'chExt';
    final a = double.tryParse(e.getAttribute(ext ? 'cx' : 'x') ?? '');
    final b = double.tryParse(e.getAttribute(ext ? 'cy' : 'y') ?? '');
    return a == null || b == null ? null : (a, b);
  }

  // -------------------------------------------------------------- editing

  /// Adds a text box to [slide] and returns it.
  PptxShape addTextBox(
    PptxSlide slide, {
    String text = '',
    double sizePt = 18,
    String? color,
    bool bold = false,
    String? font,
  }) {
    final s =
        PptxShape(
            kind: PptxShapeKind.text,
            x: width * 0.25,
            y: height * 0.4,
            w: width * 0.5,
            h: height * 0.12,
            paras: [
              PptxPara([
                PptxRun(
                  text,
                  sizePt: sizePt,
                  color: color,
                  bold: bold,
                  font: font,
                ),
              ]),
            ],
            label: 'Text Box',
            defaultSizePt: sizePt,
            levelSizes: [sizePt],
          )
          ..isNew = true
          ..dirtyText = true;
    slide.shapes.add(s);
    return s;
  }

  /// Adds a drawn shape (`rect`, `ellipse`, `line`, `rightArrow`…).
  PptxShape addShape(PptxSlide slide, String geom) {
    final line = geom == 'line' || geom == 'arrow';
    final side = height * 0.3;
    final s = PptxShape(
      kind: PptxShapeKind.text,
      x: (width - (line ? side * 1.6 : side * 1.3)) / 2,
      y: (height - (line ? 0 : side)) / 2,
      w: line ? side * 1.6 : side * 1.3,
      h: line ? 0 : side,
      paras: line ? const [] : [PptxPara([], align: 'ctr')],
      geom: line ? 'line' : geom,
      fill: line ? 'none' : '@accent1',
      line: line ? '@accent1' : '@accent1/50000/0',
      lineWidth: line ? 28575 : 12700,
      arrowEnd: geom == 'arrow',
      label: line ? 'Line' : _geomName(geom),
      anchor: 'ctr',
      fontColor: '@lt1',
      defaultSizePt: 18,
      levelSizes: const [18],
    )..isNew = true;
    slide.shapes.add(s);
    return s;
  }

  /// Adds a [rows] × [cols] table.
  PptxShape addTable(PptxSlide slide, int rows, int cols) {
    final w = width * 0.8, h = math.min(height * 0.7, rows * 370840.0);
    final s = PptxShape(
      kind: PptxShapeKind.table,
      x: (width - w) / 2,
      y: (height - h) / 2,
      w: w,
      h: h,
      cells: List.generate(rows, (_) => List.filled(cols, '')),
      label: 'Table',
    )..isNew = true;
    slide.shapes.add(s);
    return s;
  }

  /// Adds a picture ([bytes], extension [ext]) to [slide].
  PptxShape addPicture(
    PptxSlide slide,
    Uint8List bytes,
    String ext,
    double aspect,
  ) {
    var n = 1;
    while (files.containsKey('ppt/media/ds_image$n.$ext')) {
      n++;
    }
    final path = 'ppt/media/ds_image$n.$ext';
    files[path] = bytes;
    final w = width * 0.4;
    final h = (w / aspect).clamp(height * 0.05, height * 0.9);
    final s = PptxShape(
      kind: PptxShapeKind.picture,
      x: (width - w) / 2,
      y: (height - h) / 2,
      w: w,
      h: h.toDouble(),
      media: path,
      label: 'Picture',
    )..isNew = true;
    slide.shapes.add(s);
    return s;
  }

  void removeShape(PptxSlide slide, PptxShape s) {
    slide.shapes.remove(s);
    if (s.node != null) slide.removed.add(s.node!);
  }

  /// Bring to front / send to back / one step forward or backward.
  void reorder(PptxSlide slide, PptxShape s, String how) {
    final list = slide.shapes;
    final i = list.indexOf(s);
    if (i < 0) return;
    list.removeAt(i);
    final j = switch (how) {
      'front' => list.length,
      'back' => 0,
      'forward' => math.min(i + 1, list.length),
      _ => math.max(i - 1, 0),
    };
    list.insert(j, s);
    slide.orderDirty = true;
  }

  /// A copy of [slide] placed after it (or an empty slide with its layout).
  PptxSlide duplicateSlide(PptxSlide slide, {bool empty = false}) {
    if (empty && slide.layoutPath != null) {
      final l = layouts.where((e) => e.path == slide.layoutPath).firstOrNull;
      // A title slide is followed by "Title and Content", as in PowerPoint.
      final next = l?.type == 'title'
          ? layouts.where((e) => e.type == 'obj').firstOrNull ?? l
          : l;
      if (next != null) return addSlide(next, after: slide);
    }
    final path = _newSlidePath();
    final xml = XmlDocument.parse(_slideXml(slide));
    _ensurePictureRels(slide);
    files[path] = Uint8List.fromList(utf8.encode(xml.toXmlString()));
    final relData = files[_relPath(slide.path)];
    if (relData != null) {
      // The copy shares layout and pictures, not the speaker notes.
      final rels = XmlDocument.parse(utf8.decode(relData));
      for (final r in rels.rootElement.childElements.toList()) {
        if ((r.getAttribute('Type') ?? '').endsWith('/notesSlide')) r.remove();
      }
      files[_relPath(path)] = Uint8List.fromList(
        utf8.encode(rels.toXmlString()),
      );
    }
    final copy = _readSlide(path, xml)
      ..notes = slide.notes
      ..notesDirty = slide.notes.isNotEmpty;
    slides.insert(slides.indexOf(slide) + 1, copy);
    return copy;
  }

  String _newSlidePath() {
    var n = 1;
    while (files.containsKey('ppt/slides/slide$n.xml') ||
        slides.any((s) => s.path == 'ppt/slides/slide$n.xml')) {
      n++;
    }
    return 'ppt/slides/slide$n.xml';
  }

  /// New slide with [layout]'s placeholders, after [after] (or at the end).
  PptxSlide addSlide(PptxLayout layout, {PptxSlide? after}) {
    final path = _newSlidePath();
    final l = _ro(layout.path);
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr>'
      '<p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>',
    );
    var id = 2;
    for (final sp in l.findAllElements('sp', namespaceUri: _p)) {
      final ph = sp.findAllElements('ph', namespaceUri: _p).firstOrNull;
      if (ph == null) continue;
      final type = ph.getAttribute('type');
      if (const {
        'dt',
        'ftr',
        'sldNum',
        'pic',
        'chart',
        'tbl',
        'dgm',
        'media',
        'clipArt',
      }.contains(type))
        continue;
      final idx = ph.getAttribute('idx');
      final name =
          sp
              .findAllElements('cNvPr', namespaceUri: _p)
              .firstOrNull
              ?.getAttribute('name') ??
          'Placeholder $id';
      b.write(
        '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="${_esc(name)}"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr>'
        '<p:nvPr><p:ph${type == null ? '' : ' type="$type"'}${idx == null ? '' : ' idx="$idx"'}/></p:nvPr></p:nvSpPr>'
        '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>',
      );
      id++;
    }
    b.write(
      '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>',
    );
    files[path] = Uint8List.fromList(utf8.encode(b.toString()));
    files[_relPath(path)] = Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="$_relNs">'
        '<Relationship Id="rId1" Type="$_rel/slideLayout" Target="${p.posix.relative(layout.path, from: 'ppt/slides')}"/></Relationships>',
      ),
    );
    final s = _readSlide(path, _xml(path));
    final at = after == null ? slides.length : slides.indexOf(after) + 1;
    slides.insert(at, s);
    return s;
  }

  /// Gives [slide] the placeholders of [layout] (text kept where it fits).
  PptxSlide changeLayout(PptxSlide slide, PptxLayout layout) {
    final fresh = addSlide(layout, after: slide);
    final texts = slide.shapes
        .where((s) => s.placeholder != null && s.plainText.trim().isNotEmpty)
        .toList();
    final others = slide.shapes.where((s) => s.placeholder == null).toList();
    for (final ph in fresh.shapes) {
      final src = texts.where((t) => t.isTitle == ph.isTitle).firstOrNull;
      if (src == null) continue;
      texts.remove(src);
      ph
        ..paras = src.paras
        ..dirtyText = true;
    }
    // Pictures, drawn shapes and text boxes move over as they are.
    final tree = fresh.xml.findAllElements('spTree', namespaceUri: _p).first;
    _slideXml(slide);
    _ensurePictureRels(slide);
    final srcRels = _rels(files, slide.path);
    for (final o in others) {
      final node = o.node;
      if (node == null) continue;
      final copy = node.copy();
      final blip = copy.findAllElements('blip', namespaceUri: _a).firstOrNull;
      final rid = blip?.getAttribute('embed', namespaceUri: _r);
      if (blip != null && rid != null && srcRels[rid] != null) {
        final media = _resolve(slide.path, srcRels[rid]!);
        final rels = _pictureRels.putIfAbsent(fresh.path, () => {});
        final nid = rels.putIfAbsent(
          media,
          () => _pictureRid(fresh.path, rels),
        );
        blip.setAttribute('r:embed', nid);
      }
      tree.children.add(copy);
    }
    fresh.notes = slide.notes;
    fresh.notesDirty = slide.notes.isNotEmpty;
    fresh.transition = slide.transition;
    fresh.dirtyTransition = slide.transition != null;
    final i = slides.indexOf(slide);
    slides.remove(fresh);
    files[fresh.path] = Uint8List.fromList(utf8.encode(_slideXml(fresh)));
    _ensurePictureRels(fresh);
    final reread = _readSlide(fresh.path, fresh.xml)
      ..notes = fresh.notes
      ..notesDirty = fresh.notesDirty
      ..transition = fresh.transition
      ..dirtyTransition = fresh.dirtyTransition;
    slides[i] = reread;
    return reread;
  }

  void deleteSlide(PptxSlide slide) {
    slides.remove(slide);
  }

  void moveSlide(int from, int to) {
    final s = slides.removeAt(from);
    slides.insert(to.clamp(0, slides.length), s);
  }

  // ------------------------------------------------------ clipboard

  /// A shape as XML for copy/paste (pictures carry their media path).
  (XmlElement, String?)? copyShape(PptxSlide slide, PptxShape s) {
    if (s.locked) return null;
    _slideXml(slide);
    _ensurePictureRels(slide);
    final node = s.node;
    if (node == null) return null;
    final c = node.copy();
    // A placeholder takes its place and text size from the layout: give the
    // copy its own, since it is pasted as an ordinary object.
    if (s.placeholder != null) {
      _setXfrm(c, s);
      for (final para in c.findAllElements('p', namespaceUri: _a)) {
        final lvl =
            int.tryParse(
              para.getElement('pPr', namespaceUri: _a)?.getAttribute('lvl') ??
                  '',
            ) ??
            0;
        for (final rPr in [
          ...para.findAllElements('rPr', namespaceUri: _a),
          ...para.findAllElements('endParaRPr', namespaceUri: _a),
        ]) {
          if (rPr.getAttribute('sz') == null)
            rPr.setAttribute('sz', '${(s.sizeForLevel(lvl) * 100).round()}');
        }
      }
      final bodyPr = c.findAllElements('bodyPr', namespaceUri: _a).firstOrNull;
      bodyPr?.setAttribute('anchor', s.anchor);
    }
    return (c, s.media);
  }

  /// Pastes a copied shape on [slide], offset when it lands on its source.
  PptxShape? pasteShape(
    PptxSlide slide,
    (XmlElement, String?) clip, {
    bool offset = true,
  }) {
    final el = clip.$1.copy();
    final xfrm = el.findAllElements('xfrm', namespaceUri: _a).firstOrNull;
    final off = xfrm?.getElement('off', namespaceUri: _a);
    if (off != null && offset) {
      final d = (width * 0.02).round();
      off.setAttribute(
        'x',
        '${(int.tryParse(off.getAttribute('x') ?? '') ?? 0) + d}',
      );
      off.setAttribute(
        'y',
        '${(int.tryParse(off.getAttribute('y') ?? '') ?? 0) + d}',
      );
    }
    final media = clip.$2;
    final blip = el.findAllElements('blip', namespaceUri: _a).firstOrNull;
    if (blip != null && media != null) {
      final rels = _pictureRels.putIfAbsent(slide.path, () => {});
      blip.setAttribute(
        'r:embed',
        rels.putIfAbsent(media, () => _pictureRid(slide.path, rels)),
      );
    }
    final cNvPr = el.findAllElements('cNvPr', namespaceUri: _p).firstOrNull;
    cNvPr?.setAttribute('id', '${_nextId(slide)}');
    // A pasted placeholder becomes an ordinary text box.
    for (final ph in el.findAllElements('ph', namespaceUri: _p).toList()) {
      ph.remove();
    }
    _slideXml(slide);
    slide.xml
        .findAllElements('spTree', namespaceUri: _p)
        .first
        .children
        .add(el);
    _ensurePictureRels(slide);
    final fresh = _reloadSlide(slide);
    return fresh.shapes.lastOrNull;
  }

  int _nextId(PptxSlide slide) {
    var m = 1;
    for (final c in slide.xml.findAllElements('cNvPr', namespaceUri: _p)) {
      m = math.max(m, int.tryParse(c.getAttribute('id') ?? '') ?? 0);
    }
    return m + 1;
  }

  /// Writes [slide] and reads it back (fresh shape objects).
  PptxSlide _reloadSlide(PptxSlide slide) {
    final xml = _slideXml(slide);
    files[slide.path] = Uint8List.fromList(utf8.encode(xml));
    final fresh = _readSlide(slide.path, XmlDocument.parse(xml))
      ..sldId = slide.sldId
      ..notes = slide.notes
      ..notesDirty = slide.notesDirty
      ..dirtyTransition = slide.dirtyTransition;
    final i = slides.indexOf(slide);
    if (i >= 0) slides[i] = fresh;
    return fresh;
  }

  // ------------------------------------------------------ deck-wide

  /// New slide size; every slide, layout and master is scaled to fit.
  void setSlideSize(double w, double h) {
    if ((w - width).abs() < 1 && (h - height).abs() < 1) return;
    final sx = w / width, sy = h / height;
    for (final s in slides) {
      files[s.path] = Uint8List.fromList(utf8.encode(_slideXml(s)));
      _ensurePictureRels(s);
    }
    for (final path in files.keys.toList()) {
      if (!RegExp(r'^ppt/(slides|slideLayouts|slideMasters)/[^/]+\.xml$')
          .hasMatch(path))
        continue;
      final d = _xml(path);
      for (final e in d.descendantElements) {
        if (e.namespaceUri != _a) continue;
        final n = e.name.local;
        if (n == 'off' || n == 'chOff') {
          for (final (at, k) in [('x', sx), ('y', sy)]) {
            final v = double.tryParse(e.getAttribute(at) ?? '');
            if (v != null) e.setAttribute(at, '${(v * k).round()}');
          }
        } else if (n == 'ext' || n == 'chExt') {
          for (final (at, k) in [('cx', sx), ('cy', sy)]) {
            final v = double.tryParse(e.getAttribute(at) ?? '');
            if (v != null && e.parentElement?.name.local != 'extLst')
              e.setAttribute(at, '${(v * k).round()}');
          }
        }
      }
      files[path] = Uint8List.fromList(utf8.encode(d.toXmlString()));
    }
    final pres = _xml('ppt/presentation.xml');
    final sz = pres.findAllElements('sldSz', namespaceUri: _p).firstOrNull;
    sz?.setAttribute('cx', '${w.round()}');
    sz?.setAttribute('cy', '${h.round()}');
    sz?.removeAttribute('type');
    files['ppt/presentation.xml'] = Uint8List.fromList(
      utf8.encode(pres.toXmlString()),
    );
    final keep = {for (final s in slides) s.path: (s.notes, s.notesDirty)};
    _load(order: [for (final s in slides) s.path]);
    for (final s in slides) {
      final k = keep[s.path];
      if (k != null) {
        s.notes = k.$1;
        s.notesDirty = k.$2;
      }
    }
  }

  /// Applies a design: theme colours and fonts for the whole deck.
  void applyTheme(PptxTheme t) {
    theme = t.copy();
    dirtyTheme = true;
  }

  /// Replaces [find] in every slide's text; returns the count.
  int replaceAll(String find, String replace, {bool matchCase = false}) {
    if (find.isEmpty) return 0;
    var n = 0;
    final re = RegExp(RegExp.escape(find), caseSensitive: matchCase);
    for (final s in slides) {
      for (final sh in s.shapes) {
        if (sh.locked) continue;
        var changed = false;
        for (final para in sh.paras) {
          for (final r in para.runs) {
            final c = re.allMatches(r.text).length;
            if (c > 0) {
              r.text = r.text.replaceAll(re, replace);
              n += c;
              changed = true;
            }
          }
        }
        if (changed) sh.dirtyText = true;
      }
    }
    return n;
  }

  // ------------------------------------------------------------- undo

  PptxSnapshot snapshot({PptxSlide? only}) {
    final targets = only == null ? slides : [only];
    final xml = {for (final s in targets) s.path: _slideXml(s)};
    for (final s in targets) {
      _ensurePictureRels(s);
    }
    return PptxSnapshot._(
      xml,
      [for (final s in slides) s.path],
      only == null ? Map.of(files) : null,
      width,
      height,
    );
  }

  void restore(PptxSnapshot snap) {
    final notes = {for (final s in slides) s.path: (s.notes, s.notesDirty)};
    final ids = {for (final s in slides) s.path: s.sldId};
    if (snap.parts != null) {
      files
        ..clear()
        ..addAll(snap.parts!);
    }
    snap.slides.forEach(
      (path, xml) => files[path] = Uint8List.fromList(utf8.encode(xml)),
    );
    if (snap.parts != null) {
      _load(order: snap.order);
    } else {
      slides.removeWhere((s) => !snap.order.contains(s.path));
      for (final path in snap.slides.keys) {
        final i = slides.indexWhere((s) => s.path == path);
        final fresh = _readSlide(path, _xml(path));
        if (i >= 0) {
          slides[i] = fresh;
        } else {
          slides.add(fresh);
        }
      }
      slides.sort(
        (a, b) =>
            snap.order.indexOf(a.path).compareTo(snap.order.indexOf(b.path)),
      );
    }
    width = snap.width;
    height = snap.height;
    for (final s in slides) {
      final n = notes[s.path];
      if (n != null) {
        s.notes = n.$1;
        s.notesDirty = n.$2;
      }
      s.sldId ??= ids[s.path];
    }
  }

  // --------------------------------------------------------------- saving

  /// Applies every edit to the package and returns the new .pptx bytes.
  Uint8List save() {
    for (final s in slides) {
      files[s.path] = Uint8List.fromList(utf8.encode(_slideXml(s)));
      _ensurePictureRels(s);
      if (s.notesDirty) _writeNotes(s);
    }
    if (dirtyTheme) _writeTheme();
    _writePresentationOrder();
    final out = Archive();
    for (final e in files.entries) {
      out.addFile(ArchiveFile(e.key, e.value.length, e.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(out));
  }

  String _slideXml(PptxSlide s) {
    final doc = s.xml;
    for (final r in s.removed) {
      if (r.parent != null) r.remove();
    }
    s.removed.clear();
    final tree = doc.findAllElements('spTree', namespaceUri: _p).first;
    for (final shape in s.shapes) {
      if (shape.isNew) {
        final id = _nextId(s);
        final el = switch (shape.kind) {
          PptxShapeKind.picture => _newPicture(s, shape, id),
          PptxShapeKind.table => _newTable(shape, id),
          _ => _newShape(shape, id),
        };
        tree.children.add(el);
        shape
          ..node = el
          ..isNew = false
          ..dirtyGeometry = false
          ..dirtyText = false
          ..dirtyStyle = false;
        continue;
      }
      final node = shape.node;
      if (node == null) continue;
      if (shape.dirtyGeometry) {
        _setXfrm(node, shape);
        shape.dirtyGeometry = false;
      }
      if (shape.dirtyStyle) {
        _setStyle(node, shape);
        shape.dirtyStyle = false;
      }
      if (shape.dirtyText) {
        if (shape.kind == PptxShapeKind.table) {
          _setTable(node, shape);
        } else {
          _setText(node, shape);
        }
        shape.dirtyText = false;
      }
    }
    if (s.orderDirty) {
      final nodes = [for (final sh in s.shapes) ?sh.node];
      final slots = <int>[];
      for (var i = 0; i < tree.children.length; i++) {
        if (nodes.contains(tree.children[i])) slots.add(i);
      }
      final ordered = nodes.where((n) => n.parent == tree).toList();
      for (final n in ordered) {
        n.remove();
      }
      for (var k = 0; k < slots.length && k < ordered.length; k++) {
        tree.children.insert(slots[k], ordered[k]);
      }
      s.orderDirty = false;
    }
    if (s.dirtyBackground) {
      final cSld = doc.findAllElements('cSld', namespaceUri: _p).first;
      for (final bg in cSld.findElements('bg', namespaceUri: _p).toList()) {
        bg.remove();
      }
      if (s.ownBackground && s.background != null) {
        cSld.children.insert(
          0,
          _el(
            '<p:bg><p:bgPr><a:solidFill>${_colorXml(s.background!)}</a:solidFill><a:effectLst/></p:bgPr></p:bg>',
          ),
        );
      }
      s.dirtyBackground = false;
    }
    if (s.dirtyTransition) {
      final root = doc.rootElement;
      for (final c in root.childElements.toList()) {
        if (c.name.local == 'transition' ||
            (c.name.local == 'AlternateContent' &&
                c.descendantElements.any(
                  (e) => e.name.local == 'transition',
                ))) {
          c.remove();
        }
      }
      final t = s.transition;
      if (t != null || s.advanceAfterMs != null) {
        final attrs = StringBuffer(' spd="${s.transitionSpeed}"');
        if (s.advanceAfterMs != null)
          attrs.write(' advTm="${s.advanceAfterMs}"');
        final dir =
            s.transitionDir == null ||
                !const {'push', 'wipe', 'cover', 'pull'}.contains(t)
            ? ''
            : ' dir="${s.transitionDir}"';
        final el = _el(
          '<p:transition$attrs>${t == null || t == 'none' ? '' : '<p:$t$dir/>'}</p:transition>',
        );
        final after =
            root.childElements
                .where((c) => c.name.local == 'clrMapOvr')
                .firstOrNull ??
            root.childElements.where((c) => c.name.local == 'cSld').first;
        root.children.insert(root.children.indexOf(after) + 1, el);
      }
      s.dirtyTransition = false;
    }
    if (s.dirtyAnimations ||
        s.animations.any((a) => !s.shapes.contains(a.shape))) {
      s.animations.removeWhere((a) => !s.shapes.contains(a.shape));
      final root = doc.rootElement;
      for (final c in root.childElements.toList()) {
        if (c.name.local == 'timing') c.remove();
      }
      String idOf(PptxShape sh) =>
          sh.node
              ?.findAllElements('cNvPr', namespaceUri: _p)
              .firstOrNull
              ?.getAttribute('id') ??
          '0';
      final xml = pptxTimingXml(s.animations, idOf);
      if (xml != null) {
        // After cSld / clrMapOvr / transition, before extLst.
        final before = root.childElements
            .where((c) => c.name.local == 'extLst')
            .firstOrNull;
        final el = _el(xml);
        if (before == null) {
          root.children.add(el);
        } else {
          root.children.insert(root.children.indexOf(before), el);
        }
      }
      s.dirtyAnimations = false;
    }
    if (s.dirtyHidden) {
      final root = doc.rootElement;
      root.removeAttribute('show');
      if (s.hidden) root.setAttribute('show', '0');
      s.dirtyHidden = false;
    }
    return doc.toXmlString();
  }

  void _setXfrm(XmlElement node, PptxShape s) {
    final props =
        node.getElement('spPr', namespaceUri: _p) ??
        node.getElement('grpSpPr', namespaceUri: _p);
    XmlElement? xfrm =
        props?.getElement('xfrm', namespaceUri: _a) ??
        node.getElement('xfrm', namespaceUri: _p);
    if (xfrm == null) {
      // Placeholder that inherited its place: give it its own.
      xfrm = _el('<a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></a:xfrm>');
      props?.children.insert(0, xfrm);
    }
    final off = xfrm.getElement('off', namespaceUri: _a);
    final ext = xfrm.getElement('ext', namespaceUri: _a);
    off?.setAttribute('x', '${s.x.round()}');
    off?.setAttribute('y', '${s.y.round()}');
    ext?.setAttribute('cx', '${s.w.round()}');
    ext?.setAttribute('cy', '${s.h.round()}');
    xfrm.removeAttribute('rot');
    final rot = (s.rotation % 360 + 360) % 360;
    if (rot.abs() > 0.01) xfrm.setAttribute('rot', '${(rot * 60000).round()}');
  }

  void _setStyle(XmlElement node, PptxShape s) {
    final spPr = node.getElement('spPr', namespaceUri: _p);
    if (spPr == null) return;
    const fills = {
      'noFill',
      'solidFill',
      'gradFill',
      'pattFill',
      'blipFill',
      'grpFill',
    };
    if (node.name.local != 'pic' && node.name.local != 'cxnSp') {
      for (final c in spPr.childElements.toList()) {
        if (fills.contains(c.name.local)) c.remove();
      }
      final fill = s.fill;
      if (fill != null) {
        final el = _el(
          fill == 'none'
              ? '<a:noFill/>'
              : '<a:solidFill>${_colorXml(fill)}</a:solidFill>',
        );
        final geo =
            spPr.childElements
                .where(
                  (c) =>
                      c.name.local == 'prstGeom' || c.name.local == 'custGeom',
                )
                .firstOrNull ??
            spPr.childElements.where((c) => c.name.local == 'xfrm').firstOrNull;
        spPr.children.insert(
          geo == null ? 0 : spPr.children.indexOf(geo) + 1,
          el,
        );
      }
    }
    if (s.line != null || s.lineWidth != null) {
      var ln = spPr.getElement('ln', namespaceUri: _a);
      if (ln == null) {
        ln = _el('<a:ln/>');
        final fill =
            spPr.childElements
                .where((c) => fills.contains(c.name.local))
                .lastOrNull ??
            spPr.childElements
                .where(
                  (c) =>
                      c.name.local == 'prstGeom' || c.name.local == 'custGeom',
                )
                .firstOrNull;
        spPr.children.insert(
          fill == null ? spPr.children.length : spPr.children.indexOf(fill) + 1,
          ln,
        );
      }
      if (s.lineWidth != null) ln.setAttribute('w', '${s.lineWidth!.round()}');
      for (final c in ln.childElements.toList()) {
        if (fills.contains(c.name.local)) c.remove();
      }
      if (s.line != null) {
        ln.children.insert(
          0,
          _el(
            s.line == 'none'
                ? '<a:noFill/>'
                : '<a:solidFill>${_colorXml(s.line!)}</a:solidFill>',
          ),
        );
      }
    }
  }

  static String _runXml(PptxRun r) {
    final rPr = r.rPr?.copy() ?? _el('<a:rPr lang="en-US" dirty="0"/>');
    void set(String name, String? v) {
      rPr.removeAttribute(name);
      if (v != null) rPr.setAttribute(name, v);
    }

    set('sz', r.sizePt == null ? null : '${(r.sizePt! * 100).round()}');
    set('b', r.bold ? '1' : (rPr.getAttribute('b') == null ? null : '0'));
    set('i', r.italic ? '1' : (rPr.getAttribute('i') == null ? null : '0'));
    set('u', r.underline ? 'sng' : null);
    set('strike', r.strike ? 'sngStrike' : null);
    for (final c in rPr.childElements.toList()) {
      if (c.name.local == 'solidFill' ||
          c.name.local == 'latin' ||
          c.name.local == 'noFill' ||
          c.name.local == 'gradFill')
        c.remove();
    }
    // Schema order: ln, fill, effects…, latin, ea, cs, sym, hlinkClick.
    var at = rPr.childElements.where((c) => c.name.local == 'ln').isEmpty
        ? 0
        : 1;
    if (r.color != null) {
      rPr.children.insert(
        at++,
        _el('<a:solidFill>${_colorXml(r.color!)}</a:solidFill>'),
      );
    }
    if (r.font != null) {
      final before = rPr.childElements
          .where(
            (c) => const {
              'ea',
              'cs',
              'sym',
              'hlinkClick',
              'hlinkMouseOver',
              'rtl',
              'extLst',
            }.contains(c.name.local),
          )
          .firstOrNull;
      final el = _el('<a:latin typeface="${_esc(r.font!)}"/>');
      if (before == null) {
        rPr.children.add(el);
      } else {
        rPr.children.insert(rPr.children.indexOf(before), el);
      }
    }
    final x = rPr.toXmlString().replaceAll(RegExp(r'\s+xmlns:\w+="[^"]*"'), '');
    return '<a:r>$x<a:t>${_esc(r.text)}</a:t></a:r>';
  }

  static String _paraXml(PptxPara para) {
    final pPr = para.pPr?.copy() ?? _el('<a:pPr/>');
    void set(String name, String? v) {
      pPr.removeAttribute(name);
      if (v != null) pPr.setAttribute(name, v);
    }

    set('lvl', para.level > 0 ? '${para.level}' : null);
    set('algn', para.align);
    const bu = {
      'buNone',
      'buChar',
      'buAutoNum',
      'buFont',
      'buBlip',
      'buSzPct',
      'buClr',
    };
    final hadOwn = pPr.childElements.any((c) => bu.contains(c.name.local));
    final explicit =
        para.numbered || para.bullet != para.inheritedBullet || hadOwn;
    if (explicit) {
      for (final c in pPr.childElements.toList()) {
        if (bu.contains(c.name.local)) c.remove();
      }
      final el = para.numbered
          ? _frag(
              '<a:buFont typeface="+mj-lt"/><a:buAutoNum type="arabicPeriod"/>',
            )
          : para.bullet
          ? _frag('<a:buFont typeface="Arial"/><a:buChar char="•"/>')
          : _frag('<a:buNone/>');
      if ((para.bullet || para.numbered) && !para.inheritedBullet) {
        set('marL', '${342900 + para.level * 457200}');
        set('indent', '-342900');
      } else if (!para.bullet &&
          !para.numbered &&
          !para.inheritedBullet &&
          pPr.getAttribute('indent') == '-342900') {
        set('marL', null);
        set('indent', null);
      }
      // After lnSpc/spcBef/spcAft, before tabLst/defRPr.
      final before = pPr.childElements
          .where(
            (c) =>
                c.name.local == 'tabLst' ||
                c.name.local == 'defRPr' ||
                c.name.local == 'extLst',
          )
          .firstOrNull;
      var at = before == null
          ? pPr.children.length
          : pPr.children.indexOf(before);
      for (final e in el) {
        pPr.children.insert(at++, e);
      }
    }
    for (final c in pPr.childElements.toList()) {
      if (c.name.local == 'lnSpc') c.remove();
    }
    if (para.lineSpacing != null) {
      pPr.children.insert(
        0,
        _el(
          '<a:lnSpc><a:spcPct val="${(para.lineSpacing! * 100000).round()}"/></a:lnSpc>',
        ),
      );
    }
    final pXml = pPr.attributes.isEmpty && pPr.children.isEmpty
        ? ''
        : pPr.toXmlString().replaceAll(RegExp(r'\s+xmlns:\w+="[^"]*"'), '');
    final b = StringBuffer('<a:p>$pXml');
    for (final r in para.runs) {
      if (r.text == '\v') {
        b.write('<a:br/>');
      } else if (r.text.isNotEmpty) {
        b.write(_runXml(r));
      }
    }
    final last = para.runs.lastOrNull;
    final end = last?.sizePt == null
        ? ''
        : ' sz="${(last!.sizePt! * 100).round()}"';
    b.write('<a:endParaRPr lang="en-US"$end dirty="0"/></a:p>');
    return b.toString();
  }

  static String _parasXml(PptxShape s) {
    if (s.paras.isEmpty) return '<a:p><a:endParaRPr lang="en-US"/></a:p>';
    return s.paras.map(_paraXml).join();
  }

  void _setText(XmlElement node, PptxShape s) {
    var txBody = node.getElement('txBody', namespaceUri: _p);
    if (txBody == null) {
      if (node.name.local != 'sp') return;
      txBody = _el(
        '<p:txBody><a:bodyPr rtlCol="0" anchor="ctr"/><a:lstStyle/></p:txBody>',
      );
      node.children.add(txBody);
    }
    for (final p0 in txBody.findElements('p', namespaceUri: _a).toList()) {
      p0.remove();
    }
    final bodyPr = txBody.getElement('bodyPr', namespaceUri: _a);
    bodyPr?.setAttribute('anchor', s.anchor);
    for (final c in _frag(_parasXml(s))) {
      txBody.children.add(c);
    }
  }

  void _setTable(XmlElement node, PptxShape s) {
    final tbl = node.findAllElements('tbl', namespaceUri: _a).firstOrNull;
    final cells = s.cells;
    if (tbl == null || cells == null || cells.isEmpty) return;
    final cols = cells.fold<int>(1, (m, r) => math.max(m, r.length));
    final rows = tbl.findElements('tr', namespaceUri: _a).toList();
    while (rows.length < cells.length) {
      final c = rows.last.copy();
      tbl.children.insert(tbl.children.indexOf(rows.last) + 1, c);
      rows.add(c);
    }
    while (rows.length > cells.length && rows.length > 1) {
      rows.removeLast().remove();
    }
    final grid = tbl.getElement('tblGrid', namespaceUri: _a);
    if (grid != null) {
      final gc = grid.findElements('gridCol', namespaceUri: _a).toList();
      while (gc.length < cols) {
        final c = gc.last.copy();
        grid.children.add(c);
        gc.add(c);
      }
      while (gc.length > cols && gc.length > 1) {
        gc.removeLast().remove();
      }
      final w = (s.w / cols).round();
      for (final g in gc) {
        g.setAttribute('w', '$w');
      }
    }
    for (var r = 0; r < rows.length; r++) {
      final tcs = rows[r].findElements('tc', namespaceUri: _a).toList();
      while (tcs.length < cols) {
        final c = tcs.last.copy();
        rows[r].children.insert(rows[r].children.indexOf(tcs.last) + 1, c);
        tcs.add(c);
      }
      while (tcs.length > cols && tcs.length > 1) {
        tcs.removeLast().remove();
      }
      for (var c = 0; c < tcs.length; c++) {
        final text = c < cells[r].length ? cells[r][c] : '';
        final body = tcs[c].getElement('txBody', namespaceUri: _a);
        if (body == null) continue;
        final first = body.findElements('p', namespaceUri: _a).firstOrNull;
        final rPr = first
            ?.findAllElements('rPr', namespaceUri: _a)
            .firstOrNull
            ?.copy();
        final pPr = first?.getElement('pPr', namespaceUri: _a)?.copy();
        for (final pp in body.findElements('p', namespaceUri: _a).toList()) {
          pp.remove();
        }
        for (final line in text.split('\n')) {
          final rp =
              rPr?.toXmlString().replaceAll(
                RegExp(r'\s+xmlns:\w+="[^"]*"'),
                '',
              ) ??
              '<a:rPr lang="en-US" dirty="0"/>';
          final pp =
              pPr?.toXmlString().replaceAll(
                RegExp(r'\s+xmlns:\w+="[^"]*"'),
                '',
              ) ??
              '';
          body.children.add(
            _el(
              '<a:p>$pp${line.isEmpty ? '' : '<a:r>$rp<a:t>${_esc(line)}</a:t></a:r>'}<a:endParaRPr lang="en-US" dirty="0"/></a:p>',
            ),
          );
        }
      }
    }
    // Row heights follow the frame.
    final rh = (s.h / rows.length).round();
    for (final tr in rows) {
      tr.setAttribute('h', '$rh');
    }
  }

  XmlElement _newShape(PptxShape s, int id) {
    final xfrm =
        '<a:xfrm${s.rotation.abs() > 0.01 ? ' rot="${(s.rotation * 60000).round()}"' : ''}${s.flipH ? ' flipH="1"' : ''}${s.flipV ? ' flipV="1"' : ''}>'
        '<a:off x="${s.x.round()}" y="${s.y.round()}"/><a:ext cx="${s.w.round()}" cy="${s.h.round()}"/></a:xfrm>';
    final fill = s.fill == null
        ? ''
        : (s.fill == 'none'
              ? '<a:noFill/>'
              : '<a:solidFill>${_colorXml(s.fill!)}</a:solidFill>');
    final ln = s.line == null
        ? ''
        : '<a:ln${s.lineWidth == null ? '' : ' w="${s.lineWidth!.round()}"'}>${s.line == 'none' ? '<a:noFill/>' : '<a:solidFill>${_colorXml(s.line!)}</a:solidFill>'}${s.arrowEnd ? '<a:tailEnd type="triangle"/>' : ''}</a:ln>';
    if (s.geom == 'line') {
      return _el(
        '<p:cxnSp><p:nvCxnSpPr><p:cNvPr id="$id" name="Straight Connector $id"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>'
        '<p:spPr>$xfrm<a:prstGeom prst="line"><a:avLst/></a:prstGeom>$ln</p:spPr></p:cxnSp>',
      );
    }
    final textBox = s.geom == null;
    final name = textBox ? 'TextBox $id' : '${s.label} $id';
    final fontColor = s.fontColor == null || textBox
        ? ''
        : '<a:defRPr><a:solidFill>${_colorXml(s.fontColor!)}</a:solidFill></a:defRPr>';
    final paras = fontColor.isEmpty
        ? _parasXml(s)
        : _parasXml(s).replaceAllMapped(RegExp(r'<a:p>(<a:pPr[^>]*/>)?'), (m) {
            // Shape text colour as the paragraph default.
            final pPr = m.group(1);
            if (pPr == null) return '<a:p><a:pPr>$fontColor</a:pPr>';
            return '<a:p>${pPr.replaceFirst('/>', '>')}$fontColor</a:pPr>';
          });
    return _el(
      '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="${_esc(name)}"/><p:cNvSpPr${textBox ? ' txBox="1"' : ''}/><p:nvPr/></p:nvSpPr>'
      '<p:spPr>$xfrm<a:prstGeom prst="${s.geom ?? 'rect'}"><a:avLst/></a:prstGeom>${textBox && s.fill == null ? '<a:noFill/>' : fill}$ln</p:spPr>'
      '<p:txBody><a:bodyPr wrap="square" rtlCol="0" anchor="${s.anchor}">${textBox ? '<a:spAutoFit/>' : ''}</a:bodyPr><a:lstStyle/>$paras</p:txBody>'
      '</p:sp>',
    );
  }

  XmlElement _newTable(PptxShape s, int id) {
    final cells = s.cells!;
    final cols = cells.fold<int>(1, (m, r) => math.max(m, r.length));
    final colW = (s.w / cols).round(), rowH = (s.h / cells.length).round();
    final b = StringBuffer(
      '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="$id" name="Table $id"/>'
      '<p:cNvGraphicFramePr><a:graphicFrameLocks noGrp="1"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>'
      '<p:xfrm><a:off x="${s.x.round()}" y="${s.y.round()}"/><a:ext cx="${s.w.round()}" cy="${s.h.round()}"/></p:xfrm>'
      '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
      '<a:tbl><a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr><a:tblGrid>',
    );
    for (var c = 0; c < cols; c++) {
      b.write('<a:gridCol w="$colW"/>');
    }
    b.write('</a:tblGrid>');
    for (final r in cells) {
      b.write('<a:tr h="$rowH">');
      for (var c = 0; c < cols; c++) {
        final t = c < r.length ? r[c] : '';
        b.write(
          '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p>${t.isEmpty ? '' : '<a:r><a:rPr lang="en-US" dirty="0"/><a:t>${_esc(t)}</a:t></a:r>'}<a:endParaRPr lang="en-US" dirty="0"/></a:p></a:txBody><a:tcPr/></a:tc>',
        );
      }
      b.write('</a:tr>');
    }
    b.write('</a:tbl></a:graphicData></a:graphic></p:graphicFrame>');
    return _el(b.toString());
  }

  final _pictureRels = <String, Map<String, String>>{}; // slide → media → rId

  /// A relationship id free in the slide's .rels file and among the
  /// pictures waiting to be written (saved / duplicated slides already use
  /// rIdDs1…).
  String _pictureRid(String slidePath, Map<String, String> pending) {
    final used = {..._relsOf(slidePath).keys, ...pending.values};
    var n = pending.length + 1;
    while (used.contains('rIdDs$n')) {
      n++;
    }
    return 'rIdDs$n';
  }

  XmlElement _newPicture(PptxSlide slide, PptxShape s, int id) {
    final rels = _pictureRels.putIfAbsent(slide.path, () => {});
    final rid = rels.putIfAbsent(s.media!, () => _pictureRid(slide.path, rels));
    return _el(
      '<p:pic><p:nvPicPr><p:cNvPr id="$id" name="Picture $id"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>'
      '<p:blipFill><a:blip r:embed="$rid"/><a:stretch><a:fillRect/></a:stretch></p:blipFill>'
      '<p:spPr><a:xfrm><a:off x="${s.x.round()}" y="${s.y.round()}"/><a:ext cx="${s.w.round()}" cy="${s.h.round()}"/></a:xfrm>'
      '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>',
    );
  }

  void _ensurePictureRels(PptxSlide slide) {
    final rels = _pictureRels[slide.path];
    if (rels == null || rels.isEmpty) return;
    final relPath = _relPath(slide.path);
    final doc = files[relPath] == null
        ? XmlDocument.parse('<Relationships xmlns="$_relNs"/>')
        : XmlDocument.parse(utf8.decode(files[relPath]!));
    final root = doc.rootElement;
    final existing = {for (final r in root.childElements) r.getAttribute('Id')};
    rels.forEach((media, rid) {
      if (existing.contains(rid)) return;
      final target = p.posix.relative(media, from: p.posix.dirname(slide.path));
      root.children.add(
        XmlDocument.parse(
          '<Relationship xmlns="$_relNs" Id="$rid" Type="$_rel/image" Target="$target"/>',
        ).rootElement.copy(),
      );
    });
    files[relPath] = Uint8List.fromList(utf8.encode(doc.toXmlString()));
    _ensureContentTypeDefaults();
  }

  void _ensureContentTypeDefaults() {
    final ct = XmlDocument.parse(utf8.decode(files['[Content_Types].xml']!));
    final root = ct.rootElement;
    final have = {
      for (final d in root.childElements.where(
        (e) => e.name.local == 'Default',
      ))
        (d.getAttribute('Extension') ?? '').toLowerCase(),
    };
    var changed = false;
    for (final (ext, type) in const [
      ('png', 'image/png'),
      ('jpeg', 'image/jpeg'),
      ('jpg', 'image/jpeg'),
      ('gif', 'image/gif'),
      ('bmp', 'image/bmp'),
    ]) {
      if (!have.contains(ext)) {
        changed = true;
        root.children.insert(
          0,
          XmlDocument.parse(
            '<Default xmlns="$_ctNs" Extension="$ext" ContentType="$type"/>',
          ).rootElement.copy(),
        );
      }
    }
    if (changed)
      files['[Content_Types].xml'] = Uint8List.fromList(
        utf8.encode(ct.toXmlString()),
      );
  }

  void _addOverride(String part, String type) {
    final ct = XmlDocument.parse(utf8.decode(files['[Content_Types].xml']!));
    final root = ct.rootElement;
    if (root.childElements.any((o) => o.getAttribute('PartName') == '/$part'))
      return;
    root.children.add(
      XmlDocument.parse(
        '<Override xmlns="$_ctNs" PartName="/$part" ContentType="$type"/>',
      ).rootElement.copy(),
    );
    files['[Content_Types].xml'] = Uint8List.fromList(
      utf8.encode(ct.toXmlString()),
    );
  }

  void _addRel(String part, String id, String type, String target) {
    final relPath = _relPath(part);
    final doc = files[relPath] == null
        ? XmlDocument.parse('<Relationships xmlns="$_relNs"/>')
        : XmlDocument.parse(utf8.decode(files[relPath]!));
    doc.rootElement.children.add(
      XmlDocument.parse(
        '<Relationship xmlns="$_relNs" Id="$id" Type="$_rel/$type" Target="$target"/>',
      ).rootElement.copy(),
    );
    files[relPath] = Uint8List.fromList(utf8.encode(doc.toXmlString()));
  }

  String _freeRelId(String part) {
    final used = _rels(files, part).keys.toSet();
    var n = 1;
    while (used.contains('rIdDs$n')) {
      n++;
    }
    return 'rIdDs$n';
  }

  /// Speaker notes: the notes page is created (with a notes master when the
  /// deck has none) the first time a slide gets notes.
  void _writeNotes(PptxSlide s) {
    s.notesDirty = false;
    final paras = s.notes
        .split('\n')
        .map(
          (l) =>
              '<a:p>${l.isEmpty ? '' : '<a:r><a:rPr lang="en-US" dirty="0"/><a:t>${_esc(l)}</a:t></a:r>'}</a:p>',
        )
        .join();
    var path = s.notesPath;
    if (path != null && files.containsKey(path)) {
      final n = _xml(path);
      for (final sp in n.findAllElements('sp', namespaceUri: _p)) {
        if (sp
                .findAllElements('ph', namespaceUri: _p)
                .firstOrNull
                ?.getAttribute('type') !=
            'body')
          continue;
        final body = sp.getElement('txBody', namespaceUri: _p);
        if (body == null) continue;
        for (final pp in body.findElements('p', namespaceUri: _a).toList()) {
          pp.remove();
        }
        for (final e in _frag(paras)) {
          body.children.add(e);
        }
      }
      files[path] = Uint8List.fromList(utf8.encode(n.toXmlString()));
      return;
    }
    if (s.notes.trim().isEmpty) return;
    final master = _ensureNotesMaster();
    var k = 1;
    while (files.containsKey('ppt/notesSlides/notesSlide$k.xml')) {
      k++;
    }
    path = 'ppt/notesSlides/notesSlide$k.xml';
    files[path] = Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notes xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg"/></p:nvPr></p:nvSpPr><p:spPr/></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" idx="1"/></p:nvPr></p:nvSpPr><p:spPr/>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>$paras</p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:notes>',
      ),
    );
    _addRel(
      path,
      'rId1',
      'notesMaster',
      p.posix.relative(master, from: 'ppt/notesSlides'),
    );
    _addRel(
      path,
      'rId2',
      'slide',
      p.posix.relative(s.path, from: 'ppt/notesSlides'),
    );
    _addRel(
      s.path,
      _freeRelId(s.path),
      'notesSlide',
      p.posix.relative(path, from: p.posix.dirname(s.path)),
    );
    _addOverride(
      path,
      'application/vnd.openxmlformats-officedocument.presentationml.notesSlide+xml',
    );
    s.notesPath = path;
  }

  String _ensureNotesMaster() {
    for (final f in files.keys) {
      if (RegExp(r'^ppt/notesMasters/notesMaster\d+\.xml$').hasMatch(f))
        return f;
    }
    const path = 'ppt/notesMasters/notesMaster1.xml';
    files[path] = Uint8List.fromList(
      utf8.encode(
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:notesMaster xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Slide Image Placeholder 1"/><p:cNvSpPr><a:spLocks noGrp="1" noRot="1" noChangeAspect="1"/></p:cNvSpPr><p:nvPr><p:ph type="sldImg" idx="2"/></p:nvPr></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="381000" y="685800"/><a:ext cx="6096000" cy="3429000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln w="12700"><a:solidFill><a:prstClr val="black"/></a:solidFill></a:ln></p:spPr></p:sp>'
        '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Notes Placeholder 2"/><p:cNvSpPr><a:spLocks noGrp="1"/></p:cNvSpPr><p:nvPr><p:ph type="body" sz="quarter" idx="3"/></p:nvPr></p:nvSpPr>'
        '<p:spPr><a:xfrm><a:off x="685800" y="4400550"/><a:ext cx="5486400" cy="3600450"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr vert="horz" lIns="91440" tIns="45720" rIns="91440" bIns="45720" rtlCol="0"/><a:lstStyle/><a:p><a:endParaRPr lang="en-US"/></a:p></p:txBody></p:sp>'
        '</p:spTree></p:cSld><p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>'
        '<p:notesStyle><a:lvl1pPr marL="0" algn="l" defTabSz="914400" rtl="0" eaLnBrk="1" latinLnBrk="0" hangingPunct="1"><a:defRPr sz="1200" kern="1200"><a:solidFill><a:schemeClr val="tx1"/></a:solidFill><a:latin typeface="+mn-lt"/><a:ea typeface="+mn-ea"/><a:cs typeface="+mn-cs"/></a:defRPr></a:lvl1pPr></p:notesStyle>'
        '</p:notesMaster>',
      ),
    );
    // Its own copy of the theme.
    var t = 1;
    while (files.containsKey('ppt/theme/theme$t.xml')) {
      t++;
    }
    final themeCopy = 'ppt/theme/theme$t.xml';
    final src = themePath ?? 'ppt/theme/theme1.xml';
    if (files[src] != null) {
      files[themeCopy] = files[src]!;
      _addOverride(
        themeCopy,
        'application/vnd.openxmlformats-officedocument.theme+xml',
      );
      _addRel(path, 'rId1', 'theme', '../theme/${p.posix.basename(themeCopy)}');
    }
    _addOverride(
      path,
      'application/vnd.openxmlformats-officedocument.presentationml.notesMaster+xml',
    );
    final rid = _freeRelId('ppt/presentation.xml');
    _addRel(
      'ppt/presentation.xml',
      rid,
      'notesMaster',
      'notesMasters/notesMaster1.xml',
    );
    final pres = _xml('ppt/presentation.xml');
    final root = pres.rootElement;
    final lst = _el(
      '<p:notesMasterIdLst><p:notesMasterId r:id="$rid"/></p:notesMasterIdLst>',
    );
    final after = root.childElements
        .where((c) => c.name.local == 'sldMasterIdLst')
        .firstOrNull;
    root.children.insert(
      after == null ? 0 : root.children.indexOf(after) + 1,
      lst,
    );
    files['ppt/presentation.xml'] = Uint8List.fromList(
      utf8.encode(pres.toXmlString()),
    );
    return path;
  }

  void _writeTheme() {
    dirtyTheme = false;
    final path = themePath;
    if (path == null || files[path] == null) return;
    final t = _xml(path);
    final scheme = t.findAllElements('clrScheme', namespaceUri: _a).firstOrNull;
    if (scheme != null) {
      scheme.setAttribute('name', theme.name);
      for (final c in scheme.childElements) {
        final v = theme.colors[c.name.local];
        if (v == null) continue;
        for (final k in c.children.toList()) {
          k.remove();
        }
        c.children.add(_el('<a:srgbClr val="$v"/>'));
      }
    }
    for (final (kind, font) in [
      ('majorFont', theme.major),
      ('minorFont', theme.minor),
    ]) {
      t
          .findAllElements(kind, namespaceUri: _a)
          .firstOrNull
          ?.getElement('latin', namespaceUri: _a)
          ?.setAttribute('typeface', font);
    }
    files[path] = Uint8List.fromList(utf8.encode(t.toXmlString()));
  }

  /// presentation.xml slide list, its relationships and content types.
  void _writePresentationOrder() {
    const presPath = 'ppt/presentation.xml';
    const relPath = 'ppt/_rels/presentation.xml.rels';
    final pres = XmlDocument.parse(utf8.decode(files[presPath]!));
    final relDoc = XmlDocument.parse(utf8.decode(files[relPath]!));
    final relRoot = relDoc.rootElement;
    for (final r in relRoot.childElements.toList()) {
      if ((r.getAttribute('Type') ?? '').endsWith('/slide')) r.remove();
    }
    final list = pres.findAllElements('sldIdLst', namespaceUri: _p).firstOrNull;
    final used = {for (final r in relRoot.childElements) r.getAttribute('Id')};
    final ids = <String>[];
    var k = 1;
    for (final s in slides) {
      var rid = 'rIdDsS$k';
      while (used.contains(rid)) {
        k++;
        rid = 'rIdDsS$k';
      }
      used.add(rid);
      ids.add(rid);
      relRoot.children.add(
        XmlDocument.parse(
          '<Relationship xmlns="$_relNs" Id="$rid" Type="$_rel/slide" Target="${p.posix.relative(s.path, from: 'ppt')}"/>',
        ).rootElement.copy(),
      );
      k++;
    }
    if (list != null) {
      for (final c in list.childElements.toList()) {
        c.remove();
      }
      // Keep each slide's id; new slides get unused ones (≥ 256).
      final taken = <int>{};
      var next = 255;
      for (final s in slides) {
        final id = s.sldId;
        if (id != null && id >= 256 && taken.add(id)) next = math.max(next, id);
      }
      for (var i = 0; i < ids.length; i++) {
        var id = slides[i].sldId;
        if (id == null || id < 256 || !taken.contains(id)) {
          do {
            next++;
          } while (taken.contains(next));
          id = next;
          taken.add(id);
          slides[i].sldId = id;
        }
        list.children.add(
          XmlDocument.parse(
            '<p:sldId xmlns:p="$_p" xmlns:r="$_r" id="$id" r:id="${ids[i]}"/>',
          ).rootElement.copy(),
        );
      }
    }
    files[presPath] = Uint8List.fromList(utf8.encode(pres.toXmlString()));
    files[relPath] = Uint8List.fromList(utf8.encode(relDoc.toXmlString()));
    final ct = XmlDocument.parse(utf8.decode(files['[Content_Types].xml']!));
    final root = ct.rootElement;
    final keep = {for (final s in slides) '/${s.path}'};
    for (final o in root.childElements.toList()) {
      final part = o.getAttribute('PartName') ?? '';
      if (part.startsWith('/ppt/slides/slide') && !keep.contains(part))
        o.remove();
    }
    final have = {
      for (final o in root.childElements) o.getAttribute('PartName'),
    };
    for (final s in slides) {
      if (!have.contains('/${s.path}')) {
        root.children.add(
          XmlDocument.parse(
            '<Override xmlns="$_ctNs" PartName="/${s.path}" '
            'ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>',
          ).rootElement.copy(),
        );
      }
    }
    final live = {for (final s in slides) s.path};
    for (final f in files.keys.toList()) {
      if (RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(f) &&
          !live.contains(f)) {
        final relKey = _relPath(f);
        final rel = files[relKey];
        if (rel != null) {
          for (final r in XmlDocument.parse(
            utf8.decode(rel),
          ).findAllElements('Relationship')) {
            final t = r.getAttribute('Target') ?? '';
            if (!t.contains('notesSlide')) continue;
            final notes = p.posix.normalize(p.posix.join('ppt/slides', t));
            files.remove(notes);
            files.remove(_relPath(notes));
            for (final o in root.childElements.toList()) {
              if (o.getAttribute('PartName') == '/$notes') o.remove();
            }
          }
        }
        files.remove(f);
        files.remove(relKey);
      }
    }
    files['[Content_Types].xml'] = Uint8List.fromList(
      utf8.encode(ct.toXmlString()),
    );
  }
}

/// Built-in designs (Design → Themes): colours and fonts.
final kPptxDesigns = <PptxTheme>[
  PptxTheme(
    name: 'Office',
    major: 'Calibri Light',
    minor: 'Calibri',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '44546A', 'lt2': 'E7E6E6', //
      'accent1': '4472C4',
      'accent2': 'ED7D31',
      'accent3': 'A5A5A5',
      'accent4': 'FFC000',
      'accent5': '5B9BD5',
      'accent6': '70AD47',
      'hlink': '0563C1', 'folHlink': '954F72',
    },
  ),
  PptxTheme(
    name: 'Facet',
    major: 'Trebuchet MS',
    minor: 'Trebuchet MS',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '2C3C43', 'lt2': 'EBEBEB', //
      'accent1': '90C226',
      'accent2': '54A021',
      'accent3': 'E6B91E',
      'accent4': 'E76618',
      'accent5': 'C42F1A',
      'accent6': '918655',
      'hlink': '99CA3C', 'folHlink': 'B9D181',
    },
  ),
  PptxTheme(
    name: 'Ion',
    major: 'Century Gothic',
    minor: 'Century Gothic',
    colors: {
      'dk1': 'FFFFFF', 'lt1': '1B5768', 'dk2': 'FFFFFF', 'lt2': '2B7A8B', //
      'accent1': 'B01513',
      'accent2': 'EA6312',
      'accent3': 'E6B729',
      'accent4': '6AAC90',
      'accent5': '5F9C9D',
      'accent6': '9E5E9B',
      'hlink': 'FFF5BE', 'folHlink': 'D9E7E8',
    },
  ),
  PptxTheme(
    name: 'Retrospect',
    major: 'Calibri Light',
    minor: 'Calibri',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '637052', 'lt2': 'CCDDEA', //
      'accent1': 'E48312',
      'accent2': 'BD582C',
      'accent3': '865640',
      'accent4': '9B8357',
      'accent5': 'C2BC80',
      'accent6': '94A088',
      'hlink': '2998E3', 'folHlink': '8C8C8C',
    },
  ),
  PptxTheme(
    name: 'Slice',
    major: 'Century Gothic',
    minor: 'Century Gothic',
    colors: {
      'dk1': 'FFFFFF', 'lt1': '052F61', 'dk2': 'FFFFFF', 'lt2': '0B4B8F', //
      'accent1': '4A66AC',
      'accent2': '629DD1',
      'accent3': '297FD5',
      'accent4': '7F8FA9',
      'accent5': '5AA2AE',
      'accent6': '9D90A0',
      'hlink': '9DC3E6', 'folHlink': 'B4C7E7',
    },
  ),
  PptxTheme(
    name: 'Berlin',
    major: 'Trebuchet MS',
    minor: 'Trebuchet MS',
    colors: {
      'dk1': 'FFFFFF', 'lt1': '9D360E', 'dk2': 'FFFFFF', 'lt2': 'C55A11', //
      'accent1': 'F09415',
      'accent2': 'C1B56B',
      'accent3': '4BAF73',
      'accent4': '5AA6C0',
      'accent5': 'D17DF9',
      'accent6': 'FA7E5C',
      'hlink': 'FFD966', 'folHlink': 'F4B183',
    },
  ),
  PptxTheme(
    name: 'Organic',
    major: 'Garamond',
    minor: 'Garamond',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '212121', 'lt2': 'F2F0E6', //
      'accent1': '83992A',
      'accent2': '3C9770',
      'accent3': '44709D',
      'accent4': 'A23C33',
      'accent5': 'D97828',
      'accent6': 'DEB340',
      'hlink': 'A8BF4D', 'folHlink': 'B4CA80',
    },
  ),
  PptxTheme(
    name: 'Dividend',
    major: 'Gill Sans',
    minor: 'Gill Sans',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '3A3A3A', 'lt2': 'E4E4E4', //
      'accent1': '4D1434',
      'accent2': '903163',
      'accent3': 'B2324B',
      'accent4': '969FA7',
      'accent5': '66B1CE',
      'accent6': '40619D',
      'hlink': '6B9F25', 'folHlink': 'B26B02',
    },
  ),
  PptxTheme(
    name: 'Mono',
    major: 'Arial',
    minor: 'Arial',
    colors: {
      'dk1': '000000', 'lt1': 'FFFFFF', 'dk2': '262626', 'lt2': 'F2F2F2', //
      'accent1': '404040',
      'accent2': '7F7F7F',
      'accent3': 'A5A5A5',
      'accent4': '595959',
      'accent5': 'BFBFBF',
      'accent6': '262626',
      'hlink': '0563C1', 'folHlink': '954F72',
    },
  ),
  PptxTheme(
    name: 'Midnight',
    major: 'Segoe UI',
    minor: 'Segoe UI',
    colors: {
      'dk1': 'F5F5F5', 'lt1': '16162B', 'dk2': 'F5F5F5', 'lt2': '24244A', //
      'accent1': 'E94560',
      'accent2': '3D7BD9',
      'accent3': '16C79A',
      'accent4': 'F6C90E',
      'accent5': '8E7DBE',
      'accent6': '53A8B6',
      'hlink': '7FB8FF', 'folHlink': 'C3A6FF',
    },
  ),
];
