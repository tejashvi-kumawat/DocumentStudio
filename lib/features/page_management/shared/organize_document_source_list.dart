import 'package:document_studio/design_system/ds_colors.dart';
import 'package:flutter/material.dart';

/// One row in a document-level source list (merge, batch inputs, etc.).
class OrganizeDocumentSourceEntry {
  OrganizeDocumentSourceEntry({
    required this.id,
    required this.displayName,
    this.pageCountLabel,
    this.loading = false,
  });

  final String id;
  final String displayName;
  final String? pageCountLabel;
  final bool loading;
}

/// Compact reorderable list of PDF sources — document-level tools only.
class OrganizeDocumentSourceList extends StatelessWidget {
  const OrganizeDocumentSourceList({
    super.key,
    required this.sources,
    required this.onReorder,
    required this.onRemove,
    this.onItemTap,
    this.enabled = true,
  });

  final List<OrganizeDocumentSourceEntry> sources;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(int index) onRemove;
  final void Function(int index)? onItemTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: sources.length,
        onReorder: enabled ? onReorder : (_, __) {},
        itemBuilder: (context, index) {
          final s = sources[index];
          final pages = s.loading
              ? '…'
              : (s.pageCountLabel ?? '—');
          return ListTile(
            key: ValueKey(s.id),
            dense: true,
            onTap: onItemTap == null ? null : () => onItemTap!(index),
            visualDensity: VisualDensity.compact,
            leading: ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                size: 20,
                color: enabled ? null : theme.disabledColor,
              ),
            ),
            title: Text(
              s.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(pages, style: theme.textTheme.bodySmall),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: enabled ? () => onRemove(index) : null,
            ),
          );
        },
      ),
    );
  }
}
