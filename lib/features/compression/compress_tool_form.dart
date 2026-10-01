import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_page_busy_bar.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/compression/compress_service.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// Shared compress UI for `/compress` route and viewer embedded panel.
class CompressToolForm extends ConsumerStatefulWidget {
  const CompressToolForm({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.lockSourceFile = false,
    this.showRelatedTools = true,
    this.showStickyActions = true,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool lockSourceFile;
  final bool showRelatedTools;
  final bool showStickyActions;

  @override
  ConsumerState<CompressToolForm> createState() => _CompressToolFormState();
}

class _CompressToolFormState extends ConsumerState<CompressToolForm> {
  LocalFileRef? _file;
  CompressResult? _result;
  CompressResult? _estimate;
  CompressProfile _profile = CompressProfile.balanced;
  bool _customRecompressFlate = true;
  bool _customLinearize = false;
  bool _customOptimizeImages = false;
  bool _customDownsample = true;
  bool _busy = false;
  bool _estimating = false;
  bool? _qpdfAvailable;
  String? _statusMessage;
  double? _progress;
  JobHandle<CompressResult>? _activeJob;
  String? _password;

  @override
  void initState() {
    super.initState();
    _refreshQpdf();
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) {
        _password = pw;
      }
    }
  }

  Future<void> _refreshQpdf() async {
    final svc = ref.read(compressServiceProvider);
    final ok = await svc.isQpdfPreferredAvailable();
    if (mounted) setState(() => _qpdfAvailable = ok);
  }

  PdfCompressOptions _currentOptions() {
    if (_profile == CompressProfile.custom) {
      final lossy = _customOptimizeImages || _customDownsample;
      return PdfCompressOptions.fromProfile(CompressProfile.custom).mergeCustom(
        recompressFlate: _customRecompressFlate,
        linearize: _customLinearize,
        optimizeImages: _customOptimizeImages,
        jpegQuality: lossy ? 65 : null,
        downsampleMaxPx: _customDownsample ? 2000 : null,
      );
    }
    return PdfCompressOptions.fromProfile(_profile);
  }

