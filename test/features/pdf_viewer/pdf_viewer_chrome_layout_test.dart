import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_tab_bar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_top_chrome.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_markup_palette.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _widths = <double>[360, 599, 600, 839, 840, 1280, 1440, 1920];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MarkupEditorController markup;

  setUp(() {
    markup = MarkupEditorController();
    PdfViewerMarkupPalette.sessionOrigin = null;
    PdfViewerMarkupPalette.setSessionCollapsed(true);
  });

  tearDown(() {
    markup.dispose();
    PdfViewerMarkupPalette.sessionOrigin = null;
    PdfViewerMarkupPalette.setSessionCollapsed(true);
  });

  Future<void> setView(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('tool row scrolls in order and has no More button', (tester) async {
    Future<void> pumpRow(double width) async {
      await setView(tester, Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PdfViewerToolRow(
              enabled: true,
              markup: markup,
              onArmMarkup: (_) {},
              onAllTools: () {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    const order = <String>[
      'pdf_viewer_tool_organize',
      'pdf_viewer_tool_crop',
      'pdf_viewer_tool_rotate',
      'pdf_viewer_tool_edit',
      'pdf_viewer_tool_convert',
      'pdf_viewer_tool_encrypt',
      'pdf_viewer_tool_decrypt',
      'pdf_viewer_tool_all',
    ];

    await pumpRow(1400);
    expect(tester.takeException(), isNull);
    expect(find.text('More'), findsNothing);
    expect(find.byTooltip('More'), findsNothing);
    var previous = -1.0;
    for (final name in order) {
      final dx = tester.getTopLeft(find.byKey(Key(name))).dx;
      expect(dx, greaterThan(previous), reason: name);
      previous = dx;
    }

    for (final width in _widths) {
      await pumpRow(width);
      expect(tester.takeException(), isNull, reason: 'width $width');
      expect(find.text('More'), findsNothing);
      expect(find.byKey(const Key('pdf_viewer_tool_organize')), findsOneWidget);
    }

    await pumpRow(360);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    await tester.scrollUntilVisible(
      find.byKey(const Key('pdf_viewer_tool_all')),
      120,
    );
    expect(find.text('Tools'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('top chrome stays under the status bar at every width', (
    tester,
  ) async {
    for (final width in _widths) {
      await setView(tester, Size(width, 800));
      final tabs = DocumentTabsController();
      addTearDown(tabs.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                padding: const EdgeInsets.only(top: 32, bottom: 16),
              ),
              child: child!,
            );
          },
          home: Scaffold(
            appBar: PdfViewerAcrobatTopChrome(
              tabs: tabs,
              documentTitle: 'Quarterly-report-final-signed.pdf',
              showDocumentTabs: width >= DsSpacing.breakpointCompact,
              showFind: width >= DsSpacing.breakpointCompact,
              onBack: () {},
              onFind: () {},
              toolRow: PdfViewerToolRow(
                enabled: true,
                markup: markup,
                onArmMarkup: (_) {},
                onAllTools: () {},
              ),
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'width $width');
      final title = tester.getTopLeft(
        find.byKey(const Key('pdf_viewer_chrome_title')),
      );
      expect(title.dy, greaterThanOrEqualTo(32), reason: 'width $width');
      if (width < DsSpacing.breakpointCompact) {
        expect(find.byType(PdfDocumentTabBar), findsNothing);
      }
    }
  });

  testWidgets('draw button stays on the page at phone and desktop widths', (
    tester,
  ) async {
    Future<Rect> buttonAt(Size size, {EdgeInsets padding = EdgeInsets.zero}) async {
      await setView(tester, size);
      PdfViewerMarkupPalette.sessionOrigin = const Offset(4000, -80);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(padding: padding),
              child: child!,
            );
          },
          home: PdfViewerMarkupPalette(
            enabled: true,
            markup: markup,
            onSelect: (_) {},
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
      return tester.getRect(find.byKey(const Key('pdf_viewer_markup_palette')));
    }

    final phone = await buttonAt(
      const Size(360, 640),
      padding: const EdgeInsets.only(bottom: 24),
    );
    expect(phone.left, greaterThanOrEqualTo(12));
    expect(phone.right, lessThanOrEqualTo(360 - 12));
    expect(phone.top, greaterThanOrEqualTo(12));
    expect(phone.bottom, lessThanOrEqualTo(640 - 12));

    final shortPhone = await buttonAt(const Size(360, 220));
    expect(shortPhone.left, greaterThanOrEqualTo(0));
    expect(shortPhone.right, lessThanOrEqualTo(360));
    expect(shortPhone.top, greaterThanOrEqualTo(0));
    expect(shortPhone.bottom, lessThanOrEqualTo(220));

    final desktop = await buttonAt(const Size(1280, 800));
    expect(desktop.right, lessThanOrEqualTo(1280 - 8));
    expect(desktop.left, greaterThan(1280 - 120));
    expect(desktop.top, greaterThanOrEqualTo(8));
    expect(desktop.bottom, lessThanOrEqualTo(800));

    final expanded = await buttonAt(const Size(840, 700));
    expect(expanded.right, lessThanOrEqualTo(840 - 8));
    expect(expanded.bottom, lessThanOrEqualTo(700));
  });

  testWidgets('tool form is full width on compact and about 380 on wide', (
    tester,
  ) async {
    Future<void> pumpForm(Size size) async {
      await setView(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          home: ViewerToolFormScaffold(
            primaryLabel: 'Apply',
            onPrimary: () {},
            children: const [Text('Options')],
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
    }

    await pumpForm(const Size(360, 700));
    final compactButton = tester.getSize(find.byType(FilledButton));
    expect(compactButton.height, 48);
    expect(compactButton.width, greaterThan(300));

    await pumpForm(const Size(1280, 800));
    final wideButton = tester.getSize(find.byType(FilledButton));
    expect(wideButton.height, 48);
    expect(wideButton.width, lessThan(viewerAcrobatOptionsWidth));
    final options = tester.getTopLeft(find.text('Options'));
    final optionsRight = tester.getTopRight(find.text('Options'));
    expect(options.dx, greaterThanOrEqualTo((1280 - viewerAcrobatOptionsWidth) / 2));
    expect(optionsRight.dx, lessThanOrEqualTo((1280 + viewerAcrobatOptionsWidth) / 2));
  });
}
