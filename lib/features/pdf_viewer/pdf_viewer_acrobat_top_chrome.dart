import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_tab_bar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_acrobat_page_field.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_tool_row.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_zoom_controls.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Open-PDF chrome: title row, then the grouped tool row.
///
/// Scaffold adds [MediaQuery.padding.top] to this preferred height and this
/// widget pads with [SafeArea] so the title sits below the status bar.
/// Phone passes [showFind] false and no document tabs.
class PdfViewerAcrobatTopChrome extends StatelessWidget
    implements PreferredSizeWidget {
  const PdfViewerAcrobatTopChrome({
    super.key,
    required this.tabs,
    required this.documentTitle,
    this.viewerController,
    this.onBack,
    this.backTooltip = 'Back',
    this.onOpenAnother,
    this.onGoToPage,
    this.onFind,
    this.onFitWidth,
    this.onFitPage,
    this.onManualZoom,
    this.showDocumentTabs = true,
    this.showFind = true,
    this.signPlacementActive = false,
    this.onSignCancel,
    this.onSignDone,
    this.signDoneEnabled = true,
    this.signStatusLabel,
    this.toolRow,
    this.showTitleRow = true,
  });

  static const tabBarHeight = 36.0;
  static const barHeight = 48.0;

  final DocumentTabsController tabs;
  final String documentTitle;
  final PdfViewerController? viewerController;
  final VoidCallback? onBack;
  final String backTooltip;
  final VoidCallback? onOpenAnother;
  final VoidCallback? onGoToPage;
  final VoidCallback? onFind;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitPage;
  final VoidCallback? onManualZoom;
  final bool showDocumentTabs;
  final bool showFind;

  final bool signPlacementActive;
  final VoidCallback? onSignCancel;
  final VoidCallback? onSignDone;
  final bool signDoneEnabled;
  final String? signStatusLabel;

  /// Organize, Crop, Rotate, Edit, Convert, Encrypt, Decrypt, Tools.
  final Widget? toolRow;

  /// File name, page box, zoom and find. Off on desktop, where the tab shows
  /// the name and the bottom bar carries the rest.
  final bool showTitleRow;

  @override
  Size get preferredSize {
    final tabH = (showDocumentTabs && tabs.hasTabs) ? tabBarHeight : 0.0;
    final toolsH = (!signPlacementActive && toolRow != null)
        ? PdfViewerToolRow.height
        : 0.0;
    final titleH = (showTitleRow || signPlacementActive) ? barHeight : 0.0;
    return Size.fromHeight(tabH + titleH + toolsH);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? DsColors.surfaceContainerDark
        : DsColors.surfaceContainerLight;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;

    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDocumentTabs && tabs.hasTabs)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: SizedBox(
                  height: tabBarHeight,
                  child: PdfDocumentTabBar(
                    controller: tabs,
                    onOpenAnother: onOpenAnother,
                  ),
                ),
              ),
            if (showTitleRow || signPlacementActive)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: border)),
                ),
                child: signPlacementActive
                    ? _SignPlacementBar(
                        statusLabel: signStatusLabel,
                        onCancel: onSignCancel,
                        onDone: onSignDone,
                        doneEnabled: signDoneEnabled,
                      )
                    : _TitleRow(
                        title: documentTitle,
                        onBack: onBack,
                        backTooltip: backTooltip,
                        controller: viewerController,
                        onGoToPage: onGoToPage,
                        onFind: showFind ? onFind : null,
                        onFitWidth: onFitWidth,
                        onFitPage: onFitPage,
                        onManualZoom: onManualZoom,
                      ),
              ),
            if (!signPlacementActive && toolRow != null) toolRow!,
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.controller,
    this.onBack,
    this.backTooltip = 'Back',
    this.onGoToPage,
    this.onFind,
    this.onFitWidth,
    this.onFitPage,
    this.onManualZoom,
  });

  final String title;
  final PdfViewerController? controller;
  final VoidCallback? onBack;
  final String backTooltip;
  final VoidCallback? onGoToPage;
  final VoidCallback? onFind;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitPage;
  final VoidCallback? onManualZoom;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: PdfViewerAcrobatTopChrome.barHeight,
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              key: const Key('pdf_viewer_chrome_back'),
              tooltip: backTooltip,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          else
            const SizedBox(width: DsSpacing.sm),
          Expanded(
            child: Text(
              title,
              key: const Key('pdf_viewer_chrome_title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: DsSpacing.xs),
          PdfViewerAcrobatPageField(
            controller: controller,
            onGoToPage: onGoToPage ?? () {},
            fieldHeight: 32,
          ),
          const SizedBox(width: 6),
          _ZoomChip(
            controller: controller,
            onFitWidth: onFitWidth,
            onFitPage: onFitPage,
            onManualZoom: onManualZoom,
          ),
          if (onFind != null)
            IconButton(
              tooltip: 'Find',
              onPressed: onFind,
              icon: const Icon(Icons.search, size: 20),
              style: IconButton.styleFrom(
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            )
          else
            const SizedBox(width: DsSpacing.xs),
        ],
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  const _ZoomChip({
    required this.controller,
    this.onFitWidth,
    this.onFitPage,
    this.onManualZoom,
  });

  final PdfViewerController? controller;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitPage;
  final VoidCallback? onManualZoom;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (ctrl == null) {
      return _chip(context, percent: 100, enabled: false);
    }
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final ready = ctrl.isReady;
        final pct = ready ? (ctrl.value.zoom * 100).round() : 100;
        return _chip(context, percent: pct, enabled: ready);
      },
    );
  }

  Widget _chip(
    BuildContext context, {
    required int percent,
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final border = isDark ? DsColors.borderDark : DsColors.borderLight;
    final bg = isDark ? DsColors.surfaceDark : DsColors.surfaceLight;

    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          onPressed: enabled
              ? () {
                  final c = controller;
                  if (c == null) return;
                  onManualZoom?.call();
                  pdfViewerZoomIn(c);
                }
              : null,
          child: const Text('Zoom in'),
        ),
        MenuItemButton(
          onPressed: enabled
              ? () {
                  final c = controller;
                  if (c == null) return;
                  onManualZoom?.call();
                  pdfViewerZoomOut(c);
                }
              : null,
          child: const Text('Zoom out'),
        ),
        MenuItemButton(
          onPressed: enabled ? onFitWidth : null,
          child: const Text('Fit width'),
        ),
        MenuItemButton(
          onPressed: enabled ? onFitPage : null,
          child: const Text('Fit page'),
        ),
      ],
      builder: (context, menu, _) {
        return Tooltip(
          message: 'Zoom',
          child: InkWell(
            key: const Key('pdf_viewer_acrobat_zoom_field'),
            onTap: enabled
                ? () => menu.isOpen ? menu.close() : menu.open()
                : null,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: border),
              ),
              alignment: Alignment.center,
              child: Text(
                '$percent%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SignPlacementBar extends StatelessWidget {
  const _SignPlacementBar({
    required this.onCancel,
    required this.onDone,
    required this.doneEnabled,
    this.statusLabel,
  });

  final VoidCallback? onCancel;
  final VoidCallback? onDone;
  final bool doneEnabled;
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    return SizedBox(
      height: PdfViewerAcrobatTopChrome.barHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
        child: Row(
          children: [
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            Expanded(
              child: Text(
                statusLabel ?? 'Adjust signature',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: DsColors.textSecondary(brightness),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            FilledButton(
              onPressed: doneEnabled ? onDone : null,
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
