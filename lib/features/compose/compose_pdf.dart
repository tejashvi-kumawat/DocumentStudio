import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/features/compose/compose_model.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// A typeset formula, ready to place in the PDF.
class MathImage {
  const MathImage(this.png, this.width, this.height, this.descent);
  final Uint8List png;

  /// Size in points at the font size it was rendered for.
  final double width, height;

  /// Below-baseline part (inline alignment).
  final double descent;
}

/// Renders formulas (TeX) — provided by the UI layer, which owns the
/// typesetter. Returns null for a formula that cannot be typeset.
typedef MathRenderer = Future<MathImage?> Function(
  String tex, {
  required bool display,
  required double fontSize,
});

/// The bundled fonts the composer typesets with (Liberation: metric twins
/// of Arial / Times / Courier), loaded once.
class ComposeFonts {
  ComposeFonts._(this.sans, this.serif, this.mono, this.fallback);
  final List<pw.Font> sans, serif, mono; // regular, bold, italic, bold-italic

  /// DejaVu Sans: symbols the text fonts lack (₹, ✓, ☐, arrows, maths).
  final List<pw.Font> fallback;

  static ComposeFonts? _cache;

  static Future<ComposeFonts> load() async {
    final c = _cache;
    if (c != null) return c;
    Future<List<pw.Font>> fam(String base) async => [
      for (final s in ['Regular', 'Bold', 'Italic', 'BoldItalic'])
        pw.Font.ttf(await rootBundle.load('assets/fonts/text/$base-$s.ttf')),
    ];
    return _cache = ComposeFonts._(
      await fam('LiberationSans'),
      await fam('LiberationSerif'),
      await fam('LiberationMono'),
      [
        pw.Font.ttf(await rootBundle.load('assets/fonts/text/DejaVuSans.ttf')),
        pw.Font.ttf(
          await rootBundle.load('assets/fonts/text/DejaVuSans-Bold.ttf'),
        ),
      ],
    );
  }
}

/// [ComposeDoc] → PDF bytes. Everything happens on this device.
/// A running header/footer line with its page fields filled in.
pw.Widget _running(
  String text,
  CAlign align,
  pw.Context ctx,
  double base, {
  required bool top,
}) => pw.Container(
  alignment: switch (align) {
    CAlign.left => pw.Alignment.centerLeft,
    CAlign.right => pw.Alignment.centerRight,
    _ => pw.Alignment.center,
  },
  margin: top
      ? const pw.EdgeInsets.only(top: 8)
      : const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(
    text
        .replaceAll('{PAGE}', '${ctx.pageNumber}')
        .replaceAll('{PAGES}', '${ctx.pagesCount}'),
    style: pw.TextStyle(fontSize: base * 0.85, color: PdfColors.grey800),
  ),
);

/// `595x842` (points) → a page format.
PdfPageFormat? _customFormat(String s) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)x(\d+(?:\.\d+)?)$').firstMatch(s);
  if (m == null) return null;
  return PdfPageFormat(double.parse(m.group(1)!), double.parse(m.group(2)!));
}

