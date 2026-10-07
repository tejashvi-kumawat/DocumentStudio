import 'dart:io';

import 'package:document_studio/core/session/page_sessions.dart';
import 'package:document_studio/features/office/docx_editor_screen.dart';
import 'package:document_studio/features/office/docx_io.dart';
import 'package:document_studio/features/office/pptx_editor_screen.dart';
import 'package:document_studio/features/office/pptx_io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

const officeRoutePath = '/office';

/// Extensions the Office editors open.
const officeExtensions = ['docx', 'pptx'];

bool isOfficePath(String path) => officeExtensions.contains(
  p.extension(path).toLowerCase().replaceFirst('.', ''),
);

var _newSeq = 0;

/// Location that opens [path] (or a new blank [kind] when path is null;
/// each new document gets its own tab).
String officeLocation({String? path, String? kind}) => Uri(
  path: officeRoutePath,
  queryParameters: {
    'path': ?path,
    'kind': ?kind,
    if (path == null)
      'new': '${DateTime.now().millisecondsSinceEpoch}-${_newSeq++}',
  },
).toString();

/// An open Word or PowerPoint document kept across tab switches
/// ([PageSessions], keyed by the tab's location).
class OfficeSession {
  OfficeSession(this.doc, this.path, {this.key});

  /// [PageSessions] key (the tab location).
  final String? key;

  /// Saves the open document (set while its editor is on screen).
  Future<bool> Function()? saveNow;

  /// The editor was closed: forget the document.
  void release() {
    if (key != null) PageSessions.drop(key!);
  }

  /// [DocxDocument] or [PptxDocument]; edited in place.
  final Object doc;
  String? path;
  bool dirty = false;

  /// Editor view state (text, zoom, current slide, history…).
  final Map<String, Object?> state = {};
}

GoRoute buildOfficeRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) =>
    GoRoute(
      parentNavigatorKey: parentNavigatorKey,
      path: officeRoutePath,
      builder: (context, state) => OfficeOpenScreen(
        key: ValueKey(state.uri.toString()),
        sessionKey: state.uri.toString(),
        path: state.uri.queryParameters['path'],
        kind: state.uri.queryParameters['kind'],
      ),
    );

/// Loads a .docx / .pptx (off the UI thread) and shows its editor.
class OfficeOpenScreen extends StatefulWidget {
  const OfficeOpenScreen({super.key, this.path, this.kind, this.sessionKey});

  final String? path;

  /// Where the open document is parked between tab switches.
  final String? sessionKey;
  final String? kind; // docx | pptx (new document)

  @override
  State<OfficeOpenScreen> createState() => _OfficeOpenScreenState();
}

class _OfficeOpenScreenState extends State<OfficeOpenScreen> {
  Widget? _editor;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Widget _editorFor(OfficeSession s) => switch (s.doc) {
    final PptxDocument d => PptxEditorScreen(doc: d, path: s.path, session: s),
    final DocxDocument d => DocxEditorScreen(doc: d, path: s.path, session: s),
    _ => const SizedBox.shrink(),
  };

  Future<void> _load() async {
    final key = widget.sessionKey;
    final live = key == null ? null : PageSessions.get<OfficeSession>(key);
    if (live != null) {
      // Back to this tab: the document is already open.
      _editor = _editorFor(live);
      return;
    }
    final path = widget.path;
    final kind = path == null
        ? (widget.kind ?? 'docx')
        : p.extension(path).toLowerCase().replaceFirst('.', '');
    try {
      final Object doc;
      if (kind == 'pptx') {
        final bytes = path == null
            ? await blankPresentationBytes()
            : await File(path).readAsBytes();
        doc = await compute(PptxDocument.read, bytes);
      } else if (kind == 'docx') {
        doc = path == null
            ? DocxDocument.blank()
            : await compute(readDocx, await File(path).readAsBytes());
      } else {
        throw FormatException('Unsupported file type: .$kind');
      }
      final session = OfficeSession(doc, path, key: key);
      if (key != null) PageSessions.put(key, session);
      if (mounted) setState(() => _editor = _editorFor(session));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final editor = _editor;
    if (editor != null) return editor;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.path == null ? 'New document' : p.basename(widget.path!),
        ),
      ),
      body: Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 40,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Could not open this file.\n$_error',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Before a Word / PowerPoint tab at [location] closes: asks to save
/// unsaved changes. False when the user cancels.
Future<bool> confirmCloseOfficePage(
  BuildContext context,
  String location,
) async {
  final session = PageSessions.get<OfficeSession>(location);
  if (session == null || !session.dirty) return true;
  final name = session.path == null
      ? 'This document'
      : '"${p.basename(session.path!)}"';
  final save = session.saveNow;
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Save changes?'),
      content: Text('$name has changes that are not saved.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, 'cancel'),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, 'discard'),
          child: const Text("Don't save"),
        ),
        if (save != null)
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            child: const Text('Save'),
          ),
      ],
    ),
  );
  if (r == null || r == 'cancel') return false;
  if (r == 'save' && save != null) return save();
  return true;
}
