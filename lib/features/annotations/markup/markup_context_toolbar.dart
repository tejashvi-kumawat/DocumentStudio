import 'dart:math' as math;

import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_dialogs.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/features/annotations/markup/markup_page_layer.dart';
import 'package:document_studio/features/annotations/markup/markup_painter.dart';
import 'package:document_studio/features/annotations/markup/markup_text_layout.dart';
import 'package:document_studio/features/annotations/markup/markup_tool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Positions [MarkupContextToolbar] next to the selection, inside the page.
class MarkupContextToolbarAnchor extends StatelessWidget {
  const MarkupContextToolbarAnchor({
    super.key,
    required this.controller,
    required this.selection,
    required this.scale,
    required this.pageSize,
    required this.actions,
  });

  final MarkupEditorController controller;
  final List<MarkupObject> selection;
  final double scale;
  final Size pageSize;
  final MarkupPageActions actions;

  @override
  Widget build(BuildContext context) {
    if (selection.isEmpty) return const SizedBox.shrink();
    var b = selection.first.bounds;
    for (final o in selection.skip(1)) {
      b = b.expandToInclude(o.bounds);
    }
    final screen = Rect.fromLTRB(
      b.left * scale,
      b.top * scale,
      b.right * scale,
      b.bottom * scale,
    );
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _ToolbarLayout(screen),
        child: TextFieldTapRegion(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..translateByDouble(0, (1 - t) * 6, 0, 1)
                  ..scaleByDouble(0.94 + 0.06 * t, 0.94 + 0.06 * t, 1, 1),
                child: child,
              ),
            ),
            child: MarkupContextToolbar(
              controller: controller,
              selection: selection,
              actions: actions,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarLayout extends SingleChildLayoutDelegate {
  _ToolbarLayout(this.target);

  final Rect target;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(math.max(0, constraints.maxWidth - 8), constraints.maxHeight),
      );

  @override
  Offset getPositionForChild(Size size, Size child) {
    const gap = 14.0;
    var top = target.bottom + gap;
    if (top + child.height > size.height - 4) {
      // Above, clearing the rotate knob.
      top = target.top - child.height - 44;
    }
    top = top.clamp(4, math.max(4, size.height - child.height - 4));
    var left = target.center.dx - child.width / 2;
    left = left.clamp(4, math.max(4, size.width - child.width - 4));
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _ToolbarLayout old) => old.target != target;
}

// ================================================================ toolbar

/// Floating contextual toolbar for the current selection: grouped, compact
/// and adaptive (scrolls horizontally when the page is narrow).
class MarkupContextToolbar extends StatelessWidget {
  const MarkupContextToolbar({
    super.key,
    required this.controller,
    required this.selection,
    required this.actions,
  });

  final MarkupEditorController controller;
  final List<MarkupObject> selection;
  final MarkupPageActions actions;

  MarkupEditorController get c => controller;

  bool get _single => selection.length == 1;
  MarkupObject get _first => selection.first;
  bool get _anyLocked => selection.any((o) => o.locked);

  void _apply(MarkupObject Function(MarkupObject o) f) => c.updateSelected(f);

  void _text(TextBoxMarkup Function(TextBoxMarkup o) f) =>
      _apply((o) => o is TextBoxMarkup ? relayoutTextBox(f(o)) : o);

  List<int> get _palette {
    if (selection.every(
      (o) =>
          o is TextMarkupMarkup && o.kind == TextMarkupKind.highlight ||
          o is InkMarkup && o.highlighter,
    )) {
      return kHighlightPalette;
    }
    if (selection.every((o) => o is NoteMarkup)) return kNotePalette;
    return kMarkupPalette;
  }

  bool get _canRecolor =>
      selection.any((o) => o is! ImageMarkup && o is! LinkMarkup);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final locked = _anyLocked;
    final sections = <List<Widget>>[];

