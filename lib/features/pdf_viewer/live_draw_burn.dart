import 'package:document_studio/core/pdf/page_loader.dart';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_ink_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_shape_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// How long burned marks stay on the overlay after the write, so the page
/// can re-render underneath before the preview disappears (no flicker).
const Duration kLiveBurnHandoverDelay = Duration(milliseconds: 700);

/// Writes queued [LiveDrawCommit]s (ink, shapes, stamps, text markup) into the
/// open PDF.
///
/// * Each mark is burned on the page it was drawn on, with the displayed page
///   size the overlay used — so preview and output line up.
/// * Writes are serialized; marks drawn while a write runs wait for the next.
/// * Owns no widget state: the panel can close (tool deactivated) and pending
///   marks are still flushed.
class LiveDrawBurner {
  LiveDrawBurner({
    required this.live,
    required this.tool,
    required this.overlay,
    required this.storage,
    required this.tabs,
    required this.autosaveEnabled,
    required this.contextOf,
    this.onBusyChanged,
  }) {
    live.addListener(_onLive);
    _snapshot();
  }

  final ViewerLiveToolSession live;
  final ViewerToolId tool;
  final PdfOverlayService overlay;
  final FileStoragePort storage;
  final DocumentTabsController tabs;
  final bool Function() autosaveEnabled;
  final BuildContext? Function() contextOf;
  final ValueChanged<bool>? onBusyChanged;

  /// Unburned marks as last seen — survives `live.deactivate()` clearing them.
  List<LiveDrawCommit> _pending = const [];
  final Set<LiveDrawCommit> _written = {};
  int _seenEpoch = -1;
  Timer? _debounce;
  bool _busy = false;
  bool _again = false;
  bool _disposed = false;

  bool get busy => _busy;

  void _snapshot() {
    if (live.toolId != tool) return;
    _pending = [
      for (final c in live.unburnedDrawCommits)
        if (!_written.contains(c)) c,
    ];
  }

  void _onLive() {
    if (live.toolId != tool) {
      // Tool closed / switched: write whatever was still pending.
      if (_pending.isNotEmpty) flushNow();
      return;
    }
    _snapshot();
    if (live.drawCommitEpoch != _seenEpoch) {
      _seenEpoch = live.drawCommitEpoch;
      if (live.pendingDrawCommit != null) {
        live.clearPendingDrawCommit();
        _schedule();
      }
    }
  }

  void _schedule() {
    _debounce?.cancel();
    if (autosaveEnabled()) {
      _debounce = Timer(kViewerAutosaveDebounce, flushNow);
    } else {
      flushNow();
    }
  }

  /// Writes all pending marks now (serial; coalesces concurrent calls).
  void flushNow() {
    _debounce?.cancel();
    unawaited(_flush());
  }

