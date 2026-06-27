import 'package:document_studio/app/providers.dart';
import 'package:document_studio/domain/pdf_markup/markup_fonts.dart';
import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_context_toolbar.dart';
import 'package:document_studio/features/annotations/markup/markup_dialogs.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_format_panel.dart';
import 'package:document_studio/features/annotations/markup/markup_providers.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Side panel for on-page markup: tools, style for the next object, save
/// status. The floating format bar is enough to style text and strokes;
/// this panel stays as the secondary inspector.
class MarkupToolPanel extends ConsumerWidget {
  const MarkupToolPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(markupEditorProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => _MarkupToolPanelBody(controller: c),
    );
  }
}

class _MarkupToolPanelBody extends ConsumerWidget {
  const _MarkupToolPanelBody({required this.controller});

  final MarkupEditorController controller;

  MarkupEditorController get c => controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tool = c.tool;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _StatusRow(controller: c),
        MarkupFormatPanel(controller: c),
        if (c.readOnly)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _Banner(
              icon: Icons.lock_outline,
              text: c.loadError?.toLowerCase().contains('encrypt') ?? false
                  ? 'This PDF is encrypted, so markup can’t be saved into it. '
                        'Remove its security first (All tools › Remove security).'
                  : 'This PDF couldn’t be read for editing: ${c.loadError ?? c.saveError}',
            ),
          ),
        for (final (label, tools) in kMarkupToolGroups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 6),
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in tools)
                _ToolChip(
                  tool: t,
                  selected: tool == t,
                  onTap: () => c.setTool(t),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Divider(height: 1),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          child: KeyedSubtree(
            key: ValueKey(tool),
            child: _ToolOptions(controller: c),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _hintFor(tool),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static String _hintFor(MarkupTool t) => switch (t) {
    MarkupTool.select =>
      'Click to select, Shift-click or drag a box to select several. '
          'Drag to move — pink guides snap to the page and other objects '
          '(hold Alt to move freely). Use the handles to resize or rotate '
          '(Shift snaps to 15°). Double-click text to edit it. '
          '⌘/Ctrl+G groups, ⌘/Ctrl+] / [ change layer order, '
          '⌘/Ctrl+D duplicates, arrows nudge.',
    MarkupTool.text =>
      'Click to type (the box grows as you type) or drag to set a width. '
          'Enter adds a line; Esc or ⌘/Ctrl+Enter finishes. '
          '⌘/Ctrl+B, I, U style the text.',
    MarkupTool.callout =>
      'Press on the point you want to call out, drag to where the text box '
          'should go, then type.',
    MarkupTool.note => 'Click to drop a sticky note and type your comment.',
    MarkupTool.highlight ||
    MarkupTool.underline ||
    MarkupTool.strikeout ||
    MarkupTool.squiggly =>
      'Drag across text — marks snap to the text lines. On scanned pages '
          'without text, drag a box instead.',
    MarkupTool.pen || MarkupTool.highlighter =>
      'Draw freely; strokes are smoothed when you lift the pen.',
    MarkupTool.rectangle ||
    MarkupTool.ellipse => 'Drag to draw. Hold Shift for a square / circle.',
    MarkupTool.line ||
    MarkupTool.arrow => 'Drag to draw. Hold Shift to snap to 45°.',
    MarkupTool.polygon || MarkupTool.cloud =>
      'Click to add corners. Double-click, press Enter or click the first '
          'corner to finish; Esc cancels.',
    MarkupTool.eraser => 'Click or drag over markup to remove it.',
    MarkupTool.link =>
      'Drag a box (or click) where the link should appear, then enter the '
          'link text and a web URL or page number.',
    MarkupTool.image =>
      'Choose an image, then click on the page (or drag a box) to place it.',
  };
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final (IconData icon, String text, Color color) = c.loading
        ? (Icons.hourglass_empty, 'Loading markup…', theme.colorScheme.outline)
        : c.saving
        ? (Icons.cloud_upload_outlined, 'Saving…', theme.colorScheme.outline)
        : c.saveError != null && !c.readOnly
        ? (Icons.error_outline, 'Not saved', theme.colorScheme.error)
        : c.hasUnsavedChanges
        ? (Icons.edit_outlined, 'Editing…', theme.colorScheme.outline)
        : (
            Icons.check_circle_outline,
            'Saved in the PDF',
            theme.colorScheme.primary,
          );
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(color: color),
          ),
        ),
        IconButton(
          tooltip: 'Undo markup',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.undo, size: 18),
          onPressed: c.canUndo ? c.undo : null,
        ),
        IconButton(
          tooltip: 'Redo markup',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.redo, size: 18),
          onPressed: c.canRedo ? c.redo : null,
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: cs.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolChip extends StatelessWidget {
  const _ToolChip({
    required this.tool,
    required this.selected,
    required this.onTap,
  });

  final MarkupTool tool;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hint = tool.shortcutHint;
    return Tooltip(
      message: hint == null ? tool.label : '${tool.label}  ($hint)',
      waitDuration: const Duration(milliseconds: 400),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? cs.primary : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 40,
            child: Icon(
              tool.icon,
              size: 20,
              color: selected ? cs.primary : cs.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolOptions extends ConsumerWidget {
  const _ToolOptions({required this.controller});

  final MarkupEditorController controller;

  MarkupEditorController get c => controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = c.tool;
    final theme = Theme.of(context);
    final children = <Widget>[];

    Widget label(String s) => Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(s, style: theme.textTheme.labelMedium),
    );

    if (t == MarkupTool.select || t == MarkupTool.eraser) {
      final n = c.selection.length;
      children.add(
        Text(
          n == 0
              ? 'Nothing selected'
              : n == 1
              ? '1 object selected'
              : '$n objects selected',
          style: theme.textTheme.titleSmall,
        ),
      );
      children.add(
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Smart guides & snapping'),
          value: c.snapEnabled,
          onChanged: (v) => c.updateStyle(() => c.snapEnabled = v),
        ),
      );
      if (n > 0) {
        children.add(
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: c.duplicateSelection,
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Duplicate'),
              ),
              TextButton.icon(
                onPressed: c.deleteSelected,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Delete'),
              ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }

    final palette = switch (t) {
      MarkupTool.highlight || MarkupTool.highlighter => kHighlightPalette,
      MarkupTool.note => kNotePalette,
      _ => kMarkupPalette,
    };
    final textTool = t == MarkupTool.text || t == MarkupTool.callout;
    final selectedText = c.selectedObjects.any(
      (o) => o is TextBoxMarkup && !o.locked,
    );
    if (!textTool && t != MarkupTool.image && t != MarkupTool.link) {
      children
        ..add(label('Color'))
        ..add(
          MarkupPaletteGrid(
            palette: palette,
            current: c.activeColor,
            onPick: (v) {
              if (v != null) c.setActiveColor(v);
            },
          ),
        );
    }

    if (t.isShape) {
      children
        ..add(label('Line width'))
        ..add(
          _WidthPicker(
            value: c.strokeWidth,
            onChanged: (v) => c.updateStyle(() => c.strokeWidth = v),
          ),
        )
        ..add(label('Line style'))
        ..add(
          SegmentedButton<StrokeDash>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: StrokeDash.solid, label: Text('Solid')),
              ButtonSegment(value: StrokeDash.dashed, label: Text('Dashed')),
              ButtonSegment(value: StrokeDash.dotted, label: Text('Dotted')),
            ],
            selected: {c.dash},
            onSelectionChanged: (v) => c.updateStyle(() => c.dash = v.first),
          ),
        );
      if (t != MarkupTool.line && t != MarkupTool.arrow) {
        children
          ..add(label('Fill'))
          ..add(
            MarkupPaletteGrid(
              palette: kMarkupPalette,
              current: c.fillColor,
              allowNone: true,
              allowTranslucent: true,
              onPick: (v) => c.updateStyle(() => c.fillColor = v),
            ),
          );
      }
    }
    if (t == MarkupTool.pen || t == MarkupTool.highlighter) {
      final hl = t == MarkupTool.highlighter;
      children
        ..add(label('Width'))
        ..add(
          _WidthPicker(
            value: hl ? c.highlighterWidth : c.penWidth,
            values: hl ? const [6, 9, 12, 16, 22, 30] : kMarkupStrokeWidths,
            onChanged: (v) => c.updateStyle(() {
              if (hl) {
                c.highlighterWidth = v;
              } else {
                c.penWidth = v;
              }
            }),
          ),
        );
    }
    if (textTool && !selectedText) {
      children
        ..add(const PdfOptionHeading('Text', first: true))
        ..add(
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 8.0;
              const sizeMin = 108.0;
              final maxW = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : sizeMin;
              final sideBySide = maxW >= 200;
              final sizeW = sideBySide ? sizeMin : maxW.clamp(0.0, maxW);
              final familyW = sideBySide
                  ? (maxW - gap - sizeW).clamp(0.0, maxW)
                  : maxW;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: familyW > 0 ? familyW : maxW,
                    child: DropdownButtonFormField<MarkupFontFamily>(
                      initialValue: c.fontFamily,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Font',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final f in MarkupFontFamily.values)
                          DropdownMenuItem(
                            value: f,
                            child: Text(
                              f.pdfFamily,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: f.flutterFamily),
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) {
                          c.updateStyle(() => c.fontFamily = v);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: sizeW > 0 ? sizeW : maxW,
                    child: DropdownButtonFormField<double>(
                      initialValue: c.fontSize,
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        for (final s in kMarkupFontSizes)
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.toInt()} pt'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v != null) c.updateStyle(() => c.fontSize = v);
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton.outlined(
                isSelected: c.bold,
                tooltip: 'Bold',
                icon: const Icon(Icons.format_bold),
                onPressed: () => c.updateStyle(() => c.bold = !c.bold),
              ),
              IconButton.outlined(
                isSelected: c.italic,
                tooltip: 'Italic',
                icon: const Icon(Icons.format_italic),
                onPressed: () => c.updateStyle(() => c.italic = !c.italic),
              ),
              IconButton.outlined(
                isSelected: c.underline,
                tooltip: 'Underline',
                icon: const Icon(Icons.format_underline),
                onPressed: () =>
                    c.updateStyle(() => c.underline = !c.underline),
              ),
              IconButton.outlined(
                isSelected: c.strike,
                tooltip: 'Strikethrough',
                icon: const Icon(Icons.format_strikethrough),
                onPressed: () => c.updateStyle(() => c.strike = !c.strike),
              ),
            ],
          ),
        )
        ..add(const SizedBox(height: 8))
        ..add(
          PdfTextAlignGroup<MarkupTextAlign>(
            value: c.textAlign,
            left: MarkupTextAlign.left,
            center: MarkupTextAlign.center,
            right: MarkupTextAlign.right,
            onChanged: (align) => c.updateStyle(() => c.textAlign = align),
          ),
        )
        ..add(
          label(
            'Letter spacing  '
            '${(c.letterSpacing / c.fontSize * 1000).round()}',
          ),
        )
        ..add(
          Slider(
            value: (c.letterSpacing / c.fontSize * 1000).clamp(-100, 600),
            min: -100,
            max: 600,
            divisions: 70,
            onChanged: (v) =>
                c.updateStyle(() => c.letterSpacing = v / 1000 * c.fontSize),
          ),
        )
        ..add(label('Line spacing  ${c.lineHeight.toStringAsFixed(2)}'))
        ..add(
          Slider(
            value: c.lineHeight.clamp(0.8, 3),
            min: 0.8,
            max: 3,
            divisions: 44,
            onChanged: (v) => c.updateStyle(() => c.lineHeight = v),
          ),
        )
        ..add(const PdfOptionHeading('Appearance'))
        ..add(
          PdfCompactColorPicker<int>(
            colors: kMarkupPalette,
            selected: c.activeColor,
            swatch: Color.new,
            onChanged: (v) {
              if (v != null) c.setActiveColor(v);
            },
          ),
        );
    }
    if (t == MarkupTool.image) {
      final has = c.pendingImage != null;
      children.add(
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              onPressed: () async {
                final storage = ref.read(fileStorageProvider);
                final picked = await pickMarkupImage(context, storage);
                if (picked != null) c.setPendingImage(picked.$1, picked.$2);
              },
              icon: const Icon(Icons.image_outlined),
              label: Text(has ? 'Choose another…' : 'Choose image…'),
            ),
            if (has)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.memory(
                  c.pendingImage!,
                  height: 40,
                  fit: BoxFit.contain,
                ),
              ),
          ],
        ),
      );
    }

    if (t != MarkupTool.link) {
      children
        ..add(label('Opacity  ${(c.opacity * 100).round()}%'))
        ..add(
          Slider(
            value: c.opacity,
            min: 0.1,
            max: 1,
            divisions: 18,
            onChanged: (v) => c.updateStyle(() => c.opacity = v),
          ),
        );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _WidthPicker extends StatelessWidget {
  const _WidthPicker({
    required this.value,
    required this.onChanged,
    this.values = kMarkupStrokeWidths,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final List<double> values;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final w in values)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(w),
            child: Container(
              width: 38,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: w == value ? cs.primary : cs.outlineVariant,
                  width: w == value ? 1.6 : 1,
                ),
              ),
              child: Container(
                width: 22,
                height: (w * 0.8).clamp(0.8, 12),
                decoration: BoxDecoration(
                  color: cs.onSurface,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
