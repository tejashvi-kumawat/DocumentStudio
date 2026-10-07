import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/pdf_markup/pdf_markup_models.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/infrastructure/ocr/android_searchable_pdf_service.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:document_studio/infrastructure/ocr/tesseract_searchable_pdf_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum ViewerBatchOp { rotate, compress, watermark, pageNumbers, ocr }

String viewerBatchOpLabel(ViewerBatchOp op) => switch (op) {
  ViewerBatchOp.rotate => 'Rotate 90° CW',
  ViewerBatchOp.compress => 'Compress (balanced)',
  ViewerBatchOp.watermark => 'Watermark',
  ViewerBatchOp.pageNumbers => 'Page numbers',
  ViewerBatchOp.ocr => 'Searchable OCR',
};

/// Run one operation across a page range of the open document (in-panel batch).
class ViewerBatchPanel extends ConsumerStatefulWidget {
  const ViewerBatchPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerBatchPanel> createState() => _ViewerBatchPanelState();
}

class _ViewerBatchPanelState extends ConsumerState<ViewerBatchPanel> {
  ViewerBatchOp _op = ViewerBatchOp.rotate;
  PdfPageScopeKind _scopeKind = PdfPageScopeKind.allPages;
  String _rangeExpression = '';
  String? _rangeError;
  bool _busy = false;
  String? _progress;
  final _watermarkCtrl = TextEditingController(text: 'CONFIDENTIAL');

  @override
  void dispose() {
    _watermarkCtrl.dispose();
    super.dispose();
  }

