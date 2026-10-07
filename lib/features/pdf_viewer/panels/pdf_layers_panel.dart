import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter/material.dart';

/// Canva-style layer list for the page in view: every text block, picture,
/// shape and comment Edit found, top-most first. Click a row to select it on
/// the page; the bin removes exactly that object.
class PdfLayersPanel extends StatelessWidget {
  const PdfLayersPanel({
    super.key,
    required this.session,
    required this.onEnableEdit,
  });

  final ViewerLiveToolSession session;
  final VoidCallback onEnableEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final theme = Theme.of(context);
        if (session.toolId != ViewerToolId.editText) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 36,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Layers list every text block, picture, shape and comment on the page.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onEnableEdit,
                    icon: const Icon(Icons.edit_document, size: 18),
                    label: const Text('Turn on Edit'),
                  ),
                ],
              ),
            ),
          );
        }
        final page = session.pageIndex1Based;
        final texts = session.textRunsForPage(page);
        final objects = session.imagesForPage(page);
        final annots = [
          for (final o in objects)
            if (o.kind == EditableKind.annotation) o,
        ];
        final images = [
          for (final o in objects)
            if (o.kind == EditableKind.image) o,
        ];
        final shapes = [
          for (final o in objects)
            if (o.kind == EditableKind.shape) o,
        ];
        final rows = <Widget>[
          _header(
            theme,
            'Page $page',
            '${texts.length + objects.length} layers',
          ),
          if (annots.isNotEmpty) _section(theme, 'Comments & drawings'),
          for (final a in annots) _objectRow(context, a, Icons.draw_outlined),
          if (texts.isNotEmpty) _section(theme, 'Text'),
          for (final t in texts) _textRow(context, t),
          if (images.isNotEmpty) _section(theme, 'Pictures'),
          for (final i in images) _objectRow(context, i, Icons.image_outlined),
          if (shapes.isNotEmpty) _section(theme, 'Shapes (${shapes.length})'),
          for (final sh in shapes.take(150))
            _objectRow(context, sh, Icons.category_outlined),
          if (shapes.length > 150)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '${shapes.length - 150} more small shapes — select them on the page.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (texts.isEmpty && objects.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Reading this page…',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ];
        return ListView(
          padding: const EdgeInsets.only(bottom: 12),
          children: rows,
        );
      },
    );
  }

  Widget _header(ThemeData theme, String title, String sub) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
    child: Row(
      children: [
        Text(title, style: theme.textTheme.titleSmall),
        const Spacer(),
        Text(sub, style: theme.textTheme.labelSmall),
      ],
    ),
  );

  Widget _section(ThemeData theme, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
    child: Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        letterSpacing: 0.7,
        fontWeight: FontWeight.w700,
        color: DsColors.primary,
      ),
    ),
  );

  Widget _textRow(BuildContext context, LiveTextEditTarget t) {
    final sel = session.selectedRun;
    final selected =
        sel != null &&
        sel.originalText == t.originalText &&
        (sel.hitRect.center - t.hitRect.center).distance < 1e-4;
    final first = t.originalText.replaceAll('\n', ' ').trim();
    return _Row(
      icon: Icons.text_fields,
      title: first.isEmpty ? '(empty)' : first,
      subtitle:
          '${t.fontSizePt.round()} pt'
          '${t.fontMatch == null ? '' : ' · ${t.fontMatch!.original}'}',
      selected: selected,
      onTap: () => session.selectTextRun(t),
      onEdit: () => session.setTextEditTarget(t),
      onDelete: () {
        session.setTextEditTarget(t);
        session.setLabelText('');
        session.requestTextCommit();
      },
    );
  }

  Widget _objectRow(BuildContext context, EditableImage o, IconData icon) {
    final sel = session.selectedImage;
    final selected =
        sel != null &&
        sel.kind == o.kind &&
        sel.form == o.form &&
        sel.opStart == o.opStart;
    final r = o.normRect;
    return _Row(
      icon: icon,
      title: o.label,
      subtitle:
          '${(r.width * 100).round()}% × ${(r.height * 100).round()}% of page'
          '${o.form != 0 ? ' · in a group' : ''}',
      selected: selected,
      onTap: () => session.selectImage(o),
      onDelete: () {
        session.imageEditHandler?.call(
          ImageEditRequest(ImageEditKind.delete, o),
        );
        session.selectImage(null);
      },
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.onDelete,
    this.onEdit,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback? onEdit;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: widget.selected
            ? DsColors.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onEdit,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: widget.selected
                      ? DsColors.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                if (_hover || widget.selected) ...[
                  if (widget.onEdit != null)
                    IconButton(
                      tooltip: 'Edit text',
                      iconSize: 16,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: widget.onEdit,
                    ),
                  IconButton(
                    tooltip: 'Delete this layer',
                    iconSize: 16,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onDelete,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
