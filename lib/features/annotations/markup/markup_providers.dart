import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One markup editor, bound to the active viewer tab's document session.
final markupEditorProvider = Provider<MarkupEditorController>((ref) {
  ref.keepAlive();
  final c = MarkupEditorController();
  ref.onDispose(c.dispose);
  return c;
});
