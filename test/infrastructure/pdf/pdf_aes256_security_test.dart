import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/pdf_aes256_security.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('R6 user entry verifies only the right password', () {
    final m = PdfAes256SecurityMaterial.build(
      userPassword: 'correct horse',
      allowPrinting: true,
      allowModify: false,
      allowExtract: true,
      allowAnnotate: true,
    );
    expect(m.u.length, 48);
    expect(m.o.length, 48);
    expect(m.ue.length, 32);
    expect(m.perms.length, 16);
    expect(PdfAes256SecurityMaterial.verifyUser('correct horse', m.u), isTrue);
    expect(PdfAes256SecurityMaterial.verifyUser('wrong', m.u), isFalse);
  });

  test('every string/stream gets a fresh IV', () {
    final m = PdfAes256SecurityMaterial.build(
      userPassword: 'a',
      allowPrinting: true,
      allowModify: true,
      allowExtract: true,
      allowAnnotate: true,
    );
    final d = Uint8List.fromList(List.filled(40, 7));
    expect(m.encryptStream(d, 1, 0), isNot(m.encryptStream(d, 1, 0)));
  });
}
