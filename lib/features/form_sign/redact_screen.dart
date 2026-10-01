import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/form_sign/form_sign_route.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Standalone /redact entry when no open PDF — real redact lives in the viewer.
class RedactScreen extends StatelessWidget {
  const RedactScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: DsToolbar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: 'Redact PDF',
        subtitle: 'Open a PDF to mark and flatten',
        dense: dsUseCompactToolLayout(context),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            DsToolFormLayout(
              primary: DsToolPanel(
                title: 'Use Redact on an open document',
                subtitle: 'Search matches → mark → Apply flattens the page',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open a PDF in the viewer, then Tools → Redact. Search a phrase '
                      'to mark matches, or drag boxes on the page. Apply permanently '
                      'removes content (flattened image page) so extractPlainText no '
                      'longer returns that text. Undo restores the prior session bytes.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: DsSpacing.lg),
                    Text(
                      'This is not a black rectangle over extractable text.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              sidebar: DsToolPanel(
                title: 'Related',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextButton.icon(
                      onPressed: () => context.push(protectRoutePath),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Encrypt'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push(removeMetadataRoutePath),
                      icon: const Icon(Icons.cleaning_services_outlined),
                      label: const Text('Remove metadata'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push(visualSignRoutePath),
                      icon: const Icon(Icons.draw_outlined),
                      label: const Text('Visual signature'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
