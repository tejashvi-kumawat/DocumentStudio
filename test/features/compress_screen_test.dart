import 'package:document_studio/design_system/ds_theme.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The platform override must be cleared inside the test body.
  void body(String name, Future<void> Function(WidgetTester) f) => testWidgets(name, (tester) async {
        try {
          await f(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  Future<void> pump(WidgetTester tester, Size size, {LocalFileRef? file}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: DsTheme.light(), home: CompressScreen(initialFile: file)),
    ));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final size in const [Size(390, 800), Size(820, 900), Size(1280, 800)]) {
    body('empty state lays out at ${size.width.toInt()}px', (tester) async {
      await pump(tester, size);
      expect(find.text('Drop a PDF here'), findsOneWidget);
      expect(find.text('Compression level'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    body('with a file lays out at ${size.width.toInt()}px', (tester) async {
      await pump(tester, size, file: const LocalFileRef(path: '/nonexistent/a.pdf', displayName: 'a.pdf'));
      expect(find.text('Source PDF'), findsOneWidget);
      expect(find.text('Estimated size'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  body('wide window puts the preview beside the form', (tester) async {
    await pump(tester, const Size(1280, 800));
    final drop = tester.getCenter(find.text('Drop a PDF here'));
    final level = tester.getCenter(find.text('Compression level'));
    expect(drop.dx, greaterThan(level.dx + 300));
  });
}
