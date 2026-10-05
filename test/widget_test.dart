import 'package:document_studio/app/document_studio_app.dart';
import 'package:document_studio/core/settings/app_prefs.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen shows the welcome and Open PDF', (tester) async {
    AppPrefs.showSplash = false;
    await tester.pumpWidget(
      const ProviderScope(
        child: DocumentStudioApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Open PDF'), findsWidgets);
    expect(find.text('Browse'), findsOneWidget);
  });
}
