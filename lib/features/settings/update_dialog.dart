import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/update/app_updater.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Update available" dialog: release notes, then download + install with
/// progress (the checksum GitHub publishes is verified first).
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateDialog(update: update),
  );
}

/// Checks now and reports the result (Settings → Check for updates).
Future<void> checkForUpdatesInteractive(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    const SnackBar(content: Text('Checking for updates…'), duration: Duration(seconds: 2)),
  );
  final u = await AppUpdater.instance.check();
  if (!context.mounted) return;
  messenger?.hideCurrentSnackBar();
  if (u == null) {
    final v = await AppUpdater.instance.currentVersion();
    messenger?.showSnackBar(
      SnackBar(content: Text('Document Studio $v is up to date.')),
    );
    return;
  }
  await showUpdateDialog(context, u);
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppUpdate update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double? _progress;
  String? _error;
  bool _cancel = false;

  Future<void> _install() async {
    setState(() {
      _progress = 0;
      _error = null;
      _cancel = false;
    });
    final err = await AppUpdater.instance.downloadAndInstall(
      widget.update,
      onProgress: (f) {
        if (mounted) setState(() => _progress = f);
      },
      cancelled: () => _cancel,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _progress = null;
        _error = err;
      });
      return;
    }
    if (!Platform.isWindows) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final theme = Theme.of(context);
    final busy = _progress != null;
    final mb = u.assetSize == null ? '' : ' (${(u.assetSize! / 1048576).round()} MB)';
    return AlertDialog(
      title: Text('Document Studio ${u.version} is available'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (u.notes.trim().isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Text(u.notes.trim(), style: theme.textTheme.bodySmall),
                ),
              ),
            const SizedBox(height: 12),
            if (busy) ...[
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 6),
              Text(
                _progress! >= 1
                    ? (Platform.isWindows
                        ? 'Installing — Document Studio will restart…'
                        : 'Opening the installer…')
                    : 'Downloading${(_progress! * 100).round()}%'.replaceFirst(
                        'Downloading',
                        'Downloading ',
                      ),
                style: theme.textTheme.bodySmall,
              ),
            ] else if (!u.canInstall)
              Text(
                'There is no installer for this system in the release; '
                'open the release page to download it.',
                style: theme.textTheme.bodySmall,
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(u.pageUrl),
            mode: LaunchMode.externalApplication,
          ),
          child: const Text('Release page'),
        ),
        TextButton(
          onPressed: () {
            _cancel = true;
            Navigator.of(context).pop();
          },
          child: Text(busy ? 'Cancel' : 'Later'),
        ),
        if (u.canInstall)
          FilledButton.icon(
            onPressed: busy ? null : () => unawaited(_install()),
            icon: const Icon(Icons.system_update_alt, size: 18),
            label: Text('Update now$mb'),
          ),
      ],
    );
  }
}
