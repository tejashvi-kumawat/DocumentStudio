import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/features/ocr/ocr_tool_widgets.dart';
import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

/// OCR the current page of the open PDF (does not rewrite the file).
class ViewerOcrImagePanel extends ConsumerStatefulWidget {
  const ViewerOcrImagePanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerOcrImagePanel> createState() =>
      _ViewerOcrImagePanelState();
}

class _ViewerOcrImagePanelState extends ConsumerState<ViewerOcrImagePanel> {
  OcrOptions _options = const OcrOptions();
  OcrTextResult? _result;
  bool _busy = false;

  bool get _engineBlocked => isOcrEngineBlocked(ref.read(ocrPortProvider));

  Future<Uint8List> _renderCurrentPagePng() async {
    final password = widget.handoff.password;
    // Shared cache, current page only — never loadAllPages on the open file.
    final lease = await PdfDocumentCache.instance.acquire(
      widget.handoff.file.path,
      password: password,
    );
    try {
      final doc = lease.document;
      final pageIndex = widget.handoff.currentPage1 - 1;
      if (pageIndex < 0 || pageIndex >= doc.pages.length) {
        throw StateError('Invalid page');
      }
      final page = doc.pages[pageIndex];
      final scale = PdfToImagesService.renderScaleForDpi(_options.dpi);
      final pdfImage = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
      );
      if (pdfImage == null) {
        throw StateError('Could not render page');
      }
      try {
        final frame = img.Image.fromBytes(
          width: pdfImage.width,
          height: pdfImage.height,
          bytes: pdfImage.pixels.buffer,
          order: img.ChannelOrder.bgra,
        );
        return Uint8List.fromList(img.encodePng(frame));
      } finally {
        pdfImage.dispose();
      }
    } finally {
      lease.release();
    }
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final png = await _renderCurrentPagePng();
      final port = ref.read(ocrPortProvider);
      final result = await port.recognizeText(png, options: _options);
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      final mapped = mapOcrException(e);
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shortToolHelper(
              mapped.recoveryHint ?? mapped.message,
              fallback: 'Couldn’t read text on this page.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyResult() async {
    final text = _result?.text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied OCR text')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    if (_engineBlocked) {
      return ViewerToolFormBody(
        child: Text(
          'Text recognition isn’t ready on this device yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            color: secondary,
          ),
        ),
      );
    }

    return ViewerToolFormBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Page ${widget.handoff.currentPage1}',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: DsSpacing.xs),
          Text(
            'Reads the text on this page so you can copy it.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.md),
          OcrOptionsPanel(
            options: _options,
            busy: _busy,
            onChanged: (o) => setState(() => _options = o),
          ),
          const SizedBox(height: DsSpacing.md),
          ViewerToolPrimaryButton(
            label: _busy ? 'Reading…' : 'Recognize this page',
            icon: Icons.document_scanner_outlined,
            onPressed: _busy ? null : _run,
          ),
          if (_busy) ...[
            const SizedBox(height: DsSpacing.md),
            const LinearProgressIndicator(),
          ],
          if (_result != null) ...[
            const SizedBox(height: DsSpacing.lg),
            Text('Result', style: theme.textTheme.titleSmall),
            const SizedBox(height: DsSpacing.sm),
            SelectableText(_result!.text),
            const SizedBox(height: DsSpacing.sm),
            ViewerToolSecondaryButton(
              onPressed: _copyResult,
              icon: Icons.copy_outlined,
              label: 'Copy text',
            ),
          ],
        ],
      ),
    );
  }
}
