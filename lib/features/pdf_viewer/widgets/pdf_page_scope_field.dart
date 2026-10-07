import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:flutter/material.dart';

const _defaultScopeLabels = <PdfPageScopeKind, String>{
  PdfPageScopeKind.thisPage: 'This page',
  PdfPageScopeKind.selectedPages: 'Selected',
  PdfPageScopeKind.allPages: 'All',
  PdfPageScopeKind.range: 'Range',
};

/// Shared page scope control for viewer tool panels.
///
/// Shows a segmented control when there is room and falls back to wrapping
/// chips in narrow panels / bottom sheets so it never overflows.
class PdfPageScopeField extends StatefulWidget {
  const PdfPageScopeField({
    super.key,
    required this.kind,
    required this.onKindChanged,
    required this.rangeExpression,
    required this.onRangeExpressionChanged,
    this.selectedPageCount = 0,
    this.rangeError,
    this.kinds = PdfPageScopeKind.values,
    this.labels = const {},
    this.title = 'Pages',
    this.rangeHint = '1-3, 5, 8-',
    this.enabled = true,
  });

  final PdfPageScopeKind kind;
  final ValueChanged<PdfPageScopeKind> onKindChanged;
  final String rangeExpression;
  final ValueChanged<String> onRangeExpressionChanged;
  final int selectedPageCount;
  final String? rangeError;

  /// Which scopes to offer, in order.
  final List<PdfPageScopeKind> kinds;

  /// Label overrides (e.g. `{thisPage: 'Current'}`).
  final Map<PdfPageScopeKind, String> labels;

  /// Section title; null hides it.
  final String? title;
  final String rangeHint;
  final bool enabled;

  @override
  State<PdfPageScopeField> createState() => _PdfPageScopeFieldState();
}

class _PdfPageScopeFieldState extends State<PdfPageScopeField> {
  late TextEditingController _rangeController;

  @override
  void initState() {
    super.initState();
    _rangeController = TextEditingController(text: widget.rangeExpression);
  }

  @override
  void didUpdateWidget(covariant PdfPageScopeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rangeExpression != widget.rangeExpression &&
        _rangeController.text != widget.rangeExpression) {
      _rangeController.text = widget.rangeExpression;
    }
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  String _label(PdfPageScopeKind k) =>
      widget.labels[k] ?? _defaultScopeLabels[k]!;

  void _select(PdfPageScopeKind k) {
    if (widget.enabled && k != widget.kind) widget.onKindChanged(k);
  }

  Widget _selector(BuildContext context, double maxWidth) {
    final kinds = widget.kinds;
    final labelWidth = kinds.fold<double>(
      0,
      (sum, k) => sum + _label(k).length * 7.5 + 28,
    );
    if (labelWidth <= maxWidth) {
      return SegmentedButton<PdfPageScopeKind>(
        key: const Key('pdf_page_scope_kind'),
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          for (final k in kinds)
            ButtonSegment(
              value: k,
              label: Text(
                _label(k),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
        ],
        selected: {widget.kind},
        onSelectionChanged: widget.enabled
            ? (next) {
                if (next.isNotEmpty) _select(next.first);
              }
            : null,
      );
    }
    return Wrap(
      key: const Key('pdf_page_scope_kind'),
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final k in kinds)
          ChoiceChip(
            label: Text(_label(k), style: const TextStyle(fontSize: 12.5)),
            selected: widget.kind == k,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            selectedColor: DsColors.primary.withValues(alpha: 0.14),
            onSelected: widget.enabled ? (_) => _select(k) : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: DsSpacing.xs),
        ],
        LayoutBuilder(builder: (context, c) => _selector(context, c.maxWidth)),
        if (widget.kind == PdfPageScopeKind.selectedPages) ...[
          const SizedBox(height: DsSpacing.xs),
          Text(
            widget.selectedPageCount == 0
                ? 'No thumbnail selection yet.'
                : '${widget.selectedPageCount} page(s) selected in sidebar.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (widget.kind == PdfPageScopeKind.range) ...[
          const SizedBox(height: DsSpacing.sm),
          TextField(
            key: const Key('pdf_page_scope_range'),
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: 'Range',
              hintText: widget.rangeHint,
              errorText: widget.rangeError,
              isDense: true,
            ),
            controller: _rangeController,
            onChanged: widget.onRangeExpressionChanged,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: [
              for (final preset in const ['odd', 'even'])
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    preset == 'odd' ? 'Odd pages' : 'Even pages',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onPressed: widget.enabled
                      ? () {
                          _rangeController.text = preset;
                          widget.onRangeExpressionChanged(preset);
                        }
                      : null,
                ),
            ],
          ),
        ],
      ],
    );
  }
}
