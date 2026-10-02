import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/desktop/desktop_engine_status.dart';
import 'package:document_studio/core/desktop/qpdf_engine_fetch.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/infrastructure/conversion/libreoffice_engine_installer.dart';
import 'package:flutter/material.dart';

/// First-run or Settings: install missing tools with progress (no terminal).
Future<void> showDesktopEngineSetupDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DesktopEngineSetupDialog(),
  );
}

class _DesktopEngineSetupDialog extends StatefulWidget {
  const _DesktopEngineSetupDialog();

  @override
  State<_DesktopEngineSetupDialog> createState() =>
      _DesktopEngineSetupDialogState();
}

class _DesktopEngineSetupDialogState extends State<_DesktopEngineSetupDialog> {
  DesktopEngineStatus? _status;
  var _busy = false;
  String? _progress;
  double? _fraction;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    final s = await DesktopEngineStatus.probe();
    if (!mounted) return;
    setState(() => _status = s);
  }

  Future<void> _installMissing() async {
    final status = _status;
    if (status == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Preparing…';
      _fraction = 0.02;
    });
    try {
      if (!status.qpdfReady) {
        setState(() {
          _progress = 'Downloading qpdf…';
          _fraction = 0.15;
        });
        await const QpdfEngineFetch().fetchOnce();
      }
      if (!mounted) return;
      var next = await DesktopEngineStatus.probe();
      if (!next.libreOfficeReady &&
          Platform.isWindows &&
          LibreOfficeEngineInstaller().isSupported) {
        setState(() {
          _progress = 'Downloading LibreOffice (large, one time)…';
          _fraction = 0.35;
        });
        await LibreOfficeEngineInstaller().installIntoAppStorage(
          onProgress: (f, msg) {
            if (!mounted) return;
            setState(() {
              _fraction = 0.35 + f * 0.6;
              _progress = msg;
            });
          },
        );
      }
      if (!mounted) return;
      next = await DesktopEngineStatus.probe();
      setState(() {
        _status = next;
        _progress = next.corePdfToolsReady
            ? 'Document tools are ready.'
            : 'Some tools still missing — reinstall from Setup.exe if needed.';
        _fraction = 1;
      });
      if (next.allRecommendedReady) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Install document tools'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Document Studio keeps PDF, OCR, and Office tools on your '
              'computer. A full Setup.exe includes everything; this wizard '
              'downloads anything that is still missing.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: DsSpacing.md),
            if (status == null)
              const LinearProgressIndicator()
            else ...[
              _row('PDF engine (qpdf)', status.qpdfReady),
              _row('OCR (Tesseract)', status.tesseractReady),
              if (DesktopEngineStatus.needsLibreOffice)
                _row('Office conversion (LibreOffice)', status.libreOfficeReady),
            ],
            if (_busy) ...[
              const SizedBox(height: DsSpacing.md),
              if (_fraction != null) LinearProgressIndicator(value: _fraction),
              if (_progress != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(_progress!, style: theme.textTheme.bodySmall),
              ],
            ],
            if (_error != null) ...[
              const SizedBox(height: DsSpacing.sm),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: (_busy || status == null || status.allRecommendedReady)
              ? null
              : _installMissing,
          child: Text(
            status?.allRecommendedReady == true
                ? 'Done'
                : 'Install missing tools',
          ),
        ),
      ],
    );
  }

  Widget _row(String label, bool ok) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: ok ? Colors.green.shade700 : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
