import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/live_draw_burn.dart';
import 'package:document_studio/features/pdf_viewer/live_page_text_loader.dart';
import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_text_option_controls.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_shape_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Click existing text to replace it, or click / drag empty space to add a
/// text box (T). Enter or clicking outside commits; the text stays on screen
/// while it is written into the page in the background.
class ViewerEditTextPanel extends ConsumerStatefulWidget {
  const ViewerEditTextPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerEditTextPanel> createState() => _ViewerEditTextPanelState();
}

class _TextJob {
  const _TextJob({
    required this.pendingId,
    required this.page,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.box,
    required this.lines,
    required this.fontSizePt,
    required this.color,
    required this.bold,
    required this.align,
    required this.cover,
  });

  final int pendingId;
  final int page;
  final double pageWidthPt;
  final double pageHeightPt;
  final ui.Rect box;
  final List<String> lines;
  final double fontSizePt;
  final Color color;
  final bool bold;
  final LiveMarginAlign align;
  final ui.Rect? cover;
}

class _ViewerEditTextPanelState extends ConsumerState<ViewerEditTextPanel> {
  static const _palette = <Color>[
    Color(0xFF1A1A1A),
    Color(0xFFE4002B),
    Color(0xFF007AFF),
    Color(0xFF34C759),
    Color(0xFF6B4F2A),
    Color(0xFFFFFFFF),
  ];

