import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/organize/split_plan.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/page_management/shared/organize_drop_zone.dart';
import 'package:document_studio/features/page_management/shared/organize_tool_scaffold.dart';
import 'package:document_studio/features/page_management/widgets/organize_drop_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class SplitToolScreen extends ConsumerStatefulWidget {
  const SplitToolScreen({super.key, this.initialFile, this.initialPassword});

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  ConsumerState<SplitToolScreen> createState() => _SplitToolScreenState();
}

class _SplitToolScreenState extends ConsumerState<SplitToolScreen> {
  LocalFileRef? _file;
  int? _pageCount;
  bool _loadingInfo = false;
  SplitMethodKind _method = SplitMethodKind.everyN;
  int _pagesPerFile = 5;
  final _customRanges = <PageRange>[];
  bool _busy = false;
  String? _status;
  double? _progress;
  String? _password;
  JobHandle<List<LocalFileRef>>? _activeJob;

  @override
  void initState() {
    super.initState();
    final file = widget.initialFile;
    if (file != null) {
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) {
        _password = pw;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadInfo(file));
    }
  }

  Future<void> _loadInfo(LocalFileRef file) async {
    setState(() {
      _file = file;
      _loadingInfo = true;
      _pageCount = null;
    });
    try {
      final pdf = ref.read(pdfRenderPortProvider);
      final info = await pdf.loadInfo(file, password: _password);
      if (!mounted) return;
      setState(() {
        _pageCount = info.pageCount;
        _loadingInfo = false;
        if (_customRanges.isEmpty && info.pageCount > 0) {
          _customRanges.add(PageRange(1, info.pageCount));
        }
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired) {
        if (!mounted) return;
        final pw = await promptPdfPassword(context);
        if (!mounted) return;
        if (pw != null) {
          setState(() => _password = pw);
          await _loadInfo(file);
        } else {
          setState(() => _loadingInfo = false);
        }
        return;
      }
      rethrow;
    } catch (_) {
      if (mounted) setState(() => _loadingInfo = false);
    }
  }

  Future<void> _pick() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked != null) {
      setState(() => _customRanges.clear());
      await _loadInfo(picked);
    }
  }

  List<PageRange> get _plan {
    final total = _pageCount ?? 0;
    return buildSplitPlan(
      totalPages: total,
      method: _method,
      pagesPerFile: _pagesPerFile,
      customRanges: _customRanges,
    );
  }

  Future<void> _split() async {
    if (_file == null || _pageCount == null || _pageCount! < 1) return;
    final plan = _plan;
    if (plan.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Splitting…';
      _progress = 0.12;
    });
    final job = JobHandle<List<LocalFileRef>>();
    setState(() => _activeJob = job);
    try {
      final ranges = [for (final part in plan) part.toPageNumbers1Based()];
      await ref
          .read(pageOrganizeServiceProvider)
          .splitByRangesAndPromptSave(
            handle: job,
            input: _file!,
            rangesPages1Based: ranges,
            namePrefix: p.basenameWithoutExtension(_file!.displayName),
            password: _password,
            onProgress: (prog) {
              if (mounted) {
                setState(() {
                  _status = prog.message;
                  _progress = prog.fraction;
                });
              }
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created ${plan.length} files')));
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.recoveryHint ?? e.message)));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = null;
          _progress = null;
          _activeJob = null;
        });
      }
    }
  }

  void _addCustomRange() {
    final total = _pageCount ?? 1;
    setState(() {
      _customRanges.add(PageRange(1, total.clamp(1, total)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary = isDark
        ? DsColors.textSecondaryDark
        : DsColors.textSecondaryLight;
    final plan = _plan;
    final wide =
        MediaQuery.sizeOf(context).width >= 980 &&
        !dsUseCompactToolLayout(context);

    Future<void> dropped(List<LocalFileRef> files) async {
      if (files.isNotEmpty) {
        setState(() => _customRanges.clear());
        await _loadInfo(files.first);
      }
    }

    return OrganizeToolScaffold(
      title: 'Split PDF',
      subtitle: _file == null
          ? 'Document-level — divide one PDF into multiple files'
          : '${_file!.displayName}${_pageCount != null ? ' · $_pageCount pages' : ''}',
      busy: _busy,
      statusMessage: _status,
      progress: _progress,
      onCancel: _activeJob == null
          ? null
          : () => ref.read(jobRunnerProvider).requestCancel(_activeJob!),
      actions: [
        if (_file != null && _pageCount != null)
          Text('${plan.length} output files', style: theme.textTheme.bodySmall),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _file == null || _busy || plan.isEmpty ? null : _split,
          child: const Text('Split & save'),
        ),
      ],
      body: OrganizeDropTarget(
        enabled: !_busy,
        onFilesDropped: dropped,
        child: _workbench(
          wide: wide,
          preview: DsPdfPreviewPane(
            file: _file,
            enabled: !_busy,
            onPick: _pick,
            onFilesDropped: dropped,
            emptyTitle: 'Drop a PDF here',
            emptySubtitle: 'Preview output parts before you split',
            icon: Icons.call_split,
          ),
          form: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_file == null && !wide)
                OrganizeDropZone(
                  enabled: !_busy,
                  onBrowse: _pick,
                  title: 'Drop a PDF here',
                  subtitle: 'Preview output parts before you split',
                )
              else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _file!.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _pick,
                      child: const Text('Change file'),
                    ),
                  ],
                ),
                if (_loadingInfo)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
              ],
              const SizedBox(height: 16),
              Text('Split method', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<SplitMethodKind>(
                segments: const [
                  ButtonSegment(
                    value: SplitMethodKind.everyN,
                    label: Text('Every N'),
                    icon: Icon(Icons.view_column_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: SplitMethodKind.singlePages,
                    label: Text('One per page'),
                    icon: Icon(Icons.filter_1_outlined, size: 18),
                  ),
                  ButtonSegment(
                    value: SplitMethodKind.customRanges,
                    label: Text('Ranges'),
                    icon: Icon(Icons.linear_scale, size: 18),
                  ),
                ],
                selected: {_method},
                onSelectionChanged: _busy || _pageCount == null
                    ? null
                    : (s) => setState(() => _method = s.first),
              ),
              const SizedBox(height: 16),
              if (_method == SplitMethodKind.everyN && _pageCount != null) ...[
                Text('Pages per file', style: theme.textTheme.titleSmall),
                Row(
                  children: [
                    Expanded(
                      child: Slider.adaptive(
                        min: 1,
                        max: (_pageCount! > 50 ? 50 : _pageCount!).toDouble(),
                        divisions: (_pageCount! > 50 ? 50 : _pageCount!) - 1,
                        value: _pagesPerFile
                            .clamp(1, _pageCount! > 50 ? 50 : _pageCount!)
                            .toDouble(),
                        label: '$_pagesPerFile',
                        onChanged: _busy
                            ? null
                            : (v) => setState(() => _pagesPerFile = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text('$_pagesPerFile', textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ],
              if (_method == SplitMethodKind.customRanges &&
                  _pageCount != null) ...[
                Text(
                  'Custom ranges (1-based)',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _customRanges.length; i++)
                  _RangeEditorRow(
                    range: _customRanges[i],
                    maxPage: _pageCount!,
                    enabled: !_busy,
                    onChanged: (r) => setState(() => _customRanges[i] = r),
                    onRemove: _customRanges.length > 1
                        ? () => setState(() => _customRanges.removeAt(i))
                        : null,
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _addCustomRange,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add range'),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text('Output preview', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              if (_pageCount == null)
                Text(
                  'Choose a PDF to see how it will be divided.',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                )
              else if (plan.isEmpty)
                Text(
                  'Adjust ranges to create at least one output part.',
                  style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < plan.length; i++)
                      InputChip(
                        label: Text(
                          'Part ${i + 1}: ${plan[i].label()} (${plan[i].pageCount} pg)',
                        ),
                        onSelected: (_) {},
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Text(
                'Each part opens a save dialog in order. Bookmark-based split is planned when the engine supports it.',
                style: theme.textTheme.bodySmall?.copyWith(color: secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Wide windows: options on the left, the PDF filling the right.
  Widget _workbench({
    required bool wide,
    required Widget preview,
    required Widget form,
  }) {
    if (!wide) return form;
    final b = Theme.of(context).brightness;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 460, child: form),
        VerticalDivider(width: 1, color: DsColors.border(b)),
        Expanded(
          child: ColoredBox(
            color: DsColors.groupedBackground(b),
            child: preview,
          ),
        ),
      ],
    );
  }
}

class _RangeEditorRow extends StatelessWidget {
  const _RangeEditorRow({
    required this.range,
    required this.maxPage,
    required this.enabled,
    required this.onChanged,
    this.onRemove,
  });

  final PageRange range;
  final int maxPage;
  final bool enabled;
  final void Function(PageRange) onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: TextFormField(
              enabled: enabled,
              initialValue: '${range.start1Based}',
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'From',
              ),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (v) {
                final n = int.tryParse(v) ?? range.start1Based;
                onChanged(PageRange(n, range.end1Based));
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('–'),
          ),
          SizedBox(
            width: 72,
            child: TextFormField(
              enabled: enabled,
              initialValue: '${range.end1Based}',
              decoration: const InputDecoration(isDense: true, labelText: 'To'),
              keyboardType: TextInputType.number,
              onFieldSubmitted: (v) {
                final n = int.tryParse(v) ?? range.end1Based;
                onChanged(PageRange(range.start1Based, n));
              },
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: enabled ? onRemove : null,
            ),
        ],
      ),
    );
  }
}