    final shapes = selection.whereType<ShapeMarkup>().toList();
    final texts = selection.whereType<TextBoxMarkup>().toList();
    final images = selection.whereType<ImageMarkup>().toList();
    final marks = selection.whereType<TextMarkupMarkup>().toList();
    final editingText = c.editingId != null;

    if (!locked && texts.isNotEmpty) {
      sections.add(_textSection(context, texts.first));
    }

    final pencilBar = selection.any(
      (o) =>
          !o.locked &&
          (o is InkMarkup || o is ShapeMarkup || o is TextMarkupMarkup),
    );
    if (!locked) {
      final style = <Widget>[];
      // Color and stroke width for ink, shapes, and text markup are on the
      // floating format bar. Notes and other objects keep a swatch here.
      if (_canRecolor && texts.isEmpty && !pencilBar) {
        style.add(
          _ColorButton(
            tooltip: 'Color',
            color: _first.color,
            palette: _palette,
            onPick: (argb) {
              if (argb != null) _apply((o) => o.recolored(argb));
            },
          ),
        );
      }
      final closed = shapes.where((s) => s.isClosed).toList();
      if (closed.isNotEmpty) {
        style.add(
          _ColorButton(
            tooltip: 'Fill',
            color: closed.first.fillColor,
            icon: Icons.format_color_fill,
            palette: kMarkupPalette,
            allowNone: true,
            allowTranslucent: true,
            onPick: (argb) => _apply(
              (o) => o is ShapeMarkup ? o.copyWith(fillColor: () => argb) : o,
            ),
          ),
        );
      }
      if (shapes.isNotEmpty) {
        style.add(
          _MenuButton<StrokeDash>(
            tooltip: 'Line style',
            icon: switch (shapes.first.dash) {
              StrokeDash.solid => Icons.horizontal_rule,
              StrokeDash.dashed => Icons.more_horiz,
              StrokeDash.dotted => Icons.more_horiz,
            },
            values: StrokeDash.values,
            selected: shapes.first.dash,
            labelOf: (v) => switch (v) {
              StrokeDash.solid => 'Solid',
              StrokeDash.dashed => 'Dashed',
              StrokeDash.dotted => 'Dotted',
            },
            onSelected: (v) =>
                _apply((o) => o is ShapeMarkup ? o.copyWith(dash: v) : o),
          ),
        );
      }
      if (marks.isNotEmpty) {
        style.add(
          _MenuButton<TextMarkupKind>(
            tooltip: 'Markup style',
            icon: switch (marks.first.kind) {
              TextMarkupKind.highlight => Icons.highlight,
              TextMarkupKind.underline => Icons.format_underline,
              TextMarkupKind.strikeout => Icons.format_strikethrough,
              TextMarkupKind.squiggly => Icons.waves,
            },
            values: TextMarkupKind.values,
            selected: marks.first.kind,
            labelOf: (v) => switch (v) {
              TextMarkupKind.highlight => 'Highlight',
              TextMarkupKind.underline => 'Underline',
              TextMarkupKind.strikeout => 'Strikethrough',
              TextMarkupKind.squiggly => 'Squiggly',
            },
            onSelected: (v) =>
                _apply((o) => o is TextMarkupMarkup ? o.copyWith(kind: v) : o),
          ),
        );
      }
      if (style.isNotEmpty) sections.add(style);
    }

    if (!locked && images.isNotEmpty) {
      sections.add(_imageSection(context, images));
    }

    if (!locked && _single && _first is LinkMarkup) {
      sections.add([
        _ToolButton(
          tooltip: 'Edit link',
          icon: Icons.edit_outlined,
          onPressed: () async {
            final edited = await actions.editLink(
              _first as LinkMarkup,
              isNew: false,
            );
            if (edited != null) c.replaceObjects([fitMarkupLinkFrame(edited)]);
          },
        ),
      ]);
    }

