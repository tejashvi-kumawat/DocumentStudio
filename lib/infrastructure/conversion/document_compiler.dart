import 'dart:convert';
import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:path/path.dart' as p;

/// Source languages "Create PDF" can compile.
enum DocumentSourceKind { markdown, html, latex }

/// Result of a compile: the PDF path, or an error with the engine's log.
class CompileResult {
  const CompileResult.ok(this.pdfPath, this.engine) : error = null;
  const CompileResult.failed(this.error, {this.engine}) : pdfPath = null;

  final String? pdfPath;
  final String? engine;
  final String? error;
  bool get ok => pdfPath != null;
}

/// Compiles Markdown, HTML or LaTeX into a PDF on this device.
///
/// * HTML / Markdown → a headless Chromium-family browser (Chrome, Edge,
///   Chromium, Brave) prints the page, so CSS, web fonts, tables and images
///   come out exactly as in the browser; without one, the bundled
///   LibreOffice converts the HTML.
/// * Markdown is first turned into styled HTML (GitHub-flavoured: tables,
///   code blocks, task lists, footnotes).
/// * LaTeX → Tectonic, LuaLaTeX, XeLaTeX or pdfLaTeX, whichever is installed
///   (run twice for references / tables of contents; Tectonic handles that).
class DocumentCompiler {
  const DocumentCompiler();

  static const _browsers = [
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
    'microsoft-edge',
    'msedge',
    'brave-browser',
    'chrome',
  ];

  static const _latexEngines = ['tectonic', 'lualatex', 'xelatex', 'pdflatex'];

  /// First available browser for HTML printing.
  Future<String?> findBrowser() async {
    if (Platform.isWindows) {
      for (final root in [
        Platform.environment['ProgramFiles(x86)'],
        Platform.environment['ProgramFiles'],
        Platform.environment['LOCALAPPDATA'],
      ]) {
        if (root == null) continue;
        for (final rel in [
          r'Microsoft\Edge\Application\msedge.exe',
          r'Google\Chrome\Application\chrome.exe',
          r'BraveSoftware\Brave-Browser\Application\brave.exe',
        ]) {
          final f = File(p.join(root, rel));
          if (f.existsSync()) return f.path;
        }
      }
    }
    if (Platform.isMacOS) {
      for (final app in [
        '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
        '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
        '/Applications/Chromium.app/Contents/MacOS/Chromium',
        '/Applications/Brave Browser.app/Contents/MacOS/Brave Browser',
      ]) {
        if (File(app).existsSync()) return app;
      }
    }
    for (final b in _browsers) {
      final path = await desktopEngineResolver.resolve(b);
      if (path != null) return path;
    }
    return null;
  }

  /// First available LaTeX engine (name, path).
  Future<(String, String)?> findLatex() async {
    for (final e in _latexEngines) {
      final path = await desktopEngineResolver.resolve(e);
      if (path != null) return (e, path);
    }
    return null;
  }

  /// Which engines this device has, for the UI.
  Future<Map<DocumentSourceKind, String?>> availableEngines() async {
    final browser = await findBrowser();
    final office = await desktopEngineResolver.resolveSoffice();
    final latex = await findLatex();
    final htmlEngine = browser != null
        ? p.basenameWithoutExtension(browser)
        : (office != null ? 'LibreOffice' : null);
    return {
      DocumentSourceKind.markdown: htmlEngine,
      DocumentSourceKind.html: htmlEngine,
      DocumentSourceKind.latex: latex?.$1,
    };
  }

  Future<CompileResult> compile({
    required DocumentSourceKind kind,
    required String source,
    required String outputPath,
    String title = 'Document',
    String pageSize = 'A4', // A4 | Letter
    String? baseDir,
  }) async {
    switch (kind) {
      case DocumentSourceKind.markdown:
        return _html(markdownToHtml(source, title: title, pageSize: pageSize),
            outputPath, baseDir);
      case DocumentSourceKind.html:
        return _html(source, outputPath, baseDir);
      case DocumentSourceKind.latex:
        return _latex(source, outputPath, baseDir);
    }
  }

  /// Markdown → a complete, print-styled HTML page.
  static String markdownToHtml(
    String source, {
    String title = 'Document',
    String pageSize = 'A4',
  }) {
    final body = md.markdownToHtml(
      source,
      extensionSet: md.ExtensionSet.gitHubWeb,
    );
    final t = const HtmlEscape().convert(title);
    return '''<!doctype html>
<html><head><meta charset="utf-8"><title>$t</title>
<style>
@page { size: $pageSize; margin: 20mm 18mm; }
body { font-family: "Segoe UI", "Inter", "Noto Sans", Arial, sans-serif;
  font-size: 11pt; line-height: 1.55; color: #1f2328; }
h1, h2, h3, h4 { line-height: 1.25; margin: 1.2em 0 .5em; }
h1 { font-size: 22pt; border-bottom: 1px solid #d0d7de; padding-bottom: .2em; }
h2 { font-size: 16pt; border-bottom: 1px solid #d8dee4; padding-bottom: .15em; }
h3 { font-size: 13pt; }
p, ul, ol, table, pre, blockquote { margin: 0 0 .8em; }
code { font-family: "JetBrains Mono", Consolas, "Courier New", monospace;
  font-size: 9.5pt; background: #f6f8fa; padding: .1em .3em; border-radius: 4px; }
pre { background: #f6f8fa; padding: 10px 12px; border-radius: 6px;
  overflow-wrap: anywhere; white-space: pre-wrap; }
pre code { background: none; padding: 0; }
blockquote { border-left: 4px solid #d0d7de; color: #57606a; padding: 0 1em; margin-left: 0; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #d0d7de; padding: 5px 9px; text-align: left; }
th { background: #f6f8fa; }
img { max-width: 100%; }
hr { border: 0; border-top: 1px solid #d0d7de; margin: 1.5em 0; }
h1, h2, h3 { page-break-after: avoid; }
pre, table, img { page-break-inside: avoid; }
</style></head><body>
$body
</body></html>''';
  }

