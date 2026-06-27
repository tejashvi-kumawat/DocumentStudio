import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/insert_scan_mjpeg.dart';
import 'package:document_studio/features/pdf_viewer/panels/insert_scan_place.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _doc = LocalFileRef(path: '/doc.pdf', displayName: 'doc.pdf');
const _scan = LocalFileRef(path: '/scan.pdf', displayName: 'scan.pdf');

List<String> _slots(List<OrganizePageRef> pages) => [
      for (final page in pages) '${page.file.path}#${page.pageNumber1Based}',
    ];

void main() {
  test('places the scan after the current page, at the start, at the end, or after a number', () {
    final afterCurrent = pagesForScanInsert(
      document: _doc,
      totalPages: 4,
      currentPage1: 2,
      insertFile: _scan,
      insertPageCount: 1,
      anchor: ScanInsertAnchor.afterCurrent,
    );
    expect(_slots(afterCurrent), [
      '/doc.pdf#1',
      '/doc.pdf#2',
      '/scan.pdf#1',
      '/doc.pdf#3',
      '/doc.pdf#4',
    ]);

    final start = pagesForScanInsert(
      document: _doc,
      totalPages: 4,
      currentPage1: 2,
      insertFile: _scan,
      insertPageCount: 2,
      anchor: ScanInsertAnchor.start,
    );
    expect(_slots(start), [
      '/scan.pdf#1',
      '/scan.pdf#2',
      '/doc.pdf#1',
      '/doc.pdf#2',
      '/doc.pdf#3',
      '/doc.pdf#4',
    ]);

    final end = pagesForScanInsert(
      document: _doc,
      totalPages: 4,
      currentPage1: 2,
      insertFile: _scan,
      insertPageCount: 1,
      anchor: ScanInsertAnchor.end,
    );
    expect(_slots(end).last, '/scan.pdf#1');
    expect(_slots(end).sublist(0, 4), [
      '/doc.pdf#1',
      '/doc.pdf#2',
      '/doc.pdf#3',
      '/doc.pdf#4',
    ]);

    final afterNumber = pagesForScanInsert(
      document: _doc,
      totalPages: 4,
      currentPage1: 2,
      insertFile: _scan,
      insertPageCount: 1,
      anchor: ScanInsertAnchor.afterNumber,
      afterPageNumber: 1,
    );
    expect(_slots(afterNumber).take(3), [
      '/doc.pdf#1',
      '/scan.pdf#1',
      '/doc.pdf#2',
    ]);
  });

  test('mjpeg assembler waits for a full frame and keeps the latest', () {
    final assembler = MjpegAssembler();
    final frame1 = [0xFF, 0xD8, 1, 2, 0xFF, 0xD9];
    final frame2 = [0xFF, 0xD8, 9, 0xFF, 0xD9];
    assembler.add(frame1.sublist(0, 3));
    expect(assembler.latest, isNull);
    assembler.add(frame1.sublist(3));
    expect(assembler.latest, orderedEquals(frame1));
    assembler.add([0, 1, 2, ...frame2]);
    expect(assembler.latest, orderedEquals(frame2));
  });

  testWidgets('cancel closes the place dialog without a choice', (tester) async {
    ScanInsertChoice? result = const ScanInsertChoice(anchor: ScanInsertAnchor.start);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showScanInsertPlaceDialog(
                context: context,
                pageCount: 5,
                currentPage1: 2,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('After current page (page 2)'), findsOneWidget);
    expect(find.text('At the start'), findsOneWidget);
    expect(find.text('At the end'), findsOneWidget);
    expect(find.text('After a page number'), findsOneWidget);
    await tester.tap(find.byKey(const Key('insert_scan_place_cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('insert confirms after current, start, or a page number', (tester) async {
    ScanInsertChoice? result;

    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showScanInsertPlaceDialog(
                  context: context,
                  pageCount: 5,
                  currentPage1: 2,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    await show();
    await tester.tap(find.byKey(const Key('insert_scan_place_confirm')));
    await tester.pumpAndSettle();
    expect(result?.anchor, ScanInsertAnchor.afterCurrent);

    result = null;
    await show();
    await tester.tap(find.text('At the start'));
    await tester.tap(find.byKey(const Key('insert_scan_place_confirm')));
    await tester.pumpAndSettle();
    expect(result?.anchor, ScanInsertAnchor.start);

    result = null;
    await show();
    await tester.tap(find.text('After a page number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('insert_scan_place_page_field')),
      '9',
    );
    await tester.tap(find.byKey(const Key('insert_scan_place_confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insert_scan_place_dialog')), findsOneWidget);
    expect(find.text('Enter a page from 1 to 5.'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(
      find.byKey(const Key('insert_scan_place_page_field')),
      '3',
    );
    await tester.tap(find.byKey(const Key('insert_scan_place_confirm')));
    await tester.pumpAndSettle();
    expect(result?.anchor, ScanInsertAnchor.afterNumber);
    expect(result?.afterPageNumber, 3);
  });
}