    // Arrange: aspect lock, position, grouping, opacity.
    final arrange = <Widget>[];
    if (!locked &&
        _single &&
        (_first is ImageMarkup ||
            (_first is ShapeMarkup && (_first as ShapeMarkup).isFrameBased))) {
      final on = c.aspectLockedFor(_first);
      arrange.add(
        _ToolButton(
          tooltip: on
              ? 'Aspect ratio locked (Shift frees)'
              : 'Lock aspect ratio',
          icon: on ? Icons.lock_outline : Icons.lock_open_outlined,
          selected: on,
          onPressed: () => c.toggleAspectLockFor(_first),
        ),
      );
    }
    if (!locked && !editingText) {
      arrange.add(
        _PopoverButton(
          tooltip: 'Position',
          icon: Icons.align_horizontal_left,
          width: 248,
          builder: (context) => _PositionPopover(controller: c),
        ),
      );
    }
    if (!editingText && (c.canGroup || c.canUngroup)) {
      arrange.add(
        c.canGroup
            ? _ToolButton(
                tooltip: 'Group  (${_mod()}G)',
                icon: Icons.group_work_outlined,
                onPressed: c.groupSelection,
              )
            : _ToolButton(
                tooltip: 'Ungroup  (${_mod()}⇧G)',
                icon: Icons.call_split,
                onPressed: c.ungroupSelection,
              ),
      );
    }
    if (!locked && selection.any((o) => o is! LinkMarkup)) {
      arrange.add(
        _PopoverButton(
          tooltip: 'Transparency',
          icon: Icons.opacity,
          label: '${(_first.opacity * 100).round()}%',
          width: 240,
          builder: (context) => _OpacityPopover(controller: c),
        ),
      );
    }
    if (arrange.isNotEmpty) sections.add(arrange);

