import 'package:flutter/material.dart';

/// Asks for a PDF's open password. Null when cancelled.
///
/// The field's controller belongs to the dialog widget itself and is disposed
/// with it. Disposing it right after `showDialog` returns would pull it out
/// from under the field while the dialog's closing animation is still drawing
/// ("A TextEditingController was used after being disposed").
Future<String?> promptPdfPassword(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _PdfPasswordDialog(),
);

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog();

  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final _controller = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Password required'),
      content: TextField(
        controller: _controller,
        obscureText: !_show,
        autofocus: true,
        decoration: InputDecoration(
          labelText: 'PDF password',
          suffixIcon: IconButton(
            tooltip: _show ? 'Hide password' : 'Show password',
            icon: Icon(
              _show ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              size: 20,
            ),
            onPressed: () => setState(() => _show = !_show),
          ),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Unlock')),
      ],
    );
  }
}
