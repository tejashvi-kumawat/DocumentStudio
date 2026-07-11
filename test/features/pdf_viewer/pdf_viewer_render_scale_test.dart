import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('moving preview is 400px and never sharper than the settled bitmap', () {
    const wide = 2400.0;
    const tall = 1600.0;
    final settled = pdfViewerSettledRenderScale(
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(settled * wide, kPdfSettledRenderLongEdgePx);

    final preview = pdfViewerMovingPreviewScale(
      pageWidth: wide,
      pageHeight: tall,
      settledScale: settled,
    );
    expect(preview * wide, kPdfMovingPreviewLongEdgePx);
    expect(preview, lessThan(settled));
  });

  test('settled scale follows the screen when that is under 1600px', () {
    const page = 800.0;
    final settled = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(settled, 1);
    expect(settled * page, lessThan(kPdfSettledRenderLongEdgePx));
  });

  test('a fling keeps a settled page and previews only a new one', () {
    final pace = PdfViewerRenderPace();
    addTearDown(pace.dispose);

    final settled = pace.scaleFor(
      pageNumber: 3,
      pageWidth: 2400,
      pageHeight: 1600,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(settled * 2400, kPdfSettledRenderLongEdgePx);

    pace.noteMotion();
    expect(pace.isMoving, isTrue);
    expect(
      pace.scaleFor(
        pageNumber: 3,
        pageWidth: 2400,
        pageHeight: 1600,
        zoom: 1,
        devicePixelRatio: 1,
      ),
      settled,
    );
    final incoming = pace.scaleFor(
      pageNumber: 4,
      pageWidth: 2400,
      pageHeight: 1600,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(incoming * 2400, kPdfMovingPreviewLongEdgePx);
  });
}