Future<Uint8List> renderComposePdf(
  ComposeDoc doc, {
  required ComposeFonts fonts,
  required MathRenderer math,
  String? baseDir,
}) async {
  final base = doc.baseFontSize;
  // Typeset every formula first (async), then lay out synchronously.
  final formulas = <String, MathImage?>{};
  Future<void> collect(List<CBlock> blocks) async {
    for (final b in blocks) {
      switch (b) {
        case CMath(:final tex):
          formulas['D|$tex'] ??= await math(
            tex,
            display: true,
            fontSize: base * 1.1,
          );
        case CPara(:final inlines) || CHeading(:final inlines):
          for (final i in inlines) {
            if (i.math != null) {
              formulas['I|${i.math}'] ??= await math(
                i.math!,
                display: false,
                fontSize: base,
              );
            }
          }
        case CList(:final items):
          for (final it in items) {
            await collect(it);
          }
        case CQuote(:final blocks) ||
            CAbstract(:final blocks) ||
            CBox(:final blocks):
          await collect(blocks);
        case CTable(:final rows):
          for (final r in rows) {
            for (final cell in r) {
              for (final i in cell) {
                if (i.math != null) {
                  formulas['I|${i.math}'] ??= await math(
                    i.math!,
                    display: false,
                    fontSize: base,
                  );
                }
              }
            }
          }
        case CDrawing() ||
            CImage() ||
            CCode() ||
            CRule() ||
            CPageBreak() ||
            CSpace() ||
            CTitleBlock() ||
            CToc():
          break;
      }
    }
  }

  await collect(doc.blocks);
  for (final f in doc.footnotes) {
    for (final i in f) {
      if (i.math != null) {
        formulas['I|${i.math}'] ??= await math(
          i.math!,
          display: false,
          fontSize: base * 0.85,
        );
      }
    }
  }

  // A table of contents needs page numbers: lay out once to learn where each
  // heading lands, then for real (the contents block keeps its size).
  final hasToc = doc.blocks.any((b) => b is CToc);
  Map<int, int>? pages;
  if (hasToc) {
    final probe = _Renderer(doc, fonts, formulas, baseDir, null);
    await _document(doc, probe, fonts).save();
    pages = probe.headingPages;
  }
  final r = _Renderer(doc, fonts, formulas, baseDir, pages);
  return _document(doc, r, fonts).save();
}

pw.Document _document(ComposeDoc doc, _Renderer r, ComposeFonts fonts) {
  final base = doc.baseFontSize;
  final pdf = pw.Document(
    title: doc.title,
    author: doc.author,
    creator: 'Document Studio',
    producer: 'Document Studio Composer',
  );
  final format = switch (doc.pageSize.toLowerCase()) {
    'letter' => PdfPageFormat.letter,
    'legal' => PdfPageFormat.legal,
    'a5' => PdfPageFormat.a5,
    'a3' => PdfPageFormat.a3,
    final custom => _customFormat(custom) ?? PdfPageFormat.a4,
  };
  final margin = doc.marginPt ?? (doc.serif ? 72.0 : 56.0);
  final family = doc.serif ? fonts.serif : fonts.sans;
  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: format.copyWith(
          marginLeft: margin,
          marginRight: margin,
          marginTop: margin * 0.9,
          marginBottom: margin * 0.9,
        ),
        theme:
            pw.ThemeData.withFont(
              base: family[0],
              bold: family[1],
              italic: family[2],
              boldItalic: family[3],
            ).copyWith(
              defaultTextStyle: pw.TextStyle(
                font: family[0],
                fontBold: family[1],
                fontItalic: family[2],
                fontBoldItalic: family[3],
                fontSize: base,
                lineSpacing: base * 0.3,
                color: PdfColor.fromInt(0xFF1F2328),
              ),
            ),
      ),
      maxPages: 2000,
      header: doc.pageHeader == null || doc.pageHeader!.isEmpty
          ? null
          : (ctx) => _running(
              doc.pageHeader!,
              doc.headerAlign,
              ctx,
              base,
              top: false,
            ),
      footer: doc.pageFooter == null
          ? (ctx) => pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(top: 8),
              child: pw.Text(
                '${ctx.pageNumber}',
                style: pw.TextStyle(
                  fontSize: base * 0.8,
                  color: PdfColors.grey700,
                ),
              ),
            )
          : doc.pageFooter!.isEmpty
          ? null
          : (ctx) => _running(
              doc.pageFooter!,
              doc.footerAlign,
              ctx,
              base,
              top: true,
            ),
      build: (ctx) => r.build(),
    ),
  );
  return pdf;
}

class _Renderer {
  _Renderer(this.doc, this.fonts, this.formulas, this.baseDir, this.knownPages);

  /// Page of each heading from the previous layout pass (for the contents).
  final Map<int, int>? knownPages;

  /// Filled during layout: heading index → page number.
  final Map<int, int> headingPages = {};
  int _headingIndex = 0;

  final ComposeDoc doc;
  final ComposeFonts fonts;
  final Map<String, MathImage?> formulas;
  final String? baseDir;

  double get base => doc.baseFontSize;
  List<pw.Font> get family => doc.serif ? fonts.serif : fonts.sans;

