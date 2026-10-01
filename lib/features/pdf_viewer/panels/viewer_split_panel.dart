import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_merge_split_apply.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum _SplitMode {
  everyN('Every N pages'),
  afterPages('After pages'),
  ranges('Custom ranges'),
  oddEven('Odd / even'),
  eachPage('Each page');

  const _SplitMode(this.label);
  final String label;
}

/// Split the open PDF by the ranges set here.
///
/// A split is several files, so the result is written beside the original
/// (or into a folder the user picks when that directory is not writable).
/// The open document and its source file are not replaced. Save / Ctrl+S
/// still writes the source.
class ViewerSplitPanel extends ConsumerStatefulWidget {
  const ViewerSplitPanel({
    super.key,
    required this.handoff,
    this.pageCount,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerSplitPanel> createState() => _ViewerSplitPanelState();
}

class _ViewerSplitPanelState extends ConsumerState<ViewerSplitPanel> {
  _SplitMode _mode = _SplitMode.everyN;
  final _everyN = TextEditingController(text: '1');
  final _after = TextEditingController();
  final _ranges = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _everyN.dispose();
    _after.dispose();
    _ranges.dispose();
    super.dispose();
  }

  /// Resulting files as 1-based page lists, or an error message.
  (List<List<int>>, String?) _plan() {
    final total = widget.pageCount ?? 0;
    if (total < 1) return (const [], 'Page count not ready yet.');
    List<int> span(int a, int b) => [for (var i = a; i <= b; i++) i];
    switch (_mode) {
      case _SplitMode.everyN:
        final n = int.tryParse(_everyN.text.trim());
        if (n == null || n < 1) return (const [], 'Enter a number of pages.');
        return (
          [
            for (var s = 1; s <= total; s += n)
              span(s, (s + n - 1).clamp(1, total)),
          ],
          null,
        );
      case _SplitMode.eachPage:
        return ([for (var i = 1; i <= total; i++) [i]], null);
      case _SplitMode.oddEven:
        if (total < 2) return (const [], 'Needs at least two pages.');
        return (
          [
            [for (var i = 1; i <= total; i += 2) i],
            [for (var i = 2; i <= total; i += 2) i],
          ],
          null,
        );
      case _SplitMode.afterPages:
        final cuts = <int>{};
        for (final raw in _after.text.split(RegExp(r'[,;\s]+'))) {
          if (raw.isEmpty) continue;
          final v = int.tryParse(raw);
          if (v == null || v < 1 || v >= total) {
            return (const [], 'Split points must be between 1 and ${total - 1}.');
          }
          cuts.add(v);
        }
        if (cuts.isEmpty) return (const [], 'Enter pages to split after, e.g. 3, 7.');
        final sorted = cuts.toList()..sort();
        final parts = <List<int>>[];
        var start = 1;
        for (final c in sorted) {
          parts.add(span(start, c));
          start = c + 1;
        }
        parts.add(span(start, total));
        return (parts, null);
      case _SplitMode.ranges:
        final groups = _ranges.text
            .split(RegExp(r'[,;\n]'))
            .map((g) => g.trim())
            .where((g) => g.isNotEmpty)
            .toList();
        if (groups.isEmpty) {
          return (const [], 'Enter ranges, e.g. 1-3, 4-8, 9-');
        }
        final parts = <List<int>>[];
        for (final g in groups) {
          final r = parsePdfPageRangeExpression(g, total);
          if (!r.isOk) return (const [], r.error);
          parts.add(r.pages!.toList()..sort());
        }
        return (parts, null);
    }
  }

  Future<void> _split() async {
    final (plan, error) = _plan();
    if (error != null || plan.isEmpty) {
      _snack(error ?? 'Nothing to split.');
      return;
    }
    setState(() => _busy = true);
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    final handoffPath = widget.handoff.file.path;
    try {
      final service = ref.read(pageOrganizeServiceProvider);
      final passwords = widget.handoff.password != null
          ? {handoffPath: widget.handoff.password!}
          : null;
      final stem = p.basenameWithoutExtension(widget.handoff.file.displayName);
      final parts = await service.splitByRangesToTemp(
        input: widget.handoff.file,
        rangesPages1Based: plan,
        namePrefix: _mode == _SplitMode.oddEven ? '${stem}_odd_even' : stem,
        passwordsByPath: passwords,
      );
      try {
        final saved = await writeSplitPartsWithoutClobberingSource(
          storage: ref.read(fileStorageProvider),
          tempParts: parts,
          namePrefix: _mode == _SplitMode.oddEven ? '${stem}_odd_even' : stem,
          preferredDirectory: splitOutputDirectoryForOpenDocument(
            session: session,
            handoffPath: handoffPath,
          ),
          forbiddenPaths: splitForbiddenPaths(
            session: session,
            handoffPath: handoffPath,
          ),
        );
        if (!mounted || saved.isEmpty) return;
        final folder = p.dirname(saved.first.path);
        _snack(
          'Wrote ${saved.length} file${saved.length == 1 ? '' : 's'} in $folder. '
          'The open document was not changed.',
        );
      } finally {
        if (parts.isNotEmpty) {
          try {
            await Directory(p.dirname(parts.first.path)).delete(recursive: true);
          } catch (_) {}
        }
      }
    } on DocumentStudioError catch (e) {
      if (mounted) _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _input(TextEditingController c, String label, String hint,
      {bool digitsOnly = false}) {
    return TextField(
      controller: c,
      enabled: !_busy,
      keyboardType: digitsOnly ? TextInputType.number : TextInputType.text,
      inputFormatters:
          digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(labelText: label, hintText: hint, isDense: true),
      onChanged: (_) => setState(() {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (plan, error) = _plan();
    final total = widget.pageCount;

    final fileCount = plan.length;
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_split_apply'),
      primaryLabel: _busy ? 'Splitting…' : 'Split',
      primaryIcon: Icons.call_split,
      primaryEnabled: !_busy && error == null && plan.isNotEmpty,
      primaryBusy: _busy,
      onPrimary: _busy || error != null || plan.isEmpty ? null : _split,
      notice: error == null && fileCount > 0
          ? Text(
              '$fileCount file${fileCount == 1 ? '' : 's'}. The open document stays as it is.',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            )
          : null,
      children: [
          Text('Split method', style: theme.textTheme.labelLarge),
          const SizedBox(height: DsSpacing.xs),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in _SplitMode.values)
                ChoiceChip(
                  label: Text(m.label, style: const TextStyle(fontSize: 12.5)),
                  selected: _mode == m,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  selectedColor: DsColors.primary.withValues(alpha: 0.14),
                  onSelected: _busy ? null : (_) => setState(() => _mode = m),
                ),
            ],
          ),
          const SizedBox(height: DsSpacing.md),
          switch (_mode) {
            _SplitMode.everyN =>
              _input(_everyN, 'Pages per file', '1', digitsOnly: true),
            _SplitMode.afterPages =>
              _input(_after, 'Split after pages', '3, 7'),
            _SplitMode.ranges => _input(
                _ranges, 'One file per range', '1-3, 4-8, 9-  (or odd; even)'),
            _SplitMode.oddEven => Text(
                'Two files: odd pages (1, 3, 5…) and even pages (2, 4, 6…).',
                style: theme.textTheme.bodySmall,
              ),
            _SplitMode.eachPage => Text(
                'One file for every page${total == null ? '' : ' ($total files)'}.',
                style: theme.textTheme.bodySmall,
              ),
          },
          const SizedBox(height: DsSpacing.md),
          _SplitPreview(plan: plan, error: error),
        ],
    );
  }
}

class _SplitPreview extends StatelessWidget {
  const _SplitPreview({required this.plan, required this.error});

  final List<List<int>> plan;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (error != null) {
      return Text(
        error!,
        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
      );
    }
    const maxShown = 12;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Result', style: theme.textTheme.labelLarge),
        const SizedBox(height: DsSpacing.xs),
        for (var i = 0; i < plan.length && i < maxShown; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.picture_as_pdf_rounded,
                    size: 16, color: DsColors.primary),
                const SizedBox(width: 6),
                Text('File ${i + 1}', style: theme.textTheme.bodySmall),
                const Spacer(),
                Flexible(
                  child: Text(
                    '${plan[i].length == 1 ? 'page' : 'pages'} '
                    '${formatPdfPageRange(plan[i])}',
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (plan.length > maxShown)
          Text('…and ${plan.length - maxShown} more',
              style: theme.textTheme.bodySmall),
      ],
    );
  }
}
