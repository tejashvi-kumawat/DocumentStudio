import 'dart:typed_data';

import 'package:document_studio_ocr/document_studio_ocr.dart';
import 'package:test/test.dart';

/// Compile-time check that feature code can depend on [OcrPort] / [SearchablePdfPort].
class _FakeOcrPort implements OcrPort {
  @override
  Future<OcrTextResult> recognizeText(
    Uint8List imageBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    return OcrTextResult(text: 'stub', language: options.language);
  }
}

class _FakeSearchablePdfPort implements SearchablePdfPort {
  @override
  Future<Uint8List> createSearchablePdf(
    Uint8List pdfBytes, {
    OcrOptions options = const OcrOptions(),
  }) async {
    return pdfBytes;
  }
}

void main() {
  test('OcrPort and SearchablePdfPort interfaces compile', () {
    final OcrPort ocr = _FakeOcrPort();
    final SearchablePdfPort searchable = _FakeSearchablePdfPort();
    expect(ocr, isA<OcrPort>());
    expect(searchable, isA<SearchablePdfPort>());
    expect(const BlockedOcrPort(), isA<OcrPort>());
    expect(const BlockedSearchablePdfPort(), isA<SearchablePdfPort>());
  });
}
