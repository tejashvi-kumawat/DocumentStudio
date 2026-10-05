import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/page_management/tools/delete_pages_tool_screen.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubPdfRenderPort implements PdfRenderPort {
  @override
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password}) async {
    return const PdfDocumentInfo(pageCount: 3);
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
  testWidgets('delete pages tool mounts with export preview path', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: DeletePagesToolScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Delete pages'), findsOneWidget);
    expect(find.text('Save PDF without deleted pages'), findsOneWidget);

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save PDF without deleted pages')).onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('delete export save enabled after PDF import (export preview gate)',
      (tester) async {
    const file = LocalFileRef(path: '/tmp/delete.pdf', displayName: 'delete.pdf');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pdfRenderPortProvider.overrideWithValue(_StubPdfRenderPort()),
        ],
        child: const MaterialApp(home: DeletePagesToolScreen(initialFile: file)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save PDF without deleted pages')).onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });
}
