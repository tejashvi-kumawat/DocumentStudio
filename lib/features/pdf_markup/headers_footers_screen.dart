import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/app/tree_unlock.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_controller.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_editor.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_panel_parts.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/viewer_live_tool_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

/// Headers & footers: the six-zone editor. Embedded in the viewer it paints a
/// live preview on every in-scope page of the open document; standalone it
/// shows a real page preview beside the editor. Both use the writer's own
/// layout function, so the preview is what Apply burns.
class HeadersFootersScreen extends ConsumerStatefulWidget {
  const HeadersFootersScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<HeadersFootersScreen> createState() =>
      _HeadersFootersScreenState();
}

class _HeadersFootersScreenState extends ConsumerState<HeadersFootersScreen> {
  final _ctrl = HeaderFooterController();
  LocalFileRef? _file;
  String? _password;
  int _page = 1;
  int _revision = 0;
  ViewerLiveToolSession? _live;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    if (widget.embedInViewerPanel) {
      _live = ref.read(viewerLiveToolSessionProvider);
    }
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) _password = pw;
      unawaited(_ctrl.load(file));
    }
  }

  @override
  void dispose() {
    final live = _live;
    final pushed = live?.headerFooterPreviewNotifier.value;
    if (live != null) {
      runWhenTreeUnlocked(() {
        if (identical(live.headerFooterPreviewNotifier.value, pushed)) {
          live.setHeaderFooterPagePreview(null);
        }
      });
    }
    _ctrl.removeListener(_onChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _pushLivePreview();
    if (mounted) setState(() {});
  }

  void _pushLivePreview() {
    final live = _live;
    if (live == null) return;
    final ready = _ctrl.document != null && !_ctrl.loading;
    live.setHeaderFooterPagePreview(ready ? _ctrl.previewState(_file) : null);
  }

  Future<void> _pick() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked == null) return;
    setState(() {
      _file = picked;
      _password = null;
      _page = 1;
      _revision++;
    });
    await _ctrl.load(picked);
  }

  LocalFileRef? _sourceFile() {
    if (!widget.embedInViewerPanel) return _file;
    final session = ref.read(documentTabsControllerProvider).activeSession;
    return session?.file ?? _file;
  }

  Future<void> _apply() async {
    final file = _sourceFile();
    if (file == null) return;
    try {
      final bytes = await _ctrl.applyToBytes(file);
      await _deliver(
        bytes,
        'hf-${file.displayName}',
        'Header & footer applied.',
      );
    } on DocumentStudioError catch (e) {
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      _snack('Could not apply header & footer: $e');
    }
  }

  Future<void> _remove() async {
    final file = _sourceFile();
    if (file == null || !await confirmHfRemove(context)) return;
    try {
      final bytes = await _ctrl.removeToBytes(file);
      await _deliver(
        bytes,
        'clean-${file.displayName}',
        'Header & footer removed.',
      );
    } on DocumentStudioError catch (e) {
      _snack(e.recoveryHint ?? e.message);
    } catch (e) {
      _snack('Could not remove header & footer: $e');
    }
  }

  /// Viewer embed commits in place; standalone asks where to save.
  Future<void> _deliver(
    Uint8List bytes,
    String suggested,
    String message,
  ) async {
    final storage = ref.read(fileStorageProvider);
    if (widget.embedInViewerPanel) {
      final tabs = ref.read(documentTabsControllerProvider);
      final session = tabs.activeSession;
      if (session == null || !mounted) return;
      final saved = await commitBytesToSession(
        context: context,
        storage: storage,
        tabs: tabs,
        session: session,
        bytes: bytes,
        successMessage: message,
      );
      if (saved != null && mounted) {
        _file = saved;
        await _ctrl.refresh(saved);
      }
      return;
    }
    final path = await storage.pickSavePath(
      suggestedName: suggested,
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (path == null) return;
    await storage.writeAtomic(
      destinationPath: path,
      writeToTemp: (temp) => File(temp).writeAsBytes(bytes, flush: true),
    );
    if (!mounted) return;
    final out = LocalFileRef(
      path: path,
      displayName: path.split(Platform.pathSeparator).last,
    );
    showDocumentSaveResultActions(
      context,
      file: out,
      password: _password,
      message: 'Saved ${out.displayName}',
    );
  }

  Future<void> _saveTemplate() async {
    final name = await showHfSaveTemplateDialog(context);
    if (name == null) return;
    await _ctrl.saveTemplate(name);
    _snack('Template saved.');
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _editor() {
    final file = _file;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!(widget.embedInViewerPanel && file != null))
          Padding(
            padding: EdgeInsets.fromLTRB(
              dsUseCompactToolLayout(context)
                  ? DsSpacing.pagePaddingCompact
                  : DsSpacing.xl,
              DsSpacing.lg,
              dsUseCompactToolLayout(context)
                  ? DsSpacing.pagePaddingCompact
                  : DsSpacing.xl,
              0,
            ),
            child: dsUseCompactToolLayout(context)
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        file?.displayName ?? 'No PDF selected',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: DsSpacing.sm),
                      SizedBox(
                        height: DsSpacing.controlHeightComfortable,
                        child: DsSecondaryButton(
                          label: file == null ? 'Choose PDF' : 'Change',
                          icon: Icons.folder_open,
                          onPressed: _ctrl.busy ? null : _pick,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          file?.displayName ?? 'No PDF selected',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: DsSpacing.md),
                      DsSecondaryButton(
                        label: file == null ? 'Choose PDF' : 'Change',
                        icon: Icons.folder_open,
                        onPressed: _ctrl.busy ? null : _pick,
                      ),
                    ],
                  ),
          ),
        Expanded(
          child: HeaderFooterEditor(
            spec: _ctrl.spec,
            onChanged: _ctrl.update,
            focusZone: _ctrl.focusZone,
            onFocusZone: _ctrl.focus,
            doc: _ctrl.docInfo(file),
            customTemplates: _ctrl.customTemplates,
            onDeleteTemplate: _ctrl.deleteTemplate,
            enabled: !_ctrl.busy,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.embedInViewerPanel) const _LiveHint(),
                HfExistingBanner(controller: _ctrl, onRemove: _remove),
              ],
            ),
          ),
        ),
        HfActionBar(
          controller: _ctrl,
          applyLabel: file == null
              ? 'Choose a PDF first'
              : widget.embedInViewerPanel
              ? 'Apply'
              : 'Apply & save as…',
          onApply: () => unawaited(_apply()),
          onSaveTemplate: () => unawaited(_saveTemplate()),
        ),
      ],
    );
  }

  Widget _preview() {
    final file = _file;
    if (file == null) {
      return DsEmptyState(
        title: 'Choose a PDF to preview',
        subtitle: 'Templates and zones preview on your real pages.',
        action: DsPrimaryButton(
          label: 'Choose PDF',
          icon: Icons.folder_open,
          onPressed: _pick,
        ),
      );
    }
    return HfPagePreview(
      key: ValueKey('${file.path}#$_revision'),
      file: file,
      password: _password,
      page: _page,
      pageCount: _ctrl.pageCount,
      state: _ctrl.previewState(file, showGuides: true),
      onPage: (p) => setState(() => _page = p),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = LayoutBuilder(
      builder: (context, c) {
        if (widget.embedInViewerPanel) return _editor();
        // Android / phone: always stack — never desktop side-by-side.
        if (dsUseCompactToolLayout(context) || c.maxWidth < 820) {
          return Column(
            children: [
              SizedBox(
                height: math.min(380, c.maxHeight * 0.45),
                child: _preview(),
              ),
              const Divider(height: 1),
              Expanded(child: _editor()),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(flex: 6, child: _editor()),
            const VerticalDivider(width: 1),
            Flexible(flex: 5, child: _preview()),
          ],
        );
      },
    );
    if (widget.embedInViewerPanel) return body;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _ctrl.busy ? null : () => context.pop(),
        ),
        title: const Text('Headers & footers'),
      ),
      body: SafeArea(
        top: false,
        child: DsMotion.fadeRiseIn(child: body),
      ),
    );
  }
}

