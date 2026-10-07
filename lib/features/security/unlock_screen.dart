import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_tool_route_actions.dart';
import 'package:document_studio/design_system/widgets/ds_pdf_preview.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/page_management/pdf_password_prompt.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/security/security_save_helper.dart';
import 'package:document_studio/features/security/security_tool_widgets.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:document_studio/infrastructure/pdf/routing_pdf_encrypt_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class UnlockDeps {
  const UnlockDeps({required this.fileStorage, required this.encryptPort});

  final FileStoragePort fileStorage;
  final PdfEncryptPort encryptPort;
}

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({
    super.key,
    required this.deps,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final UnlockDeps deps;
  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  LocalFileRef? _file;
  bool _busy = false;
  bool? _qpdfAvailable;
  final _passwordController = TextEditingController();
  LocalFileRef? _saved;
  String? _error;
  bool _alreadyOpen = false;

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) {
        _passwordController.text = pw;
      }
    }
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _refreshAvailability() async {
    final available = await widget.deps.encryptPort.isAvailable();
    if (mounted) setState(() => _qpdfAvailable = available);
  }

  Future<void> _pick() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: ['pdf'],
    );
    if (picked != null) _setFile(picked);
  }

  Future<void> _run() async {
    if (_file == null) return;
    setState(() => _alreadyOpen = false);
    var password = _passwordController.text;
    PdfProtectionState protection;
    final port = widget.deps.encryptPort;
    if (port is QpdfEncryptAdapter || port is RoutingPdfEncryptAdapter) {
      protection = await probePdfProtectionRouted(_file!.path);
    } else {
      // Test doubles / alternate engines: skip filesystem probe.
      protection = PdfProtectionState.unknown;
    }
    if (!mounted) return;
    if (protection == PdfProtectionState.none) {
      setState(() {
        _saved = null;
        _error = null;
        _alreadyOpen = true;
      });
      return;
    }
    final needsPassword =
        protection == PdfProtectionState.openPassword ||
        protection == PdfProtectionState.unknown;
    if (password.isEmpty && needsPassword) {
      final prompted = await promptPdfPassword(context);
      if (prompted == null || prompted.isEmpty) return;
      password = prompted;
      _passwordController.text = password;
    }

    setState(() {
      _busy = true;
      _saved = null;
      _error = null;
    });
    try {
      while (mounted) {
        try {
          final storage = widget.deps.fileStorage;
          final temp = await storage.createTempFile(
            prefix: 'unlock',
            suffix: '.pdf',
          );
          await widget.deps.encryptPort.decryptToFile(
            input: _file!,
            outputPath: temp,
            password: password,
          );
          if (widget.embedInViewerPanel) {
            if (!mounted) return;
            await commitTempPathToActiveSession(
              ref: ref,
              context: context,
              tempPath: temp,
              successMessage: 'Security removed from this document.',
              configureSession: (session) {
                session.password = null;
              },
            );
            return;
          }
          final LocalFileRef? saved;
          try {
            saved = await promptSavePdfFromTemp(
              storage: storage,
              source: LocalFileRef(path: temp, displayName: 'unlocked.pdf'),
              suggestedBaseName:
                  '${p.basenameWithoutExtension(_file!.displayName)}-unlocked',
            );
          } finally {
            File(temp).delete().ignore();
          }
          if (!mounted || saved == null) return;
          setState(() => _saved = saved);
          return;
        } on DocumentStudioError catch (e) {
          if (e.code != DocumentStudioErrorCode.wrongPassword &&
              e.code != DocumentStudioErrorCode.passwordRequired) {
            rethrow;
          }
          if (!mounted) return;
          _passwordController.clear();
          final pw = await promptPdfPasswordAfterRejection(
            context,
            rejected: e,
          );
          if (pw == null || pw.isEmpty) return;
          password = pw;
          _passwordController.text = password;
        }
      }
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.recoveryHint ?? e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setFile(LocalFileRef? file) {
    setState(() {
      _file = file;
      _saved = null;
      _error = null;
      _passwordController.clear();
    });
  }

  Widget _formBody({required bool lockFile, bool split = false}) {
    final theme = Theme.of(context);
    final qpdf = _qpdfAvailable;

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
        if (!split || _file != null)
          DsToolSection(
            topPadding: false,
            title: 'Source file',
            subtitle: 'Encrypted PDF to decrypt',
            child: lockFile
                ? Text(_file!.displayName, style: theme.textTheme.titleSmall)
                : DsToolFileSource(
                    files: [?_file],
                    enabled: !_busy,
                    onPick: _pick,
                    onFilesDropped: (files) => _setFile(files.first),
                    onRemove: (_) => _setFile(null),
                    metaFor: (f) => f.sizeBytes == null
                        ? null
                        : dsFormatBytes(f.sizeBytes!),
                    emptyTitle: 'Drop a protected PDF',
                    emptySubtitle: 'You will need its password if it has one',
                    icon: Icons.lock_open_rounded,
                  ),
          ),
        DsToolSection(
          title: 'Password',
          subtitle:
              'Leave empty if the PDF opens without a password and only '
              'blocks printing, copying, or editing',
          child: TextField(
            key: const Key('unlock_password'),
            controller: _passwordController,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'PDF password',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (_alreadyOpen && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Nothing to decrypt',
              message: 'This PDF has no password or restrictions.',
              tone: DsResultTone.info,
              onDismiss: () => setState(() => _alreadyOpen = false),
            ),
          ),
        if (_error != null && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Could not decrypt this PDF',
              message: _error,
              tone: DsResultTone.error,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        if (_saved case final saved? when !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Decrypted copy saved',
              message: 'Anyone can now open, print and copy from this copy.',
              file: saved,
              onOpen: () => openToolResult(context, saved),
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
    final lockFile = embed && _file != null;

    if (embed) {
      return ViewerToolFormScaffold(
        primaryLabel: 'Decrypt',
        primaryIcon: Icons.lock_open,
        primaryEnabled: _file != null && qpdf == true,
        primaryBusy: _busy,
        onPrimary: _run,
        children: [_formBody(lockFile: lockFile)],
      );
    }

    return DsToolPage(
      title: 'Decrypt',
      subtitle: 'Remove the password and save a new copy.',
      icon: Icons.lock_open_rounded,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => handleDsToolFormCancel(context, ref),
      ),
      primaryLabel: 'Decrypt & save as',
      primaryIcon: Icons.lock_open,
      primaryEnabled: _file != null && qpdf == true,
      primaryBusy: _busy,
      onPrimary: _run,
      onCancel: () => handleDsToolFormCancel(context, ref),
      busy: _busy,
      busyMessage: _busy ? 'Decrypting…' : null,
      footer: SecurityRelatedToolsPanel(
        compact: true,
        busy: _busy,
        excludePath: unlockRoutePath,
        sourceFile: _file,
        sourcePassword: _passwordController.text.isEmpty
            ? widget.initialPassword
            : _passwordController.text,
      ),
      preview: DsPdfPreviewPane(
        file: _file,
        enabled: !_busy,
        onPick: _pick,
        onFilesDropped: (files) => _setFile(files.first),
        emptyTitle: 'Drop a protected PDF',
        emptySubtitle: 'You will need its password if it has one',
        icon: Icons.lock_open_rounded,
      ),
      child: _formBody(lockFile: false, split: true),
    );
  }
}
