import 'package:document_studio/features/page_management/organize_tool_catalog.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

class CommandPaletteItem {
  const CommandPaletteItem({
    required this.id,
    required this.label,
    required this.subtitle,
    required this.onInvoke,
    this.keywords = const [],
  });

  final String id;
  final String label;
  final String subtitle;
  final VoidCallback onInvoke;
  final List<String> keywords;
}

/// ⌘/Ctrl+K command launcher (organize tools + navigation).
Future<void> showDocumentStudioCommandPalette(
  BuildContext context, {
  List<CommandPaletteItem> leadingItems = const [],
}) async {
  final items = <CommandPaletteItem>[
    ...leadingItems,
    for (final t in OrganizeToolCatalog.tools)
      if (t.availability == OrganizeToolAvailability.available)
        CommandPaletteItem(
          id: t.id,
          label: t.label,
          subtitle: t.description,
          keywords: [t.group.name, 'organize'],
          onInvoke: () => context.push(t.routePath),
        ),
    CommandPaletteItem(
      id: 'organize_hub',
      label: 'Organize tools',
      subtitle: 'Open the Organize toolbox',
      keywords: ['tools', 'pages'],
      onInvoke: () => context.push(OrganizeToolCatalog.hubPath),
    ),
    CommandPaletteItem(
      id: 'home',
      label: 'Home',
      subtitle: 'Document Studio home',
      keywords: ['start'],
      onInvoke: () => context.go('/'),
    ),
  ];

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _CommandPaletteDialog(items: items),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.items});

  final List<CommandPaletteItem> items;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  String _query = '';
  int _highlight = 0;

  List<CommandPaletteItem> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return widget.items.where((item) {
      if (item.label.toLowerCase().contains(q)) return true;
      if (item.subtitle.toLowerCase().contains(q)) return true;
      return item.keywords.any((k) => k.toLowerCase().contains(q));
    }).toList();
  }

  void _run(CommandPaletteItem item) {
    Navigator.pop(context);
    item.onInvoke();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = _filtered;
    if (_highlight >= list.length) _highlight = list.isEmpty ? 0 : list.length - 1;

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.arrowDown): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp): const ActivateIntent(),
        LogicalKeySet(LogicalKeyboardKey.enter): const ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            // handled in TextField onSubmitted / key
            return null;
          }),
        },
        child: Dialog(
          alignment: Alignment.topCenter,
          insetPadding: const EdgeInsets.only(top: 80, left: 24, right: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Focus(
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Search commands…',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (v) => setState(() {
                        _query = v;
                        _highlight = 0;
                      }),
                      onSubmitted: (_) {
                        if (list.isNotEmpty) _run(list[_highlight]);
                      },
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final item = list[i];
                      final selected = i == _highlight;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(item.label, style: theme.textTheme.titleSmall),
                        subtitle: Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _run(item),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ignore: depend_on_referenced_packages