    sections.add([
      _MoreMenu(controller: c, selection: selection, locked: locked),
      if (!locked && !editingText)
        _ToolButton(
          tooltip: 'Delete',
          icon: Icons.delete_outline,
          onPressed: c.deleteSelected,
        ),
    ]);

    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) children.add(const _Divider());
      children.addAll(sections[i]);
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AnimatedSize(
            duration: MediaQuery.maybeDisableAnimationsOf(context) ?? false
                ? Duration.zero
                : const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
              child: IconTheme.merge(
                data: IconThemeData(size: 18, color: cs.onSurface),
                child: Row(mainAxisSize: MainAxisSize.min, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- text

  List<Widget> _textSection(BuildContext context, TextBoxMarkup t) {
    // Font, size, bold, italic, underline, color, alignment, and line
    // spacing live on the floating format bar. Strike and box options stay
    // here with the other object actions.
    return [
      _ToolButton(
        tooltip: 'Strikethrough',
        icon: Icons.format_strikethrough,
        selected: t.strike,
        onPressed: () => _text((o) => o.copyWith(strike: !t.strike)),
      ),
      _PopoverButton(
        tooltip: 'Background & box',
        icon: Icons.crop_square,
        width: 280,
        builder: (context) => _TextOptionsPopover(controller: c),
      ),
    ];
  }

  // -------------------------------------------------------------- image

  List<Widget> _imageSection(BuildContext context, List<ImageMarkup> images) {
    final single = images.length == 1 && _single ? images.first : null;
    return [
      if (single != null)
        _ToolButton(
          tooltip: 'Crop',
          icon: Icons.crop,
          onPressed: () async {
            final decoded = MarkupImageCache.instance.imageFor(single.bytes);
            final size = decoded == null
                ? Size(single.frame.width, single.frame.height)
                : Size(decoded.width.toDouble(), decoded.height.toDouble());
            final crop = await showMarkupCropDialog(
              context,
              bytes: single.bytes,
              imageSize: size,
              crop: single.crop,
            );
            if (crop != null && crop != single.crop) {
              c.cropImage(single.id, crop, size);
            }
          },
        ),
      if (single != null)
        _ToolButton(
          tooltip: 'Replace image…',
          icon: Icons.swap_horiz,
          onPressed: () async {
            final picked = await actions.pickImage();
            if (picked == null) return;
            c.replaceImage(single.id, picked.$1, picked.$2);
          },
        ),
      _ToolButton(
        tooltip: 'Flip horizontal',
        icon: Icons.flip,
        onPressed: () =>
            _apply((o) => o is ImageMarkup ? o.copyWith(flipH: !o.flipH) : o),
      ),
      _ToolButton(
        tooltip: 'Flip vertical',
        icon: Icons.flip,
        quarterTurns: 1,
        onPressed: () =>
            _apply((o) => o is ImageMarkup ? o.copyWith(flipV: !o.flipV) : o),
      ),
      _ToolButton(
        tooltip: 'Rotate 90°',
        icon: Icons.rotate_90_degrees_cw_outlined,
        onPressed: () => _apply(
          (o) => o is ImageMarkup ? o.rotatedTo((o.rotation + 90) % 360) : o,
        ),
      ),
      _PopoverButton(
        tooltip: 'Corners & border',
        icon: Icons.rounded_corner,
        width: 280,
        builder: (context) => _ImageStylePopover(controller: c),
      ),
    ];
  }
}

String _mod() => defaultTargetPlatform == TargetPlatform.macOS ? '⌘' : 'Ctrl+';

// ============================================================== popovers

/// Opens a small anchored panel below (or above) the widget at [context].
Future<T?> showMarkupPopover<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double width = 260,
}) {
  final nav = Navigator.of(context);
  final box = context.findRenderObject() as RenderBox?;
  final overlay = nav.overlay?.context.findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return Future.value();
  final anchor = MatrixUtils.transformRect(
    box.getTransformTo(overlay),
    Offset.zero & box.size,
  );
  return nav.push(
    _PopoverRoute<T>(
      anchor: anchor,
      builder: builder,
      width: width,
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      themes: InheritedTheme.capture(from: context, to: nav.context),
      label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({
    required this.anchor,
    required this.builder,
    required this.width,
    required this.reduceMotion,
    required this.themes,
    required this.label,
  });

  final Rect anchor;
  final WidgetBuilder builder;
  final double width;
  final bool reduceMotion;
  final CapturedThemes themes;
  final String label;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => label;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 110);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final panel = FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.6),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 22,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(builder: builder),
              ),
            ),
          ),
        ),
      ),
    );
    return themes.wrap(
      CustomSingleChildLayout(
        delegate: _PopoverLayout(anchor, MediaQuery.paddingOf(context)),
        child: panel,
      ),
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout(this.anchor, this.padding);

  final Rect anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(const EdgeInsets.all(8) + padding);

  @override
  Offset getPositionForChild(Size size, Size child) {
    var top = anchor.bottom + 6;
    if (top + child.height > size.height - padding.bottom - 8) {
      top = anchor.top - child.height - 6;
    }
    top = top.clamp(
      padding.top + 8,
      math.max(padding.top + 8, size.height - child.height - 8),
    );
    var left = anchor.center.dx - child.width / 2;
    left = left.clamp(8, math.max(8, size.width - child.width - 8));
    return Offset(left, top);
  }

  @override
  bool shouldRelayout(covariant _PopoverLayout old) =>
      old.anchor != anchor || old.padding != padding;
}

class _PopoverTitle extends StatelessWidget {
  const _PopoverTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 0.6,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Label + value + slider that previews live and commits once on release.
class _LiveSlider extends StatelessWidget {
  const _LiveSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onPreview,
    required this.onCommit,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double v) format;
  final ValueChanged<double> onPreview;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
            Text(
              format(value),
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onPreview,
            onChangeEnd: (_) => onCommit(),
          ),
        ),
      ],
    );
  }
}

/// Rebuilds popover content from the controller's live selection.
class _SelectionBuilder extends StatelessWidget {
  const _SelectionBuilder({required this.controller, required this.builder});

  final MarkupEditorController controller;
  final Widget Function(BuildContext context, List<MarkupObject> sel) builder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller,
        controller.previewTick,
        controller.textEditTick,
      ]),
      builder: (context, _) {
        final sel = controller.selectedObjects;
        if (sel.isEmpty) return const SizedBox(height: 24);
        return builder(context, sel);
      },
    );
  }
}

