import 'package:document_studio/features/compose/compose_model.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// HTML (+ inline `style` for colour, size, weight, alignment, and
/// `\( … \)` / `\[ … \]` math) → [ComposeDoc]. Runs offline: nothing is
/// fetched; `<img>` reads local files or `data:` URIs.
ComposeDoc htmlToCompose(String source, {String pageSize = 'A4'}) {
  final document = html.parse(source);
  final warnings = <String>{};
  final title = document.querySelector('title')?.text.trim();
  // `@page { size: … }` in a <style> block picks the paper.
  var size = pageSize;
  for (final st in document.querySelectorAll('style')) {
    final m = RegExp(r'@page\s*\{[^}]*size:\s*([A-Za-z0-9]+)')
        .firstMatch(st.text);
    if (m != null) size = m.group(1)!;
  }
  final body = document.body ?? document.documentElement;
  final blocks = body == null
      ? <CBlock>[]
      : _Walker(warnings).blocks(body.nodes, const CStyle(), CAlign.left);
  return ComposeDoc(
    blocks: blocks,
    title: title == null || title.isEmpty ? null : title,
    pageSize: size,
    warnings: warnings.toList(),
  );
}

const _blockTags = {
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'nav',
  'aside',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'ul',
  'ol',
  'li',
  'pre',
  'blockquote',
  'table',
  'hr',
  'figure',
  'figcaption',
  'center',
  'dl',
  'dt',
  'dd',
  'img',
  'address',
  'details',
  'summary',
};

class _Walker {
  _Walker(this.warnings);
  final Set<String> warnings;

  CStyle _styled(dom.Element e, CStyle s) {
    var st = s;
    final css = _css(e.attributes['style']);
    final color = css['color'] ?? e.attributes['color'];
    if (color != null) st = st.copyWith(color: parseComposeColor(color));
    final fw = css['font-weight'];
    if (fw != null && (fw == 'bold' || (int.tryParse(fw) ?? 400) >= 600)) {
      st = st.copyWith(bold: true);
    }
    if (css['font-style'] == 'italic') st = st.copyWith(italic: true);
    final td = css['text-decoration'] ?? '';
    if (td.contains('underline')) st = st.copyWith(underline: true);
    if (td.contains('line-through')) st = st.copyWith(strike: true);
    final fs = css['font-size'];
    if (fs != null) {
      final px = RegExp(r'([\d.]+)\s*(px|pt|em|rem|%)?').firstMatch(fs);
      if (px != null) {
        final v = double.parse(px.group(1)!);
        final scale = switch (px.group(2)) {
          'em' || 'rem' => v,
          '%' => v / 100,
          'pt' => v / 11,
          _ => v / 14.6,
        };
        st = st.copyWith(scale: scale.clamp(0.5, 4.0));
      }
    }
    return st;
  }

  CAlign _align(dom.Element e, CAlign inherited) {
    final a =
        _css(e.attributes['style'])['text-align'] ?? e.attributes['align'];
    return switch (a) {
      'center' => CAlign.center,
      'right' => CAlign.right,
      'justify' => CAlign.justify,
      'left' => CAlign.left,
      _ => e.localName == 'center' ? CAlign.center : inherited,
    };
  }

  List<CBlock> blocks(List<dom.Node> nodes, CStyle s, CAlign align) {
    final out = <CBlock>[];
    var pending = <dom.Node>[];
    void flush() {
      if (pending.isEmpty) return;
      final inl = inlines(pending, s);
      pending = [];
      if (inl.any(
        (i) => i.math != null || i.lineBreak || i.text.trim().isNotEmpty,
      )) {
        out.addAll(_splitDisplayMath(inl, align));
      }
    }

    for (final n in nodes) {
      if (n is dom.Element && _blockTags.contains(n.localName)) {
        flush();
        out.addAll(block(n, s, align));
      } else if (n is dom.Element &&
          const {
            'script',
            'style',
            'head',
            'title',
            'meta',
            'link',
          }.contains(n.localName)) {
        continue;
      } else {
        pending.add(n);
      }
    }
    flush();
    return out;
  }

