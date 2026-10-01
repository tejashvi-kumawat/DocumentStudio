import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/infrastructure/pdf/pdf_embedded_files.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// DS-READ-012 — embedded files from the open session PDF.
class PdfViewerAttachmentsPanel extends ConsumerStatefulWidget {
  const PdfViewerAttachmentsPanel({
    super.key,
    this.pdfPath,
    this.protectedPdfPaths = const [],
    this.reloadToken,
    this.storage,
    this.openExtractedFile,
    this.loadFiles,
    this.extractBytes,
  });

  /// Session working copy (or the source when no working file exists yet).
  final String? pdfPath;

  /// Paths that Open and Save must not replace. Includes the original PDF.
  final List<String> protectedPdfPaths;

  /// Changes when the working copy is rewritten so the list reloads.
  final Object? reloadToken;

  /// Overrides [fileStorageProvider] (tests).
  final FileStoragePort? storage;

  /// Overrides the system opener (tests). Return false when launch fails.
  final Future<bool> Function(String path)? openExtractedFile;

  /// Overrides reading the session file (tests).
  final Future<List<PdfEmbeddedFile>> Function(String path)? loadFiles;

  /// Overrides extracting one embedded file (tests).
  final Future<Uint8List> Function(String path, int index)? extractBytes;

  @override
  ConsumerState<PdfViewerAttachmentsPanel> createState() =>
      _PdfViewerAttachmentsPanelState();
}

class _PdfViewerAttachmentsPanelState
    extends ConsumerState<PdfViewerAttachmentsPanel> {
  List<PdfEmbeddedFile> _files = const [];
  String? _error;
  bool _loading = true;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _load(announce: false);
  }

  @override
  void didUpdateWidget(covariant PdfViewerAttachmentsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pdfPath != widget.pdfPath ||
        oldWidget.reloadToken != widget.reloadToken) {
      Future.microtask(() {
        if (mounted) _load();
      });
    }
  }

  void _apply(VoidCallback change, {required bool announce}) {
    if (!announce) {
      change();
      return;
    }
    if (!mounted) return;
    setState(change);
  }

  List<String> get _protectedPaths => [
    ...widget.protectedPdfPaths,
    if (widget.pdfPath != null) widget.pdfPath!,
  ];

  Future<void> _load({bool announce = true}) async {
    final gen = ++_loadGen;
    final path = widget.pdfPath;
    if (path == null || path.isEmpty) {
      _apply(() {
        _files = const [];
        _error = null;
        _loading = false;
      }, announce: announce);
      return;
    }
    _apply(() {
      _loading = true;
      _error = null;
    }, announce: announce);
    try {
      final files = await (widget.loadFiles ?? listPdfEmbeddedFilesAtPath)(
        path,
      );
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _files = files;
        _error = null;
        _loading = false;
      });
    } on PdfEmbeddedFileException catch (e) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _files = const [];
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _files = const [];
        _error = 'Could not read attachments.';
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _open(int index) async {
    final path = widget.pdfPath;
    if (path == null || index < 0 || index >= _files.length) return;
    final file = _files[index];
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open attachment?'),
        content: Text(
          'Open "${file.fileName}" with another application? '
          'The PDF itself is not changed.',
        ),
        actions: [
          TextButton(
            key: const Key('pdf_attachment_open_cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('pdf_attachment_open_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    try {
      final bytes = await (widget.extractBytes ?? extractPdfEmbeddedFileAtPath)(
        path,
        index,
      );
      if (!mounted) return;
      final extracted = await writeExtractedAttachmentToTemp(
        bytes: bytes,
        fileName: file.fileName,
        protectedPdfPaths: _protectedPaths,
      );
      final opener =
          widget.openExtractedFile ?? openExtractedAttachmentWithSystem;
      final opened = await opener(extracted);
      if (!mounted) return;
      if (!opened) _snack('Could not open the attachment.');
    } on PdfEmbeddedFileException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not open the attachment.');
    }
  }

  Future<void> _save(int index) async {
    final path = widget.pdfPath;
    if (path == null || index < 0 || index >= _files.length) return;
    final file = _files[index];
    final FileStoragePort storage =
        widget.storage ?? ref.read(fileStorageProvider);
    final directory = await storage.pickOutputDirectory(
      dialogTitle: 'Save attachment',
    );
    if (directory == null || !mounted) return;
    try {
      final bytes = await (widget.extractBytes ?? extractPdfEmbeddedFileAtPath)(
        path,
        index,
      );
      if (!mounted) return;
      await writePdfAttachmentFile(
        storage: storage,
        directory: directory,
        fileName: file.fileName,
        bytes: bytes,
        protectedPdfPaths: _protectedPaths,
      );
      if (!mounted) return;
      _snack('Saved ${file.fileName}');
    } on PdfEmbeddedFileException catch (e) {
      if (mounted) _snack(e.message);
    } catch (_) {
      if (mounted) _snack('Could not save the attachment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Padding(
      padding: const EdgeInsets.all(DsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Attachments', style: theme.textTheme.titleSmall),
          const SizedBox(height: DsSpacing.sm),
          if (_loading)
            Text(
              'Reading attachments…',
              key: const Key('pdf_attachments_loading'),
              style: muted,
            )
          else if (_error != null)
            Text(_error!, key: const Key('pdf_attachments_error'), style: muted)
          else if (_files.isEmpty)
            Text(
              'No attachments',
              key: const Key('pdf_attachments_empty'),
              style: muted,
            )
          else
            Expanded(
              child: ListView.builder(
                key: const Key('pdf_attachments_list'),
                padding: EdgeInsets.zero,
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          file.fileName,
                          key: Key('pdf_attachment_name_$index'),
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (file.description != null)
                          Text(
                            file.description!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (file.declaredBytes != null)
                          Text(
                            formatAttachmentSize(file.declaredBytes!),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        Wrap(
                          spacing: DsSpacing.xs,
                          children: [
                            TextButton(
                              key: Key('pdf_attachment_open_$index'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DsSpacing.xs,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _open(index),
                              child: const Text('Open'),
                            ),
                            TextButton(
                              key: Key('pdf_attachment_save_$index'),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: DsSpacing.xs,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () => _save(index),
                              child: const Text('Save'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