  /// Stops listening; pending marks are flushed first.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _snapshot();
    live.removeListener(_onLive);
    if (_pending.isNotEmpty) {
      flushNow();
    } else {
      _debounce?.cancel();
    }
  }

  void _setBusy(bool v) {
    _busy = v;
    if (!_disposed) onBusyChanged?.call(v);
  }

  Future<void> _flush() async {
    if (_busy) {
      _again = true;
      return;
    }
    final commits = [
      for (final c in _pending)
        if (!_written.contains(c)) c,
    ];
    if (commits.isEmpty) return;
    final session = tabs.activeSession;
    if (session == null) return;
    _setBusy(true);
    live.markDrawCommitsBurning(commits);
    try {
      final bytes = await _write(
        input: session.file,
        password: session.password,
        commits: commits,
      );
      if (bytes == null) {
        live.unmarkDrawCommitsBurning(commits);
        return;
      }
      final ctx = contextOf();
      if (ctx == null) {
        final outcome = await session.commitBytes(bytes);
        if (outcome == DocumentSaveOutcome.needsSaveAs) {
          live.unmarkDrawCommitsBurning(commits);
          return;
        }
        tabs.syncActiveTabFromSession();
      } else {
        final saved = await commitBytesToSession(
          // ignore: use_build_context_synchronously
          context: ctx,
          storage: storage,
          tabs: tabs,
          session: session,
          bytes: bytes,
          successMessage: 'Markup saved to PDF',
          silent: true,
        );
        if (saved == null) {
          live.unmarkDrawCommitsBurning(commits);
          return;
        }
      }
      _written.addAll(commits);
      _pending = [
        for (final c in _pending)
          if (!_written.contains(c)) c,
      ];
      Timer(kLiveBurnHandoverDelay, () => live.removeDrawCommits(commits));
    } on DocumentStudioError catch (e) {
      live.unmarkDrawCommitsBurning(commits);
      _toast(e.recoveryHint ?? e.message);
    } catch (e) {
      live.unmarkDrawCommitsBurning(commits);
      _toast('Could not save markup: $e');
    } finally {
      _setBusy(false);
      if (_again) {
        _again = false;
        unawaited(_flush());
      }
    }
  }

  void _toast(String msg) {
    final ctx = contextOf();
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Uint8List?> _write({
    required LocalFileRef input,
    required String? password,
    required List<LiveDrawCommit> commits,
  }) async {
    final byPage = <int, List<LiveDrawCommit>>{};
    for (final c in commits) {
      final page = c.pageIndex1Based > 0 ? c.pageIndex1Based : live.pageIndex1Based;
      byPage.putIfAbsent(page, () => []).add(c);
    }
    final tempDir = await storage.getTempDirectory();
    var working = input;
    final temps = <String>[];
    String nextTemp(String tag) {
      final path = p.join(
        tempDir,
        'live-$tag-${DateTime.now().microsecondsSinceEpoch}-${temps.length}.pdf',
      );
      temps.add(path);
      return path;
    }

    try {
      for (final entry in byPage.entries) {
        final page = entry.key;
        final size = live.pageSizePtFor(page) ??
            await _loadPageSize(input, page, password);
        final w = size.width;
        final h = size.height;
        final ink = <PdfInkStroke>[];
        final rects = <PdfOverlayRect>[];
        final texts = <PdfOverlayTextLine>[];
        final stamps = <LiveDrawCommit>[];
        for (final c in entry.value) {
          final kind = c.markupKind;
          if (kind != null) {
            _markupToPdf(c, kind, w, h, rects, texts);
          } else if (c.tool == LiveDrawTool.stamp) {
            stamps.add(c);
          } else if (c.pointsNorm.length >= 2) {
            ink.add(
              PdfInkStroke(
                points: [
                  for (final o in c.pointsNorm) (o.dx * w, (1 - o.dy) * h),
                ],
                widthPt: c.strokeWidthPt,
                colorRgb: _rgb(c.color),
                opacity: c.opacity,
                closed: c.closed,
              ),
            );
          }
        }
        if (rects.isNotEmpty) {
          final out = nextTemp('rects');
          await overlay.applyMarkupRectsOnPage(
            input: working,
            outputPath: out,
            pageIndex1Based: page,
            rects: rects,
            password: password,
          );
          working = LocalFileRef(path: out, displayName: 'tmp.pdf');
        }
        if (ink.isNotEmpty) {
          final out = nextTemp('ink');
          await overlay.applyInkStrokesOnPage(
            input: working,
            outputPath: out,
            pageIndex1Based: page,
            strokes: ink,
            password: password,
          );
          working = LocalFileRef(path: out, displayName: 'tmp.pdf');
        }
        if (texts.isNotEmpty) {
          final out = nextTemp('text');
          await overlay.applyTextLinesOnPage(
            input: working,
            outputPath: out,
            pageIndex1Based: page,
            lines: texts,
            password: password,
          );
          working = LocalFileRef(path: out, displayName: 'tmp.pdf');
        }
        if (stamps.isNotEmpty) {
          final out = nextTemp('stamp');
          await overlay.applyStampLabelsOnPage(
            input: working,
            outputPath: out,
            pageIndex1Based: page,
            stamps: [
              for (final s in stamps)
                (
                  boxNorm: _boundsOf(s.pointsNorm),
                  label: s.labelText ?? 'APPROVED',
                  rgb: _rgb(s.color),
                ),
            ],
            password: password,
          );
          working = LocalFileRef(path: out, displayName: 'tmp.pdf');
        }
      }
      if (identical(working, input)) return null;
      return Uint8List.fromList(await File(working.path).readAsBytes());
    } finally {
      for (final t in temps) {
        try {
          await File(t).delete();
        } catch (_) {}
      }
    }
  }

  void _markupToPdf(
    LiveDrawCommit c,
    LiveMarkupKind kind,
    double w,
    double h,
    List<PdfOverlayRect> rects,
    List<PdfOverlayTextLine> texts,
  ) {
    PdfOverlayRect band(Rect r, {(double, double, double)? stroke}) =>
        PdfOverlayRect(
          xPt: r.left * w,
          yPt: (1 - r.bottom) * h,
          widthPt: r.width * w,
          heightPt: r.height * h,
          fillRgb: _rgb(c.color),
          fillOpacity: c.opacity,
          strokeRgb: stroke,
          strokeWidthPt: stroke == null ? 0 : 0.75,
        );
    if (kind != LiveMarkupKind.note) {
      for (final r in c.rectsNorm) {
        rects.add(band(r));
      }
      return;
    }
    final box = c.rectsNorm.first;
    rects.add(band(box, stroke: _rgb(kLiveNoteStroke)));
    final lines = liveNoteLines(c.labelText ?? '', widthPt: box.width * w);
    final inner = Rect.fromLTRB(
      box.left + kLiveNotePadPt / w,
      box.top + kLiveNotePadPt / h,
      box.right - kLiveNotePadPt / w,
      box.bottom - kLiveNotePadPt / h,
    );
    texts.addAll(
      overlayTextLinesForBox(
        lines: lines,
        boxNorm: inner,
        pageWidthPt: w,
        pageHeightPt: h,
        fontSizePt: kLiveNoteFontPt,
        bold: false,
        fillRgb: (0.13, 0.13, 0.13),
      ),
    );
  }

  static Rect _boundsOf(List<Offset> pts) {
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final o in pts) {
      if (o.dx < minX) minX = o.dx;
      if (o.dy < minY) minY = o.dy;
      if (o.dx > maxX) maxX = o.dx;
      if (o.dy > maxY) maxY = o.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static (double, double, double) _rgb(Color c) => (c.r, c.g, c.b);

  static Future<Size> _loadPageSize(
    LocalFileRef input,
    int page1Based,
    String? password,
  ) async {
    final doc = await openPdfLazily(input.path, password: password);
    try {
      final page = await loadPageOnDemand(
            doc,
            page1Based.clamp(1, doc.pages.length),
          ) ??
          doc.pages.first;
      return Size(page.width, page.height);
    } finally {
      await doc.dispose();
    }
  }
}
