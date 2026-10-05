import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/batch/batch_runner.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/batch/batch_job.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

final batchRunnerProvider = Provider<BatchRunner>((ref) {
  return BatchRunner(jobs: ref.watch(jobRunnerProvider));
});

/// Run one tool over many PDFs.
class BatchScreen extends ConsumerStatefulWidget {
  const BatchScreen({super.key});

  @override
  ConsumerState<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends ConsumerState<BatchScreen> {
  final List<LocalFileRef> _inputs = [];
  BatchResult? _result;
  BatchProgress? _progress;
  bool _continueOnError = true;
  bool _busy = false;
  bool _cancelling = false;
  bool? _qpdfAvailable;
  BatchToolKind _tool = BatchToolKind.compressBalanced;

  /// Extra steps run after [_tool] (Action Wizard style), in fixed order.
  final Set<BatchToolKind> _also = {};

  static const _alsoOptions = [
    BatchToolKind.ocr,
    BatchToolKind.watermark,
    BatchToolKind.removeMetadata,
    BatchToolKind.protect,
  ];

  final _watermarkCtrl = TextEditingController(text: 'CONFIDENTIAL');
  bool get _usesWatermark => _steps.contains(BatchToolKind.watermark);

  List<BatchToolKind> get _steps => [
        _tool,
        if (_tool.writesFiles)
          for (final t in _alsoOptions)
            if (_also.contains(t) && t != _tool) t,
      ];

  bool get _usesPassword => _steps.contains(BatchToolKind.protect);
  String? _outputDirectory;
  final _suffixCtrl = TextEditingController(
    text: BatchToolKind.compressBalanced.defaultSuffix,
  );
  final _passwordCtrl = TextEditingController();
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    ref.read(pdfEncryptPortProvider).isAvailable().then((ok) {
      if (mounted) setState(() => _qpdfAvailable = ok);
    });
  }

  @override
  void dispose() {
    _suffixCtrl.dispose();
    _passwordCtrl.dispose();
    _watermarkCtrl.dispose();
    super.dispose();
  }

  void _addFiles(Iterable<LocalFileRef> files) {
    setState(() {
      for (final picked in files) {
        if (!_inputs.any((f) => p.equals(f.path, picked.path))) {
          _inputs.add(picked);
        }
      }
      _result = null;
    });
  }

  Future<void> _addFilesPicker() async {
    final picked = await ref.read(fileStorageProvider).pickOpenFiles(
          allowedExtensions: ['pdf', ...kBatchImageExtensions],
          allowMultiple: true,
        );
    _addFiles(picked);
  }

  Future<void> _pickOutputFolder() async {
    final dir = await ref.read(fileStorageProvider).pickOutputDirectory(
          dialogTitle: 'Batch output folder',
        );
    if (dir != null) setState(() => _outputDirectory = dir);
  }

  void _selectTool(BatchToolKind tool) {
    setState(() {
      final oldDefault = _tool.defaultSuffix;
      if (_suffixCtrl.text.trim().isEmpty || _suffixCtrl.text == oldDefault) {
        _suffixCtrl.text = tool.defaultSuffix;
      }
      _tool = tool;
      _also.remove(tool);
      _result = null;
    });
  }

