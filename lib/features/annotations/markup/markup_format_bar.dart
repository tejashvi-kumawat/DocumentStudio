import 'dart:math' as math;

import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/material.dart';

/// What the floating format bar is editing.
enum MarkupFormatBarMode { hidden, text, pencil }

/// Text, ink, shapes, and text markup drive the bar. Images and links do not,
/// so their drag targets stay clear.
bool markupObjectUsesFormatBar(MarkupObject o) {
  if (o.locked) return false;
  return o is TextBoxMarkup ||
      o is InkMarkup ||
      o is ShapeMarkup ||
      o is TextMarkupMarkup;
}

bool markupFormatAnchoredToSelection(MarkupEditorController c) {
  if (!c.editMode || c.readOnly) return false;
  return c.selectedObjects.any(markupObjectUsesFormatBar);
}

MarkupFormatBarMode markupFormatBarMode(MarkupEditorController c) {
  if (!c.editMode || c.readOnly) return MarkupFormatBarMode.hidden;
  final driving = c.selectedObjects.where(markupObjectUsesFormatBar);
  if (driving.any((o) => o is TextBoxMarkup)) return MarkupFormatBarMode.text;
  if (driving.any(
    (o) => o is InkMarkup || o is ShapeMarkup || o is TextMarkupMarkup,
  )) {
    return MarkupFormatBarMode.pencil;
  }
  return switch (c.tool) {
    MarkupTool.text || MarkupTool.callout => MarkupFormatBarMode.text,
    MarkupTool.highlight ||
    MarkupTool.underline ||
    MarkupTool.strikeout ||
    MarkupTool.squiggly ||
    MarkupTool.pen ||
    MarkupTool.highlighter => MarkupFormatBarMode.pencil,
    _ when c.tool.isShape => MarkupFormatBarMode.pencil,
    _ => MarkupFormatBarMode.hidden,
  };
}

/// Gap under the floating format bar. Clears the keyboard and the system
/// inset. The open-PDF status strip is gone, so this does not reserve a bar.
double markupFormatDockBottom(BuildContext context) {
  final mq = MediaQuery.of(context);
  final keyboard = mq.viewInsets.bottom;
  final system = mq.padding.bottom;
  return math.max(keyboard, system) + 8;
}

/// Sits just above the page tools while a text or drawing tool is armed and
/// nothing on the page is selected yet.
class MarkupFormatDock extends StatelessWidget {
  const MarkupFormatDock({super.key, required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.previewTick,
        controller.textEditTick,
      ]),
      builder: (context, _) {
        if (markupFormatAnchoredToSelection(controller)) {
          return const SizedBox.shrink();
        }
        if (markupFormatBarMode(controller) == MarkupFormatBarMode.hidden) {
          return const SizedBox.shrink();
        }
        return Align(
          alignment: Alignment.bottomCenter,
          child: MarkupFormatBar(controller: controller),
        );
      },
    );
  }
}

/// Positions [MarkupFormatBar] just above the selected object, clearing the
/// rotate handle. Falls below the object toolbar when the top of the page
/// is too tight.
class MarkupFormatBarAnchor extends StatelessWidget {
  const MarkupFormatBarAnchor({
    super.key,
    required this.controller,
    required this.selection,
    required this.scale,
  });

  final MarkupEditorController controller;
  final List<MarkupObject> selection;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final driving = selection.where(markupObjectUsesFormatBar).toList();
    if (driving.isEmpty) return const SizedBox.shrink();
    var b = driving.first.bounds;
    for (final o in driving.skip(1)) {
      b = b.expandToInclude(o.bounds);
    }
    final screen = Rect.fromLTRB(
      b.left * scale,
      b.top * scale,
      b.right * scale,
      b.bottom * scale,
    );
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _FormatBarLayout(screen),
        child: TextFieldTapRegion(
          child: MarkupFormatBar(controller: controller),
        ),
      ),
    );
  }
}

class _FormatBarLayout extends SingleChildLayoutDelegate {
  _FormatBarLayout(this.target);