class _TextOptionsPopover extends StatelessWidget {
  const _TextOptionsPopover({required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    TextBoxMarkup Function(MarkupObject) relayout(
      TextBoxMarkup Function(TextBoxMarkup t) f,
    ) =>
        (o) => relayoutTextBox(f(o as TextBoxMarkup));
    MarkupObject Function(MarkupObject) onText(
      TextBoxMarkup Function(TextBoxMarkup t) f,
    ) =>
        (o) => o is TextBoxMarkup ? relayout(f)(o) : o;
    return _SelectionBuilder(
      controller: c,
      builder: (context, sel) {
        final t = sel.whereType<TextBoxMarkup>().firstOrNull;
        if (t == null) return const SizedBox(height: 24);
        final em = t.letterSpacing / math.max(1, t.fontSize);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PopoverTitle('Spacing'),
            _LiveSlider(
              label: 'Letter spacing',
              value: em * 1000,
              min: -100,
              max: 600,
              divisions: 70,
              format: (v) => v.round().toString(),
              onPreview: (v) => c.previewSelected(
                onText((o) => o.copyWith(letterSpacing: v / 1000 * o.fontSize)),
              ),
              onCommit: c.commitPreview,
            ),
            _LiveSlider(
              label: 'Line spacing',
              value: t.lineHeight,
              min: 0.8,
              max: 3,
              divisions: 44,
              format: (v) => v.toStringAsFixed(2),
              onPreview: (v) =>
                  c.previewSelected(onText((o) => o.copyWith(lineHeight: v))),
              onCommit: c.commitPreview,
            ),
            const SizedBox(height: 4),
            const _PopoverTitle('Box'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Background',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _ColorButton(
                  tooltip: 'Background',
                  color: t.fillColor,
                  palette: kMarkupPalette,
                  allowNone: true,
                  allowTranslucent: true,
                  onPick: (argb) => c.updateSelected(
                    onText((o) => o.copyWith(fillColor: () => argb)),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Border',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _ColorButton(
                  tooltip: 'Border',
                  color: t.borderColor,
                  palette: kMarkupPalette,
                  allowNone: true,
                  onPick: (argb) => c.updateSelected(
                    onText((o) => o.copyWith(borderColor: () => argb)),
                  ),
                ),
              ],
            ),
            if (t.borderColor != null)
              _LiveSlider(
                label: 'Border width',
                value: t.borderWidth,
                min: 0.5,
                max: 8,
                divisions: 15,
                format: (v) => '${v.toStringAsFixed(1)} pt',
                onPreview: (v) => c.previewSelected(
                  onText((o) => o.copyWith(borderWidth: v)),
                ),
                onCommit: c.commitPreview,
              ),
            _LiveSlider(
              label: 'Padding',
              value: t.padding,
              min: 0,
              max: 24,
              divisions: 24,
              format: (v) => '${v.round()} pt',
              onPreview: (v) =>
                  c.previewSelected(onText((o) => o.copyWith(padding: v))),
              onCommit: c.commitPreview,
            ),
            if (!t.isCallout)
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto width'),
                subtitle: const Text(
                  'Box grows with the text instead of wrapping',
                ),
                value: t.autoWidth,
                onChanged: (v) =>
                    c.updateSelected(onText((o) => o.copyWith(autoWidth: v))),
              ),
          ],
        );
      },
    );
  }
}

