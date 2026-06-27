import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template resolves file and page variables', () {
    const file = LocalFileRef(path: '/tmp/a.pdf', displayName: 'a.pdf');
    final ctx = PdfMarkupTemplateContext(
      file: file,
      pageIndex1Based: 2,
      pageCount: 5,
      documentTitle: 'Report',
      date: DateTime(2026, 9, 27),
    );
    expect(
      ctx.resolve('{title} — {page}/{pages} ({file})'),
      'Report — 2/5 (a.pdf)',
    );
    expect(ctx.resolve('{date}'), '2026-09-27');
  });

  test('page number styles', () {
    expect(formatPageNumber(3, PageNumberStyle.arabic), '3');
    expect(formatPageNumber(4, PageNumberStyle.romanLower), 'iv');
    expect(formatPageNumber(4, PageNumberStyle.romanUpper), 'IV');
  });

  test('PageNumberOptions label respects start offset', () {
    const options = PageNumberOptions(startAt: 10, prefix: 'P-');
    expect(options.labelForPage(1), 'P-10');
    expect(options.labelForPage(2), 'P-11');
  });

  test('validatePdfMarkupTemplate catches unknown tokens and braces', () {
    expect(validatePdfMarkupTemplate('{title}'), isEmpty);
    expect(
      validatePdfMarkupTemplate('{unknown}'),
      contains('Unknown variable {unknown}'),
    );
    expect(
      validatePdfMarkupTemplate('Page {page'),
      contains('Unclosed "{" in template'),
    );
  });

  test('previewHeaderFooter resolves sample pages', () {
    const options = HeaderFooterOptions(
      headerTemplate: '{title}',
      footerTemplate: '{page}/{pages}',
    );
    final lines = previewHeaderFooter(options);
    expect(lines.length, 4);
    expect(lines.first.text, 'Sample document');
    expect(lines.last.text, '12/12');
  });

  test('validatePageNumberOptions rejects invalid start', () {
    const bad = PageNumberOptions(startAt: 0);
    expect(validatePageNumberOptions(bad), isNotEmpty);
    const ok = PageNumberOptions(startAt: 1);
    expect(validatePageNumberOptions(ok), isEmpty);
  });

  test('previewPageNumbers shows first and last sample labels', () {
    const options = PageNumberOptions(startAt: 5, prefix: '§');
    final lines = previewPageNumbers(options);
    expect(lines.map((l) => l.text).toList(), ['§5', '§16']);
  });

  test('formatBatesNumber stub pads sequence (DS-PGN-002)', () {
    expect(formatBatesNumber(1, prefix: 'ACME', minWidth: 6), 'ACME000001');
    expect(formatBatesNumber(42, prefix: 'X', minWidth: 4), 'X0042');
  });

  test('WatermarkOptions validation and preview (DS-WTM-001)', () {
    const ok = WatermarkOptions(textTemplate: '{title}');
    expect(validateWatermarkOptions(ok), isEmpty);
    expect(ok.effectiveRotationDegrees, 45);
    expect(ok.opacity, closeTo(0.2, 1e-9));
    expect(ok.behindContent, isFalse);

    const flat = WatermarkOptions(
      textTemplate: 'DRAFT',
      placement: WatermarkPlacement.center,
    );
    expect(flat.effectiveRotationDegrees, 0);

    const behind = WatermarkOptions(
      textTemplate: 'X',
      behindContent: true,
    );
    expect(behind.behindContent, isTrue);

    const badOpacity = WatermarkOptions(textTemplate: 'X', opacity: 0);
    expect(validateWatermarkOptions(badOpacity), isNotEmpty);

    final preview = previewWatermark(ok);
    expect(preview.single.text, contains('Sample document'));
  });
}