  final Rect target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(0, constraints.maxWidth - 8),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    const rotateClearance = 46.0;
    var top = target.top - child.height - rotateClearance;
    if (top < 4) {
      // Below the selection, under the object toolbar.
      top = target.bottom + 58;
    }
    top = top.clamp(4.0, math.max(4.0, size.height - child.height - 4));
    var left = target.center.dx - child.width / 2;
    left = left.clamp(4.0, math.max(4.0, size.width - child.width - 4));
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _FormatBarLayout old) => old.target != target;
}

/// Small floating style bar for the markup editor.
///
/// Text: Helvetica / Times / Courier, size, bold, italic, underline, color,
/// alignment, and line spacing, written with [MarkupEditorController.updateSelected]
/// and [relayoutTextBox]. Drawing tools share the bar for color and stroke
/// width when those fields exist on the editor.
class MarkupFormatBar extends StatelessWidget {
  const MarkupFormatBar({super.key, required this.controller});

  final MarkupEditorController controller;

  static const _lineSpacings = <double>[1.0, 1.15, 1.2, 1.5, 1.8, 2.0];
  static const _highlighterWidths = <double>[6, 9, 12, 16, 22, 30];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.previewTick,
        controller.textEditTick,
      ]),
      builder: (context, _) {
        final mode = markupFormatBarMode(controller);
        if (mode == MarkupFormatBarMode.hidden) {
          return const SizedBox.shrink();
        }
        final theme = Theme.of(context);
        final cs = theme.colorScheme;
        final controls = mode == MarkupFormatBarMode.text
            ? _textControls(context)
            : _pencilControls(context);
        return Material(
          key: const Key('markup_format_bar'),
          elevation: 6,
          shadowColor: const Color(0x33000000),
          color: cs.surfaceContainerHigh.withValues(alpha: 0.98),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.7)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: IconTheme.merge(
              data: IconThemeData(size: 18, color: cs.onSurface),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: controls,
              ),
            ),
          ),
        );
      },
    );
  }

  TextBoxMarkup? get _text {
    for (final o in controller.selectedObjects) {
      if (o is TextBoxMarkup && !o.locked) return o;
    }
    return null;
  }

  MarkupObject? get _pencil {
    for (final o in controller.selectedObjects) {
      if (o is InkMarkup || o is ShapeMarkup || o is TextMarkupMarkup) {
        if (!o.locked) return o;
      }
    }
    return null;
  }

  void _restyle(
    TextBoxMarkup Function(TextBoxMarkup t) change,
    VoidCallback styleOnly,
  ) {
    final c = controller;
    final has = c.selectedObjects.any((o) => o is TextBoxMarkup && !o.locked);
    if (!has) {
      c.updateStyle(styleOnly);
      return;
    }
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

  List<Widget> _textControls(BuildContext context) {
    final c = controller;
    final t = _text;
    final family = t?.fontFamily ?? c.fontFamily;
    final size = t?.fontSize ?? c.fontSize;
    final bold = t?.bold ?? c.bold;
    final italic = t?.italic ?? c.italic;
    final underline = t?.underline ?? c.underline;
    final color = t?.textColor ?? c.textColor;
    final align = t?.align ?? c.textAlign;
    final leading = t?.lineHeight ?? c.lineHeight;
    final sizes = <double>{...kMarkupFontSizes, size}.toList()..sort();
    final leadings = <double>{
      ..._lineSpacings,
      double.parse(leading.toStringAsFixed(2)),
    }.toList()..sort();

    return [
      _Menu<MarkupFontFamily>(
        key: const Key('markup_format_bar_font'),
        tooltip: 'Font',
        value: family,
        values: MarkupFontFamily.values,
        label: _pdfFontName(family),
        labelOf: _pdfFontName,
        itemStyle: (f) => TextStyle(fontFamily: f.flutterFamily),
        onSelected: (f) =>
            _restyle((o) => o.copyWith(fontFamily: f), () => c.fontFamily = f),
      ),
      _Menu<double>(
        key: const Key('markup_format_bar_size'),
        tooltip: 'Size',
        value: _nearest(sizes, size),
        values: sizes,
        label: _num(size),
        labelOf: (v) => '${_num(v)} pt',
        onSelected: (v) =>
            _restyle((o) => o.copyWith(fontSize: v), () => c.fontSize = v),
      ),
      _Toggle(
        key: const Key('markup_format_bar_bold'),
        icon: Icons.format_bold,
        tooltip: 'Bold',
        selected: bold,
        onPressed: () =>
            _restyle((o) => o.copyWith(bold: !o.bold), () => c.bold = !c.bold),
      ),
      _Toggle(
        key: const Key('markup_format_bar_italic'),
        icon: Icons.format_italic,
        tooltip: 'Italic',
        selected: italic,
        onPressed: () => _restyle(
          (o) => o.copyWith(italic: !o.italic),
          () => c.italic = !c.italic,
        ),
      ),
      _Toggle(
        key: const Key('markup_format_bar_underline'),
        icon: Icons.format_underline,
        tooltip: 'Underline',
        selected: underline,
        onPressed: () => _restyle(
          (o) => o.copyWith(underline: !o.underline),
          () => c.underline = !c.underline,
        ),
      ),
      _ColorMenu(
        key: const Key('markup_format_bar_color'),
        tooltip: 'Color',
        color: color,
        palette: kMarkupPalette,
        onPick: (argb) => _restyle(
          (o) => o.copyWith(textColor: argb),
          () => c.textColor = argb,
        ),
      ),
      _Toggle(
        key: const Key('markup_format_bar_align_left'),
        icon: Icons.format_align_left,
        tooltip: 'Align left',
        selected: align == MarkupTextAlign.left,
        onPressed: () => _restyle(
          (o) => o.copyWith(align: MarkupTextAlign.left),
          () => c.textAlign = MarkupTextAlign.left,
        ),
      ),
      _Toggle(
        key: const Key('markup_format_bar_align_center'),
        icon: Icons.format_align_center,
        tooltip: 'Align center',
        selected: align == MarkupTextAlign.center,
        onPressed: () => _restyle(
          (o) => o.copyWith(align: MarkupTextAlign.center),
          () => c.textAlign = MarkupTextAlign.center,
        ),
      ),
      _Toggle(
        key: const Key('markup_format_bar_align_right'),
        icon: Icons.format_align_right,
        tooltip: 'Align right',
        selected: align == MarkupTextAlign.right,
        onPressed: () => _restyle(
          (o) => o.copyWith(align: MarkupTextAlign.right),
          () => c.textAlign = MarkupTextAlign.right,
        ),
      ),
      _Menu<double>(
        key: const Key('markup_format_bar_line_spacing'),
        tooltip: 'Line spacing',
        value: _nearest(leadings, leading),
        values: leadings,
        label: leading.toStringAsFixed(2),
        icon: Icons.format_line_spacing,
        labelOf: (v) => v.toStringAsFixed(2),
        onSelected: (v) =>
            _restyle((o) => o.copyWith(lineHeight: v), () => c.lineHeight = v),
      ),
    ];
  }

  bool get _showWidth {
    final o = _pencil;
    if (o is InkMarkup || o is ShapeMarkup) return true;
    if (o != null) return false;
    final tool = controller.tool;
    return tool == MarkupTool.pen ||
        tool == MarkupTool.highlighter ||
        tool.isShape;
  }

  double get _width {
    final o = _pencil;
    if (o is InkMarkup) return o.strokeWidth;
    if (o is ShapeMarkup) return o.strokeWidth;
    if (controller.tool == MarkupTool.highlighter) {
      return controller.highlighterWidth;
    }
    if (controller.tool == MarkupTool.pen) return controller.penWidth;
    return controller.strokeWidth;
  }

  List<double> get _widths {
    final o = _pencil;
    final hl =
        controller.tool == MarkupTool.highlighter ||
        (o is InkMarkup && o.highlighter);
    final base = hl ? _highlighterWidths : kMarkupStrokeWidths;
    return <double>{...base, _width}.toList()..sort();
  }

  int get _pencilColor {
    final o = _pencil;
    if (o != null) return o.color;
    return controller.activeColor;
  }

  List<int> get _palette {
    final o = _pencil;
    if (o is TextMarkupMarkup && o.kind == TextMarkupKind.highlight) {
      return kHighlightPalette;
    }
    if (o is InkMarkup && o.highlighter) return kHighlightPalette;
    final tool = controller.tool;
    if (o == null &&
        (tool == MarkupTool.highlight || tool == MarkupTool.highlighter)) {
      return kHighlightPalette;
    }
    return kMarkupPalette;
  }

  void _setColor(int argb) {
    final c = controller;
    final has = _pencil != null;
    if (has) {
      c.updateSelected((o) {
        if (o.locked) return o;
        if (o is InkMarkup || o is ShapeMarkup || o is TextMarkupMarkup) {
          return o.recolored(argb);
        }
        return o;
      });
      c.updateStyle(() => _storeColor(argb));
      return;
    }
    c.setActiveColor(argb);
  }

  void _storeColor(int argb) {
    final c = controller;
    final o = _pencil;
    if (o is InkMarkup) {
      if (o.highlighter) {
        c.highlighterColor = argb;
      } else {
        c.penColor = argb;
      }
      return;
    }
    if (o is ShapeMarkup) {
      c.strokeColor = argb;
      return;
    }
    if (o is TextMarkupMarkup) {
      switch (o.kind) {
        case TextMarkupKind.highlight:
          c.highlightColor = argb;
        case TextMarkupKind.underline:
          c.underlineColor = argb;
        case TextMarkupKind.strikeout:
          c.strikeColor = argb;
        case TextMarkupKind.squiggly:
          c.squigglyColor = argb;
      }
    }
  }

  void _setWidth(double v) {
    final c = controller;
    if (_pencil != null) {
      c.updateSelected(
        (o) => switch (o) {
          ShapeMarkup() => o.copyWith(strokeWidth: v),
          InkMarkup() => o.copyWith(strokeWidth: v),
          _ => o,
        },
      );
    }
    c.updateStyle(() {
      final o = _pencil;
      if ((o is InkMarkup && o.highlighter) ||
          (o == null && c.tool == MarkupTool.highlighter)) {
        c.highlighterWidth = v;
      } else if (o is InkMarkup || c.tool == MarkupTool.pen) {
        c.penWidth = v;
      } else {
        c.strokeWidth = v;
      }
    });
  }

  List<Widget> _pencilControls(BuildContext context) {
    final widths = _widths;
    return [
      _ColorMenu(
        key: const Key('markup_format_bar_color'),
        tooltip: 'Color',
        color: _pencilColor,
        palette: _palette,
        onPick: _setColor,
      ),
      if (_showWidth)
        _Menu<double>(
          key: const Key('markup_format_bar_stroke'),
          tooltip: 'Stroke width',
          value: _nearest(widths, _width),
          values: widths,
          label: _num(_width),
          icon: Icons.line_weight,
          labelOf: (v) => '${_num(v)} pt',
          onSelected: _setWidth,
        ),
    ];
  }
}

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

