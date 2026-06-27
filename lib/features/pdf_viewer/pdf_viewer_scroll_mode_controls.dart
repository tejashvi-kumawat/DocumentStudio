import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:flutter/material.dart';

/// Toolbar control for scroll layout modes (DS-READ-003-A/B/C).
class PdfViewerScrollModeToolbarControl extends StatelessWidget {
  const PdfViewerScrollModeToolbarControl({
    super.key,
    required this.mode,
    required this.onModeChanged,
    this.enabled = true,
    this.dense = false,
  });

  final PdfViewerScrollLayoutMode mode;
  final ValueChanged<PdfViewerScrollLayoutMode> onModeChanged;
  final bool enabled;
  final bool dense;

  static const _segmentBreakpoint = 880.0;

  IconData get _icon => switch (mode) {
        PdfViewerScrollLayoutMode.continuous => Icons.article_outlined,
        PdfViewerScrollLayoutMode.singlePage => Icons.view_agenda_outlined,
        PdfViewerScrollLayoutMode.twoPage => Icons.menu_book_outlined,
      };

  String get _tooltip => switch (mode) {
        PdfViewerScrollLayoutMode.continuous => 'Continuous scroll',
        PdfViewerScrollLayoutMode.singlePage => 'Single page',
        PdfViewerScrollLayoutMode.twoPage => 'Two page spread',
      };

  Future<void> _openMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final selected = await showMenu<PdfViewerScrollLayoutMode>(
      context: context,
      position: position,
      items: [
        _menuItem(
          PdfViewerScrollLayoutMode.continuous,
          'Continuous scroll',
          Icons.article_outlined,
        ),
        _menuItem(
          PdfViewerScrollLayoutMode.singlePage,
          'Single page',
          Icons.view_agenda_outlined,
        ),
        _menuItem(
          PdfViewerScrollLayoutMode.twoPage,
          'Two page',
          Icons.menu_book_outlined,
        ),
      ],
    );
    if (selected != null && selected != mode) {
      onModeChanged(selected);
    }
  }

  PopupMenuItem<PdfViewerScrollLayoutMode> _menuItem(
    PdfViewerScrollLayoutMode value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          if (mode == value) const Icon(Icons.check, size: 18),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final useSegments =
        MediaQuery.sizeOf(context).width >= _segmentBreakpoint;

    if (useSegments) {
      return DsToolbarSegmentedControl<PdfViewerScrollLayoutMode>(
        key: const Key('pdf_viewer_scroll_mode'),
        dense: dense,
        enabled: enabled,
        selected: mode,
        onSelected: enabled ? onModeChanged : null,
        segments: const [
          DsToolbarSegment(
            value: PdfViewerScrollLayoutMode.continuous,
            icon: Icons.article_outlined,
            tooltip: 'Continuous scroll',
          ),
          DsToolbarSegment(
            value: PdfViewerScrollLayoutMode.singlePage,
            icon: Icons.view_agenda_outlined,
            tooltip: 'Single page',
          ),
          DsToolbarSegment(
            value: PdfViewerScrollLayoutMode.twoPage,
            icon: Icons.menu_book_outlined,
            tooltip: 'Two page spread',
          ),
        ],
      );
    }

    return Builder(
      builder: (context) {
        return DsToolbarIconButton(
          key: const Key('pdf_viewer_scroll_mode'),
          dense: dense,
          tooltip: 'Page layout: $_tooltip',
          icon: _icon,
          selected: mode != PdfViewerScrollLayoutMode.continuous,
          onPressed: enabled ? () => _openMenu(context) : null,
        );
      },
    );
  }
}
