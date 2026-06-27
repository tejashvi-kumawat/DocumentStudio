import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/core/jobs/job_runner.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/infrastructure/conversion/conversion_format.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_page_size.dart';
import 'package:document_studio/infrastructure/conversion/images_to_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

class ImagesToPdfDeps {
  const ImagesToPdfDeps({
    required this.fileStorage,
    required this.imagesToPdf,
    required this.jobs,
  });

  final FileStoragePort fileStorage;
  final ImagesToPdfService imagesToPdf;
  final JobRunner jobs;
}

/// Images → PDF: add images, order them, pick a page size, save one PDF.
class ImagesToPdfScreen extends StatefulWidget {
  ImagesToPdfScreen({
    super.key,
    required this.deps,
    ImagesToPdfRouteOptions? routeOptions,
  }) : routeOptions = routeOptions ?? ImagesToPdfRouteOptions.fromQuery(null);

  final ImagesToPdfDeps deps;
  final ImagesToPdfRouteOptions routeOptions;

  @override
  State<ImagesToPdfScreen> createState() => _ImagesToPdfScreenState();
}

class _ImagesToPdfScreenState extends State<ImagesToPdfScreen> {
  final List<LocalFileRef> _images = [];
  ImagesToPdfPageSize _pageSize = ImagesToPdfPageSize.fitImage;
  bool _busy = false;
  bool _cancelling = false;
  String _status = '';
  double? _progress;
  JobHandle<LocalFileRef>? _job;
  LocalFileRef? _saved;
  int _savedPages = 0;
  String? _error;

  List<String> get _extensions => widget.routeOptions.pickExtensions;

  Future<void> _pickImages() async {
    final picked = await widget.deps.fileStorage.pickOpenFiles(
      allowedExtensions: _extensions,
    );
    _addImages(picked);
  }

  void _addImages(List<LocalFileRef> files) {
    if (files.isEmpty) return;
    setState(() {
      _images.addAll(files);
      _saved = null;
      _error = null;
    });
  }

