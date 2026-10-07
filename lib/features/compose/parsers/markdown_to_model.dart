import 'package:document_studio/features/compose/compose_model.dart';
import 'package:markdown/markdown.dart' as md;

/// Markdown (GitHub flavour + `$math$` / `$$display math$$`) → [ComposeDoc].
ComposeDoc markdownToCompose(String source, {String pageSize = 'A4'}) {
  final doc = md.Document(
    extensionSet: md.ExtensionSet.gitHubWeb,
    blockSyntaxes: const [_DisplayMathSyntax()],
    inlineSyntaxes: [_InlineMathSyntax()],
    encodeHtml: false,
  );
  final nodes = doc.parseLines(source.replaceAll('\r\n', '\n').split('\n'));
  final blocks = _blocks(nodes);
  String? title;
  final first = blocks.isNotEmpty ? blocks.first : null;
  if (first is CHeading && first.level == 1) {
    title = first.inlines.map((i) => i.text).join();
  }
  return ComposeDoc(blocks: blocks, title: title, pageSize: pageSize);
}

class _DisplayMathSyntax extends md.BlockSyntax {
  const _DisplayMathSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*\$\$');

  @override
  md.Node? parse(md.BlockParser parser) {
    final first = parser.current.content.trim().substring(2);
    final buf = StringBuffer();
    // `$$ x $$` on one line.
    if (first.trim().endsWith(r'$$') && first.trim().length > 2) {
      parser.advance();
      return md.Element.text(
        'displaymath',
        first.trim().substring(0, first.trim().length - 2),
      );
    }
    buf.writeln(first);
    parser.advance();
    while (!parser.isDone) {
      final line = parser.current.content;
      parser.advance();
      final i = line.indexOf(r'$$');
      if (i >= 0) {
        buf.write(line.substring(0, i));
        break;
      }
      buf.writeln(line);
    }
    return md.Element.text('displaymath', buf.toString().trim());
  }
}

class _InlineMathSyntax extends md.InlineSyntax {
  _InlineMathSyntax() : super(r'(?<!\\)\$([^\$\n]+?)\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', match.group(1)!));
    return true;
  }
}

List<CBlock> _blocks(List<md.Node> nodes) {
  final out = <CBlock>[];
  for (final n in nodes) {
    if (n is md.Text) {
      if (n.text.trim().isNotEmpty) {
        out.add(CPara(_inlines([n], const CStyle())));
      }
      continue;
    }
    if (n is! md.Element) continue;
    final kids = n.children ?? const <md.Node>[];
    switch (n.tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        out.add(
          CHeading(
            int.parse(n.tag.substring(1)),
            _inlines(kids, const CStyle()),
          ),
        );
      case 'p':
        // A paragraph holding only an image is a figure.
        if (kids.length == 1 &&
            kids.first is md.Element &&
            (kids.first as md.Element).tag == 'img') {
          final img = kids.first as md.Element;
          final alt = img.attributes['alt'] ?? '';
          out.add(
            CImage(
              img.attributes['src'] ?? '',
              caption: alt.isEmpty ? null : [CInline(alt, italic: true)],
            ),
          );
        } else {
          out.add(CPara(_inlines(kids, const CStyle())));
        }
      case 'ul' || 'ol':
        final items = <List<CBlock>>[];
        final labels = <List<CInline>?>[];
        var task = false;
        for (final li in kids.whereType<md.Element>()) {
          final liKids = li.children ?? const <md.Node>[];
          // Tight lists hold inline content directly.
          final hasBlocks = liKids.any(
            (k) => k is md.Element && _isBlock(k.tag),
          );
          var content = liKids;
          List<CInline>? label;
          final cb = liKids.whereType<md.Element>().where(
            (e) => e.tag == 'input',
          );
          if (cb.isNotEmpty) {
            task = true;
            label = [
              CInline(cb.first.attributes.containsKey('checked') ? '☑' : '☐'),
            ];
            content = [
              for (final k in liKids)
                if (k != cb.first) k,
            ];
          }
          labels.add(label);
          items.add(
            hasBlocks
                ? _blocks(content)
                : [CPara(_inlines(content, const CStyle()))],
          );
        }
        out.add(
          CList(
            items,
            ordered: n.tag == 'ol',
            start: int.tryParse(n.attributes['start'] ?? '') ?? 1,
            labels: task ? labels : null,
          ),
        );
      case 'pre':
        final code = kids.whereType<md.Element>().firstOrNull;
        final lang = code?.attributes['class']?.replaceFirst('language-', '');
        out.add(
          CCode(_plain(code?.children ?? kids).trimRight(), language: lang),
        );
      case 'blockquote':
        out.add(CQuote(_blocks(kids)));
      case 'hr':
        out.add(const CRule());
      case 'table':
        final rows = <List<List<CInline>>>[];
        List<CAlign>? aligns;
        for (final section in kids.whereType<md.Element>()) {
          for (final tr
              in (section.children ?? const <md.Node>[])
                  .whereType<md.Element>()) {
            final cells = (tr.children ?? const <md.Node>[])
                .whereType<md.Element>()
                .toList();
            aligns ??= [
              for (final c in cells)
                switch (c.attributes['align'] ??
                    _styleAlign(c.attributes['style'])) {
                  'center' => CAlign.center,
                  'right' => CAlign.right,
                  _ => CAlign.left,
                },
            ];
            rows.add([
              for (final c in cells)
                _inlines(c.children ?? const [], const CStyle()),
            ]);
          }
        }
        out.add(CTable(rows, aligns: aligns));
      case 'displaymath':
        out.add(CMath(_plain(kids)));
      case 'img':
        out.add(CImage(n.attributes['src'] ?? ''));
      default:
        final inl = _inlines([n], const CStyle());
        if (inl.isNotEmpty) out.add(CPara(inl));
    }
  }
  return out;
}

String? _styleAlign(String? style) =>
    RegExp(r'text-align:\s*(\w+)').firstMatch(style ?? '')?.group(1);

bool _isBlock(String tag) => const {
  'p',
  'ul',
  'ol',
  'pre',
  'blockquote',
  'table',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'hr',
  'displaymath',
}.contains(tag);

String _plain(List<md.Node> nodes) => nodes.map((n) => n.textContent).join();

List<CInline> _inlines(List<md.Node> nodes, CStyle s) {
  final out = <CInline>[];
  for (final n in nodes) {
    if (n is md.Text) {
      out.add(s.run(_unescape(n.text)));
      continue;
    }
    if (n is! md.Element) continue;
    final kids = n.children ?? const <md.Node>[];
    switch (n.tag) {
      case 'strong':
        out.addAll(_inlines(kids, s.copyWith(bold: true)));
      case 'em':
        out.addAll(_inlines(kids, s.copyWith(italic: true)));
      case 'del':
        out.addAll(_inlines(kids, s.copyWith(strike: true)));
      case 'code':
        out.add(s.copyWith(code: true).run(_plain(kids)));
      case 'a':
        out.addAll(
          _inlines(
            kids,
            s.copyWith(
              link: n.attributes['href'],
              color: 0xFF0B57D0,
              underline: true,
            ),
          ),
        );
      case 'br':
        out.add(const CInline('', lineBreak: true));
      case 'math':
        out.add(CInline('', math: _plain(kids)));
      case 'img':
        out.add(s.run('[${n.attributes['alt'] ?? 'image'}]'));
      case 'input':
        out.add(s.run(n.attributes.containsKey('checked') ? '☑ ' : '☐ '));
      default:
        out.addAll(_inlines(kids, s));
    }
  }
  return out;
}

String _unescape(String t) => t
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(r'\$', r'$');
