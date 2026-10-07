import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_markup_palette.dart';
import 'package:document_studio/features/pdf_viewer/quick_tools/quick_tools.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MarkupEditorController markup;
  final picked = <MarkupTool>[];
  final opened = <ViewerToolId>[];

  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PdfViewerMarkupPalette(
          enabled: true,
          markup: markup,
          onSelect: picked.add,
          onViewerTool: opened.add,
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    markup = MarkupEditorController();
    picked.clear();
    opened.clear();
    PdfViewerMarkupPalette.sessionOrigin = null;
    PdfViewerMarkupPalette.setSessionCollapsed(false);
    QuickToolsConfig.instance.reset();
  });

  tearDown(() => markup.dispose());

  testWidgets('shows the pinned tools and a blue More button, no group arrows', (tester) async {
    await show(tester);
    for (final id in QuickToolsConfig.defaults) {
      expect(find.byKey(Key('pdf_viewer_markup_palette_$id')), findsOneWidget, reason: id);
    }
    expect(find.byKey(const Key('pdf_viewer_markup_palette_underline')), findsNothing);
    expect(find.byKey(const Key('pdf_viewer_markup_palette_more')), findsOneWidget);
    // A comment tool arms; a viewer tool (Edit PDF) opens.
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_pen')));
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_editText')));
    expect(picked, [MarkupTool.pen]);
    expect(opened, [ViewerToolId.editText]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('More lists every tool; using an unpinned one keeps it on the bar', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_more')));
    await tester.pumpAndSettle();
    expect(find.text('Quick tools'), findsOneWidget);
    // A comment tool near the top…
    await tester.tap(find.text('Underline').last);
    await tester.pumpAndSettle();
    expect(picked, [MarkupTool.underline]);
    expect(find.text('Quick tools'), findsNothing, reason: 'the panel closes');
    expect(find.byKey(const Key('pdf_viewer_markup_palette_underline')), findsOneWidget);
    expect(QuickToolsConfig.instance.isPinned('underline'), isFalse);
    // …and a viewer tool far down the list.
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_more')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Redact'),
      120,
      scrollable: find.ancestor(of: find.text('Underline').first, matching: find.byType(Scrollable)).first,
    );
    await tester.ensureVisible(find.text('Redact'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Redact'));
    await tester.pumpAndSettle();
    expect(opened, [ViewerToolId.redact]);
    // The newest unpinned tool replaces the previous one on the bar.
    expect(find.byKey(const Key('pdf_viewer_markup_palette_redact')), findsOneWidget);
    expect(find.byKey(const Key('pdf_viewer_markup_palette_underline')), findsNothing);
  });

  testWidgets('pin, unpin, reorder and reset customise the bar', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_more')));
    await tester.pumpAndSettle();
    // Pin Underline with the pin on its tile.
    final tile = find.ancestor(of: find.text('Underline').first, matching: find.byType(GestureDetector)).first;
    await tester.tap(find.descendant(of: tile, matching: find.byIcon(Icons.push_pin_outlined)), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(QuickToolsConfig.instance.isPinned('underline'), isTrue);
    QuickToolsConfig.instance.unpin('note');
    QuickToolsConfig.instance.move(0, 2); // select goes after highlight
    await tester.pumpAndSettle();
    expect(QuickToolsConfig.instance.pinned.take(3), ['highlight', 'pen', 'select']);
    // Saved on the device.
    final saved = (await SharedPreferences.getInstance()).getStringList('quick_tools_v1');
    expect(saved, QuickToolsConfig.instance.pinned);
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(QuickToolsConfig.instance.pinned, QuickToolsConfig.defaults);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Hide bar collapses to the single button; it comes back', (tester) async {
    await show(tester);
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide bar'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf_viewer_markup_palette_pen')), findsNothing);
    await tester.tap(find.byKey(const Key('pdf_viewer_markup_palette_expand')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf_viewer_markup_palette_pen')), findsOneWidget);
  });

  test('every tool id is unique and every viewer tool has an icon and label', () {
    final ids = kQuickTools.map((t) => t.id).toList();
    expect(ids.toSet(), hasLength(ids.length));
    for (final t in kQuickTools) {
      expect(t.markup != null || (t.viewer != null && t.icon != null && t.label != null), isTrue, reason: t.id);
      expect(kQuickSections, contains(t.section));
    }
    expect(QuickToolsConfig.defaults.every((d) => quickToolById(d) != null), isTrue);
  });
}
