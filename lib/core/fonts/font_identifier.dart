import 'dart:convert';

import 'package:document_studio/infrastructure/pdf/edit/pdf_font_identity.dart';

/// Result of font recognition: the bundled family and style that best
/// reproduce a PDF font, and how it was found.
class FontIdentity {
  const FontIdentity(
    this.family,
    this.bold,
    this.italic, {
    required this.how,
    this.score = 0,
  });
  final String family;
  final bool bold, italic;

  /// `name`, `embedded`, `metrics` or `class` (serif / sans / mono guess).
  final String how;

  /// Width mismatch (0 = identical metrics) when metrics were compared.
  final double score;

  @override
  String toString() =>
      '$family${bold ? ' Bold' : ''}${italic ? ' Italic' : ''} ($how${how == 'metrics' ? ' ${score.toStringAsFixed(3)}' : ''})';
}

class _Metrics {
  _Metrics(this.family, this.bold, this.italic, this.weight, this.w);
  final String family;
  final bool bold, italic;
  final int weight;
  final List<int> w; // codes 32…126
}

/// Identifies PDF fonts like Adobe's "recognise font": by name (with
/// metric-compatible twins: Calibri → Carlito, Arial → Arimo…), by the
/// embedded program's own family name, then by comparing glyph widths with
/// every bundled font, and finally by the descriptor's serif / fixed-pitch
/// flags.
class FontIdentifier {
  FontIdentifier(String metricsJson, this.familyForName)
    : _metrics = [
        for (final m
            in (jsonDecode(metricsJson) as List).cast<Map<String, dynamic>>())
          _Metrics(
            m['family'] as String,
            m['bold'] == true,
            m['italic'] == true,
            (m['weight'] as num?)?.toInt() ?? 400,
            (m['w'] as List).cast<int>(),
          ),
      ];

  final List<_Metrics> _metrics;

  /// Library family for a font name (see FontLibrary.libraryFamilyFor).
  final String? Function(String name) familyForName;

  static final _boldRe = RegExp(
    r'bold|black|heavy|semibold|demi|extrabold|ultrabold',
    caseSensitive: false,
  );
  static final _italicRe = RegExp(
    r'italic|oblique|slanted|-it$|-ital',
    caseSensitive: false,
  );

  FontIdentity identify(PdfFontEvidence e) {
    final names = [e.name, ?e.embeddedFamily];
    final nameBold = names.any(_boldRe.hasMatch);
    final bold = nameBold || e.forceBold || (e.weight ?? 0) >= 600;
    final italic = names.any(_italicRe.hasMatch) || e.italic;
    final usable = !e.symbolic && e.widths.length >= 6;

    // 1. The name (or the embedded font's own name) says which family.
    for (var k = 0; k < names.length; k++) {
      final fam = familyForName(names[k]);
      if (fam == null) continue;
      var b = bold, i = italic;
      // Widths settle a style the name does not state (e.g. "F1" + Arial).
      if (usable && !nameBold && e.weight == null) {
        final best = _best(e, only: fam);
        if (best != null && best.$2 < 0.02) {
          b = best.$1.bold || e.forceBold;
          i = i || best.$1.italic;
        }
      }
      return FontIdentity(fam, b, i, how: k == 0 ? 'name' : 'embedded');
    }
    // 2. Metrics: the bundled font whose widths match.
    if (usable) {
      final best = _best(e);
      if (best != null && best.$2 < 0.035) {
        final m = best.$1;
        return FontIdentity(
          m.family,
          m.bold || bold,
          m.italic || italic,
          how: 'metrics',
          score: best.$2,
        );
      }
    }
    // 3. Class from the descriptor and the name.
    final n = names.join(' ').toLowerCase();
    final mono =
        e.fixedPitch ||
        RegExp(r'mono|courier|consol|code|typewriter').hasMatch(n);
    final serif =
        !mono &&
        (e.serif ||
            RegExp(r'serif|times|roman|georgia|garamond|book|minion')
                .hasMatch(n)) &&
        !n.contains('sans');
    return FontIdentity(
      mono ? 'Cousine' : (serif ? 'Tinos' : 'Arimo'),
      bold,
      italic,
      how: 'class',
    );
  }

  /// Closest bundled font by widths: (font, mean relative error).
  (_Metrics, double)? _best(PdfFontEvidence e, {String? only}) {
    (_Metrics, double)? best;
    for (final m in _metrics) {
      if (only != null && m.family != only) continue;
      var err = 0.0, total = 0.0, n = 0;
      e.widths.forEach((code, w) {
        final lw = m.w[code - 32];
        if (lw <= 0 || code == 32) return;
        err += (w - lw).abs();
        total += w;
        n++;
      });
      if (n < 6 || total <= 0) continue;
      final score = err / total;
      if (best == null || score < best.$2) best = (m, score);
    }
    return best;
  }
}
