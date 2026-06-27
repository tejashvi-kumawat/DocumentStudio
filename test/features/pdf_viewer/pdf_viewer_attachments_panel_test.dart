import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_attachments_panel.dart';
import 'package:document_studio/infrastructure/pdf/pdf_embedded_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('says No attachments and drops the engine placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 168,
              height: 420,
              child: PdfViewerAttachmentsPanel(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No attachments'), findsOneWidget);
    expect(find.byKey(const Key('pdf_attachments_empty')), findsOneWidget);
    expect(find.textContaining('Embedded files are not listed'), findsNothing);
    expect(find.textContaining('engine exposes'), findsNothing);
  });

  testWidgets('lists an embedded file with Open and Save', (tester) async {
    const payload = 'hello attachment';
    final opened = <String>[];

    await tester.pumpWidget(
      _app(
        pdfPath: '/tmp/session.pdf',
        protected: const ['/tmp/session.pdf', '/tmp/original.pdf'],
        storage: _DirStorage('/tmp'),
        loadFiles: (path) async {
          expect(path, '/tmp/session.pdf');
          return const [
            PdfEmbeddedFile(
              name: 'notes.txt',
              fileName: 'notes.txt',
              description: 'A note',
              declaredBytes: payload.length,
            ),
          ];
        },
        extractBytes: (_, _) async => Uint8List.fromList(payload.codeUnits),
        openExtractedFile: (path) async {
          opened.add(path);
          return true;
        },
      ),
    );
    await tester.pump();

    expect(find.text('notes.txt'), findsOneWidget);
    expect(find.text('A note'), findsOneWidget);
    expect(find.byKey(const Key('pdf_attachment_open_0')), findsOneWidget);
    expect(find.byKey(const Key('pdf_attachment_save_0')), findsOneWidget);
    expect(find.text('No attachments'), findsNothing);
    expect(find.textContaining('Embedded files are not listed'), findsNothing);

    await tester.tap(find.byKey(const Key('pdf_attachment_open_0')));
    await tester.pumpAndSettle();
    expect(find.text('Open attachment?'), findsOneWidget);
    expect(
      find.textContaining('The PDF itself is not changed.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('pdf_attachment_open_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Open attachment?'), findsNothing);
    expect(opened, isEmpty);
  });
}

Widget _app({
  required String pdfPath,
  required List<String> protected,
  required FileStoragePort storage,
  required Future<List<PdfEmbeddedFile>> Function(String path) loadFiles,
  required Future<Uint8List> Function(String path, int index) extractBytes,
  required Future<bool> Function(String path) openExtractedFile,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 168,
          height: 420,
          child: PdfViewerAttachmentsPanel(
            pdfPath: pdfPath,
            protectedPdfPaths: protected,
            storage: storage,
            loadFiles: loadFiles,
            extractBytes: extractBytes,
            openExtractedFile: openExtractedFile,
          ),
        ),
      ),
    ),
  );
}

class _DirStorage implements FileStoragePort {
  _DirStorage(this.directory);
  final String directory;

  @override
  Future<String?> pickOutputDirectory({String? dialogTitle}) async => directory;

  @override
  Future<void> writeAtomic({
    required String destinationPath,
    required Future<void> Function(String tempPath) writeToTemp,
  }) async {
    final temp = '$destinationPath.partial';
    await writeToTemp(temp);
    final file = File(temp);
    if (await File(destinationPath).exists()) {
      await File(destinationPath).delete();
    }
    await file.rename(destinationPath);
  }

  @override
  Future<LocalFileRef> copyToTemp(
    LocalFileRef source, {
    required String prefix,
  }) => throw UnimplementedError();

  @override
  Future<String> createTempFile({required String prefix, String? suffix}) =>
      throw UnimplementedError();

  @override
  Future<void> deleteIfExists(String path) => throw UnimplementedError();

  @override
  Future<bool> fileExists(LocalFileRef ref) => throw UnimplementedError();

  @override
  Future<String> getAppSupportDirectory() => throw UnimplementedError();

  @override
  Future<String> getTempDirectory() => throw UnimplementedError();

  @override
  Future<LocalFileRef?> pickOpenFile({List<String>? allowedExtensions}) =>
      throw UnimplementedError();

  @override
  Future<List<LocalFileRef>> pickOpenFiles({
    List<String>? allowedExtensions,
    bool allowMultiple = true,
  }) => throw UnimplementedError();

  @override
  Future<String?> pickSavePath({
    required String suggestedName,
    required Uint8List bytes,
    List<String>? allowedExtensions,
    String mimeType = 'application/octet-stream',
  }) => throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(LocalFileRef ref) => throw UnimplementedError();
}