  List<CBlock> block(dom.Element e, CStyle parent, CAlign inherited) {
    final s = _styled(e, parent);
    final align = _align(e, inherited);
    switch (e.localName) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        return [
          CHeading(int.parse(e.localName!.substring(1)), inlines(e.nodes, s)),
        ];
      case 'p' || 'summary' || 'dt' || 'address':
        return _splitDisplayMath(
          inlines(e.nodes, e.localName == 'dt' ? s.copyWith(bold: true) : s),
          align,
        );
      case 'div' ||
          'section' ||
          'article' ||
          'header' ||
          'footer' ||
          'main' ||
          'nav' ||
          'aside' ||
          'center' ||
          'figure' ||
          'details' ||
          'dd' ||
          'dl':
        return blocks(e.nodes, s, align);
      case 'figcaption':
        return [
          CPara(
            inlines(e.nodes, s.copyWith(italic: true)),
            align: CAlign.center,
          ),
        ];
      case 'ul' || 'ol':
        final items = <List<CBlock>>[];
        for (final li in e.children.where((c) => c.localName == 'li')) {
          items.add(blocks(li.nodes, s, CAlign.left));
        }
        return [
          CList(
            items,
            ordered: e.localName == 'ol',
            start: int.tryParse(e.attributes['start'] ?? '') ?? 1,
          ),
        ];
      case 'li':
        return blocks(e.nodes, s, align);
      case 'pre':
        return [CCode(e.text.replaceAll(RegExp(r'^\n'), '').trimRight())];
      case 'blockquote':
        return [CQuote(blocks(e.nodes, s.copyWith(italic: true), CAlign.left))];
      case 'hr':
        return const [CRule()];
      case 'img':
        final w = e.attributes['width'] ?? _css(e.attributes['style'])['width'];
        double? frac;
        if (w != null && w.endsWith('%')) {
          frac = (double.tryParse(w.replaceAll('%', '')) ?? 100) / 100;
        } else if (w != null) {
          final px = double.tryParse(w.replaceAll('px', ''));
          if (px != null) frac = (px / 680).clamp(0.05, 1.0);
        }
        return [
          CImage(e.attributes['src'] ?? '', widthFraction: frac, align: align),
        ];
      case 'table':
        final rows = <List<List<CInline>>>[];
        var header = false;
        List<CAlign>? aligns;
        List<CInline>? caption;
        final cap = e.querySelector('caption');
        if (cap != null) caption = inlines(cap.nodes, s);
        for (final tr in e.querySelectorAll('tr')) {
          final cells = tr.children
              .where((c) => c.localName == 'td' || c.localName == 'th')
              .toList();
          if (rows.isEmpty &&
              cells.isNotEmpty &&
              cells.every((c) => c.localName == 'th')) {
            header = true;
          }
          aligns ??= [for (final c in cells) _align(c, CAlign.left)];
          rows.add([for (final c in cells) inlines(c.nodes, _styled(c, s))]);
        }
        return [CTable(rows, header: header, aligns: aligns, caption: caption)];
      default:
        return blocks(e.nodes, s, align);
    }
  }

  List<CInline> inlines(List<dom.Node> nodes, CStyle s) {
    final out = <CInline>[];
    for (final n in nodes) {
      if (n is dom.Text) {
        var t = n.text.replaceAll(RegExp(r'\s+'), ' ');
        // Whitespace collapses at the start of a line (block start or <br>).
        if (out.isEmpty || out.last.lineBreak) t = t.trimLeft();
        if (t.isNotEmpty) out.addAll(_mathRuns(t, s));
        continue;
      }
      if (n is! dom.Element) continue;
      final st = _styled(n, s);
      switch (n.localName) {
        case 'b' || 'strong':
          out.addAll(inlines(n.nodes, st.copyWith(bold: true)));
        case 'i' || 'em' || 'cite' || 'var' || 'dfn':
          out.addAll(inlines(n.nodes, st.copyWith(italic: true)));
        case 'u' || 'ins':
          out.addAll(inlines(n.nodes, st.copyWith(underline: true)));
        case 's' || 'del' || 'strike':
          out.addAll(inlines(n.nodes, st.copyWith(strike: true)));
        case 'code' || 'kbd' || 'samp' || 'tt':
          out.add(st.copyWith(code: true).run(n.text));
        case 'sup':
          out.addAll(inlines(n.nodes, st.copyWith(superscript: true)));
        case 'sub':
          out.addAll(inlines(n.nodes, st.copyWith(subscript: true)));
        case 'small':
          out.addAll(inlines(n.nodes, st.copyWith(scale: st.scale * 0.85)));
        case 'big':
          out.addAll(inlines(n.nodes, st.copyWith(scale: st.scale * 1.2)));
        case 'mark':
          out.addAll(
            inlines(n.nodes, st.copyWith(color: 0xFF795548, bold: true)),
          );
        case 'a':
          out.addAll(
            inlines(
              n.nodes,
              st.copyWith(
                link: n.attributes['href'],
                color: st.color ?? 0xFF0B57D0,
                underline: true,
              ),
            ),
          );
        case 'br':
          out.add(const CInline('', lineBreak: true));
        case 'img':
          out.add(st.run('[${n.attributes['alt'] ?? 'image'}]'));
        case 'script' || 'style':
          break;
        case 'span' || 'font' || 'abbr' || 'label' || 'time' || 'q':
          out.addAll(inlines(n.nodes, st));
        default:
          warnings.add('<${n.localName}>');
          out.addAll(inlines(n.nodes, st));
      }
    }
    return out;
  }
}

/// `\( … \)` inline math inside text.
List<CInline> _mathRuns(String t, CStyle s) {
  final out = <CInline>[];
  final re = RegExp(r'\\\((.+?)\\\)|\\\[(.+?)\\\]');
  var pos = 0;
  for (final m in re.allMatches(t)) {
    if (m.start > pos) out.add(s.run(t.substring(pos, m.start)));
    if (m.group(1) != null) {
      out.add(CInline('', math: m.group(1)));
    } else {
      // Display math marker: split into its own block later.
      out.add(CInline('\u0000', math: m.group(2)));
    }
    pos = m.end;
  }
  if (pos < t.length) out.add(s.run(t.substring(pos)));
  return out;
}

/// Splits a paragraph at display-math markers.
List<CBlock> _splitDisplayMath(List<CInline> inl, CAlign align) {
  final out = <CBlock>[];
  var cur = <CInline>[];
  for (final i in inl) {
    if (i.math != null && i.text == '\u0000') {
      if (cur.isNotEmpty) out.add(CPara(cur, align: align));
      cur = [];
      out.add(CMath(i.math!));
    } else {
      cur.add(i);
    }
  }
  if (cur.isNotEmpty) out.add(CPara(cur, align: align));
  return out;
}

Map<String, String> _css(String? style) {
  if (style == null) return const {};
  final out = <String, String>{};
  for (final part in style.split(';')) {
    final i = part.indexOf(':');
    if (i <= 0) continue;
    out[part.substring(0, i).trim().toLowerCase()] = part
        .substring(i + 1)
        .trim();
  }
  return out;
}
