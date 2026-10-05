import 'dart:convert';
import 'dart:io';

import 'package:document_studio/core/fonts/font_library.dart';
import 'package:document_studio/infrastructure/pdf/ttf_font.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every bundled library font is a usable TrueType font', () {
    final index = jsonDecode(
      File('assets/fonts/library/index.json').readAsStringSync(),
    ) as List<dynamic>;
    expect(index.length, greaterThanOrEqualTo(50));
    for (final fam in index.cast<Map<String, dynamic>>()) {
      for (final f in (fam['files'] as List).cast<Map<String, dynamic>>()) {
        final bytes = File('assets/fonts/library/${f['file']}').readAsBytesSync();
        final ttf = TtfFont.parse(bytes);
        expect(ttf, isNotNull, reason: '${f['file']}');
        expect(ttf!.textWidthPt('Hello', 10), greaterThan(0));
      }
    }
  });

  test('identifies PDF font names', () async {
    final lib = FontLibrary.instance;
    await lib.ensureLoaded();
    expect(lib.library.length, greaterThanOrEqualTo(50));
    expect(lib.libraryFamilyFor('ABCDEF+Montserrat-SemiBold'), 'Montserrat');
    expect(lib.libraryFamilyFor('Calibri-Bold'), 'Carlito');
    expect(lib.libraryFamilyFor('TimesNewRomanPSMT'), 'Tinos');
    expect(lib.libraryFamilyFor('ArialMT'), 'Arimo');
    expect(lib.libraryFamilyFor('NotoSansDisplay-Bold'), 'Noto Sans Display');
    expect(lib.libraryFamilyFor('RobotoCondensed-Regular'), 'Roboto Condensed');
    expect(lib.libraryFamilyFor('XyzUnknownFace'), isNull);
    final f = await lib.resolveOriginal('QWERTY+Lato-BoldItalic');
    expect(f?.libraryFamily, 'Lato');
    expect(f!.ttf.bold, isTrue);
    expect(f.ttf.italic, isTrue);
    expect(lib.matchOriginal('Lato-BoldItalic'), same(f));
  });
}
