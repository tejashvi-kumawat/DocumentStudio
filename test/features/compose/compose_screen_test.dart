import 'package:document_studio/features/compose/compose_model.dart';
import 'package:document_studio/features/compose/compose_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('LaTeX editor: suggestions under the caret, Tab inserts, environments close',
      (tester) async {
    SharedPreferences.setMockInitialValues({'compose_draft_tex': 'x'});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: ComposeScreen(language: ComposeLanguage.latex)),
    ));
    await _settle(tester);

    final field = find.byType(TextField).first;
    await tester.tap(field);
    await tester.enterText(field, r'\textb');
    await _settle(tester);
    expect(find.text(r'\textbf'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settle(tester);
    expect(tester.widget<TextField>(field).controller!.text, r'\textbf{}');

    await tester.enterText(field, r'\begin{itemize}');
    await _settle(tester);
    // Dismiss suggestions, then Enter closes the environment.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(
      tester.widget<TextField>(field).controller!.text,
      '\\begin{itemize}\n  \\item \n\\end{itemize}',
    );
  });
}
