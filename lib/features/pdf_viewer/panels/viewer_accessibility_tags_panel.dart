import 'package:document_studio/core/pdf/large_doc_policy.dart';
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/pdf/pdf_accessibility_checker.dart';
import 'package:document_studio/infrastructure/pdf/pdf_archive_checker.dart';
import 'package:document_studio/infrastructure/pdf/pdfa/pdfa_converter.dart';
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
  List<A11yFinding> _findings = const [];
  List<A11yFinding> _archive = const [];

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

  Future<void> _runCheck() async {
    try {
      if ((await File(widget.handoff.file.path).length()) >
          LargeDocPolicy.analysisByteLimit) {
        return; // very large file: the structure check is skipped
      }
      final bytes = await File(widget.handoff.file.path).readAsBytes();
      final found = await Isolate.run(() => checkPdfAccessibility(bytes));
      final arch = await Isolate.run(() => checkPdfArchiveReadiness(bytes));
      if (mounted) {
        setState(() {
          _findings = found;
          _archive = arch;
        });
      }
    } catch (_) {}
  }

  Future<void> _fix(A11yFinding f) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null || f.fixId == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await LargeDocPolicy.readBounded(session);
      if (bytes == null) return;
      final title = widget.handoff.file.displayName.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '',
      );
      final out = await Isolate.run(
        () => fixPdfAccessibility(
          bytes,
          fixId: f.fixId!,
          title: title,
          language: _langCtrl.text,
        ),
      );
      if (out == null || !mounted) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: out,
        successMessage: 'Fixed: ${f.title}.',
        silent: true,
      );
      await _runCheck();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  PdfALevel _pdfaLevel = PdfALevel.a2b;

  /// Archive copy: fonts embedded, sRGB output intent, PDF/A metadata.
  Future<void> _convertPdfA() async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) return;
    setState(() => _busy = true);
    try {
      final storage = ref.read(fileStorageProvider);
      final out = await storage.createTempFile(prefix: 'pdfa', suffix: '.pdf');
      final r = await convertToPdfA(
        inputPath: session.file.path,
        outputPath: out,
        level: _pdfaLevel,
        password: session.password,
        title: widget.handoff.file.displayName.replaceFirst(
          RegExp(r'\.pdf$', caseSensitive: false),
          '',
        ),
      );
      if (!mounted) return;
      if (!r.ok) {
        await storage.deleteIfExists(out);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(r.error ?? 'PDF/A conversion failed.')),
        );
        return;
      }
      await commitTempPathToActiveSession(
        ref: ref,
        context: context,
        tempPath: out,
        successMessage: 'Converted to ${_pdfaLevel.label}. Save to keep it.',
      );
      await _runCheck();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    unawaited(_runCheck());
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
        if (_findings.isNotEmpty) ...[
          Text('Accessibility check', style: theme.textTheme.titleSmall),
          const SizedBox(height: DsSpacing.xs),
          for (final f in _findings)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (f.severity) {
                  A11ySeverity.pass => Icons.check_circle,
                  A11ySeverity.warning => Icons.warning_amber_rounded,
                  A11ySeverity.fail => Icons.cancel,
                },
                size: 20,
                color: switch (f.severity) {
                  A11ySeverity.pass => const Color(0xFF059669),
                  A11ySeverity.warning => const Color(0xFFD97706),
                  A11ySeverity.fail => const Color(0xFFDC2626),
                },
              ),
              title: Text(f.title),
              subtitle: Text(f.detail, style: const TextStyle(fontSize: 12)),
              trailing: f.fixId != null && f.severity != A11ySeverity.pass
                  ? TextButton(
                      onPressed: _busy ? null : () => _fix(f),
                      child: const Text('Fix'),
                    )
                  : null,
            ),
          const Divider(height: DsSpacing.lg),
        ],
        if (_archive.isNotEmpty) ...[
          Text('PDF/A archive readiness', style: theme.textTheme.titleSmall),
          const SizedBox(height: DsSpacing.xs),
          for (final f in _archive)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                switch (f.severity) {
                  A11ySeverity.pass => Icons.check_circle,
                  A11ySeverity.warning => Icons.warning_amber_rounded,
                  A11ySeverity.fail => Icons.cancel,
                },
                size: 20,
                color: switch (f.severity) {
                  A11ySeverity.pass => const Color(0xFF059669),
                  A11ySeverity.warning => const Color(0xFFD97706),
                  A11ySeverity.fail => const Color(0xFFDC2626),
                },
              ),
              title: Text(f.title),
              subtitle: Text(f.detail, style: const TextStyle(fontSize: 12)),
            ),
          const SizedBox(height: DsSpacing.xs),
          Row(
            children: [
              DropdownButton<PdfALevel>(
                value: _pdfaLevel,
                isDense: true,
                items: [
                  for (final l in PdfALevel.values)
                    DropdownMenuItem(value: l, child: Text(l.label)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _pdfaLevel = v ?? _pdfaLevel),
              ),
              const SizedBox(width: DsSpacing.sm),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : _convertPdfA,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: Text(_busy ? 'Converting…' : 'Convert to PDF/A'),
                ),
              ),
            ],
          ),
          const Divider(height: DsSpacing.lg),
        ],
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
