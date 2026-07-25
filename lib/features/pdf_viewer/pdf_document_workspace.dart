import 'dart:async';
import 'dart:ui' as ui;

import 'package:document_studio/core/storage/linux_document_portal.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/markup_display_document.dart';
import 'package:document_studio/features/pdf_viewer/pdf_approach_decoder.dart';
import 'package:document_studio/features/pdf_viewer/pdf_thumbnail_sidebar.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_params_config.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_scroll_layout.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_sidebar_content.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_soft_reload.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_view_rotation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';

/// Viewer area with an optional thumbnail sidebar on wide layouts.
class PdfDocumentWorkspace extends StatefulWidget {
  const PdfDocumentWorkspace({
    super.key,
    required this.file,
    required this.documentTabId,
    /// Stable open identity for [PdfViewer] ValueKey / [PdfDocumentRefKey].
    /// Use the session **source** path (not a mutating working temp).
    this.viewerIdentityPath,
    this.password,
    this.sidebarEnabled = true,
    this.embedLeftSidebar = true,
    this.pagePaintCallbacks,
    this.onControllerReady,
    this.scrollLayoutMode = PdfViewerScrollLayoutMode.continuous,
    this.viewRotation = PdfViewerViewRotation.degrees0,
    this.immersiveSinglePage = false,
    this.presentationAdvanceOnTap = false,
    this.linkHandlerParams,
    this.sidebarContent,
    this.pageOverlaysBuilder,
    this.onOpenContextMenu,
    this.canvasMargin = true,
  });

  final LocalFileRef file;
  final String documentTabId;
  /// When null, [file.path] is used (resolved sync in State).
  final String? viewerIdentityPath;
  final String? password;
  final bool sidebarEnabled;

  /// When false, the canvas only — left rail is hosted by [PdfViewerAcrobatShell].
  final bool embedLeftSidebar;
  final List<PdfViewerPagePaintCallback>? pagePaintCallbacks;
  final void Function(PdfViewerController controller)? onControllerReady;
  final PdfViewerScrollLayoutMode scrollLayoutMode;
  final PdfViewerViewRotation viewRotation;
  final bool immersiveSinglePage;
  final bool presentationAdvanceOnTap;
  final PdfLinkHandlerParams? linkHandlerParams;
  final PdfViewerSidebarContent? sidebarContent;
  final PdfPageOverlaysBuilder? pageOverlaysBuilder;
  final void Function(Offset globalPosition)? onOpenContextMenu;
  final bool canvasMargin;

  @override
  State<PdfDocumentWorkspace> createState() => _PdfDocumentWorkspaceState();
}

class _PdfDocumentWorkspaceState extends State<PdfDocumentWorkspace> {
  bool _invalidateScheduled = false;
  double? _lastViewportHeight;

  static bool _samePagePaintCallbacks(
    List<PdfViewerPagePaintCallback>? a,
    List<PdfViewerPagePaintCallback>? b,
  ) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  late PdfViewerController _controller;
  final PdfViewerRenderPace _renderPace = PdfViewerRenderPace();
  final PdfApproachDecoder _approach = PdfApproachDecoder();
  late final PdfViewerPagePaintCallback _approachPaint = _paintApproachPage;
  List<PdfViewerPagePaintCallback>? _combinedPaint;
  List<PdfViewerPagePaintCallback>? _combinedPaintSource;
  double _devicePixelRatio = 1;
  bool _approachKicked = false;
  bool _approachRetryQueued = false;
  int _approachTries = 0;
  double? _motionZoom;
  double? _motionX;
  double? _motionY;

