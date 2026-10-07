import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<String?> open(WidgetTester tester, Future<void> Function() act) async {
    String? result = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await promptPdfPassword(context),
              child: const Text('Preview size'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Preview size'));
    await tester.pumpAndSettle();
    await act();
    return result;
  }

  testWidgets('Unlock returns the password and closes without errors', (tester) async {
    final r = await open(tester, () async {
      await tester.enterText(find.byType(TextField), 's3cret');
      await tester.tap(find.text('Unlock'));
      // The closing animation draws the field for several more frames.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    });
    expect(r, 's3cret');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Enter submits; Cancel returns null; the eye shows the text', (tester) async {
    final shown = await open(tester, () async {
      await tester.enterText(find.byType(TextField), 'abc');
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    });
    expect(shown, 'abc');
    final cancelled = await open(tester, () async {
      await tester.tap(find.text('Cancel'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pumpAndSettle();
    });
    expect(cancelled, isNull);
    expect(tester.takeException(), isNull);
  });
}
