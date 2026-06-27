import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/jobs/job_models.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/infrastructure/pdf/pdf_compress_options.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Right-rail compress: Smallest, Extreme, Recommended, and Lossless.
class ViewerCompressPanel extends ConsumerStatefulWidget {
  const ViewerCompressPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerCompressPanel> createState() =>
      _ViewerCompressPanelState();
}

class _ViewerCompressPanelState extends ConsumerState<ViewerCompressPanel> {
  CompressProfile _profile = CompressProfile.balanced;
  String? _sizeNote;
  bool _estimating = false;
  bool _busy = false;
  String? _error;
  String? _password;

  @override
  void initState() {
    super.initState();
    final pw = widget.handoff.password;
    if (pw != null && pw.isNotEmpty) _password = pw;
  }

  PdfCompressOptions get _options => PdfCompressOptions.fromProfile(_profile);

  /// Session working copy. Apply never reads or writes the user's original.
  LocalFileRef _inputFile() {
    final session = ref.read(documentTabsControllerProvider).activeSession;
    if (session != null) return session.file;
    return widget.handoff.file;
  }

  String? _inputPassword() {
    final prompted = _password;
    if (prompted != null && prompted.isNotEmpty) return prompted;
    final fromSession =
        ref.read(documentTabsControllerProvider).activeSession?.password;
    if (fromSession != null && fromSession.isNotEmpty) return fromSession;
    final handoff = widget.handoff.password;
    if (handoff != null && handoff.isNotEmpty) return handoff;
    return null;
  }

  String _sizeLine(int before, int after) {
    final line = '${_fmtBytes(before)} → ${_fmtBytes(after)}';
    if (before <= 0 || after >= before) return '$line. Not smaller.';
    final saved = (1 - after / before) * 100;
    return '$line (${saved.toStringAsFixed(1)}% smaller)';
  }

  String _fmtBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String _errorText(Object e) {
    final raw = _rawErrorText(e);
    if (!kIsWeb &&
        Platform.isAndroid &&
        raw.toLowerCase().contains('qpdf') &&
        raw.toLowerCase().contains('not available')) {
      return 'Compression runs on this device. Text pages stay selectable.';
    }
    return raw;
  }

  String _rawErrorText(Object e) {
    if (e is DocumentStudioError) {
      final hint = e.recoveryHint?.trim();
      if (hint != null && hint.isNotEmpty) return hint;
      final cause = e.cause;
      if (cause is QpdfCliException) {
        final detail = cause.stderr.trim().isEmpty
            ? cause.stdout.trim()
            : cause.stderr.trim();
        if (detail.isNotEmpty) return detail;
      }
      return e.message;
    }
    if (e is QpdfCliException) {
      final detail =
          e.stderr.trim().isEmpty ? e.stdout.trim() : e.stderr.trim();
      return detail.isEmpty ? e.toString() : detail;
    }
    return '$e';
  }

  Future<void> _estimateSize() async {
    setState(() {
      _estimating = true;
      _sizeNote = null;
      _error = null;
    });
    try {
      final svc = ref.read(compressServiceProvider);
      final result = await svc.estimateCompress(
        input: _inputFile(),
        options: _options,
        password: _inputPassword(),
      );
      if (!mounted) return;
      setState(() {
        _sizeNote = _sizeLine(result.beforeBytes, result.afterBytes);
      });
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.passwordRequired ||
          e.code == DocumentStudioErrorCode.wrongPassword) {
        if (!mounted) return;
        final pw = await promptPdfPasswordAfterRejection(
          context,
          rejected: e.code == DocumentStudioErrorCode.wrongPassword ? e : null,
        );
        if (pw != null && pw.isNotEmpty) {
          setState(() => _password = pw);
          await _estimateSize();
        }
        return;
      }
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session == null) {
        setState(() => _error = 'Open a PDF to compress it.');
        return;
      }
      final input = session.file;
      final before = await File(input.path).length();
      final svc = ref.read(compressServiceProvider);
      final storage = ref.read(fileStorageProvider);
      final tempDir = await storage.getTempDirectory();
      final tempOut = p.join(
        tempDir,
        'compress-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      await svc.compressToPath(
        handle: JobHandle<LocalFileRef>(),
        input: input,
        outputPath: tempOut,
        options: _options,
        password: _inputPassword(),
      );
      if (!mounted) return;
      final after = await File(tempOut).length();
      if (!mounted) return;
      if (after >= before) {
        File(tempOut).delete().ignore();
        setState(() {
          _sizeNote =
              '${_sizeLine(before, after)} The document was not changed.';
        });
        return;
      }
      await commitTempPathToActiveSession(
        ref: ref,
        context: context,
        tempPath: tempOut,
        successMessage: _sizeLine(before, after),
      );
      if (mounted) {
        setState(() => _sizeNote = _sizeLine(before, after));
      }
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
          await _apply();
        }
        return;
      }
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(fontSize: 13);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(fontSize: 13);
    final options = _options;

    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_compress_apply'),
      primaryLabel: _busy ? 'Compressing…' : 'Compress',
      primaryIcon: Icons.compress,
      primaryEnabled: !_busy && !_estimating,
      primaryBusy: _busy,
      onPrimary: () => unawaited(_apply()),
      notice: _error == null
          ? null
          : Text(
              _error!,
              style: bodyStyle?.copyWith(color: DsColors.primary),
            ),
      children: [
              Text('Compression level', style: labelStyle),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final profile in kCompressPanelProfiles)
                    ChoiceChip(
                      label: Text(
                        PdfCompressOptions.fromProfile(profile).userLabel,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: _profile == profile,
                      onSelected: _busy || _estimating
                          ? null
                          : (selected) {
                              if (!selected) return;
                              setState(() {
                                _profile = profile;
                                _sizeNote = null;
                                _error = null;
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: DsSpacing.sm),
              Text(options.effectDescription, style: bodyStyle),
              const SizedBox(height: DsSpacing.md),
              OutlinedButton(
                onPressed: _busy || _estimating
                    ? null
                    : () => unawaited(_estimateSize()),
                child: Text(
                  _estimating ? 'Estimating…' : 'Estimate',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              if (_sizeNote != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  _sizeNote!,
                  key: const Key('viewer_compress_estimate'),
                  style: bodyStyle?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
        ],
    );
  }
}
