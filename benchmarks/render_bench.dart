// Render and text-extraction timing at several scales.
// Usage: dart benchmarks/render_bench.dart <pdf>
import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

Future<void> main(List<String> args) async {
  await pdfrxInitialize();
  final doc = await PdfDocument.openFile(args.single);
  try {
    final n = doc.pages.length;
    stdout.writeln('pages=$n');
    for (final long in [1000.0, 1500.0, 2300.0, 3400.0]) {
      final sw = Stopwatch()..start();
      var count = 0;
      for (var i = 0; i < 6 && i < n; i++) {
        final page = await doc.pages[i].ensureLoaded();
        final k = long / (page.width > page.height ? page.width : page.height);
        final img = await page.render(
          fullWidth: page.width * k,
          fullHeight: page.height * k,
          backgroundColor: 0xffffffff,
        );
        img?.dispose();
        count++;
      }
      stdout.writeln('render long-edge ${long.toInt()}px: '
          '${(sw.elapsedMilliseconds / count).toStringAsFixed(0)} ms/page');
    }
    final sw = Stopwatch()..start();
    var chars = 0;
    final limit = n < 300 ? n : 300;
    for (var i = 0; i < limit; i++) {
      final page = await doc.pages[i].ensureLoaded();
      final t = await page.loadText();
      chars += t?.fullText.length ?? 0;
    }
    stdout.writeln('text of first $limit pages: ${sw.elapsedMilliseconds} ms '
        '(${(sw.elapsedMilliseconds / limit).toStringAsFixed(1)} ms/page, $chars chars)');
  } finally {
    await doc.dispose();
  }
}
