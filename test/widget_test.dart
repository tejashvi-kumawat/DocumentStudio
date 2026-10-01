import 'package:document_studio/app/document_studio_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home screen shows Document Studio title', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: DocumentStudioApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Document Studio'), findsWidgets);
    expect(find.text('Open file'), findsOneWidget);
  });
}
