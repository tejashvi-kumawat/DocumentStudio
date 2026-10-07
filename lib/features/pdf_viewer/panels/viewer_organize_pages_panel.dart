import 'package:document_studio/app/keyboard/text_input_guard.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/organize_page_ref.dart';
import 'package:document_studio/features/page_management/widgets/organize_page_thumbnail.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_grid_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_export.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_page_organize_logic.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_panel_scope.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rearrange the open document from its page thumbnails.
///
/// Click selects a thumbnail. Shift-click extends the range. Ctrl or Cmd
/// click toggles. Drag a thumbnail to reorder. Ctrl+Delete (Linux) or
/// Cmd+Delete / Cmd+Backspace (macOS) deletes the selection. Rotate,
/// duplicate, and the other actions use that same selection. Apply writes
/// the session working copy.
class ViewerOrganizePagesPanel extends ConsumerStatefulWidget {
  const ViewerOrganizePagesPanel({
    super.key,
    required this.handoff,
    this.pageCount,
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerOrganizePagesPanel> createState() =>
      _ViewerOrganizePagesPanelState();
}

class _ViewerOrganizePagesPanelState
    extends ConsumerState<ViewerOrganizePagesPanel> {
  List<OrganizePageRef> _pages = const [];
  List<OrganizePageRef> _original = const [];
  final Set<String> _selected = {};
  int? _anchor;
  final ValueNotifier<int?> _dropBefore = ValueNotifier<int?>(null);
  bool _busy = false;
  int _thumbGen = 0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onDeleteChord);
    _reset();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onDeleteChord);
    _dropBefore.dispose();
    super.dispose();
  }

  /// Ctrl+Delete on Linux. Cmd+Delete and Cmd+Backspace on macOS.
  bool _onDeleteChord(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted || TextInputGuard.isTyping) {
      return false;
    }
    final key = event.logicalKey;
    final hw = HardwareKeyboard.instance;
    final mac = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
    final chord = mac
        ? hw.isMetaPressed &&
              (key == LogicalKeyboardKey.delete ||
                  key == LogicalKeyboardKey.backspace)
        : hw.isControlPressed && key == LogicalKeyboardKey.delete;
    if (!chord) return false;
    _deleteSelected();
    return true;
  }

  @override
  void didUpdateWidget(covariant ViewerOrganizePagesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final pathChanged = oldWidget.handoff.file.path != widget.handoff.file.path;
    final countChanged = oldWidget.pageCount != widget.pageCount;
    if (_busy || (!pathChanged && !countChanged)) return;
    // Apply rewrites the working path before the viewer reports a new
    // page count (delete). Keep the list just committed.
    final awaitingCount =
        pathChanged &&
        !countChanged &&
        widget.pageCount != null &&
        widget.pageCount != _pages.length;
    if (awaitingCount) return;
    _reset();
    _selected.clear();
    _anchor = null;
    _thumbGen++;
  }

  void _reset({LocalFileRef? file, int? count}) {
    final n = count ?? widget.pageCount ?? 0;
    _original = buildDocumentPageList(file ?? widget.handoff.file, n);
    _pages = [..._original];
  }

  bool get _changed {
    if (_pages.length != _original.length) return true;
    for (var i = 0; i < _pages.length; i++) {
      if (_pages[i] != _original[i]) return true;
    }
    return false;
  }

  int _normRot(int degrees) => ((degrees % 360) + 360) % 360;

  void _move(OrganizePageRef page, int before) {
    final from = _pages.indexOf(page);
    if (from < 0) return;
    final next = [..._pages]..removeAt(from);
    final to = (before > from ? before - 1 : before).clamp(0, next.length);
    next.insert(to, page);
    _dropBefore.value = null;
    setState(() => _pages = next);
  }

  void _onTileTap(int index) {
    if (_busy || index < 0 || index >= _pages.length) return;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final shift =
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
    final toggle =
        keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    final id = _pages[index].id;
    setState(() {
      if (shift) {
        final anchor = _anchor;
        if (anchor == null || anchor < 0 || anchor >= _pages.length) {
          _selected
            ..clear()
            ..add(id);
          _anchor = index;
          return;
        }
        final lo = anchor < index ? anchor : index;
        final hi = anchor < index ? index : anchor;
        _selected
          ..clear()
          ..addAll([for (var i = lo; i <= hi; i++) _pages[i].id]);
        return;
      }
      if (toggle) {
        if (!_selected.add(id)) _selected.remove(id);
        _anchor = index;
        return;
      }
      _selected
        ..clear()
        ..add(id);
      _anchor = index;
    });
  }

  void _rotateSelected(int delta) {
    if (_selected.isEmpty || _busy) return;
    setState(() {
      _pages = [
        for (final p in _pages)
          _selected.contains(p.id)
              ? p.copyWith(rotationDegrees: _normRot(p.rotationDegrees + delta))
              : p,
      ];
    });
  }

  void _deleteSelected() {
    if (_selected.isEmpty || _busy) return;
    if (_selected.length >= _pages.length) {
      _snack('A PDF needs at least one page.');
      return;
    }
    setState(() {
      _pages = [
        for (final p in _pages)
          if (!_selected.contains(p.id)) p,
      ];
      _selected.clear();
      _anchor = null;
    });
  }

  void _selectAll() {
    if (_busy) return;
    setState(() {
      _selected
        ..clear()
        ..addAll(_pages.map((p) => p.id));
    });
  }

  /// Blank page after the last selected page (or at the end).
  Future<void> _insertBlank() async {
    if (_busy) return;
    final blank = await ref.read(blankPageFactoryProvider).blankPageFile();
    if (!mounted) return;
    var at = _pages.length;
    for (var i = _pages.length - 1; i >= 0; i--) {
      if (_selected.contains(_pages[i].id)) {
        at = i + 1;
        break;
      }
    }
    setState(() {
      _pages = [..._pages]..insert(at, OrganizePageRef.fromFilePage(blank, 1));
    });
  }

  void _duplicateSelected() {
    if (_selected.isEmpty || _busy) return;
    final next = <OrganizePageRef>[];
    for (final p in _pages) {
      next.add(p);
      if (_selected.contains(p.id)) {
        next.add(
          OrganizePageRef.fromFilePage(
            p.file,
            p.pageNumber1Based,
          ).copyWith(rotationDegrees: p.rotationDegrees),
        );
      }
    }
    setState(() => _pages = next);
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    try {
      await commitOrganizePagesInSession(
        ref: ref,
        context: context,
        handoff: widget.handoff,
        pages: _pages,
        successMessage: 'Pages rearranged.',
      );
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      final count = _pages.length;
      setState(() {
        _thumbGen++;
        _selected.clear();
        _anchor = null;
        _reset(file: session?.file ?? widget.handoff.file, count: count);
      });
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
            total < 1
                ? 'This PDF has no pages to organize.'
                : 'Waiting for page list…',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }
    final hasSelection = _selected.isNotEmpty;
    final mac = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => true,
      _ => false,
    };
    return ViewerPageGridScaffold(
      applyKey: const Key('viewer_organize_apply'),
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
              ? '${_selected.length} selected — drag to reorder'
              : mac
              ? 'Click to select. Drag to reorder. ⌘ Delete removes.'
              : 'Click to select. Drag to reorder. Ctrl+Delete removes.',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      toolbar: [
        viewerPageToolButton(
          icon: Icons.select_all,
          label: 'Select all',
          onPressed: _busy ? null : _selectAll,
        ),
        viewerPageToolButton(
          icon: Icons.note_add_outlined,
          label: 'Blank page',
          onPressed: _busy ? null : _insertBlank,
        ),
        viewerPageToolButton(
          icon: Icons.upload_file_outlined,
          label: 'Insert file',
          onPressed: _busy || _changed
              ? null
              : () =>
                    openViewerToolPanel(context, ViewerToolId.workspaceInsert),
        ),
        viewerPageToolButton(
          icon: Icons.content_cut,
          label: 'Extract',
          onPressed: _busy || _changed
              ? null
              : () => openViewerToolPanel(context, ViewerToolId.extract),
        ),
        viewerPageToolButton(
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
          icon: Icons.copy_rounded,
          label: 'Duplicate',
          onPressed: _busy || !hasSelection ? null : _duplicateSelected,
        ),
        viewerPageToolButton(
          icon: Icons.delete_outline_rounded,
          label: 'Delete',
          onPressed: _busy || !hasSelection ? null : _deleteSelected,
        ),
        viewerPageToolButton(
          icon: Icons.swap_vert_rounded,
          label: 'Reverse',
          onPressed: _busy
              ? null
              : () => setState(() => _pages = _pages.reversed.toList()),
        ),
        viewerPageToolButton(
          icon: Icons.restart_alt_rounded,
          label: 'Reset',
          onPressed: _busy || !_changed
              ? null
              : () => setState(() {
                  _pages = [..._original];
                  _selected.clear();
                  _anchor = null;
                }),
        ),
      ],
      body: ViewerPageThumbnailGrid(
        itemCount: _pages.length,
        itemBuilder: (context, i) => _tile(context, i),
      ),
    );
  }

  Widget _tile(BuildContext context, int i) {
    final page = _pages[i];
    return ValueListenableBuilder<int?>(
      valueListenable: _dropBefore,
      builder: (context, dropBefore, _) {
        final moved = page.pageNumber1Based != i + 1;
        final label = moved
            ? '${i + 1} · was ${page.pageNumber1Based}'
            : '${i + 1}';
        final thumb = ViewerPageThumbTile(
          label: label,
          selected: _selected.contains(page.id) || dropBefore == i,
          onTap: () => _onTileTap(i),
          child: AnimatedRotation(
            turns: page.rotationDegrees / 360,
            duration: DsMotion.switchDuration,
            child: OrganizeCachedPageThumbnail(
              key: ValueKey(
                '${page.file.path}#${page.pageNumber1Based}#${page.id}#$_thumbGen',
              ),
              file: page.file,
              pageNumber1Based: page.pageNumber1Based,
              password: widget.handoff.password,
            ),
          ),
        );
        return DragTarget<OrganizePageRef>(
          onWillAcceptWithDetails: (d) {
            if (identical(d.data, page) || d.data.id == page.id) return false;
            if (_dropBefore.value != i) _dropBefore.value = i;
            return true;
          },
          onLeave: (_) {
            if (_dropBefore.value == i) _dropBefore.value = null;
          },
          onAcceptWithDetails: (d) {
            final from = _pages.indexWhere((p) => p.id == d.data.id);
            _move(d.data, from >= 0 && from < i ? i + 1 : i);
          },
          builder: (context, _, _) => Draggable<OrganizePageRef>(
            data: page,
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: 110,
                height: 150,
                child: Opacity(opacity: 0.9, child: thumb),
              ),
            ),
            childWhenDragging: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: DsColors.border(Theme.of(context).brightness),
                ),
                borderRadius: BorderRadius.circular(DsSpacing.radiusButton),
              ),
            ),
            onDragEnd: (_) => _dropBefore.value = null,
            child: MouseRegion(cursor: SystemMouseCursors.grab, child: thumb),
          ),
        );
      },
    );
  }
}
