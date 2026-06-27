import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/core/storage/local_file_storage.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_embedded_files.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('empty catalog lists no embedded files', () {
    final files = listPdfEmbeddedFiles(_minimalPdf());
    expect(files, isEmpty);
  });

  test('reads EmbeddedFiles name tree and /EF bytes without page content', () {
    const payload = 'hello attachment';
    final pdf = _pdfWithEmbedded([
      _Emb('notes.txt', payload, description: 'A note'),
    ]);
    final files = listPdfEmbeddedFiles(pdf);
    expect(files, hasLength(1));
    expect(files.single.name, 'notes.txt');
    expect(files.single.fileName, 'notes.txt');
    expect(files.single.description, 'A note');
    expect(files.single.declaredBytes, payload.length);
    expect(
      extractPdfEmbeddedFileBytes(pdf, 0),
      Uint8List.fromList(payload.codeUnits),
    );
    expect(String.fromCharCodes(pdf).contains('page-only-text'), isFalse);
  });

  test('walks a Kids name tree and decodes FlateDecode /EF streams', () {
    const plain = 'csv,1\n';
    final pdf = _pdfWithEmbedded([
      _Emb('report.csv', plain, flate: true),
      _Emb('photo.bin', 'abc'),
    ], nested: true);
    final files = listPdfEmbeddedFiles(pdf);
    expect(files.map((f) => f.fileName), ['report.csv', 'photo.bin']);
    expect(
      extractPdfEmbeddedFileBytes(pdf, 0),
      Uint8List.fromList(plain.codeUnits),
    );
    expect(
      extractPdfEmbeddedFileBytes(pdf, 1),
      Uint8List.fromList('abc'.codeUnits),
    );
  });

  test('encrypted files are not listed as attachments', () {
    expect(
      () => listPdfEmbeddedFiles(_encryptedPdf()),
      throwsA(
        isA<PdfEmbeddedFileException>().having(
          (e) => e.message,
          'message',
          'Unlock this PDF to see attachments.',
        ),
      ),
    );
  });

  test('save refuses a path that would replace the open PDF', () async {
    final dir = await Directory.systemTemp.createTemp('ds_att_guard_');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File(p.join(dir.path, 'doc.pdf'));
    await pdf.writeAsBytes(const [1, 2, 3, 4]);
    final storage = _RecordingStorage();
    expect(
      () => writePdfAttachmentFile(
        storage: storage,
        directory: dir.path,
        fileName: 'doc.pdf',
        bytes: Uint8List.fromList([9]),
        protectedPdfPaths: [pdf.path],
      ),
      throwsA(
        isA<PdfEmbeddedFileException>().having(
          (e) => e.message,
          'message',
          contains('not replaced'),
        ),
      ),
    );
    expect(storage.writes, 0);
    expect(await pdf.readAsBytes(), [1, 2, 3, 4]);
  });

  test('session file extract and save do not rewrite the PDF', () async {
    final dir = await Directory.systemTemp.createTemp('ds_att_path_');
    addTearDown(() => dir.delete(recursive: true));
    final pdf = File(p.join(dir.path, 'session.pdf'));
    final original = _pdfWithEmbedded([_Emb('notes.txt', 'hello attachment')]);
    await pdf.writeAsBytes(original);

    final files = await listPdfEmbeddedFilesAtPath(pdf.path);
    expect(files.single.fileName, 'notes.txt');
    final extracted = await extractPdfEmbeddedFileAtPath(pdf.path, 0);
    expect(String.fromCharCodes(extracted), 'hello attachment');

    final opened = await writeExtractedAttachmentToTemp(
      bytes: extracted,
      fileName: files.single.fileName,
      protectedPdfPaths: [pdf.path],
    );
    expect(opened == pdf.path, isFalse);
    expect(await File(opened).readAsString(), 'hello attachment');

    final out = Directory(p.join(dir.path, 'saved'))..createSync();
    final saved = await writePdfAttachmentFile(
      storage: LocalFileStorage(),
      directory: out.path,
      fileName: files.single.fileName,
      bytes: extracted,
      protectedPdfPaths: [pdf.path],
    );
    expect(saved == pdf.path, isFalse);
    expect(await File(saved).readAsString(), 'hello attachment');
    expect(await pdf.readAsBytes(), original);
  });

  test('sanitizeAttachmentFileName drops directories', () {
    expect(sanitizeAttachmentFileName(r'..\..\etc\passwd'), 'passwd');
    expect(sanitizeAttachmentFileName('..'), 'attachment');
  });
}

