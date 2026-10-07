import 'dart:io';

import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_pdf.dart';
import 'package:document_studio/features/compose/math_raster.dart';
import 'package:document_studio/features/compose/parsers/html_to_model.dart';
import 'package:document_studio/features/compose/parsers/latex_to_model.dart';
import 'package:document_studio/features/compose/parsers/markdown_to_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _latex = r'''
\documentclass[11pt,a4paper]{article}
\usepackage{amsmath}
\newcommand{\R}{\mathbb{R}}
\title{Composer Test}
\author{Tejashvi Kumawat}
\date{October 2026}
\begin{document}
\maketitle
\tableofcontents
\section{Introduction}\label{sec:intro}
Hello \textbf{bold} and \emph{emphasis}, inline $e^{i\pi}+1=0$ in $\R$.
See Section~\ref{sec:intro} and Equation~\eqref{eq:1}.\footnote{A note.}

\begin{equation}\label{eq:1}
  \int_0^1 x^2\,dx = \frac{1}{3}
\end{equation}
\subsection{Lists}
\begin{itemize}
  \item First
  \item Second with \texttt{code}
  \begin{enumerate}
    \item Nested
  \end{enumerate}
\end{itemize}
\begin{table}[h]
\centering
\begin{tabular}{|l|c|r|}
\hline
A & B & C \\
\hline
1 & 2 & 3 \\
\hline
\end{tabular}
\caption{Numbers}
\end{table}
\begin{align}
a &= b + c \\
d &= e
\end{align}
\end{document}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('LaTeX parses into the document model', () {
    final doc = latexToCompose(_latex);
    expect(doc.title, 'Composer Test');
    final heads = doc.blocks.whereType<CHeading>().toList();
    expect(heads.first.number, '1');
    expect(heads[1].number, '1.1');
    final para = doc.blocks.whereType<CPara>().first;
    final text = para.inlines.map((i) => i.text).join();
    expect(text, contains('See Section 1 and Equation (1)'));
    expect(para.inlines.where((i) => i.math != null).length, 2);
    expect(para.inlines.any((i) => i.bold && i.text == 'bold'), isTrue);
    expect(doc.footnotes, hasLength(1));
    final eqs = doc.blocks.whereType<CMath>().toList();
    expect(eqs.first.number, '(1)');
    expect(eqs.last.tex, startsWith(r'\begin{aligned}'));
    final list = doc.blocks.whereType<CList>().single;
    expect(list.items, hasLength(2));
    expect(list.items[1].whereType<CList>().single.ordered, isTrue);
    final table = doc.blocks.whereType<CTable>().single;
    expect(table.rows, hasLength(2));
    expect(table.caption!.map((i) => i.text).join(), 'Table 1: Numbers');
  });

  test('Markdown and HTML parse', () {
    final md = markdownToCompose('# T\n\nA **b** \$x^2\$\n\n\$\$\ny=1\n\$\$\n\n- [x] done\n- [ ] todo\n\n| a | b |\n|---|--:|\n| 1 | 2 |');
    expect(md.blocks.whereType<CHeading>().single.level, 1);
    expect(md.blocks.whereType<CMath>().single.tex, 'y=1');
    expect(md.blocks.whereType<CList>().single.labels, isNotNull);
    expect(md.blocks.whereType<CTable>().single.aligns![1], CAlign.right);
    final html = htmlToCompose('<h2 style="color:red">H</h2><p>a <b>b</b> \\(x\\)</p><ul><li>one</li></ul><table><tr><th>A</th></tr><tr><td>1</td></tr></table>');
    expect(html.blocks.whereType<CHeading>().single.level, 2);
    expect(html.blocks.whereType<CPara>().single.inlines.any((i) => i.math == 'x'), isTrue);
    expect(html.blocks.whereType<CTable>().single.header, isTrue);
  });

  test('TikZ subset, boxes, vfill, and newenvironment do not warn', () {
    const src = r'''
\documentclass{article}
\newcommand{\x}{x}
\newenvironment{tipbox}{\textbf{Tip:}\par}{\par}
\begin{document}
\begin{tikzpicture}
  \draw[thick, blue] (0,0) -- (2,1) -- (2,0);
  \fill[red] (0.5,0.5) circle (0.3);
  \node at (1,1.2) {A};
\end{tikzpicture}
\begin{questionbox}
What is $2+2$?
\end{questionbox}
\begin{answerbox}
Four.
\end{answerbox}
\vfill
\begin{tipbox}
Remember \x.
\end{tipbox}
\end{document}
''';
    final doc = latexToCompose(src);
    final drawing = doc.blocks.whereType<CDrawing>().single;
    expect(drawing.ops, isNotEmpty);
    expect(
      drawing.ops.any((o) => o.kind == CDrawKind.line || o.kind == CDrawKind.polyline),
      isTrue,
    );
    expect(drawing.ops.any((o) => o.kind == CDrawKind.ellipse), isTrue);
    expect(drawing.ops.any((o) => o.kind == CDrawKind.text && o.text == 'A'), isTrue);

    final boxes = doc.blocks.whereType<CBox>().toList();
    expect(boxes, hasLength(2));
    expect(boxes[0].title, 'Question');
    expect(boxes[1].title, 'Answer');
    expect(doc.blocks.whereType<CSpace>(), isNotEmpty);

    final tip = doc.blocks
        .whereType<CPara>()
        .map((p) => p.inlines.map((i) => i.text).join())
        .join(' ');
    expect(tip, contains('Tip:'));
    expect(tip, contains('Remember x'));

    for (final w in doc.warnings) {
      expect(w, isNot(contains('tikzpicture')));
      expect(w, isNot(contains(r'\draw')));
      expect(w, isNot(contains(r'\fill')));
      expect(w, isNot(contains(r'\node')));
      expect(w, isNot(contains(r'\x')));
      expect(w, isNot(contains(r'\vfill')));
      expect(w, isNot(contains('questionbox')));
      expect(w, isNot(contains('answerbox')));
    }
  });

  testWidgets('renders a PDF with typeset maths', (tester) async {
    await tester.runAsync(() async {
      // Tests run with the Ahem font; load KaTeX's so the output is real.
      final dir = Directory(
        '${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/flutter_math_fork-0.7.4/lib/katex_fonts/fonts',
      );
      if (dir.existsSync()) {
        final byFamily = <String, List<File>>{};
        for (final f in dir.listSync().whereType<File>()) {
          final fam = f.uri.pathSegments.last.split('-').first;
          (byFamily[fam] ??= []).add(f);
        }
        for (final e in byFamily.entries) {
          final loader = FontLoader('packages/flutter_math_fork/${e.key}');
          for (final f in e.value) {
            loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
          await loader.load();
        }
      }
      final fonts = await ComposeFonts.load();
      final pdf = await renderComposePdf(
        latexToCompose(_latex),
        fonts: fonts,
        math: MathRaster.instance.render,
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      final out = Platform.environment['DS_COMPOSE_OUT'];
      if (out != null) File(out).writeAsBytesSync(pdf);
    });
  });
}
