import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_grid_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rotate pages of the open document, then apply once to the session copy.
class ViewerRotatePagesPanel extends ConsumerStatefulWidget {
  const ViewerRotatePagesPanel({
    super.key,
    required this.handoff,
    this.pageCount,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerRotatePagesPanel> createState() =>
      _ViewerRotatePagesPanelState();
}

class _ViewerRotatePagesPanelState extends ConsumerState<ViewerRotatePagesPanel> {
  List<OrganizePageRef> _pages = const [];
  final Set<String> _selected = {};
  bool _busy = false;
  int _thumbGen = 0;

  @override
  void initState() {
    super.initState();
    _reset(selectCurrent: true);
  }

  @override
  void didUpdateWidget(covariant ViewerRotatePagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pageCount != widget.pageCount ||
        oldWidget.handoff.file.path != widget.handoff.file.path) {
      _reset(selectCurrent: true);
      _thumbGen++;
    }
  }

  int get _currentPage {
    final total = widget.pageCount ?? 1;
    return widget.handoff.currentPage1.clamp(1, total < 1 ? 1 : total);
  }

  void _reset({required bool selectCurrent, LocalFileRef? file, int? count}) {
    final n = count ?? widget.pageCount ?? 0;
    final kept = <int>{
      for (var i = 0; i < _pages.length; i++)
        if (_selected.contains(_pages[i].id)) i,
    };
    _pages = buildDocumentPageList(file ?? widget.handoff.file, n);
    _selected.clear();
    if (_pages.isEmpty) return;
    if (!selectCurrent && kept.isNotEmpty) {
      for (final i in kept) {
        if (i >= 0 && i < _pages.length) _selected.add(_pages[i].id);
      }
      return;
    }
    final page = _currentPage;
    if (page >= 1 && page <= _pages.length) {
      _selected.add(_pages[page - 1].id);
    }
  }

  bool get _changed => _pages.any((p) => p.rotationDegrees != 0);

  int _normRot(int degrees) => ((degrees % 360) + 360) % 360;

  void _toggle(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _rotateSelected(int delta) {
    if (_selected.isEmpty || _busy) return;
    setState(() {
      _pages = [
        for (final p in _pages)
          _selected.contains(p.id)
              ? p.copyWith(
                  rotationDegrees: _normRot(p.rotationDegrees + delta),
                )
              : p,
      ];
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      final turned = _pages.where((p) => p.rotationDegrees != 0).length;
      await commitOrganizePagesInSession(
        ref: ref,
        context: context,
        handoff: widget.handoff,
        pages: _pages,
        successMessage: turned == 1
            ? 'Rotated 1 page.'
            : 'Rotated $turned pages.',
      );
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      setState(() {
        _thumbGen++;
        _reset(
          selectCurrent: false,
          file: session?.file ?? widget.handoff.file,
          count: _pages.length,
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_pages.isEmpty) {
      final total = widget.pageCount;
      if (total == null) {
        return const Center(child: CircularProgressIndicator.adaptive());
      }
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpacing.md),
          child: Text(
            total < 1 ? 'This PDF has no pages to rotate.' : 'Waiting for page list…',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    final hasSelection = _selected.isNotEmpty;
    return ViewerPageGridScaffold(
      applyKey: const Key('viewer_rotate_apply'),
      applyLabel: _busy ? 'Applying…' : 'Apply',
      onApply: _busy || !_changed ? null : _apply,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpacing.md,
          DsSpacing.sm,
          DsSpacing.md,
          0,
        ),
        child: Text(
          hasSelection
              ? '${_selected.length} selected'
              : 'Select pages, rotate, then apply',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      toolbar: [
        viewerPageToolButton(
          key: const Key('viewer_rotate_left_apply'),
          icon: Icons.rotate_left_rounded,
          label: 'Left',
          onPressed: _busy || !hasSelection ? null : () => _rotateSelected(-90),
        ),
        viewerPageToolButton(
          icon: Icons.rotate_right_rounded,
          label: 'Right',
          onPressed: _busy || !hasSelection ? null : () => _rotateSelected(90),
        ),
        viewerPageToolButton(
          icon: Icons.flip,
          label: '180°',
          onPressed: _busy || !hasSelection ? null : () => _rotateSelected(180),
        ),
        viewerPageToolButton(
          icon: Icons.select_all_rounded,
          label: 'All',
          onPressed: _busy
              ? null
              : () => setState(() {
                    _selected
                      ..clear()
                      ..addAll(_pages.map((p) => p.id));
                  }),
        ),
        viewerPageToolButton(
          icon: Icons.deselect_rounded,
          label: 'Clear',
          onPressed: _busy || !hasSelection
              ? null
              : () => setState(_selected.clear),
        ),
      ],
      body: ViewerPageThumbnailGrid(
        itemCount: _pages.length,
        itemBuilder: (context, i) {
          final page = _pages[i];
          final selected = _selected.contains(page.id);
          final turned = page.rotationDegrees != 0;
          final label = turned
              ? '${i + 1} · ${page.rotationDegrees}°'
              : '${i + 1}';
          return ViewerPageThumbTile(
            label: label,
            selected: selected,
            onTap: _busy ? null : () => _toggle(page.id),
            child: AnimatedRotation(
              turns: page.rotationDegrees / 360,
              duration: DsMotion.switchDuration,
              child: OrganizeCachedPageThumbnail(
                key: ValueKey(
                  '${page.file.path}#${page.pageNumber1Based}#$_thumbGen',
                ),
                file: page.file,
                pageNumber1Based: page.pageNumber1Based,
                password: widget.handoff.password,
              ),
            ),
          );
        },
      ),
    );
  }
}
