import 'dart:io';

import 'package:document_studio/infrastructure/conversion/document_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('markdown becomes styled HTML with tables', () {
    final html = DocumentCompiler.markdownToHtml(
      '# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n```dart\nmain() {}\n```',
      title: 'T <x>',
    );
    expect(html, contains('>Title</h1>'));
    expect(html, contains('<table>'));
    expect(html, contains('<title>T &lt;x&gt;</title>'));
    expect(html, contains('@page { size: A4'));
  });

  test('compiles markdown to PDF when a browser is installed', () async {
    const c = DocumentCompiler();
    if (await c.findBrowser() == null) return;
    final dir = Directory.systemTemp.createTempSync('dc_t');
    final out = '${dir.path}/o.pdf';
    final r = await c.compile(
      kind: DocumentSourceKind.markdown,
      source: '# Hello Compiler\n\nSome *text*.',
      outputPath: out,
    );
    expect(r.error, isNull);
    expect(File(out).readAsBytesSync().take(4), '%PDF'.codeUnits);
    final copy = Platform.environment['DS_MD_OUT'];
    if (copy != null) File(out).copySync(copy);
    dir.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
