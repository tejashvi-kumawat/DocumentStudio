import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_motion.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_watermark_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/watermark_preview_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';

/// Watermark tool. Inside the viewer it is the options panel with the live
/// on-page preview; standalone it adds a file picker, a page preview and
/// save-as delivery. Both use the same panel, geometry and writer.
class WatermarkScreen extends ConsumerStatefulWidget {
  const WatermarkScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends ConsumerState<WatermarkScreen> {
  final _preview = ValueNotifier<WatermarkPreviewState?>(null);
  LocalFileRef? _file;
  String? _password;
  int _page = 1;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    final pw = widget.initialPassword;
    if (pw != null && pw.isNotEmpty) _password = pw;
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
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
  }

  Future<String?> _saveAs(Uint8List bytes, String suggestedName) async {
    final storage = ref.read(fileStorageProvider);
    final path = await storage.pickSavePath(
      suggestedName: suggestedName,
      bytes: bytes,
      allowedExtensions: const ['pdf'],
      mimeType: 'application/pdf',
    );
    if (path == null) return null;
    await storage.writeAtomic(
      destinationPath: path,
      writeToTemp: (temp) => File(temp).writeAsBytes(bytes, flush: true),
    );
    if (!mounted) return null;
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
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (widget.embedInViewerPanel && file != null) {
      final live = ref.read(viewerLiveToolSessionProvider);
      return ViewerWatermarkPanel(
        key: ValueKey(file.path),
        handoff: PdfViewerDocumentHandoff(
          file: file,
          password: _password,
          currentPage1: math.max(1, live.pageIndex1Based),
        ),
      );
    }

    final theme = Theme.of(context);
    Widget panel() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: DsSpacing.sm),
                        SizedBox(
                          height: DsSpacing.controlHeightComfortable,
                          child: DsSecondaryButton(
                            label: file == null ? 'Choose PDF' : 'Change',
                            icon: Icons.folder_open,
                            onPressed: _pick,
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
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: DsSpacing.md),
                        DsSecondaryButton(
                          label: file == null ? 'Choose PDF' : 'Change',
                          icon: Icons.folder_open,
                          onPressed: _pick,
                        ),
                      ],
                    ),
            ),
            if (file != null)
              Expanded(
                child: ViewerWatermarkPanel(
                  key: ValueKey('${file.path}#$_revision'),
                  handoff: PdfViewerDocumentHandoff(
                    file: file,
                    password: _password,
                    currentPage1: _page,
                  ),
                  livePreview: false,
                  previewSink: _preview,
                  onDeliver: _saveAs,
                ),
              ),
          ],
        );

    Widget preview() => file == null
        ? DsEmptyState(
            title: 'Choose a PDF to watermark',
            subtitle: 'The preview shows exactly what gets saved.',
            action: DsPrimaryButton(
              label: 'Choose PDF',
              icon: Icons.folder_open,
              onPressed: _pick,
            ),
          )
        : _WatermarkPagePreview(
            key: ValueKey('${file.path}#$_revision'),
            file: file,
            password: _password,
            page: _page,
            preview: _preview,
            onPage: (p) => setState(() => _page = p),
          );

    final body = LayoutBuilder(
      builder: (context, c) {
        // Android / phone: always stack — never desktop side-by-side.
        if (dsUseCompactToolLayout(context) || c.maxWidth < 820) {
          return Column(
            children: [
              SizedBox(
                height: math.min(340, c.maxHeight * 0.4),
                child: preview(),
              ),
              const Divider(height: 1),
              Expanded(child: panel()),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(flex: 6, child: panel()),
            const VerticalDivider(width: 1),
            Flexible(flex: 5, child: preview()),
          ],
        );
      },
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Watermark'),
      ),
      body: SafeArea(
        top: false,
        child: DsMotion.fadeRiseIn(child: body),
      ),
    );
  }
}

class _WatermarkPagePreview extends StatefulWidget {
  const _WatermarkPagePreview({
    super.key,
    required this.file,
    required this.password,
    required this.page,
    required this.preview,
    required this.onPage,
  });

  final LocalFileRef file;
  final String? password;
  final int page;
  final ValueNotifier<WatermarkPreviewState?> preview;
  final ValueChanged<int> onPage;

  @override
  State<_WatermarkPagePreview> createState() => _WatermarkPagePreviewState();
}

class _WatermarkPagePreviewState extends State<_WatermarkPagePreview> {
  late final PdfDocumentRefFile _ref = PdfDocumentRefFile(
    widget.file.path,
    passwordProvider:
        widget.password == null ? null : () async => widget.password,
  );

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DsColors.groupedBackground(Theme.of(context).brightness),
      child: PdfDocumentViewBuilder(
        documentRef: _ref,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, e, _) => Center(child: Text('$e')),
        builder: (context, document) {
          if (document == null || document.pages.isEmpty) {
            return const SizedBox.shrink();
          }
          final count = document.pages.length;
          final page = widget.page.clamp(1, count);
          final pg = document.pages[page - 1];
          return Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(DsSpacing.lg),
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: pg.width / math.max(pg.height, 1),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: DsSpacing.cardShadowLight(opacity: 0.12),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PdfPageView(
                              key: ValueKey(page),
                              document: document,
                              pageNumber: page,
                              maximumDpi: 150,
                            ),
                            CustomPaint(
                              painter: _PageWatermarkPainter(
                                preview: widget.preview,
                                page1Based: page,
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
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: DsSpacing.md),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous page',
                      onPressed:
                          page > 1 ? () => widget.onPage(page - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Page $page of $count'),
                    IconButton(
                      tooltip: 'Next page',
                      onPressed:
                          page < count ? () => widget.onPage(page + 1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PageWatermarkPainter extends CustomPainter {
  _PageWatermarkPainter({
    required this.preview,
    required this.page1Based,
    required this.pageWidthPt,
    required this.pageHeightPt,
  }) : super(repaint: preview);

  final ValueNotifier<WatermarkPreviewState?> preview;
  final int page1Based;
  final double pageWidthPt;
  final double pageHeightPt;

  @override
  void paint(Canvas canvas, Size size) {
    final state = preview.value;
    if (state == null || !state.appliesTo(page1Based)) return;
    paintWatermarkMarks(
      canvas,
      size,
      spec: state.spec,
      pageWidthPt: pageWidthPt,
      pageHeightPt: pageHeightPt,
      text: state.textFor(page1Based),
      image: state.image,
    );
  }

  @override
  bool shouldRepaint(covariant _PageWatermarkPainter old) =>
      old.preview != preview ||
      old.page1Based != page1Based ||
      old.pageWidthPt != pageWidthPt ||
      old.pageHeightPt != pageHeightPt;
}
