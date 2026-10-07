import 'package:document_studio/features/compose/compose_model.dart';

/// Parses a small TikZ subset into a [CDrawing] (no TeX engine).
///
/// Supports `\draw` / `\fill` / `\filldraw` with `--`, `rectangle`,
/// `circle`, `ellipse`, mid-path `node {…}`, and `\node at (x,y) {…}`.
/// Unknown path fragments are skipped; the environment is still consumed.
CDrawing parseTikzSubset(String body) {
  final ops = <CDrawOp>[];
  final src = _stripComments(body);
  var i = 0;
  while (i < src.length) {
    if (src[i] != r'\') {
      i++;
      continue;
    }
    final name = _commandName(src, i);
    if (name == null) {
      i++;
      continue;
    }
    i = name.$2;
    switch (name.$1) {
      case 'draw' || 'fill' || 'filldraw' || 'path':
        final stmt = _readStatement(src, i);
        i = stmt.$2;
        ops.addAll(
          _parsePath(
            stmt.$1,
            stroke: name.$1 != 'fill',
            fill: name.$1 == 'fill' || name.$1 == 'filldraw',
          ),
        );
      case 'node':
        final stmt = _readStatement(src, i);
        i = stmt.$2;
        final n = _parseNode(stmt.$1);
        if (n != null) ops.add(n);
      default:
        // Skip unknown TikZ commands (foreach, clip, …) to end of statement.
        final stmt = _readStatement(src, i);
        i = stmt.$2;
    }
  }
  return _bounded(ops);
}

String _stripComments(String s) {
  final out = StringBuffer();
  for (final line in s.split('\n')) {
    var cut = line.length;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == '%' && (i == 0 || line[i - 1] != r'\')) {
        cut = i;
        break;
      }
    }
    out.writeln(line.substring(0, cut));
  }
  return out.toString();
}

(String, int)? _commandName(String s, int at) {
  if (at >= s.length || s[at] != r'\') return null;
  var i = at + 1;
  final start = i;
  while (i < s.length && RegExp('[A-Za-z]').hasMatch(s[i])) {
    i++;
  }
  if (i == start) {
    if (i < s.length) i++;
    return (s.substring(start, i), i);
  }
  final name = s.substring(start, i);
  return (name, _skipSpaces(s, i));
}

int _skipSpaces(String s, int i) {
  while (i < s.length && (s[i] == ' ' || s[i] == '\n' || s[i] == '\t')) {
    i++;
  }
  return i;
}

/// Content up to `;` (groups respected), returns (content, index after `;`).
(String, int) _readStatement(String s, int start) {
  var i = start;
  var depth = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == r'\') {
      i += 2;
      continue;
    }
    if (ch == '{') depth++;
    if (ch == '}') depth = depth > 0 ? depth - 1 : 0;
    if (ch == ';' && depth == 0) {
      return (s.substring(start, i), i + 1);
    }
    i++;
  }
  return (s.substring(start), s.length);
}

