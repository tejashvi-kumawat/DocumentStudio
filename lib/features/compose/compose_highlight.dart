import 'package:document_studio/features/compose/compose_model.dart';
import 'package:flutter/material.dart';

/// Editor controller that colours Markdown / HTML / LaTeX syntax as you
/// type (commands, tags, maths, comments, headings, code).
class ComposeEditingController extends TextEditingController {
  ComposeEditingController({super.text, required this.language});

  ComposeLanguage language;
  bool dark = false;

  static final _rules = <ComposeLanguage, List<(RegExp, int, bool)>>{
    ComposeLanguage.latex: [
      (RegExp(r'(?<!\\)%.*'), 0xFF8B949E, false), // comment
      (
        RegExp(
          r'\$\$[\s\S]*?\$\$|(?<!\\)\$[^$\n]*?\$|\\\[[\s\S]*?\\\]|\\\([\s\S]*?\\\)',
        ),
        0xFF0E7C3A,
        false,
      ),
      (RegExp(r'\\(?:begin|end)\{[^}]*\}'), 0xFF8250DF, true),
      (
        RegExp(
          r'\\(?:part|chapter|section|subsection|subsubsection|paragraph)\*?',
        ),
        0xFFCF222E,
        true,
      ),
      (RegExp(r'\\[A-Za-z@]+\*?|\\.'), 0xFF0550AE, false),
      (RegExp(r'[{}\[\]]'), 0xFF953800, false),
      (RegExp(r'&|\\\\'), 0xFFCF222E, false),
    ],
    ComposeLanguage.markdown: [
      (RegExp(r'^```[\s\S]*?^```', multiLine: true), 0xFF57606A, false),
      (RegExp(r'^#{1,6} .*$', multiLine: true), 0xFFCF222E, true),
      (RegExp(r'\$\$[\s\S]*?\$\$|(?<!\\)\$[^$\n]+?\$'), 0xFF0E7C3A, false),
      (RegExp(r'`[^`\n]+`'), 0xFF57606A, false),
      (RegExp(r'\*\*[^*\n]+\*\*|__[^_\n]+__'), 0xFF1F2328, true),
      (RegExp(r'!?\[[^\]\n]*\]\([^)\n]*\)'), 0xFF0550AE, false),
      (RegExp(r'^\s*(?:[-*+]|\d+\.)\s', multiLine: true), 0xFF953800, true),
      (RegExp(r'^>.*$', multiLine: true), 0xFF6E7781, false),
      (RegExp(r'^\|.*\|\s*$', multiLine: true), 0xFF8250DF, false),
    ],
    ComposeLanguage.html: [
      (RegExp(r'<!--[\s\S]*?-->'), 0xFF8B949E, false),
      (RegExp(r'\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\]'), 0xFF0E7C3A, false),
      (RegExp(r'"[^"\n]*"'), 0xFF0A3069, false),
      (RegExp(r'</?[A-Za-z][A-Za-z0-9-]*|/?>'), 0xFF116329, true),
      (RegExp(r'\s[a-zA-Z-]+(?==)'), 0xFF0550AE, false),
    ],
  };

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final t = text;
    // Very large sources: plain text keeps typing instant.
    if (t.length > 200000) return TextSpan(style: style, text: t);
    final paint = List<(int, bool)?>.filled(t.length, null);
    for (final (re, color, bold) in _rules[language]!) {
      for (final m in re.allMatches(t)) {
        for (var i = m.start; i < m.end; i++) {
          paint[i] ??= (color, bold);
        }
      }
    }
    final spans = <TextSpan>[];
    var i = 0;
    while (i < t.length) {
      final cur = paint[i];
      var j = i + 1;
      while (j < t.length && paint[j] == cur) {
        j++;
      }
      final seg = t.substring(i, j);
      spans.add(
        cur == null
            ? TextSpan(text: seg)
            : TextSpan(
                text: seg,
                style: TextStyle(
                  color: _adapt(cur.$1),
                  fontWeight: cur.$2 ? FontWeight.w700 : null,
                ),
              ),
      );
      i = j;
    }
    return TextSpan(style: style, children: spans);
  }

  /// Lighter variants on a dark editor.
  Color _adapt(int argb) {
    final c = Color(argb);
    if (!dark) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + 0.45).clamp(0.0, 0.85)).toColor();
  }

  /// Inserts [snippet] at the cursor (`$|` = caret, `$SEL` = selection).
  void insertSnippet(String snippet) {
    final sel = selection.isValid
        ? selection
        : TextSelection.collapsed(offset: text.length);
    final selected = sel.textInside(text);
    var ins = snippet.replaceAll(r'$SEL', selected);
    var caret = ins.indexOf(r'$|');
    ins = ins.replaceAll(r'$|', '');
    if (caret < 0) caret = ins.length;
    final next = sel.textBefore(text) + ins + sel.textAfter(text);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: sel.start + caret),
    );
  }

  /// Replaces the [prefixLength] characters before the caret with [snippet].
  void completeWith(int prefixLength, String snippet) {
    final at = selection.baseOffset;
    if (at < prefixLength) return insertSnippet(snippet);
    selection = TextSelection(baseOffset: at - prefixLength, extentOffset: at);
    final s = snippet.replaceAll(r'$SEL', '');
    insertSnippet(s);
  }
}
