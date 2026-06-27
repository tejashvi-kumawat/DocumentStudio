import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/document_properties_dialog.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakePdfRenderPort implements PdfRenderPort {
  _FakePdfRenderPort(this.info, {this.onLoad});

  final PdfDocumentInfo info;
  final void Function(LocalFileRef file, {String? password})? onLoad;

  @override
  Future<PdfDocumentInfo> loadInfo(LocalFileRef file, {String? password}) async {
    onLoad?.call(file, password: password);
    return info;
  }

  @override
  Future<bool> validateOpenable(LocalFileRef file, {String? password}) async =>
      true;

  @override
  Future<String> extractPlainText(LocalFileRef file, {String? password}) async =>
      '';
}

void main() {
  const sampleInfo = PdfDocumentInfo(
    pageCount: 12,
    title: 'Quarterly Report',
    author: 'Document Studio QA',
    encrypted: false,
  );

  group('displayDocumentProperty', () {
    test('returns em dash for empty values', () {
      expect(displayDocumentProperty(null), '—');
      expect(displayDocumentProperty(''), '—');
      expect(displayDocumentProperty('   '), '—');
    });

    test('returns trimmed text', () {
      expect(displayDocumentProperty('  Title  '), 'Title');
    });
  });

  group('formatDocumentByteSize', () {
    test('formats bytes KB and MB', () {
      expect(formatDocumentByteSize(null), '—');
      expect(formatDocumentByteSize(512), '512 B');
      expect(formatDocumentByteSize(2048), '2.0 KB');
      expect(formatDocumentByteSize(5 * 1024 * 1024), '5.00 MB');
    });
  });

  group('displayDocumentEncryption', () {
    test('maps encrypted flag', () {
      expect(displayDocumentEncryption(null), '—');
      expect(displayDocumentEncryption(false), 'Not encrypted');
      expect(displayDocumentEncryption(true), 'Password protected');
    });
  });

  group('DocumentPropertiesPanel', () {
    testWidgets('shows title, author, and page count', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPropertiesPanel(
              info: sampleInfo,
              fileSizeBytes: 1024,
            ),
          ),
        ),
      );

      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Document Studio QA'), findsOneWidget);
      expect(find.text('Pages'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('File size'), findsOneWidget);
      expect(find.text('1.0 KB'), findsOneWidget);
      expect(find.text('Security'), findsOneWidget);
      expect(find.text('Not encrypted'), findsOneWidget);
    });
  });

  group('showDocumentProperties', () {
    testWidgets('loads info and shows dialog on wide layout', (tester) async {
      String? loadPassword;
      final file = LocalFileRef(
        path: '/docs/report.pdf',
        displayName: 'report.pdf',
        sizeBytes: 1024,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(800, 600)),
            child: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showDocumentProperties(
                    context: context,
                    pdf: _FakePdfRenderPort(
                      sampleInfo,
                      onLoad: (_, {password}) => loadPassword = password,
                    ),
                    file: file,
                    password: 'cached-secret',
                  ),
                  child: const Text('Open properties'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open properties'));
      await tester.pumpAndSettle();

      expect(loadPassword, 'cached-secret');
      expect(find.text('Document properties'), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
      expect(find.text('Document Studio QA'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Edit metadata'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Document properties'), findsNothing);
    });

    testWidgets('uses bottom sheet on narrow layout', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(400, 700)),
            child: Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showDocumentProperties(
                    context: context,
                    pdf: _FakePdfRenderPort(sampleInfo),
                    file: LocalFileRef(path: '/a.pdf', displayName: 'a.pdf'),
                  ),
                  child: const Text('Open properties'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open properties'));
      await tester.pumpAndSettle();

      expect(find.text('Document properties'), findsNothing);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Quarterly Report'), findsOneWidget);
    });
  });
}
