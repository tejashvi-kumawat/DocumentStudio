import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/infrastructure/pdf/signing/digital_id_store.dart';
import 'package:flutter/material.dart';

String describeSignError(Object error) {
  final text = error
      .toString()
      .replaceFirst(RegExp(r'^(DocumentStudioError|Exception):\s*'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final lower = text.toLowerCase();
  if (text.isEmpty ||
      text.length > 160 ||
      text.contains('#') ||
      lower.contains('stacktrace')) {
    return 'Couldn’t sign this document. Check the digital ID and try again.';
  }
  return text;
}

Future<DigitalId?> showCreateDigitalIdDialog(
  BuildContext context, {
  required DigitalIdStore store,
  String? suggestedName,
}) {
  return showDialog<DigitalId>(
    context: context,
    builder: (ctx) =>
        _CreateDigitalIdDialog(store: store, suggestedName: suggestedName),
  );
}

Future<DigitalId?> importDigitalIdFlow(
  BuildContext context, {
  required DigitalIdStore store,
  required Future<String?> Function() pickP12Path,
}) async {
  final path = await pickP12Path();
  if (path == null) return null;
  if (!context.mounted) return null;
  return showDialog<DigitalId>(
    context: context,
    builder: (ctx) => _ImportDigitalIdDialog(store: store, p12Path: path),
  );
}

class _CreateDigitalIdDialog extends StatefulWidget {
  const _CreateDigitalIdDialog({required this.store, this.suggestedName});
  final DigitalIdStore store;
  final String? suggestedName;

  @override
  State<_CreateDigitalIdDialog> createState() => _CreateDigitalIdDialogState();
}

class _CreateDigitalIdDialogState extends State<_CreateDigitalIdDialog> {
  late final _name = TextEditingController(text: widget.suggestedName ?? '');
  final _password = TextEditingController();
  final _org = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _org.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_password.text.length < 4) {
      setState(() => _error = 'Password must be at least 4 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.store.createSelfSigned(
        displayName: _name.text.trim(),
        password: _password.text,
        organization: _org.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeSignError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create digital ID'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            TextField(
              controller: _org,
              decoration: const InputDecoration(
                labelText: 'Organization (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: DsSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        DsPrimaryButton(label: 'Create', onPressed: _busy ? null : _create),
      ],
    );
  }
}

class _ImportDigitalIdDialog extends StatefulWidget {
  const _ImportDigitalIdDialog({required this.store, required this.p12Path});
  final DigitalIdStore store;
  final String p12Path;

  @override
  State<_ImportDigitalIdDialog> createState() => _ImportDigitalIdDialogState();
}

class _ImportDigitalIdDialogState extends State<_ImportDigitalIdDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.store.importP12(
        sourcePath: widget.p12Path,
        displayName: _name.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = describeSignError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import digital ID'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.p12Path, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: DsSpacing.sm),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Display name (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DsSpacing.sm),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: DsSpacing.sm),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        DsPrimaryButton(label: 'Import', onPressed: _busy ? null : _import),
      ],
    );
  }
}
