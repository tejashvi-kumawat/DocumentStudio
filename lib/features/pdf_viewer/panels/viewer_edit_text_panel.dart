import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_stamp.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:document_studio/core/fonts/font_identifier.dart';
import 'package:document_studio/core/fonts/font_library.dart';
import 'package:document_studio/core/pdf/large_doc_policy.dart';

import 'dart:async';
import 'dart:io';
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
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_shape_builder.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Click existing text to replace it, or click / drag empty space to add a
/// text box (T). Enter or clicking outside commits; the text stays on screen
/// while it is written into the page in the background.
/// Pictures, vector shapes, annotations and font hints of [args.$2] pages,
/// read from the file at [args.$1]. Runs in a background isolate.
(Map<int, List<EditableImage>>, Map<int, List<TextFontHint>>) _scanPageObjects(
  (String, List<int>) args,
) {
  final (path, pages) = args;
  final bytes = File(path).readAsBytesSync();
  return (
    {
      for (final p in pages)
        p: <EditableImage>[
          ...findPageImages(bytes, p),
          ...findPageShapes(bytes, p),
          ...findPageAnnotations(bytes, p),
        ],
    },
    {for (final p in pages) p: findPageTextFonts(bytes, p)},
  );
}

class _TextEditArgs {
  const _TextEditArgs({
    required this.path,
    required this.outPath,
    required this.page,
    required this.pageWidthPt,
    required this.pageHeightPt,
    required this.covers,
    required this.coverRgb,
    required this.lines,
    required this.linkFrom,
    required this.linkTo,
  });

  final String path;
  final String outPath;
  final int page;
  final double pageWidthPt;
  final double pageHeightPt;
  final List<List<double>> covers;
  final List<double> coverRgb;
  final List<PdfOverlayTextLine> lines;
  final List<double>? linkFrom;
  final List<double> linkTo;
}

/// Background half of a text edit (see `_runJobFast`).
bool _applyTextEdit(_TextEditArgs a) {
  final out = _editTextBytes(File(a.path).readAsBytesSync(), a);
  if (out == null) return false;
  File(a.outPath).writeAsBytesSync(out, flush: true);
  return true;
}

/// Several text edits in one pass over the file (one read, one write, one
/// reload in the viewer). Returns how many could not be written.
int _applyTextEdits((String, String, List<_TextEditArgs>) args) {
  final (path, outPath, edits) = args;
  var bytes = File(path).readAsBytesSync();
  var failed = 0;
  for (final a in edits) {
    final next = _editTextBytes(bytes, a);
    if (next == null) {
      failed++;
    } else {
      bytes = next;
    }
  }
  File(outPath).writeAsBytesSync(bytes, flush: true);
  return failed;
}

Uint8List? _editTextBytes(Uint8List input, _TextEditArgs a) {
  ui.Rect r(List<double> v) => ui.Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  var bytes = input;
  var covers = [for (final c in a.covers) r(c)];
  if (covers.isNotEmpty) {
    final stripped = removeTextInRects(bytes, a.page, covers);
    if (stripped != null) {
      bytes = stripped;
      covers = const [];
    }
  }
  if (a.lines.isNotEmpty || covers.isNotEmpty) {
    final overlay = a.lines.isEmpty
        ? null
        : PdfOverlayTextBuilder().build(
            pageCount: 1,
            pageWidthPt: (_) => a.pageWidthPt,
            pageHeightPt: (_) => a.pageHeightPt,
            linesForPage: (_) => a.lines,
          );
    final stamped = stampOverlayOnPage(
      bytes,
      a.page,
      overlay,
      covers: covers,
      coverRgb: (a.coverRgb[0], a.coverRgb[1], a.coverRgb[2]),
    );
    if (stamped == null) return null;
    bytes = stamped;
  }
  final from = a.linkFrom;
  if (from != null &&
      (r(from).topLeft - r(a.linkTo).topLeft).distance > 0.002) {
    bytes = moveLinksWithBlock(bytes, a.page, r(from), r(a.linkTo)) ?? bytes;
  }
  return bytes;
}

/// One queued object edit, in a form that can cross isolates.
class _ObjEdit {
  const _ObjEdit({
    required this.kind,
    required this.objKind,
    required this.page,
    required this.opStart,
    required this.form,
    required this.name,
    required this.rect,
    this.newRect,
    this.rgb,
    this.replacement,
  });

  final int kind; // ImageEditKind.index
  final int objKind; // EditableKind.index
  final int page;
  final int opStart;
  final int form;
  final String name;
  final List<double> rect; // as shown when edited (normalized LTRB)
  final List<double>? newRect;
  final List<double>? rgb;
  final Uint8List? replacement;
}

