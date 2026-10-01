import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_tool_route_actions.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/security/security_save_helper.dart';
import 'package:document_studio/features/security/security_tool_widgets.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_metadata_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class RemoveMetadataDeps {
  const RemoveMetadataDeps({
    required this.fileStorage,
    required this.metadataPort,
  });

  final FileStoragePort fileStorage;
  final PdfMetadataPort metadataPort;
}

class RemoveMetadataScreen extends ConsumerStatefulWidget {
  const RemoveMetadataScreen({
    super.key,
    required this.deps,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final RemoveMetadataDeps deps;
  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<RemoveMetadataScreen> createState() =>
      _RemoveMetadataScreenState();
}

class _RemoveMetadataScreenState extends ConsumerState<RemoveMetadataScreen> {
  LocalFileRef? _file;
  bool _busy = false;
  bool? _qpdfAvailable;
  String? _inputPassword;
  LocalFileRef? _saved;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) _inputPassword = pw;
    }
  }

  Future<void> _refreshAvailability() async {
    final available = await widget.deps.metadataPort.isAvailable();
    if (mounted) setState(() => _qpdfAvailable = available);
  }

  void _setFile(LocalFileRef? file) {
    setState(() {
      _file = file;
      _inputPassword = null;
      _saved = null;
      _error = null;
    });
  }

  Future<void> _pick() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: ['pdf'],
    );
    if (picked != null) _setFile(picked);
  }

  Future<void> _run() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _saved = null;
      _error = null;
    });
    var retry = false;
    String? temp;
    try {
      final storage = widget.deps.fileStorage;
      temp = await storage.createTempFile(prefix: 'strip-meta', suffix: '.pdf');
      await widget.deps.metadataPort.stripAllMetadata(
        input: file,
        outputPath: temp,
        inputPassword: _inputPassword,
      );
      if (!mounted) return;
      if (widget.embedInViewerPanel) {
        await commitTempPathToActiveSession(
          ref: ref,
          context: context,
          tempPath: temp,
          successMessage: 'Metadata removed from this document.',
        );
        temp = null;
        return;
      }
      final saved = await promptSavePdfFromTemp(
        storage: storage,
        source: LocalFileRef(path: temp, displayName: 'clean.pdf'),
        suggestedBaseName:
            '${p.basenameWithoutExtension(file.displayName)}-clean',
      );
      if (!mounted || saved == null) return;
      setState(() => _saved = saved);
    } on DocumentStudioError catch (e) {
      if (e.code == DocumentStudioErrorCode.wrongPassword ||
          e.code == DocumentStudioErrorCode.passwordRequired) {
        if (!mounted) return;
        final pw = await promptPdfPasswordAfterRejection(
          context,
          rejected: e.code == DocumentStudioErrorCode.wrongPassword ? e : null,
        );
        if (pw != null && pw.isNotEmpty && mounted) {
          setState(() => _inputPassword = pw);
          retry = true;
        }
        return;
      }
      if (mounted) setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (temp != null) File(temp).delete().ignore();
      if (mounted) setState(() => _busy = false);
      if (retry && mounted) {
        Future.microtask(_run);
      }
    }
  }

  Widget _body({required bool lockFile}) {
    final theme = Theme.of(context);
    final qpdf = _qpdfAvailable;
    final secondary = DsColors.textSecondary(theme.brightness);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (qpdf == false) ...[
          SecurityQpdfUnavailablePanel(
            onRecheck: _refreshAvailability,
            busy: _busy,
          ),
          const SizedBox(height: DsSpacing.lg),
        ],
        DsToolSection(
          topPadding: false,
          title: 'Source PDF',
          child: lockFile
              ? Text(_file!.displayName, style: theme.textTheme.titleSmall)
              : DsToolFileSource(
                  files: [?_file],
                  enabled: !_busy,
                  onPick: _pick,
                  onFilesDropped: (files) => _setFile(files.first),
                  onRemove: (_) => _setFile(null),
                  metaFor: (f) =>
                      f.sizeBytes == null ? null : dsFormatBytes(f.sizeBytes!),
                  emptyTitle: 'Drop a PDF to clean',
                  emptySubtitle: 'Produces a copy without hidden metadata',
                  icon: Icons.cleaning_services_outlined,
                ),
        ),
        DsToolSection(
          title: 'What gets removed',
          child: Wrap(
            spacing: DsSpacing.sm,
            runSpacing: DsSpacing.sm,
            children: [
              for (final label in const [
                'Title',
                'Author',
                'Subject & keywords',
                'Creator app',
                'Dates',
                'XMP metadata',
              ])
                Chip(
                  avatar: const Icon(Icons.remove_circle_outline, size: 16),
                  label: Text(label),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: DsSpacing.sm),
          child: Text(
            'Page content, annotations and form fields are unchanged.',
            style: theme.textTheme.bodySmall?.copyWith(color: secondary),
          ),
        ),
        DsToolSection(
          title: 'Encrypted PDFs',
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy
                  ? null
                  : () async {
                      final pw = await promptPdfPasswordAfterRejection(context);
                      if (pw != null && pw.isNotEmpty && mounted) {
                        setState(() => _inputPassword = pw);
                      }
                    },
              icon: Icon(
                _inputPassword == null
                    ? Icons.vpn_key_outlined
                    : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(
                _inputPassword == null
                    ? 'Set PDF password'
                    : 'Password set — change',
              ),
            ),
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolProgressCard(message: 'Removing metadata…'),
          ),
        if (_error != null && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Could not remove metadata',
              message: _error,
              tone: DsResultTone.error,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        if (_saved case final saved? when !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Clean copy saved',
              message: 'Document info and XMP metadata were removed.',
              file: saved,
              onOpen: () =>
                  openToolResult(context, saved, password: _inputPassword),
              openLabel: 'Open in viewer',
              onShowInFolder: documentSaveResultCanRevealInFolder
                  ? () => revealToolResult(context, saved)
                  : null,
              onDismiss: () => setState(() => _saved = null),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final qpdf = _qpdfAvailable;
    final embed = widget.embedInViewerPanel;
    final canRun = _file != null && !_busy && qpdf == true;

    if (embed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DsSpacing.md),
              children: [_body(lockFile: _file != null)],
            ),
          ),
          DsToolStickyActionBar(
            primaryLabel: 'Remove metadata',
            primaryIcon: Icons.cleaning_services_outlined,
            primaryEnabled: canRun,
            primaryBusy: _busy,
            onPrimary: _run,
          ),
        ],
      );
    }

    return DsToolPage(
      title: 'Remove metadata',
      subtitle: 'Strip hidden document info before you share a PDF.',
      icon: Icons.cleaning_services_outlined,
      iconColor: const Color(0xFF7C3AED),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => handleDsToolFormCancel(context, ref),
      ),
      primaryLabel: 'Remove & save as…',
      primaryIcon: Icons.save_alt_rounded,
      primaryEnabled: canRun,
      primaryBusy: _busy,
      onPrimary: _run,
      onCancel: () => handleDsToolFormCancel(context, ref),
      footer: SecurityRelatedToolsPanel(
        compact: true,
        busy: _busy,
        excludePath: removeMetadataRoutePath,
        sourceFile: _file,
        sourcePassword: _inputPassword,
      ),
      child: _body(lockFile: false),
    );
  }
}