class _Emb {
  _Emb(this.name, this.text, {this.flate = false, this.description});
  final String name;
  final String text;
  final bool flate;
  final String? description;
}

Uint8List _minimalPdf() {
  final objects = <String>[
    '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n',
    '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n',
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj\n',
  ];
  final b = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[0];
  for (final obj in objects) {
    offsets.add(b.length);
    b.write(obj);
  }
  final xref = b.length;
  b.write('xref\n0 ${objects.length + 1}\n');
  b.write('0000000000 65535 f \n');
  for (var i = 1; i < offsets.length; i++) {
    b.write('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer<< /Size ${objects.length + 1} /Root 1 0 R >>\n');
  b.write('startxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(b.toString().codeUnits);
}

Uint8List _pdfWithEmbedded(List<_Emb> files, {bool nested = false}) {
  final doc = PdfCosDocument.parse(_minimalPdf());
  final writer = PdfIncrementalWriter(doc);
  final pairs = <PdfObj>[];
  for (final file in files) {
    final plain = Uint8List.fromList(file.text.codeUnits);
    final raw = file.flate ? pdfDeflate(plain) : plain;
    final dict = PdfDict({
      'Type': const PdfName('EmbeddedFile'),
      'Subtype': const PdfName('text/plain'),
      'Params': PdfDict({'Size': PdfNum(plain.length)}),
    });
    if (file.flate) dict['Filter'] = const PdfName('FlateDecode');
    final streamRef = writer.add(PdfStream(dict, raw));
    final spec = PdfDict({
      'Type': const PdfName('Filespec'),
      'F': PdfString.text(file.name),
      'UF': PdfString.text(file.name),
      'EF': PdfDict({'UF': streamRef, 'F': streamRef}),
    });
    if (file.description != null) {
      spec['Desc'] = PdfString.text(file.description!);
    }
    pairs
      ..add(PdfString.text(file.name))
      ..add(writer.add(spec));
  }
  final leaf = writer.add(PdfDict({'Names': PdfArray(pairs)}));
  final tree = nested
      ? writer.add(
          PdfDict({
            'Kids': PdfArray([leaf]),
          }),
        )
      : leaf;
  final catalog = doc.catalog.clone();
  catalog['Names'] = PdfDict({'EmbeddedFiles': tree});
  final root = doc.rootRef;
  if (root == null) fail('catalog ref missing');
  writer.put(root, catalog);
  return writer.build();
}

Uint8List _encryptedPdf() {
  final b = StringBuffer('%PDF-1.4\n');
  b.write('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n');
  b.write('2 0 obj<< /Type /Pages /Kids [] /Count 0 >>endobj\n');
  b.write('99 0 obj<< /Filter /Standard >>endobj\n');
  b.write('trailer<< /Size 100 /Root 1 0 R /Encrypt 99 0 R >>\n');
  b.write('startxref\n0\n%%EOF\n');
  return Uint8List.fromList(b.toString().codeUnits);
}

class _RecordingStorage implements FileStoragePort {
  int writes = 0;

  @override
  Future<void> writeAtomic({
    required String destinationPath,
    required Future<void> Function(String tempPath) writeToTemp,
  }) async {
    writes++;
    await writeToTemp('$destinationPath.partial');
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
  Future<String?> pickOutputDirectory({String? dialogTitle}) =>
      throw UnimplementedError();

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
