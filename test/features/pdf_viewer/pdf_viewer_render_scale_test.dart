import 'package:document_studio/features/pdf_viewer/pdf_approach_pages.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('screen scale is capped at 1600px on the long edge', () {
    const wide = 2400.0;
    const tall = 1600.0;
    final settled = pdfViewerSettledRenderScale(
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(settled * wide, kPdfSettledRenderLongEdgePx);
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

  testWidgets('scrolling still requests the one screen scale', (tester) async {
    final pace = PdfViewerRenderPace();
    addTearDown(pace.dispose);
    const wide = 2400.0;
    const tall = 1600.0;

    double screen() => pace.scaleFor(
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );

    final still = screen();
    expect(still * wide, kPdfSettledRenderLongEdgePx);

    pace.noteMotion();
    expect(pace.isMoving, isTrue);
    final moving = screen();
    expect(moving, still);
    expect(moving * wide, kPdfSettledRenderLongEdgePx);

    await tester.pump(kPdfScrollSettleDelay);
    expect(pace.isMoving, isFalse);
    expect(screen(), still);
    expect(
      pdfApproachScaleFor(
        moving: true,
        inViewport: false,
        pageWidth: wide,
        pageHeight: tall,
        zoom: 1,
        devicePixelRatio: 1,
      ),
      still,
    );
  });

  test('a small zoom-in keeps a screen-scale bitmap', () {
    const page = 800.0;
    final atFit = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1,
      devicePixelRatio: 1,
    );
    final slight = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1.1,
      devicePixelRatio: 1,
    );
    expect(atFit, 1);
    expect(slight, 1.1);
    expect(pdfViewerKeepsRenderedScale(held: atFit, target: slight), isTrue);
  });

  test('zooming out keeps a sharper bitmap', () {
    const page = 800.0;
    final sharp = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1.5,
      devicePixelRatio: 1,
    );
    final smaller = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(sharp, greaterThan(smaller));
    expect(pdfViewerKeepsRenderedScale(held: sharp, target: smaller), isTrue);
  });

  test('a zoom-in that would look soft asks for the new screen scale', () {
    const page = 800.0;
    final held = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 1,
      devicePixelRatio: 1,
    );
    final target = pdfViewerSettledRenderScale(
      pageWidth: page,
      pageHeight: page,
      zoom: 2,
      devicePixelRatio: 1,
    );
    expect(pdfViewerKeepsRenderedScale(held: held, target: target), isFalse);
    expect(target, 2);
    expect(target * page, kPdfSettledRenderLongEdgePx);
  });

  test('a bitmap below the screen scale is not kept', () {
    const wide = 2400.0;
    final screen = pdfViewerSettledRenderScale(
      pageWidth: wide,
      pageHeight: 1600,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(
      pdfViewerKeepsRenderedScale(held: 400 / wide, target: screen),
      isFalse,
    );
  });

  test('approaching window is the visible page plus one each side', () {
    final layouts = [
      for (var i = 0; i < 10; i++) Rect.fromLTWH(0, i * 1000, 800, 1000),
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

  test('moving, settled, and neighbor pages share one full-quality scale', () {
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
    final settled = pdfApproachScaleFor(
      moving: false,
      inViewport: true,
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    final neighbor = pdfApproachScaleFor(
      moving: false,
      inViewport: false,
      pageWidth: wide,
      pageHeight: tall,
      zoom: 1,
      devicePixelRatio: 1,
    );
    expect(moving, settled);
    expect(neighbor, settled);
    expect(settled * wide, kPdfSettledRenderLongEdgePx);
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