  bool get _canRun {
    if (_inputs.isEmpty || _busy) return false;
    if (_tool.needsQpdf && _qpdfAvailable != true) return false;
    if (_usesPassword && _passwordCtrl.text.isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _runBatch() async {
    if (!_canRun) return;
    setState(() {
      _busy = true;
      _cancelling = false;
      _result = null;
      _progress = null;
    });
    final naming = BatchOutputNaming(
      outputDirectory: _outputDirectory,
      suffix: _suffixCtrl.text.trim().isEmpty
          ? _tool.defaultSuffix
          : _suffixCtrl.text.trim(),
    );
    try {
      final processor = batchPipelineProcessor(
        steps: _steps,
        storage: ref.read(fileStorageProvider),
        compress: ref.read(compressServiceProvider),
        metadata: ref.read(pdfMetadataPortProvider),
        encrypt: ref.read(pdfEncryptPortProvider),
        password: _passwordCtrl.text,
        searchable: ref.read(searchablePdfPortProvider),
        overlay: ref.read(pdfOverlayServiceProvider),
        watermarkText: _watermarkCtrl.text.trim().isEmpty
            ? 'CONFIDENTIAL'
            : _watermarkCtrl.text.trim(),
        finalNaming: naming,
      );
      final result = await ref.read(batchRunnerProvider).run(
            inputs: List.unmodifiable(_inputs),
            options: BatchOptions(continueOnError: _continueOnError),
            onProgress: (prog) {
              if (mounted) setState(() => _progress = prog);
            },
            processFile: processor,
          );
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is StateError ? e.message : '$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _cancelBatch() {
    setState(() => _cancelling = true);
    ref.read(batchRunnerProvider).requestCancel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final result = _result;
    final n = _inputs.length;

    return DsToolPage(
      title: 'Batch processing',
      subtitle: 'Run one tool on many PDFs at once.',
      icon: Icons.dynamic_feed_outlined,
      iconColor: const Color(0xFF0EA5E9),
      primaryLabel: n <= 1 ? 'Run' : 'Run on $n files',
      primaryIcon: Icons.play_arrow_rounded,
      primaryEnabled: _canRun,
      primaryBusy: _busy,
      onPrimary: _runBatch,
      onCancel: _busy
          ? null
          : () => context.canPop() ? context.pop() : context.go('/'),
      maxWidth: 960,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DsToolSection(
            topPadding: false,
            title: n == 0 ? 'Files' : 'Files ($n)',
            child: n == 0
                ? DsToolFileSource(
                    files: const [],
                    multiple: true,
                    allowedExtensions: ['pdf', ...kBatchImageExtensions],
                    enabled: !_busy,
                    onPick: _addFilesPicker,
                    onFilesDropped: _addFiles,
                    emptyTitle: 'Drop PDFs or images here',
                    emptySubtitle: 'Images become PDFs first. Add as many files as you like',
                    pickLabel: 'Choose files',
                    icon: Icons.library_add_outlined,
                  )
                : _queue(theme),
          ),
          DsToolSection(
            title: 'Tool',
            subtitle: _tool.description,
            child: Wrap(
              spacing: DsSpacing.sm,
              runSpacing: DsSpacing.sm,
              children: [
                for (final tool in BatchToolKind.values)
                  ChoiceChip(
                    avatar: Icon(tool.icon, size: 16),
                    label: Text(tool.label),
                    selected: _tool == tool,
                    onSelected: _busy ? null : (_) => _selectTool(tool),
                  ),
              ],
            ),
          ),
          if (_tool.needsQpdf && _qpdfAvailable == false)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.md),
              child: DsToolResultCard(
                title: 'qpdf engine not found',
                message: 'This tool needs the bundled qpdf engine. '
                    'Download it once from Settings, or reinstall the desktop app.',
                tone: DsResultTone.error,
              ),
            ),
          if (_tool.writesFiles)
            DsToolSection(
              title: 'Then also',
              subtitle: 'Chain more steps; each file goes through them in order.',
              child: Wrap(
                spacing: DsSpacing.sm,
                runSpacing: DsSpacing.sm,
                children: [
                  for (final t in _alsoOptions)
                    if (t != _tool)
                      FilterChip(
                        avatar: Icon(t.icon, size: 16),
                        label: Text(t.label),
                        selected: _also.contains(t),
                        onSelected: _busy
                            ? null
                            : (v) => setState(() {
                                  v ? _also.add(t) : _also.remove(t);
                                  _result = null;
                                }),
                      ),
                ],
              ),
            ),
          if (_usesWatermark)
            DsToolSection(
              title: 'Watermark text',
              child: TextField(
                controller: _watermarkCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'CONFIDENTIAL',
                ),
              ),
            ),
          if (_usesPassword)
            DsToolSection(
              title: 'Open password',
              child: TextField(
                controller: _passwordCtrl,
                enabled: !_busy,
                obscureText: !_showPassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  hintText: 'Password readers will need',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
            ),
          if (_tool.writesFiles)
            DsToolSection(
              title: 'Output',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: DsColors.textSecondary(b),
                      ),
                      const SizedBox(width: DsSpacing.sm),
                      Expanded(
                        child: Text(
                          _outputDirectory ?? 'Next to each original file',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_outputDirectory != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _outputDirectory = null),
                          child: const Text('Reset'),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _pickOutputFolder,
                        child: const Text('Choose folder…'),
                      ),
                    ],
                  ),
                  const SizedBox(height: DsSpacing.sm),
                  TextField(
                    controller: _suffixCtrl,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Name suffix',
                      helperText:
                          'report.pdf → report${_suffixCtrl.text.trim().isEmpty ? _tool.defaultSuffix : _suffixCtrl.text.trim()}.pdf'
                          ' · existing files are never overwritten',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
            ),
          DsToolSection(
            child: CheckboxListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Keep going when a file fails'),
              value: _continueOnError,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _continueOnError = v ?? true),
            ),
          ),
          if (_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.md),
              child: DsToolProgressCard(
                message: _cancelling
                    ? 'Stopping after the current file…'
                    : _progress == null
                        ? 'Starting…'
                        : 'File ${_progress!.index + 1} of ${_progress!.total}',
                detail: _progress?.message,
                fraction: _progress?.overallFraction,
                onCancel: _cancelBatch,
                cancelling: _cancelling,
              ),
            ),
          if (result != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.md),
              child: DsToolResultCard(
                title: result.failedCount == 0 && !result.cancelled
                    ? 'All ${result.successCount} files done'
                    : '${result.successCount} done, ${result.failedCount} failed'
                        '${result.cancelled ? ', rest skipped' : ''}',
                tone: result.failedCount == 0
                    ? DsResultTone.success
                    : DsResultTone.error,
                stats: [
                  DsResultStat('Succeeded', '${result.successCount}',
                      highlight: true),
                  DsResultStat('Failed', '${result.failedCount}'),
                ],
                onShowInFolder: _tool.writesFiles &&
                        documentSaveResultCanRevealInFolder &&
                        _firstOutput(result) != null
                    ? () => revealToolResult(context, _firstOutput(result)!)
                    : null,
                onDismiss: () => setState(() => _result = null),
              ),
            ),
        ],
      ),
    );
  }

  LocalFileRef? _firstOutput(BatchResult result) {
    for (final item in result.items) {
      final out = item.outputPath;
      if (out != null) return LocalFileRef(path: out, displayName: p.basename(out));
    }
    return null;
  }

  Widget _queue(ThemeData theme) {
    final b = theme.brightness;
    final byPath = <String, BatchItemResult>{
      for (final item in _result?.items ?? const <BatchItemResult>[])
        item.input.path: item,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: DsColors.border(b)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _inputs.length,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                color: DsColors.border(b),
              ),
              itemBuilder: (context, i) {
                final file = _inputs[i];
                final item = byPath[file.path];
                final running = _busy &&
                    _progress?.currentInput?.path == file.path;
                return _QueueRow(
                  file: file,
                  item: item,
                  running: running,
                  onRemove: _busy
                      ? null
                      : () => setState(() {
                            _inputs.removeAt(i);
                            _result = null;
                          }),
                  onOpen: item?.outputPath == null
                      ? null
                      : () => openToolResult(
                            context,
                            LocalFileRef(
                              path: item!.outputPath!,
                              displayName: p.basename(item.outputPath!),
                            ),
                          ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        Row(
          children: [
            TextButton.icon(
              onPressed: _busy ? null : _addFilesPicker,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add PDFs'),
            ),
            const Spacer(),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _inputs.clear();
                        _result = null;
                      }),
              child: const Text('Clear all'),
            ),
          ],
        ),
      ],
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.file,
    required this.item,
    required this.running,
    required this.onRemove,
    required this.onOpen,
  });

  final LocalFileRef file;
  final BatchItemResult? item;
  final bool running;
  final VoidCallback? onRemove;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final (IconData icon, Color color, String label) = running
        ? (Icons.autorenew_rounded, DsColors.primary, 'Running')
        : switch (item?.outcome) {
            null => (
                Icons.schedule_rounded,
                DsColors.textSecondary(b),
                'Queued',
              ),
            BatchItemOutcome.success => (
                Icons.check_circle_rounded,
                DsColors.success,
                'Done',
              ),
            BatchItemOutcome.failed => (
                Icons.error_rounded,
                DsColors.error,
                'Failed',
              ),
            BatchItemOutcome.skipped => (
                Icons.remove_circle_outline,
                DsColors.textSecondary(b),
                'Skipped',
              ),
          };
    final error = item?.error;
    final errorText = error is DocumentStudioError
        ? (error.recoveryHint ?? error.message)
        : error is StateError
            ? error.message
            : error?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpacing.md,
        vertical: DsSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf_outlined, size: 20, color: DsColors.primary),
          const SizedBox(width: DsSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                if (errorText != null || item?.outputPath != null)
                  Text(
                    errorText ?? p.basename(item!.outputPath!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: errorText != null
                          ? DsColors.error
                          : DsColors.textSecondary(b),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DsSpacing.sm),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Row(
              key: ValueKey(label),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(icon, size: 16, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          if (onOpen != null)
            IconButton(
              tooltip: 'Open result',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: onOpen,
            ),
          IconButton(
            tooltip: 'Remove',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
