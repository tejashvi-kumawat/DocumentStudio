import 'dart:io';

import 'package:document_studio/core/desktop/qpdf_engine_fetch.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Desktop-only status for the bundled qpdf binary.
///
/// The download button is the one explicit fetch. It is not run at startup,
/// and it is hidden on Android and iOS.
class LocalQpdfEnginePanel extends StatefulWidget {
  const LocalQpdfEnginePanel({super.key});

  @override
  State<LocalQpdfEnginePanel> createState() => _LocalQpdfEnginePanelState();
}

class _LocalQpdfEnginePanelState extends State<LocalQpdfEnginePanel> {
  late Future<bool> _ready = isQpdfCliAvailable();
  var _busy = false;
  String? _detail;

  bool get _desktop =>
      !kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS);

  Future<void> _download() async {
    setState(() {
      _busy = true;
      _detail = null;
    });
    try {
      final path = await const QpdfEngineFetch().fetchOnce();
      if (!mounted) return;
      setState(() {
        _detail = 'qpdf is ready ($path).';
        _ready = Future<bool>.value(true);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _detail = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.lg),
      child: DsToolPanel(
        title: 'PDF engine',
        subtitle: 'qpdf ships inside the desktop app. '
            'This download runs only if that copy is missing.',
        child: FutureBuilder<bool>(
        future: _ready,
        builder: (context, snap) {
          final ready = snap.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                switch (ready) {
                  null => 'Checking the bundled qpdf…',
                  true => 'qpdf is included with this app.',
                  false => 'qpdf is not in the app folder yet.',
                },
              ),
              if (ready == false) ...[
                const SizedBox(height: DsSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _busy ? null : _download,
                    child: Text(_busy ? 'Downloading qpdf…' : 'Download qpdf'),
                  ),
                ),
              ],
              if (_detail != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(_detail!),
              ],
            ],
          );
        },
        ),
      ),
    );
  }
}

String _friendly(Object error) {
  final text = error.toString();
  const prefix = 'Bad state: ';
  if (text.startsWith(prefix)) return text.substring(prefix.length);
  return text;
}
