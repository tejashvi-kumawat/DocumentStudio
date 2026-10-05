import 'dart:io';

import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads Liberation Sans metrics like Helvetica', () {
    final f = TtfFont.parse(
      File('assets/fonts/text/LiberationSans-Regular.ttf').readAsBytesSync(),
    )!;
    expect(f.family, contains('Liberation'));
    expect(f.bold, isFalse);
    // Helvetica widths: "A"=667, "i"=222, space=278 (per 1000 em).
    expect(f.advance1000('A'.codeUnitAt(0)).round(), 667);
    expect(f.advance1000('i'.codeUnitAt(0)).round(), 222);
    expect(f.advance1000(' '.codeUnitAt(0)).round(), 278);
    expect(f.winAnsiWidths().length, 224);
  });

  test('bold and italic flags', () {
    final b = TtfFont.parse(
      File('assets/fonts/text/LiberationSerif-BoldItalic.ttf').readAsBytesSync(),
    )!;
    expect(b.bold, isTrue);
    expect(b.italic, isTrue);
  });

  test('garbage is rejected', () {
    expect(TtfFont.parse(File('pubspec.yaml').readAsBytesSync()), isNull);
  });
}
