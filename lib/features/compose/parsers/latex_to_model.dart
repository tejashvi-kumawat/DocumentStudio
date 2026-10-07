import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/parsers/tikz_subset.dart';

/// Everyday LaTeX → [ComposeDoc], entirely in Dart (no TeX install, no
/// network). Covers the document structure people actually write: title
/// block, numbered sections + table of contents, paragraphs, text styles,
/// sizes and colours, lists, tables (`tabular`), figures with
/// `\includegraphics`, quotes, verbatim / code, footnotes, `\label` /
/// `\ref`, `\newcommand` macros, `\newenvironment`, a TikZ subset,
/// framed boxes, and maths (inline and display: equation, align, gather …)
/// rendered with a KaTeX-compatible engine.
ComposeDoc latexToCompose(String source) {
  // Two passes: the first collects \label targets so \ref resolves.
  final first = _LatexParser(source, const {});
  first.parse();
  final second = _LatexParser(source, first.labels);
  return second.parse();
}

class _LatexParser {
  _LatexParser(this.source, this.knownLabels);

  final String source;
  final Map<String, String> knownLabels;
  final labels = <String, String>{};
  final warnings = <String>{};
  final footnotes = <List<CInline>>[];

  String? title, author, date;
  double fontSize = 11;
  String paper = 'A4';
  bool hasChapters = false;

  // Counters.
  final _sec = [0, 0, 0, 0, 0, 0];
  int _eq = 0, _fig = 0, _tab = 0;
  String _lastLabelTarget = '';

  ComposeDoc parse() {
    var text = _stripComments(source.replaceAll('\r\n', '\n'));
    final begin = text.indexOf(r'\begin{document}');
    var preamble = '';
    if (begin >= 0) {
      preamble = text.substring(0, begin);
      final end = text.indexOf(r'\end{document}', begin);
      text = text.substring(begin + 16, end < 0 ? text.length : end);
    }
    final macros = _macros('$preamble\n$text');
    final envs = _newEnvironments('$preamble\n$text');
    text = _expand(text, macros);
    preamble = _expand(preamble, macros);
    text = _expandEnvironments(text, envs);
    preamble = _expandEnvironments(preamble, envs);
    _preamble(preamble);
    _preamble(text); // \title etc. may sit in the body too
    hasChapters = text.contains(r'\chapter');
    final blocks = _blocks(text, CAlign.left);
    return ComposeDoc(
      blocks: blocks,
      title: title,
      author: author,
      date: date,
      serif: true,
      baseFontSize: fontSize,
      pageSize: paper,
      footnotes: footnotes,
      warnings: warnings.toList(),
    );
  }

  // ------------------------------------------------------------ preamble

  void _preamble(String p) {
    final dc = RegExp(r'\\documentclass(?:\[([^\]]*)\])?\{(\w+)\}')
        .firstMatch(p);
    if (dc != null) {
      final opts = dc.group(1) ?? '';
      final pt = RegExp(r'(\d+)pt').firstMatch(opts);
      if (pt != null) fontSize = double.parse(pt.group(1)!);
      if (opts.contains('letterpaper')) paper = 'Letter';
      if (opts.contains('a5paper')) paper = 'A5';
      if (opts.contains('legalpaper')) paper = 'Legal';
    }
    String? arg(String cmd) {
      final i = p.indexOf('\\$cmd');
      if (i < 0) return null;
      final c = _Cursor(p, i + cmd.length + 1);
      c.skipSpaces();
      if (c.peek == '[') c.readBracket();
      if (c.peek != '{') return null;
      return c.readGroup();
    }

    title ??= arg('title');
    author ??= arg('author');
    date ??= arg('date');
  }

