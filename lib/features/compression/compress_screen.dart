import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/adaptive/ds_adaptive.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_tool_route_actions.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_service.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Standalone `/compress` tool: pick a PDF, choose a level, save a smaller copy.
class CompressScreen extends ConsumerStatefulWidget {
  const CompressScreen({super.key, this.initialFile, this.initialPassword});

  final LocalFileRef? initialFile;
  final String? initialPassword;

  @override
  ConsumerState<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends ConsumerState<CompressScreen> {
  LocalFileRef? _file;
  int? _fileBytes;
  String? _password;

  CompressProfile _profile = CompressProfile.balanced;
  bool _customDownsample = true;
  bool _customOptimizeImages = false;
  bool _customRecompressFlate = true;
  bool _customLinearize = false;

  bool? _qpdfAvailable;
  bool _busy = false;
  bool _cancelling = false;
  String _status = '';
  double? _progress;
  JobHandle<CompressResult>? _job;

  bool _estimating = false;
  CompressResult? _estimate;
  CompressResult? _result;

  @override
  void initState() {
    super.initState();
    _refreshQpdf();
    final file = widget.initialFile;
    if (file != null) {
      final pw = widget.initialPassword;
      _setFile(file, password: pw != null && pw.isNotEmpty ? pw : null);
    }
  }

  Future<void> _refreshQpdf() async {
    final ok = await ref
        .read(compressServiceProvider)
        .isQpdfPreferredAvailable();
    if (mounted) setState(() => _qpdfAvailable = ok);
  }

  void _setFile(LocalFileRef file, {String? password}) {
    setState(() {
      _file = file;
      _fileBytes = file.sizeBytes;
      _password = password;
      _result = null;
      _estimate = null;
    });
    if (file.sizeBytes == null) {
      File(file.path)
          .length()
          .then((n) {
            if (mounted && _file?.path == file.path) {
              setState(() => _fileBytes = n);
            }
          })
          .catchError((_) {});
    }
  }

  void _clearFile() => setState(() {
    _file = null;
    _fileBytes = null;
    _password = null;
    _result = null;
    _estimate = null;
  });

  Future<void> _unlock() async {
    final pw = await promptPdfPasswordAfterRejection(context);
    if (pw == null || pw.isEmpty || !mounted) return;
    setState(() {
      _password = pw;
      _estimate = null;
    });
  }

  Future<void> _pick() async {
    final picked = await ref
        .read(fileStorageProvider)
        .pickOpenFile(allowedExtensions: ['pdf']);
    if (picked != null) _setFile(picked);
  }

  PdfCompressOptions _options() {
    if (_profile != CompressProfile.custom) {
      return PdfCompressOptions.fromProfile(_profile);
    }
    final lossy = _customOptimizeImages || _customDownsample;
    return PdfCompressOptions.fromProfile(CompressProfile.custom).mergeCustom(
      recompressFlate: _customRecompressFlate,
      linearize: _customLinearize,
      optimizeImages: _customOptimizeImages,
      jpegQuality: lossy ? 65 : null,
      downsampleMaxPx: _customDownsample ? 2000 : null,
    );
  }

  void _changeOption(VoidCallback change) {
    setState(() {
      change();
      _estimate = null;
    });
  }

  static bool _isPasswordError(DocumentStudioError e) =>
      e.code == DocumentStudioErrorCode.passwordRequired ||
      e.code == DocumentStudioErrorCode.wrongPassword;

  /// Returns true when the user entered a password and the action should retry.
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

  Future<void> _estimateSize() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _estimating = true;
      _estimate = null;
      _errorMessage = null;
    });
    var retry = false;
    try {
      final result = await ref
          .read(compressServiceProvider)
          .estimateCompress(
            input: file,
            options: _options(),
            password: _password,
          );
      if (mounted && _file?.path == file.path) {
        setState(() => _estimate = result);
      }
    } on DocumentStudioError catch (e) {
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
      } else if (mounted) {
        _showError(e);
      }
    } catch (e) {
      if (mounted) _showSnack('Could not preview the size: $e');
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
    if (retry && mounted) await _estimateSize();
  }

  Future<void> _run() async {
    final file = _file;
    if (file == null || _busy) return;
    final job = JobHandle<CompressResult>();
    setState(() {
      _busy = true;
      _cancelling = false;
      _result = null;
      _errorMessage = null;
      _status = 'Preparing…';
      _progress = null;
      _job = job;
    });
    var retry = false;
    try {
      final result = await ref
          .read(compressServiceProvider)
          .compressAndPromptSave(
            handle: job,
            input: file,
            options: _options(),
            password: _password,
            onProgress: (p) {
              if (!mounted) return;
              setState(() {
                _status = p.message ?? _status;
                _progress = p.fraction;
              });
            },
          );
      if (mounted) setState(() => _result = result);
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.processCancelled) return;
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
      } else if (mounted) {
        _showError(e);
      }
    } catch (e) {
      if (mounted) _showSnack('Compression failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _job = null;
          _progress = null;
        });
      }
    }
    if (retry && mounted) await _run();
  }

  void _cancel() {
    final job = _job;
    if (job == null) return;
    setState(() => _cancelling = true);
    ref.read(jobRunnerProvider).requestCancel(job);
  }

  void _showError(DocumentStudioError e) {
    final hint = e.recoveryHint?.trim();
    var detail = hint != null && hint.isNotEmpty ? hint : e.message;
    final cause = e.cause;
    if (cause is QpdfCliException) {
      final d = cause.stderr.trim().isEmpty
          ? cause.stdout.trim()
          : cause.stderr.trim();
      if (d.isNotEmpty) detail = d;
    }
    setState(() {
      _result = null;
      _errorMessage = detail;
    });
  }

  String? _errorMessage;

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final file = _file;
    final qpdf = _qpdfAvailable;
    final canRun = file != null && !_busy;

    return DsToolPage(
      title: 'Compress PDF',
      subtitle: 'Shrink a PDF on this device — nothing is uploaded.',
      icon: Icons.compress_rounded,
      headerTrailing: _EngineChip(qpdf: qpdf, onRecheck: _refreshQpdf),
      preview: DsPdfPreviewPane(
        file: file,
        password: _password,
        onUnlock: _unlock,
        enabled: !_busy,
        onPick: _pick,
        onFilesDropped: (files) => _setFile(files.first),
        emptyTitle: 'Drop a PDF here',
        emptySubtitle: 'or browse to choose the file you want to shrink',
      ),
      primaryLabel: 'Compress & save as…',
      primaryIcon: Icons.save_alt_rounded,
      primaryEnabled: canRun,
      primaryBusy: _busy,
      onPrimary: _run,
      onCancel: () => handleDsToolFormCancel(context, ref),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (file != null)
            DsToolSection(
              title: 'Source PDF',
              topPadding: false,
              child: DsToolFileSource(
                files: [file],
                enabled: !_busy,
                onPick: _pick,
                onFilesDropped: (files) => _setFile(files.first),
                onRemove: (_) => _clearFile(),
                metaFor: (_) =>
                    _fileBytes == null ? null : dsFormatBytes(_fileBytes!),
              ),
            ),
          DsToolSection(
            title: 'Compression level',
            topPadding: file != null,
            subtitle: PdfCompressOptions.fromProfile(_profile)
                .effectDescription,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DsToolChoiceGroup<CompressProfile>(
                  selected: _profile,
                  onChanged: _busy
                      ? null
                      : (v) => _changeOption(() => _profile = v),
                  minCardWidth: 240,
                  choices: const [
                    DsToolChoice(
                      value: CompressProfile.smallest,
                      title: 'Smallest',
                      subtitle: 'Quality 40, longest edge 1000px',
                      icon: Icons.compress_rounded,
                    ),
                    DsToolChoice(
                      value: CompressProfile.extreme,
                      title: 'Extreme',
                      subtitle: 'Quality 45, longest edge 1200px',
                      icon: Icons.photo_size_select_large,
                    ),
                    DsToolChoice(
                      value: CompressProfile.balanced,
                      title: 'Recommended',
                      subtitle: 'Quality 60, longest edge 1600px',
                      icon: Icons.tune_rounded,
                      badge: 'Best',
                    ),
                    DsToolChoice(
                      value: CompressProfile.highQuality,
                      title: 'Lossless',
                      subtitle: 'Images untouched',
                      icon: Icons.high_quality_outlined,
                    ),
                    DsToolChoice(
                      value: CompressProfile.custom,
                      title: 'Custom',
                      subtitle: 'Pick each step',
                      icon: Icons.settings_suggest_outlined,
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _profile == CompressProfile.custom
                      ? Padding(
                          padding: const EdgeInsets.only(top: DsSpacing.md),
                          child: _customOptions(),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          DsToolSection(
            title: 'Estimated size',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_estimate case final e?)
                  _SizeCompare(before: e.beforeBytes, after: e.afterBytes)
                else
                  Text(
                    'See how small the file gets before you save it.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: DsColors.textSecondary(b),
                    ),
                  ),
                const SizedBox(height: DsSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: file == null || _busy || _estimating
                        ? null
                        : _estimateSize,
                    icon: _estimating
                        ? const SizedBox.square(
                            dimension: 14,
                            child: DsAdaptiveProgress(size: 14),
                          )
                        : const Icon(Icons.speed_rounded, size: 18),
                    label: Text(_estimating ? 'Estimating…' : 'Preview size'),
                  ),
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
          if (_errorMessage != null && !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: 'Compression failed',
                message: _errorMessage,
                tone: DsResultTone.error,
                onDismiss: () => setState(() => _errorMessage = null),
              ),
            ),
          if (_result case final r? when !_busy)
            Padding(
              padding: const EdgeInsets.only(top: DsSpacing.lg),
              child: DsToolResultCard(
                title: r.afterBytes >= r.beforeBytes
                    ? 'Not smaller'
                    : 'Saved ${r.percentSaved.toStringAsFixed(0)}% smaller',
                message: r.usedQpdf
                    ? null
                    : 'Optimized on this device with the built-in PDF engine.',
                file: r.output,
                tone: r.afterBytes >= r.beforeBytes
                    ? DsResultTone.info
                    : DsResultTone.success,
                stats: [
                  DsResultStat('Before', dsFormatBytes(r.beforeBytes)),
                  DsResultStat(
                    'After',
                    dsFormatBytes(r.afterBytes),
                    highlight: true,
                  ),
                  DsResultStat(
                    'Saved',
                    dsFormatBytes(
                      (r.beforeBytes - r.afterBytes).clamp(0, r.beforeBytes),
                    ),
                  ),
                ],
                onOpen: () => openToolResult(context, r.output),
                openLabel: 'Open in viewer',
                onShowInFolder: documentSaveResultCanRevealInFolder
                    ? () => revealToolResult(context, r.output)
                    : null,
                onDismiss: () => setState(() => _result = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _customOptions() {
    final onChanged = !_busy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DsColors.groupedBackground(Theme.of(context).brightness)
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpacing.md,
          vertical: DsSpacing.xs,
        ),
        child: Column(
          children: [
            DsAdaptiveSwitchTile(
              title: 'Downsample photos and scans',
              subtitle: 'Resample large JPEG images to about 180 dpi',
              value: _customDownsample,
              onChanged: onChanged
                  ? (v) => _changeOption(() => _customDownsample = v)
                  : null,
            ),
            DsAdaptiveSwitchTile(
              title: 'Convert other images to JPEG',
              subtitle: 'Lossy; only applied when the image gets smaller',
              value: _customOptimizeImages,
              onChanged: onChanged
                  ? (v) => _changeOption(() => _customOptimizeImages = v)
                  : null,
            ),
            DsAdaptiveSwitchTile(
              title: 'Recompress data streams',
              subtitle: 'Lossless',
              value: _customRecompressFlate,
              onChanged: onChanged
                  ? (v) => _changeOption(() => _customRecompressFlate = v)
                  : null,
            ),
            DsAdaptiveSwitchTile(
              title: 'Fast web view',
              subtitle: 'Linearize so the first page shows while downloading',
              value: _customLinearize,
              onChanged: onChanged
                  ? (v) => _changeOption(() => _customLinearize = v)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.qpdf, required this.onRecheck});

  final bool? qpdf;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color, tip) = switch (qpdf) {
      null => (
        'Checking engine…',
        DsColors.textSecondary(theme.brightness),
        '',
      ),
      true => ('qpdf engine', DsColors.success, 'Full-strength compression'),
      false => (
        'On-device engine',
        DsColors.success,
        'Built-in PDF compression (no external tools required).',
      ),
    };
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: qpdf == false ? onRecheck : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Before / after sizes as two bars on a common scale.
class _SizeCompare extends StatelessWidget {
  const _SizeCompare({required this.before, required this.after});

  final int before;
  final int after;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    final smaller = after < before;
    final saved = before == 0 ? 0 : (before - after) * 100 / before;
    Widget bar(String label, int bytes, Color color) => Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: DsColors.textSecondary(b),
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(
                end: before == 0 ? 0 : (bytes / before).clamp(0.0, 1.0),
              ),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                color: color,
                backgroundColor: DsColors.border(b).withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 72,
          child: Text(
            dsFormatBytes(bytes),
            textAlign: TextAlign.right,
            style: theme.textTheme.labelMedium,
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        bar('Before', before, DsColors.textSecondary(b)),
        const SizedBox(height: DsSpacing.sm),
        bar(
          'After',
          after,
          smaller ? DsColors.success : DsColors.textSecondary(b),
        ),
        const SizedBox(height: DsSpacing.sm),
        Text(
          smaller
              ? '${saved.toStringAsFixed(0)}% smaller'
              : 'Not smaller — this file is already well optimised.',
          style: theme.textTheme.labelLarge?.copyWith(
            color: smaller ? DsColors.success : DsColors.textSecondary(b),
          ),
        ),
      ],
    );
  }
}
