import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/infrastructure/conversion/conversion_format.dart';
import 'package:document_studio/infrastructure/conversion/pdf_to_images_service.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

enum _RangeMode { all, current, custom }

class PdfToImagesDeps {
  const PdfToImagesDeps({
    required this.fileStorage,
    required this.pdfToImages,
    required this.jobs,
  });

  final FileStoragePort fileStorage;
  final PdfToImagesService pdfToImages;
  final JobRunner jobs;
}

/// PDF → images: render pages at a chosen DPI and format.
class PdfToImagesScreen extends StatefulWidget {
  PdfToImagesScreen({
    super.key,
    required this.deps,
    PdfToImagesRouteOptions? routeOptions,
    this.initialPdf,
    this.initialPage1,
    this.initialPassword,
  }) : routeOptions = routeOptions ?? PdfToImagesRouteOptions.fromQuery(null);

  final PdfToImagesDeps deps;
  final PdfToImagesRouteOptions routeOptions;

  /// Pre-loaded PDF from viewer or route `extra`.
  final LocalFileRef? initialPdf;

  /// Optional 1-based page from viewer deep-link (`?page=`).
  final int? initialPage1;

  /// Password from viewer tab when exporting an encrypted PDF.
  final String? initialPassword;

  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _ExportResult {
  const _ExportResult({
    required this.files,
    required this.folder,
    required this.totalBytes,
  });

  final List<LocalFileRef> files;
  final String folder;
  final int totalBytes;
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  static const _dpiChoices = [72, 96, 150, 200, 300, 600];

  LocalFileRef? _pdf;
  late PdfToImageFormat _format;
  int _dpi = PdfToImagesService.defaultDpi;
  String? _password;
  int? _pageCount;
  bool _loadingPdf = false;
  _RangeMode _rangeMode = _RangeMode.all;
  final _fromCtrl = TextEditingController(text: '1');
  final _toCtrl = TextEditingController(text: '1');
  int _currentPage = 1;

  bool _busy = false;
  bool _cancelling = false;
  String _status = '';
  double? _progress;
  JobHandle<List<LocalFileRef>>? _job;
  _ExportResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _format = widget.routeOptions.initialFormat;
    final seed = widget.initialPage1;
    if (seed != null && seed >= 1) {
      _currentPage = seed;
      _rangeMode = _RangeMode.current;
    }
    final pdf = widget.initialPdf;
    if (pdf != null) {
      _pdf = pdf;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) _password = pw;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPageCount());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pdf != null) return;
        final tab = ProviderScope.containerOf(
          context,
          listen: false,
        ).read(documentTabsControllerProvider).activeTab;
        final file = tab?.file;
        if (file == null || !file.isPdf) return;
        final pw = tab!.password;
        setState(() {
          _pdf = file;
          if (pw != null && pw.isNotEmpty) _password = pw;
        });
        _loadPageCount();
      });
    }
  }

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  static bool _isPasswordError(DocumentStudioError e) =>
      e.code == DocumentStudioErrorCode.passwordRequired ||
      e.code == DocumentStudioErrorCode.wrongPassword;

  Future<bool> _askPassword(DocumentStudioError e) async {
    if (!mounted) return false;
    final pw = await promptPdfPasswordAfterRejection(
      context,
      rejected: e.code == DocumentStudioErrorCode.wrongPassword ? e : null,
    );
    if (pw == null || pw.isEmpty || !mounted) return false;
    setState(() => _password = pw);
    return true;
  }

  Future<void> _loadPageCount() async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() {
      _loadingPdf = true;
      _error = null;
    });
    var retry = false;
    try {
      final count = await widget.deps.pdfToImages.pageCount(
        pdf: pdf,
        password: _password,
      );
      if (!mounted || _pdf?.path != pdf.path) return;
      setState(() {
        _pageCount = count;
        _currentPage = _currentPage.clamp(1, count);
        _fromCtrl.text = '1';
        _toCtrl.text = '$count';
      });
    } on DocumentStudioError catch (e) {
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
        if (!retry && mounted) setState(() => _pdf = null);
      } else if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } finally {
      if (mounted) setState(() => _loadingPdf = false);
    }
    if (retry && mounted) await _loadPageCount();
  }

  void _setPdf(LocalFileRef? pdf) {
    setState(() {
      _pdf = pdf;
      _password = null;
      _pageCount = null;
      _result = null;
      _error = null;
      if (_rangeMode == _RangeMode.current) _rangeMode = _RangeMode.all;
    });
    if (pdf != null) _loadPageCount();
  }

  Future<void> _pickPdf() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: ['pdf'],
    );
    if (picked != null) _setPdf(picked);
  }

  (int?, int?) _bounds() {
    final max = _pageCount ?? 1;
    switch (_rangeMode) {
      case _RangeMode.all:
        return (null, null);
      case _RangeMode.current:
        final page = _currentPage.clamp(1, max);
        return (page, page);
      case _RangeMode.custom:
        final from = (int.tryParse(_fromCtrl.text) ?? 1).clamp(1, max);
        final to = (int.tryParse(_toCtrl.text) ?? max).clamp(from, max);
        return (from, to);
    }
  }

  int get _exportCount {
    final total = _pageCount;
    if (total == null) return 0;
    final (from, to) = _bounds();
    return (to ?? total) - (from ?? 1) + 1;
  }

  Future<void> _export() async {
    final pdf = _pdf;
    if (pdf == null || _busy) return;
    final job = JobHandle<List<LocalFileRef>>();
    setState(() {
      _busy = true;
      _cancelling = false;
      _result = null;
      _error = null;
      _status = 'Rendering pages…';
      _progress = 0;
      _job = job;
    });
    final storage = widget.deps.fileStorage;
    Directory? workDir;
    var retry = false;
    try {
      workDir = await Directory(
        p.join(
          await storage.getTempDirectory(),
          'pdf-to-images-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      final (from, to) = _bounds();
      final images = await widget.deps.jobs.run(
        handle: job,
        work: (report, cancelToken) => widget.deps.pdfToImages.exportPages(
          pdf: pdf,
          outputDirectory: workDir!.path,
          format: _format,
          dpi: _dpi,
          firstPage1: from,
          lastPage1: to,
          password: _password,
          onProgress: (prog) {
            report(prog);
            if (mounted) {
              setState(() {
                _status = prog.message ?? _status;
                _progress = prog.fraction;
              });
            }
          },
          cancelToken: cancelToken,
        ),
      );
      if (images.isEmpty) {
        if (mounted) setState(() => _error = 'No pages were exported.');
        return;
      }
      if (!mounted) return;
      setState(() {
        _status = 'Choose where to save';
        _progress = null;
      });
      final saved = <LocalFileRef>[];
      String? folder;
      if (images.length == 1) {
        final bytes = await storage.readBytes(images.first);
        final save = await storage.pickSavePath(
          suggestedName: images.first.displayName,
          bytes: bytes,
          allowedExtensions: [_format.fileExtension],
          mimeType: _format.mimeType,
        );
        if (save == null) return;
        await storage.writeAtomic(
          destinationPath: save,
          writeToTemp: (t) => File(t).writeAsBytes(bytes, flush: true),
        );
        saved.add(
          LocalFileRef(
            path: save,
            displayName: p.basename(save),
            sizeBytes: bytes.length,
          ),
        );
        folder = p.dirname(save);
      } else {
        folder = await storage.pickOutputDirectory(
          dialogTitle: 'Choose a folder for ${images.length} images',
        );
        if (folder == null) return;
        for (final image in images) {
          final target = p.join(folder, image.displayName);
          await File(image.path).copy(target);
          saved.add(
            LocalFileRef(
              path: target,
              displayName: image.displayName,
              sizeBytes: image.sizeBytes,
            ),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _result = _ExportResult(
          files: saved,
          folder: folder!,
          totalBytes: saved.fold(0, (sum, f) => sum + (f.sizeBytes ?? 0)),
        );
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.processCancelled) return;
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
      } else if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() => _error = 'Could not write the images: ${e.message}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      try {
        await workDir?.delete(recursive: true);
      } catch (_) {}
      if (mounted) {
        setState(() {
          _busy = false;
          _job = null;
          _progress = null;
        });
      }
    }
    if (retry && mounted) await _export();
  }

  void _cancel() {
    final job = _job;
    if (job == null) return;
    setState(() => _cancelling = true);
    widget.deps.jobs.requestCancel(job);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final total = _pageCount;
    final pdf = _pdf;
    final count = _exportCount;

    return DsToolPage(
      title: widget.routeOptions.title,
      subtitle: widget.routeOptions.subtitle,
      icon: Icons.image_outlined,
      preview: DsPdfPreviewPane(
        file: pdf,
        password: _password,
        enabled: !_busy,
        onPick: _pickPdf,
        onFilesDropped: (files) => _setPdf(files.first),
        emptyTitle: 'Drop a PDF to turn into images',
        emptySubtitle: 'Each page becomes one image file',
        icon: Icons.image_outlined,
      ),
      primaryLabel: count <= 1 ? 'Export image' : 'Export $count images',
      primaryIcon: Icons.file_download_outlined,
      primaryEnabled: pdf != null && total != null && !_loadingPdf,
      primaryBusy: _busy,
      onPrimary: _export,
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      footer: Wrap(
        spacing: DsSpacing.sm,
        runSpacing: DsSpacing.sm,
        children: [
          ActionChip(
            avatar: const Icon(Icons.collections_outlined, size: 16),
            label: const Text('Images to PDF'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => context.push(imagesToPdfRoutePath),
          ),
          ActionChip(
            avatar: const Icon(Icons.compress, size: 16),
            label: const Text('Compress PDF'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => context.push('/compress'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (pdf != null)
            DsToolSection(
              topPadding: false,
              title: 'Source PDF',
              child: DsToolFileSource(
                files: [pdf],
                enabled: !_busy,
                loading: _loadingPdf,
                onPick: _pickPdf,
                onFilesDropped: (files) => _setPdf(files.first),
                onRemove: (_) => _setPdf(null),
                metaFor: (f) => [
                  if (total != null) '$total ${total == 1 ? 'page' : 'pages'}',
                  if (f.sizeBytes != null) dsFormatBytes(f.sizeBytes!),
                ].join(' · '),
                emptyTitle: 'Drop a PDF to turn into images',
                emptySubtitle: 'Each page becomes one image file',
              ),
            ),
          DsToolSection(
            title: 'Pages',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: DsAdaptiveSegmented<_RangeMode>(
                    value: _rangeMode,
                    segments: const {
                      _RangeMode.all: (
                        label: 'All pages',
                        icon: null,
                        tooltip: null,
                      ),
                      _RangeMode.current: (
                        label: 'One page',
                        icon: null,
                        tooltip: null,
                      ),
                      _RangeMode.custom: (
                        label: 'Range',
                        icon: null,
                        tooltip: null,
                      ),
                    },
                    onChanged: (m) {
                      if (_busy || total == null) return;
                      setState(() => _rangeMode = m);
                    },
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: switch ((_rangeMode, total)) {
                    (_RangeMode.current, final int t) => Padding(
                      padding: const EdgeInsets.only(top: DsSpacing.sm),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed: _busy || _currentPage <= 1
                                ? null
                                : () => setState(() => _currentPage--),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Text(
                            'Page $_currentPage of $t',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: _busy || _currentPage >= t
                                ? null
                                : () => setState(() => _currentPage++),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                    ),
                    (_RangeMode.custom, final int t) => Padding(
                      padding: const EdgeInsets.only(top: DsSpacing.md),
                      child: Row(
                        children: [
                          _pageField(_fromCtrl, 'From'),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('–'),
                          ),
                          _pageField(_toCtrl, 'To'),
                          const SizedBox(width: DsSpacing.md),
                          Text(
                            'of $t',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: DsColors.textSecondary(b),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _ => const SizedBox(width: double.infinity),
                  },
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Format',
            child: DsToolChoiceGroup<PdfToImageFormat>(
              selected: _format,
              minCardWidth: 130,
              onChanged: _busy ? null : (f) => setState(() => _format = f),
              choices: const [
                DsToolChoice(
                  value: PdfToImageFormat.png,
                  title: 'PNG',
                  subtitle: 'Lossless, sharp text',
                  icon: Icons.image_outlined,
                ),
                DsToolChoice(
                  value: PdfToImageFormat.jpeg,
                  title: 'JPEG',
                  subtitle: 'Smallest for photos',
                  icon: Icons.photo_outlined,
                ),
                DsToolChoice(
                  value: PdfToImageFormat.webp,
                  title: 'WebP',
                  subtitle: 'Modern, compact',
                  icon: Icons.web_asset_rounded,
                ),
                DsToolChoice(
                  value: PdfToImageFormat.tiff,
                  title: 'TIFF',
                  subtitle: 'For print & archive',
                  icon: Icons.print_outlined,
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Resolution',
            subtitle:
                '$_dpi DPI — ${switch (_dpi) {
                  <= 96 => 'screen and web',
                  <= 150 => 'good for sharing',
                  <= 300 => 'print quality',
                  _ => 'very large files',
                }}',
            child: Wrap(
              spacing: DsSpacing.sm,
              runSpacing: DsSpacing.sm,
              children: [
                for (final dpi in _dpiChoices)
                  ChoiceChip(
                    label: Text('$dpi'),
                    selected: _dpi == dpi,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _dpi = dpi),
                  ),
              ],
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolProgressCard(
                message: _cancelling ? 'Cancelling…' : _status,
                fraction: _progress,
                onCancel: _job == null ? null : _cancel,
                cancelling: _cancelling,
              ),
            ),
          if (_error != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: 'Export failed',
                message: _error,
                tone: DsResultTone.error,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          if (_result case final r? when !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: r.files.length == 1
                    ? 'Image saved'
                    : '${r.files.length} images saved',
                message: r.files.length == 1 ? null : r.folder,
                file: r.files.length == 1 ? r.files.first : null,
                stats: [
                  DsResultStat('Files', '${r.files.length}', highlight: true),
                  DsResultStat('Total size', dsFormatBytes(r.totalBytes)),
                  DsResultStat('Resolution', '$_dpi DPI'),
                ],
                onShowInFolder: documentSaveResultCanRevealInFolder
                    ? () => revealToolResult(context, r.files.first)
                    : null,
                onDismiss: () => setState(() => _result = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pageField(TextEditingController controller, String label) {
    return SizedBox(
      width: 84,
      child: TextField(
        controller: controller,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
