import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// DS-READ-013 — title, author, and page count from [PdfRenderPort.loadInfo].
Future<void> showDocumentProperties({
  required BuildContext context,
  required PdfRenderPort pdf,
  required LocalFileRef file,
  String? password,
}) async {
  try {
    final info = await pdf.loadInfo(file, password: password);
    if (!context.mounted) return;
    await showDocumentPropertiesDialog(
      context: context,
      info: info,
      fileSizeBytes: file.sizeBytes,
      file: file,
      password: password,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

Future<void> showDocumentPropertiesDialog({
  required BuildContext context,
  required PdfDocumentInfo info,
  int? fileSizeBytes,
  LocalFileRef? file,
  String? password,
}) async {
  final compact = MediaQuery.sizeOf(context).width < 600;
  if (compact) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: 24 + MediaQuery.paddingOf(ctx).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DocumentPropertiesPanel(info: info, fileSizeBytes: fileSizeBytes),
              if (file != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.push(
                      metadataRoutePath,
                      extra: MetadataEditorRouteArgs(
                        file: file,
                        password: password,
                      ),
                    );
                  },
                  child: const Text('Edit metadata'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Document properties'),
      content: DocumentPropertiesPanel(
        info: info,
        fileSizeBytes: fileSizeBytes,
      ),
      actions: [
        if (file != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.push(
                metadataRoutePath,
                extra: MetadataEditorRouteArgs(file: file, password: password),
              );
            },
            child: const Text('Edit metadata'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class DocumentPropertiesPanel extends StatelessWidget {
  const DocumentPropertiesPanel({
    super.key,
    required this.info,
    this.fileSizeBytes,
  });

  final PdfDocumentInfo info;
  final int? fileSizeBytes;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PropertyRow(
          label: 'Title',
          value: displayDocumentProperty(info.title),
        ),
        const SizedBox(height: 12),
        _PropertyRow(
          label: 'Author',
          value: displayDocumentProperty(info.author),
        ),
        const SizedBox(height: 12),
        _PropertyRow(label: 'Pages', value: '${info.pageCount}'),
        const SizedBox(height: 12),
        _PropertyRow(
          label: 'File size',
          value: formatDocumentByteSize(fileSizeBytes),
        ),
        const SizedBox(height: 12),
        _PropertyRow(
          label: 'Security',
          value: displayDocumentEncryption(info.encrypted),
        ),
      ],
    );
  }
}

String formatDocumentByteSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

String displayDocumentEncryption(bool? encrypted) {
  if (encrypted == null) return '—';
  return encrypted ? 'Password protected' : 'Not encrypted';
}

String displayDocumentProperty(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return '—';
  return trimmed;
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: theme.bodyLarge),
      ],
    );
  }
}