  ViewerLiveToolSession? _live;
  Future<void> _queue = Future.value();
  int _jobsRunning = 0;
  int _handledCommitId = 0;
  int _runsLoadedFor = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      if (live.toolId != ViewerToolId.editText) {
        live.activate(
          ViewerToolId.editText,
          pageIndex1Based: widget.handoff.currentPage1,
          awaitingClickPlacement: true,
        );
        live.setFontSizePt(14);
        live.setMarkupColor(const Color(0xFF1A1A1A));
        live.setLabelText('');
      }
      _handledCommitId = live.textCommitRequestId;
      live.addListener(_onLive);
      _onLive();
    });
  }

  @override
  void dispose() {
    _live?.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    final live = _live;
    if (!mounted || live == null || live.toolId != ViewerToolId.editText) return;
    if (live.textCommitRequestId != _handledCommitId) {
      _handledCommitId = live.textCommitRequestId;
      _commitCurrent();
    }
    final page = live.pageIndex1Based;
    if (page != _runsLoadedFor) {
      _runsLoadedFor = page;
      unawaited(_loadRuns(page));
    }
    _safeSetState();
  }

  void _safeSetState() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _loadRuns(int page) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final text = await loadLivePageText(
      file: session?.file ?? widget.handoff.file,
      password: session?.password ?? widget.handoff.password,
      page1Based: page,
      withChars: false,
    );
    final live = _live;
    if (!mounted || live == null || text == null) return;
    if (live.pageIndex1Based != page || live.toolId != ViewerToolId.editText) {
      return;
    }
    live.setTextRunHits(text.runs);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  (double, double, double) _rgb(Color c) => (c.r, c.g, c.b);

  /// Snapshots the edited box synchronously, hands it to the writer queue and
  /// frees the editor so the user can keep typing elsewhere.
  void _commitCurrent() {
    final live = _live;
    if (live == null) return;
    final target = live.textEditTarget;
    final text = (live.labelText ?? '').trimRight();
    if (text.trim().isEmpty && target == null) {
      live.requestTextCancel();
      return;
    }
    if (target != null && text == target.originalText.trimRight()) {
      live.requestTextCancel();
      return;
    }
    final page = live.pageIndex1Based;
    final size = live.pageSizePtFor(page);
    if (size == null) {
      _toast('Page is still loading — try again');
      return;
    }
    final box = live.placement.rect;
    final fontSize = live.fontSizePt;
    final bold = live.textBold;
    final lines = text.trim().isEmpty
        ? const <String>[]
        : wrapPlainTextToWidth(
            text: text,
            maxWidthPt: box.width * size.width,
            fontSizePt: fontSize,
            bold: bold,
          );
    final cover = target?.coverNorm ?? target?.normRect;
    live.finishTextEditAfterCommit();
    final pendingId = live.addPendingText(
      pageIndex1Based: page,
      boxNorm: box,
      lines: lines,
      fontSizePt: fontSize,
      color: live.markupColor,
      bold: bold,
      align: live.textAlign,
      coverNorm: cover,
    );
    final job = _TextJob(
      pendingId: pendingId,
      page: page,
      pageWidthPt: size.width,
      pageHeightPt: size.height,
      box: box,
      lines: lines,
      fontSizePt: fontSize,
      color: live.markupColor,
      bold: bold,
      align: live.textAlign,
      cover: cover,
    );
    _jobsRunning++;
    _queue = _queue.then((_) => _runJob(job)).whenComplete(() {
      _jobsRunning--;
      _safeSetStateIfMounted();
    });
    _safeSetState();
  }

  void _safeSetStateIfMounted() {
    if (mounted) _safeSetState();
  }

  Future<void> _runJob(_TextJob job) async {
    final live = _live;
    final tabs = ref.read(documentTabsControllerProvider);
    final session = tabs.activeSession;
    if (live == null || session == null) {
      live?.removePendingText(job.pendingId);
      return;
    }
    final storage = ref.read(fileStorageProvider);
    final overlay = ref.read(pdfOverlayServiceProvider);
    try {
      var working = session.file;
      final w = job.pageWidthPt;
      final h = job.pageHeightPt;
      final cover = job.cover;
      if (cover != null) {
        final out = await storage.createTempFile(prefix: 'text-cover', suffix: '.pdf');
        await overlay.applyMarkupRectsOnPage(
          input: working,
          outputPath: out,
          pageIndex1Based: job.page,
          rects: [
            PdfOverlayRect(
              xPt: cover.left * w,
              yPt: (1 - cover.bottom) * h,
              widthPt: cover.width * w,
              heightPt: cover.height * h,
              fillRgb: const (1.0, 1.0, 1.0),
            ),
          ],
          password: session.password,
        );
        working = LocalFileRef(path: out, displayName: session.file.displayName);
      }
      if (job.lines.isNotEmpty) {
        final out = await storage.createTempFile(prefix: 'text-draw', suffix: '.pdf');
        await overlay.applyTextLinesOnPage(
          input: working,
          outputPath: out,
          pageIndex1Based: job.page,
          lines: overlayTextLinesForBox(
            lines: job.lines,
            boxNorm: job.box,
            pageWidthPt: w,
            pageHeightPt: h,
            fontSizePt: job.fontSizePt,
            bold: job.bold,
            fillRgb: _rgb(job.color),
            align: job.align,
          ),
          password: session.password,
        );
        working = LocalFileRef(path: out, displayName: session.file.displayName);
      }
      final bytes = Uint8List.fromList(await File(working.path).readAsBytes());
      if (mounted) {
        await commitBytesToSession(
          context: context,
          storage: storage,
          tabs: tabs,
          session: session,
          bytes: bytes,
          successMessage: 'Text saved on page ${job.page}.',
          silent: true,
        );
      } else {
        await session.commitBytes(bytes);
        tabs.syncActiveTabFromSession();
      }
      if (live.pageIndex1Based == job.page &&
          live.toolId == ViewerToolId.editText) {
        unawaited(_loadRuns(job.page));
      }
      await Future<void>.delayed(kLiveBurnHandoverDelay);
      live.removePendingText(job.pendingId);
    } on DocumentStudioError catch (e) {
      live.removePendingText(job.pendingId);
      _toast(e.recoveryHint ?? e.message);
    } catch (e) {
      live.removePendingText(job.pendingId);
      _toast('Could not save text: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.read(viewerLiveToolSessionProvider);
    final editing = live.inlineEditing || live.textEditTarget != null;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ListView(
        padding: const EdgeInsets.all(DsSpacing.pagePaddingCompact),
        children: [
          Text(
            'Click existing text to edit it, or click / drag on empty space to '
            'add a text box. Enter or clicking outside saves, Shift+Enter adds a '
            'line, Esc discards.',
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13),
          ),
          const PdfOptionHeading('Text'),
          const InputDecorator(
            decoration: InputDecoration(
              labelText: 'Font',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            child: Text('Helvetica'),
          ),
          const SizedBox(height: DsSpacing.sm),
          Text(
            'Size ${live.fontSizePt.toStringAsFixed(0)} pt',
            style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          Slider(
            value: live.fontSizePt.clamp(6, 96).toDouble(),
            min: 6,
            max: 96,
            onChanged: live.setFontSizePt,
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilterChip(
              selected: live.textBold,
              label: const Text('Bold', style: TextStyle(fontSize: 13)),
              onSelected: live.setTextBold,
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          PdfTextAlignGroup<LiveMarginAlign>(
            value: live.textAlign,
            left: LiveMarginAlign.left,
            center: LiveMarginAlign.center,
            right: LiveMarginAlign.right,
            onChanged: live.setTextAlign,
          ),
          const PdfOptionHeading('Appearance'),
          PdfCompactColorPicker<Color>(
            colors: _palette,
            selected: live.markupColor,
            swatch: (c) => c,
            onChanged: (c) {
              if (c != null) live.setMarkupColor(c);
            },
          ),
          const SizedBox(height: DsSpacing.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: _jobsRunning > 0
                ? const Row(
                    key: ValueKey('saving'),
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Saving text…', style: TextStyle(fontSize: 13)),
                    ],
                  )
                : editing
                    ? Row(
                        key: const ValueKey('editing'),
                        children: [
                          TextButton(
                            onPressed: live.requestTextCancel,
                            child: const Text('Discard'),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: live.requestTextCommit,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, DsSpacing.controlHeightComfortable),
                            ),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Done'),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(key: ValueKey('idle')),
          ),
        ],
      ),
    );
  }
}
