import 'dart:io';

import 'package:document_studio/core/desktop/qpdf_engine_fetch.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SecurityQpdfUnavailablePanel extends StatefulWidget {
  const SecurityQpdfUnavailablePanel({
    super.key,
    required this.onRecheck,
    this.busy = false,
  });

  final VoidCallback onRecheck;
  final bool busy;

  static String get unavailableMessage {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return 'This tool needs a desktop engine that is not available on '
          'Android/iOS. Encrypt, decrypt, and metadata editing work on this '
          'device; crop/resize and some advanced tools still need desktop.';
    }
    return 'This feature needs the bundled qpdf engine under engines/. '
        'Reinstall Document Studio, or download qpdf once into app storage.';
  }

  @override
  State<SecurityQpdfUnavailablePanel> createState() =>
      _SecurityQpdfUnavailablePanelState();
}

class _SecurityQpdfUnavailablePanelState
    extends State<SecurityQpdfUnavailablePanel> {
  var _downloading = false;
  String? _downloadError;

  bool get _mobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _downloadError = null;
    });
    try {
      await const QpdfEngineFetch().fetchOnce();
      if (!mounted) return;
      widget.onRecheck();
    } catch (e) {
      if (!mounted) return;
      final text = e.toString();
      const prefix = 'Bad state: ';
      setState(() {
        _downloadError =
            text.startsWith(prefix) ? text.substring(prefix.length) : text;
      });
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = widget.busy || _downloading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _mobile ? 'Desktop-only feature' : 'PDF engine unavailable',
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: DsSpacing.xs),
        Text(
          SecurityQpdfUnavailablePanel.unavailableMessage,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        ),
        if (!_mobile)
          TextButton(
            onPressed: busy ? null : widget.onRecheck,
            child: const Text('Check again'),
          ),
        if (!_mobile)
          TextButton(
            onPressed: busy ? null : _download,
            child: Text(_downloading ? 'Downloading qpdf…' : 'Download qpdf'),
          ),
        if (_downloadError != null)
          Text(
            _downloadError!,
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}

class SecurityRelatedToolsPanel extends StatelessWidget {
  const SecurityRelatedToolsPanel({
    super.key,
    this.busy = false,
    this.excludePath,
    this.sourceFile,
    this.sourcePassword,
    this.compact = false,
  });

  /// Single wrapping row of chips instead of a vertical list.
  final bool compact;
  final bool busy;
  final String? excludePath;
  final LocalFileRef? sourceFile;
  final String? sourcePassword;

  @override
  Widget build(BuildContext context) {
    void go(String path) {
      if (excludePath == path) return;
      final file = sourceFile;
      if (file != null) {
        context.push(
          path,
          extra: PdfDocumentRouteArgs(file: file, password: sourcePassword),
        );
      } else {
        context.push(path);
      }
    }

    final theme = Theme.of(context);
    if (compact) {
      final items = <(String, IconData, String)>[
        (protectRoutePath, Icons.lock_outline, 'Encrypt'),
        (unlockRoutePath, Icons.lock_open_outlined, 'Decrypt'),
        (metadataRoutePath, Icons.description_outlined, 'Edit metadata'),
        (
          removeMetadataRoutePath,
          Icons.cleaning_services_outlined,
          'Remove metadata',
        ),
        (compressRoutePath, Icons.compress, 'Compress'),
      ];
      return Wrap(
        spacing: DsSpacing.sm,
        runSpacing: DsSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Related:',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.hintColor,
            ),
          ),
          for (final (path, icon, label) in items)
            if (path != excludePath)
              ActionChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                visualDensity: VisualDensity.compact,
                onPressed: busy ? null : () => go(path),
              ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Related tools',
          style: theme.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        if (excludePath != protectRoutePath)
          TextButton.icon(
            onPressed: busy ? null : () => go(protectRoutePath),
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Encrypt'),
          ),
        if (excludePath != unlockRoutePath)
          TextButton.icon(
            onPressed: busy ? null : () => go(unlockRoutePath),
            icon: const Icon(Icons.lock_open_outlined, size: 18),
            label: const Text('Decrypt'),
          ),
        if (excludePath != metadataRoutePath)
          TextButton.icon(
            onPressed: busy ? null : () => go(metadataRoutePath),
            icon: const Icon(Icons.description_outlined, size: 18),
            label: const Text('Edit metadata'),
          ),
        if (excludePath != removeMetadataRoutePath)
          TextButton.icon(
            onPressed: busy ? null : () => go(removeMetadataRoutePath),
            icon: const Icon(Icons.cleaning_services_outlined, size: 18),
            label: const Text('Remove metadata'),
          ),
        if (excludePath != compressRoutePath)
          TextButton.icon(
            onPressed: busy ? null : () => go(compressRoutePath),
            icon: const Icon(Icons.compress, size: 18),
            label: const Text('Compress PDF'),
          ),
      ],
    );
  }
}
