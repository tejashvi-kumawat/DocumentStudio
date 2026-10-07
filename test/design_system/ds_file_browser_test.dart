import 'dart:io';

import 'package:document_studio/design_system/widgets/ds_file_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('browses a folder, filters by extension, opens a PDF', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('dsfb');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/report.pdf').writeAsStringSync('%PDF');
    File('${dir.path}/notes.txt').writeAsStringSync('x');
    Directory('${dir.path}/sub').createSync();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await showDsFileBrowser(context, extensions: const ['pdf']);
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.runAsync(() async {
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    await tester.enterText(find.widgetWithText(TextField, 'Location'), dir.path);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('sub'), findsOneWidget);
    expect(find.text('notes.txt'), findsNothing);
    await tester.tap(find.text('report.pdf'));
    await tester.pump(const Duration(milliseconds: 400)); // double-tap window
    await tester.tap(find.widgetWithText(FilledButton, 'Open'));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(result, ['${Directory(dir.path).absolute.path}/report.pdf']);
  });
}
