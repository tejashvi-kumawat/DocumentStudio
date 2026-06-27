import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:document_studio/features/page_management/tools/split_tool_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPdfRenderPort implements PdfRenderPort {
  @override
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password}) async {
    return const PdfDocumentInfo(pageCount: 12);
  }

  @override
  Future<bool> validateOpenable(LocalFileRef file, {String? password}) async {
    return true;
  }

  @override
  Future<String> extractPlainText(LocalFileRef file, {String? password}) async =>
      '';
}

void main() {
  testWidgets('split tool mounts with organize chrome', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: SplitToolScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Split PDF'), findsOneWidget);
    expect(find.text('Split & save'), findsOneWidget);
    expect(find.text('Drop a PDF here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('split tool shows method segments and every-N controls when loaded',
      (tester) async {
    const file = LocalFileRef(
      path: '/tmp/corpus.pdf',
      displayName: 'corpus.pdf',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfRenderPortProvider.overrideWithValue(_StubPdfRenderPort()),
        ],
        child: const MaterialApp(
          home: SplitToolScreen(initialFile: file),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Every N'), findsOneWidget);
    expect(find.text('One / page'), findsOneWidget);
    expect(find.text('Ranges'), findsOneWidget);
    expect(find.text('Selected'), findsOneWidget);
    expect(find.text('Pages per file'), findsOneWidget);

    await tester.tap(find.text('Ranges'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Custom ranges (1-based)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
