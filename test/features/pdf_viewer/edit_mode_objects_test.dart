
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_markup_host.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _size = Size(400, 560);

Future<ViewerLiveToolSession> _pump(WidgetTester tester) async {
  final s = ViewerLiveToolSession();
  s.setPageGeometryPt(widthPt: 400, heightPt: 560);
  s.activate(ViewerToolId.editText, pageIndex1Based: 1);
  s.setTextRunsForPage(1, const [
    LiveTextEditTarget(
      normRect: Rect.fromLTRB(0.1, 0.1, 0.5, 0.15),
      originalText: 'Heading',
      fontSizePt: 14,
    ),
  ]);
  s.setImagesForPage(1, const [
    EditableImage(
      page: 1,
      name: 'Im0',
      opStart: 10,
      normRect: Rect.fromLTRB(0.1, 0.5, 0.6, 0.8),
    ),
    // A highlight over the heading must still be selectable.
    EditableImage(
      page: 1,
      name: 'Highlight',
      opStart: 0,
      normRect: Rect.fromLTRB(0.12, 0.11, 0.2, 0.14),
      kind: EditableKind.annotation,
    ),
  ]);
  await tester.pumpWidget(
    ProviderScope(child: MaterialApp(
      home: Material(child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox.fromSize(
          size: _size,
          child: LiveMarkupPageHost(
            session: s,
            geom: const LivePageGeom(
              pageNumber: 1,
              pagePx: _size,
              pageWidthPt: 400,
              pageHeightPt: 560,
            ),
          ),
        ),
      ),
    ))),
  );
  await tester.pump();
  return s;
}

Future<void> _tap(WidgetTester tester, Offset norm) async {
  await tester.tapAt(Offset(norm.dx * _size.width, norm.dy * _size.height));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('text under the picture layer can be selected then edited',
      (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.4, 0.125));
    expect(s.selectedRun?.originalText, 'Heading');
    await _tap(tester, const Offset(0.4, 0.125));
    expect(s.textEditTarget?.originalText, 'Heading');
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a picture is selected, empty space deselects', (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.3, 0.6));
    expect(s.selectedImage?.name, 'Im0');
    expect(find.text('Image'), findsOneWidget);
    await _tap(tester, const Offset(0.9, 0.95));
    expect(s.selectedImage, isNull);
    expect(s.textEditTarget, isNull);
  });

  testWidgets('an annotation over text wins', (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.15, 0.125));
    expect(s.selectedImage?.kind, EditableKind.annotation);
    expect(find.text('Highlight'), findsOneWidget);
  });

  testWidgets('dragging a picture asks to move it', (tester) async {
    final s = await _pump(tester);
    ImageEditRequest? got;
    s.imageEditHandler = (r) => got = r;
    final g = await tester.startGesture(const Offset(120, 360));
    for (var i = 1; i <= 6; i++) {
      await g.moveTo(Offset(120 + i * 10, 360));
      await tester.pump();
    }
    await g.up();
    await tester.pump();
    expect(got?.kind, ImageEditKind.move);
    expect(got!.rect!.left, greaterThan(0.2));
  });

  testWidgets('Delete removes a selected text block', (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.4, 0.125));
    expect(s.selectedRun, isNotNull);
    final before = s.textCommitRequestId;
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(s.textCommitRequestId, before + 1);
    expect(s.labelText, '');
    expect(s.textEditTarget?.originalText, 'Heading');
  });

  testWidgets('selection bar edits and deletes a text block', (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.4, 0.125));
    expect(find.byKey(const Key('live_text_sel_delete')), findsOneWidget);
    await tester.tap(find.byKey(const Key('live_text_sel_edit')));
    await tester.pump();
    expect(s.textEditTarget?.originalText, 'Heading');
    // The open block offers Delete too.
    final before = s.textCommitRequestId;
    await tester.tap(find.byKey(const Key('live_text_delete')));
    await tester.pump();
    expect(s.textCommitRequestId, before + 1);
    expect(s.labelText, '');
  });

  testWidgets('a moved block is a change worth saving', (tester) async {
    final s = await _pump(tester);
    await _tap(tester, const Offset(0.4, 0.125));
    await _tap(tester, const Offset(0.4, 0.125));
    expect(s.textEditChanged, isFalse);
    s.setPlacement(s.placement.copyWith(left: s.placement.left + 0.1));
    expect(s.textEditChanged, isTrue);
  });
}
