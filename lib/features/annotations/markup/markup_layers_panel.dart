import 'package:document_studio/domain/pdf_markup/markup_objects.dart';
import 'package:document_studio/features/annotations/markup/markup_editor_controller.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_markup_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

IconData markupTypeIcon(MarkupObject o) => switch (o) {
  TextBoxMarkup() =>
    o.isCallout ? Icons.chat_bubble_outline : Icons.text_fields,
  ImageMarkup() => Icons.image_outlined,
  InkMarkup() =>
    o.highlighter ? Icons.border_color_outlined : Icons.draw_outlined,
  ShapeMarkup() => switch (o.kind) {
    ShapeKind.rectangle => Icons.crop_square,
    ShapeKind.ellipse => Icons.circle_outlined,
    ShapeKind.line => Icons.horizontal_rule,
    ShapeKind.arrow => Icons.arrow_right_alt,
    ShapeKind.polygon => Icons.pentagon_outlined,
    ShapeKind.cloud => Icons.cloud_outlined,
  },
  TextMarkupMarkup() => switch (o.kind) {
    TextMarkupKind.highlight => Icons.highlight,
    TextMarkupKind.underline => Icons.format_underline,
    TextMarkupKind.strikeout => Icons.format_strikethrough,
    TextMarkupKind.squiggly => Icons.waves,
  },
  NoteMarkup() => Icons.sticky_note_2_outlined,
  LinkMarkup() => Icons.link,
};

/// Layers: every object grouped by page (top of the stack first). Click to
/// select and scroll to it; rename, hide, lock, delete, drag to reorder.
class MarkupLayersPanel extends StatelessWidget {
  const MarkupLayersPanel({
    super.key,
    required this.controller,
    required this.onReveal,
    this.onClose,
  });

  final MarkupEditorController controller;

  /// Scroll the viewer to [page] / [bounds] (display points) and open the
  /// editor so the object shows its handles.
  final void Function(int page, Rect bounds) onReveal;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final c = controller;
    final pages = {
      ...c.pagesWithObjects,
      for (final f in c.foreign) f.page,
    }.toList()..sort();
    final count = c.objectCount;
    return Material(
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 4, 6),
            child: Row(
              children: [
                const Icon(Icons.layers_outlined, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Layers', style: theme.textTheme.titleSmall),
                ),
                Text(
                  count == 1 ? '1 object' : '$count objects',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    tooltip: 'Close layers',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: c.loading && count == 0
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : pages.isEmpty
                ? _empty(context)
                : ListView(
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      for (final p in pages) ..._pageSection(context, p),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.layers_clear_outlined,
            size: 36,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 10),
          Text('No markup yet', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'Text, images, shapes, highlights, notes and links you add appear '
            'here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _pageSection(BuildContext context, int page) {
    final theme = Theme.of(context);
    final c = controller;
    final objs = c.objectsOn(page);
    final foreign = c.foreign.where((f) => f.page == page).toList();
    final n = objs.length;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
        child: Text(
          'PAGE $page',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 0.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      if (n > 0)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: n,
          proxyDecorator: (child, index, animation) => Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
          onReorderItem: (from, to) {
            // Displayed top-first; the stack is stored back-to-front.
            c.reorder(page, n - 1 - from, n - 1 - to);
          },
          itemBuilder: (context, i) {
            final o = objs[n - 1 - i];
            return _LayerRow(
              key: ValueKey(o.id),
              index: i,
              object: o,
              selected: c.isSelected(o.id),
              controller: c,
              onTap: () {
                onReveal(o.page, o.bounds);
                if (!o.hidden) {
                  c.select(
                    o.id,
                    additive: HardwareKeyboard.instance.isShiftPressed,
                  );
                }
                c.reveal.value = null;
                c.reveal.value = o.id;
              },
            );
          },
        ),
      for (final f in foreign)
        _ForeignRow(
          annotation: f,
          readOnly: c.readOnly,
          onTap: () => onReveal(f.page, f.rect),
          onDelete: () => c.deleteForeign(f),
        ),
    ];
  }
}

class _LayerRow extends StatefulWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.object,
    required this.selected,
    required this.controller,
    required this.onTap,
  });

  final int index;
  final MarkupObject object;
  final bool selected;
  final MarkupEditorController controller;
  final VoidCallback onTap;

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _renaming = false;
  late final TextEditingController _name = TextEditingController(
    text: widget.object.label,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'layerRename');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _renaming) _commit();
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startRename() {
    _name.text = widget.object.label;
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _commit() {
    final v = _name.text.trim();
    setState(() => _renaming = false);
    if (v != widget.object.label) {
      widget.controller.rename(
        widget.object.id,
        v == widget.object.defaultLabel ? '' : v,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final o = widget.object;
    final c = widget.controller;
    final dim = o.hidden;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: widget.selected
            ? cs.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          onDoubleTap: o.locked ? null : _startRename,
          child: SizedBox(
            height: 38,
            child: Row(
              children: [
                ReorderableDragStartListener(
                  index: widget.index,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.grab,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.drag_indicator,
                        size: 16,
                        color: cs.outline,
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(o.color | 0xFF000000).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    markupTypeIcon(o),
                    size: 14,
                    color: Color(o.color | 0xFF000000),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _renaming
                      ? TextField(
                          controller: _name,
                          focusNode: _focus,
                          style: theme.textTheme.bodyMedium,
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                          ),
                          onSubmitted: (_) => _commit(),
                        )
                      : Text(
                          o.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: dim ? cs.outline : null,
                            fontStyle: dim ? FontStyle.italic : null,
                          ),
                        ),
                ),
                _MiniIcon(
                  tooltip: o.hidden ? 'Show' : 'Hide',
                  icon: o.hidden
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  active: o.hidden,
                  onPressed: c.readOnly
                      ? null
                      : () => c.setHidden(o.id, !o.hidden),
                ),
                _MiniIcon(
                  tooltip: o.locked ? 'Unlock' : 'Lock',
                  icon: o.locked ? Icons.lock : Icons.lock_open_outlined,
                  active: o.locked,
                  onPressed: c.readOnly
                      ? null
                      : () => c.setLocked(o.id, !o.locked),
                ),
                PopupMenuButton<String>(
                  tooltip: 'More',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_horiz,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _startRename();
                      case 'delete':
                        c.deleteObjects({o.id});
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'rename',
                      enabled: !o.locked,
                      child: const Text('Rename'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      enabled: !o.locked && !c.readOnly,
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIcon extends StatelessWidget {
  const _MiniIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      padding: EdgeInsets.zero,
      iconSize: 16,
      color: active ? cs.primary : cs.onSurfaceVariant,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}

class _ForeignRow extends StatelessWidget {
  const _ForeignRow({
    required this.annotation,
    required this.readOnly,
    required this.onTap,
    required this.onDelete,
  });

  final ForeignAnnotation annotation;
  final bool readOnly;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Row(
            children: [
              const SizedBox(width: 26),
              Icon(Icons.comment_outlined, size: 16, color: cs.outline),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message:
                      'Created by another app — can be deleted, not edited',
                  child: Text(
                    annotation.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              if (annotation.refNum != null && !readOnly)
                _MiniIcon(
                  tooltip: 'Delete',
                  icon: Icons.delete_outline,
                  onPressed: onDelete,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
