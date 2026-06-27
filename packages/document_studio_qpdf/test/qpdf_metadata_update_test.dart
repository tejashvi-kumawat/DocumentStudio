import 'dart:convert';
import 'dart:io';

import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String? _findBundledQpdf() {
  final roots = [
    p.join(Directory.current.path, 'build/linux/x64/debug/bundle/engines/qpdf'),
    p.join(Directory.current.path, '../../build/linux/x64/debug/bundle/engines/qpdf'),
    p.join(Directory.current.path, '.tools/qpdf/bin/qpdf'),
    p.join(Directory.current.path, '../../.tools/qpdf/bin/qpdf'),
  ];
  for (final path in roots) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

void main() {
  test('updateDocumentInfo writes Title via update-from-json', () async {
    final qpdfPath = _findBundledQpdf();
    if (qpdfPath == null) {
      // ignore: avoid_print
      print('skip: bundled/portable qpdf missing');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('qpdf_meta_test_');
    try {
      final input = p.join(dir.path, 'in.pdf');
      final output = p.join(dir.path, 'out.pdf');
      final create = await Process.run(qpdfPath, ['--empty', '--', input]);
      expect(create.exitCode, anyOf(0, 3));

      final runner = QpdfCliRunner(executable: qpdfPath);
      await runner.updateDocumentInfo(
        inputPath: input,
        outputPath: output,
        fields: const {
          'Title': 'Meta Test Title',
          'Author': 'Document Studio',
          'Subject': '',
        },
      );
      expect(File(output).existsSync(), isTrue);

      final dump = await Process.run(qpdfPath, ['--json-output', output, '-']);
      expect(dump.exitCode, anyOf(0, 3));
      final root = jsonDecode(dump.stdout.toString()) as Map<String, dynamic>;
      final objects = (root['qpdf'] as List)[1] as Map<String, dynamic>;
      final trailer = objects['trailer']['value'] as Map<String, dynamic>;
      final infoRef = trailer['/Info'] as String;
      final info = objects['obj:$infoRef']['value'] as Map<String, dynamic>;
      expect(info['/Title'], 'u:Meta Test Title');
      expect(info['/Author'], 'u:Document Studio');
      expect(info.containsKey('/Subject'), isFalse);
    } finally {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  });
}
