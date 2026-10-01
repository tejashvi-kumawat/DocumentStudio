import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/material.dart';

/// Compact text format controls for the viewer tool row.
///
/// Writes the markup editor's armed style (used by the next text box) and,
/// when a text box is selected, the same properties on that object.
class PdfViewerTextFormatStrip extends StatelessWidget {
  const PdfViewerTextFormatStrip({super.key, required this.controller});

  final MarkupEditorController controller;

  TextBoxMarkup? get _selectedText {
    for (final o in controller.selectedObjects) {
      if (o is TextBoxMarkup && !o.locked) return o;
    }
    return null;
  }

  void _apply({
    required void Function() arm,
    required TextBoxMarkup Function(TextBoxMarkup t) change,
  }) {
    final selected = _selectedText;
    if (selected != null) {
      controller.updateSelected((o) {
        if (o is! TextBoxMarkup || o.locked) return o;
        return relayoutTextBox(change(o));
      });
    }
    controller.updateStyle(arm);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selected = _selectedText;
        final family = selected?.fontFamily ?? controller.fontFamily;
        final size = selected?.fontSize ?? controller.fontSize;
        final bold = selected?.bold ?? controller.bold;
        final italic = selected?.italic ?? controller.italic;
        final color = selected?.textColor ?? controller.textColor;
        final align = selected?.align ?? controller.textAlign;
        final sizes = <double>{...kMarkupFontSizes, size}.toList()..sort();

        return SizedBox(
          key: const Key('pdf_viewer_text_format_strip'),
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 108,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<MarkupFontFamily>(
                    key: const Key('pdf_viewer_format_font'),
                    isDense: true,
                    isExpanded: true,
                    value: family,
                    items: [
                      for (final f in MarkupFontFamily.values)
                        DropdownMenuItem(
                          value: f,
                          child: Text(
                            f.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: f.flutterFamily),
                          ),
                        ),
                    ],
                    onChanged: (f) {
                      if (f == null) return;
                      _apply(
                        arm: () => controller.fontFamily = f,
                        change: (t) => t.copyWith(fontFamily: f),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 64,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    key: const Key('pdf_viewer_format_size'),
                    isDense: true,
                    isExpanded: true,
                    value: _nearest(sizes, size),
                    items: [
                      for (final s in sizes)
                        DropdownMenuItem(
                          value: s,
                          child: Text(_num(s)),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      _apply(
                        arm: () => controller.fontSize = v,
                        change: (t) => t.copyWith(fontSize: v),
                      );
                    },
                  ),
                ),
              ),
              _Toggle(
                key: const Key('pdf_viewer_format_bold'),
                icon: Icons.format_bold,
                tooltip: 'Bold',
                selected: bold,
                onPressed: () {
                  final next = !bold;
                  _apply(
                    arm: () => controller.bold = next,
                    change: (t) => t.copyWith(bold: next),
                  );
                },
              ),
              _Toggle(
                key: const Key('pdf_viewer_format_italic'),
                icon: Icons.format_italic,
                tooltip: 'Italic',
                selected: italic,
                onPressed: () {
                  final next = !italic;
                  _apply(
                    arm: () => controller.italic = next,
                    change: (t) => t.copyWith(italic: next),
                  );
                },
              ),
              _ColorButton(
                color: color,
                onPick: (argb) {
                  _apply(
                    arm: () => controller.textColor = argb,
                    change: (t) => t.copyWith(textColor: argb),
                  );
                },
              ),
              _Toggle(
                key: const Key('pdf_viewer_format_align_left'),
                icon: Icons.format_align_left,
                tooltip: 'Align left',
                selected: align == MarkupTextAlign.left,
                onPressed: () => _apply(
                  arm: () => controller.textAlign = MarkupTextAlign.left,
                  change: (t) => t.copyWith(align: MarkupTextAlign.left),
                ),
              ),
              _Toggle(
                key: const Key('pdf_viewer_format_align_center'),
                icon: Icons.format_align_center,
                tooltip: 'Align center',
                selected: align == MarkupTextAlign.center,
                onPressed: () => _apply(
                  arm: () => controller.textAlign = MarkupTextAlign.center,
                  change: (t) => t.copyWith(align: MarkupTextAlign.center),
                ),
              ),
              _Toggle(
                key: const Key('pdf_viewer_format_align_right'),
                icon: Icons.format_align_right,
                tooltip: 'Align right',
                selected: align == MarkupTextAlign.right,
                onPressed: () => _apply(
                  arm: () => controller.textAlign = MarkupTextAlign.right,
                  change: (t) => t.copyWith(align: MarkupTextAlign.right),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

double _nearest(List<double> sizes, double size) {
  var best = sizes.first;
  var bestDelta = (best - size).abs();
  for (final s in sizes) {
    final d = (s - size).abs();
    if (d < bestDelta) {
      best = s;
      bestDelta = d;
    }
  }
  return best;
}

String _num(double v) {
  if (v == v.roundToDouble()) return v.round().toString();
  return v.toString();
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
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      style: IconButton.styleFrom(
        minimumSize: const Size(36, 36),
        maximumSize: const Size(36, 36),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor: selected
            ? DsColors.primary
            : Theme.of(context).colorScheme.onSurface,
        backgroundColor: selected
            ? DsColors.primary.withValues(alpha: 0.12)
            : Colors.transparent,
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({required this.color, required this.onPick});

  final int color;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final argb in kMarkupPalette)
          MenuItemButton(
            leadingIcon: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Color(argb),
                shape: BoxShape.circle,
                border: Border.all(
                  color: argb == color ? DsColors.primary : DsColors.borderLight,
                  width: argb == color ? 2 : 1,
                ),
              ),
            ),
            onPressed: () => onPick(argb),
            child: Text(
              '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
            ),
          ),
      ],
      builder: (context, menu, _) {
        return IconButton(
          key: const Key('pdf_viewer_format_color'),
          tooltip: 'Text color',
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          style: IconButton.styleFrom(
            minimumSize: const Size(36, 36),
            maximumSize: const Size(36, 36),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Color(color),
              shape: BoxShape.circle,
              border: Border.all(color: DsColors.borderLight),
            ),
          ),
        );
      },
    );
  }
}
