import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/features/annotations/annotation_list_filter.dart';
import 'package:document_studio/features/annotations/annotation_port.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_annotation_adapter.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Comments / annotations side panel (DS-ANN-006). Wire from the PDF viewer shell.
///
/// Uses [PdfViewerController.useDocument] so listing does not reopen the file.
class AnnotationListPanel extends StatefulWidget {
  const AnnotationListPanel({
    super.key,
    required this.controller,
    this.adapter,
    this.onAnnotationSelected,
    this.width = 280,
  });

  final PdfViewerController controller;
  final PdfrxAnnotationAdapter? adapter;
  final ValueChanged<PdfMarkupAnnotation>? onAnnotationSelected;
  final double width;

  static const panelWidth = 280.0;

  @override
  State<AnnotationListPanel> createState() => _AnnotationListPanelState();
}

class _AnnotationListPanelState extends State<AnnotationListPanel> {
  late PdfrxAnnotationAdapter _adapter;

  List<PdfMarkupAnnotation> _items = const [];
  String? _error;
  bool _loading = true;
  String? _selectedId;
  AnnotationListFilterState _filter = const AnnotationListFilterState();

  @override
  void initState() {
    super.initState();
    _adapter = widget.adapter ?? PdfrxAnnotationAdapter();
    _reload();
  }

  @override
  void didUpdateWidget(covariant AnnotationListPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.adapter != widget.adapter) {
      _adapter = widget.adapter ?? PdfrxAnnotationAdapter();
      _reload();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await widget.controller.useDocument(
        (document) => _adapter.listFromOpenDocument(document),
      );
      if (!mounted) return;
      final items = list ?? const <PdfMarkupAnnotation>[];
      setState(() {
        _items = items;
        _loading = false;
        if (_selectedId != null && !items.any((a) => a.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _items = const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _items = const [];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final caps = _adapter.capabilities;
    final theme = Theme.of(context);

    return Material(
      elevation: 1,
      child: SizedBox(
        width: widget.width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Annotations',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh list',
                    onPressed: _loading ? null : _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            if (!caps.canAuthor)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Text(
                  'Read-only — authoring blocked until PDFium annot FFI.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (caps.listLimitation != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  caps.listLimitation!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: TextField(
                key: const Key('annotation_list_search'),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search annotations…',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() => _filter = _filter.copyWith(query: value));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: DropdownButtonFormField<AnnotationKindFilter>(
                key: const Key('annotation_list_kind_filter'),
                isExpanded: true,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                initialValue: _filter.kindFilter,
                items: AnnotationKindFilter.values
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(annotationKindFilterLabel(f)),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _filter = _filter.copyWith(kindFilter: value));
                },
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No annotations found in this document.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final visible = filterAnnotationList(_items, _filter);
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No annotations match your search or filter.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      key: const Key('annotation_list_panel'),
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = visible[index];
        final selected = item.id == _selectedId;
        return ListTile(
          selected: selected,
          leading: Icon(_iconForKind(item.kind)),
          title: Text(
            item.displayLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('Page ${item.pageNumber} · ${_kindLabel(item.kind)}'),
          onTap: () {
            setState(() => _selectedId = item.id);
            widget.onAnnotationSelected?.call(item);
          },
        );
      },
    );
  }

  static IconData _iconForKind(PdfAnnotationKind kind) => switch (kind) {
        PdfAnnotationKind.highlight => Icons.highlight,
        PdfAnnotationKind.underline => Icons.format_underlined,
        PdfAnnotationKind.strikeOut => Icons.format_strikethrough,
        PdfAnnotationKind.squiggly => Icons.flutter_dash,
        PdfAnnotationKind.text || PdfAnnotationKind.freeText => Icons.text_fields,
        PdfAnnotationKind.ink => Icons.draw,
        PdfAnnotationKind.stamp => Icons.approval,
        PdfAnnotationKind.comment => Icons.comment,
        PdfAnnotationKind.uriLink => Icons.link,
        PdfAnnotationKind.destinationLink => Icons.subdirectory_arrow_right,
        PdfAnnotationKind.unknown => Icons.note_alt_outlined,
      };

  static String _kindLabel(PdfAnnotationKind kind) => switch (kind) {
        PdfAnnotationKind.highlight => 'Highlight',
        PdfAnnotationKind.underline => 'Underline',
        PdfAnnotationKind.strikeOut => 'Strike out',
        PdfAnnotationKind.squiggly => 'Squiggly',
        PdfAnnotationKind.text => 'Text',
        PdfAnnotationKind.freeText => 'Text box',
        PdfAnnotationKind.ink => 'Ink',
        PdfAnnotationKind.stamp => 'Stamp',
        PdfAnnotationKind.comment => 'Comment',
        PdfAnnotationKind.uriLink => 'Web link',
        PdfAnnotationKind.destinationLink => 'Internal link',
        PdfAnnotationKind.unknown => 'Annotation',
      };
}