  static String _stripComments(String s) {
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

  /// `\newcommand{\x}[n]{body}`, `\renewcommand`, `\def\x{body}`.
  Map<String, (int, String)> _macros(String s) {
    final out = <String, (int, String)>{};
    final re = RegExp(r'\\(?:re)?newcommand\*?\s*\{?\\([A-Za-z]+)\}?');
    for (final m in re.allMatches(s)) {
      final c = _Cursor(s, m.end);
      c.skipSpaces();
      var n = 0;
      if (c.peek == '[') n = int.tryParse(c.readBracket()) ?? 0;
      c.skipSpaces();
      if (c.peek == '[') c.readBracket(); // default value
      c.skipSpaces();
      if (c.peek != '{') continue;
      out[m.group(1)!] = (n, c.readGroup());
    }
    for (final m in RegExp(r'\\def\\([A-Za-z]+)').allMatches(s)) {
      final c = _Cursor(s, m.end);
      if (c.peek != '{') continue;
      out[m.group(1)!] = (0, c.readGroup());
    }
    return out;
  }

  String _expand(String s, Map<String, (int, String)> macros) {
    if (macros.isEmpty) return s;
    // Drop the definitions themselves.
    s = s.replaceAllMapped(
      RegExp(
        r'\\(?:re)?newcommand\*?\s*\{?\\[A-Za-z]+\}?(\[\d\])?(\[[^\]]*\])?',
      ),
      (_) => '\u0001',
    );
    var out = s;
    for (var round = 0; round < 8; round++) {
      var changed = false;
      for (final e in macros.entries) {
        final re = RegExp('\\\\${e.key}(?![A-Za-z])');
        final buf = StringBuffer();
        var pos = 0;
        for (final m in re.allMatches(out)) {
          if (m.start < pos) continue;
          buf.write(out.substring(pos, m.start));
          final c = _Cursor(out, m.end);
          var body = e.value.$2;
          for (var i = 1; i <= e.value.$1; i++) {
            c.skipSpaces();
            final a = c.peek == '{' ? c.readGroup() : c.readChar();
            body = body.replaceAll('#$i', a);
          }
          buf.write(body);
          pos = c.pos;
          changed = true;
        }
        buf.write(out.substring(pos));
        out = buf.toString();
      }
      if (!changed) break;
    }
    // A removed definition leaves "\u0001{body}" — drop the body group.
    final clean = StringBuffer();
    var i = 0;
    while (i < out.length) {
      if (out[i] == '\u0001') {
        final c = _Cursor(out, i + 1);
        c.skipSpaces();
        if (c.peek == '{') c.readGroup();
        i = c.pos;
        continue;
      }
      clean.write(out[i]);
      i++;
    }
    return clean.toString();
  }

  /// `\newenvironment{name}[n]{begin}{end}` / `\renewenvironment`.
  Map<String, (int arity, String begin, String end)> _newEnvironments(
    String s,
  ) {
    final out = <String, (int, String, String)>{};
    final re = RegExp(r'\\(?:re)?newenvironment\*?\s*\{([A-Za-z*]+)\}');
    for (final m in re.allMatches(s)) {
      final c = _Cursor(s, m.end);
      c.skipSpaces();
      var n = 0;
      if (c.peek == '[') n = int.tryParse(c.readBracket()) ?? 0;
      c.skipSpaces();
      if (c.peek == '[') c.readBracket(); // default
      c.skipSpaces();
      if (c.peek != '{') continue;
      final begin = c.readGroup();
      c.skipSpaces();
      if (c.peek != '{') continue;
      final end = c.readGroup();
      out[m.group(1)!] = (n, begin, end);
    }
    return out;
  }

  /// Rewrite `\begin{name}…\end{name}` using collected newenvironment defs.
  String _expandEnvironments(
    String s,
    Map<String, (int arity, String begin, String end)> envs,
  ) {
    // Drop the definitions themselves.
    s = s.replaceAllMapped(
      RegExp(r'\\(?:re)?newenvironment\*?\s*\{[A-Za-z*]+\}'),
      (_) => '\u0001',
    );
    // Strip trailing [n][default]{begin}{end} after the marker.
    {
      final clean = StringBuffer();
      var i = 0;
      while (i < s.length) {
        if (s[i] == '\u0001') {
          final c = _Cursor(s, i + 1);
          c.skipSpaces();
          if (c.peek == '[') c.readBracket();
          c.skipSpaces();
          if (c.peek == '[') c.readBracket();
          c.skipSpaces();
          if (c.peek == '{') c.readGroup();
          c.skipSpaces();
          if (c.peek == '{') c.readGroup();
          i = c.pos;
          continue;
        }
        clean.write(s[i]);
        i++;
      }
      s = clean.toString();
    }
    if (envs.isEmpty) return s;

    // Built-ins we handle natively — don't expand those away.
    const native = {
      'tikzpicture',
      'tikzpicture*',
      'questionbox',
      'answerbox',
      'tcolorbox',
      'mdframed',
      'framed',
    };

    var out = s;
    for (var round = 0; round < 6; round++) {
      var changed = false;
      for (final e in envs.entries) {
        if (native.contains(e.key)) continue;
        final open = '\\begin{${e.key}}';
        final close = '\\end{${e.key}}';
        final buf = StringBuffer();
        var pos = 0;
        while (true) {
          final start = out.indexOf(open, pos);
          if (start < 0) {
            buf.write(out.substring(pos));
            break;
          }
          buf.write(out.substring(pos, start));
          var i = start + open.length;
          final c = _Cursor(out, i);
          c.skipSpaces();
          if (c.peek == '[') c.readBracket(); // placement / opts
          var begin = e.value.$2;
          var end = e.value.$3;
          for (var a = 1; a <= e.value.$1; a++) {
            c.skipSpaces();
            final arg = c.peek == '{' ? c.readGroup() : '';
            begin = begin.replaceAll('#$a', arg);
            end = end.replaceAll('#$a', arg);
          }
          // Body until matching \end{name}.
          final bodyStart = c.pos;
          var depth = 1;
          var j = bodyStart;
          while (j < out.length) {
            if (out.startsWith(open, j)) {
              depth++;
              j += open.length;
              continue;
            }
            if (out.startsWith(close, j)) {
              depth--;
              if (depth == 0) {
                final body = out.substring(bodyStart, j);
                // Keep TeX tokens from gluing (`\par` + `Remember` → `\parRemember`).
                buf.write(begin);
                if (begin.isNotEmpty &&
                    body.isNotEmpty &&
                    !RegExp(r'\s$').hasMatch(begin) &&
                    !RegExp(r'^\s').hasMatch(body)) {
                  buf.write('\n');
                }
                buf.write(body);
                if (body.isNotEmpty &&
                    end.isNotEmpty &&
                    !RegExp(r'\s$').hasMatch(body) &&
                    !RegExp(r'^\s').hasMatch(end)) {
                  buf.write('\n');
                }
                buf.write(end);
                pos = j + close.length;
                changed = true;
                break;
              }
              j += close.length;
              continue;
            }
            j++;
          }
          if (depth != 0) {
            buf.write(out.substring(start));
            pos = out.length;
            break;
          }
        }
        out = buf.toString();
      }
      if (!changed) break;
    }
    return out;
  }

  // -------------------------------------------------------------- blocks

  static const _sectionLevels = {
    'part': 0,
    'chapter': 0,
    'section': 1,
    'subsection': 2,
    'subsubsection': 3,
    'paragraph': 4,
    'subparagraph': 5,
  };

  List<CBlock> _blocks(String src, CAlign align) {
    final out = <CBlock>[];
    final para = StringBuffer();
    var noIndent = true; // first paragraph after a heading is flush
    var forceNoIndent = false;

    void flush() {
      final t = para.toString();
      para.clear();
      if (t.trim().isEmpty) return;
      final inl = _inlines(t, const CStyle());
      if (inl.every(
        (i) => i.math == null && !i.lineBreak && i.text.trim().isEmpty,
      )) {
        return;
      }
      out.add(
        CPara(
          _trim(inl),
          align: align,
          indent: !noIndent && !forceNoIndent && align == CAlign.left,
        ),
      );
      noIndent = false;
      forceNoIndent = false;
    }

    final c = _Cursor(src, 0);
    while (!c.done) {
      final ch = c.peek;
      // Blank line = paragraph break.
      if (ch == '\n') {
        final save = c.pos;
        c.pos++;
        var blank = false;
        while (!c.done && (c.peek == ' ' || c.peek == '\t' || c.peek == '\n')) {
          if (c.peek == '\n') blank = true;
          c.pos++;
        }
        if (blank) {
          flush();
        } else {
          para.write(' ');
        }
        if (c.pos == save) c.pos++;
        continue;
      }
      if (ch == r'$' && c.peekAt(1) == r'$') {
        flush();
        c.pos += 2;
        final end = src.indexOf(r'$$', c.pos);
        final e = end < 0 ? src.length : end;
        out.add(CMath(src.substring(c.pos, e).trim()));
        c.pos = (end < 0 ? src.length : end + 2);
        continue;
      }
      if (ch != r'\') {
        para.write(ch);
        c.pos++;
        continue;
      }
      // Commands.
      if (c.peekAt(1) == '[') {
        flush();
        c.pos += 2;
        final end = src.indexOf(r'\]', c.pos);
        final e = end < 0 ? src.length : end;
        out.add(_displayMath(src.substring(c.pos, e), numbered: false));
        c.pos = end < 0 ? src.length : end + 2;
        continue;
      }
      final start = c.pos;
      final name = c.readCommandName();
      switch (name) {
        case 'begin':
          c.skipSpaces();
          final env = c.readGroup();
          // Float placement / list options: [h], [htbp], [label=…].
          if (const {
                'figure',
                'figure*',
                'table',
                'table*',
                'itemize',
                'enumerate',
                'description',
                'lstlisting',
                'minipage',
                'tikzpicture',
                'tikzpicture*',
                'tcolorbox',
                'mdframed',
                'framed',
                'questionbox',
                'answerbox',
              }.contains(env) &&
              c.peek == '[') {
            c.readBracket();
          }
          if (env == 'wrapfigure') {
            if (c.peek == '[') c.readBracket();
            if (c.peek == '{') c.readGroup();
            if (c.peek == '{') c.readGroup();
          }
          final body = c.readUntilEnd(env);
          final isBlock = !const {'math', 'displaymath*'}.contains(env);
          if (isBlock) flush();
          out.addAll(_environment(env, body, align));
          noIndent = env != 'math';
        case final n when _sectionLevels.containsKey(n):
          flush();
          final star = c.peek == '*';
          if (star) c.pos++;
          c.skipSpaces();
          if (c.peek == '[') c.readBracket();
          c.skipSpaces();
          final heading = c.peek == '{' ? c.readGroup() : '';
          out.add(_heading(n, heading, numbered: !star));
          noIndent = true;
        case 'maketitle':
          flush();
          out.add(const CTitleBlock());
          noIndent = true;
        case 'tableofcontents':
          flush();
          out.add(const CToc());
        case 'newpage' || 'clearpage' || 'pagebreak' || 'cleardoublepage':
          flush();
          if (c.peek == '[') c.readBracket();
          out.add(const CPageBreak());
          noIndent = true;
        case 'vspace' || 'vspace*':
          flush();
          if (c.peek == '*') c.pos++;
          final v = c.readGroup();
          out.add(CSpace(_lengthPt(v, fontSize)));
        case 'vfill' || 'vfill*':
          flush();
          if (c.peek == '*') c.pos++;
          // Approximate TeX glue: leave room for exam answer space.
          out.add(CSpace(fontSize * 8));
        case 'bigskip':
          flush();
          out.add(CSpace(fontSize));
        case 'medskip':
          flush();
          out.add(CSpace(fontSize * 0.5));
        case 'smallskip':
          flush();
          out.add(CSpace(fontSize * 0.25));
        case 'hrule' || 'hline' || 'rule':
          flush();
          if (name == 'rule') {
            if (c.peek == '[') c.readBracket();
            if (c.peek == '{') c.readGroup();
            if (c.peek == '{') c.readGroup();
          }
          out.add(const CRule());
        case 'noindent':
          forceNoIndent = true;
        case 'par':
          flush();
        case 'centering' || 'raggedright' || 'raggedleft':
          break; // handled by the enclosing environment
        case 'title' ||
            'author' ||
            'date' ||
            'documentclass' ||
            'usepackage' ||
            'geometry' ||
            'pagestyle' ||
            'thispagestyle' ||
            'setlength' ||
            'bibliographystyle' ||
            'graphicspath' ||
            'hypersetup' ||
            'setcounter' ||
            'linespread' ||
            'definecolor' ||
            'newtheorem':
          // Consume arguments.
          c.skipSpaces();
          if (c.peek == '[') c.readBracket();
          c.skipSpaces();
          var args =
              name == 'setlength' ||
                  name == 'setcounter' ||
                  name == 'newtheorem'
              ? 2
              : 1;
          if (name == 'definecolor') args = 3;
          for (var i = 0; i < args; i++) {
            c.skipSpaces();
            if (c.peek == '{') c.readGroup();
          }
        case 'item':
          // Stray \item outside a list: treat as a bullet paragraph.
          flush();
          para.write('• ');
        default:
          // Inline command: keep it in the paragraph text.
          para.write(src.substring(start, c.pos));
      }
    }
    flush();
    return out;
  }

  CHeading _heading(String cmd, String text, {required bool numbered}) {
    var level = _sectionLevels[cmd]!;
    if (!hasChapters && level >= 1) {
      // article: section is the top level
    } else if (hasChapters) {
      level = cmd == 'chapter' ? 1 : level + 1;
    }
    level = level.clamp(1, 6);
    String? number;
    if (numbered &&
        cmd != 'paragraph' &&
        cmd != 'subparagraph' &&
        cmd != 'part') {
      _sec[level - 1]++;
      for (var i = level; i < _sec.length; i++) {
        _sec[i] = 0;
      }
      number = [for (var i = 0; i < level; i++) _sec[i]].join('.');
      _lastLabelTarget = number;
    }
    return CHeading(
      level,
      _trim(_inlines(text, const CStyle())),
      number: number,
    );
  }

  CMath _displayMath(String tex, {required bool numbered, String wrap = ''}) {
    var t = tex;
    // \label inside the maths.
    String? label;
    t = t.replaceAllMapped(RegExp(r'\\label\{([^}]*)\}'), (m) {
      label = m.group(1);
      return '';
    });
    final noNumber = t.contains(r'\nonumber') || t.contains(r'\notag');
    t = t.replaceAll(r'\nonumber', '').replaceAll(r'\notag', '');
    String? number;
    if (numbered && !noNumber) {
      _eq++;
      number = '($_eq)';
      if (label != null) labels[label!] = '$_eq';
    }
    if (wrap.isNotEmpty) t = '\\begin{$wrap}$t\\end{$wrap}';
    return CMath(t.trim(), number: number);
  }

  List<CBlock> _environment(String env, String body, CAlign align) {
    switch (env) {
      case 'itemize' || 'enumerate' || 'description':
        return [_list(env, body)];
      case 'equation' || 'displaymath' || 'math':
        return [_displayMath(body, numbered: env == 'equation')];
      case 'equation*':
        return [_displayMath(body, numbered: false)];
      case 'align' || 'eqnarray' || 'flalign':
        return [_displayMath(body, numbered: true, wrap: 'aligned')];
      case 'align*' || 'eqnarray*' || 'flalign*' || 'alignat' || 'alignat*':
        return [_displayMath(body, numbered: false, wrap: 'aligned')];
      case 'gather' || 'multline':
        return [_displayMath(body, numbered: true, wrap: 'gathered')];
      case 'gather*' || 'multline*':
        return [_displayMath(body, numbered: false, wrap: 'gathered')];
      case 'center':
        return _blocks(body, CAlign.center);
      case 'flushleft':
        return _blocks(body, CAlign.left);
      case 'flushright':
        return _blocks(body, CAlign.right);
      case 'quote' || 'quotation' || 'verse':
        return [CQuote(_blocks(body, CAlign.left))];
      case 'verbatim' || 'verbatim*' || 'lstlisting' || 'Verbatim':
        var b = body;
        if (b.startsWith('[')) b = b.substring(b.indexOf(']') + 1);
        return [CCode(b.replaceFirst(RegExp(r'^\n'), '').trimRight())];
      case 'minted':
        final c = _Cursor(body, 0);
        if (c.peek == '[') c.readBracket();
        final lang = c.peek == '{' ? c.readGroup() : null;
        return [
          CCode(
            body.substring(c.pos).replaceFirst(RegExp(r'^\n'), '').trimRight(),
            language: lang,
          ),
        ];
      case 'abstract':
        return [CAbstract(_blocks(body, CAlign.justify))];
      case 'tikzpicture' || 'tikzpicture*':
        // Optional [options] before path body.
        var b = body;
        if (b.trimLeft().startsWith('[')) {
          final c = _Cursor(b.trimLeft(), 0);
          c.readBracket();
          b = b.trimLeft().substring(c.pos);
        }
        return [parseTikzSubset(b)];
      case 'questionbox' ||
          'answerbox' ||
          'tcolorbox' ||
          'mdframed' ||
          'framed':
        return [_boxEnv(env, body)];
      case 'figure' || 'figure*' || 'wrapfigure':
        return _figure(body);
      case 'table' || 'table*':
        return _tableFloat(body);
      case 'tabular' || 'tabular*' || 'tabularx' || 'longtable' || 'array':
        return [_tabular(env, body)];
      case 'titlepage' ||
          'minipage' ||
          'document' ||
          'small' ||
          'footnotesize' ||
          'large' ||
          'Large' ||
          'huge' ||
          'theorem' ||
          'lemma' ||
          'proof' ||
          'definition' ||
          'example' ||
          'remark' ||
          'corollary':
        var b = body;
        // minipage / wrapfigure width argument.
        if (env == 'minipage') {
          final c = _Cursor(b, 0);
          if (c.peek == '[') c.readBracket();
          if (c.peek == '{') c.readGroup();
          b = b.substring(c.pos);
        }
        final inner = _blocks(b, align);
        const theorems = {
          'theorem',
          'lemma',
          'definition',
          'example',
          'remark',
          'corollary',
          'proof',
        };
        if (theorems.contains(env) &&
            inner.isNotEmpty &&
            inner.first is CPara) {
          final p0 = inner.first as CPara;
          final head = env == 'proof'
              ? 'Proof. '
              : '${env[0].toUpperCase()}${env.substring(1)}. ';
          inner[0] = CPara([
            CInline(head, bold: env != 'proof', italic: env == 'proof'),
            ...p0.inlines,
          ]);
          if (env == 'proof') {
            inner.add(const CPara([CInline('∎')], align: CAlign.right));
          }
        }
        return inner;
      default:
        warnings.add('\\begin{$env}');
        return _blocks(body, align);
    }
  }

  CBox _boxEnv(String env, String body) {
    var b = body;
    // Drop optional [title/options] / {title}.
    final c = _Cursor(b, 0);
    c.skipSpaces();
    String? title;
    if (c.peek == '[') {
      final opt = c.readBracket();
      final tm = RegExp(r'title\s*=\s*\{?([^,\}\]]+)').firstMatch(opt);
      if (tm != null) title = tm.group(1)!.trim();
      b = b.substring(c.pos);
    } else if (c.peek == '{') {
      title = c.readGroup();
      b = b.substring(c.pos);
    }
    title ??= switch (env) {
      'questionbox' => 'Question',
      'answerbox' => 'Answer',
      _ => null,
    };
    final (border, fill) = switch (env) {
      'questionbox' => (0xFF1565C0, 0xFFE3F2FD),
      'answerbox' => (0xFF2E7D32, 0xFFE8F5E9),
      _ => (0xFF757575, 0xFFF5F5F5),
    };
    return CBox(
      _blocks(b, CAlign.left),
      title: title,
      borderColor: border,
      fillColor: fill,
    );
  }

  CList _list(String env, String body) {
    final items = <List<CBlock>>[];
    final labels = <List<CInline>?>[];
    for (final (label, content) in _splitItems(body)) {
      labels.add(
        label == null
            ? null
            : _inlines(
                label,
                env == 'description'
                    ? const CStyle(bold: true)
                    : const CStyle(),
              ),
      );
      items.add(_blocks(content, CAlign.left));
    }
    final anyLabel = labels.any((l) => l != null);
    return CList(
      items,
      ordered: env == 'enumerate',
      labels: anyLabel ? labels : null,
    );
  }

  /// Splits on top-level `\item` (groups and nested environments skipped).
  List<(String?, String)> _splitItems(String body) {
    final out = <(String?, String)>[];
    final c = _Cursor(body, 0);
    String? label;
    var start = -1;
    var depth = 0;
    while (!c.done) {
      if (c.startsWith(r'\begin{')) {
        depth++;
        c.pos += 7;
        continue;
      }
      if (c.startsWith(r'\end{')) {
        depth--;
        c.pos += 5;
        continue;
      }
      if (depth == 0 &&
          c.startsWith(r'\item') &&
          !RegExp('[A-Za-z]').hasMatch(c.peekAt(5) ?? ' ')) {
        if (start >= 0) out.add((label, body.substring(start, c.pos)));
        c.pos += 5;
        c.skipSpaces();
        label = c.peek == '[' ? c.readBracket() : null;
        start = c.pos;
        continue;
      }
      if (c.peek == '{') {
        c.readGroup();
        continue;
      }
      c.pos++;
    }
    if (start >= 0) out.add((label, body.substring(start)));
    return out;
  }

  List<CBlock> _figure(String body) {
    final out = <CBlock>[];
    final img = RegExp(r'\\includegraphics\s*(?:\[([^\]]*)\])?\s*\{([^}]*)\}')
        .firstMatch(body);
    final cap = _command(body, 'caption');
    final label = RegExp(r'\\label\{([^}]*)\}').firstMatch(body)?.group(1);
    if (cap != null || img != null) {
      _fig++;
      if (label != null) labels[label] = '$_fig';
    }
    if (img != null) {
      out.add(
        CImage(
          img.group(2)!.trim(),
          widthFraction: _widthFraction(img.group(1)),
          caption: cap == null
              ? null
              : [
                  CInline('Figure $_fig: ', bold: true),
                  ..._inlines(cap, const CStyle()),
                ],
        ),
      );
    }
    // A tabular inside a figure.
    if (body.contains(r'\begin{tabular')) {
      out.addAll(
        _blocks(_withoutFloatCommands(body), CAlign.center).whereType<CTable>(),
      );
    }
    return out;
  }

  List<CBlock> _tableFloat(String body) {
    final cap = _command(body, 'caption');
    final label = RegExp(r'\\label\{([^}]*)\}').firstMatch(body)?.group(1);
    _tab++;
    if (label != null) labels[label] = '$_tab';
    final inner = _blocks(_withoutFloatCommands(body), CAlign.center);
    final caption = cap == null
        ? null
        : [
            CInline('Table $_tab: ', bold: true),
            ..._inlines(cap, const CStyle()),
          ];
    return [
      for (final b in inner)
        if (b is CTable)
          CTable(b.rows, header: b.header, aligns: b.aligns, caption: caption)
        else
          b,
    ];
  }

  String _withoutFloatCommands(String body) => body
      .replaceAll(RegExp(r'\\caption\s*\{(?:[^{}]|\{[^{}]*\})*\}'), '')
      .replaceAll(RegExp(r'\\label\{[^}]*\}'), '')
      .replaceAll(
        RegExp(r'\\includegraphics\s*(?:\[[^\]]*\])?\s*\{[^}]*\}'),
        '',
      )
      .replaceAll(r'\centering', '');

  CTable _tabular(String env, String body) {
    final c = _Cursor(body, 0);
    c.skipSpaces();
    if (env == 'tabular*' || env == 'tabularx') {
      if (c.peek == '{') c.readGroup(); // width
    }
    if (c.peek == '[') c.readBracket();
    c.skipSpaces();
    final spec = c.peek == '{' ? c.readGroup() : '';
    final aligns = <CAlign>[];
    final sc = _Cursor(spec, 0);
    while (!sc.done) {
      final ch = sc.peek!;
      switch (ch) {
        case 'l':
          aligns.add(CAlign.left);
        case 'c':
          aligns.add(CAlign.center);
        case 'r':
          aligns.add(CAlign.right);
        case 'p' || 'm' || 'b' || 'X':
          aligns.add(CAlign.left);
          sc.pos++;
          if (sc.peek == '{') sc.readGroup();
          continue;
        case '@' || '>' || '<':
          sc.pos++;
          if (sc.peek == '{') sc.readGroup();
          continue;
      }
      sc.pos++;
    }
    final rest = body.substring(c.pos);
    var header = false;
    final rows = <List<List<CInline>>>[];
    final rawRows = _splitTop(rest, r'\\');
    for (var i = 0; i < rawRows.length; i++) {
      var r = rawRows[i];
      if (r.startsWith('[')) r = r.substring(r.indexOf(']') + 1);
      final hadRule =
          RegExp(r'\\(midrule|hline)').hasMatch(r.split('&').first) &&
          rows.length == 1;
      if (hadRule) header = true;
      r = r
          .replaceAll(
            RegExp(
              r'\\(hline|toprule|midrule|bottomrule|endhead|endfirsthead)',
            ),
            '',
          )
          .replaceAll(RegExp(r'\\cline\{[^}]*\}'), '')
          .replaceAll(RegExp(r'\\cmidrule(\([^)]*\))?\{[^}]*\}'), '');
      if (r.trim().isEmpty) continue;
      final cells = _splitTop(r, '&').map((cell) {
        final mc = RegExp(
          r'\\multicolumn\{\d+\}\{[^}]*\}\{(.*)\}\s*$',
          dotAll: true,
        ).firstMatch(cell.trim());
        return _trim(_inlines(mc?.group(1) ?? cell, const CStyle()));
      }).toList();
      rows.add(cells);
    }
    if (rest.contains(r'\toprule')) header = true;
    return CTable(rows, header: header, aligns: aligns);
  }

  /// Splits [s] on [sep] outside groups / environments.
  List<String> _splitTop(String s, String sep) {
    final out = <String>[];
    var depth = 0;
    var start = 0;
    var i = 0;
    while (i < s.length) {
      final ch = s[i];
      if (ch == r'\' && i + 1 < s.length && sep != r'\\' && s[i + 1] == '&') {
        i += 2; // escaped \&
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      if (depth == 0 && s.startsWith(sep, i)) {
        if (sep == r'\\' || (i == 0 || s[i - 1] != r'\')) {
          out.add(s.substring(start, i));
          i += sep.length;
          start = i;
          continue;
        }
      }
      i++;
    }
    out.add(s.substring(start));
    return out;
  }

  String? _command(String s, String name) {
    final i = s.indexOf('\\$name');
    if (i < 0) return null;
    final c = _Cursor(s, i + name.length + 1);
    if (c.peek == '*') c.pos++;
    c.skipSpaces();
    if (c.peek == '[') c.readBracket();
    c.skipSpaces();
    return c.peek == '{' ? c.readGroup() : null;
  }

  static double? _widthFraction(String? opts) {
    if (opts == null) return null;
    final w = RegExp(
      r'width\s*=\s*([\d.]*)\s*\\(?:textwidth|linewidth|columnwidth)',
    ).firstMatch(opts);
    if (w != null) {
      return double.tryParse(w.group(1)!.isEmpty ? '1' : w.group(1)!);
    }
    final sc = RegExp(r'scale\s*=\s*([\d.]+)').firstMatch(opts);
    if (sc != null) return (double.parse(sc.group(1)!)).clamp(0.05, 1.0);
    final abs = RegExp(r'width\s*=\s*([\d.]+)\s*(cm|mm|in|pt)')
        .firstMatch(opts);
    if (abs != null) {
      final v = double.parse(abs.group(1)!);
      final pt = switch (abs.group(2)) {
        'cm' => v * 28.35,
        'mm' => v * 2.835,
        'in' => v * 72,
        _ => v,
      };
      return (pt / 455).clamp(0.05, 1.0);
    }
    return null;
  }

  static double _lengthPt(String v, double em) {
    final m = RegExp(r'(-?[\d.]+)\s*(pt|mm|cm|in|em|ex)?').firstMatch(v);
    if (m == null) return em;
    final n = double.tryParse(m.group(1)!) ?? 1;
    return switch (m.group(2)) {
      'mm' => n * 2.835,
      'cm' => n * 28.35,
      'in' => n * 72,
      'em' => n * em,
      'ex' => n * em * 0.45,
      _ => n,
    };
  }

  // ------------------------------------------------------------- inlines

  static const _sizes = {
    'tiny': 0.5,
    'scriptsize': 0.7,
    'footnotesize': 0.8,
    'small': 0.9,
    'normalsize': 1.0,
    'large': 1.2,
    'Large': 1.44,
    'LARGE': 1.73,
    'huge': 2.07,
    'Huge': 2.49,
  };

  static const _symbols = {
    'LaTeX': 'LaTeX',
    'TeX': 'TeX',
    'ldots': '…',
    'dots': '…',
    'textellipsis': '…',
    'S': '§',
    'P': '¶',
    'copyright': '©',
    'textregistered': '®',
    'texttrademark': '™',
    'textbackslash': r'\',
    'textasciitilde': '~',
    'textasciicircum': '^',
    'textbar': '|',
    'textless': '<',
    'textgreater': '>',
    'textbullet': '•',
    'textdegree': '°',
    'pounds': '£',
    'euro': '€',
    'textendash': '–',
    'textemdash': '—',
    'ss': 'ß',
    'ae': 'æ',
    'AE': 'Æ',
    'oe': 'œ',
    'OE': 'Œ',
    'o': 'ø',
    'O': 'Ø',
    'aa': 'å',
    'AA': 'Å',
    'l': 'ł',
    'L': 'Ł',
    'i': 'ı',
    'quad': '\u2003',
    'qquad': '\u2003\u2003',
    'enspace': '\u2002',
    'thinspace': '\u2009',
    'hfill': '\u0002', // right-aligns the rest of the line (renderer)
    'dag': '†',
    'ddag': '‡',
    'checkmark': '✓',
  };

  static const _accents = {
    "'": {
      'a': 'á',
      'e': 'é',
      'i': 'í',
      'o': 'ó',
      'u': 'ú',
      'y': 'ý',
      'A': 'Á',
      'E': 'É',
      'I': 'Í',
      'O': 'Ó',
      'U': 'Ú',
      'c': 'ć',
      'n': 'ń',
      's': 'ś',
      'z': 'ź',
    },
    '`': {
      'a': 'à',
      'e': 'è',
      'i': 'ì',
      'o': 'ò',
      'u': 'ù',
      'A': 'À',
      'E': 'È',
      'O': 'Ò',
      'U': 'Ù',
    },
    '"': {
      'a': 'ä',
      'e': 'ë',
      'i': 'ï',
      'o': 'ö',
      'u': 'ü',
      'y': 'ÿ',
      'A': 'Ä',
      'E': 'Ë',
      'O': 'Ö',
      'U': 'Ü',
    },
    '^': {
      'a': 'â',
      'e': 'ê',
      'i': 'î',
      'o': 'ô',
      'u': 'û',
      'A': 'Â',
      'E': 'Ê',
      'O': 'Ô',
      'U': 'Û',
    },
    '~': {'a': 'ã', 'n': 'ñ', 'o': 'õ', 'A': 'Ã', 'N': 'Ñ', 'O': 'Õ'},
    'c': {'c': 'ç', 'C': 'Ç', 's': 'ş'},
    'v': {
      'c': 'č',
      's': 'š',
      'z': 'ž',
      'r': 'ř',
      'e': 'ě',
      'C': 'Č',
      'S': 'Š',
      'Z': 'Ž',
    },
    '=': {'a': 'ā', 'e': 'ē', 'i': 'ī', 'o': 'ō', 'u': 'ū'},
    '.': {'z': 'ż', 'Z': 'Ż'},
  };

  List<CInline> _inlines(String src, CStyle start) {
    final out = <CInline>[];
    var s = start;
    final buf = StringBuffer();
    void emit() {
      if (buf.isEmpty) return;
      out.add(s.run(_typography(buf.toString())));
      buf.clear();
    }

    final c = _Cursor(src, 0);
    while (!c.done) {
      final ch = c.peek!;
      if (ch == '{') {
        emit();
        out.addAll(_inlines(c.readGroup(), s));
        continue;
      }
      if (ch == '}') {
        c.pos++;
        continue;
      }
      if (ch == r'$') {
        emit();
        final dbl = c.peekAt(1) == r'$';
        c.pos += dbl ? 2 : 1;
        final end = src.indexOf(dbl ? r'$$' : r'$', c.pos);
        final e = end < 0 ? src.length : end;
        out.add(CInline('', math: src.substring(c.pos, e)));
        c.pos = end < 0 ? src.length : end + (dbl ? 2 : 1);
        continue;
      }
      if (ch == '~') {
        buf.write('\u00A0');
        c.pos++;
        continue;
      }
      if (ch == '\n' || ch == '\t') {
        buf.write(' ');
        c.pos++;
        continue;
      }
      if (ch != r'\') {
        buf.write(ch);
        c.pos++;
        continue;
      }
      // Backslash forms.
      final next = c.peekAt(1);
      if (next == r'\') {
        emit();
        c.pos += 2;
        if (c.peek == '*') c.pos++;
        if (c.peek == '[') c.readBracket();
        out.add(const CInline('', lineBreak: true));
        continue;
      }
      if (next == '(') {
        emit();
        c.pos += 2;
        final end = src.indexOf(r'\)', c.pos);
        final e = end < 0 ? src.length : end;
        out.add(CInline('', math: src.substring(c.pos, e)));
        c.pos = end < 0 ? src.length : end + 2;
        continue;
      }
      if (next != null && r'&%$#_{}'.contains(next)) {
        buf.write(next);
        c.pos += 2;
        continue;
      }
      if (next == ' ' ||
          next == ',' ||
          next == ';' ||
          next == '!' ||
          next == '/' ||
          next == '@') {
        buf.write(next == ' ' ? ' ' : (next == ',' ? '\u2009' : ''));
        c.pos += 2;
        continue;
      }
      if (next == '-') {
        c.pos += 2; // discretionary hyphen
        continue;
      }
      final symbolAccent =
          next != null &&
          _accents.containsKey(next) &&
          !RegExp('[A-Za-z]').hasMatch(next);
      final letterAccent = (next == 'c' || next == 'v') && c.peekAt(2) == '{';
      if (symbolAccent || letterAccent) {
        c.pos += 2;
        final letter = c.peek == '{' ? c.readGroup() : c.readChar();
        buf.write(_accents[next]?[letter.trim()] ?? letter);
        continue;
      }
      final name = c.readCommandName();
      String arg() {
        c.skipSpaces();
        if (c.peek == '[') c.readBracket();
        c.skipSpaces();
        return c.peek == '{' ? c.readGroup() : (c.done ? '' : c.readChar());
      }

      switch (name) {
        case 'textbf' || 'mathbf':
          emit();
          out.addAll(_inlines(arg(), s.copyWith(bold: true)));
        case 'textit' || 'emph' || 'textsl' || 'mathit':
          emit();
          out.addAll(
            _inlines(arg(), s.copyWith(italic: !s.italic || name != 'emph')),
          );
        case 'underline' || 'uline':
          emit();
          out.addAll(_inlines(arg(), s.copyWith(underline: true)));
        case 'sout' || 'st':
          emit();
          out.addAll(_inlines(arg(), s.copyWith(strike: true)));
        case 'texttt' || 'verb':
          emit();
          if (name == 'verb') {
            final delim = c.readChar();
            final end = src.indexOf(delim, c.pos);
            final e = end < 0 ? src.length : end;
            out.add(s.copyWith(code: true).run(src.substring(c.pos, e)));
            c.pos = end < 0 ? src.length : end + 1;
          } else {
            out.addAll(_inlines(arg(), s.copyWith(code: true)));
          }
        case 'textsc':
          emit();
          out.addAll(_inlines(arg(), s.copyWith(smallCaps: true)));
        case 'textrm' ||
            'textsf' ||
            'textup' ||
            'textnormal' ||
            'mbox' ||
            'hbox' ||
            'text' ||
            'makebox' ||
            'fbox' ||
            'framebox' ||
            'colorbox' ||
            'boxed':
          emit();
          if (name == 'colorbox') arg();
          out.addAll(_inlines(arg(), s));
        case 'textsuperscript':
          emit();
          out.addAll(
            _inlines(arg(), s.copyWith(superscript: true, scale: s.scale)),
          );
        case 'textsubscript':
          emit();
          out.addAll(_inlines(arg(), s.copyWith(subscript: true)));
        case 'textcolor':
          emit();
          final col = parseComposeColor(arg());
          out.addAll(_inlines(arg(), s.copyWith(color: col)));
        case 'color':
          emit();
          s = s.copyWith(color: parseComposeColor(arg()));
        case 'href':
          emit();
          final url = arg();
          out.addAll(_inlines(arg(), s.copyWith(link: url, color: 0xFF0B57D0)));
        case 'url' || 'nolinkurl':
          emit();
          final url = arg();
          out.add(
            s.copyWith(link: url, code: true, color: 0xFF0B57D0).run(url),
          );
        case 'footnote':
          emit();
          footnotes.add(_trim(_inlines(arg(), const CStyle())));
          out.add(s.copyWith(superscript: true).run('${footnotes.length}'));
        case 'cite' || 'citep' || 'citet':
          emit();
          out.add(s.run('[${arg()}]'));
        case 'ref' || 'eqref' || 'pageref' || 'autoref' || 'cref' || 'Cref':
          emit();
          final key = arg();
          final v = knownLabels[key] ?? '??';
          out.add(s.run(name == 'eqref' ? '($v)' : v));
        case 'label':
          final key = arg();
          if (_lastLabelTarget.isNotEmpty) labels[key] = _lastLabelTarget;
        case 'today':
          emit();
          final d = DateTime.now();
          const months = [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
          buf.write('${months[d.month - 1]} ${d.day}, ${d.year}');
        case 'bfseries':
          emit();
          s = s.copyWith(bold: true);
        case 'itshape' || 'em' || 'slshape':
          emit();
          s = s.copyWith(italic: true);
        case 'ttfamily':
          emit();
          s = s.copyWith(code: true);
        case 'scshape':
          emit();
          s = s.copyWith(smallCaps: true);
        case 'normalfont' ||
            'rmfamily' ||
            'sffamily' ||
            'upshape' ||
            'mdseries':
          emit();
          s = CStyle(color: s.color, scale: s.scale);
        case final n when _sizes.containsKey(n):
          emit();
          s = s.copyWith(scale: _sizes[n]);
        case final n when _symbols.containsKey(n):
          buf.write(_symbols[n]);
          if (c.peek == '{' && c.peekAt(1) == '}') c.pos += 2;
        case 'newline' || 'linebreak':
          emit();
          out.add(const CInline('', lineBreak: true));
        case 'hspace' ||
            'hspace*' ||
            'vspace' ||
            'vspace*' ||
            'vfill' ||
            'vfill*' ||
            'phantom' ||
            'index' ||
            'nocite' ||
            'thanks' ||
            'centering' ||
            'raggedright' ||
            'raggedleft' ||
            'noindent' ||
            'protect' ||
            'nolinebreak' ||
            'allowbreak' ||
            'smallskip' ||
            'medskip' ||
            'bigskip' ||
            'par' ||
            'relax' ||
            'ignorespaces' ||
            'unskip' ||
            'textwidth' ||
            'linewidth' ||
            'columnwidth' ||
            'fill' ||
            'stretch':
          if (c.peek == '*') c.pos++;
          if (const {
            'hspace',
            'vspace',
            'phantom',
            'index',
            'nocite',
            'thanks',
          }.contains(name)) {
            final a = arg();
            if (name == 'hspace') {
              buf.write(_lengthPt(a, 10) > 8 ? '\u2003' : ' ');
            }
          }
          if (name == 'vfill' || name == 'vfill*') {
            // Inline stray \vfill: treat as a paragraph break via space.
            buf.write('\n\n');
          }
          if (name == 'thanks') {
            // keep footnote-ish thanks out of the title text
          }
        case 'and':
          buf.write('\u2003·\u2003');
        case 'item':
          emit();
          buf.write('• ');
        case '':
          c.pos++;
        default:
          warnings.add('\\$name');
          emit();
          if (c.peek == '{') out.addAll(_inlines(c.readGroup(), s));
      }
    }
    emit();
    return out;
  }

  /// TeX ligature conventions: -- – , --- — , `` “ , '' ” , ` ‘ , ' ’.
  static String _typography(String t) => t
      .replaceAll('---', '—')
      .replaceAll('--', '–')
      .replaceAll('``', '“')
      .replaceAll("''", '”')
      .replaceAll('`', '‘')
      .replaceAll("'", '’')
      .replaceAll(RegExp(r' {2,}'), ' ');

  static List<CInline> _trim(List<CInline> l) {
    final out = [...l];
    while (out.isNotEmpty &&
        out.first.math == null &&
        !out.first.lineBreak &&
        out.first.text.trim().isEmpty) {
      out.removeAt(0);
    }
    while (out.isNotEmpty &&
        (out.last.lineBreak ||
            (out.last.math == null && out.last.text.trim().isEmpty))) {
      out.removeLast();
    }
    if (out.isNotEmpty && out.first.math == null) {
      out[0] = out.first.copyWith(text: out.first.text.trimLeft());
    }
    if (out.isNotEmpty && out.last.math == null) {
      out[out.length - 1] = out.last.copyWith(text: out.last.text.trimRight());
    }
    return out;
  }
}

/// Character cursor with TeX-aware reading helpers.
class _Cursor {
  _Cursor(this.s, this.pos);
  final String s;
  int pos;

  bool get done => pos >= s.length;
  String? get peek => done ? null : s[pos];
  String? peekAt(int o) => pos + o < s.length ? s[pos + o] : null;
  bool startsWith(String t) => s.startsWith(t, pos);

  String readChar() => done ? '' : s[pos++];

  void skipSpaces() {
    while (!done && (s[pos] == ' ' || s[pos] == '\n' || s[pos] == '\t')) {
      pos++;
    }
  }

  /// After a backslash: letters, or one symbol.
  String readCommandName() {
    pos++; // the backslash
    final start = pos;
    while (!done && RegExp('[A-Za-z]').hasMatch(s[pos])) {
      pos++;
    }
    if (pos == start && !done) pos++;
    final name = s.substring(start, pos);
    // A space after a letter command is swallowed (TeX rule).
    if (RegExp(r'^[A-Za-z]+$').hasMatch(name)) {
      while (!done && s[pos] == ' ') {
        pos++;
      }
    }
    return name;
  }

  /// `{…}` with nesting; returns the inside.
  String readGroup() {
    if (peek != '{') return '';
    var depth = 0;
    final start = pos + 1;
    while (!done) {
      final ch = s[pos];
      if (ch == r'\') {
        pos += 2;
        continue;
      }
      if (ch == '{') depth++;
      if (ch == '}') {
        depth--;
        if (depth == 0) {
          pos++;
          return s.substring(start, pos - 1);
        }
      }
      pos++;
    }
    return s.substring(start);
  }

  /// `[…]`; returns the inside.
  String readBracket() {
    if (peek != '[') return '';
    var depth = 0;
    final start = pos + 1;
    while (!done) {
      final ch = s[pos];
      if (ch == '{') depth++;
      if (ch == '}') depth--;
      if (ch == ']' && depth == 0) {
        pos++;
        return s.substring(start, pos - 1);
      }
      pos++;
    }
    return s.substring(start);
  }

  /// Body up to the matching `\end{env}` (nested same-name envs counted).
  String readUntilEnd(String env) {
    final open = '\\begin{$env}';
    final close = '\\end{$env}';
    var depth = 1;
    final start = pos;
    while (!done) {
      if (s.startsWith(open, pos)) {
        depth++;
        pos += open.length;
        continue;
      }
      if (s.startsWith(close, pos)) {
        depth--;
        if (depth == 0) {
          final body = s.substring(start, pos);
          pos += close.length;
          return body;
        }
        pos += close.length;
        continue;
      }
      pos++;
    }
    return s.substring(start);
  }
}
