import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:flutter/material.dart';
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

  test('approaching window is the visible page plus one each side', () {
    final layouts = [
      for (var i = 0; i < 10; i++)
        Rect.fromLTWH(0, i * 1000, 800, 1000),
    ];
    final onPage5 = pdfApproachPageWindow(
      layouts: layouts,
      visible: const Rect.fromLTWH(0, 4200, 800, 800),
    );
    expect(onPage5.visiblePages, {5});
    expect(onPage5.decodePages, {4, 5, 6});

    final two = pdfApproachPageWindow(
      layouts: layouts,
      visible: const Rect.fromLTWH(0, 4500, 800, 1000),
    );
    expect(two.visiblePages, {5, 6});
    expect(two.decodePages, {4, 5, 6, 7});

    final first = pdfApproachPageWindow(
      layouts: layouts,
      visible: const Rect.fromLTWH(0, 0, 800, 400),
    );
    expect(first.visiblePages, {1});
    expect(first.decodePages, {1, 2});
    expect(first.decodePages.contains(10), isFalse);
  });

  test('decode order is the current page, then ahead, then behind', () {
    expect(
      pdfApproachDecodeOrder(
        visiblePages: {5, 6},
        decodePages: {4, 5, 6, 7},
        currentPage: 5,
      ),
      [5, 6, 7, 4],
    );
    expect(kPdfApproachMaxDecodes, 2);
    expect(kPdfThumbMaxDecodes, 2);
  });

  test('only the settled visible page is upgraded to 1600px', () {
    const wide = 2400.0;
    const tall = 1600.0;
    final moving = pdfApproachScaleFor(
      moving: true,
      inViewport: true,
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(moving * wide, kPdfMovingPreviewLongEdgePx);

    final settled = pdfApproachScaleFor(
      moving: false,
      inViewport: true,
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(settled * wide, kPdfSettledRenderLongEdgePx);

    final neighbor = pdfApproachScaleFor(
      moving: false,
      inViewport: false,
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(neighbor * wide, kPdfMovingPreviewLongEdgePx);
  });

  test('thumbnail strip offset follows the page index', () {
    expect(
      pdfThumbStripOffset(pageNumber: 1, stride: 210, maxScrollExtent: 4000),
      0,
    );
    expect(
      pdfThumbStripOffset(pageNumber: 10, stride: 210, maxScrollExtent: 4000),
      1890,
    );
    expect(
      pdfThumbStripOffset(pageNumber: 40, stride: 210, maxScrollExtent: 1000),
      1000,
    );
  });
}
