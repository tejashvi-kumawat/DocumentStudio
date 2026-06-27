import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_merge_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_merge_split_apply.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Save as names a new file and refuses the open document', () {
    expect(suggestedMergeSaveAsName('Report.pdf'), 'Report-merged.pdf');
    expect(normalizeMergeSaveAsFileName('notes'), 'notes.pdf');
    expect(
      mergeSaveAsDestination(
        directory: '/docs',
        fileName: 'notes',
        forbiddenPaths: const {'/docs/Report.pdf'},
      ),
      '/docs/notes.pdf',
    );
    expect(
      () => mergeSaveAsDestination(
        directory: '/docs',
        fileName: 'Report.pdf',
        forbiddenPaths: const {'/docs/Report.pdf'},
      ),
      throwsA(
        isA<DocumentStudioError>().having(
          (e) => e.code,
          'code',
          DocumentStudioErrorCode.invalidFile,
        ),
      ),
    );
    expect(
      () => normalizeMergeSaveAsFileName('../Report.pdf'),
      throwsA(isA<DocumentStudioError>()),
    );
  });

  testWidgets('open PDF merge shows Save and Save as', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: ViewerMergePanel(
              handoff: PdfViewerDocumentHandoff(
                file: LocalFileRef(
                  path: '/tmp/open.pdf',
                  displayName: 'open.pdf',
                ),
              ),
              pageCount: 3,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('viewer_merge_save')), findsOneWidget);
    expect(find.byKey(const Key('viewer_merge_save_as')), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Save as'), findsOneWidget);
    expect(find.text('Merge'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('viewer_merge_save')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('viewer_merge_save_as')))
          .onPressed,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });
}
