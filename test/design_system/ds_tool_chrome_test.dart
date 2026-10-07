import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const widths = [Size(360, 740), Size(820, 700), Size(1440, 900)];

  Future<void> pump(WidgetTester tester, Size size, Widget home) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final size in widths) {
    testWidgets('DsToolPage lays out at ${size.width.toInt()} px: header, left-aligned body, pinned actions', (tester) async {
      var saved = 0;
      await pump(
        tester,
        size,
        DsToolPage(
          title: 'Compress a very long document title that has to be shortened',
          subtitle: 'One line of help that is also quite long and has to fit the header without wrapping',
          icon: Icons.compress,
          headerTrailing: const Chip(label: Text('On-device engine')),
          primaryLabel: 'Compress & save',
          onPrimary: () => saved++,
          onCancel: () {},
          child: DsToolSection(
            topPadding: false,
            title: 'Options',
            child: Container(height: 120, color: Colors.black12),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Pinned action bar sits at the bottom, header at the top.
      expect(tester.getRect(find.byType(DsToolFooter)).bottom, closeTo(size.height, 1));
      expect(tester.getRect(find.byType(DsToolHeader)).top, 0);
      // The content starts at the left, not centred.
      expect(tester.getRect(find.text('Options')).left, lessThan(40));
      await tester.tap(find.text('Compress & save'));
      expect(saved, 1);
    });
  }

  testWidgets('every tool badge is the same colour', (tester) async {
    await pump(
      tester,
      const Size(900, 600),
      Scaffold(
        body: Column(children: const [
          DsToolBadge(icon: Icons.compress),
          DsToolBadge(icon: Icons.lock_outline),
          DsToolBadge(icon: Icons.merge_type),
        ]),
      ),
    );
    final colours = tester
        .widgetList<Icon>(find.byType(Icon))
        .map((i) => i.color)
        .toSet();
    expect(colours, {DsColors.primary});
    final fills = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .toSet();
    expect(fills, hasLength(1));
  });

  for (final size in widths) {
    testWidgets('OrganizeToolScaffold uses the same header at ${size.width.toInt()} px', (tester) async {
      await pump(
        tester,
        size,
        OrganizeToolScaffold(
          title: 'Reverse page order',
          subtitle: 'Load a PDF, reverse all pages, then export',
          actions: [FilledButton(onPressed: () {}, child: const Text('Reverse & save'))],
          body: const SizedBox.expand(),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(DsToolHeader), findsOneWidget);
      // The icon is picked from the tool catalog ("Reverse page order" → Reverse).
      expect(find.byIcon(Icons.tune), findsNothing);
      expect(find.text('Reverse & save'), findsOneWidget);
    });
  }
}
