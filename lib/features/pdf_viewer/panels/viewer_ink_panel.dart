import 'package:document_studio/core/pdf/page_loader.dart';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_shortcuts.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_ink_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'dart:async';

/// Compact live-page draw strip: pen, highlighter, shapes → burn on mouse-up.
class ViewerInkPanel extends ConsumerStatefulWidget {
  const ViewerInkPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerInkPanel> createState() => _ViewerInkPanelState();
}

class _ViewerInkPanelState extends ConsumerState<ViewerInkPanel> {
  bool _busy = false;
  double _pageWidthPt = 612;
  double _pageHeightPt = 792;
  int _seenCommitEpoch = 0;
  ViewerLiveToolSession? _live;
  late final TextEditingController _stampCtrl;

  static const _palette = <Color>[
    Color(0xFFE4002B),
    Color(0xFF1A1A1A),
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFFF5D76E),
    Color(0xFFFFFFFF),
  ];

  @override
  void initState() {
    super.initState();
    _stampCtrl = TextEditingController(text: 'APPROVED');
    unawaited(_primePageSize());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      live.addListener(_onLive);
      if (live.toolId != ViewerToolId.ink) {
        live.activate(
          ViewerToolId.ink,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      }
      live.setLabelText(_stampCtrl.text);
      _seenCommitEpoch = live.drawCommitEpoch;
    });
  }

  @override
  void dispose() {
    _inkDebounce?.cancel();
    _stampCtrl.dispose();
    _live?.removeListener(_onLive);
    super.dispose();
  }

  void _flushInkNow() {
    final live = _live;
    if (live == null) return;
    unawaited(_burnQueued(live));
  }

  void _onLive() {
    final live = _live;
    if (live == null || !mounted) return;
    if (live.drawCommitEpoch != _seenCommitEpoch &&
        live.pendingDrawCommit != null) {
      _seenCommitEpoch = live.drawCommitEpoch;
      // Keep strokes on the overlay; coalesce into one write after 6s idle when
      // autosave is on (otherwise burn the queue immediately).
      final autosaveOn = ref.read(viewerAutosaveEnabledProvider);
      live.clearPendingDrawCommit();
      if (autosaveOn) {
        _scheduleDebouncedInkBurn(live);
      } else {
        unawaited(_burnQueued(live));
      }
    } else if (mounted) {
      setState(() {});
    }
  }

  Timer? _inkDebounce;

  void _scheduleDebouncedInkBurn(ViewerLiveToolSession live) {
    _inkDebounce?.cancel();
    _inkDebounce = Timer(kViewerAutosaveDebounce, () {
      unawaited(_burnQueued(live));
    });
    if (mounted) setState(() {});
  }

  Future<void> _burnQueued(ViewerLiveToolSession live) async {
    if (_busy || live.queuedDrawCommits.isEmpty) return;
    final commits = List<LiveDrawCommit>.from(live.queuedDrawCommits);
    // Burn on the page the overlay was drawn on, not wherever the viewer
    // happens to be scrolled now.
    final targetPage = live.pageIndex1Based;
    setState(() => _busy = true);
    try {
      await _primePageSize(page1Based: targetPage);
      final tempDir = await ref.read(fileStorageProvider).getTempDirectory();
      var working = widget.handoff.file;
      final ink = <PdfInkStroke>[];
      final stamps = <LiveDrawCommit>[];
      for (final c in commits) {
        if (c.tool == LiveDrawTool.stamp) {
          stamps.add(c);
        } else {
          ink.add(
            PdfInkStroke(
              points: [
                for (final o in c.pointsNorm)
                  (
                    o.dx * _pageWidthPt,
                    (1 - o.dy) * _pageHeightPt,
                  ),
              ],
              widthPt: c.strokeWidthPt,
              colorRgb: _rgb(c.color),
              opacity: c.opacity,
            ),
          );
        }
      }

      String? lastTemp;
      if (ink.isNotEmpty) {
        final tempOut = p.join(
          tempDir,
          'ink-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        await ref.read(pdfOverlayServiceProvider).applyInkStrokesOnPage(
              input: working,
              outputPath: tempOut,
              pageIndex1Based: targetPage,
              strokes: ink,
              password: widget.handoff.password,
            );
        lastTemp = tempOut;
        working = LocalFileRef(path: tempOut, displayName: 'tmp.pdf');
      }

      if (stamps.isNotEmpty) {
        final tempOut = p.join(
          tempDir,
          'stamp-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        await _applyStamps(working, tempOut, stamps, targetPage);
        if (lastTemp != null) {
          try {
            await File(lastTemp).delete();
          } catch (_) {}
        }
        lastTemp = tempOut;
        working = LocalFileRef(path: tempOut, displayName: 'tmp.pdf');
      }

      if (lastTemp == null) return;
      final bytes = Uint8List.fromList(await File(lastTemp).readAsBytes());
      try {
        await File(lastTemp).delete();
      } catch (_) {}
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session == null) return;
      final autosaveOn = ref.read(viewerAutosaveEnabledProvider);
      await commitBytesToSession(
        context: context,
        storage: ref.read(fileStorageProvider),
        tabs: ref.read(documentTabsControllerProvider),
        session: session,
        bytes: bytes,
        successMessage: 'Drawing applied to page $targetPage.',
        debounce: false,
        silent: autosaveOn,
      );
      live.clearInk();
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.recoveryHint ?? e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Burns all queued stamps in one overlay pass, laid out by the same
  /// [layoutStampLabel] the live preview paints with.
  Future<void> _applyStamps(
    LocalFileRef input,
    String tempOut,
    List<LiveDrawCommit> stamps,
    int page1Based,
  ) async {
    await ref.read(pdfOverlayServiceProvider).applyStampLabelsOnPage(
          input: input,
          outputPath: tempOut,
          pageIndex1Based: page1Based,
          stamps: [
            for (final s in stamps)
              (
                boxNorm: _boundsOf(s.pointsNorm),
                label: s.labelText ?? 'APPROVED',
                rgb: _rgb(s.color),
              ),
          ],
          password: widget.handoff.password,
        );
  }

  Rect _boundsOf(List<Offset> pts) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final o in pts) {
      minX = o.dx < minX ? o.dx : minX;
      minY = o.dy < minY ? o.dy : minY;
      maxX = o.dx > maxX ? o.dx : maxX;
      maxY = o.dy > maxY ? o.dy : maxY;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Future<void> _primePageSize({int? page1Based}) async {
    try {
      final doc = await openPdfLazily(widget.handoff.file.path, password: widget.handoff.password);
      try {
        final idx = ((page1Based ?? widget.handoff.currentPage1) - 1)
            .clamp(0, doc.pages.length - 1);
        final page =
            await loadPageOnDemand(doc, idx + 1) ?? doc.pages.first;
        if (!mounted) return;
        setState(() {
          _pageWidthPt = page.width;
          _pageHeightPt = page.height;
        });
      } finally {
        await doc.dispose();
      }
    } catch (_) {}
  }

  (double, double, double) _rgb(Color c) => (c.r, c.g, c.b);

  Widget _toolChip({
    required LiveDrawTool tool,
    required IconData icon,
    required String label,
    String? shortcut,
  }) {
    final live = ref.read(viewerLiveToolSessionProvider);
    final selected = live.drawTool == tool;
    final tip = shortcut == null ? label : '$label ($shortcut)';
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: tip,
        child: FilterChip(
          selected: selected,
          label: Icon(icon, size: 16),
          onSelected: (_) {
            live.setDrawTool(tool);
            if (tool == LiveDrawTool.highlighter) {
              live.setMarkupColor(const Color(0xFFF5D76E));
            }
            setState(() {});
          },
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.watch(viewerLiveToolSessionProvider);
    return ColoredBox(
      color: const Color(0xFFF4F4F4),
      child: ListenableBuilder(
        listenable: live,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.all(DsSpacing.md),
            children: [
              Text(
                'Draw on any page. Hold Shift for straight lines / squares. '
                'Stamps are one click. Ctrl+Z undoes the last mark, Esc cancels the current stroke.',
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
              ),
              const SizedBox(height: DsSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _toolChip(
                      tool: LiveDrawTool.pen,
                      icon: Icons.edit_outlined,
                      label: 'Pen',
                      shortcut: viewerToolShortcutTooltip(ViewerToolShortcutId.draw),
                    ),
                    _toolChip(
                      tool: LiveDrawTool.highlighter,
                      icon: Icons.highlight_outlined,
                      label: 'Highlighter',
                    ),
                    _toolChip(
                      tool: LiveDrawTool.line,
                      icon: Icons.show_chart,
                      label: 'Line',
                      shortcut:
                          viewerToolShortcutTooltip(ViewerToolShortcutId.line),
                    ),
                    _toolChip(
                      tool: LiveDrawTool.arrow,
                      icon: Icons.arrow_right_alt,
                      label: 'Arrow',
                    ),
                    _toolChip(
                      tool: LiveDrawTool.rectangle,
                      icon: Icons.crop_square,
                      label: 'Rectangle',
                      shortcut: viewerToolShortcutTooltip(
                        ViewerToolShortcutId.rectangle,
                      ),
                    ),
                    _toolChip(
                      tool: LiveDrawTool.ellipse,
                      icon: Icons.circle_outlined,
                      label: 'Ellipse',
                    ),
                    _toolChip(
                      tool: LiveDrawTool.callout,
                      icon: Icons.chat_bubble_outline,
                      label: 'Callout',
                    ),
                    _toolChip(
                      tool: LiveDrawTool.stamp,
                      icon: Icons.approval_outlined,
                      label: 'Stamp',
                    ),
                  ],
                ),
              ),
              if (live.drawTool == LiveDrawTool.stamp) ...[
                const SizedBox(height: DsSpacing.sm),
                TextField(
                  key: const Key('viewer_ink_stamp_label'),
                  controller: _stampCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Stamp label',
                    labelStyle: TextStyle(fontSize: 13),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: live.setLabelText,
                ),
                const SizedBox(height: DsSpacing.xs),
                Wrap(
                  spacing: 4,
                  children: [
                    for (final label in const ['APPROVED', 'DRAFT', 'CONFIDENTIAL'])
                      ActionChip(
                        label: Text(label, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          _stampCtrl.text = label;
                          live.setLabelText(label);
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: DsSpacing.sm),
              Text('Color', style: theme.textTheme.labelLarge?.copyWith(fontSize: 13)),
              const SizedBox(height: DsSpacing.xs),
              Wrap(
                spacing: 6,
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () {
                        live.setMarkupColor(c);
                        setState(() {});
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: live.markupColor == c
                                ? const Color(0xFFE4002B)
                                : Colors.black26,
                            width: live.markupColor == c ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DsSpacing.sm),
              Text(
                'Stroke ${live.strokeWidthPt.toStringAsFixed(1)} pt',
                style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
              ),
              Slider(
                value: live.strokeWidthPt.clamp(0.5, 36.0),
                min: 0.5,
                max: 36,
                onChanged: (v) {
                  live.setStrokeWidthPt(v);
                  setState(() {});
                },
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _busy
                    ? const Padding(
                        key: ValueKey('busy'),
                        padding: EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(minHeight: 2),
                      )
                    : live.unburnedDrawCommits.isNotEmpty
                        ? Padding(
                            key: const ValueKey('pending'),
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${live.unburnedDrawCommits.length} unsaved mark(s)',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => unawaited(_burnQueued(live)),
                                  child: const Text('Save now'),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(key: ValueKey('idle')),
              ),
            ],
          );
        },
      ),
    );
  }
}
