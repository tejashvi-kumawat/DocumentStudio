import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/merge_tool_screen.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPdfRenderPort implements PdfRenderPort {
  @override
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password}) async {
    return const PdfDocumentInfo(pageCount: 2);
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
  testWidgets('merge tool mounts with organize chrome', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: MergeToolScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Merge PDFs'), findsOneWidget);
    expect(find.text('Merge & save'), findsOneWidget);
    expect(find.text('Drop PDF files here'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge disabled with one PDF (export preview gate)', (tester) async {
    const one = LocalFileRef(path: '/tmp/a.pdf', displayName: 'a.pdf');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfRenderPortProvider.overrideWithValue(_StubPdfRenderPort()),
        ],
        child: const MaterialApp(
          home: MergeToolScreen(initialFiles: [one]),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge & save')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge enabled after two PDFs load (export preview gate)', (tester) async {
    const one = LocalFileRef(path: '/tmp/a.pdf', displayName: 'a.pdf');
    const two = LocalFileRef(path: '/tmp/b.pdf', displayName: 'b.pdf');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfRenderPortProvider.overrideWithValue(_StubPdfRenderPort()),
        ],
        child: const MaterialApp(
          home: MergeToolScreen(initialFiles: [one, two]),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Merge & save')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('merge shows per-document preview when source tapped',
      (tester) async {
    const one = LocalFileRef(path: '/tmp/a.pdf', displayName: 'a.pdf');
    const two = LocalFileRef(path: '/tmp/b.pdf', displayName: 'b.pdf');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfRenderPortProvider.overrideWithValue(_StubPdfRenderPort()),
        ],
        child: const MaterialApp(
          home: MergeToolScreen(initialFiles: [one, two]),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.text('b.pdf'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('b.pdf'), findsWidgets);
    expect(find.textContaining('pages'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