class _ImageStylePopover extends StatelessWidget {
  const _ImageStylePopover({required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _SelectionBuilder(
      controller: c,
      builder: (context, sel) {
        final im = sel.whereType<ImageMarkup>().firstOrNull;
        if (im == null) return const SizedBox(height: 24);
        final maxR = math.max(
          1.0,
          math.min(im.frame.width, im.frame.height) / 2,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _PopoverTitle('Corners'),
            _LiveSlider(
              label: 'Corner radius',
              value: math.min(im.cornerRadius, maxR),
              min: 0,
              max: maxR,
              format: (v) => '${v.round()} pt',
              onPreview: (v) => c.previewSelected(
                (o) => o is ImageMarkup ? o.copyWith(cornerRadius: v) : o,
              ),
              onCommit: c.commitPreview,
            ),
            const _PopoverTitle('Border'),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Color',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                _ColorButton(
                  tooltip: 'Border color',
                  color: im.borderColor,
                  palette: kMarkupPalette,
                  allowNone: true,
                  onPick: (argb) => c.updateSelected(
                    (o) => o is ImageMarkup
                        ? o.copyWith(
                            borderColor: () => argb,
                            borderWidth: argb != null && o.borderWidth <= 0
                                ? 2
                                : null,
                          )
                        : o,
                  ),
                ),
              ],
            ),
            if (im.borderColor != null)
              _LiveSlider(
                label: 'Width',
                value: im.borderWidth,
                min: 0.5,
                max: 16,
                divisions: 31,
                format: (v) => '${v.toStringAsFixed(1)} pt',
                onPreview: (v) => c.previewSelected(
                  (o) => o is ImageMarkup ? o.copyWith(borderWidth: v) : o,
                ),
                onCommit: c.commitPreview,
              ),
            if (im.isCropped)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () {
                    final decoded = MarkupImageCache.instance.imageFor(
                      im.bytes,
                    );
                    if (decoded == null) return;
                    c.cropImage(
                      im.id,
                      kFullCrop,
                      Size(decoded.width.toDouble(), decoded.height.toDouble()),
                    );
                  },
                  icon: const Icon(Icons.crop_free, size: 18),
                  label: const Text('Remove crop'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _OpacityPopover extends StatelessWidget {
  const _OpacityPopover({required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return _SelectionBuilder(
      controller: c,
      builder: (context, sel) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _PopoverTitle('Transparency'),
          _LiveSlider(
            label: 'Opacity',
            value: sel.first.opacity,
            min: 0.05,
            max: 1,
            divisions: 19,
            format: (v) => '${(v * 100).round()}%',
            onPreview: (v) => c.previewSelected(
              (o) => o is LinkMarkup ? o : o.withCommon(opacity: v),
            ),
            onCommit: c.commitPreview,
          ),
        ],
      ),
    );
  }
}

class _PositionPopover extends StatelessWidget {
  const _PositionPopover({required this.controller});

  final MarkupEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    Widget cell(IconData icon, String tip, VoidCallback onTap) =>
        _ToolButton(tooltip: tip, icon: icon, onPressed: onTap);
    return _SelectionBuilder(
      controller: c,
      builder: (context, sel) {
        final multi = sel.length > 1 && !c.selectionIsGroup;
        final to = multi ? 'selection' : 'page';
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PopoverTitle('Align to $to'),
            Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                cell(
                  Icons.align_horizontal_left,
                  'Left',
                  () => c.alignSelection(MarkupAlign.left),
                ),
                cell(
                  Icons.align_horizontal_center,
                  'Center',
                  () => c.alignSelection(MarkupAlign.centerH),
                ),
                cell(
                  Icons.align_horizontal_right,
                  'Right',
                  () => c.alignSelection(MarkupAlign.right),
                ),
                cell(
                  Icons.align_vertical_top,
                  'Top',
                  () => c.alignSelection(MarkupAlign.top),
                ),
                cell(
                  Icons.align_vertical_center,
                  'Middle',
                  () => c.alignSelection(MarkupAlign.middle),
                ),
                cell(
                  Icons.align_vertical_bottom,
                  'Bottom',
                  () => c.alignSelection(MarkupAlign.bottom),
                ),
              ],
            ),
            if (c.canDistribute) ...[
              const SizedBox(height: 6),
              const _PopoverTitle('Distribute'),
              Row(
                children: [
                  cell(
                    Icons.horizontal_distribute,
                    'Horizontally',
                    () => c.distributeSelection(Axis.horizontal),
                  ),
                  cell(
                    Icons.vertical_distribute,
                    'Vertically',
                    () => c.distributeSelection(Axis.vertical),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            const _PopoverTitle('Layer order'),
            _MenuRow(
              icon: Icons.flip_to_front,
              label: 'Bring to front',
              shortcut: '${_mod()}⇧]',
              onTap: c.bringToFront,
            ),
            _MenuRow(
              icon: Icons.arrow_upward,
              label: 'Bring forward',
              shortcut: '${_mod()}]',
              onTap: c.bringForward,
            ),
            _MenuRow(
              icon: Icons.arrow_downward,
              label: 'Send backward',
              shortcut: '${_mod()}[',
              onTap: c.sendBackward,
            ),
            _MenuRow(
              icon: Icons.flip_to_back,
              label: 'Send to back',
              shortcut: '${_mod()}⇧[',
              onTap: c.sendToBack,
            ),
          ],
        );
      },
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.shortcut,
  });

  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            if (shortcut != null)
              Text(
                shortcut!,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================== controls

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 22,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.quarterTurns = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: selected
              ? cs.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onPressed,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: RotatedBox(
                  quarterTurns: quarterTurns,
                  child: Icon(icon, color: selected ? cs.primary : null),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PopoverButton extends StatelessWidget {
  const _PopoverButton({
    required this.tooltip,
    required this.builder,
    this.icon,
    this.label,
    this.width = 260,
  });

  final String tooltip;
  final WidgetBuilder builder;
  final IconData? icon;
  final String? label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () =>
            showMarkupPopover<void>(context, builder: builder, width: width),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34, minWidth: 34),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) Icon(icon),
                if (label != null)
                  Padding(
                    padding: EdgeInsets.only(left: icon == null ? 0 : 4),
                    child: Text(
                      label!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                Icon(
                  Icons.expand_more,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuButton<T> extends StatelessWidget {
  const _MenuButton({
    required this.tooltip,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.icon,
    this.label,
  });

  final String tooltip;
  final List<T> values;
  final T selected;
  final String Function(T v) labelOf;
  final ValueChanged<T> onSelected;
  final IconData? icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<T>(
      tooltip: tooltip,
      initialValue: selected,
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final v in values)
          CheckedPopupMenuItem<T>(
            value: v,
            checked: v == selected,
            child: Text(labelOf(v)),
          ),
      ],
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 34, minWidth: 34),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon),
              if (label != null)
                Padding(
                  padding: EdgeInsets.only(left: icon == null ? 0 : 4),
                  child: Text(label!, style: theme.textTheme.labelMedium),
                ),
              Icon(
                Icons.expand_more,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({
    required this.controller,
    required this.selection,
    required this.locked,
  });

  final MarkupEditorController controller;
  final List<MarkupObject> selection;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz, size: 18),
      iconSize: 18,
      padding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      constraints: const BoxConstraints(minWidth: 210),
      onSelected: (v) {
        switch (v) {
          case 'copy':
            c.copySelection();
          case 'duplicate':
            c.duplicateSelection();
          case 'lock':
            for (final o in selection) {
              c.setLocked(o.id, !locked);
            }
          case 'hide':
            for (final o in selection) {
              c.setHidden(o.id, true);
            }
          case 'snap':
            c.updateStyle(() => c.snapEnabled = !c.snapEnabled);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'copy',
          child: _MenuItemText('Copy', '${_mod()}C'),
        ),
        PopupMenuItem(
          value: 'duplicate',
          child: _MenuItemText('Duplicate', '${_mod()}D'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'lock', child: Text(locked ? 'Unlock' : 'Lock')),
        const PopupMenuItem(value: 'hide', child: Text('Hide')),
        const PopupMenuDivider(),
        CheckedPopupMenuItem(
          value: 'snap',
          checked: c.snapEnabled,
          child: const Text('Smart guides'),
        ),
      ],
    );
  }
}

class _MenuItemText extends StatelessWidget {
  const _MenuItemText(this.label, this.shortcut);

  final String label;
  final String shortcut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          shortcut,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.tooltip,
    required this.color,
    required this.palette,
    required this.onPick,
    this.icon,
    this.allowNone = false,
    this.allowTranslucent = false,
  });

  final String tooltip;
  final int? color;
  final List<int> palette;
  final ValueChanged<int?> onPick;
  final IconData? icon;
  final bool allowNone;
  final bool allowTranslucent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final swatch = Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color == null ? Colors.transparent : Color(color!),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outline, width: 1),
      ),
      child: color == null
          ? CustomPaint(painter: _NoneSlashPainter(cs.error))
          : null,
    );
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => showMarkupPopover<void>(
          context,
          width: 236,
          builder: (popover) => _ColorPopover(
            title: tooltip,
            palette: palette,
            current: color,
            allowNone: allowNone,
            allowTranslucent: allowTranslucent,
            onPick: (v) {
              Navigator.of(popover).pop();
              onPick(v);
            },
          ),
        ),
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 4)],
                swatch,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorPopover extends StatefulWidget {
  const _ColorPopover({
    required this.title,
    required this.palette,
    required this.current,
    required this.onPick,
    required this.allowNone,
    required this.allowTranslucent,
  });

  final String title;
  final List<int> palette;
  final int? current;
  final ValueChanged<int?> onPick;
  final bool allowNone;
  final bool allowTranslucent;

  @override
  State<_ColorPopover> createState() => _ColorPopoverState();
}

