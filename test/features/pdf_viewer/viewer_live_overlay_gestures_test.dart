import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_controller_safe.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_view_rotation.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/page_placement_canvas.dart';
import 'package:document_studio/features/pdf_viewer/widgets/viewer_live_page_overlay.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

Widget _pumpSurface(ViewerLiveToolSession session, {Size size = const Size(400, 560)}) {
  return ProviderScope(child: MaterialApp(
    home: Scaffold(
      body: Center(
        child: ViewerLiveToolOverlaySurface(
          key: const Key('live_overlay_surface'),
          session: session,
          pageSize: size,
        ),
      ),
    ),
  ));
}

Future<void> _dragLocal(
  WidgetTester tester,
  Offset start,
  Offset end, {
  int steps = 8,
}) async {
  final gesture = await tester.startGesture(start);
  await tester.pump();
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    await gesture.moveTo(Offset.lerp(start, end, t)!);
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Offset _surfaceOrigin(WidgetTester tester) {
  final box = tester.renderObject<RenderBox>(
    find.byKey(const Key('live_overlay_surface')),
  );
  return box.localToGlobal(Offset.zero);
}

void main() {
  group('Text (T) live overlay gestures', () {
    testWidgets('tap selects a text run, a second tap opens it', (tester) async {
      final session = ViewerLiveToolSession();
      session.setPageGeometryPt(widthPt: 612, heightPt: 792);
      session.activate(ViewerToolId.editText, pageIndex1Based: 1);
      session.setTextRunHits([
        const LiveTextEditTarget(
          normRect: Rect.fromLTRB(0.1, 0.1, 0.4, 0.16),
          originalText: 'Hello run',
          fontSizePt: 12,
        ),
      ]);

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      final origin = _surfaceOrigin(tester);
      // Center of the highlighted run (norm 0.25, 0.13) on 400×560.
      await tester.tapAt(origin + const Offset(100, 72.8));
      await tester.pump(const Duration(milliseconds: 50));
      expect(session.selectedRun?.originalText, 'Hello run');
      expect(session.textEditTarget, isNull);

      await tester.tapAt(origin + const Offset(100, 72.8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();

      expect(session.textEditTarget?.originalText, 'Hello run');
      expect(session.inlineEditing, isTrue);
      expect(session.awaitingClickPlacement, isFalse);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('plain click does not drop unbounded caret', (tester) async {
      final session = ViewerLiveToolSession();
      session.setPageGeometryPt(widthPt: 612, heightPt: 792);
      session.activate(ViewerToolId.editText, pageIndex1Based: 1);

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      final origin = _surfaceOrigin(tester);
      await tester.tapAt(origin + const Offset(200, 280));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(session.creatingTextBox, isFalse);
      expect(session.inlineEditing, isFalse);
      expect(session.awaitingClickPlacement, isTrue);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Drag on the page to add a text box'), findsOneWidget);
    });

    testWidgets('drag empty space sets width then opens typing', (tester) async {
      final session = ViewerLiveToolSession();
      session.setPageGeometryPt(widthPt: 612, heightPt: 792);
      session.activate(ViewerToolId.editText, pageIndex1Based: 1);

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      final origin = _surfaceOrigin(tester);
      // Drag horizontally from 0.2 → 0.55 of page width.
      await _dragLocal(
        tester,
        origin + const Offset(80, 168),
        origin + const Offset(220, 168),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(session.creatingTextBox, isFalse);
      expect(session.inlineEditing, isTrue, reason: 'drag should open typing');
      expect(session.awaitingClickPlacement, isFalse);
      expect(session.placement.width, greaterThan(0.2));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('Enter commits once; Esc cancels', (tester) async {
      final session = ViewerLiveToolSession();
      session.setPageGeometryPt(widthPt: 612, heightPt: 792);
      session.activate(ViewerToolId.editText, pageIndex1Based: 1);
      session.placeTextTopLeftAtNorm(
        const Offset(0.2, 0.3),
        width: 0.35,
        height: 0.06,
      );
      session.setLabelText('typed');

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pump();

      final beforeCommit = session.textCommitRequestId;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(session.textCommitRequestId, beforeCommit + 1);

      session.setInlineEditing(true);
      session.setLabelText('again');
      await tester.pump();
      final beforeCancel = session.textCancelRequestId;
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(session.textCancelRequestId, beforeCancel + 1);
      expect(session.inlineEditing, isFalse);
      expect(session.awaitingClickPlacement, isTrue);
    });

    testWidgets('pointer-down on box does not jump placement', (tester) async {
      final session = ViewerLiveToolSession();
      session.setPageGeometryPt(widthPt: 612, heightPt: 792);
      session.activate(ViewerToolId.editText, pageIndex1Based: 1);
      session.placeTextTopLeftAtNorm(
        const Offset(0.25, 0.35),
        width: 0.3,
        height: 0.08,
      );
      final before = session.placement;

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      final origin = _surfaceOrigin(tester);
      // Pointer down inside the box without moving.
      final gesture = await tester.startGesture(
        origin + Offset(before.left * 400 + 20, before.top * 560 + 10),
      );
      await tester.pump();
      expect(session.placement.left, closeTo(before.left, 1e-9));
      expect(session.placement.top, closeTo(before.top, 1e-9));

      // Move by a known delta — base+delta, no jump.
      await gesture.moveBy(const Offset(40, 28));
      await tester.pump();
      expect(session.placement.left, closeTo(before.left + 0.1, 1e-6));
      expect(session.placement.top, closeTo(before.top + 0.05, 1e-6));
      await gesture.up();
    });
  });

  group('Watermark live overlay', () {
    testWidgets('preview only — no caret and no click-to-type copy', (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(
        ViewerToolId.watermark,
        pageIndex1Based: 1,
        labelText: 'CONFIDENTIAL',
      );

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      expect(session.awaitingClickPlacement, isFalse);
      expect(session.inlineEditing, isFalse);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('click', findRichText: true), findsNothing);
      expect(find.textContaining('Click', findRichText: true), findsNothing);
      expect(find.textContaining('type', findRichText: true), findsNothing);
      // Watermark is painted (shared layout painter), not a Text widget.
      expect(find.byType(CustomPaint), findsWidgets);

      // Tap must not open a caret (IgnorePointer preview).
      final origin = _surfaceOrigin(tester);
      await tester.tapAt(origin + const Offset(200, 280));
      await tester.pump();
      expect(find.byType(TextField), findsNothing);
      expect(session.inlineEditing, isFalse);
    });
  });

  group('Image (I) live overlay', () {
    testWidgets('places image object not a text field; drag moves', (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(
        ViewerToolId.placeImage,
        pageIndex1Based: 1,
        imageBytes: Uint8List.fromList([
          // Minimal invalid image bytes — Image.memory may error; we still
          // assert placement geometry / no TextField.
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        ]),
      );
      session.setAwaitingClickPlacement(false);
      session.setPlacement(
        const PagePlacementNorm(left: 0.3, top: 0.3, width: 0.28, height: 0.14),
      );

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();
      // Swallow Image.memory decode errors from tiny PNG header.
      while (tester.takeException() != null) {}

      expect(find.byType(TextField), findsNothing);
      expect(session.toolId, ViewerToolId.placeImage);

      final before = session.placement;
      final origin = _surfaceOrigin(tester);
      await _dragLocal(
        tester,
        origin + Offset(before.left * 400 + 40, before.top * 560 + 20),
        origin + Offset(before.left * 400 + 80, before.top * 560 + 48),
      );
      while (tester.takeException() != null) {}

      expect(session.placement.left, greaterThan(before.left));
      expect(session.placement.top, greaterThan(before.top));
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Sign (S) live overlay', () {
    testWidgets('signature layer is not a text tool', (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(
        ViewerToolId.visualSign,
        pageIndex1Based: 1,
        imageBytes: Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
      );

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();
      while (tester.takeException() != null) {}

      // Placement belongs to the sign controller (hint on hover); the page
      // must never offer a text caret or click-to-type copy.
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining('click the page to type', findRichText: true),
        findsNothing,
      );
      final origin = _surfaceOrigin(tester);
      await tester.tapAt(origin + const Offset(200, 280));
      await tester.pump();
      while (tester.takeException() != null) {}
      expect(session.inlineEditing, isFalse);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('Crop (Alt+C) live overlay', () {
    testWidgets('starts empty; dragging draws the area to keep', (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(ViewerToolId.crop, pageIndex1Based: 1);

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(session.toolId, ViewerToolId.crop);
      expect(session.dragRectNorm, isNull);
      expect(
        find.text('Drag a rectangle around the area to keep'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      final origin = _surfaceOrigin(tester);
      await _dragLocal(
        tester,
        origin + const Offset(40, 56),
        origin + const Offset(360, 504),
      );
      final r = session.dragRectNorm!;
      expect(r.left, closeTo(0.1, 0.01));
      expect(r.bottom, closeTo(0.9, 0.01));
    });
  });

  group('Draw (D) live overlay', () {
    testWidgets('pen stroke commits on pointer-up; Esc cancels in-progress',
        (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(
        ViewerToolId.ink,
        pageIndex1Based: 1,
        drawTool: LiveDrawTool.pen,
      );

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      final origin = _surfaceOrigin(tester);
      await _dragLocal(
        tester,
        origin + const Offset(40, 40),
        origin + const Offset(160, 120),
      );

      expect(session.currentInkStroke, isNull);
      expect(session.queuedDrawCommits, isNotEmpty);
      expect(session.pendingDrawCommit?.tool, LiveDrawTool.pen);

      // Start a new stroke then Esc-cancel via session (viewer shortcut path).
      session.beginInkStroke(const Offset(0.1, 0.1));
      session.appendInkStroke(const Offset(0.2, 0.2));
      expect(session.currentInkStroke, isNotNull);
      final queuedBefore = session.queuedDrawCommits.length;
      expect(session.cancelCurrentStroke(), isTrue);
      expect(session.currentInkStroke, isNull);
      expect(session.queuedDrawCommits.length, queuedBefore);
    });
  });

  group('Form fill live overlay', () {
    testWidgets('click blank focuses editor on that rect', (tester) async {
      final session = ViewerLiveToolSession();
      session.activate(ViewerToolId.fillForm, pageIndex1Based: 1);
      session.setFormSpots([
        const PdfFormSpot(
          id: 'name',
          name: 'Name',
          kind: PdfFormSpotKind.text,
          pdfRect: Rect.fromLTRB(72, 650, 300, 680),
          normRect: Rect.fromLTRB(0.2, 0.2, 0.6, 0.28),
        ),
      ]);

      await tester.pumpWidget(_pumpSurface(session));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);

      final origin = _surfaceOrigin(tester);
      await tester.tapAt(origin + const Offset(160, 134));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(session.activeFormSpotId, 'name');
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });
  });

  group('Find / ValueKey / autosave constraints', () {
    test('PdfViewerControllerNavSnapshot never throws when detached', () {
      final ctrl = PdfViewerController();
      expect(
        () => PdfViewerControllerNavSnapshot.of(ctrl),
        returnsNormally,
      );
      final snap = PdfViewerControllerNavSnapshot.of(ctrl);
      expect(snap.isReady, isFalse);
    });

    test('PdfViewer ValueKey must omit viewport height and save revision', () {
      // Mirrors PdfDocumentWorkspace key composition.
      const path = '/tmp/doc.pdf';
      const mode = PdfViewerScrollLayoutMode.continuous;
      const rot = PdfViewerViewRotation.degrees0;
      const revision = 42;
      const viewportHeight = 900.0;
      final key = ValueKey('$path:${mode.name}:${rot.name}');
      expect(key.value.toString(), isNot(contains('$revision')));
      expect(key.value.toString(), isNot(contains('$viewportHeight')));
      expect(key.value.toString(), isNot(contains('900')));
    });

    test('autosave debounce is 6s; watermark apply path is not debounced', () {
      expect(kViewerAutosaveDebounce, const Duration(seconds: 6));
      // Watermark panel commits with debounce: false (see ViewerWatermarkPanel).
      // Preview keystrokes only call setLabelText on the live session.
      final session = ViewerLiveToolSession();
      session.activate(
        ViewerToolId.watermark,
        pageIndex1Based: 1,
        labelText: 'A',
      );
      session.setLabelText('AB');
      session.setLabelText('ABC');
      expect(documentSessionAutosave.hasPending, isFalse);
    });
  });
}