  /// pdfrx [PdfViewerController.invalidate] notifies listeners synchronously;
  /// defer so param updates never run during [State.didUpdateWidget] / layout.
  void _scheduleControllerInvalidate() {
    if (_invalidateScheduled) return;
    _invalidateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _invalidateScheduled = false;
      if (!mounted || !_controller.isReady) return;
      _controller.invalidate();
    });
  }

  /// Viewer chrome (status bar, find bar) changes height — refresh layout params
  /// without remounting [PdfViewer].
  void _onViewportHeightChanged(double viewportHeight) {
    final prev = _lastViewportHeight;
    _lastViewportHeight = viewportHeight;
    if (prev == null || (prev - viewportHeight).abs() < 0.5) return;
    if (widget.scrollLayoutMode == PdfViewerScrollLayoutMode.continuous &&
        !widget.immersiveSinglePage) {
      return;
    }
    _scheduleControllerInvalidate();
  }

  void _notifyControllerReady() {
    registerPdfViewerSeamlessReload(_controller, _seamlessReload);
    final callback = widget.onControllerReady;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(_controller);
    });
  }

  MarkupDisplayDocumentHandle? _document;
  late String _identityPath;
  String? _heldIdentity;
  String? _heldPassword;
  bool _documentReady = false;

  final GlobalKey _viewerBoundaryKey = GlobalKey(debugLabel: 'pdfViewerFrame');
  ui.Image? _freezeFrame;
  bool _freezeVisible = false;
  int _reloadSeq = 0;

  /// Swaps in the file's current bytes without a visible blink.
  Future<bool> _seamlessReload({
    int? preferredPage,
    double? preferredZoom,
    Offset? preferredCenter,
  }) async {
    final controller = _controller;
    if (!mounted || !controller.isReady) return false;
    final seq = ++_reloadSeq;
    final matrix = controller.value.clone();
    final page = preferredPage ?? controller.pageNumber ?? 1;
    final pageCount = controller.pageCount;

    ui.Image? shot;
    final boundary = _viewerBoundaryKey.currentContext?.findRenderObject();
    if (boundary is RenderRepaintBoundary) {
      try {
        shot = await boundary.toImage(
          pixelRatio: MediaQuery.devicePixelRatioOf(context),
        );
      } catch (_) {
        shot = null;
      }
    }
    if (!mounted || seq != _reloadSeq) {
      shot?.dispose();
      return true;
    }
    if (shot != null) {
      final old = _freezeFrame;
      setState(() {
        _freezeFrame = shot;
        _freezeVisible = true;
      });
      old?.dispose();
    }

    try {
      await controller.documentRef.resolveListenable().load(forceReload: true);
    } catch (_) {
      _dropFreezeFrame(seq, immediate: true);
      return false;
    }
    await SchedulerBinding.instance.endOfFrame;
    if (!mounted || controller != _controller || !controller.isReady) {
      _dropFreezeFrame(seq, immediate: true);
      return true;
    }
    try {
      if (controller.pageCount == pageCount) {
        controller.value = matrix;
      } else {
        await controller.goToPage(
          pageNumber: page.clamp(1, controller.pageCount),
          duration: Duration.zero,
        );
        if (preferredZoom != null) {
          await controller.setZoom(
            preferredCenter ?? controller.centerPosition,
            preferredZoom,
            duration: Duration.zero,
          );
        }
      }
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 220));
    _dropFreezeFrame(seq);
    return true;
  }

  void _dropFreezeFrame(int seq, {bool immediate = false}) {
    if (!mounted || seq != _reloadSeq || _freezeFrame == null) return;
    if (immediate) {
      final img = _freezeFrame;
      setState(() {
        _freezeFrame = null;
        _freezeVisible = false;
      });
      img?.dispose();
      return;
    }
    setState(() => _freezeVisible = false);
  }

  void _onFreezeFaded() {
    if (_freezeVisible || _freezeFrame == null) return;
    final img = _freezeFrame;
    setState(() => _freezeFrame = null);
    img?.dispose();
  }

  void _holdDocument({
    required String identityPath,
    required String loadPath,
    required String? password,
  }) {
    if (_document != null &&
        _heldIdentity == identityPath &&
        _heldPassword == password) {
      _document!.updateLoadPath(loadPath);
      return;
    }
    _dropDocument();
    _heldIdentity = identityPath;
    _heldPassword = password;
    _identityPath = identityPath;
    _document = MarkupDisplayDocumentHandle.retain(
      identityPath: identityPath,
      password: password,
    );
    _document!.updateLoadPath(loadPath);
  }

  void _dropDocument() {
    final held = _heldIdentity;
    if (held == null) {
      _document = null;
      return;
    }
    MarkupDisplayDocumentHandle.release(held, password: _heldPassword);
    _document = null;
    _heldIdentity = null;
  }

  @override
  void initState() {
    super.initState();
    _controller = PdfViewerController();
    _bindControllerMotion(_controller);
    _approach.addListener(_onApproachPixels);
    _renderPace.onSettled = _upgradeSettledPages;
    final identityHint = widget.viewerIdentityPath ?? widget.file.path;
    final loadHint = widget.file.path;
    // Sync path first (cache hit after shell await resolve). If still FUSE,
    // finish resolve before the PdfDocumentRefKey exists.
    final syncIdentity = LinuxDocumentPortal.resolveSync(identityHint);
    final syncLoad = LinuxDocumentPortal.resolveSync(loadHint);
    if (!LinuxDocumentPortal.isPortalPath(syncIdentity) &&
        !LinuxDocumentPortal.isPortalPath(syncLoad)) {
      _holdDocument(
        identityPath: syncIdentity,
        loadPath: syncLoad,
        password: widget.password,
      );
      _documentReady = true;
      _notifyControllerReady();
      return;
    }
    _identityPath = syncIdentity;
    _documentReady = false;
    unawaited(_resolvePortalThenCreate(identityHint, loadHint));
  }

  Future<void> _resolvePortalThenCreate(
    String identityHint,
    String loadHint,
  ) async {
    final identity = await LinuxDocumentPortal.resolve(identityHint);
    final load = await LinuxDocumentPortal.resolve(loadHint);
    if (!mounted) return;
    setState(() {
      _holdDocument(
        identityPath: identity,
        loadPath: load,
        password: widget.password,
      );
      _documentReady = true;
    });
    _notifyControllerReady();
  }

  void _bindControllerMotion(PdfViewerController controller) {
    _approach.attach(controller);
    controller.addListener(_onViewerMotion);
  }

  void _unbindControllerMotion(PdfViewerController controller) {
    controller.removeListener(_onViewerMotion);
    _approach.detach(controller);
  }

  /// Scroll offset changes on the UI thread. This only marks which pages to
  /// decode; it does not wait on a render, so the scroll position moves now.
  void _onViewerMotion() {
    final controller = _controller;
    if (!controller.isReady) return;
    final zoom = controller.currentZoom;
    final matrix = controller.value;
    final x = matrix.storage[12];
    final y = matrix.storage[13];
    final prevZoom = _motionZoom;
    final prevX = _motionX;
    final prevY = _motionY;
    _motionZoom = zoom;
    _motionX = x;
    _motionY = y;
    final first = prevZoom == null || prevX == null || prevY == null;
    final moved = !first &&
        ((zoom - prevZoom).abs() >= 0.001 ||
            (x - prevX).abs() >= 0.5 ||
            (y - prevY).abs() >= 0.5);
    if (moved) _renderPace.noteMotion();
    if (first || moved || _renderPace.isMoving) {
      _syncApproach(moving: _renderPace.isMoving);
    }
  }

  void _upgradeSettledPages() {
    if (!mounted || !_controller.isReady) return;
    _syncApproach(moving: false);
    // Ask pdfrx for the settled scale. A zoom is not required.
    _controller.invalidate();
  }

  void _syncApproach({required bool moving}) {
    final ready = _approach.sync(
      moving: moving,
      devicePixelRatio: _devicePixelRatio,
    );
    if (ready) {
      _approachTries = 0;
      return;
    }
    if (_approachRetryQueued || _approachTries > 30) return;
    _approachRetryQueued = true;
    _approachTries++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _approachRetryQueued = false;
      if (!mounted) return;
      _syncApproach(moving: _renderPace.isMoving);
    });
  }

  void _onApproachPixels() {
    if (!mounted || !_controller.isReady) return;
    _controller.invalidate();
  }

  void _paintApproachPage(Canvas canvas, Rect pageRect, PdfPage page) {
    _approach.paintStandIn(canvas, pageRect, page.pageNumber);
  }

  List<PdfViewerPagePaintCallback> _pagePaintCallbacks() {
    final src = widget.pagePaintCallbacks;
    final cached = _combinedPaint;
    if (cached != null && identical(src, _combinedPaintSource)) return cached;
    _combinedPaintSource = src;
    return _combinedPaint = [_approachPaint, ...?src];
  }

  @override
  void dispose() {
    _approach.removeListener(_onApproachPixels);
    _unbindControllerMotion(_controller);
    _approach.dispose();
    _renderPace.dispose();
    registerPdfViewerSeamlessReload(_controller, null);
    _dropDocument();
    _freezeFrame?.dispose();
    _freezeFrame = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PdfDocumentWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIdentity = LinuxDocumentPortal.resolveSync(
      widget.viewerIdentityPath ?? widget.file.path,
    );
    final identityChanged = newIdentity != _identityPath;
    final passwordChanged = oldWidget.password != widget.password;
    final loadPathChanged = oldWidget.file.path != widget.file.path;

    if (identityChanged || passwordChanged) {
      // Save As / replace file — new identity.
      registerPdfViewerSeamlessReload(_controller, null);
      if (LinuxDocumentPortal.isPortalPath(newIdentity) ||
          LinuxDocumentPortal.isPortalPath(widget.file.path)) {
        _dropDocument();
        _documentReady = false;
        _identityPath = newIdentity;
        unawaited(
          _resolvePortalThenCreate(
            widget.viewerIdentityPath ?? widget.file.path,
            widget.file.path,
          ),
        );
        return;
      }
      _holdDocument(
        identityPath: newIdentity,
        loadPath: LinuxDocumentPortal.resolveSync(widget.file.path),
        password: widget.password,
      );
      _documentReady = true;
      _unbindControllerMotion(_controller);
      _controller = PdfViewerController();
      _bindControllerMotion(_controller);
      _renderPace.clear();
      _approachKicked = false;
      _approachTries = 0;
      _motionZoom = null;
      _motionX = null;
      _motionY = null;
      _notifyControllerReady();
    } else if (loadPathChanged) {
      // Working-copy path change: keep State + ref key; retarget loader only.
      _document?.updateLoadPath(widget.file.path);
    } else if (oldWidget.scrollLayoutMode != widget.scrollLayoutMode ||
        oldWidget.viewRotation != widget.viewRotation ||
        oldWidget.immersiveSinglePage != widget.immersiveSinglePage ||
        oldWidget.presentationAdvanceOnTap !=
            widget.presentationAdvanceOnTap ||
        !_samePagePaintCallbacks(
          oldWidget.pagePaintCallbacks,
          widget.pagePaintCallbacks,
        ) ||
        oldWidget.linkHandlerParams != widget.linkHandlerParams) {
      _scheduleControllerInvalidate();
    }
  }

  Future<void> _goToPage(int pageNumber) async {
    await _controller.goToPage(pageNumber: pageNumber);
  }

  @override
  Widget build(BuildContext context) {
    final document = _document;
    if (!_documentReady || document == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _onViewportHeightChanged(constraints.maxHeight);
        _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
        if (!_approachKicked) {
          _approachKicked = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _syncApproach(moving: _renderPace.isMoving);
          });
        }
        final showSidebar = shouldShowPdfThumbnailSidebar(
          viewportWidth: constraints.maxWidth,
          sidebarEnabled: widget.sidebarEnabled,
        );

        // ValueKey: resolved identity path + scroll mode only.
        final pdfViewer = PdfViewer(
          document.ref,
          key: ValueKey(
            '$_identityPath:${widget.scrollLayoutMode.name}',
          ),
          controller: _controller,
          params: buildPdfViewerParams(
            renderPace: _renderPace,
            pagePaintCallbacks: _pagePaintCallbacks(),
            pageNavigationController: _controller,
            scrollLayoutMode: widget.scrollLayoutMode,
            viewportHeight: constraints.maxHeight,
            linkHandlerParams: widget.linkHandlerParams,
            immersiveSinglePage: widget.immersiveSinglePage,
            presentationAdvanceOnTap: widget.presentationAdvanceOnTap,
            pageOverlaysBuilder: widget.pageOverlaysBuilder,
          ),
        );
        final freeze = _freezeFrame;
        final viewer = Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(key: _viewerBoundaryKey, child: pdfViewer),
            if (freeze != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _freezeVisible ? 1 : 0,
                    duration: _freezeVisible
                        ? Duration.zero
                        : const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    onEnd: _onFreezeFaded,
                    child: RawImage(image: freeze, fit: BoxFit.fill),
                  ),
                ),
              ),
          ],
        );

        if (!widget.embedLeftSidebar || !showSidebar) {
          return viewer;
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dividerColor =
            isDark ? DsColors.borderDark : DsColors.borderLight;

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PdfThumbnailSidebar(
              controller: _controller,
              onPageSelected: _goToPage,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: dividerColor,
            ),
            Expanded(child: viewer),
          ],
        );
      },
    );
  }
}
