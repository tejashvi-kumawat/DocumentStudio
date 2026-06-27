import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview uses decimal and roman', () {
    expect(
      previewPdfPageLabelRun(style: 'D', prefix: 'A-', startAt: 3),
      'A-3, A-4, A-5',
    );
    expect(
      previewPdfPageLabelRun(style: 'r', prefix: '', startAt: 4),
      'iv, v, vi',
    );
    expect(
      previewPdfPageLabelRun(style: 'R', prefix: '', startAt: 4),
      'IV, V, VI',
    );
    expect(
      previewPdfPageLabelRun(style: 'Cambria', prefix: '', startAt: 2),
      '2, 3, 4',
    );
  });

  test('all pages replaces existing labels', () {
    final ranges = mergePdfPageLabels(
      existing: const [
        PdfPageLabelRange(startIndex0: 0, style: 'r', startAt: 1),
      ],
      pageCount: 5,
      edit: const PdfPageLabelEdit(
        allPages: true,
        fromPage1: 1,
        toPage1: 5,
        beginNewSection: true,
        style: 'D',
        prefix: 'P',
        startAt: 10,
      ),
    );
    expect(ranges, hasLength(1));
    expect(ranges.single.startIndex0, 0);
    expect(ranges.single.style, 'D');
    expect(ranges.single.prefix, 'P');
    expect(ranges.single.startAt, 10);
    expect(resolvePdfPageLabel(page1Based: 1, ranges: ranges), 'P10');
  });

  test('a middle section resumes the previous numbering after it', () {
    final ranges = mergePdfPageLabels(
      existing: const [
        PdfPageLabelRange(startIndex0: 0, style: 'r', startAt: 1),
      ],
      pageCount: 8,
      edit: const PdfPageLabelEdit(
        allPages: false,
        fromPage1: 5,
        toPage1: 6,
        beginNewSection: true,
        style: 'D',
        startAt: 1,
      ),
    );
    expect(ranges.map((r) => r.startIndex0), [0, 4, 6]);
    expect(resolvePdfPageLabel(page1Based: 4, ranges: ranges), 'iv');
    expect(resolvePdfPageLabel(page1Based: 5, ranges: ranges), '1');
    expect(resolvePdfPageLabel(page1Based: 6, ranges: ranges), '2');
    expect(resolvePdfPageLabel(page1Based: 7, ranges: ranges), 'vii');
  });

  test('extend drops section starts inside the selected pages', () {
    final ranges = mergePdfPageLabels(
      existing: const [
        PdfPageLabelRange(startIndex0: 0, style: 'D', startAt: 1),
        PdfPageLabelRange(startIndex0: 4, style: 'r', startAt: 1),
        PdfPageLabelRange(startIndex0: 7, style: 'D', startAt: 20),
      ],
      pageCount: 10,
      edit: const PdfPageLabelEdit(
        allPages: false,
        fromPage1: 5,
        toPage1: 7,
        beginNewSection: false,
      ),
    );
    expect(ranges.map((r) => r.startIndex0), [0, 7]);
    expect(resolvePdfPageLabel(page1Based: 5, ranges: ranges), '5');
    expect(resolvePdfPageLabel(page1Based: 8, ranges: ranges), '20');
  });
}
