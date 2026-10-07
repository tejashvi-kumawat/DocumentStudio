import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_status.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/features/setup/desktop_engine_setup_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Settings: status of bundled tools + GUI installer (no terminal).
class DesktopDocumentToolsPanel extends StatefulWidget {
  const DesktopDocumentToolsPanel({super.key});

  @override
  State<DesktopDocumentToolsPanel> createState() =>
      _DesktopDocumentToolsPanelState();
}

class _DesktopDocumentToolsPanelState extends State<DesktopDocumentToolsPanel> {
  late Future<DesktopEngineStatus> _status = DesktopEngineStatus.probe();

  bool get _desktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  Future<void> _openSetup() async {
    await showDesktopEngineSetupDialog(context);
    if (!mounted) return;
    setState(() => _status = DesktopEngineStatus.probe());
  }

  @override
  Widget build(BuildContext context) {
    if (!_desktop) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.lg),
      child: DsToolPanel(
        title: 'Document tools',
        subtitle:
            'PDF, OCR, and Office engines. Use the setup wizard to download '
            'missing components, or reinstall from DocumentStudio-Setup.exe.',
        child: FutureBuilder<DesktopEngineStatus>(
          future: _status,
          builder: (context, snap) {
            final s = snap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (s) {
                  null => 'Checking installed tools…',
                  final st when st.allRecommendedReady =>
                    'All recommended tools are installed.',
                  final st when st.corePdfToolsReady => 'Core PDF tools OK. Office conversion may need LibreOffice.',
                  _ => 'Some tools are missing — open the setup wizard or run the full installer.',
                }),
                const SizedBox(height: DsSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _openSetup,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Install / update tools…'),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
