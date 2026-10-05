import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/pdf_standard_security.dart';
import 'package:document_studio/infrastructure/pdf/dart_pdf_security_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AES-128 security material is 16-byte key with 32-byte O/U', () {
    final m = buildAes128Security(
      userPassword: 'secret',
      ownerPassword: 'owner',
      allowPrinting: true,
      allowModify: false,
      allowExtract: false,
      allowAnnotate: false,
    );
    expect(m.fileKey.length, 16);
    expect(m.ownerEntry.length, 32);
    expect(m.userEntry.length, 32);
    expect(m.fileId.length, 16);
  });

  test('encryptPdfBytes produces /Encrypt and opens as encrypted structure', () {
    // Minimal one-page blank-ish PDF via PdfEditDocument round-trip of a
    // tiny hand-written PDF.
    const src = '%PDF-1.4\n'
        '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
        '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
        '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj\n'
        'xref\n0 4\n'
        '0000000000 65535 f \n'
        '0000000009 00000 n \n'
        '0000000058 00000 n \n'
        '0000000115 00000 n \n'
        'trailer<< /Size 4 /Root 1 0 R >>\n'
        'startxref\n190\n%%EOF\n';
    final plain = Uint8List.fromList(src.codeUnits);
    // Fix offsets by re-parsing through editor save of unchanged doc —
    // reconstruct path accepts loose xref.
    final doc = PdfEditDocument.open(plain);
    expect(doc.isEncrypted, isFalse);
    expect(doc.trailer['Root'], isA<PdfRef>());

    final out = encryptPdfBytes(
      plain,
      userPassword: 'testpass',
      allowPrinting: true,
      allowModify: false,
      allowExtract: false,
      allowAnnotate: false,
    );
    expect(String.fromCharCodes(out).contains('/Encrypt'), isTrue);
    expect(String.fromCharCodes(out).contains('/AESV3'), isTrue);
    expect(
      () => PdfEditDocument.open(out),
      throwsA(
        isA<Object>().having(
          (e) => e.toString().toLowerCase(),
          'message',
          contains('encrypt'),
        ),
      ),
    );
  });

  test('writeInfoFields updates Title via incremental save', () {
    const src = '%PDF-1.4\n'
        '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj\n'
        '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj\n'
        '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>endobj\n'
        'xref\n0 4\n'
        '0000000000 65535 f \n'
        '0000000009 00000 n \n'
        '0000000058 00000 n \n'
        '0000000115 00000 n \n'
        'trailer<< /Size 4 /Root 1 0 R >>\n'
        'startxref\n190\n%%EOF\n';
    final doc = PdfEditDocument.open(Uint8List.fromList(src.codeUnits));
    doc.writeInfoFields({'Title': 'Hello', 'Author': 'DocStudio'});
    final saved = doc.save();
    final again = PdfEditDocument.open(saved);
    final info = again.dictOf(again.trailer['Info']);
    expect(info, isNotNull);
    expect((info!['Title'] as PdfString).text, 'Hello');
    expect((info['Author'] as PdfString).text, 'DocStudio');
  });
}