class _LiveHint extends StatelessWidget {
  const _LiveHint();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpacing.md),
      child: Row(
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 15,
            color: DsColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Previewed live on the pages — exactly what Apply writes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: DsColors.textSecondary(theme.brightness),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One real page with a header/footer painted on top, plus page stepping.
class HfPagePreview extends StatefulWidget {
  const HfPagePreview({
    super.key,
    required this.file,
    required this.password,
    required this.page,
    required this.pageCount,
    required this.state,
    required this.onPage,
  });

  final LocalFileRef file;
  final String? password;
  final int page;
  final int pageCount;
  final HeaderFooterPreviewState state;
  final ValueChanged<int> onPage;

  @override
  State<HfPagePreview> createState() => _HfPagePreviewState();
}

class _HfPagePreviewState extends State<HfPagePreview> {
  late final PdfDocumentRefFile _ref = PdfDocumentRefFile(
    widget.file.path,
    passwordProvider: widget.password == null
        ? null
        : () async => widget.password,
  );

  @override
  Widget build(BuildContext context) {
    final page = widget.page.clamp(1, math.max(1, widget.pageCount)).toInt();
    return ColoredBox(
      color: DsColors.groupedBackground(Theme.of(context).brightness),
      child: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(DsSpacing.lg),
              child: PdfDocumentViewBuilder(
                documentRef: _ref,
                loadingBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, e, _) => Center(child: Text('$e')),
                builder: (context, document) {
                  if (document == null || document.pages.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  final p =
                      document.pages[page.clamp(1, document.pages.length) - 1];
                  return AnimatedSwitcher(
                    duration: DsMotion.switchDuration,
                    child: PdfPageView(
                      key: ValueKey(p.pageNumber),
                      document: document,
                      pageNumber: p.pageNumber,
                      maximumDpi: 150,
                      decorationBuilder: (context, size, pg, image) => Center(
                        child: AspectRatio(
                          aspectRatio: pg.width / math.max(pg.height, 1),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: DsSpacing.cardShadowLight(
                                opacity: 0.12,
                              ),
                            ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ?image,
                                CustomPaint(
                                  painter: HeaderFooterPreviewPainter(
                                    state: widget.state,
                                    page1Based: pg.pageNumber,
                                    pageWidthPt: pg.width,
                                    pageHeightPt: pg.height,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: DsSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Previous page',
                  onPressed: page > 1 ? () => widget.onPage(page - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Page $page of ${widget.pageCount}'),
                IconButton(
                  tooltip: 'Next page',
                  onPressed: page < widget.pageCount
                      ? () => widget.onPage(page + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
