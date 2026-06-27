import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/pdf/pdf_accessibility_tags_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Viewer panel: inspect `/Lang` / `/MarkInfo` / StructTreeRoot and set language.
///
/// Does not claim PDF/UA. Image `/Alt` is not offered without a real structure tree.
class ViewerAccessibilityTagsPanel extends ConsumerStatefulWidget {
  const ViewerAccessibilityTagsPanel({
    super.key,
    required this.handoff,
  });

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerAccessibilityTagsPanel> createState() =>
      _ViewerAccessibilityTagsPanelState();
}

class _ViewerAccessibilityTagsPanelState
    extends ConsumerState<ViewerAccessibilityTagsPanel> {
  final _langCtrl = TextEditingController(text: 'en-US');
  final _service = PdfAccessibilityTagsService();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  PdfAccessibilityStructureInfo? _info;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _langCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final render = ref.read(pdfRenderPortProvider);
      final plain = await render.extractPlainText(
        widget.handoff.file,
        password: widget.handoff.password,
      );
      final lines = plain
          .split(RegExp(r'\r?\n'))
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final info = await _service.inspect(
        inputPath: widget.handoff.file.path,
        password: widget.handoff.password,
        readingOrderLines: lines,
      );
      if (!mounted) return;
      if (info.documentLanguage != null && info.documentLanguage!.isNotEmpty) {
        _langCtrl.text = info.documentLanguage!;
      }
      setState(() {
        _info = info;
        _loading = false;
      });
    } on DocumentStudioError catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not inspect accessibility structure.';
        });
      }
    }
  }

  Future<void> _applyLanguage() async {
    final lang = _langCtrl.text.trim();
    if (lang.isEmpty) {
      setState(() => _error = 'Enter a document language (e.g. en-US).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session == null) {
        setState(() => _error = 'No open document session.');
        return;
      }
      final temp = await ref.read(fileStorageProvider).createTempFile(
            prefix: 'a11y_lang_',
            suffix: '.pdf',
          );
      await _service.setLanguageAndMarked(
        inputPath: widget.handoff.file.path,
        outputPath: temp,
        languageTag: lang,
        password: widget.handoff.password,
        markAsMarked: true,
      );
      final bytes = await File(temp).readAsBytes();
      try {
        await File(temp).delete();
      } catch (_) {}
      if (!mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage:
            'Document language set to $lang; MarkInfo /Marked written. '
            'This is not PDF/UA certification.',
      );
      await _load();
    } on DocumentStudioError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update language.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = _info;
    return ListView(
      padding: const EdgeInsets.all(DsSpacing.md),
      children: [
        Text(
          'Inspect catalog language and tagging flags. Setting language writes '
          '/Lang and /MarkInfo /Marked via qpdf — not a full tag tree or PDF/UA.',
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
        ),
        const SizedBox(height: DsSpacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (info != null) ...[
          _row(theme, 'Document language', info.documentLanguage ?? '(not set)'),
          _row(
            theme,
            'Tagged claim',
            info.hasStructTreeRoot
                ? 'Has /StructTreeRoot'
                : info.markInfoMarked == true
                    ? '/MarkInfo /Marked true (no StructTreeRoot)'
                    : 'Not tagged',
          ),
          if (!info.hasStructTreeRoot) ...[
            const SizedBox(height: DsSpacing.sm),
            Text(
              'This file has no tag tree yet. Image alternative text cannot be '
              'saved into structure elements until a real /StructTreeRoot exists.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            ),
          ],
          const SizedBox(height: DsSpacing.md),
          TextField(
            controller: _langCtrl,
            enabled: !_busy,
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Document language (BCP 47)',
              labelStyle: TextStyle(fontSize: 13),
              hintText: 'en-US',
              isDense: true,
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          DsPrimaryButton(
            label: _busy ? 'Saving…' : 'Set language & Marked',
            icon: Icons.translate_outlined,
            onPressed: _busy ? null : _applyLanguage,
          ),
          const SizedBox(height: DsSpacing.lg),
          Text(
            'Reading order (text lines)',
            style: theme.textTheme.titleSmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.xs),
          Text(
            'Page-order plain text from the text layer — not a structure-tree walk.',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.sm),
          if (info.readingOrderLines.isEmpty)
            Text(
              'No extractable text lines.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
            )
          else
            for (var i = 0;
                i < info.readingOrderLines.length.clamp(0, 200);
                i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Text('${i + 1}', style: theme.textTheme.labelSmall),
                title: Text(
                  info.readingOrderLines[i],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
        ],
        if (_error != null) ...[
          const SizedBox(height: DsSpacing.sm),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFE4002B),
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: DsSpacing.sm),
        TextButton(
          onPressed: _busy || _loading ? null : _load,
          child: const Text('Refresh'),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