  Set<int>? _resolvePages() {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return null;
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
      return null;
    }
    setState(() => _rangeError = null);
    return resolved.pages;
  }

  Future<void> _commitBytes(Uint8List bytes, String message) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session != null && session.sameDocumentPath(widget.handoff.file.path)) {
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage: message,
      );
    } else {
      await commitOrganizeExport(
        ref: ref,
        context: context,
        bytes: bytes,
        successMessage: message,
      );
    }
  }

  Future<void> _apply() async {
    final pages = _resolvePages();
    if (pages == null || pages.isEmpty) return;
    final total = widget.pageCount!;
    final file = widget.handoff.file;
    final password = widget.handoff.password;

    setState(() {
      _busy = true;
      _progress = 'Working…';
    });
    try {
      switch (_op) {
        case ViewerBatchOp.rotate:
          setState(() => _progress = 'Rotating pages…');
          final exportPages = pagesForRotate(file, total, pages, 90);
          await exportViewerOrganizePages(
            ref: ref,
            context: context,
            handoff: widget.handoff,
            pages: exportPages,
            passwordsByPath: password == null ? null : {file.path: password},
            successMessage: 'Rotated pages saved.',
            suggestedName:
                '${p.basenameWithoutExtension(file.displayName)}_rotated.pdf',
          );
        case ViewerBatchOp.compress:
          setState(() => _progress = 'Compressing…');
          final temp = await ref
              .read(fileStorageProvider)
              .createTempFile(prefix: 'batch-compress', suffix: '.pdf');
          await ref
              .read(compressServiceProvider)
              .compressToPath(
                input: file,
                outputPath: temp,
                options: PdfCompressOptions.fromProfile(
                  CompressProfile.balanced,
                ),
                password: password,
              );
          final bytes = await File(temp).readAsBytes();
          await _commitBytes(
            Uint8List.fromList(bytes),
            'Compressed PDF saved.',
          );
        case ViewerBatchOp.watermark:
          setState(() => _progress = 'Applying watermark…');
          final text = _watermarkCtrl.text.trim();
          if (text.isEmpty) {
            _snack('Enter watermark text.');
            return;
          }
          final temp = await ref
              .read(fileStorageProvider)
              .createTempFile(prefix: 'batch-wm', suffix: '.pdf');
          await ref
              .read(pdfOverlayServiceProvider)
              .applyTextWatermark(
                input: file,
                outputPath: temp,
                options: WatermarkOptions(
                  textTemplate: text,
                  pages1Based: pages,
                ),
                password: password,
              );
          final bytes = await File(temp).readAsBytes();
          await _commitBytes(Uint8List.fromList(bytes), 'Watermark applied.');
        case ViewerBatchOp.pageNumbers:
          setState(() => _progress = 'Adding page numbers…');
          // Overlay applies to all pages; for a subset, stamp only those via
          // watermark-style per-page filter by rebuilding page-number overlay
          // only on selected pages through temporary watermark of numbers.
          final temp = await ref
              .read(fileStorageProvider)
              .createTempFile(prefix: 'batch-pgn', suffix: '.pdf');
          final opts = const PageNumberOptions();
          // Apply full page numbers then... actually applyPageNumbers marks all.
          // Use overlay service with custom approach: call applyPageNumbers for
          // whole doc when all pages selected; otherwise watermark each label.
          if (pages.length == total) {
            await ref
                .read(pdfOverlayServiceProvider)
                .applyPageNumbers(
                  input: file,
                  outputPath: temp,
                  options: opts,
                  password: password,
                );
          } else {
            await ref
                .read(pdfOverlayServiceProvider)
                .applyTextWatermark(
                  input: file,
                  outputPath: temp,
                  options: WatermarkOptions(
                    textTemplate: '{{page}}',
                    fontSizePt: 10,
                    opacity: 1,
                    placement: WatermarkPlacement.bottomRight,
                    pages1Based: pages,
                  ),
                  password: password,
                );
          }
          final bytes = await File(temp).readAsBytes();
          await _commitBytes(
            Uint8List.fromList(bytes),
            'Page numbers applied.',
          );
        case ViewerBatchOp.ocr:
          setState(() => _progress = 'Running OCR…');
          final service = ref.read(searchablePdfPortProvider);
          if (service is TesseractSearchablePdfService) {
            final status = await service.probeEngine();
            if (!status.isReady) {
              _snack(status.missingMessage!);
              return;
            }
            final bytes = await service.makeSearchableFile(
              file: file,
              password: password,
              pages1Based: pages,
              onProgress: (f, msg) {
                if (mounted) setState(() => _progress = msg);
              },
            );
            await _commitBytes(bytes, 'Searchable text layer added.');
          } else if (service is AndroidSearchablePdfService) {
            final status = await service.probeEngine();
            if (!status.isReady) {
              _snack(status.missingMessage!);
              return;
            }
            final bytes = await service.makeSearchableFile(
              file: file,
              password: password,
              pages1Based: pages,
              onProgress: (f, msg) {
                if (mounted) setState(() => _progress = msg);
              },
            );
            await _commitBytes(bytes, 'Searchable text layer added.');
          } else {
            _snack(BlockedSearchablePdfPort.blockedReason);
            return;
          }
      }
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compressNote = _op == ViewerBatchOp.compress;

    return ColoredBox(
      color: const Color(0xFFF4F4F4),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(DsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Run one operation on a page range of this document.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.md),
            Text(
              'Operation',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
            const SizedBox(height: DsSpacing.xs),
            DropdownButtonFormField<ViewerBatchOp>(
              key: const Key('viewer_batch_op'),
              value: _op,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                for (final op in ViewerBatchOp.values)
                  DropdownMenuItem(
                    value: op,
                    child: Text(viewerBatchOpLabel(op)),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) {
                      if (v != null) setState(() => _op = v);
                    },
            ),
            const SizedBox(height: DsSpacing.md),
            if (!compressNote)
              PdfPageScopeField(
                kind: _scopeKind,
                onKindChanged: (k) => setState(() => _scopeKind = k),
                rangeExpression: _rangeExpression,
                onRangeExpressionChanged: (v) =>
                    setState(() => _rangeExpression = v),
                selectedPageCount: widget.selectedPages1Based.length,
                rangeError: _rangeError,
              )
            else
              Text(
                'Compress applies to the whole file (page range is ignored).',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              ),
            if (_op == ViewerBatchOp.watermark) ...[
              const SizedBox(height: DsSpacing.md),
              TextField(
                controller: _watermarkCtrl,
                decoration: const InputDecoration(
                  labelText: 'Watermark text',
                  labelStyle: TextStyle(fontSize: 13),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 13),
                enabled: !_busy,
              ),
            ],
            if (_progress != null) ...[
              const SizedBox(height: DsSpacing.sm),
              Text(
                _progress!,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              ),
            ],
            const SizedBox(height: DsSpacing.md),
            Tooltip(
              message: 'Apply to this document and save in place (undoable)',
              child: DsPrimaryButton(
                key: const Key('viewer_batch_apply'),
                onPressed: _busy ? null : _apply,
                label: _busy ? 'Working…' : 'Apply',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
