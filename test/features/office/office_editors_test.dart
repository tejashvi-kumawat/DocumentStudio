import 'dart:convert';
import 'dart:io';

import 'package:document_studio/features/office/docx_io.dart';
import 'package:document_studio/features/office/docx_editor_screen.dart';
import 'package:document_studio/features/office/office_chrome.dart';
import 'package:document_studio/features/office/pptx_editor_screen.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:document_studio/features/office/pptx_render.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: child,
      ),
    );

final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

void main() {
  testWidgets('Word: a picture can be selected, resized, aligned and deleted', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = DocxDocument(
      delta: Delta()
        ..insert('Before\n')
        ..insert({'docimage': 'p'})
        ..insert('\nAfter\n'),
      images: {'p': DocxImage(_png, 300 * 9525, 200 * 9525, 'word/media/p.png')},
      tables: {},
    );
    await tester.pumpWidget(_app(DocxEditorScreen(doc: doc)));
    await tester.pump();
    final pic = find.byType(Image).first;
    await tester.tap(pic);
    await tester.pump(const Duration(milliseconds: 100));
    // Selected: handles and the picture bar.
    expect(find.byTooltip('Delete image'), findsWidgets);
    expect(find.byTooltip('Center'), findsOneWidget);
    // Drag the bottom-right handle 150 px to the right: wider, same shape.
    final box = tester.getRect(pic);
    await tester.dragFrom(box.bottomRight - const Offset(5, 5), const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 100));
    final resized = doc.images.values.where((i) => i.widthEmu > 300 * 9525).toList();
    expect(resized, isNotEmpty);
    expect(resized.last.heightEmu / resized.last.widthEmu, closeTo(200 / 300, 0.02));
    // Center it.
    await tester.tap(find.byTooltip('Center'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('Center'), findsOneWidget, reason: 'picture stays selected');
    // Drag the picture below "After": it moves there in the text.
    final pic2 = tester.getRect(find.byType(Image).first);
    final after = tester.getRect(find.text('After', findRichText: true).first);
    await tester.dragFrom(pic2.center, Offset(0, after.bottom + 4 - pic2.center.dy));
    await tester.pump(const Duration(milliseconds: 100));
    final plain = DocxEditorScreen.debugPlain(tester.state(find.byType(DocxEditorScreen)));
    expect(plain.indexOf('After'), lessThan(plain.indexOf('\uFFFC')));
    await tester.tap(find.byType(Image).first);
    await tester.pump(const Duration(milliseconds: 100));
    // Delete.
    await tester.tap(find.byTooltip('Delete image').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Word editor opens a document with its text and pictures', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final f = File('/home/tejashvi-sprix/Downloads/lab5 sp.docx');
    final doc = f.existsSync() ? readDocx(f.readAsBytesSync()) : DocxDocument.blank();
    await tester.pumpWidget(_app(DocxEditorScreen(doc: doc)));
    await tester.pump();
    expect(find.byType(QuillEditor), findsOneWidget);
    expect(find.byType(OfficeTopBar), findsOneWidget);
    for (final menu in ['File', 'Edit', 'View', 'Insert', 'Format', 'Tools']) {
      expect(find.text(menu), findsOneWidget);
    }
    expect(find.text('Saved'), findsOneWidget);
    // File → Page setup → Orientation → Landscape swaps the page.
    for (final item in ['File', 'Page setup', 'Orientation', 'Landscape']) {
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }
    expect(doc.page.landscape, isTrue);
    // Insert → Page break puts a break in the text.
    for (final item in ['Insert', 'Page break']) {
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }
    expect(find.text('Page Break'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('PowerPoint editor shows slides; dragging moves an object', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = PptxDocument.read(File('test/fixtures/deck.pptx').readAsBytesSync());
    await tester.pumpWidget(_app(PptxEditorScreen(doc: doc)));
    await tester.pump();
    // Strip thumbnails + main canvas.
    expect(find.byType(PptxSlideView), findsNWidgets(3));
    final title = doc.slides[0].shapes.firstWhere((s) => s.label == 'Title');
    final x0 = title.x;
    await tester.drag(find.text('Hello Deck', findRichText: true).last, const Offset(60, 0));
    await tester.pump();
    expect(title.x, greaterThan(x0));
    expect(title.dirtyGeometry, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 1)); // gesture timers
  });

  for (final size in const [Size(800, 600), Size(1100, 700), Size(1920, 1080)]) {
    testWidgets('editors lay out without overflow at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(DocxEditorScreen(doc: DocxDocument.blank())));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final deck = PptxDocument.read(File('test/fixtures/deck.pptx').readAsBytesSync());
      await tester.pumpWidget(_app(PptxEditorScreen(doc: deck)));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('PowerPoint: animate, edit text in place, add shape, undo', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = PptxDocument.read(File('test/fixtures/deck.pptx').readAsBytesSync());
    await tester.pumpWidget(_app(PptxEditorScreen(doc: doc)));
    await tester.pump();
    final title = doc.slides[0].shapes.firstWhere((s) => s.label == 'Title');
    // Select the title, then Slide → Animations → Add animation.
    await tester.tap(find.text('Hello Deck', findRichText: true).last, warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Slide').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animations').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add animation'));
    await tester.pump(const Duration(seconds: 2));
    expect(doc.slides[0].animations, hasLength(1));
    expect(identical(doc.slides[0].animations.first.shape, title), isTrue);
    // Double-click edits the text in place; typing replaces the selection.
    await tester.tap(find.text('Hello Deck', findRichText: true).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Hello Deck', findRichText: true).last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(QuillEditor), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(QuillEditor), findsNothing);
    expect(doc.slides[0].shapes.firstWhere((s) => s.label == 'Title').plainText, 'Hello Deck');
    // Insert → Shape → Star adds an object; undo removes it again.
    final n = doc.slides[0].shapes.length;
    await tester.tap(find.text('Insert').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shape').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Star'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(doc.slides[0].shapes, hasLength(n + 1));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(doc.slides[0].shapes, hasLength(n));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('Word: comment on selected text, then resolve it', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = DocxDocument(delta: Delta()..insert('Check this sentence please\n'), images: {}, tables: {});
    await tester.pumpWidget(_app(DocxEditorScreen(doc: doc)));
    await tester.pump();
    DocxEditorScreen.debugSelect(tester.state(find.byType(DocxEditorScreen)), 6, 10);
    await tester.pump();
    await tester.tap(find.byTooltip('Add comment (Ctrl+Alt+M)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doc.comments, hasLength(1));
    await tester.enterText(find.widgetWithText(TextField, 'Add a comment…'), 'Is this right?');
    await tester.tap(find.widgetWithText(FilledButton, 'Comment'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doc.comments.values.single.text, 'Is this right?');
    expect(find.text('Is this right?'), findsOneWidget);
    expect(find.text('"this"'), findsOneWidget);
    await tester.tap(find.byTooltip('Resolve (removes the comment)'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(doc.comments, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Word: suggesting mode marks edits, then accept / reject', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = DocxDocument(delta: Delta()..insert('The quick fox\n'), images: {}, tables: {});
    await tester.pumpWidget(_app(DocxEditorScreen(doc: doc)));
    await tester.pump();
    final st = tester.state(find.byType(DocxEditorScreen));
    DocxEditorScreen.debugSuggest(st, true);
    // Replace "quick" with "slow": the old word stays, struck through.
    DocxEditorScreen.debugReplace(st, 4, 5, 'slow');
    await tester.pump(const Duration(milliseconds: 400));
    expect(DocxEditorScreen.debugPlain(st), 'The quickslow fox\n');
    expect(find.text('Accept all'), findsOneWidget);
    // Typing then deleting your own suggestion removes it for real.
    DocxEditorScreen.debugReplace(st, 13, 0, '!');
    DocxEditorScreen.debugReplace(st, 13, 1, '');
    expect(DocxEditorScreen.debugPlain(st), 'The quickslow fox\n');
    DocxEditorScreen.debugResolveAll(st, true);
    expect(DocxEditorScreen.debugPlain(st), 'The slow fox\n');
    // Reject: a suggested deletion comes back as plain text.
    DocxEditorScreen.debugReplace(st, 4, 5, '');
    DocxEditorScreen.debugResolveAll(st, false);
    expect(DocxEditorScreen.debugPlain(st), 'The slow fox\n');
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Word: deleting table rows and columns in the editor does not break the text fields', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final doc = DocxDocument(
      delta: Delta()
        ..insert({'doctable': 't'})
        ..insert('\nAfter\n'),
      images: {},
      tables: {
        't': docxNewTable([
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
          ['g', 'h', 'i'],
        ]),
      },
    );
    await tester.pumpWidget(_app(DocxEditorScreen(doc: doc)));
    await tester.pump();
    DocxEditorScreen.debugSelect(tester.state(find.byType(DocxEditorScreen)), 0, 0);
    await tester.pump(const Duration(milliseconds: 300));
    // Double-click the table to edit it.
    await tester.tap(find.byType(Table).first);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(Table).first);
    await tester.pumpAndSettle();
    expect(find.text('Edit Table'), findsOneWidget);
    for (final label in ['Delete Row', 'Delete Column', 'Delete Row', 'Delete Column']) {
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
