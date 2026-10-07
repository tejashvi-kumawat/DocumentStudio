import 'dart:async';
import 'dart:convert';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/ocr/ocr_tool_widgets.dart';
import 'package:document_studio/infrastructure/ocr/desktop_tesseract_ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class ImageOcrScreen extends StatefulWidget {
  const ImageOcrScreen({super.key, required this.deps});

  final ImageOcrDeps deps;

  @override
  State<ImageOcrScreen> createState() => _ImageOcrScreenState();
}

class _ImageOcrScreenState extends State<ImageOcrScreen> {
  LocalFileRef? _file;
  Uint8List? _previewBytes;
  OcrOptions _options = const OcrOptions();
  OcrTextResult? _result;
  OcrCancelToken? _token;
  String? _error;
  String? _engineError;

  bool get _busy => _token != null;

  bool get _engineBlocked =>
      isOcrEngineBlocked(widget.deps.ocrPort) || _engineError != null;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  Future<void> _probe({bool refresh = false}) async {
    if (widget.deps.ocrPort is BlockedOcrPort) return;
    final env = await loadOcrEngineEnvironment(refresh: refresh);
    if (!mounted) return;
    setState(() => _engineError = env.readinessError(_options.language));
  }

  static const _imageExtensions = [
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
    'tif',
    'tiff',
  ];

  Future<void> _pick() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: _imageExtensions,
    );
    if (picked != null) await _setFile(picked);
  }

  Future<void> _setFile(LocalFileRef picked) async {
    final bytes = await widget.deps.fileStorage.readBytes(picked);
    if (!mounted) return;
    setState(() {
      _file = picked;
      _previewBytes = bytes;
      _result = null;
      _error = null;
    });
  }

  Future<void> _run() async {
    final bytes = _previewBytes;
    if (bytes == null || _busy) return;
    final token = OcrCancelToken();
    setState(() {
      _token = token;
      _result = null;
      _error = null;
    });
    try {
      final port = widget.deps.ocrPort;
      final result = port is DesktopTesseractOcrPort
          ? await port.recognizeText(
              bytes,
              options: _options,
              cancelToken: token,
            )
          : await port.recognizeText(bytes, options: _options);
      if (!mounted || !identical(_token, token)) return;
      setState(() {
        _result = result;
        _token = null;
      });
    } on OcrCancelledException {
      if (mounted) setState(() => _token = null);
    } catch (e) {
      if (!mounted) return;
      final mapped = mapOcrException(e);
      setState(() {
        _token = null;
        _error = mapped.recoveryHint ?? mapped.message;
      });
    }
  }

  void _cancel() {
    _token?.cancel();
    setState(() => _token = null);
  }

  Future<void> _copyText() async {
    final text = _result?.text;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Text copied to clipboard')));
  }

  Future<void> _saveText() async {
    final text = _result?.text;
    if (text == null || text.isEmpty) return;
    final base = _file?.displayName ?? 'ocr';
    final name = base.contains('.')
        ? '${base.substring(0, base.lastIndexOf('.'))}_ocr.txt'
        : '${base}_ocr.txt';
    final saved = await widget.deps.fileStorage.pickSavePath(
      suggestedName: name,
      bytes: Uint8List.fromList(utf8.encode(text)),
      allowedExtensions: ['txt'],
      mimeType: 'text/plain',
    );
    if (!mounted || saved == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Saved to $saved')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);

    return DsToolPage(
      title: 'Image OCR',
      subtitle:
          'Extract text from a photo, screenshot, or scanned image. '
          'Runs fully offline.',
      icon: Icons.text_snippet_outlined,
      preview: _previewBytes != null
          ? DsImagePreview(bytes: _previewBytes!)
          : DsDropPane(
              allowedExtensions: _imageExtensions,
              enabled: !_busy,
              onPick: _pick,
              onFilesDropped: (files) {
                if (files.isNotEmpty) unawaited(_setFile(files.first));
              },
              emptyTitle: 'Drop an image here',
              emptySubtitle: 'Photos, screenshots, and scans',
              pickLabel: 'Choose image',
              icon: Icons.image_search_outlined,
            ),
      primaryLabel: _busy ? 'Recognizing…' : 'Recognize text',
      primaryIcon: Icons.document_scanner_outlined,
      primaryEnabled: _previewBytes != null && !_engineBlocked && !_busy,
      primaryBusy: _busy,
      onPrimary: _run,
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      busy: _busy,
      footer: OcrRelatedToolsPanel(busy: _busy, excludePath: imageOcrRoutePath),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_engineBlocked)
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpacing.lg),
              child: OcrEngineStatusPanel(
                portBlocked: true,
                blockedReason: _engineError,
                onRecheck: () => _probe(refresh: true),
              ),
            ),
          if (_file != null)
            DsToolSection(
              topPadding: false,
              title: 'Source image',
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _file!.displayName,
                      style: theme.textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DsSecondaryButton(
                    label: 'Change',
                    icon: Icons.swap_horiz,
                    onPressed: _busy ? null : _pick,
                  ),
                ],
              ),
            ),
          DsToolSection(
            title: 'Options',
            child: OcrOptionsPanel(
              options: _options,
              busy: _busy,
              onChanged: (o) {
                final langChanged = o.language != _options.language;
                setState(() => _options = o);
                if (langChanged) unawaited(_probe());
              },
            ),
          ),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, child: child),
            ),
            child: _buildStatus(theme, secondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(ThemeData theme, Color secondary) {
    if (_busy) {
      return Padding(
        key: const ValueKey('busy'),
        padding: const EdgeInsets.only(top: DsSpacing.lg),
        child: OcrProgressCard(
          fraction: null,
          message: 'Recognizing text…',
          onCancel: _cancel,
        ),
      );
    }
    if (_error != null) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: DsSpacing.lg),
        child: OcrResultBanner(
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
          title: 'Text recognition failed',
          details: _error!,
          actions: [
            TextButton(onPressed: _run, child: const Text('Try again')),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink(key: ValueKey('none'));
    final text = result.text.trim();
    final words = text.isEmpty ? 0 : text.split(RegExp(r'\s+')).length;
    return DsToolSection(
      key: const ValueKey('result'),
      title: 'Recognized text',
      subtitle: text.isEmpty
          ? 'No text was found. Try Best quality or Enhance faded scans.'
          : '$words word${words == 1 ? '' : 's'}',
      child: text.isEmpty
          ? const SizedBox.shrink()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  constraints: const BoxConstraints(maxHeight: 360),
                  padding: const EdgeInsets.all(DsSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.4,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result.text,
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                    ),
                  ),
                ),
                const SizedBox(height: DsSpacing.sm),
                Wrap(
                  spacing: DsSpacing.sm,
                  children: [
                    DsSecondaryButton(
                      label: 'Copy text',
                      icon: Icons.copy_outlined,
                      onPressed: _copyText,
                    ),
                    DsSecondaryButton(
                      label: 'Save as .txt',
                      icon: Icons.save_alt,
                      onPressed: _saveText,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
