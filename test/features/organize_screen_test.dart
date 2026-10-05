import 'package:document_studio/features/page_management/organize_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('organize hub shows compact tool list', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: OrganizeHubScreen())),
    );
    await tester.pump();

    expect(find.text('Organize'), findsOneWidget);
    expect(
      find.text('Search tools (⌘/Ctrl+K for commands)'),
      findsOneWidget,
    );
    expect(find.text('Merge PDFs'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });
}
