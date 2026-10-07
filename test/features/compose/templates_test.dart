import 'dart:io';

import 'package:document_studio/features/compose/compose_screen.dart';
import 'package:document_studio/features/compose/compose_templates.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('every template compiles to a PDF', (tester) async {
    await tester.runAsync(() async {
      final dir = Directory('${Platform.environment['HOME']}/.pub-cache/hosted/pub.dev/flutter_math_fork-0.7.4/lib/katex_fonts/fonts');
      if (dir.existsSync()) {
        final byFamily = <String, List<File>>{};
        for (final f in dir.listSync().whereType<File>()) {
          (byFamily[f.uri.pathSegments.last.split('-').first] ??= []).add(f);
        }
        for (final e in byFamily.entries) {
          final loader = FontLoader('packages/flutter_math_fork/${e.key}');
          for (final f in e.value) {
            loader.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
          }
          await loader.load();
        }
      }
      final out = Platform.environment['DS_TPL_OUT'];
      expect(kComposeTemplates.map((t) => t.id).toSet().length, kComposeTemplates.length);
      for (final t in kComposeTemplates) {
        final (bytes, doc) = await compileCompose(t.language, t.source);
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-', reason: t.id);
        if (doc.warnings.isNotEmpty) {
          // ignore: avoid_print
          print('${t.id}: unsupported ${doc.warnings}');
        }
        if (out != null) File('$out/${t.id}.pdf').writeAsBytesSync(bytes);
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
