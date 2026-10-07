import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Export PDF pages to PNG/JPEG from the viewer panel.
class ViewerExportImagesPanel extends ConsumerStatefulWidget {
  const ViewerExportImagesPanel({
    super.key,
    required this.handoff,
    required this.format,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final PdfToImageFormat format;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerExportImagesPanel> createState() =>
      _ViewerExportImagesPanelState();
}

class _ViewerExportImagesPanelState
    extends ConsumerState<ViewerExportImagesPanel> {
  PdfPageScopeKind _scopeKind = PdfPageScopeKind.thisPage;
  String _rangeExpression = '';
  String? _rangeError;
  String? _outputDirectory;
  int _dpi = PdfToImagesService.defaultDpi;
  bool _busy = false;

  Future<void> _pickFolder() async {
    final storage = ref.read(fileStorageProvider);
    final dest = await storage.pickOutputDirectory(
      dialogTitle: 'Choose folder for exported images',
    );
    if (dest != null && mounted) {
      setState(() => _outputDirectory = dest);
    }
  }

  Future<void> _export() async {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return;
    }
    final resolved = resolvePdfPageScope(
      kind: _scopeKind,
      currentPage1: widget.handoff.currentPage1,
      selectedPages1Based: widget.selectedPages1Based,
      totalPages: total,
      rangeExpression: _rangeExpression,
    );
    if (!resolved.isOk) {
      setState(() => _rangeError = resolved.error);
      return;
    }
    setState(() => _rangeError = null);

    var outDir = _outputDirectory;
    if (outDir == null || outDir.isEmpty) {
      await _pickFolder();
      outDir = _outputDirectory;
    }
    if (outDir == null || outDir.isEmpty) return;

    setState(() => _busy = true);
    final job = JobHandle<List<dynamic>>();
    Directory? workDir;
    try {
      final storage = ref.read(fileStorageProvider);
      final pdfToImages = PdfToImagesService();
      final jobs = ref.read(jobRunnerProvider);
      workDir = await Directory(
        '${await storage.getTempDirectory()}/viewer-export-${DateTime.now().microsecondsSinceEpoch}',
      ).create(recursive: true);

      final pages = resolved.pages!.toList()..sort();
      final exported = <dynamic>[];
      await jobs.run(
        handle: job,
        work: (report, cancelToken) async {
          for (var i = 0; i < pages.length; i++) {
            final page = pages[i];
            report(
              JobProgress(
                fraction: pages.isEmpty ? 0 : i / pages.length,
                message: 'Rendering page $page',
              ),
            );
            final batch = await pdfToImages.exportPages(
              pdf: widget.handoff.file,
              outputDirectory: workDir!.path,
              format: widget.format,
              dpi: _dpi,
              firstPage1: page,
              lastPage1: page,
              password: widget.handoff.password,
              cancelToken: cancelToken,
            );
            exported.addAll(batch);
          }
          report(const JobProgress(fraction: 1, message: 'Done'));
          return exported;
        },
      );

      for (final image in exported) {
        final bytes = await storage.readBytes(image);
        final destPath = '$outDir/${image.displayName}';
        await File(destPath).writeAsBytes(bytes, flush: true);
      }

      if (!mounted) return;
      _snack(
        'Exported ${exported.length} ${widget.format.label} file(s) to folder.',
      );
    } catch (e) {
      if (mounted) {
        _snack(shortToolHelper('$e', fallback: 'Couldn’t export these pages.'));
      }
    } finally {
      try {
        await workDir?.delete(recursive: true);
      } catch (_) {}
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final folder = _outputDirectory;
    return ViewerToolFormBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Saves the chosen pages as ${widget.format.label} files.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.md),
          PdfPageScopeField(
            kind: _scopeKind,
            onKindChanged: (k) => setState(() => _scopeKind = k),
            rangeExpression: _rangeExpression,
            onRangeExpressionChanged: (v) =>
                setState(() => _rangeExpression = v),
            selectedPageCount: widget.selectedPages1Based.length,
            rangeError: _rangeError,
          ),
          const SizedBox(height: DsSpacing.md),
          Text(
            'Output folder',
            style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.xs),
          Text(
            folder ?? 'You’ll pick a folder when you export.',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
          const SizedBox(height: DsSpacing.sm),
          ViewerToolSecondaryButton(
            label: folder == null ? 'Choose folder' : 'Change folder',
            icon: Icons.folder_open_outlined,
            onPressed: _busy ? null : _pickFolder,
          ),
          const SizedBox(height: DsSpacing.md),
          Row(
            children: [
              Text(
                'Resolution',
                style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              const Spacer(),
              Text('$_dpi DPI', style: theme.textTheme.bodySmall),
            ],
          ),
          Slider(
            value: _dpi.toDouble(),
            min: 72,
            max: 300,
            divisions: 19,
            label: '$_dpi',
            onChanged: _busy ? null : (v) => setState(() => _dpi = v.round()),
          ),
          const SizedBox(height: DsSpacing.sm),
          ViewerToolPrimaryButton(
            key: const Key('viewer_export_images_apply'),
            onPressed: _busy ? null : _export,
            icon: Icons.image_outlined,
            label: _busy ? 'Exporting…' : 'Export ${widget.format.label}',
          ),
        ],
      ),
    );
  }
}
