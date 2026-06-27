import 'package:flutter/material.dart';

Future<String?> promptPdfPassword(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Password required'),
      content: TextField(
        controller: controller,
        obscureText: true,
        decoration: const InputDecoration(labelText: 'PDF password'),
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(ctx, controller.text),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Unlock'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