class _ColorPopoverState extends State<_ColorPopover> {
  late final TextEditingController _hex = TextEditingController(
    text: widget.current == null
        ? ''
        : (widget.current! & 0xFFFFFF)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase(),
  );

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _submitHex() {
    final v = int.tryParse(_hex.text.trim().replaceAll('#', ''), radix: 16);
    if (v == null || _hex.text.trim().replaceAll('#', '').length != 6) return;
    final alpha = widget.current == null
        ? 0xFF000000
        : widget.current! & 0xFF000000;
    widget.onPick(v | (alpha == 0 ? 0xFF000000 : alpha));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PopoverTitle(widget.title),
        MarkupPaletteGrid(
          palette: widget.palette,
          current: widget.current,
          allowNone: widget.allowNone,
          allowTranslucent: widget.allowTranslucent,
          onPick: widget.onPick,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _hex,
          decoration: const InputDecoration(
            isDense: true,
            prefixText: '#',
            hintText: 'Hex, e.g. 1E88E5',
            border: OutlineInputBorder(),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
            LengthLimitingTextInputFormatter(7),
          ],
          onSubmitted: (_) => _submitHex(),
        ),
      ],
    );
  }
}

class _NoneSlashPainter extends CustomPainter {
  _NoneSlashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.15),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _NoneSlashPainter old) => old.color != color;
}

