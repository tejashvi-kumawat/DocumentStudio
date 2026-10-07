import 'package:document_studio/features/office/pptx_io.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_quill/quill_delta.dart';

/// Slide text ↔ Quill delta, for rich in-place editing. Each run carries
/// `pr: "para:run"` (and each line `pp: "para"`) so the original run and
/// paragraph properties — theme colours, spacing, language — survive.

String _hex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

String? _alignToQuill(String? a) => switch (a) {
  'ctr' => 'center',
  'r' => 'right',
  'just' => 'justify',
  _ => null,
};

String? _alignFromQuill(Object? a) => switch (a) {
  'center' => 'ctr',
  'right' => 'r',
  'justify' => 'just',
  _ => null,
};

String _num(double v) =>
    v % 1 == 0 ? v.toInt().toString() : v.toStringAsFixed(1);

Delta pptxToDelta(PptxDocument doc, PptxShape s) {
  final d = Delta();
  final defColor =
      doc.resolve(s.fontColor ?? '@tx1') ?? const Color(0xFF000000);
  for (var i = 0; i < s.paras.length; i++) {
    final para = s.paras[i];
    for (var j = 0; j < para.runs.length; j++) {
      final r = para.runs[j];
      if (r.text.isEmpty) continue;
      d.insert(r.text == '\v' ? '\n' : r.text, {
        if (r.bold) 'bold': true,
        if (r.italic) 'italic': true,
        if (r.underline) 'underline': true,
        if (r.strike) 'strike': true,
        'size': _num(r.sizePt ?? s.sizeForLevel(para.level)),
        'color': _hex(doc.resolve(r.color) ?? defColor),
        'font': doc.fontName(r.font, title: s.titleFont),
        'pr': '$i:$j',
      });
    }
    d.insert('\n', {
      'align': ?_alignToQuill(para.align ?? s.defaultAlign),
      if (para.numbered)
        'list': 'ordered'
      else if (para.bullet)
        'list': 'bullet',
      if (para.level > 0) 'indent': para.level,
      if (para.lineSpacing != null) 'line-height': para.lineSpacing,
      'pp': '$i',
    });
  }
  if (d.isEmpty) d.insert('\n');
  return d;
}

List<PptxPara> deltaToPptx(PptxDocument doc, PptxShape s, Delta d) {
  final out = <PptxPara>[];
  var runs = <PptxRun>[];
  final defColor =
      doc.resolve(s.fontColor ?? '@tx1') ?? const Color(0xFF000000);
  final defFont = s.titleFont ? doc.theme.major : doc.theme.minor;

  PptxRun? origRun(Object? pr) {
    if (pr is! String) return null;
    final parts = pr.split(':');
    final i = int.tryParse(parts.first), j = int.tryParse(parts.last);
    if (i == null ||
        j == null ||
        i >= s.paras.length ||
        j >= s.paras[i].runs.length)
      return null;
    return s.paras[i].runs[j];
  }

  PptxPara? origPara(Object? pp) {
    final i = pp is String ? int.tryParse(pp) : null;
    return i == null || i >= s.paras.length ? null : s.paras[i];
  }

  void endLine(Map<String, dynamic>? a) {
    final src =
        origPara(a?['pp']) ??
        (out.isNotEmpty ? out.last : (s.paras.isEmpty ? null : s.paras.first));
    final level = (a?['indent'] as int?) ?? 0;
    final align = _alignFromQuill(a?['align']);
    final list = a?['list'];
    final para = PptxPara(
      runs,
      // The placeholder's own alignment stays inherited.
      align: (align ?? 'l') == (s.defaultAlign ?? 'l') ? null : (align ?? 'l'),
      level: level,
      bullet: list == 'bullet',
      numbered: list == 'ordered',
      lineSpacing: (a?['line-height'] as num?)?.toDouble(),
      pPr: src?.pPr?.copy(),
      inheritedBullet: src?.inheritedBullet ?? false,
    );
    // Sizes equal to the level default stay inherited.
    for (final r in runs) {
      if (r.sizePt != null &&
          (r.sizePt! - s.sizeForLevel(level)).abs() < 0.05 &&
          (r.rPr?.getAttribute('sz') == null)) {
        r.sizePt = null;
      }
    }
    out.add(para);
    runs = [];
  }

  for (final op in d.toList()) {
    final data = op.data;
    if (data is! String) continue;
    final a = op.attributes;
    final parts = data.split('\n');
    for (var k = 0; k < parts.length; k++) {
      final text = parts[k];
      if (text.isNotEmpty) {
        final o = origRun(a?['pr']);
        final size = double.tryParse('${a?['size'] ?? ''}');
        final colorHex = a?['color'] as String?;
        String? color;
        if (colorHex != null) {
          final resolvedOrig = o == null ? null : doc.resolve(o.color);
          if (o?.color != null &&
              resolvedOrig != null &&
              _hex(resolvedOrig) == colorHex.toUpperCase()) {
            color = o!.color;
          } else if (colorHex.toUpperCase() == _hex(defColor)) {
            color = null;
          } else {
            color = colorHex.replaceFirst('#', '').toUpperCase();
          }
        }
        final fontName = a?['font'] as String?;
        String? font;
        if (fontName != null) {
          if (o != null &&
              doc.fontName(o.font, title: s.titleFont) == fontName) {
            font = o.font;
          } else if (fontName != defFont) {
            font = fontName;
          }
        }
        runs.add(
          PptxRun(
            text,
            bold: a?['bold'] == true,
            italic: a?['italic'] == true,
            underline: a?['underline'] == true,
            strike: a?['strike'] == true,
            sizePt: size,
            color: color,
            font: font,
            rPr: o?.rPr?.copy(),
          ),
        );
      }
      if (k < parts.length - 1) endLine(a);
    }
  }
  if (runs.isNotEmpty) endLine(null);
  return out;
}