  static const _headingScale = [1.75, 1.42, 1.2, 1.08, 1.0, 0.95];
  static final _muted = PdfColor.fromInt(0xFF57606A);
  static final _border = PdfColor.fromInt(0xFFD0D7DE);
  static final _codeBg = PdfColor.fromInt(0xFFF6F8FA);

  List<pw.Widget> build() {
    final out = <pw.Widget>[];
    for (final b in doc.blocks) {
      out.addAll(block(b, 0));
    }
    if (doc.footnotes.isNotEmpty) {
      out
        ..add(pw.SizedBox(height: base))
        ..add(pw.Container(width: 120, height: 0.6, color: _border))
        ..add(pw.SizedBox(height: 4));
      for (var i = 0; i < doc.footnotes.length; i++) {
        out.add(
          pw.RichText(
            text: pw.TextSpan(
              style: pw.TextStyle(fontSize: base * 0.85),
              children: [
                pw.TextSpan(
                  text: '${i + 1}  ',
                  style: pw.TextStyle(fontSize: base * 0.7),
                ),
                ...spans(doc.footnotes[i], base * 0.85),
              ],
            ),
          ),
        );
      }
    }
    return out;
  }

  List<pw.Widget> block(CBlock b, int depth) {
    switch (b) {
      case CHeading(:final level, :final inlines, :final number):
        final index = _headingIndex++;
        final size = base * _headingScale[(level - 1).clamp(0, 5)];
        final plain = [
          ?number,
          inlines.map((i) => i.math != null ? i.math! : i.text).join(),
        ].join('  ');
        final rich = pw.RichText(
          text: pw.TextSpan(
            style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
            children: [
              if (number != null) pw.TextSpan(text: '$number\u2003'),
              ...spans(inlines, size, bold: true),
            ],
          ),
        );
        return [
          pw.SizedBox(height: size * (level <= 2 ? 0.9 : 0.6)),
          pw.Header(
            level: (level - 1).clamp(0, 5),
            title: plain,
            decoration: const pw.BoxDecoration(),
            margin: pw.EdgeInsets.zero,
            padding: pw.EdgeInsets.zero,
            child: pw.Anchor(
              name: 'ds-h$index',
              child: pw.Builder(
                builder: (ctx) {
                  headingPages[index] = ctx.pageNumber;
                  return rich;
                },
              ),
            ),
          ),
          if (!doc.serif && level <= 2)
            pw.Container(
              margin: const pw.EdgeInsets.only(top: 3),
              height: 0.6,
              color: _border,
            ),
          pw.SizedBox(height: size * 0.35),
        ];
      case CPara(:final inlines, :final align, :final indent):
        if (inlines.isEmpty) return const [];
        final textAlign = switch (align) {
          CAlign.center => pw.TextAlign.center,
          CAlign.right => pw.TextAlign.right,
          CAlign.justify => pw.TextAlign.justify,
          CAlign.left => doc.serif ? pw.TextAlign.justify : pw.TextAlign.left,
        };
        // \hfill: the part after it sits at the right margin (résumé
        // dates, letter headers).
        if (inlines.any((i) => i.text.contains('\u0002'))) {
          return [
            ..._splitLines(inlines, textAlign),
            pw.SizedBox(height: doc.serif ? base * 0.35 : base * 0.7),
          ];
        }
        return [
          if (align == CAlign.center || align == CAlign.right)
            // Short aligned lines need the full width to align within.
            pw.SizedBox(
              width: double.infinity,
              child: pw.RichText(
                textAlign: textAlign,
                text: pw.TextSpan(children: spans(inlines, base)),
              ),
            )
          else
            pw.RichText(
              textAlign: textAlign,
              text: pw.TextSpan(
                children: [
                  if (indent) const pw.TextSpan(text: '\u2003\u2002'),
                  ...spans(inlines, base),
                ],
              ),
            ),
          pw.SizedBox(height: doc.serif ? base * 0.35 : base * 0.7),
        ];
      case CList():
        return [listWidget(b, depth), pw.SizedBox(height: base * 0.5)];
      case CCode(:final text):
        final lines = text.split('\n');
        return [
          for (var i = 0; i < lines.length; i++)
            pw.Container(
              color: _codeBg,
              padding: pw.EdgeInsets.fromLTRB(
                10,
                i == 0 ? 8 : 0,
                10,
                i == lines.length - 1 ? 8 : 0,
              ),
              child: pw.Text(
                lines[i].isEmpty ? ' ' : lines[i].replaceAll('\t', '    '),
                style: pw.TextStyle(
                  font: fonts.mono[0],
                  fontBold: fonts.mono[1],
                  fontSize: base * 0.85,
                  lineSpacing: 1,
                ),
              ),
            ),
          pw.SizedBox(height: base * 0.7),
        ];
      case CQuote(:final blocks):
        return [
          pw.Container(
            padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
            decoration: pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: _border, width: 3)),
            ),
            child: pw.DefaultTextStyle.merge(
              style: pw.TextStyle(color: _muted),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [for (final c in blocks) ...block(c, depth)],
              ),
            ),
          ),
          pw.SizedBox(height: base * 0.6),
        ];
      case CBox(
        :final blocks,
        :final title,
        :final borderColor,
        :final fillColor,
      ):
        final border = PdfColor.fromInt(borderColor ?? 0xFF757575);
        final fill = PdfColor.fromInt(fillColor ?? 0xFFF5F5F5);
        return [
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: pw.BoxDecoration(
              color: fill,
              border: pw.Border.all(color: border, width: 1.2),
              borderRadius: pw.BorderRadius.circular(3),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (title != null && title.trim().isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 6),
                    child: pw.Text(
                      title,
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: base * 0.95,
                        color: border,
                      ),
                    ),
                  ),
                for (final c in blocks) ...block(c, depth),
              ],
            ),
          ),
          pw.SizedBox(height: base * 0.7),
        ];
      case CDrawing(:final ops, :final width, :final height):
        final dw = width.clamp(40.0, 480.0);
        final dh = height.clamp(40.0, 480.0);
        final sx = dw / width;
        final sy = dh / height;
        final scale = sx < sy ? sx : sy;
        final ox = (dw - width * scale) / 2;
        final oy = (dh - height * scale) / 2;
        return [
          pw.SizedBox(height: base * 0.3),
          pw.Center(
            child: pw.SizedBox(
              width: dw,
              height: dh,
              child: pw.Stack(
                children: [
                  pw.CustomPaint(
                    size: PdfPoint(dw, dh),
                    painter: (canvas, size) =>
                        _paintDrawing(canvas, size, ops, width, height),
                  ),
                  for (final op in ops)
                    if (op.kind == CDrawKind.text &&
                        op.text != null &&
                        op.points.isNotEmpty)
                      pw.Positioned(
                        left: ox + op.points.first.$1 * scale - 40,
                        bottom: oy + op.points.first.$2 * scale - 6,
                        child: pw.SizedBox(
                          width: 80,
                          child: pw.Text(
                            op.text!,
                            textAlign: pw.TextAlign.center,
                            style: pw.TextStyle(fontSize: base * 0.85),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          pw.SizedBox(height: base * 0.6),
        ];
      case CAbstract(:final blocks):
        return [
          pw.Center(
            child: pw.Text(
              'Abstract',
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: base * 0.95,
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 30),
            child: pw.DefaultTextStyle.merge(
              style: pw.TextStyle(fontSize: base * 0.92),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [for (final c in blocks) ...block(c, depth)],
              ),
            ),
          ),
          pw.SizedBox(height: base),
        ];
      case CTable():
        return tableWidget(b);
      case CImage():
        return imageWidget(b);
      case CMath(:final tex, :final number):
        final img = formulas['D|$tex'];
        final body = img == null
            ? pw.Text(
                tex,
                style: pw.TextStyle(
                  color: PdfColors.red800,
                  font: fonts.mono[0],
                ),
              )
            : pw.Image(
                pw.MemoryImage(img.png),
                width: img.width,
                height: img.height,
              );
        return [
          pw.SizedBox(height: base * 0.4),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Center(child: body)),
              if (number != null) pw.Text(number),
            ],
          ),
          pw.SizedBox(height: base * 0.6),
        ];
      case CRule():
        return [
          pw.SizedBox(height: base * 0.5),
          pw.Container(height: 0.8, color: _border),
          pw.SizedBox(height: base * 0.8),
        ];
      case CPageBreak():
        return [pw.NewPage()];
      case CSpace(:final points):
        return [pw.SizedBox(height: points)];
      case CTitleBlock():
        return [
          if (doc.title != null)
            pw.Center(
              child: pw.Text(
                doc.title!.replaceAll(RegExp(r'\\\\'), '\n'),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: base * 1.9),
              ),
            ),
          pw.SizedBox(height: base),
          if (doc.author != null && doc.author!.trim().isNotEmpty)
            pw.Center(
              child: pw.Text(
                _plainTex(doc.author!),
                textAlign: pw.TextAlign.center,
                style: pw.TextStyle(fontSize: base * 1.2),
              ),
            ),
          pw.SizedBox(height: base * 0.6),
          pw.Center(
            child: pw.Text(
              doc.date == null ? _today() : _plainTex(doc.date!),
              style: pw.TextStyle(fontSize: base * 1.1),
            ),
          ),
          pw.SizedBox(height: base * 1.8),
        ];
      case CToc():
        return [
          pw.Text(
            'Contents',
            style: pw.TextStyle(
              fontSize: base * 1.42,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: base * 0.6),
          ..._toc(),
          pw.SizedBox(height: base * 1.2),
        ];
    }
  }

  List<pw.Widget> _splitLines(List<CInline> inlines, pw.TextAlign align) {
    final lines = <List<CInline>>[[]];
    for (final i in inlines) {
      if (i.lineBreak) {
        lines.add([]);
      } else {
        lines.last.add(i);
      }
    }
    final out = <pw.Widget>[];
    for (final line in lines) {
      final left = <CInline>[], right = <CInline>[];
      var after = false;
      for (final i in line) {
        if (!after && i.math == null && i.text.contains('\u0002')) {
          final parts = i.text.split('\u0002');
          if (parts.first.trim().isNotEmpty)
            left.add(i.copyWith(text: parts.first));
          final rest = parts.skip(1).join(' ').trimLeft();
          if (rest.isNotEmpty) right.add(i.copyWith(text: rest));
          after = true;
          continue;
        }
        (after ? right : left).add(i);
      }
      if (!after) {
        if (line.isNotEmpty) {
          out.add(
            pw.RichText(
              textAlign: align,
              text: pw.TextSpan(children: spans(line, base)),
            ),
          );
        }
        continue;
      }
      out.add(
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.RichText(
                text: pw.TextSpan(children: spans(left, base)),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.RichText(
              textAlign: pw.TextAlign.right,
              text: pw.TextSpan(children: spans(right, base)),
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// Contents: one line per heading (levels 1–3) with its page, linked.
  List<pw.Widget> _toc() {
    final out = <pw.Widget>[];
    var i = 0;
    for (final b in doc.blocks) {
      if (b is! CHeading) continue;
      final index = i++;
      if (b.level > 3) continue;
      final title = [
        if (b.number != null) b.number!,
        b.inlines.map((x) => x.math ?? x.text).join(),
      ].join('  ');
      final page = knownPages?[index];
      out.add(
        pw.Link(
          destination: 'ds-h$index',
          child: pw.Padding(
            padding: pw.EdgeInsets.only(left: 14.0 * (b.level - 1), bottom: 3),
            child: pw.Row(
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontWeight: b.level == 1 ? pw.FontWeight.bold : null,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Expanded(
                  child: pw.Divider(
                    borderStyle: pw.BorderStyle.dotted,
                    thickness: 0.4,
                  ),
                ),
                pw.SizedBox(width: 6),
                pw.Text(page == null ? ' ' : '$page'),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  pw.Widget listWidget(CList l, int depth) {
    final children = <pw.Widget>[];
    for (var i = 0; i < l.items.length; i++) {
      final label = l.labels?[i];
      final marker = label != null
          ? pw.RichText(
              text: pw.TextSpan(children: spans(label, base, bold: true)),
            )
          : pw.Text(
              l.ordered
                  ? _ordinal(l.start + i, depth)
                  : const ['•', '–', '∗', '·'][depth % 4],
            );
      children.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(width: depth == 0 ? 6 : 0),
              pw.Container(
                width: label != null ? null : 18,
                constraints: label != null
                    ? const pw.BoxConstraints(minWidth: 18)
                    : null,
                padding: const pw.EdgeInsets.only(right: 4),
                child: marker,
              ),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    for (final b in l.items[i])
                      if (b is CList)
                        listWidget(b, depth + 1)
                      else if (b is CPara)
                        pw.RichText(
                          textAlign: doc.serif
                              ? pw.TextAlign.justify
                              : pw.TextAlign.left,
                          text: pw.TextSpan(children: spans(b.inlines, base)),
                        )
                      else
                        ...block(b, depth + 1),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: children,
    );
  }

  static String _ordinal(int n, int depth) => switch (depth % 3) {
    1 => '(${String.fromCharCode(96 + ((n - 1) % 26) + 1)})',
    2 => '${_roman(n)}.',
    _ => '$n.',
  };

  static String _roman(int n) {
    const v = [10, 9, 5, 4, 1];
    const s = ['x', 'ix', 'v', 'iv', 'i'];
    var out = '';
    var x = n;
    for (var i = 0; i < v.length; i++) {
      while (x >= v[i]) {
        out += s[i];
        x -= v[i];
      }
    }
    return out;
  }

  List<pw.Widget> tableWidget(CTable t) {
    if (t.rows.isEmpty) return const [];
    final cols = t.rows.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    pw.TextAlign al(int c) => switch (t.aligns != null && c < t.aligns!.length
        ? t.aligns![c]
        : CAlign.left) {
      CAlign.center => pw.TextAlign.center,
      CAlign.right => pw.TextAlign.right,
      _ => pw.TextAlign.left,
    };
    // LaTeX tables are as wide as their content; Markdown / HTML tables
    // span the text width.
    final table = pw.Table(
      columnWidths: doc.serif
          ? {for (var c = 0; c < cols; c++) c: const pw.IntrinsicColumnWidth()}
          : null,
      tableWidth: doc.serif ? pw.TableWidth.min : pw.TableWidth.max,
      border: pw.TableBorder.all(color: _border, width: 0.6),
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        for (var r = 0; r < t.rows.length; r++)
          pw.TableRow(
            repeat: r == 0 && t.header,
            decoration: r == 0 && t.header
                ? pw.BoxDecoration(color: _codeBg)
                : null,
            children: [
              for (var c = 0; c < cols; c++)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: pw.RichText(
                    textAlign: al(c),
                    text: pw.TextSpan(
                      children: c < t.rows[r].length
                          ? spans(
                              t.rows[r][c],
                              base * 0.95,
                              bold: r == 0 && t.header,
                            )
                          : const [],
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
    return [
      pw.SizedBox(height: base * 0.3),
      if (t.caption != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 4),
          child: pw.Center(
            child: pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(children: spans(t.caption!, base * 0.9)),
            ),
          ),
        ),
      if (doc.serif) pw.Center(child: table) else table,
      pw.SizedBox(height: base * 0.8),
    ];
  }

  List<pw.Widget> imageWidget(CImage im) {
    final bytes = _loadImage(im.src);
    final caption = im.caption == null
        ? null
        : pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.RichText(
              textAlign: pw.TextAlign.center,
              text: pw.TextSpan(children: spans(im.caption!, base * 0.9)),
            ),
          );
    pw.Widget body;
    if (bytes == null) {
      body = pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _border)),
        child: pw.Text(
          'Image not found: ${im.src}',
          style: pw.TextStyle(color: _muted, fontSize: base * 0.85),
        ),
      );
    } else {
      body = pw.LayoutBuilder(
        builder: (ctx, constraints) {
          final maxW = constraints?.maxWidth ?? 450;
          final w = maxW * (im.widthFraction ?? 1).clamp(0.05, 1.0);
          return pw.Image(
            pw.MemoryImage(bytes),
            width: im.widthFraction == null ? null : w,
            fit: pw.BoxFit.contain,
          );
        },
      );
      body = pw.ConstrainedBox(
        constraints: const pw.BoxConstraints(maxHeight: 520),
        child: body,
      );
    }
    final alignment = switch (im.align) {
      CAlign.left => pw.CrossAxisAlignment.start,
      CAlign.right => pw.CrossAxisAlignment.end,
      _ => pw.CrossAxisAlignment.center,
    };
    return [
      pw.SizedBox(height: base * 0.4),
      pw.Column(crossAxisAlignment: alignment, children: [body, ?caption]),
      pw.SizedBox(height: base * 0.8),
    ];
  }

  Uint8List? _loadImage(String src) {
    try {
      if (src.startsWith('data:')) {
        final i = src.indexOf(',');
        return base64Decode(src.substring(i + 1));
      }
      if (src.startsWith('http://') || src.startsWith('https://')) return null;
      var path = src.startsWith('file://') ? Uri.parse(src).toFilePath() : src;
      if (!p.isAbsolute(path) && baseDir != null) path = p.join(baseDir!, path);
      final f = File(path);
      if (f.existsSync()) return f.readAsBytesSync();
      // LaTeX lets you omit the extension.
      for (final ext in ['.png', '.jpg', '.jpeg']) {
        final g = File('$path$ext');
        if (g.existsSync()) return g.readAsBytesSync();
      }
    } catch (_) {}
    return null;
  }

  List<pw.InlineSpan> spans(
    List<CInline> inl,
    double size, {
    bool bold = false,
  }) {
    final out = <pw.InlineSpan>[];
    for (final i in inl) {
      if (i.lineBreak) {
        out.add(const pw.TextSpan(text: '\n'));
        continue;
      }
      if (i.math != null) {
        final img = formulas['I|${i.math}'];
        if (img == null) {
          out.add(
            pw.TextSpan(
              text: i.math,
              style: pw.TextStyle(
                color: PdfColors.red800,
                font: fonts.mono[0],
                fontSize: size * 0.9,
              ),
            ),
          );
        } else {
          final k = size / base;
          out.add(
            pw.WidgetSpan(
              baseline: -img.descent * k,
              child: pw.Image(
                pw.MemoryImage(img.png),
                width: img.width * k,
                height: img.height * k,
              ),
            ),
          );
        }
        continue;
      }
      var text = i.text;
      if (text.isEmpty) continue;
      // Glyphs the text fonts lack are drawn as shapes.
      if (text == '☐' || text == '☑' || text == '∎') {
        out.add(
          pw.WidgetSpan(
            baseline: -1,
            child: pw.Container(
              width: size * 0.7,
              height: size * 0.7,
              margin: const pw.EdgeInsets.only(right: 3),
              decoration: pw.BoxDecoration(
                color: text == '∎' ? PdfColors.black : null,
                border: pw.Border.all(width: 0.8),
              ),
              child: text == '☑'
                  ? pw.Center(
                      child: pw.Text(
                        'x',
                        style: pw.TextStyle(fontSize: size * 0.6),
                      ),
                    )
                  : null,
            ),
          ),
        );
        continue;
      }
      var fs = size * i.scale;
      if (i.smallCaps) {
        text = text.toUpperCase();
        fs *= 0.82;
      }
      if (i.superscript || i.subscript) fs *= 0.7;
      final isBold = bold || i.bold;
      final style = pw.TextStyle(
        fontFallback: fonts.fallback,
        fontSize: fs,
        font: i.code
            ? fonts.mono[isBold ? 1 : 0]
            : family[isBold ? (i.italic ? 3 : 1) : (i.italic ? 2 : 0)],
        color: i.color == null ? null : PdfColor.fromInt(i.color!),
        decoration: pw.TextDecoration.combine([
          if (i.underline) pw.TextDecoration.underline,
          if (i.strike) pw.TextDecoration.lineThrough,
        ]),
        background: i.code && !i.bold ? pw.BoxDecoration(color: _codeBg) : null,
      );
      out.add(
        pw.TextSpan(
          text: text,
          style: style,
          baseline: i.superscript
              ? size * 0.35
              : (i.subscript ? -size * 0.15 : 0),
          annotation: i.link == null ? null : pw.AnnotationUrl(i.link!),
        ),
      );
    }
    return out;
  }

  static String _plainTex(String s) => s
      .replaceAll(RegExp(r'\\\\'), ', ')
      .replaceAllMapped(RegExp(r'\\[A-Za-z]+\{([^}]*)\}'), (m) => m.group(1)!)
      .replaceAll(RegExp(r'\\[A-Za-z]+'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .trim();

  static String _today() {
    const m = [
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
    final d = DateTime.now();
    return '${m[d.month - 1]} ${d.day}, ${d.year}';
  }
}

void _paintDrawing(
  PdfGraphics canvas,
  PdfPoint size,
  List<CDrawOp> ops,
  double srcW,
  double srcH,
) {
  if (srcW <= 0 || srcH <= 0) return;
  final sx = size.x / srcW;
  final sy = size.y / srcH;
  final scale = sx < sy ? sx : sy;
  // Center the drawing in the paint box.
  final ox = (size.x - srcW * scale) / 2;
  final oy = (size.y - srcH * scale) / 2;
  double tx(double x) => ox + x * scale;
  double ty(double y) => oy + y * scale;

  for (final op in ops) {
    if (op.kind == CDrawKind.text) continue;
    final stroke = op.strokeColor == null
        ? null
        : PdfColor.fromInt(op.strokeColor!);
    final fill = op.fillColor == null ? null : PdfColor.fromInt(op.fillColor!);
    if (op.dashed) {
      canvas.setLineDashPattern(const [3, 2]);
    } else {
      canvas.setLineDashPattern(const []);
    }
    canvas.setLineWidth(op.strokeWidth * scale.clamp(0.5, 2.5));

    switch (op.kind) {
      case CDrawKind.line:
        if (op.points.length < 2 || stroke == null) break;
        canvas
          ..setStrokeColor(stroke)
          ..drawLine(
            tx(op.points[0].$1),
            ty(op.points[0].$2),
            tx(op.points[1].$1),
            ty(op.points[1].$2),
          )
          ..strokePath();
      case CDrawKind.polyline:
        if (op.points.length < 2) break;
        canvas.moveTo(tx(op.points.first.$1), ty(op.points.first.$2));
        for (var i = 1; i < op.points.length; i++) {
          canvas.lineTo(tx(op.points[i].$1), ty(op.points[i].$2));
        }
        if (fill != null) {
          canvas
            ..setFillColor(fill)
            ..fillPath();
          canvas.moveTo(tx(op.points.first.$1), ty(op.points.first.$2));
          for (var i = 1; i < op.points.length; i++) {
            canvas.lineTo(tx(op.points[i].$1), ty(op.points[i].$2));
          }
        }
        if (stroke != null) {
          canvas
            ..setStrokeColor(stroke)
            ..strokePath();
        }
      case CDrawKind.rect:
        if (op.points.length < 2) break;
        final x0 = tx(op.points[0].$1);
        final y0 = ty(op.points[0].$2);
        final x1 = tx(op.points[1].$1);
        final y1 = ty(op.points[1].$2);
        final left = x0 < x1 ? x0 : x1;
        final bottom = y0 < y1 ? y0 : y1;
        final w = (x1 - x0).abs();
        final h = (y1 - y0).abs();
        canvas.drawRect(left, bottom, w, h);
        if (fill != null && stroke != null) {
          canvas
            ..setFillColor(fill)
            ..setStrokeColor(stroke)
            ..fillAndStrokePath();
        } else if (fill != null) {
          canvas
            ..setFillColor(fill)
            ..fillPath();
        } else if (stroke != null) {
          canvas
            ..setStrokeColor(stroke)
            ..strokePath();
        }
      case CDrawKind.ellipse:
        if (op.points.length < 2) break;
        final cx = tx(op.points[0].$1);
        final cy = ty(op.points[0].$2);
        final rx = op.points[1].$1 * scale;
        final ry = op.points[1].$2 * scale;
        canvas.drawEllipse(cx, cy, rx, ry);
        if (fill != null && stroke != null) {
          canvas
            ..setFillColor(fill)
            ..setStrokeColor(stroke)
            ..fillAndStrokePath();
        } else if (fill != null) {
          canvas
            ..setFillColor(fill)
            ..fillPath();
        } else if (stroke != null) {
          canvas
            ..setStrokeColor(stroke)
            ..strokePath();
        }
      case CDrawKind.text:
        break;
    }
  }
  canvas.setLineDashPattern(const []);
}
