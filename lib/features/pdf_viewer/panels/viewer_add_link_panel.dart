import 'dart:async';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/live_page_text_loader.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/infrastructure/pdf/pdf_link_annotation_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Add, edit or remove real PDF link annotations (URL or go-to-page).
///
/// Drag a rectangle on any page for a new link, or click an existing link
/// (dashed) to change its target / rectangle or delete it.
class ViewerAddLinkPanel extends ConsumerStatefulWidget {
  const ViewerAddLinkPanel({super.key, required this.handoff, this.pageCount});

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;

  @override
  ConsumerState<ViewerAddLinkPanel> createState() => _ViewerAddLinkPanelState();
}

class _ViewerAddLinkPanelState extends ConsumerState<ViewerAddLinkPanel> {
  final _targetCtrl = TextEditingController();
  ViewerLiveToolSession? _live;
  bool _busy = false;
  bool _asPageJump = false;
  bool _visibleBorder = false;
  int _linksLoadedFor = 0;
  int? _seenSelection;
  int _seenApply = 0;
  int _seenDelete = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      if (live.toolId != ViewerToolId.addLink) {
        live.activate(
          ViewerToolId.addLink,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      }
      _seenApply = live.applyRequestId;
      _seenDelete = live.deleteRequestId;
      live.addListener(_onLive);
      _onLive();
    });
  }

  @override
  void dispose() {
    _live?.removeListener(_onLive);
    _targetCtrl.dispose();
    super.dispose();
  }

  void _onLive() {
    final live = _live;
    if (live == null || !mounted || live.toolId != ViewerToolId.addLink) return;
    final page = live.pageIndex1Based;
    if (page != _linksLoadedFor) {
      _linksLoadedFor = page;
      unawaited(_loadLinks(page));
    }
    final sel = live.selectedLinkIndex;
    if (sel != _seenSelection) {
      _seenSelection = sel;
      final hit = live.selectedLink;
      if (hit != null) {
        _asPageJump = hit.destPage1Based != null;
        _targetCtrl.text = hit.destPage1Based?.toString() ?? hit.uri ?? '';
      }
    }
    if (live.applyRequestId != _seenApply) {
      _seenApply = live.applyRequestId;
      unawaited(_apply());
    }
    if (live.deleteRequestId != _seenDelete) {
      _seenDelete = live.deleteRequestId;
      unawaited(_delete());
    }
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _loadLinks(int page) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final text = await loadLivePageText(
      file: session?.file ?? widget.handoff.file,
      password: session?.password ?? widget.handoff.password,
      page1Based: page,
      withRuns: false,
      withChars: false,
      withLinks: true,
    );
    final live = _live;
    if (!mounted || live == null || text == null) return;
    if (live.pageIndex1Based != page) return;
    live.setLinkHits(page, text.links);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _normalizeUrl(String raw) {
    final t = raw.trim();
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(t)) return t;
    if (RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) return 'mailto:$t';
    return 'https://$t';
  }

  Future<void> _commit(
    Future<Uint8List> Function() write,
    String message,
  ) async {
    final live = _live;
    if (live == null) return;
    setState(() => _busy = true);
    try {
      final bytes = await write();
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session == null) return;
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage: message,
      );
      live.clearDragRect();
      _linksLoadedFor = 0;
      await _loadLinks(live.pageIndex1Based);
    } on DocumentStudioError catch (e) {
      _toast(e.recoveryHint ?? e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final live = _live;
    if (live == null || _busy) return;
    final drag = live.dragRectNorm;
    final page = live.pageIndex1Based;
    final size = live.pageSizePtFor(page);
    if (drag == null ||
        size == null ||
        drag.width * size.width < 4 ||
        drag.height * size.height < 4) {
      _toast('Drag a link rectangle on the page first');
      return;
    }
    final raw = _targetCtrl.text.trim();
    if (raw.isEmpty) {
      _toast(_asPageJump ? 'Enter a page number' : 'Enter a URL');
      return;
    }
    final PdfLinkAnnotationSpec spec;
    if (_asPageJump) {
      final dest = int.tryParse(raw);
      final total = widget.pageCount ?? 1;
      if (dest == null || dest < 1 || dest > total) {
        _toast('Page must be 1–$total');
        return;
      }
      spec = PdfLinkAnnotationSpec.goToDisplayNorm(
        pageIndex1Based: page,
        displayNormRect: drag,
        destPage1Based: dest,
        visibleBorder: _visibleBorder,
      );
    } else {
      spec = PdfLinkAnnotationSpec.uriDisplayNorm(
        pageIndex1Based: page,
        displayNormRect: drag,
        uri: _normalizeUrl(raw),
        visibleBorder: _visibleBorder,
      );
    }
    final replacing = live.selectedLink?.normRect;
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) return;
    await _commit(
      () => PdfLinkAnnotationService().addLinkToBytes(
        input: session.file,
        link: spec,
        password: session.password,
        replaceDisplayNormRect: replacing,
      ),
      replacing != null ? 'Link updated.' : 'Link added on page $page.',
    );
  }

  Future<void> _delete() async {
    final live = _live;
    final hit = live?.selectedLink;
    if (live == null || hit == null || _busy) return;
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) return;
    final page = live.pageIndex1Based;
    await _commit(
      () => PdfLinkAnnotationService().removeLinksToBytes(
        input: session.file,
        pageIndex1Based: page,
        displayNormRect: hit.normRect,
        password: session.password,
      ),
      'Link removed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.read(viewerLiveToolSessionProvider);
    final editing = live.selectedLink != null;
    final hasRect = live.dragRectNorm != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ListView(
        padding: const EdgeInsets.all(DsSpacing.md),
        children: [
          Text(
            'Drag a rectangle on any page for a new link, or click an existing '
            '(dashed) link to edit it. Enter applies, Delete removes the selected link.',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              key: ValueKey('$editing$hasRect'),
              editing
                  ? 'Editing link on page ${live.pageIndex1Based}'
                  : hasRect
                  ? 'New link on page ${live.pageIndex1Based}'
                  : 'No link selected',
              style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('URL'),
                icon: Icon(Icons.public, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('Page'),
                icon: Icon(Icons.menu_book_outlined, size: 16),
              ),
            ],
            selected: {_asPageJump},
            onSelectionChanged: (v) => setState(() => _asPageJump = v.first),
          ),
          const SizedBox(height: DsSpacing.sm),
          TextField(
            controller: _targetCtrl,
            decoration: InputDecoration(
              labelText: _asPageJump
                  ? 'Page number (1–${widget.pageCount ?? '?'})'
                  : 'URL or email',
              labelStyle: const TextStyle(fontSize: 13),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 13),
            keyboardType: _asPageJump
                ? TextInputType.number
                : TextInputType.url,
            onSubmitted: (_) => unawaited(_apply()),
          ),
          const SizedBox(height: DsSpacing.xs),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Show link border',
              style: TextStyle(fontSize: 13),
            ),
            value: _visibleBorder,
            onChanged: (v) => setState(() => _visibleBorder = v),
          ),
          const SizedBox(height: DsSpacing.sm),
          DsPrimaryButton(
            label: _busy ? 'Saving…' : (editing ? 'Update link' : 'Add link'),
            icon: Icons.link,
            onPressed: _busy || !hasRect ? null : () => unawaited(_apply()),
          ),
          if (editing) ...[
            const SizedBox(height: DsSpacing.xs),
            TextButton.icon(
              onPressed: _busy ? null : () => unawaited(_delete()),
              icon: const Icon(Icons.link_off, size: 18),
              label: const Text('Remove link'),
            ),
          ],
        ],
      ),
    );
  }
}