  Future<void> _estimateSize() async {
    if (_file == null) return;
    setState(() {
      _estimating = true;
      _estimate = null;
    });
    try {
      final svc = ref.read(compressServiceProvider);
      final result = await svc.estimateCompress(
        input: _file!,
        options: _currentOptions(),
        password: _password,
      );
      if (!mounted) return;
      setState(() => _estimate = result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estimate failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Future<void> _pick() async {
    final storage = ref.read(fileStorageProvider);
    final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
    if (picked != null) {
      setState(() {
        _file = picked;
        _result = null;
        _estimate = null;
        _password = null;
      });
    }
  }

  void _pushDocumentTool(String path) {
    final file = _file;
    if (file == null) {
      context.push(path);
      return;
    }
    context.push(
      path,
      extra: PdfDocumentRouteArgs(file: file, password: _password),
    );
  }

  void _pushPdfToImages() {
    final file = _file;
    if (file == null) {
      context.push(pdfToImagesRoutePath);
      return;
    }
    context.push(
      pdfToImagesRoutePath,
      extra: PdfToImagesRouteArgs(file: file, password: _password),
    );
  }

  Future<void> _run() async {
    if (_file == null) return;
    setState(() {
      _busy = true;
      _result = null;
      _statusMessage = 'Starting…';
      _progress = null;
    });
    final job = JobHandle<CompressResult>();
    setState(() => _activeJob = job);
    try {
      final svc = ref.read(compressServiceProvider);
      final options = _currentOptions();
      if (widget.lockSourceFile) {
        final before = await File(_file!.path).length();
        final session =
            ref.read(documentTabsControllerProvider).activeSession;
        if (session == null) return;
        final storage = ref.read(fileStorageProvider);
        final tempDir = await storage.getTempDirectory();
        final tempOut = p.join(
          tempDir,
          'compress-${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
        setState(() => _statusMessage = 'Optimizing PDF…');
        await svc.compressToPath(
          handle: JobHandle<LocalFileRef>(),
          input: _file!,
          outputPath: tempOut,
          options: options,
          password: _password,
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _statusMessage = p.message;
                _progress = p.fraction;
              });
            }
          },
        );
        final after = await File(tempOut).length();
        if (!mounted) return;
        if (after >= before) {
          File(tempOut).delete().ignore();
          setState(() {
            _result = CompressResult(
              output: _file!,
              beforeBytes: before,
              afterBytes: before,
              usedQpdf: true,
            );
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${_fmtBytes(before)} → ${_fmtBytes(after)}. Not smaller. '
                'The document was not changed.',
              ),
            ),
          );
          return;
        }
        final saved = await commitTempPathToActiveSession(
          ref: ref,
          context: context,
          tempPath: tempOut,
          successMessage: 'Compressed from ${_fmtBytes(before)} to '
              '${_fmtBytes(after)}.',
        );
        if (saved != null && mounted) {
          setState(() {
            _result = CompressResult(
              output: saved,
              beforeBytes: before,
              afterBytes: after,
              usedQpdf: true,
            );
          });
        }
        return;
      }
      final result = await svc.compressAndPromptSave(
        handle: job,
        input: _file!,
        options: options,
        password: _password,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _statusMessage = p.message;
              _progress = p.fraction;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _result = result);
      showDocumentSaveResultActions(
        context,
        file: result.output,
        password: _password,
        message: result.afterBytes >= result.beforeBytes
            ? '${_fmtBytes(result.beforeBytes)} → '
                '${_fmtBytes(result.afterBytes)}. Not smaller.'
            : 'Saved — ${_fmtBytes(result.beforeBytes)} → '
                '${_fmtBytes(result.afterBytes)} '
                '(${result.percentSaved.toStringAsFixed(0)}% smaller)',
      );
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.processCancelled) return;
      if (e.code == DocumentStudioErrorCode.passwordRequired ||
          e.code == DocumentStudioErrorCode.wrongPassword) {
        if (!mounted) return;
        final pw = await promptPdfPasswordAfterRejection(
          context,
          rejected: e.code == DocumentStudioErrorCode.wrongPassword ? e : null,
        );
        if (pw != null && pw.isNotEmpty) {
          setState(() => _password = pw);
          await _run();
        }
        return;
      }
      if (!mounted) return;
      await _showCompressError(context, e, qpdfAvailable: _qpdfAvailable);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _activeJob = null;
          _statusMessage = null;
          _progress = null;
        });
      }
    }
  }

  Future<void> _showCompressError(
    BuildContext context,
    DocumentStudioError e, {
    required bool? qpdfAvailable,
  }) async {
    final detail = () {
      final hint = e.recoveryHint?.trim();
      if (hint != null && hint.isNotEmpty) return hint;
      final cause = e.cause;
      if (cause is QpdfCliException) {
        final d = cause.stderr.trim().isEmpty
            ? cause.stdout.trim()
            : cause.stderr.trim();
        if (d.isNotEmpty) return d;
      }
      return e.message;
    }();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Compression failed'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondary =
        isDark ? DsColors.textSecondaryDark : DsColors.textSecondaryLight;
    final qpdf = _qpdfAvailable;
    final lockFile = widget.lockSourceFile && _file != null;

    final formBody = ListView(
      children: [
        DsToolFormLayout(
          primary: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (qpdf == false)
                Padding(
                  padding: const EdgeInsets.only(bottom: DsSpacing.lg),
                  child: DsToolPanel(
                    title: 'On-device compression',
                    child: Text(
                      'Compression runs on this device with the built-in PDF '
                      'engine. Smallest, Extreme, and Recommended re-encode '
                      'photos as JPEG. Text pages stay selectable.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              if (!lockFile)
                DsToolPanel(
                  title: 'Source file',
                  subtitle: _file?.displayName ?? 'Choose a PDF to optimize',
                  child: _file == null
                      ? DsEmptyState(
                          title: 'No PDF selected',
                          subtitle:
                              'Pick a file, then run compress from the options panel.',
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _file!.displayName,
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: DsSpacing.sm),
                            DsSecondaryButton(
                              label: 'Choose another PDF',
                              icon: Icons.picture_as_pdf,
                              onPressed: _busy ? null : _pick,
                            ),
                          ],
                        ),
                ),
              if (_result != null) ...[
                const SizedBox(height: DsSpacing.lg),
                DsToolPanel(
                  title: 'Size comparison',
                  subtitle: _result!.output.displayName,
                  child: CompressStatsHighlight(result: _result!),
                ),
              ],
            ],
          ),
          sidebar: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DsToolPanel(
                title: 'Compression level',
                subtitle: 'Choose how much to shrink the file',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final profile in kCompressPanelProfiles)
                          ChoiceChip(
                            label: Text(
                              PdfCompressOptions.fromProfile(profile).userLabel,
                            ),
                            selected: _profile == profile,
                            onSelected: _busy
                                ? null
                                : (selected) {
                                    if (!selected) return;
                                    setState(() {
                                      _profile = profile;
                                      _estimate = null;
                                    });
                                  },
                          ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: DsSpacing.sm),
                      child: Text(
                        PdfCompressOptions.fromProfile(
                          _profile == CompressProfile.custom
                              ? CompressProfile.custom
                              : _profile,
                        ).effectDescription,
                        style: theme.textTheme.bodySmall?.copyWith(color: secondary),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(
                                () => _profile = CompressProfile.custom,
                              ),
                      child: Text(
                        _profile == CompressProfile.custom
                            ? 'Custom options'
                            : 'Advanced…',
                      ),
                    ),
                    if (_profile == CompressProfile.custom) ...[
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Downsample photos and scans'),
                        subtitle: const Text(
                          'Resample large JPEG images to about 180 dpi',
                        ),
                        value: _customDownsample,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _customDownsample = v;
                                  _estimate = null;
                                }),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Convert other images to JPEG'),
                        subtitle: const Text(
                          'Lossy; only applied when the image gets smaller',
                        ),
                        value: _customOptimizeImages,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _customOptimizeImages = v;
                                  _estimate = null;
                                }),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Recompress data streams'),
                        subtitle: const Text('Lossless'),
                        value: _customRecompressFlate,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _customRecompressFlate = v;
                                  _estimate = null;
                                }),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Fast web view'),
                        subtitle: const Text(
                          'Linearize so the first page opens while downloading',
                        ),
                        value: _customLinearize,
                        onChanged: _busy
                            ? null
                            : (v) => setState(() {
                                  _customLinearize = v;
                                  _estimate = null;
                                }),
                      ),
                    ],
                    const SizedBox(height: DsSpacing.sm),
                    DsSecondaryButton(
                      key: const Key('compress_estimate_button'),
                      label: _estimating ? 'Estimating…' : 'Preview size',
                      icon: Icons.preview_outlined,
                      onPressed: _file == null || _busy || _estimating
                          ? null
                          : _estimateSize,
                    ),
                    if (_estimate != null) ...[
                      const SizedBox(height: DsSpacing.sm),
                      Text(
                        key: const Key('compress_estimate_result'),
                        '${_fmtBytes(_estimate!.beforeBytes)} → '
                            '${_fmtBytes(_estimate!.afterBytes)}. '
                            '${_estimate!.afterBytes >= _estimate!.beforeBytes ? 'Not smaller.' : '(${_estimate!.percentSaved.toStringAsFixed(0)}% smaller)'}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (_file == null && !lockFile)
                Padding(
                  padding: const EdgeInsets.only(top: DsSpacing.lg),
                  child: DsSecondaryButton(
                    label: 'Choose PDF',
                    icon: Icons.folder_open,
                    onPressed: _busy ? null : _pick,
                  ),
                ),
              if (widget.showRelatedTools)
                DsToolPanel(
                  title: 'Related tools',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextButton.icon(
                        onPressed: _busy ? null : _pushPdfToImages,
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('PDF to images'),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => context.push(imagesToPdfRoutePath),
                        icon: const Icon(Icons.collections_bookmark_outlined),
                        label: const Text('Images to PDF'),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pushDocumentTool(protectRoutePath),
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Encrypt'),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pushDocumentTool(unlockRoutePath),
                        icon: const Icon(Icons.lock_open_outlined),
                        label: const Text('Decrypt'),
                      ),
                      TextButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pushDocumentTool(removeMetadataRoutePath),
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('Remove metadata'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return DsPageBusyHost(
      busy: _busy,
      message: _statusMessage ?? (_busy ? 'Compressing…' : null),
      progress: _progress,
      onCancel: _busy && _activeJob != null
          ? () => ref.read(jobRunnerProvider).requestCancel(_activeJob!)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: formBody),
          if (widget.showStickyActions)
            DsToolStickyActionBar(
              primaryLabel: widget.lockSourceFile
                  ? 'Compress'
                  : 'Compress & save as',
              primaryIcon: Icons.save_alt,
              primaryEnabled: _file != null,
              primaryBusy: _busy,
              onPrimary: _run,
              onCancel: _busy
                  ? () {
                      final job = _activeJob;
                      if (job != null) {
                        ref.read(jobRunnerProvider).requestCancel(job);
                      }
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

String formatCompressByteSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class CompressStatsHighlight extends StatelessWidget {
  const CompressStatsHighlight({super.key, required this.result});

  final CompressResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shrunk = result.afterBytes < result.beforeBytes;
    final saved = result.percentSaved;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Original',
                value: formatCompressByteSize(result.beforeBytes),
              ),
            ),
            Icon(Icons.arrow_forward, color: theme.hintColor, size: 20),
            Expanded(
              child: _StatTile(
                label: 'New',
                value: formatCompressByteSize(result.afterBytes),
              ),
            ),
          ],
        ),
        const SizedBox(height: DsSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(
            vertical: DsSpacing.md,
            horizontal: DsSpacing.lg,
          ),
          decoration: BoxDecoration(
            color: (shrunk ? DsColors.success : theme.colorScheme.surfaceContainerHighest)
                .withValues(alpha: shrunk ? 0.12 : 1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            shrunk
                ? '${saved.toStringAsFixed(1)}% smaller'
                : 'Not smaller',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: shrunk ? DsColors.success : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
