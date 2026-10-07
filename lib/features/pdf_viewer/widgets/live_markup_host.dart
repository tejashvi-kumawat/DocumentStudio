import 'package:document_studio/features/form_sign/sign_page_layers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_draw_layers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_form_layer.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_image_edit_layer.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_link_layer.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_page_geom.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_placement_layer.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_text_layer.dart';
import 'package:document_studio/features/pdf_viewer/widgets/viewer_nav_forwarder.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:pdfrx/pdfrx.dart';

/// Tools whose page overlay is provided by [LiveMarkupPageHost].
bool liveMarkupHostHandles(ViewerToolId? id) => switch (id) {
  ViewerToolId.ink ||
  ViewerToolId.markupBurn ||
  ViewerToolId.addLink ||
  ViewerToolId.placeImage ||
  ViewerToolId.visualSign ||
  ViewerToolId.editText ||
  ViewerToolId.fillForm => true,
  _ => false,
};

/// Mounted on every page by the viewer's page-overlay builder. Listens to the
/// session itself, so tool / page changes and drag ticks never depend on the
/// whole viewer rebuilding; drag ticks only rebuild the active page.
class LiveMarkupPageHost extends StatefulWidget {
  const LiveMarkupPageHost({
    super.key,
    required this.session,
    required this.geom,
    this.controller,
    this.signDocumentPath,
  });

  final ViewerLiveToolSession session;
  final LivePageGeom geom;

  /// Session source path. Signatures for another open document are not drawn.
  final String? signDocumentPath;

  /// Wheel events over the overlay are forwarded here so scrolling still works.
  final PdfViewerController? controller;

  @override
  State<LiveMarkupPageHost> createState() => _LiveMarkupPageHostState();
}

class _LiveMarkupPageHostState extends State<LiveMarkupPageHost> {
  bool _rebuildQueued = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSession);
    widget.session.draftRevision.addListener(_onDraft);
  }

  @override
  void didUpdateWidget(covariant LiveMarkupPageHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.removeListener(_onSession);
      oldWidget.session.draftRevision.removeListener(_onDraft);
      widget.session.addListener(_onSession);
      widget.session.draftRevision.addListener(_onDraft);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    widget.session.draftRevision.removeListener(_onDraft);
    super.dispose();
  }

  void _onSession() => _rebuild();

  void _onDraft() {
    if (widget.session.pageIndex1Based == widget.geom.pageNumber) _rebuild();
  }

  /// Immediate rebuild; deferred one frame only if notified mid-build.
  void _rebuild() {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    if (_rebuildQueued) return;
    _rebuildQueued = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _rebuildQueued = false;
      if (mounted) setState(() {});
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final live = widget.session;
    final g = widget.geom;
    final tool = live.toolId;
    if (!(g.pagePx.width > 1 && g.pagePx.height > 1)) {
      return const SizedBox.shrink();
    }
    // SignPageLayer paints items while the sign tool is up. After Apply the
    // tool can close; keep the burned image on the page without reopening
    // the PDF.
    final stamps = tool == ViewerToolId.visualSign
        ? const SizedBox.shrink()
        : SignPlacedStampLayer(
            pageNumber: g.pageNumber,
            pagePx: g.pagePx,
            documentPath: widget.signDocumentPath,
          );
    if (!liveMarkupHostHandles(tool)) return stamps;
    live.notePageGeometry(g.pageNumber, g.pageWidthPt, g.pageHeightPt);
    final onActive = live.pageIndex1Based == g.pageNumber;
    final spans = live.spansPages || tool == ViewerToolId.fillForm;
    if (!spans && !onActive) return stamps;

    final Widget layer = switch (tool) {
      ViewerToolId.ink => LiveInkLayer(session: live, geom: g),
      ViewerToolId.markupBurn => LiveMarkupLayer(session: live, geom: g),
      ViewerToolId.addLink => LiveLinkLayer(session: live, geom: g),
      ViewerToolId.placeImage => LivePlacementLayer(session: live, geom: g),
      ViewerToolId.visualSign => SignPageLayer(
        geom: g,
        viewer: widget.controller,
        documentPath: widget.signDocumentPath,
      ),
      ViewerToolId.editText => Stack(
        fit: StackFit.expand,
        children: [
          LiveTextLayer(session: live, geom: g),
          LiveImageEditLayer(session: live, geom: g),
        ],
      ),
      ViewerToolId.fillForm => LiveFormLayer(session: live, geom: g),
      _ => const SizedBox.shrink(),
    };
    final controller = widget.controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        stamps,
        ViewerNavForwarder(
          controller: controller,
          child: RepaintBoundary(
            child: KeyedSubtree(key: ValueKey(tool), child: layer),
          ),
        ),
      ],
    );
  }
}
