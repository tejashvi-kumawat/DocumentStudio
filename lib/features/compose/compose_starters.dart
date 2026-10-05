import 'package:document_studio/features/compose/compose_model.dart';

/// A first document per language that shows what the composer can do.
String composeStarter(ComposeLanguage l) => switch (l) {
  ComposeLanguage.markdown => _md,
  ComposeLanguage.html => _html,
  ComposeLanguage.latex => _latex,
};

const _md = r'''# My document

Write **Markdown** on the left — the PDF updates on the right.
Everything runs on this device, without internet.

## Text

*Italic*, **bold**, ~~struck~~, `code`, and [a link](https://example.com).

> A quotation stands out like this.

## Lists

- Bullets with `-`
  - Nested by indenting
- [x] Task lists
- [ ] with check boxes

1. Numbered
2. Lists

## Maths

Inline $E = mc^2$ and a display formula:

$$
\int_0^\infty e^{-x^2}\,dx = \frac{\sqrt{\pi}}{2}
$$

## Table

| Item   | Qty | Price |
| :----- | :-: | ----: |
| Pens   |  3  |  4.50 |
| Paper  |  1  |  9.99 |

```
Code blocks keep their spacing.
```
''';

const _html = r'''<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>My document</title>
  <style>@page { size: A4; }</style>
</head>
<body>
  <h1>My document</h1>
  <p>Write <b>HTML</b> on the left; the PDF updates on the right —
     on this device, no browser needed.</p>

  <h2>Styling</h2>
  <p style="text-align:center">
    <span style="color:#d32f2f; font-weight:bold">Red and bold</span>,
    <i>italic</i>, <u>underlined</u>, x<sup>2</sup>, H<sub>2</sub>O.
  </p>

  <h2>Lists and tables</h2>
  <ul>
    <li>First</li>
    <li>Second</li>
  </ul>
  <table>
    <caption>Prices</caption>
    <tr><th>Item</th><th>Price</th></tr>
    <tr><td>Pens</td><td style="text-align:right">4.50</td></tr>
  </table>

  <h2>Maths</h2>
  <p>Inline \( a^2 + b^2 = c^2 \) and display:</p>
  <p>\[ \sum_{k=1}^{n} k = \frac{n(n+1)}{2} \]</p>
</body>
</html>
''';

const _latex = r'''\documentclass[11pt,a4paper]{article}
\usepackage{amsmath}
\usepackage{graphicx}

\title{My Document}
\author{Your Name}
\date{\today}

\begin{document}
\maketitle

\begin{abstract}
Write \LaTeX{} on the left; the PDF updates on the right. It is
typeset on this device --- no TeX installation, no internet.
\end{abstract}

\tableofcontents

\section{Introduction}\label{sec:intro}
Text can be \textbf{bold}, \textit{italic}, \underline{underlined},
\texttt{typewriter} or \textcolor{blue}{coloured}.\footnote{Footnotes are
collected at the end.} Section~\ref{sec:intro} refers to itself.

\section{Mathematics}
Inline maths such as $e^{i\pi} + 1 = 0$, and a numbered equation:
\begin{equation}\label{eq:gauss}
  \int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
\end{equation}
Equation~\eqref{eq:gauss} is the Gaussian integral.
\begin{align}
  (a+b)^2 &= a^2 + 2ab + b^2 \\
  (a-b)^2 &= a^2 - 2ab + b^2
\end{align}

\section{Lists and tables}
\begin{itemize}
  \item First point
  \item Second point
  \begin{enumerate}
    \item Nested and numbered
  \end{enumerate}
\end{itemize}

\begin{table}[h]
  \centering
  \begin{tabular}{|l|c|r|}
    \hline
    Left & Centre & Right \\
    \hline
    1 & 2 & 3 \\
    \hline
  \end{tabular}
  \caption{A small table}
\end{table}

\end{document}
''';
