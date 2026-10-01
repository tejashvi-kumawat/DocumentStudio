import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/viewer_live_page_overlay.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:document_studio/infrastructure/pdf/pdf_text_blank_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Rect _glyph(double x, double y, double w, double h, {double page = 1000}) {
  return Rect.fromLTWH(x / page, y / page, w / page, h / page);
}

List<PdfFormSpot> _detect(String text, List<Rect> rects) {
  return detectTextLayerBlanks(
    text: text,
    normRects: rects,
    pageIndex1Based: 2,
    pageWidthPt: 1000,
    pageHeightPt: 1000,
  );
}

void main() {
  test('run of underscores is one tappable blank', () {
    final rects = [
      for (var i = 0; i < 6; i++) _glyph(120 + i * 10, 200, 10, 3),
    ];
    final spots = _detect('______', rects);
    expect(spots, hasLength(1));
    expect(spots.single.pageIndex1Based, 2);
    expect(spots.single.kind, PdfFormSpotKind.text);
    expect(spots.single.name, 'Line 1');
    expect(spots.single.normRect.left, closeTo(0.12, 0.001));
    expect(spots.single.normRect.width, closeTo(0.06, 0.01));
  });

  test('dotted leaders and spaced dots are blanks', () {
    final dots = _detect(
      '..........',
      [for (var i = 0; i < 10; i++) _glyph(80 + i * 8, 300, 6, 3)],
    );
    expect(dots, hasLength(1));
    expect(dots.single.name, 'Dots 1');

    final spaced = StringBuffer();
    final rects = <Rect>[];
    for (var i = 0; i < 5; i++) {
      spaced.write('.');
      rects.add(_glyph(40 + i * 16, 320, 4, 3));
      if (i != 4) {
        spaced.write(' ');
        rects.add(_glyph(46 + i * 16, 320, 4, 3));
      }
    }
    final leaders = _detect(spaced.toString(), rects);
    expect(leaders, hasLength(1));
    expect(leaders.single.name, 'Dots 1');
  });

  test('a wide run of spaces on a line is a blank', () {
    final text = StringBuffer('Name:');
    final rects = <Rect>[
      _glyph(40, 180, 12, 12),
      _glyph(52, 180, 12, 12),
      _glyph(64, 180, 12, 12),
      _glyph(76, 180, 12, 12),
      _glyph(88, 180, 8, 12),
    ];
    for (var i = 0; i < 8; i++) {
      text.write(' ');
      rects.add(Rect.fromLTWH(0.11, 0.186, 0, 0));
    }
    text.write('Date');
    rects.add(_glyph(220, 180, 14, 12));
    rects.add(_glyph(234, 180, 14, 12));
    rects.add(_glyph(248, 180, 14, 12));
    rects.add(_glyph(262, 180, 14, 12));

    final spots = _detect(text.toString(), rects);
    expect(spots, hasLength(1));
    expect(spots.single.name, 'Blank 1');
    expect(spots.single.normRect.left, closeTo(0.096, 0.01));
    expect(spots.single.normRect.right, closeTo(0.22, 0.01));
  });

  test('ordinary prose, ellipsis, and a single underscore are not fields', () {
    final prose = _detect(
      'Hello world. See 3.14...',
      [
        for (var i = 0; i < 'Hello world. See 3.14...'.length; i++)
          _glyph(40 + (i % 24) * 8, 100 + (i ~/ 24) * 16, 7, 11),
      ],
    );
    expect(prose, isEmpty);

    final ellipsis = _detect(
      '...',
      [
        _glyph(40, 100, 4, 3),
        _glyph(46, 100, 4, 3),
        _glyph(52, 100, 4, 3),
      ],
    );
    expect(ellipsis, isEmpty);

    final word = _detect(
      'file_name',
      [for (var i = 0; i < 9; i++) _glyph(40 + i * 8, 140, 7, 11)],
    );
    expect(word, isEmpty);
  });

  test('text blanks do not cover an AcroForm widget on the same rect', () {
    final session = ViewerLiveToolSession();
    const widget = PdfFormSpot(
      id: 'acro_2_0',
      name: 'Name',
      kind: PdfFormSpotKind.text,
      pdfRect: Rect.fromLTRB(100, 700, 400, 720),
      normRect: Rect.fromLTRB(0.1, 0.2, 0.4, 0.24),
      pageIndex1Based: 2,
    );
    session.addAcroFormSpots([widget]);
    session.setDetectedTextBlanks(2, [
      const PdfFormSpot(
        id: 'textblank_2_0',
        name: 'Line 1',
        kind: PdfFormSpotKind.text,
        pdfRect: Rect.fromLTRB(100, 700, 400, 720),
        normRect: Rect.fromLTRB(0.1, 0.2, 0.4, 0.24),
        pageIndex1Based: 2,
      ),
      const PdfFormSpot(
        id: 'textblank_2_1',
        name: 'Line 2',
        kind: PdfFormSpotKind.text,
        pdfRect: Rect.fromLTRB(100, 500, 400, 520),
        normRect: Rect.fromLTRB(0.1, 0.5, 0.4, 0.54),
        pageIndex1Based: 2,
      ),
    ]);
    expect(session.formSpots.map((s) => s.id), ['acro_2_0', 'textblank_2_1']);
    expect(session.formPageScanned(2), isTrue);
    expect(session.formPageEmptyMessage(2), isNull);
    expect(session.formPageEmptyMessage(3), isNull);

    session.setDetectedTextBlanks(3, const []);
    expect(session.formPageEmptyMessage(3), noFillInBlanksOnPageMessage);
    session.dispose();
  });

  testWidgets('scanned page with no blank says so, a real blank is a field', (tester) async {
    final session = ViewerLiveToolSession();
    session.activate(ViewerToolId.fillForm, pageIndex1Based: 1);
    session.setDetectedTextBlanks(1, const []);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ViewerLiveToolOverlaySurface(session: session),
        ),
      ),
    );
    await tester.pump();
    expect(find.text(noFillInBlanksOnPageMessage), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    session.setFormSpots([
      const PdfFormSpot(
        id: 'name',
        name: 'Name',
        kind: PdfFormSpotKind.text,
        pdfRect: Rect.fromLTRB(72, 650, 300, 680),
        normRect: Rect.fromLTRB(0.2, 0.2, 0.6, 0.28),
      ),
    ]);
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(noFillInBlanksOnPageMessage), findsNothing);
    session.dispose();
  });

  test('scan queue checks the open page before farther pages', () {
    final session = ViewerLiveToolSession();
    session.requestFormPageScan(1);
    session.requestFormPageScan(9);
    session.requestFormPageScan(4);
    session.requestFormPageScan(4);
    expect(session.takeNextFormScanPage(4), 4);
    expect(session.takeNextFormScanPage(4), 1);
    expect(session.takeNextFormScanPage(4), 9);
    expect(session.takeNextFormScanPage(4), isNull);
    session.dispose();
  });
}
