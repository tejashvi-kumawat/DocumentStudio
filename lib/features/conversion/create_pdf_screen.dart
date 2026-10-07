import 'package:document_studio/features/compose/compose_templates.dart';
import 'package:document_studio/features/compose/template_gallery_screen.dart';
import 'package:document_studio/features/compose/compose_screen.dart'
    show composeRoutePath;

import 'dart:io';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/infrastructure/conversion/blank_pdf_service.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_layout.dart';
import 'package:document_studio/infrastructure/conversion/text_to_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

enum _CreatePdfMode { text, markdown, html, latex, blank }

extension on _CreatePdfMode {
  /// Source languages open the side-by-side writer.
  String? get composeExt => switch (this) {
    _CreatePdfMode.markdown => 'md',
    _CreatePdfMode.html => 'html',
    _CreatePdfMode.latex => 'tex',
    _ => null,
  };
}

/// Dependencies for [CreatePdfScreen] (injected from route / tests).
class CreatePdfDeps {
  const CreatePdfDeps({
    required this.fileStorage,
    required this.textToPdf,
    required this.blankPdf,
  });

  final FileStoragePort fileStorage;
  final TextToPdfService textToPdf;
  final BlankPdfService blankPdf;
}

/// Create a new PDF from typed text or as blank pages.
class CreatePdfScreen extends StatefulWidget {
  const CreatePdfScreen({super.key, required this.deps});

  final CreatePdfDeps deps;

  @override
  State<CreatePdfScreen> createState() => _CreatePdfScreenState();
}