/// Applies [args.$3] in order to the PDF at [args.$1], writing [args.$2].
/// Each object is found again (same content offset, else nearest in place),
/// since every edit shifts the offsets of the ones after it.
({int applied, int failed}) _applyObjectEdits(
  (String, String, List<_ObjEdit>) args,
) {
  final (path, outPath, edits) = args;
  var bytes = File(path).readAsBytesSync();
  var applied = 0, failed = 0;
  ui.Rect r(List<double> v) => ui.Rect.fromLTRB(v[0], v[1], v[2], v[3]);
  for (final e in edits) {
    final kind = ImageEditKind.values[e.kind];
    final objKind = EditableKind.values[e.objKind];
    Uint8List? out;
    if (objKind == EditableKind.annotation) {
      out = switch (kind) {
        ImageEditKind.delete => deletePageAnnotation(
          bytes,
          e.page,
          e.opStart,
          e.name,
        ),
        ImageEditKind.move => transformPageAnnotation(
          bytes,
          e.page,
          e.opStart,
          e.name,
          r(e.newRect ?? e.rect),
        ),
        _ => null,
      };
    } else {
      final shape = objKind == EditableKind.shape;
      final current = shape
          ? findPageShapes(bytes, e.page)
          : findPageImages(bytes, e.page);
      final want = r(e.rect).center;
      EditableImage? t;
      var best = 0.02;
      for (final i in current) {
        final d = (i.normRect.center - want).distance;
        if (i.form == e.form && i.opStart == e.opStart && d < 0.002) {
          t = i;
          break;
        }
        if (d < best) {
          best = d;
          t = i;
        }
      }
      if (t != null) {
        out = switch (kind) {
          ImageEditKind.delete =>
            shape
                ? deletePageShape(bytes, t.page, t.opStart, form: t.form)
                : deletePageImage(bytes, t.page, t.opStart, form: t.form),
          ImageEditKind.move =>
            shape
                ? transformPageShape(
                    bytes,
                    t.page,
                    t.opStart,
                    r(e.newRect ?? e.rect),
                    form: t.form,
                  )
                : transformPageImage(
                    bytes,
                    t.page,
                    t.opStart,
                    r(e.newRect ?? e.rect),
                    form: t.form,
                  ),
          ImageEditKind.recolor =>
            (!shape || e.rgb == null)
                ? null
                : recolorPageShape(
                    bytes,
                    t.page,
                    t.opStart,
                    e.rgb![0],
                    e.rgb![1],
                    e.rgb![2],
                    form: t.form,
                  ),
          ImageEditKind.replace =>
            e.replacement == null
                ? null
                : replacePageImage(
                    bytes,
                    t.page,
                    t.opStart,
                    e.replacement!,
                    form: t.form,
                  ),
        };
      }
    }
    if (out == null) {
      failed++;
    } else {
      bytes = out;
      applied++;
    }
  }
  if (applied > 0) File(outPath).writeAsBytesSync(bytes, flush: true);
  return (applied: applied, failed: failed);
}

