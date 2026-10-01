import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:flutter/material.dart';

/// Short heading for a tool-options group (Text, Appearance, Position).
class PdfOptionHeading extends StatelessWidget {
  const PdfOptionHeading(this.title, {super.key, this.first = false});

  final String title;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : DsSpacing.md,
        bottom: DsSpacing.sm,
      ),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// One font menu. Only the standard-14 families a PDF can store:
/// Helvetica, Times, and Courier. Bold stays a separate toggle so the
/// menu does not pretend Cambria or a bold face is its own family.
class PdfStandardFontField extends StatelessWidget {
  const PdfStandardFontField({
    super.key,
    required this.font,
    required this.onChanged,
  });

  final HfFont font;
  final ValueChanged<HfFont>? onChanged;

  static const _families = <(HfFontFamily, String)>[
    (HfFontFamily.sans, 'Helvetica'),
    (HfFontFamily.serif, 'Times'),
    (HfFontFamily.mono, 'Courier'),
  ];

  static HfFont face(HfFontFamily family, {required bool bold}) =>
      HfFont.values.firstWhere((f) => f.family == family && f.bold == bold);

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<HfFontFamily>(
            key: ValueKey(font),
            initialValue: font.family,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Font',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              for (final (family, name) in _families)
                DropdownMenuItem(value: family, child: Text(name)),
            ],
            onChanged: enabled
                ? (family) {
                    if (family == null) return;
                    onChanged!(face(family, bold: font.bold));
                  }
                : null,
          ),
        ),
        const SizedBox(width: DsSpacing.sm),
        IconButton.outlined(
          tooltip: 'Bold',
          isSelected: font.bold,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            minimumSize: const Size(40, 40),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: font.bold ? DsColors.primary : null,
          ),
          onPressed: enabled
              ? () => onChanged!(face(font.family, bold: !font.bold))
              : null,
          icon: const Icon(Icons.format_bold),
        ),
      ],
    );
  }
}

/// Left, center, and right as one segmented control.
class PdfTextAlignGroup<T> extends StatelessWidget {
  const PdfTextAlignGroup({
    super.key,
    required this.value,
    required this.left,
    required this.center,
    required this.right,
    required this.onChanged,
  });

  final T value;
  final T left;
  final T center;
  final T right;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: [
          ButtonSegment(
            value: left,
            icon: const Icon(Icons.format_align_left, size: 18),
            tooltip: 'Align left',
          ),
          ButtonSegment(
            value: center,
            icon: const Icon(Icons.format_align_center, size: 18),
            tooltip: 'Align center',
          ),
          ButtonSegment(
            value: right,
            icon: const Icon(Icons.format_align_right, size: 18),
            tooltip: 'Align right',
          ),
        ],
        selected: {value},
        onSelectionChanged: onChanged == null
            ? null
            : (next) => onChanged!(next.first),
      ),
    );
  }
}

/// Color as one control. A short row of swatches is used only when every
/// swatch fits on a single line (at most eight). Otherwise one button
/// opens the same colors, so they never stack down the options column.
class PdfCompactColorPicker<T> extends StatelessWidget {
  const PdfCompactColorPicker({
    super.key,
    required this.colors,
    required this.selected,
    required this.swatch,
    required this.onChanged,
    this.allowNone = false,
  });

  final List<T> colors;
  final T? selected;
  final Color Function(T value) swatch;
  final ValueChanged<T?>? onChanged;
  final bool allowNone;

  static const _dotSlot = 32.0;
  static const _shortRowLimit = 8;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = colors.length + (allowNone ? 1 : 0);
        final width = constraints.maxWidth;
        final fits =
            count > 0 &&
            count <= _shortRowLimit &&
            (!width.isFinite || count * _dotSlot <= width);
        final dots = _dots();
        if (fits) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Row(mainAxisSize: MainAxisSize.min, children: dots),
          );
        }
        final current = selected;
        return Align(
          alignment: Alignment.centerLeft,
          child: MenuAnchor(
            menuChildren: [
              if (allowNone)
                MenuItemButton(
                  onPressed: onChanged == null ? null : () => onChanged!(null),
                  leadingIcon: _SwatchDot(
                    color: Colors.white,
                    selected: current == null,
                    none: true,
                  ),
                  child: const Text('None'),
                ),
              for (final color in colors)
                MenuItemButton(
                  onPressed: onChanged == null ? null : () => onChanged!(color),
                  leadingIcon: _SwatchDot(
                    color: swatch(color),
                    selected: current == color,
                  ),
                  child: const SizedBox(width: 24),
                ),
            ],
            builder: (context, controller, _) {
              return OutlinedButton(
                onPressed: onChanged == null
                    ? null
                    : () {
                        if (controller.isOpen) {
                          controller.close();
                        } else {
                          controller.open();
                        }
                      },
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SwatchDot(
                      color: current == null ? Colors.white : swatch(current),
                      selected: true,
                      none: current == null,
                    ),
                    const SizedBox(width: DsSpacing.sm),
                    const Text('Color'),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  List<Widget> _dots() {
    return [
      if (allowNone)
        _SwatchDot(
          color: Colors.white,
          selected: selected == null,
          none: true,
          onTap: onChanged == null ? null : () => onChanged!(null),
        ),
      for (final color in colors)
        _SwatchDot(
          color: swatch(color),
          selected: selected == color,
          onTap: onChanged == null ? null : () => onChanged!(color),
        ),
    ];
  }
}

class _SwatchDot extends StatelessWidget {
  const _SwatchDot({
    required this.color,
    required this.selected,
    this.onTap,
    this.none = false,
  });

  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final bool none;

  @override
  Widget build(BuildContext context) {
    final dot = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: none ? Colors.white : color,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? DsColors.primary : Colors.black26,
          width: selected ? 2.5 : 1,
        ),
      ),
      child: none
          ? const Icon(Icons.block, size: 12, color: Colors.black38)
          : null,
    );
    return SizedBox(
      width: PdfCompactColorPicker._dotSlot,
      height: PdfCompactColorPicker._dotSlot,
      child: onTap == null
          ? Center(child: dot)
          : InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Center(child: dot),
            ),
    );
  }
}
