import 'dart:io';

import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:test/test.dart';

void main() {
  test('cropPagesToBox sets CropBox via JSON update', () async {
    final qpdf = File('../../.tools/qpdf/bin/qpdf');
    if (!qpdf.existsSync()) {
      // ignore: avoid_print
      print('skip: portable qpdf missing');
      return;
    }

    final dir = await Directory.systemTemp.createTemp('qpdf_crop_test_');
    final input = File('${dir.path}/in.pdf');
    // Minimal PDF repaired by qpdf first.
    input.writeAsBytesSync(
      File('/tmp/hello-clean.pdf').readAsBytesSync(),
    );
    final output = '${dir.path}/out.pdf';
    final runner = QpdfCliRunner(executable: qpdf.absolute.path);
    await runner.cropPagesToBox(
      inputPath: input.path,
      outputPath: output,
      box: const PdfCropRectPt(llx: 40, lly: 40, urx: 400, ury: 600),
      pages1Based: {1},
    );
    expect(File(output).existsSync(), isTrue);
    expect(File(output).lengthSync(), greaterThan(0));

    final dump = await Process.run(qpdf.absolute.path, [
      '--json-output',
      '--json-key=pages',
      output,
    ]);
    expect(dump.exitCode, 0);
    expect(dump.stdout.toString(), contains('/CropBox'));
    await dir.delete(recursive: true);
  });
}
