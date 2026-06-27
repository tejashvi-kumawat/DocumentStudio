import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:test/test.dart';

void main() {
  test('buildQpdfPageSpec merges consecutive pages', () {
    expect(buildQpdfPageSpec([1, 2, 3, 5, 7, 8]), '1-3,5,7-8');
  });

  test('buildQpdfPageSpec single page', () {
    expect(buildQpdfPageSpec([4]), '4');
  });
}