List<CDrawOp> _parsePath(
  String raw, {
  required bool stroke,
  required bool fill,
}) {
  var s = raw.trim();
  var style = _PathStyle(
    stroke: stroke,
    fill: fill,
    strokeColor: 0xFF000000,
    fillColor: fill ? 0xFF000000 : null,
  );
  if (s.startsWith('[')) {
    final end = _matchingBracket(s, 0);
    if (end > 0) {
      style = _parseStyle(s.substring(1, end), style);
      s = s.substring(end + 1).trim();
    }
  }
  final ops = <CDrawOp>[];
  final pts = <(double, double)>[];
  var i = 0;

  void flushPoly() {
    if (pts.length >= 2) {
      ops.add(
        CDrawOp(
          kind: pts.length == 2 ? CDrawKind.line : CDrawKind.polyline,
          points: List.of(pts),
          strokeColor: style.stroke ? style.strokeColor : null,
          fillColor: style.fill ? style.fillColor : null,
          strokeWidth: style.width,
          dashed: style.dashed,
        ),
      );
    }
    pts.clear();
  }

  while (i < s.length) {
    i = _skipSpaces(s, i);
    if (i >= s.length) break;

    if (s.startsWith('node', i) ||
        (s[i] == r'\' && s.startsWith(r'\node', i))) {
      final at = s.startsWith(r'\node', i) ? i + 5 : i + 4;
      final rest = s.substring(at);
      final n = _parseNode(rest, inherit: style);
      // Consume until we hit a path token again — approximate by reading
      // through the node’s `{text}`.
      final brace = rest.indexOf('{');
      if (brace >= 0) {
        final inner = _matchingBrace(rest, brace);
        i = at + (inner < 0 ? rest.length : inner + 1);
      } else {
        i = at;
      }
      if (n != null) ops.add(n);
      continue;
    }

    if (s.startsWith('rectangle', i)) {
      i = _skipSpaces(s, i + 9);
      final a = pts.isNotEmpty ? pts.last : null;
      final b = _readCoord(s, i);
      if (a != null && b != null) {
        ops.add(
          CDrawOp(
            kind: CDrawKind.rect,
            points: [a, b.$1],
            strokeColor: style.stroke ? style.strokeColor : null,
            fillColor: style.fill ? (style.fillColor ?? 0xFF000000) : null,
            strokeWidth: style.width,
            dashed: style.dashed,
          ),
        );
        pts
          ..clear()
          ..add(b.$1);
        i = b.$2;
      }
      continue;
    }

    if (s.startsWith('circle', i)) {
      i = _skipSpaces(s, i + 6);
      final c = pts.isNotEmpty ? pts.last : (0.0, 0.0);
      double r = 28.35; // 1cm
      if (i < s.length && s[i] == '[') {
        final end = _matchingBracket(s, i);
        final opt = s.substring(i + 1, end);
        final rm = RegExp(r'radius\s*=\s*([+-]?\d*\.?\d+)\s*(cm|pt|mm)?')
            .firstMatch(opt);
        if (rm != null) {
          r = _toPt(double.parse(rm.group(1)!), rm.group(2));
        }
        i = end + 1;
      } else if (i < s.length && s[i] == '(') {
        final m = RegExp(r'^\(\s*([+-]?\d*\.?\d+)\s*(cm|pt|mm)?\s*\)')
            .firstMatch(s.substring(i));
        if (m != null) {
          r = _toPt(double.parse(m.group(1)!), m.group(2));
          i += m.end;
        }
      }
      ops.add(
        CDrawOp(
          kind: CDrawKind.ellipse,
          points: [c, (r, r)],
          strokeColor: style.stroke ? style.strokeColor : null,
          fillColor: style.fill ? (style.fillColor ?? 0xFF000000) : null,
          strokeWidth: style.width,
          dashed: style.dashed,
        ),
      );
      continue;
    }

    if (s.startsWith('ellipse', i)) {
      i = _skipSpaces(s, i + 7);
      final c = pts.isNotEmpty ? pts.last : (0.0, 0.0);
      double rx = 28.35, ry = 28.35;
      if (i < s.length && s[i] == '(') {
        final m = RegExp(
          r'^\(\s*([+-]?\d*\.?\d+)\s*(cm|pt|mm)?\s+and\s+([+-]?\d*\.?\d+)\s*(cm|pt|mm)?\s*\)',
        ).firstMatch(s.substring(i));
        if (m != null) {
          rx = _toPt(double.parse(m.group(1)!), m.group(2));
          ry = _toPt(double.parse(m.group(3)!), m.group(4));
          i += m.end;
        }
      }
      ops.add(
        CDrawOp(
          kind: CDrawKind.ellipse,
          points: [c, (rx, ry)],
          strokeColor: style.stroke ? style.strokeColor : null,
          fillColor: style.fill ? (style.fillColor ?? 0xFF000000) : null,
          strokeWidth: style.width,
          dashed: style.dashed,
        ),
      );
      continue;
    }

    if (s.startsWith('--', i)) {
      i += 2;
      continue;
    }

    if (s[i] == '(') {
      final c = _readCoord(s, i);
      if (c != null) {
        pts.add(c.$1);
        i = c.$2;
        continue;
      }
    }

    i++;
  }
  flushPoly();
  return ops;
}

CDrawOp? _parseNode(String raw, {_PathStyle? inherit}) {
  var s = raw.trim();
  // Optional [options]
  if (s.startsWith('[')) {
    final end = _matchingBracket(s, 0);
    if (end > 0) s = s.substring(end + 1).trim();
  }
  // `at (x,y)`
  final at = RegExp(r'^at\b').firstMatch(s);
  if (at == null) return null;
  s = s.substring(at.end).trim();
  final coord = _readCoord(s, 0);
  if (coord == null) return null;
  s = s.substring(coord.$2).trim();
  if (!s.startsWith('{')) return null;
  final end = _matchingBrace(s, 0);
  if (end < 0) return null;
  final text = s.substring(1, end).trim();
  return CDrawOp(
    kind: CDrawKind.text,
    points: [coord.$1],
    text: text
        .replaceAll(r'\#', '#')
        .replaceAll(r'\&', '&')
        .replaceAll(r'\%', '%')
        .replaceAll(RegExp(r'\\[A-Za-z]+'), '')
        .replaceAll(RegExp(r'[{}]'), ''),
    strokeColor: inherit?.strokeColor,
    fillColor: null,
  );
}

((double, double), int)? _readCoord(String s, int i) {
  i = _skipSpaces(s, i);
  final m = RegExp(
    r'^\(\s*([+-]?\d*\.?\d+)\s*(cm|pt|mm)?\s*,\s*([+-]?\d*\.?\d+)\s*(cm|pt|mm)?\s*\)',
  ).firstMatch(s.substring(i));
  if (m == null) return null;
  final x = _toPt(double.parse(m.group(1)!), m.group(2));
  final y = _toPt(double.parse(m.group(3)!), m.group(4));
  return ((x, y), i + m.end);
}

double _toPt(double v, String? unit) => switch (unit) {
  'pt' => v,
  'mm' => v * 72 / 25.4,
  'cm' || null => v * 72 / 2.54, // TikZ default: unitless ≈ cm
  _ => v * 72 / 2.54,
};

int _matchingBracket(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == r'\') {
      i++;
      continue;
    }
    if (s[i] == '[') depth++;
    if (s[i] == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

int _matchingBrace(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == r'\') {
      i++;
      continue;
    }
    if (s[i] == '{') depth++;
    if (s[i] == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

class _PathStyle {
  _PathStyle({
    required this.stroke,
    required this.fill,
    required this.strokeColor,
    this.fillColor,
    this.width = 1.2,
    this.dashed = false,
  });

  bool stroke;
  bool fill;
  int strokeColor;
  int? fillColor;
  double width;
  bool dashed;

  _PathStyle copy() => _PathStyle(
    stroke: stroke,
    fill: fill,
    strokeColor: strokeColor,
    fillColor: fillColor,
    width: width,
    dashed: dashed,
  );
}

_PathStyle _parseStyle(String opt, _PathStyle base) {
  final s = base.copy();
  for (final part in opt.split(',')) {
    final t = part.trim().toLowerCase();
    if (t.isEmpty) continue;
    if (t == 'thick') {
      s.width = 2.2;
    } else if (t == 'thin') {
      s.width = 0.7;
    } else if (t == 'ultra thick') {
      s.width = 3.2;
    } else if (t == 'dashed' || t == 'dotted') {
      s.dashed = true;
    } else if (t == 'solid') {
      s.dashed = false;
    } else if (t.startsWith('line width')) {
      final m = RegExp(r'([+-]?\d*\.?\d+)').firstMatch(t);
      if (m != null) s.width = double.parse(m.group(1)!);
    } else if (t.startsWith('color=') || t.startsWith('draw=')) {
      final c = _color(t.split('=').last.trim());
      if (c != null) s.strokeColor = c;
    } else if (t.startsWith('fill=')) {
      final c = _color(t.substring(5).trim());
      if (c != null) {
        s.fillColor = c;
        s.fill = true;
      } else if (t.endsWith('none')) {
        s.fill = false;
        s.fillColor = null;
      }
    } else {
      final c = _color(t);
      if (c != null) s.strokeColor = c;
    }
  }
  return s;
}

int? _color(String name) {
  final n = name.toLowerCase().split('!').first.trim();
  return switch (n) {
    'black' => 0xFF000000,
    'white' => 0xFFFFFFFF,
    'red' => 0xFFCC0000,
    'blue' => 0xFF1565C0,
    'green' => 0xFF2E7D32,
    'orange' => 0xFFEF6C00,
    'yellow' => 0xFFF9A825,
    'gray' || 'grey' => 0xFF757575,
    'brown' => 0xFF6D4C41,
    'cyan' => 0xFF00838F,
    'magenta' || 'purple' || 'violet' => 0xFF6A1B9A,
    _ => null,
  };
}

CDrawing _bounded(List<CDrawOp> ops) {
  if (ops.isEmpty) {
    return const CDrawing([], width: 120, height: 60);
  }
  var minX = double.infinity, minY = double.infinity;
  var maxX = -double.infinity, maxY = -double.infinity;
  void tip(double x, double y) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
  }

  for (final op in ops) {
    switch (op.kind) {
      case CDrawKind.ellipse:
        if (op.points.length >= 2) {
          final (cx, cy) = op.points[0];
          final (rx, ry) = op.points[1];
          tip(cx - rx, cy - ry);
          tip(cx + rx, cy + ry);
        }
      case CDrawKind.text:
        if (op.points.isNotEmpty) {
          final (x, y) = op.points.first;
          tip(x - 12, y - 8);
          tip(x + 12, y + 8);
        }
      default:
        for (final (x, y) in op.points) {
          tip(x, y);
        }
    }
  }
  if (!minX.isFinite) {
    return const CDrawing([], width: 120, height: 60);
  }
  const pad = 10.0;
  final ox = minX - pad;
  final oy = minY - pad;
  final w = (maxX - minX + 2 * pad).clamp(40.0, 2000.0);
  final h = (maxY - minY + 2 * pad).clamp(40.0, 2000.0);
  final shifted = [
    for (final op in ops)
      CDrawOp(
        kind: op.kind,
        points: [for (final (x, y) in op.points) (x - ox, y - oy)],
        text: op.text,
        strokeColor: op.strokeColor,
        fillColor: op.fillColor,
        strokeWidth: op.strokeWidth,
        dashed: op.dashed,
      ),
  ];
  return CDrawing(shifted, width: w, height: h);
}