class ViewerEditTextPanel extends ConsumerStatefulWidget {
  const ViewerEditTextPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerEditTextPanel> createState() =>
      _ViewerEditTextPanelState();
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
    this.coverRects = const [],
    this.coverColor,
    this.italic = false,
    this.fontBase = 'Helvetica',
    this.family = 'sans',
    this.lineHeightEm = 1.2,
    this.userFont,
    this.embed = false,
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
  final List<ui.Rect> coverRects;
  final Color? coverColor;
  final bool italic;
  final String fontBase;
  final String family;
  final double lineHeightEm;
  final InstalledFont? userFont;
  final bool embed;
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
    unawaited(FontLibrary.instance.ensureLoaded());
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
        final prefs = ref.read(viewerPrefsProvider);
        live.setFontSizePt(prefs.textSize);
        live.setTextFamily(prefs.textFamily);
        live.setMarkupColor(const Color(0xFF1A1A1A));
        live.setLabelText('');
      }
      _handledCommitId = live.textCommitRequestId;
      _tabs = ref.read(documentTabsControllerProvider);
      _flushSession = _tabs!.activeSession;
      _flushSession?.pendingFlushers.add(_flushObjectEdits);
      _flushSession?.pendingFlushers.add(_flushText);
      live.imageEditHandler = (r) => unawaited(_onImageEdit(r));
      live.objectSnapshot = (page, norm, widthPx) async {
        final session = _flushSession;
        if (session == null) return null;
        return renderPageRegion(
          path: session.file.path,
          password: session.password,
          page1: page,
          norm: norm,
          widthPx: widthPx,
        );
      };
      live.addListener(_onLive);
      _onLive();
    });
  }

  DocumentTabsController? _tabs;

  @override
  void dispose() {
    // Leaving Edit writes what is still queued (the session outlives us).
    _objTimer?.cancel();
    if (_pendingObj.isNotEmpty) unawaited(_applyBatch(List.of(_pendingObj)));
    _textTimer?.cancel();
    if (_pendingText.isNotEmpty) unawaited(_flushText());
    _flushSession?.pendingFlushers.remove(_flushObjectEdits);
    _flushSession?.pendingFlushers.remove(_flushText);
    _live?.imageEditHandler = null;
    _live?.objectSnapshot = null;
    _live?.removeListener(_onLive);
    super.dispose();
  }

  void _onLive() {
    final live = _live;
    if (!mounted || live == null || live.toolId != ViewerToolId.editText) {
      return;
    }
    if (live.textCommitRequestId != _handledCommitId) {
      _handledCommitId = live.textCommitRequestId;
      _commitCurrent();
    }
    _syncLibraryStyle(live);
    final page = live.pageIndex1Based;
    if (page != _runsLoadedFor) {
      _runsLoadedFor = page;
      unawaited(_loadRuns(page));
    }
    _safeSetState();
  }

  /// Bold / italic on a library font swap to that style's own file.
  void _syncLibraryStyle(ViewerLiveToolSession live) {
    final f = live.textUserFont;
    final fam = f?.libraryFamily;
    if (f == null || fam == null) return;
    if (f.ttf.bold == live.textBold && f.ttf.italic == live.textItalic) return;
    final wantBold = live.textBold, wantItalic = live.textItalic;
    unawaited(
      FontLibrary.instance
          .loadLibraryFont(fam, bold: wantBold, italic: wantItalic)
          .then((next) {
            if (next == null || identical(next, live.textUserFont)) return;
            if (live.textBold == wantBold && live.textItalic == wantItalic) {
              live.setTextUserFont(next);
            }
          }),
    );
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

  /// Loads editable blocks for [page] and its neighbours in one document
  /// open, so boxes show on every page in view without clicking.
  Future<void> _loadRuns(int page, {bool force = false}) async {
    final live = _live;
    if (live == null) return;
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final wanted = <int>[
      for (final n in [page, page + 1, page - 1])
        if (n >= 1 && (force || !live.hasTextRunsForPage(n))) n,
    ];
    if (wanted.isEmpty) return;
    final blocks = await loadEditableTextBlocks(
      file: session?.file ?? widget.handoff.file,
      password: session?.password ?? widget.handoff.password,
      pages: wanted,
    );
    if (!mounted || live.toolId != ViewerToolId.editText) return;
    blocks.forEach(live.setTextRunsForPage);
    unawaited(_scanObjects(wanted, blocks, live));
  }

  /// One off-thread pass over the file for the pages' pictures, shapes and
  /// fonts. The isolate reads the file itself, so nothing is copied.
  Future<void> _scanObjects(
    List<int> pages,
    Map<int, List<LiveTextEditTarget>> blocks,
    ViewerLiveToolSession live,
  ) async {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session == null) return;
    try {
      if (!await LargeDocPolicy.allowsAnalysis(session)) return;
      final path = session.file.path;
      // Top-level entry point: only the path and page list cross isolates.
      final found = await compute(_scanPageObjects, (path, pages));
      if (!mounted || live.toolId != ViewerToolId.editText) return;
      found.$1.forEach(live.setImagesForPage);
      // Recognise each font once (name, embedded family, glyph widths) and
      // load its bundled twin before the blocks get it, so opening a block
      // shows — and saves with — the matching typeface at once.
      final identifier = await FontLibrary.instance.identifier();
      final ids = <String, FontIdentity>{};
      for (final hs in found.$2.values) {
        for (final h in hs) {
          final ev = h.evidence;
          if (ev != null)
            ids.putIfAbsent(ev.name, () => identifier.identify(ev));
        }
      }
      await Future.wait([
        for (final id in ids.values)
          FontLibrary.instance.loadLibraryFont(
            id.family,
            bold: id.bold,
            italic: id.italic,
          ),
      ]);
      if (!mounted || live.toolId != ViewerToolId.editText) return;
      _applyFonts(blocks, found.$2, ids, live);
    } catch (e, st) {
      debugPrint('Edit: object scan failed: $e\n$st');
    }
  }

  /// Font recognition: each editable block takes the font that shows most
  /// of its text (a bold first word or a bullet glyph does not decide).
  void _applyFonts(
    Map<int, List<LiveTextEditTarget>> blocks,
    Map<int, List<TextFontHint>> hints,
    Map<String, FontIdentity> ids,
    ViewerLiveToolSession live,
  ) {
    for (final p in blocks.keys) {
      final ph = hints[p] ?? const <TextFontHint>[];
      if (ph.isEmpty) continue;
      final enriched = <LiveTextEditTarget>[];
      for (final b in blocks[p]!) {
        final box = (b.coverNorm ?? b.normRect).inflate(0.004);
        final votes = <String, int>{};
        TextFontHint? sample;
        for (final h in ph) {
          if (!box.contains(h.origin)) continue;
          final n = votes[h.baseFont] = (votes[h.baseFont] ?? 0) + h.weight;
          if (sample == null || n > (votes[sample.baseFont] ?? 0)) sample = h;
        }
        if (sample == null) {
          enriched.add(b);
          continue;
        }
        final id = ids[sample.baseFont];
        final cls = classifyBaseFont(sample.baseFont);
        final cat = id == null
            ? null
            : FontLibrary.instance.categoryOf(id.family);
        enriched.add(
          LiveTextEditTarget(
            normRect: b.normRect,
            originalText: b.originalText,
            fontSizePt: b.fontSizePt,
            coverNorm: b.coverNorm,
            coverRects: b.coverRects,
            coverColor: b.coverColor,
            textColor: b.textColor,
            lineCount: b.lineCount,
            fontMatch: FontMatch(
              family: switch (cat) {
                'serif' => 'serif',
                'monospace' => 'mono',
                null => cls.family,
                _ => 'sans',
              },
              bold: id?.bold ?? cls.bold,
              italic: id?.italic ?? cls.italic,
              original: sample.baseFont,
              libraryFamily: id?.family,
              how: id?.how,
            ),
            leadingEm: b.leadingEm,
          ),
        );
      }
      live.setTextRunsForPage(p, enriched);
    }
  }

  /// Object edits (move / resize / delete / recolor / replace of pictures,
  /// shapes and comments) show at once and are written to the document in
  /// one batch a moment after the last change — or right away on Save, Undo,
  /// Redo or leaving Edit. The heavy PDF work runs off the UI thread, so the
  /// page never freezes while you arrange things.
  final List<_ObjEdit> _pendingObj = [];
  Timer? _objTimer;
  Future<void>? _objFlush;
  DocumentSession? _flushSession;

  static const _objIdle = Duration(milliseconds: 450);

  Future<void> _onImageEdit(ImageEditRequest r) async {
    final live = _live;
    if (live == null) return;
    Uint8List? replacement;
    if (r.kind == ImageEditKind.replace) {
      final picked = await ref
          .read(fileStorageProvider)
          .pickOpenFile(allowedExtensions: const ['png', 'jpg', 'jpeg']);
      if (picked == null) return;
      replacement = Uint8List.fromList(await File(picked.path).readAsBytes());
    }
    _pendingObj.add(
      _ObjEdit(
        kind: r.kind.index,
        objKind: r.image.kind.index,
        page: r.image.page,
        opStart: r.image.opStart,
        form: r.image.form,
        name: r.image.name,
        rect: _ltrb(r.image.normRect),
        newRect: r.rect == null ? null : _ltrb(r.rect!),
        rgb: r.color == null ? null : [r.color!.r, r.color!.g, r.color!.b],
        replacement: replacement,
      ),
    );
    // Optimistic: the object's box follows the change immediately.
    final list = [...live.imagesForPage(r.image.page)];
    final i = list.indexWhere(
      (x) =>
          x.kind == r.image.kind &&
          x.form == r.image.form &&
          x.opStart == r.image.opStart &&
          x.normRect == r.image.normRect,
    );
    if (i >= 0) {
      if (r.kind == ImageEditKind.delete) {
        list.removeAt(i);
      } else if (r.kind == ImageEditKind.move && r.rect != null) {
        final moved = EditableImage(
          page: list[i].page,
          name: list[i].name,
          opStart: list[i].opStart,
          normRect: r.rect!,
          kind: list[i].kind,
          form: list[i].form,
        );
        list[i] = moved;
        live.setImagesForPage(r.image.page, list);
        live.selectImage(moved);
      }
      if (r.kind == ImageEditKind.delete) {
        live.setImagesForPage(r.image.page, list);
      }
    }
    _objTimer?.cancel();
    _objTimer = Timer(
      // Deletes and replacements are written at once; moves wait briefly so
      // arrow-key nudges and quick drags go out as one change.
      r.kind == ImageEditKind.move ? _objIdle : Duration.zero,
      () => unawaited(_flushObjectEdits()),
    );
    _safeSetState();
  }

  static List<double> _ltrb(ui.Rect r) => [r.left, r.top, r.right, r.bottom];

  /// Writes every queued object edit into the document (one commit).
  Future<void> _flushObjectEdits() async {
    _objTimer?.cancel();
    final running = _objFlush;
    if (running != null) await running;
    if (_pendingObj.isEmpty) return;
    final batch = List.of(_pendingObj);
    _pendingObj.clear();
    final f = _applyBatch(batch);
    _objFlush = f;
    try {
      await f;
    } finally {
      if (identical(_objFlush, f)) _objFlush = null;
    }
  }

  Future<void> _applyBatch(List<_ObjEdit> batch) async {
    final session = _flushSession;
    if (session == null) return;
    _jobsRunning++;
    _safeSetStateIfMounted();
    try {
      if (!await LargeDocPolicy.allowsAnalysis(session)) {
        _toast(LargeDocPolicy.message);
        return;
      }
      final dir = await Directory.systemTemp.createTemp('ds_obj_');
      final out = '${dir.path}/out.pdf';
      final res = await compute(_applyObjectEdits, (
        session.file.path,
        out,
        batch,
      ));
      if (res.failed > 0) {
        _toast(
          res.applied == 0
              ? 'That item changed in the meantime — select it again.'
              : '${res.failed} change(s) could not be applied.',
        );
      }
      if (res.applied == 0) {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
        return;
      }
      final outcome = await session.commitTempFile(out);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      final tabs = _tabs;
      if (outcome == DocumentSaveOutcome.needsSaveAs) {
        final bytes = session.pendingReplaceBytes;
        if (bytes != null && mounted && tabs != null) {
          await commitBytesToSession(
            context: context,
            storage: ref.read(fileStorageProvider),
            tabs: tabs,
            session: session,
            bytes: bytes,
            successMessage: 'Changes applied.',
          );
        }
      } else {
        tabs?.syncActiveTabFromSession();
      }
      final live = _live;
      final pages = {for (final e in batch) e.page};
      if (mounted && live != null && live.toolId == ViewerToolId.editText) {
        await Future.wait([for (final p in pages) _loadRuns(p, force: true)]);
      }
      // The page now shows the change itself; drop the stand-ins unless
      // newer edits on that page are still queued.
      for (final p in pages) {
        if (!_pendingObj.any((e) => e.page == p)) live?.clearGhosts(p);
      }
    } catch (e) {
      _toast('Could not apply the change: $e');
    } finally {
      _jobsRunning--;
      _safeSetStateIfMounted();
    }
  }

  /// Lets the user pick a .ttf and installs it for this and future edits.
  Future<void> _addFont() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: const ['ttf']);
    if (picked == null) return;
    final font = await FontLibrary.instance.install(picked.path);
    if (!mounted) return;
    if (font == null) {
      _toast('That file is not a usable TrueType (.ttf) font.');
      return;
    }
    _live?.setTextUserFont(font);
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
    if (target != null && !live.textEditChanged) {
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
            measure: live.textMeasure(fontSize),
          );
    final cover = target?.coverNorm ?? target?.normRect;
    final coverRects = target == null
        ? const <ui.Rect>[]
        : (target.coverRects.isNotEmpty
              ? target.coverRects
              : [target.coverNorm ?? target.normRect]);
    final coverColor = target?.coverColor;
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
      coverRects: coverRects,
      coverColor: coverColor,
      italic: live.textItalic,
      family: live.textFamily,
      lineHeightEm: live.textLineHeightEm,
      customFamily: live.textUserFont?.flutterFamily,
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
      coverRects: coverRects,
      coverColor: coverColor,
      italic: live.textItalic,
      fontBase: live.textFontBase,
      family: live.textFamily,
      lineHeightEm: live.textLineHeightEm,
      userFont: live.textUserFont,
      embed: live.embedFonts,
    );
    _queueText(job);
    _safeSetState();
  }

  /// Text edits wait a moment and go out together: the new text shows at
  /// once, and a burst of edits costs one write and one page reload. Save,
  /// Undo, Redo, leaving Edit, or editing over a waiting block write first.
  final List<_TextJob> _pendingText = [];
  Timer? _textTimer;
  static const _textIdle = Duration(milliseconds: 1200);

  void _queueText(_TextJob job) {
    bool hits(_TextJob a, _TextJob b) {
      if (a.page != b.page) return false;
      final ra = [a.box, ...a.coverRects], rb = [b.box, ...b.coverRects];
      return ra.any((x) => rb.any((y) => x.overlaps(y)));
    }

    if (_pendingText.any((p) => hits(p, job))) unawaited(_flushText());
    _pendingText.add(job);
    _textTimer?.cancel();
    _textTimer = Timer(_textIdle, () => unawaited(_flushText()));
  }

  Future<void> _flushText() {
    _textTimer?.cancel();
    if (_pendingText.isEmpty) return _queue;
    final batch = List.of(_pendingText);
    _pendingText.clear();
    _jobsRunning++;
    _safeSetStateIfMounted();
    return _queue = _queue.then((_) => _runTextBatch(batch)).whenComplete(() {
      _jobsRunning--;
      _safeSetStateIfMounted();
    });
  }

  Future<void> _runTextBatch(List<_TextJob> batch) async {
    final live = _live;
    // Captured at start: this may run after leaving Edit (no `ref` then).
    final tabs = _tabs;
    final session = _flushSession;
    if (live == null || tabs == null || session == null) {
      for (final j in batch) {
        live?.removePendingText(j.pendingId);
      }
      return;
    }
    if (!await LargeDocPolicy.allowsAnalysis(session)) {
      // Very large files: the qpdf path, one edit at a time.
      for (final j in batch) {
        if (mounted) {
          await _runJob(j);
        } else {
          live.removePendingText(j.pendingId);
        }
      }
      return;
    }
    if (batch.length == 1) {
      await _runJobFast(batch.single, session, tabs, live);
      return;
    }
    try {
      final args = <_TextEditArgs>[];
      for (final job in batch) {
        args.add(await _argsFor(job, session, ''));
      }
      final dir = await Directory.systemTemp.createTemp('ds_text_');
      final DocumentSaveOutcome outcome;
      try {
        final out = '${dir.path}/out.pdf';
        final failed = await compute(_applyTextEdits, (
          session.file.path,
          out,
          args,
        ));
        if (failed > 0)
          _toast('$failed text change(s) could not be written into the page.');
        outcome = await session.commitTempFile(out);
      } finally {
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
      }
      if (outcome == DocumentSaveOutcome.needsSaveAs) {
        final bytes = session.pendingReplaceBytes;
        if (bytes != null && mounted) {
          await commitBytesToSession(
            context: context,
            storage: ref.read(fileStorageProvider),
            tabs: tabs,
            session: session,
            bytes: bytes,
            successMessage: 'Text saved.',
          );
        }
      } else {
        tabs.syncActiveTabFromSession();
      }
      final pages = {for (final j in batch) j.page};
      if (mounted && live.toolId == ViewerToolId.editText) {
        await Future.wait([for (final p in pages) _loadRuns(p, force: true)]);
      }
      await Future<void>.delayed(kLiveBurnHandoverDelay);
    } catch (e) {
      _toast('Could not save text: $e');
    } finally {
      for (final j in batch) {
        live.removePendingText(j.pendingId);
      }
    }
  }

  /// The isolate's half of [job] (lines laid out, font chosen).
  Future<_TextEditArgs> _argsFor(
    _TextJob job,
    DocumentSession session,
    String outPath,
  ) async {
    final ttf = job.lines.isEmpty
        ? null
        : (job.userFont?.ttf ??
              (job.embed
                  ? await FontLibrary.instance.bundledFor(
                      family: job.family,
                      bold: job.bold,
                      italic: job.italic,
                    )
                  : null));
    final lines = job.lines.isEmpty
        ? const <PdfOverlayTextLine>[]
        : overlayTextLinesForBox(
            lines: job.lines,
            boxNorm: job.box,
            pageWidthPt: job.pageWidthPt,
            pageHeightPt: job.pageHeightPt,
            fontSizePt: job.fontSizePt,
            bold: job.bold,
            fillRgb: _rgb(job.color),
            align: job.align,
            fontBase: job.fontBase,
            lineHeightEm: job.lineHeightEm,
            ttf: ttf,
          );
    final bg = job.coverColor ?? Colors.white;
    return _TextEditArgs(
      path: session.file.path,
      outPath: outPath,
      page: job.page,
      pageWidthPt: job.pageWidthPt,
      pageHeightPt: job.pageHeightPt,
      covers: [
        for (final c in job.coverRects) [c.left, c.top, c.right, c.bottom],
      ],
      coverRgb: [bg.r, bg.g, bg.b],
      lines: lines,
      linkFrom: job.cover == null
          ? null
          : [
              job.cover!.left,
              job.cover!.top,
              job.cover!.right,
              job.cover!.bottom,
            ],
      linkTo: [job.box.left, job.box.top, job.box.right, job.box.bottom],
    );
  }

  void _safeSetStateIfMounted() {
    if (mounted) _safeSetState();
  }

  /// Text edit, all in one background isolate and written incrementally:
  /// strip the old text, stamp the new lines (embedded font subset if any)
  /// and keep links with a moved block. No qpdf pass, no whole-file rewrite.
  Future<void> _runJobFast(
    _TextJob job,
    DocumentSession session,
    DocumentTabsController tabs,
    ViewerLiveToolSession live,
  ) async {
    try {
      final dir = await Directory.systemTemp.createTemp('ds_text_');
      final out = '${dir.path}/out.pdf';
      final ok = await compute(
        _applyTextEdit,
        await _argsFor(job, session, out),
      );
      if (!ok) {
        live.removePendingText(job.pendingId);
        _toast('Could not write the text into this page.');
        try {
          await dir.delete(recursive: true);
        } catch (_) {}
        return;
      }
      final outcome = await session.commitTempFile(out);
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      if (outcome == DocumentSaveOutcome.needsSaveAs) {
        final bytes = session.pendingReplaceBytes;
        if (bytes != null && mounted) {
          await commitBytesToSession(
            context: context,
            storage: ref.read(fileStorageProvider),
            tabs: tabs,
            session: session,
            bytes: bytes,
            successMessage: 'Text saved on page ${job.page}.',
          );
        }
      } else {
        tabs.syncActiveTabFromSession();
      }
      if (mounted &&
          live.pageIndex1Based == job.page &&
          live.toolId == ViewerToolId.editText) {
        unawaited(_loadRuns(job.page, force: true));
      }
      await Future<void>.delayed(kLiveBurnHandoverDelay);
      live.removePendingText(job.pendingId);
    } catch (e) {
      live.removePendingText(job.pendingId);
      _toast('Could not save text: $e');
    }
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
    if (await LargeDocPolicy.allowsAnalysis(session)) {
      await _runJobFast(job, session, tabs, live);
      return;
    }
    final temps = <String>[];
    try {
      var working = session.file;
      final w = job.pageWidthPt;
      final h = job.pageHeightPt;
      var covers = job.coverRects;
      if (covers.isNotEmpty) {
        // Best case: take the original text out of the page itself, so no
        // box is painted over backgrounds or pictures.
        final srcBytes =
            (await File(working.path).length()) <=
                LargeDocPolicy.analysisByteLimit
            ? await File(working.path).readAsBytes()
            : null;
        final stripped = srcBytes == null
            ? null
            : removeTextInRects(srcBytes, job.page, covers);
        if (stripped != null) {
          final out = await storage.createTempFile(
            prefix: 'text-strip',
            suffix: '.pdf',
          );
          temps.add(out);
          await File(out).writeAsBytes(stripped, flush: true);
          working = LocalFileRef(
            path: out,
            displayName: session.file.displayName,
          );
          covers = const [];
        }
      }
      if (covers.isNotEmpty) {
        final bg = job.coverColor ?? Colors.white;
        final out = await storage.createTempFile(
          prefix: 'text-cover',
          suffix: '.pdf',
        );
        temps.add(out);
        await overlay.applyMarkupRectsOnPage(
          input: working,
          outputPath: out,
          pageIndex1Based: job.page,
          rects: [
            for (final cover in covers)
              PdfOverlayRect(
                xPt: cover.left * w,
                yPt: (1 - cover.bottom) * h,
                widthPt: cover.width * w,
                heightPt: cover.height * h,
                fillRgb: (bg.r, bg.g, bg.b),
              ),
          ],
          password: session.password,
        );
        working = LocalFileRef(
          path: out,
          displayName: session.file.displayName,
        );
      }
      if (job.lines.isNotEmpty) {
        // Embedded font: the installed one, or the bundled Liberation twin of
        // the chosen standard family when "Embed font" is on.
        final ttf =
            job.userFont?.ttf ??
            (job.embed
                ? await FontLibrary.instance.bundledFor(
                    family: job.family,
                    bold: job.bold,
                    italic: job.italic,
                  )
                : null);
        final out = await storage.createTempFile(
          prefix: 'text-draw',
          suffix: '.pdf',
        );
        temps.add(out);
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
            fontBase: job.fontBase,
            lineHeightEm: job.lineHeightEm,
            ttf: ttf,
          ),
          password: session.password,
        );
        working = LocalFileRef(
          path: out,
          displayName: session.file.displayName,
        );
      }
      var bytes = Uint8List.fromList(await File(working.path).readAsBytes());
      // A moved block takes its hyperlinks along.
      final from = job.cover;
      if (from != null &&
          (from.topLeft - job.box.topLeft).distance > 0.002 &&
          bytes.length <= LargeDocPolicy.analysisByteLimit) {
        bytes = moveLinksWithBlock(bytes, job.page, from, job.box) ?? bytes;
      }
      for (final t in temps) {
        unawaited(storage.deleteIfExists(t));
      }
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
        unawaited(_loadRuns(job.page, force: true));
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
            'Click any text block to edit it. Enter saves, Shift+Enter adds a '
            'line, Esc discards.',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          ),
          const PdfOptionHeading('Text'),
          DropdownButtonFormField<String>(
            initialValue: live.textFamily,
            isDense: true,
            decoration: const InputDecoration(
              labelText: 'Font',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'sans', child: Text('Sans (Helvetica)')),
              DropdownMenuItem(value: 'serif', child: Text('Serif (Times)')),
              DropdownMenuItem(value: 'mono', child: Text('Mono (Courier)')),
            ],
            onChanged: (v) {
              if (v != null) {
                live.setTextUserFont(null);
                live.setTextFamily(v);
              }
            },
          ),
          const SizedBox(height: DsSpacing.sm),
          ListenableBuilder(
            listenable: FontLibrary.instance,
            builder: (context, _) {
              final fonts = FontLibrary.instance.fonts;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    initialValue: live.textUserFont?.libraryFamily == null
                        ? live.textUserFont?.id
                        : null,
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: 'My fonts',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Use the font above'),
                      ),
                      for (final f in fonts)
                        DropdownMenuItem<String?>(
                          value: f.id,
                          child: Text(f.label),
                        ),
                    ],
                    onChanged: (id) {
                      live.setTextUserFont(
                        id == null ? null : fonts.firstWhere((f) => f.id == id),
                      );
                    },
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => unawaited(_addFont()),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add font…'),
                      ),
                      TextButton(
                        onPressed: () => launchUrl(
                          Uri.parse('https://fonts.google.com'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: const Text('Get more fonts'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          ListenableBuilder(
            listenable: FontLibrary.instance,
            builder: (context, _) {
              final lib = FontLibrary.instance.library;
              if (lib.isEmpty) return const SizedBox.shrink();
              final current = live.textUserFont?.libraryFamily;
              return Padding(
                padding: const EdgeInsets.only(bottom: DsSpacing.sm),
                child: DropdownButtonFormField<String?>(
                  key: ValueKey('lib-$current'),
                  initialValue: current,
                  isDense: true,
                  isExpanded: true,
                  menuMaxHeight: 420,
                  decoration: const InputDecoration(
                    labelText: 'Font library (built in)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('—'),
                    ),
                    for (final f in lib)
                      DropdownMenuItem<String?>(
                        value: f.family,
                        child: Text(f.family, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (fam) async {
                    if (fam == null) {
                      live.setTextUserFont(null);
                      return;
                    }
                    final font = await FontLibrary.instance.loadLibraryFont(
                      fam,
                      bold: live.textBold,
                      italic: live.textItalic,
                    );
                    if (font != null) live.setTextUserFont(font);
                  },
                ),
              );
            },
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Embed font in the PDF'),
            subtitle: const Text(
              'Looks the same on every device (needed for PDF/A). Adds ~200 KB.',
              style: TextStyle(fontSize: 11.5),
            ),
            value: live.embedFonts || live.textUserFont != null,
            onChanged: live.textUserFont != null ? null : live.setEmbedFonts,
          ),
          if (live.detectedFont != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Detected: ${live.detectedFont} → using '
                '${live.textUserFont?.label ?? live.textFontBase}',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
              ),
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
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                selected: live.textBold,
                label: const Text('Bold', style: TextStyle(fontSize: 13)),
                onSelected: live.setTextBold,
              ),
              FilterChip(
                selected: live.textItalic,
                label: const Text('Italic', style: TextStyle(fontSize: 13)),
                onSelected: live.setTextItalic,
              ),
            ],
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
                          minimumSize: const Size(
                            0,
                            DsSpacing.controlHeightComfortable,
                          ),
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
