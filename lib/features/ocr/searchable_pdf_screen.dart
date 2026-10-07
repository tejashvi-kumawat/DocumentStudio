import 'dart:async';
import 'dart:typed_data';

import 'package:document_studio/core/pdf/pdf_document_cache.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session.dart';
import 'package:document_studio/features/pdf_viewer/document_tabs_controller.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/ocr/ocr_route.dart';
import 'package:document_studio/features/ocr/ocr_tool_widgets.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/infrastructure/ocr/android_searchable_pdf_service.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/tesseract_searchable_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

class SearchablePdfScreen extends StatefulWidget {
  const SearchablePdfScreen({
    super.key,
    required this.deps,
    this.initialFile,
    this.initialPassword,
  });

  final SearchablePdfDeps deps;
  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  State<SearchablePdfScreen> createState() => _SearchablePdfScreenState();
}

class _SearchablePdfScreenState extends State<SearchablePdfScreen> {
  LocalFileRef? _file;
  String? _password;
  int? _pageCount;
  bool _loadingDoc = false;

  bool _allPages = true;
  final _rangeController = TextEditingController();
  String? _rangeError;

  OcrOptions _options = const OcrOptions();
  SearchablePdfEngineStatus? _engine;

  OcrCancelToken? _token;
  SearchablePdfProgress? _progress;
  bool _cancelling = false;

  SearchablePdfResult? _result;
  String? _savedPath;
  String? _error;

  bool get _running => _token != null;

  bool get _engineBlocked =>
      isSearchablePdfEngineBlocked(widget.deps.searchablePdfPort) ||
      (_engine != null && !_engine!.isReady);

