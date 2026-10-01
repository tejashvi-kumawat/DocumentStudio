import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:flutter/material.dart';

/// Acrobat-style FORMAT column for the selected text box.
///
/// Every control writes a property the PDF markup writer already draws:
/// standard-14 font, size, color, bold, italic, underline, alignment, and
/// line spacing. The on-screen family is the metric-matched face for that
/// PDF font (Helvetica, Times, or Courier).
class MarkupFormatPanel extends StatelessWidget {
  const MarkupFormatPanel({super.key, required this.controller});

  final MarkupEditorController controller;

  static const _lineSpacings = <double>[1.0, 1.15, 1.2, 1.5, 1.8, 2.0];

  TextBoxMarkup? get _text {
    for (final o in controller.selectedObjects) {
      if (o is TextBoxMarkup && !o.locked) return o;
    }
    return null;
  }

  void _restyle(TextBoxMarkup Function(TextBoxMarkup t) change) {
    final c = controller;
    c.updateSelected((o) {
      if (o is! TextBoxMarkup || o.locked) return o;
      return relayoutTextBox(change(o));
    });
    final t = _text;
    if (t == null) return;
    c.updateStyle(() {
      c.fontFamily = t.fontFamily;
      c.fontSize = t.fontSize;
      c.bold = t.bold;
      c.italic = t.italic;
      c.underline = t.underline;
      c.textColor = t.textColor;
      c.textAlign = t.align;
      c.lineHeight = t.lineHeight;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _text;
    if (t == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sizes = <double>{...kMarkupFontSizes, t.fontSize}.toList()..sort();
    final leadings = <double>{
      ..._lineSpacings,
      double.parse(t.lineHeight.toStringAsFixed(2)),
    }.toList()..sort();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        key: const Key('markup_format_panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PdfOptionHeading('Text', first: true),
          Row(
            children: [
              Expanded(
                child: _FieldLabel(
                  label: 'Font',
                  child: DropdownButton<MarkupFontFamily>(
                    key: const Key('markup_format_font'),
                    isExpanded: true,
                    value: t.fontFamily,
                    items: [
                      for (final f in MarkupFontFamily.values)
                        DropdownMenuItem(
                          value: f,
                          child: Text(
                            _pdfFontName(f),
                            style: TextStyle(fontFamily: f.flutterFamily),
                          ),
                        ),
                    ],
                    onChanged: (f) {
                      if (f != null) _restyle((o) => o.copyWith(fontFamily: f));
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: _FieldLabel(
                  label: 'Size',
                  child: DropdownButton<double>(
                    key: const Key('markup_format_size'),
                    isExpanded: true,
                    value: _nearest(sizes, t.fontSize),
                    items: [
                      for (final s in sizes)
                        DropdownMenuItem(value: s, child: Text(_num(s))),
                    ],
                    onChanged: (v) {
                      if (v != null) _restyle((o) => o.copyWith(fontSize: v));
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Toggle(
                key: const Key('markup_format_bold'),
                icon: Icons.format_bold,
                tooltip: 'Bold',
                selected: t.bold,
                onPressed: () => _restyle((o) => o.copyWith(bold: !o.bold)),
              ),
              _Toggle(
                key: const Key('markup_format_italic'),
                icon: Icons.format_italic,
                tooltip: 'Italic',
                selected: t.italic,
                onPressed: () => _restyle((o) => o.copyWith(italic: !o.italic)),
              ),
              _Toggle(
                key: const Key('markup_format_underline'),
                icon: Icons.format_underline,
                tooltip: 'Underline',
                selected: t.underline,
                onPressed: () =>
                    _restyle((o) => o.copyWith(underline: !o.underline)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PdfTextAlignGroup<MarkupTextAlign>(
            key: const Key('markup_format_align'),
            value: t.align,
            left: MarkupTextAlign.left,
            center: MarkupTextAlign.center,
            right: MarkupTextAlign.right,
            onChanged: (align) => _restyle((o) => o.copyWith(align: align)),
          ),
          const SizedBox(height: 8),
          _FieldLabel(
            label: 'Line spacing',
            child: DropdownButton<double>(
              key: const Key('markup_format_line_spacing'),
              isExpanded: true,
              value: _nearest(leadings, t.lineHeight),
              items: [
                for (final v in leadings)
                  DropdownMenuItem(value: v, child: Text(v.toStringAsFixed(2))),
              ],
              onChanged: (v) {
                if (v != null) _restyle((o) => o.copyWith(lineHeight: v));
              },
            ),
          ),
          const PdfOptionHeading('Appearance'),
          PdfCompactColorPicker<int>(
            colors: kMarkupPalette,
            selected: t.textColor,
            swatch: Color.new,
            onChanged: (argb) {
              if (argb != null) _restyle((o) => o.copyWith(textColor: argb));
            },
          ),
          const SizedBox(height: 4),
          Text(
            'Helvetica, Times, and Courier are embedded as standard PDF fonts.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// PDF BaseFont family the writer can draw. Not the on-screen metric alias.
String _pdfFontName(MarkupFontFamily family) => switch (family) {
  MarkupFontFamily.sans => 'Helvetica',
  MarkupFontFamily.serif => 'Times',
  MarkupFontFamily.mono => 'Courier',
};

double _nearest(List<double> values, double current) {
  var best = values.first;
  var bestD = (best - current).abs();
  for (final v in values.skip(1)) {
    final d = (v - current).abs();
    if (d < bestD) {
      best = v;
      bestD = d;
    }
  }
  return best;
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        child,
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        isSelected: selected,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: selected ? cs.primary.withValues(alpha: 0.14) : null,
          foregroundColor: selected ? cs.primary : cs.onSurface,
        ),
      ),
    );
  }
}
