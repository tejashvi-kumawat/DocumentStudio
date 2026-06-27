import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_autosave.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/live_draw_burn.dart';
import 'package:document_studio/features/pdf_viewer/live_form_field_loader.dart';
import 'package:document_studio/features/pdf_viewer/live_text_edit_math.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:document_studio/features/pdf_viewer/widgets/live_form_layer.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:document_studio/infrastructure/pdf/pdf_text_blank_detector.dart';
import 'package:document_studio/infrastructure/pdf/pdf_helvetica_metrics.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_ink_builder.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_service.dart';
import 'package:document_studio/infrastructure/pdf/pdf_overlay_text_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

/// Fill form fields right on the page. AcroForm widgets and text-layer blanks
/// (underscores, dotted leaders, wide space runs) are tappable on the page.
/// Typed values are flattened into the session working copy — the original
/// file is left alone until the document is saved. Filled AcroForm widgets
/// are removed so they don't paint over the text.
class ViewerFillFormPanel extends ConsumerStatefulWidget {
  const ViewerFillFormPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerFillFormPanel> createState() =>
      _ViewerFillFormPanelState();
}

class _ViewerFillFormPanelState extends ConsumerState<ViewerFillFormPanel> {
  ViewerLiveToolSession? _live;
  DocumentTabsController? _tabs;
  FileStoragePort? _storage;
  PdfOverlayService? _overlay;
  final Map<String, String> _widgetRefs = {};
  List<PdfFormSpot> _snapSpots = const [];
  Map<String, String> _snapValues = const {};
  Timer? _debounce;
  String _lastFingerprint = '';
  bool _busy = false;
  bool _dirtyWhileBusy = false;
  Future<void>? _running;
  final Set<String> _burnedIds = {};
  PdfDocument? _textDoc;
  String? _textDocPath;
  bool _scanning = false;
  int _scanEpoch = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final live = ref.read(viewerLiveToolSessionProvider);
      _live = live;
      _tabs = ref.read(documentTabsControllerProvider);
      _storage = ref.read(fileStorageProvider);
      _overlay = ref.read(pdfOverlayServiceProvider);
      if (live.toolId != ViewerToolId.fillForm) {
        live.activate(
          ViewerToolId.fillForm,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      }
      live.addListener(_onLive);
      live.beginFormDetection();
      // Current page first. Nearby pages request a scan as their overlays
      // are built — the rest of the document is not read on open.
      live.requestFormPageScan(widget.handoff.currentPage1);
      unawaited(_loadAcro());
      unawaited(_pumpScans());
    });
  }

  @override
  void dispose() {
    _scanEpoch++;
    _debounce?.cancel();
    _live?.removeListener(_onLive);
    final doc = _textDoc;
    _textDoc = null;
    if (!_scanning) unawaited(doc?.dispose());
    if (_fingerprint(_snapValues).isNotEmpty) {
      unawaited(_burn(detached: true));
    }
    super.dispose();
  }

  void _onLive() {
    final live = _live;
    if (!mounted || live == null || live.toolId != ViewerToolId.fillForm) return;
    _snapSpots = live.formSpots;
    _snapValues = live.formValues;
    final fp = _fingerprint(live.formValues);
    if (fp != _lastFingerprint) {
      _lastFingerprint = fp;
      _debounce?.cancel();
      if (fp.isNotEmpty && ref.read(viewerAutosaveEnabledProvider)) {
        _debounce = Timer(kViewerAutosaveDebounce, () => unawaited(_burn()));
      }
    }
    if (live.hasPendingFormScans) unawaited(_pumpScans());
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  String _fingerprint(Map<String, String> values) {
    final entries = values.entries
        .where((e) => e.value.trim().isNotEmpty && e.value != 'Off')
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort();
    return entries.join('|');
  }

  Future<void> _loadAcro() async {
    final live = _live;
    if (live == null) return;
    final session = ref.read(documentTabsControllerProvider).activeSession;
    final file = session?.file ?? widget.handoff.file;
    final password = session?.password ?? widget.handoff.password;
    final spots = <PdfFormSpot>[];
    final fields = await loadLiveFormFields(file: file, password: password);
    if (fields != null) {
      for (final f in fields) {
        if (f.spot.kind == PdfFormSpotKind.signature) continue;
        spots.add(f.spot);
        _widgetRefs[f.spot.id] = f.widgetRef;
      }
    }
    if (!mounted || _live == null || _live!.toolId != ViewerToolId.fillForm) {
      return;
    }
    _live!.addAcroFormSpots(spots);
  }

  /// Text-layer blanks for pages the viewer has actually shown. The open
  /// page is queued first; later pages are read only when their overlay asks.
  Future<void> _pumpScans() async {
    if (_scanning) return;
    final live = _live;
    if (live == null || live.toolId != ViewerToolId.fillForm) return;
    final epoch = _scanEpoch;
    _scanning = true;
    try {
      while (mounted && epoch == _scanEpoch && _live?.toolId == ViewerToolId.fillForm) {
        final current = _live!;
        final page = current.takeNextFormScanPage(current.pageIndex1Based);
        if (page == null) break;
        final spots = await _blanksOnPage(page);
        if (!mounted || epoch != _scanEpoch || _live?.toolId != ViewerToolId.fillForm) {
          return;
        }
        _live!.setDetectedTextBlanks(page, spots);
      }
    } finally {
      _scanning = false;
      if (epoch != _scanEpoch) {
        final doc = _textDoc;
        _textDoc = null;
        await doc?.dispose();
      } else if (mounted && (_live?.hasPendingFormScans ?? false)) {
        unawaited(_pumpScans());
      }
    }
  }

  Future<List<PdfFormSpot>> _blanksOnPage(int page1) async {
    try {
      final session = ref.read(documentTabsControllerProvider).activeSession;
      final file = session?.file ?? widget.handoff.file;
      final password = session?.password ?? widget.handoff.password;
      final doc = await _openTextDoc(file, password);
      if (page1 < 1 || page1 > doc.pages.length) return const [];
      final page = doc.pages[page1 - 1];
      _live?.notePageGeometry(page1, page.width, page.height);
      final raw = await page.loadText();
      if (raw == null) return const [];
      final n = math.min(raw.fullText.length, raw.charRects.length);
      final rects = <Rect>[];
      final w = page.width <= 0 ? 1.0 : page.width;
      final h = page.height <= 0 ? 1.0 : page.height;
      for (var i = 0; i < n; i++) {
        final px = raw.charRects[i].toRect(page: page);
        rects.add(
          Rect.fromLTRB(px.left / w, px.top / h, px.right / w, px.bottom / h),
        );
      }
      return detectTextLayerBlanks(
        text: raw.fullText.substring(0, n),
        normRects: rects,
        pageIndex1Based: page1,
        pageWidthPt: page.width,
        pageHeightPt: page.height,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<PdfDocument> _openTextDoc(LocalFileRef file, String? password) async {
    if (_textDoc != null && _textDocPath == file.path) return _textDoc!;
    final previous = _textDoc;
    _textDoc = null;
    await previous?.dispose();
    final doc = await PdfDocument.openFile(
      file.path,
      passwordProvider: password == null || password.isEmpty
          ? null
          : () async => password,
    );
    _textDoc = doc;
    _textDocPath = file.path;
    return doc;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Flattens every filled field into its page, then removes those spots
  /// from the overlay once the page has re-rendered.
  Future<void> _burn({bool detached = false}) async {
    final live = _live;
    final tabs = _tabs;
    final storage = _storage;
    final overlay = _overlay;
    if (live == null || tabs == null || storage == null || overlay == null) {
      return;
    }
    if (_busy) {
      if (!detached) {
        _dirtyWhileBusy = true;
        return;
      }
      await _running;
    }
    _debounce?.cancel();
    final done = Completer<void>();
    _running = done.future;
    try {
      await _burnSnapshot(live, tabs, storage, overlay, detached);
    } finally {
      done.complete();
    }
  }

  Future<void> _burnSnapshot(
    ViewerLiveToolSession live,
    DocumentTabsController tabs,
    FileStoragePort storage,
    PdfOverlayService overlay,
    bool detached,
  ) async {
    final values = Map<String, String>.from(_snapValues);
    final byPage = <int, List<(PdfFormSpot, String)>>{};
    for (final s in _snapSpots) {
      if (_burnedIds.contains(s.id)) continue;
      final v = values[s.id]?.trim() ?? '';
      if (v.isEmpty) continue;
      if (s.kind == PdfFormSpotKind.checkbox && !liveFormValueChecked(v)) {
        continue;
      }
      byPage.putIfAbsent(s.pageIndex1Based, () => []).add((s, v));
    }
    if (byPage.isEmpty) return;

    final session = tabs.activeSession;
    if (session == null) return;
    final password = session.password;
    final burned = <String>{};
    _busy = true;
    if (!detached && mounted) setState(() {});
    try {
      var working = session.file;
      Future<LocalFileRef> step(
        Future<void> Function(String out) run,
      ) async {
        final out = await storage.createTempFile(prefix: 'form-fill', suffix: '.pdf');
        await run(out);
        return LocalFileRef(path: out, displayName: session.file.displayName);
      }

      final widgetsByPage = <int, Set<String>>{};
      for (final entry in byPage.entries) {
        final page = entry.key;
        final size = live.pageSizePtFor(page);
        if (size == null) continue;
        final w = size.width;
        final h = size.height;
        final lines = <PdfOverlayTextLine>[];
        final checks = <PdfInkStroke>[];
        for (final (spot, value) in entry.value) {
          final r = spot.normRect;
          final wPt = r.width * w;
          final hPt = r.height * h;
          if (spot.kind == PdfFormSpotKind.checkbox) {
            checks.add(
              PdfInkStroke(
                points: [
                  for (final p in kFormCheckMarkNorm)
                    (r.left * w + p.dx * wPt, h - (r.top * h + p.dy * hPt)),
                ],
                widthPt: formCheckStrokePt(wPt, hPt),
              ),
            );
          } else {
            final fs = formFieldFontSizePt(value, wPt, hPt);
            final lineTop = r.top * h + formFieldLineTopPt(hPt, fs);
            lines.add(
              PdfOverlayTextLine(
                text: value,
                xPt: r.left * w + kFormFieldPadPt,
                yPt: h - (lineTop + kHelveticaBaselineFromLineTopEm * fs),
                fontSizePt: fs,
              ),
            );
          }
          burned.add(spot.id);
          final widgetRef = _widgetRefs[spot.id];
          if (widgetRef != null) {
            widgetsByPage.putIfAbsent(page, () => {}).add(widgetRef);
          }
        }
        if (checks.isNotEmpty) {
          final input = working;
          working = await step(
            (out) => overlay.applyInkStrokesOnPage(
              input: input,
              outputPath: out,
              pageIndex1Based: page,
              strokes: checks,
              password: password,
            ),
          );
        }
        if (lines.isNotEmpty) {
          final input = working;
          working = await step(
            (out) => overlay.applyTextLinesOnPage(
              input: input,
              outputPath: out,
              pageIndex1Based: page,
              lines: lines,
              password: password,
            ),
          );
        }
      }
      if (burned.isEmpty) return;
      if (widgetsByPage.isNotEmpty) {
        final input = working;
        working = await step(
          (out) => removeFormWidgets(
            inputPath: input.path,
            outputPath: out,
            widgetRefsByPage: widgetsByPage,
            password: password,
          ),
        );
      }
      final bytes = Uint8List.fromList(await File(working.path).readAsBytes());
      if (!detached && mounted) {
        await commitBytesToSession(
          context: context,
          storage: storage,
          tabs: tabs,
          session: session,
          bytes: bytes,
          successMessage: 'Form saved.',
          silent: true,
        );
      } else {
        await session.commitBytes(bytes);
        tabs.syncActiveTabFromSession();
      }
      _burnedIds.addAll(burned);
      if (detached) {
        live.removeFormSpots(burned);
      } else {
        await Future<void>.delayed(kLiveBurnHandoverDelay);
        live.removeFormSpots(burned);
      }
    } on DocumentStudioError catch (e) {
      _toast(e.recoveryHint ?? e.message);
    } catch (e) {
      _toast('Could not save form: $e');
    } finally {
      _busy = false;
      if (!detached && mounted) setState(() {});
      if (_dirtyWhileBusy && mounted) {
        _dirtyWhileBusy = false;
        _lastFingerprint = '';
        _onLive();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final live = ref.read(viewerLiveToolSessionProvider);
    final page = live.pageIndex1Based;
    final onPage = [
      for (final s in live.formSpots)
        if (s.pageIndex1Based == page && s.kind != PdfFormSpotKind.signature) s,
    ];
    final filled = _fingerprint(live.formValues).isNotEmpty;
    final scanned = live.formPageScanned(page);
    final body = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);
    return ListView(
      padding: const EdgeInsets.all(DsSpacing.md),
      children: [
        Text(
          'Tap a highlighted blank on the page and type. Tab or Enter moves '
          'to the next one. Text is written into this session\'s working copy, '
          'not the original file, until you save the document.',
          style: body,
        ),
        const SizedBox(height: DsSpacing.md),
        if (!scanned && onPage.isEmpty)
          const LinearProgressIndicator(minHeight: 2)
        else if (onPage.isEmpty)
          Text(noFillInBlanksOnPageMessage, style: body)
        else
          Text(
            onPage.length == 1
                ? '1 blank on this page. Tap it and type.'
                : '${onPage.length} blanks on this page. Tap one and type.',
            style: body,
          ),
        const SizedBox(height: DsSpacing.lg),
        DsPrimaryButton(
          label: _busy ? 'Saving…' : 'Save form',
          icon: Icons.save_outlined,
          onPressed: _busy || !filled ? null : () => unawaited(_burn()),
        ),
      ],
    );
  }
}