  Future<void> _replaceImage(int index) async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: _extensions,
    );
    if (picked == null) return;
    setState(() => _images[index] = picked);
  }

  void _reorder(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex--;
    setState(() => _images.insert(newIndex, _images.removeAt(oldIndex)));
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _images.length) return;
    _reorder(index, delta > 0 ? target + 1 : target);
  }

  Future<void> _buildAndSave() async {
    if (_images.isEmpty || _busy) return;
    final job = JobHandle<LocalFileRef>();
    setState(() {
      _busy = true;
      _cancelling = false;
      _saved = null;
      _error = null;
      _status = 'Preparing images…';
      _progress = 0;
      _job = job;
    });
    final storage = widget.deps.fileStorage;
    String? temp;
    try {
      temp = await storage.createTempFile(prefix: 'images-to-pdf', suffix: '.pdf');
      final images = List.of(_images);
      final built = await widget.deps.jobs.run(
        handle: job,
        work: (report, cancelToken) => widget.deps.imagesToPdf.fromImageFiles(
          images: images,
          outputPath: temp!,
          pageSize: _pageSize,
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
      if (!mounted) return;
      setState(() {
        _status = 'Choose where to save';
        _progress = null;
      });
      final bytes = await storage.readBytes(built);
      final first = p.basenameWithoutExtension(images.first.displayName);
      final save = await storage.pickSavePath(
        suggestedName: images.length == 1 ? '$first.pdf' : '$first and more.pdf',
        bytes: bytes,
        allowedExtensions: ['pdf'],
        mimeType: 'application/pdf',
      );
      if (save == null) return;
      await storage.writeAtomic(
        destinationPath: save,
        writeToTemp: (t) => File(t).writeAsBytes(bytes, flush: true),
      );
      if (!mounted) return;
      setState(() {
        _saved = LocalFileRef(
          path: save,
          displayName: p.basename(save),
          sizeBytes: bytes.length,
        );
        _savedPages = images.length;
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.processCancelled) return;
      if (mounted) setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (temp != null) File(temp).delete().ignore();
      if (mounted) {
        setState(() {
          _busy = false;
          _job = null;
          _progress = null;
        });
      }
    }
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
    final options = widget.routeOptions;
    final count = _images.length;

    return DsToolPage(
      title: options.title,
      subtitle: options.subtitle,
      icon: Icons.collections_outlined,
      iconColor: const Color(0xFFF59E0B),
      primaryLabel: count <= 1 ? 'Create PDF' : 'Create $count-page PDF',
      primaryIcon: Icons.picture_as_pdf_outlined,
      primaryEnabled: count > 0,
      primaryBusy: _busy,
      onPrimary: _buildAndSave,
      onCancel: () => context.canPop() ? context.pop() : context.go('/'),
      footer: Wrap(
        spacing: DsSpacing.sm,
        runSpacing: DsSpacing.sm,
        children: [
          ActionChip(
            avatar: const Icon(Icons.image_outlined, size: 16),
            label: const Text('PDF to images'),
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : () => context.push(pdfToImagesRoutePath),
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
          if (options.scanHandoff)
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpacing.md),
              child: DsToolResultCard(
                title: 'Build a PDF from scans',
                message: 'Add photos or saved scan pages, put them in order, '
                    'then create one PDF.',
                tone: DsResultTone.info,
              ),
            ),
          DsToolSection(
            topPadding: false,
            title: count == 0 ? 'Images' : 'Pages ($count)',
            subtitle: count == 0
                ? null
                : 'Drag to reorder — each image becomes one page.',
            child: count == 0
                ? DsToolFileSource(
                    files: const [],
                    multiple: true,
                    allowedExtensions: _extensions,
                    enabled: !_busy,
                    onPick: _pickImages,
                    onFilesDropped: _addImages,
                    emptyTitle: 'Drop images here',
                    emptySubtitle:
                        '${_extensions.map((e) => e.toUpperCase()).join(', ')}'
                        ' — add as many as you like',
                    pickLabel: 'Choose images',
                    icon: Icons.add_photo_alternate_outlined,
                  )
                : _imageList(theme),
          ),
          DsToolSection(
            title: 'Page size',
            child: DsToolChoiceGroup<ImagesToPdfPageSize>(
              selected: _pageSize,
              minCardWidth: 140,
              onChanged: _busy ? null : (v) => setState(() => _pageSize = v),
              choices: const [
                DsToolChoice(
                  value: ImagesToPdfPageSize.fitImage,
                  title: 'Fit image',
                  subtitle: 'Page matches each image',
                  icon: Icons.fit_screen_outlined,
                  badge: 'Default',
                ),
                DsToolChoice(
                  value: ImagesToPdfPageSize.a4,
                  title: 'A4',
                  subtitle: '210 × 297 mm',
                  icon: Icons.crop_portrait_rounded,
                ),
                DsToolChoice(
                  value: ImagesToPdfPageSize.letter,
                  title: 'Letter',
                  subtitle: '8.5 × 11 in',
                  icon: Icons.crop_portrait_rounded,
                ),
                DsToolChoice(
                  value: ImagesToPdfPageSize.legal,
                  title: 'Legal',
                  subtitle: '8.5 × 14 in',
                  icon: Icons.crop_portrait_rounded,
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
                title: 'Could not create the PDF',
                message: _error,
                tone: DsResultTone.error,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          if (_saved case final saved? when !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: 'PDF created',
                file: saved,
                stats: [
                  DsResultStat('Pages', '$_savedPages', highlight: true),
                  if (saved.sizeBytes != null)
                    DsResultStat('Size', dsFormatBytes(saved.sizeBytes!)),
                ],
                onOpen: () => openToolResult(context, saved),
                openLabel: 'Open in viewer',
                onShowInFolder: documentSaveResultCanRevealInFolder
                    ? () => revealToolResult(context, saved)
                    : null,
                onDismiss: () => setState(() => _saved = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageList(ThemeData theme) {
    final b = theme.brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: DsColors.border(b)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _images.length,
                onReorder: _busy ? (_, _) {} : _reorder,
                itemBuilder: (context, index) {
                  final file = _images[index];
                  return _ImageRow(
                    key: ValueKey('${file.path}#$index'),
                    index: index,
                    file: file,
                    busy: _busy,
                    isFirst: index == 0,
                    isLast: index == _images.length - 1,
                    onUp: () => _move(index, -1),
                    onDown: () => _move(index, 1),
                    onReplace: () => _replaceImage(index),
                    onRemove: () => setState(() => _images.removeAt(index)),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _pickImages,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: const Text('Add images'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : () => setState(_images.clear),
              child: const Text('Clear all'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ImageRow extends StatelessWidget {
  const _ImageRow({
    super.key,
    required this.index,
    required this.file,
    required this.busy,
    required this.isFirst,
    required this.isLast,
    required this.onUp,
    required this.onDown,
    required this.onReplace,
    required this.onRemove,
  });

  final int index;
  final LocalFileRef file;
  final bool busy;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onReplace;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Material(
      color: DsColors.groupedCell(b),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.sm,
          vertical: 6,
        ),
        child: Row(
          children: [
            ReorderableDragStartListener(
              index: index,
              enabled: !busy,
              child: MouseRegion(
                cursor: busy ? MouseCursor.defer : SystemMouseCursors.grab,
                child: Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: DsColors.textSecondary(b),
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.sm),
            SizedBox(
              width: 24,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: DsColors.textSecondary(b),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Image.file(
                  File(file.path),
                  fit: BoxFit.cover,
                  cacheWidth: (44 * dpr).round(),
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: DsColors.groupedBackground(b),
                    child: const Icon(Icons.image_not_supported_outlined, size: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DsSpacing.md),
            Expanded(
              child: Text(
                file.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            IconButton(
              tooltip: 'Move up',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_upward_rounded, size: 18),
              onPressed: busy || isFirst ? null : onUp,
            ),
            IconButton(
              tooltip: 'Move down',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.arrow_downward_rounded, size: 18),
              onPressed: busy || isLast ? null : onDown,
            ),
            IconButton(
              tooltip: 'Replace image',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              onPressed: busy ? null : onReplace,
            ),
            IconButton(
              tooltip: 'Remove',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close_rounded, size: 18),
              onPressed: busy ? null : onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