class _Menu<T> extends StatelessWidget {
  const _Menu({
    super.key,
    required this.tooltip,
    required this.value,
    required this.values,
    required this.label,
    required this.labelOf,
    required this.onSelected,
    this.icon,
    this.itemStyle,
  });

  final String tooltip;
  final T value;
  final List<T> values;
  final String label;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;
  final IconData? icon;
  final TextStyle Function(T value)? itemStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: value,
      padding: EdgeInsets.zero,
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final v in values)
          PopupMenuItem(
            value: v,
            child: Text(labelOf(v), style: itemStyle?.call(v)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontFamily: itemStyle?.call(value).fontFamily,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
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
    return IconButton(
      visualDensity: VisualDensity.compact,
      tooltip: tooltip,
      isSelected: selected,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      style: IconButton.styleFrom(
        backgroundColor: selected ? cs.primary.withValues(alpha: 0.14) : null,
        foregroundColor: selected ? cs.primary : cs.onSurface,
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

class _ColorMenu extends StatelessWidget {
  const _ColorMenu({
    super.key,
    required this.tooltip,
    required this.color,
    required this.palette,
    required this.onPick,
  });

  final String tooltip;
  final int color;
  final List<int> palette;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<int>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onSelected: onPick,
      itemBuilder: (context) => [
        for (final argb in palette)
          PopupMenuItem(
            value: argb,
            child: Row(
              children: [
                _SwatchDot(argb: argb, selected: argb == color),
                const SizedBox(width: 12),
                if (argb == color)
                  Icon(Icons.check, size: 16, color: cs.primary),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Color(color),
            shape: BoxShape.circle,
            border: Border.all(color: cs.outline),
          ),
        ),
      ),
    );
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({required this.argb, required this.selected});

  final int argb;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: Color(argb),
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
    );
  }
}