  Future<CompileResult> _html(
    String html,
    String outputPath,
    String? baseDir,
  ) async {
    final dir = await Directory.systemTemp.createTemp('ds_compile_');
    try {
      // Relative images / CSS resolve against the source file's folder.
      final folder = baseDir ?? dir.path;
      final src = File(p.join(folder, '.ds_compile_${DateTime.now().microsecondsSinceEpoch}.html'));
      await src.writeAsString(html, flush: true);
      try {
        final browser = await findBrowser();
        if (browser != null) {
          final r = await Process.run(browser, [
            '--headless=new',
            '--disable-gpu',
            '--no-sandbox',
            '--no-pdf-header-footer',
            '--user-data-dir=${p.join(dir.path, 'profile')}',
            '--print-to-pdf=$outputPath',
            Uri.file(src.path).toString(),
          ]).timeout(const Duration(minutes: 2));
          if (await File(outputPath).exists() &&
              await File(outputPath).length() > 0) {
            return CompileResult.ok(outputPath, p.basenameWithoutExtension(browser));
          }
          return CompileResult.failed(
            'The browser could not print this page.\n${r.stderr}',
            engine: p.basenameWithoutExtension(browser),
          );
        }
        final office = await desktopEngineResolver.resolveSoffice();
        if (office != null) {
          final out = p.join(dir.path, 'out');
          await Directory(out).create();
          final r = await Process.run(office, [
            '--headless',
            '--norestore',
            '-env:UserInstallation=${Uri.directory(p.join(dir.path, 'lo')).toString()}',
            '--convert-to',
            'pdf:writer_web_pdf_Export',
            '--outdir',
            out,
            src.path,
          ]).timeout(const Duration(minutes: 3));
          final pdf = File(p.join(out, '${p.basenameWithoutExtension(src.path)}.pdf'));
          if (await pdf.exists()) {
            await pdf.copy(outputPath);
            return CompileResult.ok(outputPath, 'LibreOffice');
          }
          return CompileResult.failed(
            'LibreOffice could not convert the page.\n${r.stderr}',
            engine: 'LibreOffice',
          );
        }
        return const CompileResult.failed(
          'HTML and Markdown need Chrome, Edge or Chromium (or LibreOffice) '
          'on this computer.',
        );
      } finally {
        try {
          await src.delete();
        } catch (_) {}
      }
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Future<CompileResult> _latex(
    String tex,
    String outputPath,
    String? baseDir,
  ) async {
    final engine = await findLatex();
    if (engine == null) {
      return const CompileResult.failed(
        'LaTeX needs a TeX engine. Install Tectonic (small, downloads '
        'packages on demand: tectonic-typesetting.github.io) or TeX Live / '
        'MiKTeX, then try again.',
      );
    }
    final (name, exe) = engine;
    final dir = await Directory.systemTemp.createTemp('ds_tex_');
    try {
      final src = File(p.join(dir.path, 'document.tex'));
      await src.writeAsString(tex, flush: true);
      final env = <String, String>{
        if (baseDir != null) 'TEXINPUTS': '$baseDir${Platform.isWindows ? ';' : ':'}',
      };
      ProcessResult r;
      if (name == 'tectonic') {
        r = await Process.run(
          exe,
          ['--keep-logs', '--outdir', dir.path, src.path],
          workingDirectory: baseDir ?? dir.path,
          environment: env,
        ).timeout(const Duration(minutes: 5));
      } else {
        final args = [
          '-interaction=nonstopmode',
          '-halt-on-error',
          '-output-directory=${dir.path}',
          src.path,
        ];
        r = await Process.run(exe, args,
                workingDirectory: baseDir ?? dir.path, environment: env)
            .timeout(const Duration(minutes: 5));
        if (r.exitCode == 0) {
          // Second pass for references and the table of contents.
          r = await Process.run(exe, args,
                  workingDirectory: baseDir ?? dir.path, environment: env)
              .timeout(const Duration(minutes: 5));
        }
      }
      final pdf = File(p.join(dir.path, 'document.pdf'));
      if (r.exitCode == 0 && await pdf.exists()) {
        await pdf.copy(outputPath);
        return CompileResult.ok(outputPath, name);
      }
      final log = File(p.join(dir.path, 'document.log'));
      final text = await log.exists() ? await log.readAsString() : '${r.stdout}\n${r.stderr}';
      return CompileResult.failed(_latexError(text), engine: name);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// The first LaTeX error and its line, not the whole log.
  static String _latexError(String log) {
    final lines = log.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('!') || lines[i].contains('error:')) {
        return lines.skip(i).take(6).join('\n').trim();
      }
    }
    final tail = lines.length > 15 ? lines.sublist(lines.length - 15) : lines;
    return tail.join('\n').trim();
  }
}
