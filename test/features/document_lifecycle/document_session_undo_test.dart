import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('ds_sess_test_'));
  tearDown(() => dir.deleteSync(recursive: true));

  Uint8List blob(int n, int v) => Uint8List(n)..fillRange(0, n, v);

  for (final size in [1000, 6 * 1024 * 1024]) {
    test('undo / redo restore exact bytes ($size B)', () async {
      final src = File('${dir.path}/doc.pdf')..writeAsBytesSync(blob(size, 1));
      final s = DocumentSession(
        file: LocalFileRef(path: src.path, displayName: 'doc.pdf'),
      );
      await s.commitBytes(blob(size, 2));
      await s.commitBytes(blob(size, 3));
      expect((await s.readCurrentBytes())[10], 3);
      expect(await s.undo(), isTrue);
      expect((await s.readCurrentBytes())[10], 2);
      expect(await s.undo(), isTrue);
      expect((await s.readCurrentBytes())[10], 1);
      expect(await s.redo(), isTrue);
      expect((await s.readCurrentBytes())[10], 2);
      // The user's original is untouched until Save.
      expect(src.readAsBytesSync()[10], 1);
      expect(await s.save(), DocumentSaveOutcome.savedInPlace);
      expect(src.readAsBytesSync()[10], 2);
      s.dispose();
    });
  }

  test('commitTempFile moves the file in and can be undone', () async {
    final src = File('${dir.path}/doc.pdf')..writeAsBytesSync(blob(5000, 1));
    final s = DocumentSession(
      file: LocalFileRef(path: src.path, displayName: 'doc.pdf'),
    );
    final tmp = File('${dir.path}/result.pdf')..writeAsBytesSync(blob(7000, 9));
    expect(await s.commitTempFile(tmp.path), DocumentSaveOutcome.savedInPlace);
    expect(tmp.existsSync(), isFalse);
    expect((await s.readCurrentBytes()).length, 7000);
    expect(s.isDirty, isTrue);
    expect(await s.undo(), isTrue);
    expect((await s.readCurrentBytes())[0], 1);
    s.dispose();
  });
}