class _CreatePdfScreenState extends State<CreatePdfScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();
  final _pagesController = TextEditingController(text: '1');
  _CreatePdfMode _mode = _CreatePdfMode.text;
  TextToPdfPagePreset _textPreset = TextToPdfPagePreset.a4;
  BlankPdfPagePreset _blankPreset = BlankPdfPagePreset.a4;
  double _fontSizePt = 12;
  double _marginPt = 72;

  bool _busy = false;
  LocalFileRef? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    final locale = WidgetsBinding.instance.platformDispatcher.locale;
    if (locale.countryCode == 'US' || locale.countryCode == 'CA') {
      _textPreset = TextToPdfPagePreset.letter;
      _blankPreset = BlankPdfPagePreset.letter;
    }
  }

  void _setMode(_CreatePdfMode m) {
    if (m.composeExt case final ext?) {
      context.push('$composeRoutePath?lang=$ext');
      return;
    }
    setState(() => _mode = m);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _pagesController.dispose();
    super.dispose();
  }

  String get _title {
    final t = _titleController.text.trim();
    if (t.isNotEmpty) return t;
    return _mode == _CreatePdfMode.text ? 'Document' : 'Blank document';
  }

  String get _suggestedFileName {
    final safe = _title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    return '${safe.isEmpty ? 'Document' : safe}.pdf';
  }

  int get _blankPages => int.tryParse(_pagesController.text.trim()) ?? 0;

  bool get _canCreate => switch (_mode) {
    _CreatePdfMode.text => _bodyController.text.trim().isNotEmpty,
    _CreatePdfMode.markdown ||
    _CreatePdfMode.html ||
    _CreatePdfMode.latex => false,
    _CreatePdfMode.blank =>
      _blankPages >= 1 && _blankPages <= BlankPdfService.maxPages,
  };

  Future<void> _create() async {
    if (!_canCreate || _busy) return;
    setState(() {
      _busy = true;
      _saved = null;
      _error = null;
    });
    final storage = widget.deps.fileStorage;
    String? temp;
    try {
      temp = await storage.createTempFile(prefix: 'create-pdf', suffix: '.pdf');
      final LocalFileRef created;
      if (_mode == _CreatePdfMode.text) {
        final base = _textPreset.layout;
        created = await widget.deps.textToPdf.fromPlainText(
          text: _bodyController.text,
          outputPath: temp,
          title: _title,
          layout: TextToPdfLayout(
            pageWidthPt: base.pageWidthPt,
            pageHeightPt: base.pageHeightPt,
            fontSizePt: _fontSizePt,
            marginPt: _marginPt,
          ),
        );
      } else {
        created = await widget.deps.blankPdf.create(
          outputPath: temp,
          pageCount: _blankPages,
          preset: _blankPreset,
          title: _title,
        );
      }
      final bytes = await storage.readBytes(created);
      final save = await storage.pickSavePath(
        suggestedName: _suggestedFileName,
        bytes: bytes,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
      );
      if (save == null) return;
      await storage.writeAtomic(
        destinationPath: save,
        writeToTemp: (t) => File(t).writeAsBytes(bytes, flush: true),
      );
      if (!mounted) return;
      setState(() {
        _saved = LocalFileRef(
          path: save,
          displayName: p.basename(save),
          sizeBytes: bytes.length,
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (temp != null) File(temp).delete().ignore();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Right-hand pane: the writing surface for Text, a page mock-up otherwise.
  Widget _preview(ThemeData theme, Brightness b, bool isText) {
    if (isText) {
      return Padding(
        padding: const EdgeInsets.all(DsSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _bodyController,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: 'DS Sans',
                  fontSize: 15,
                  height: 1.5,
                ),
                decoration: InputDecoration(
                  hintText: 'Type or paste your text here…',
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  contentPadding: const EdgeInsets.all(DsSpacing.xl),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.sm),
              child: Text(
                _textStats(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DsColors.textSecondary(b),
                ),
              ),
            ),
          ],
        ),
      );
    }
    final pages = _blankPages.clamp(1, BlankPdfService.maxPages);
    final shown = pages.clamp(1, 3);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 300,
              width: 260,
              child: Stack(
                children: [
                  for (var i = shown - 1; i >= 0; i--)
                    Positioned(
                      left: i * 14.0,
                      top: i * 10.0,
                      child: Container(
                        width: 212,
                        height: 280,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: DsColors.border(b)),
                          boxShadow: DsSpacing.cardShadowLight(opacity: 0.12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: DsSpacing.lg),
            Text(
              '$pages ${pages == 1 ? 'blank page' : 'blank pages'} · ${_blankPreset.label}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DsColors.textSecondary(b),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final isText = _mode == _CreatePdfMode.text;

    return DsToolPage(
      title: 'Create PDF',
      subtitle:
          'Start a new PDF from text, Markdown, HTML, LaTeX or blank pages.',
      icon: Icons.note_add_outlined,
      preview: _preview(theme, b, isText),
      primaryLabel: 'Create & save as…',
      primaryIcon: Icons.save_alt_rounded,
      primaryEnabled: _canCreate,
      primaryBusy: _busy,
      onPrimary: _create,
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      footer: Wrap(
        spacing: DsSpacing.sm,
        runSpacing: DsSpacing.sm,
        children: [
          ActionChip(
            avatar: const Icon(Icons.collections_outlined, size: 16),
            label: const Text('Images to PDF'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => context.push(imagesToPdfRoutePath),
          ),
          ActionChip(
            avatar: const Icon(Icons.description_outlined, size: 16),
            label: const Text('Office to PDF'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy
                ? null
                : () => context.push(officeConvertRoutePath),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DsToolSection(
            topPadding: false,
            title: 'Start from a template',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in TemplateCategory.values)
                  ActionChip(
                    avatar: Icon(c.icon, size: 18),
                    label: Text(c.label),
                    onPressed: _busy
                        ? null
                        : () => context.push(
                            '$templateGalleryRoutePath?category=${c.name}',
                          ),
                  ),
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () => context.push(templateGalleryRoutePath),
                  icon: const Icon(Icons.grid_view_rounded, size: 18),
                  label: Text(
                    'Browse all ${kComposeTemplates.length} templates',
                  ),
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Start from',
            child: DsToolChoiceGroup<_CreatePdfMode>(
              selected: _mode,
              minCardWidth: 200,
              onChanged: _busy ? null : _setMode,
              choices: const [
                DsToolChoice(
                  value: _CreatePdfMode.text,
                  title: 'Text',
                  subtitle:
                      'Type or paste — wraps onto as many pages as needed',
                  icon: Icons.notes_rounded,
                ),
                DsToolChoice(
                  value: _CreatePdfMode.markdown,
                  title: 'Markdown',
                  subtitle: 'Write with live preview — tables, code, maths',
                  icon: Icons.tag_rounded,
                ),
                DsToolChoice(
                  value: _CreatePdfMode.html,
                  title: 'HTML + CSS',
                  subtitle: 'Tags and inline styles, live preview',
                  icon: Icons.code_rounded,
                ),
                DsToolChoice(
                  value: _CreatePdfMode.latex,
                  title: 'LaTeX',
                  subtitle: 'Overleaf-style editor, maths, numbering — offline',
                  icon: Icons.functions_rounded,
                ),
                DsToolChoice(
                  value: _CreatePdfMode.blank,
                  title: 'Blank pages',
                  subtitle: 'Empty pages to fill, sign or annotate later',
                  icon: Icons.insert_drive_file_outlined,
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Title',
            child: TextField(
              controller: _titleController,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: isText ? 'Document' : 'Blank document',
                helperText: 'Stored in the PDF and used as the file name',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: isText
                ? Column(
                    key: const ValueKey('text'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DsToolSection(
                        title: 'Layout',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            DsToolChoiceGroup<TextToPdfPagePreset>(
                              selected: _textPreset,
                              minCardWidth: 160,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _textPreset = v),
                              choices: const [
                                DsToolChoice(
                                  value: TextToPdfPagePreset.a4,
                                  title: 'A4',
                                  subtitle: '210 × 297 mm',
                                  icon: Icons.crop_portrait_rounded,
                                ),
                                DsToolChoice(
                                  value: TextToPdfPagePreset.letter,
                                  title: 'US Letter',
                                  subtitle: '8.5 × 11 in',
                                  icon: Icons.crop_portrait_rounded,
                                ),
                              ],
                            ),
                            const SizedBox(height: DsSpacing.md),
                            _sliderRow(
                              label: 'Font size',
                              value: _fontSizePt,
                              min: 9,
                              max: 18,
                              divisions: 9,
                              unit: 'pt',
                              onChanged: (v) => setState(() => _fontSizePt = v),
                            ),
                            _sliderRow(
                              label: 'Margins',
                              value: _marginPt,
                              min: 36,
                              max: 108,
                              divisions: 6,
                              unit: 'pt',
                              onChanged: (v) => setState(() => _marginPt = v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    key: const ValueKey('blank'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DsToolSection(
                        title: 'Pages',
                        child: Row(
                          children: [
                            IconButton.outlined(
                              tooltip: 'Fewer pages',
                              onPressed: _busy || _blankPages <= 1
                                  ? null
                                  : () => setState(
                                      () => _pagesController.text =
                                          '${_blankPages - 1}',
                                    ),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            const SizedBox(width: DsSpacing.sm),
                            SizedBox(
                              width: 88,
                              child: TextField(
                                controller: _pagesController,
                                enabled: !_busy,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                  errorText: _canCreate
                                      ? null
                                      : '1–${BlankPdfService.maxPages}',
                                ),
                              ),
                            ),
                            const SizedBox(width: DsSpacing.sm),
                            IconButton.outlined(
                              tooltip: 'More pages',
                              onPressed:
                                  _busy ||
                                      _blankPages >= BlankPdfService.maxPages
                                  ? null
                                  : () => setState(
                                      () => _pagesController.text =
                                          '${_blankPages + 1}',
                                    ),
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
                      DsToolSection(
                        title: 'Page size',
                        child: DsToolChoiceGroup<BlankPdfPagePreset>(
                          selected: _blankPreset,
                          minCardWidth: 140,
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _blankPreset = v),
                          choices: [
                            for (final preset in BlankPdfPagePreset.values)
                              DsToolChoice(
                                value: preset,
                                title: preset.label,
                                icon: Icons.crop_portrait_rounded,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolProgressCard(message: 'Building PDF…'),
            ),
          if (_error != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: 'Could not create the PDF',
                message: _error,
                tone: DsResultTone.error,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          if (_saved case final saved? when !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: 'PDF created',
                file: saved,
                stats: [
                  if (saved.sizeBytes != null)
                    DsResultStat('Size', dsFormatBytes(saved.sizeBytes!)),
                ],
                onOpen: () => openToolResult(context, saved),
                openLabel: 'Open in viewer',
                onShowInFolder: documentSaveResultCanRevealInFolder
                    ? () => revealToolResult(context, saved)
                    : null,
                onDismiss: () => setState(() => _saved = null),
              ),
            ),
        ],
      ),
    );
  }

  String _textStats() {
    final text = _bodyController.text.trim();
    if (text.isEmpty) return 'Nothing typed yet';
    final words = text.split(RegExp(r'\s+')).length;
    final lines = '\n'.allMatches(text).length + 1;
    return '$words ${words == 1 ? 'word' : 'words'} · '
        '$lines ${lines == 1 ? 'line' : 'lines'}';
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String unit,
    required ValueChanged<double> onChanged,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          child: DsAdaptiveSlider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            label: '${value.round()} $unit',
            onChanged: _busy ? null : onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${value.round()} $unit',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