  @override
  void initState() {
    super.initState();
    _password = widget.initialPassword;
    unawaited(_probe());
    final initial = widget.initialFile;
    if (initial != null) {
      unawaited(_setFile(initial, password: _password));
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _file != null) return;
        final tab = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(documentTabsControllerProvider).activeTab;
        final file = tab?.file;
        if (file != null && file.isPdf) {
          unawaited(_setFile(file, password: tab!.password));
        }
      });
    }
  }

  @override
  void dispose() {
    _token?.cancel();
    _rangeController.dispose();
    super.dispose();
  }

  Future<void> _probe({bool refresh = false}) async {
    final port = widget.deps.searchablePdfPort;
    final SearchablePdfEngineStatus status;
    if (port is TesseractSearchablePdfService) {
      status = await port.probeEngine(
        language: _options.language,
        refresh: refresh,
      );
    } else if (port is AndroidSearchablePdfService) {
      status = await port.probeEngine(
        language: _options.language,
        refresh: refresh,
      );
    } else {
      return;
    }
    if (mounted) setState(() => _engine = status);
  }

  Future<void> _pick() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: ['pdf'],
    );
    if (picked != null) await _setFile(picked);
  }

  Future<void> _setFile(LocalFileRef file, {String? password}) async {
    setState(() {
      _file = file;
      _password = password;
      _pageCount = null;
      _loadingDoc = true;
      _result = null;
      _savedPath = null;
      _error = null;
    });
    var pw = password;
    while (true) {
      try {
        final lease = await PdfDocumentCache.instance.acquire(
          file.path,
          password: pw,
        );
        final count = lease.document.pages.length;
        lease.release();
        if (!mounted || _file != file) return;
        setState(() {
          _password = pw;
          _pageCount = count;
          _loadingDoc = false;
        });
        return;
      } on PdfPasswordException {
        if (!mounted) return;
        if (pw != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Incorrect password. Try again.')),
          );
        }
        pw = await promptPdfPassword(context);
        if (pw == null) {
          if (mounted) {
            setState(() {
              _file = null;
              _loadingDoc = false;
            });
          }
          return;
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _loadingDoc = false;
          _error = 'Couldn’t open this PDF.';
        });
        return;
      }
    }
  }

  Set<int>? _resolvePages() {
    final total = _pageCount;
    if (total == null) return null;
    if (_allPages) return null;
    final parsed = parsePdfPageRangeExpression(_rangeController.text, total);
    if (!parsed.isOk) {
      setState(() => _rangeError = parsed.error);
      return <int>{};
    }
    setState(() => _rangeError = null);
    return parsed.pages;
  }

  Future<void> _run() async {
    final file = _file;
    if (file == null || _pageCount == null || _running) return;
    final pages = _resolvePages();
    if (pages != null && pages.isEmpty) return;

    final token = OcrCancelToken();
    setState(() {
      _token = token;
      _cancelling = false;
      _progress = null;
      _result = null;
      _savedPath = null;
      _error = null;
    });
    try {
      final port = widget.deps.searchablePdfPort;
      final SearchablePdfResult result;
      if (port is TesseractSearchablePdfService ||
          port is AndroidSearchablePdfService) {
        void onProg(SearchablePdfProgress prog) {
          if (mounted && identical(_token, token)) {
            setState(() => _progress = prog);
          }
        }

        result = port is TesseractSearchablePdfService
            ? await port.makeSearchable(
                file: file,
                password: _password,
                options: _options,
                pages1Based: pages,
                cancelToken: token,
                onProgress: onProg,
              )
            : await (port as AndroidSearchablePdfService).makeSearchable(
                file: file,
                password: _password,
                options: _options,
                pages1Based: pages,
                cancelToken: token,
                onProgress: onProg,
              );
      } else {
        final watch = Stopwatch()..start();
        final bytes = await port.createSearchablePdf(
          await widget.deps.fileStorage.readBytes(file),
          options: _options,
        );
        result = SearchablePdfResult(
          bytes: bytes,
          recognizedPages: [for (var i = 1; i <= _pageCount!; i++) i],
          skippedPages: const [],
          elapsed: watch.elapsed,
        );
      }
      if (!mounted) return;
      setState(() {
        _token = null;
        _result = result;
      });
      // With the source open in a tab, "Apply to open document" is offered
      // instead of jumping straight into a save dialog.
      if (!result.unchanged && _openTabForSource() == null) await _save();
    } on OcrCancelledException {
      if (!mounted) return;
      setState(() => _token = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OCR cancelled. Nothing was saved.')),
      );
    } catch (e) {
      if (!mounted) return;
      final mapped = mapOcrException(e);
      setState(() {
        _token = null;
        _error = shortToolHelper(
          mapped.recoveryHint ?? mapped.message,
          fallback: 'Couldn’t make this PDF searchable.',
        );
      });
      if (e is OcrEngineBlockedException) unawaited(_probe());
    }
  }

  void _cancel() {
    setState(() => _cancelling = true);
    _token?.cancel();
  }

  String get _suggestedName {
    final name = _file?.displayName ?? 'document.pdf';
    return '${p.basenameWithoutExtension(name)}-searchable.pdf';
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null) return;
    final saved = await widget.deps.fileStorage.pickSavePath(
      suggestedName: _suggestedName,
      bytes: Uint8List.fromList(result.bytes),
      allowedExtensions: ['pdf'],
      mimeType: 'application/pdf',
    );
    if (!mounted || saved == null) return;
    setState(() => _savedPath = saved);
    showDocumentSaveResultActions(
      context,
      file: LocalFileRef(path: saved, displayName: p.basename(saved)),
      password: _password,
      message: 'Searchable PDF saved — text can now be selected and found.',
    );
  }

  /// Open tab showing the source file, if any.
  PdfViewerTab? _openTabForSource() {
    final file = _file;
    if (file == null) return null;
    final tabs = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(documentTabsControllerProvider);
    for (final tab in tabs.tabs) {
      if (tab.file.path == file.path) return tab;
    }
    return null;
  }

  /// Writes the text layer into the already-open document (undoable), so its
  /// text is selectable and searchable without reopening anything.
  Future<void> _applyToOpenDocument() async {
    final result = _result;
    final tab = _openTabForSource();
    if (result == null || tab == null) return;
    final tabs = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(documentTabsControllerProvider);
    final outcome = await tab.session.commitBytes(
      Uint8List.fromList(result.bytes),
    );
    if (!mounted) return;
    if (outcome != DocumentSaveOutcome.savedInPlace) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The open file is read-only. Use Save… instead.'),
        ),
      );
      return;
    }
    final index = tabs.tabs.indexWhere((t) => t.id == tab.id);
    if (index >= 0) tabs.activateTab(index);
    tabs.syncActiveTabFromSession();
    tabs.showDocument();
    context.go('/');
  }

  void _openInViewer(String path) {
    final tabs = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(documentTabsControllerProvider);
    tabs.openDocument(
      LocalFileRef(path: path, displayName: p.basename(path)),
      password: _password,
    );
    context.go('/');
  }

  Future<void> _recognizeAnyway() async {
    setState(() => _options = _options.copyWith(skipPagesWithText: false));
    await _run();
  }

  String _plural(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  String _elapsed(Duration d) => d.inSeconds < 60
      ? '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s'
      : '${d.inMinutes} min ${d.inSeconds % 60} s';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final progress = _progress;

    return DsToolPage(
      title: 'Searchable PDF',
      subtitle:
          'Recognize text in scanned pages so you can select, copy, and '
          'search it. The page images stay exactly as they are.',
      icon: Icons.find_in_page_outlined,
      preview: DsPdfPreviewPane(
        file: _file,
        password: _password,
        enabled: !_running,
        onPick: _pick,
        onFilesDropped: (files) {
          if (files.isNotEmpty) unawaited(_setFile(files.first));
        },
        emptyTitle: 'Drop a scanned PDF here',
        emptySubtitle: 'Text is recognized on your device',
        icon: Icons.find_in_page_outlined,
      ),
      primaryLabel: _running ? 'Recognizing…' : 'Make searchable',
      primaryIcon: Icons.find_in_page_outlined,
      primaryEnabled:
          _file != null && _pageCount != null && !_engineBlocked && !_running,
      primaryBusy: _running,
      onPrimary: _run,
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      busy: _running,
      busyProgress: progress?.fraction,
      footer: OcrRelatedToolsPanel(
        busy: _running,
        excludePath: searchablePdfRoutePath,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: DsMotion.switchDuration,
            curve: DsMotion.switchCurve,
            child: _engineBlocked
                ? Padding(
                    padding: const EdgeInsets.only(bottom: DsSpacing.lg),
                    child: OcrEngineStatusPanel(
                      portBlocked: true,
                      searchablePdf: true,
                      blockedReason:
                          _engine?.missingMessage ??
                          BlockedSearchablePdfPort.blockedReason,
                      onRecheck: () => _probe(refresh: true),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          if (_file != null)
            DsToolSection(
              topPadding: false,
              title: 'Source file',
              subtitle: 'Scanned or image-only PDF',
              child: _buildSource(theme, secondary),
            ),
          DsToolSection(title: 'Pages', child: _buildPages(theme, secondary)),
          DsToolSection(
            title: 'Options',
            child: OcrOptionsPanel(
              options: _options,
              busy: _running,
              searchablePdf: true,
              onChanged: (o) {
                final langChanged = o.language != _options.language;
                setState(() => _options = o);
                if (langChanged) unawaited(_probe());
              },
            ),
          ),
          AnimatedSwitcher(
            duration: DsMotion.switchDuration,
            switchInCurve: DsMotion.switchCurve,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, child: child),
            ),
            child: _buildStatus(),
          ),
        ],
      ),
    );
  }

  Widget _buildSource(ThemeData theme, Color secondary) {
    final file = _file;
    final compact = dsUseCompactToolLayout(context);
    if (file == null) {
      return DsToolFileSource(
        files: const [],
        enabled: !_running,
        onPick: _pick,
        onFilesDropped: (files) {
          if (files.isNotEmpty) unawaited(_setFile(files.first));
        },
        emptyTitle: 'Drop a scanned PDF here',
        emptySubtitle: 'Text is recognized on your device',
        pickLabel: 'Choose PDF',
        icon: Icons.document_scanner_outlined,
      );
    }
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          file.displayName,
          style: theme.textTheme.titleSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          _loadingDoc
              ? 'Reading document…'
              : _pageCount == null
              ? ''
              : [
                  _plural(_pageCount!, 'page'),
                  if (_password != null) 'password protected',
                ].join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(color: secondary),
        ),
      ],
    );
    final change = DsSecondaryButton(
      label: 'Change',
      icon: Icons.swap_horiz,
      onPressed: _running ? null : _pick,
    );
    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.picture_as_pdf_outlined, size: 28),
              const SizedBox(width: DsSpacing.sm),
              Expanded(child: details),
            ],
          ),
          const SizedBox(height: DsSpacing.sm),
          SizedBox(
            width: double.infinity,
            height: DsSpacing.controlHeightComfortable,
            child: change,
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.picture_as_pdf_outlined, size: 28),
        const SizedBox(width: DsSpacing.sm),
        Expanded(child: details),
        change,
      ],
    );
  }

  Widget _buildPages(ThemeData theme, Color secondary) {
    final compact = dsUseCompactToolLayout(context);
    void selectAll(bool all) {
      setState(() {
        _allPages = all;
        _rangeError = null;
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          Wrap(
            spacing: DsSpacing.sm,
            runSpacing: DsSpacing.sm,
            children: [
              ChoiceChip(
                label: const Text('All pages'),
                selected: _allPages,
                showCheckmark: false,
                onSelected: _running ? null : (_) => selectAll(true),
              ),
              ChoiceChip(
                label: const Text('Custom range'),
                selected: !_allPages,
                showCheckmark: false,
                onSelected: _running ? null : (_) => selectAll(false),
              ),
            ],
          )
        else
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: true, label: Text('All pages')),
              ButtonSegment(value: false, label: Text('Custom range')),
            ],
            selected: {_allPages},
            onSelectionChanged: _running ? null : (s) => selectAll(s.first),
          ),
        AnimatedSize(
          duration: DsMotion.switchDuration,
          curve: DsMotion.switchCurve,
          child: _allPages
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.sm),
                  child: TextField(
                    controller: _rangeController,
                    enabled: !_running,
                    decoration: InputDecoration(
                      isDense: true,
                      border: const OutlineInputBorder(),
                      hintText: _pageCount == null
                          ? 'e.g. 1-3, 7'
                          : 'e.g. 1-3, 7 (of $_pageCount)',
                      errorText: _rangeError,
                    ),
                    onChanged: (_) {
                      if (_rangeError != null) {
                        setState(() => _rangeError = null);
                      }
                    },
                    onSubmitted: (_) => _run(),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildStatus() {
    if (_running) {
      final prog = _progress;
      return Padding(
        key: const ValueKey('progress'),
        padding: const EdgeInsets.only(top: DsSpacing.lg),
        child: OcrProgressCard(
          fraction: prog?.fraction,
          message: prog?.message ?? 'Starting…',
          pagesDone: prog?.pagesDone ?? 0,
          pagesTotal: prog?.pagesTotal ?? 0,
          cancelling: _cancelling,
          onCancel: _cancel,
        ),
      );
    }
    final error = _error;
    if (error != null) {
      return Padding(
        key: const ValueKey('error'),
        padding: const EdgeInsets.only(top: DsSpacing.lg),
        child: OcrResultBanner(
          icon: Icons.error_outline,
          color: Theme.of(context).colorScheme.error,
          title: 'Couldn’t make this PDF searchable',
          details: error,
          actions: [
            TextButton(onPressed: _run, child: const Text('Try again')),
          ],
        ),
      );
    }
    final result = _result;
    if (result == null) return const SizedBox.shrink(key: ValueKey('none'));
    if (result.unchanged) {
      return Padding(
        key: const ValueKey('unchanged'),
        padding: const EdgeInsets.only(top: DsSpacing.lg),
        child: OcrResultBanner(
          icon: Icons.info_outline,
          color: DsColors.primary,
          title: 'This PDF is already searchable',
          details:
              'All ${_plural(result.skippedPages.length, 'selected page')} '
              'already contain selectable text, so nothing was changed.',
          actions: [
            TextButton(
              onPressed: _recognizeAnyway,
              child: const Text('Recognize anyway'),
            ),
          ],
        ),
      );
    }
    final skipped = result.skippedPages.length;
    return Padding(
      key: const ValueKey('done'),
      padding: const EdgeInsets.only(top: DsSpacing.lg),
      child: OcrResultBanner(
        title: _savedPath == null ? 'Text recognized' : 'Searchable PDF saved',
        details: [
          'Recognized ${_plural(result.recognizedPages.length, 'page')} '
              'in ${_elapsed(result.elapsed)}.',
          if (skipped > 0)
            'Skipped ${_plural(skipped, 'page')} that already had text.',
          if (_savedPath != null) 'Saved to $_savedPath',
        ].join(' '),
        actions: [
          if (_openTabForSource() != null)
            FilledButton.icon(
              onPressed: _applyToOpenDocument,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Apply to open document'),
            ),
          if (_savedPath == null)
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_alt, size: 18),
              label: const Text('Save…'),
            )
          else ...[
            TextButton.icon(
              onPressed: () => _openInViewer(_savedPath!),
              icon: const Icon(Icons.visibility_outlined, size: 18),
              label: const Text('Open'),
            ),
            if (documentSaveResultCanRevealInFolder)
              TextButton.icon(
                onPressed: () => revealToolResult(
                  context,
                  LocalFileRef(
                    path: _savedPath!,
                    displayName: p.basename(_savedPath!),
                  ),
                ),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('Show in folder'),
              ),
            TextButton(onPressed: _save, child: const Text('Save a copy…')),
          ],
        ],
      ),
    );
  }
}