/// Grid of color swatches (optionally "none" and 40% variants).
class MarkupPaletteGrid extends StatelessWidget {
  const MarkupPaletteGrid({
    super.key,
    required this.palette,
    required this.current,
    required this.onPick,
    this.allowNone = false,
    this.allowTranslucent = false,
  });

  final List<int> palette;
  final int? current;
  final ValueChanged<int?> onPick;
  final bool allowNone;
  final bool allowTranslucent;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget dot(int? argb) {
      final sel = argb == current;
      return InkWell(
        customBorder: const CircleBorder(),
        onTap: () => onPick(argb),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 24,
          height: 24,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: argb == null ? Colors.transparent : Color(argb),
            shape: BoxShape.circle,
            border: Border.all(
              color: sel ? cs.primary : cs.outlineVariant,
              width: sel ? 2.5 : 1,
            ),
          ),
          child: argb == null
              ? CustomPaint(painter: _NoneSlashPainter(cs.error))
              : null,
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 212),
      child: Wrap(
        children: [
          if (allowNone) dot(null),
          for (final c in palette) dot(c),
          if (allowTranslucent)
            for (final c in palette.where((c) => c != 0xFF000000))
              dot((c & 0x00FFFFFF) | 0x66000000),
        ],
      ),
    );
  }
}
