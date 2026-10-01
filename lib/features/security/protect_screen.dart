import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_tool_route_actions.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/security/protect_permission_presets.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/security/security_save_helper.dart';
import 'package:document_studio/features/security/security_tool_widgets.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class ProtectDeps {
  const ProtectDeps({
    required this.fileStorage,
    required this.encryptPort,
  });

  final FileStoragePort fileStorage;
  final PdfEncryptPort encryptPort;
}

class ProtectScreen extends ConsumerStatefulWidget {
  const ProtectScreen({
    super.key,
    required this.deps,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final ProtectDeps deps;
  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<ProtectScreen> createState() => _ProtectScreenState();
}

class _ProtectScreenState extends ConsumerState<ProtectScreen> {
  LocalFileRef? _file;
  bool _busy = false;
  bool? _qpdfAvailable;
  final _userPasswordController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _inputPasswordController = TextEditingController();
  bool _showPasswords = false;
  ProtectPermissionPreset _preset = ProtectPermissionPreset.printOnly;
  bool _allowPrinting = true;
  bool _allowCopy = false;
  bool _allowModify = false;
  bool _allowAnnotate = false;
  LocalFileRef? _saved;
  String? _savedPassword;
  String? _error;

  void _applyPreset(ProtectPermissionPreset preset) {
    if (preset == ProtectPermissionPreset.custom) {
      setState(() => _preset = preset);
      return;
    }
    final p = permissionsForPreset(preset);
    setState(() {
      _preset = preset;
      _allowPrinting = p.allowPrinting;
      _allowCopy = p.allowExtract;
      _allowModify = p.allowModify;
      _allowAnnotate = p.allowAnnotate;
    });
  }

  void _onPermissionToggle({
    required bool allowPrinting,
    required bool allowCopy,
    required bool allowModify,
    required bool allowAnnotate,
  }) {
    setState(() {
      _allowPrinting = allowPrinting;
      _allowCopy = allowCopy;
      _allowModify = allowModify;
      _allowAnnotate = allowAnnotate;
      _preset = presetMatching(
        allowPrinting: allowPrinting,
        allowCopy: allowCopy,
        allowModify: allowModify,
        allowAnnotate: allowAnnotate,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) {
        _inputPasswordController.text = pw;
      }
    }
  }

  @override
  void dispose() {
    _userPasswordController.dispose();
    _ownerPasswordController.dispose();
    _confirmPasswordController.dispose();
    _inputPasswordController.dispose();
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

  void _setFile(LocalFileRef? file) {
    setState(() {
      _file = file;
      _saved = null;
      _error = null;
      _inputPasswordController.clear();
    });
  }

  Future<void> _run() async {
    if (_file == null) return;
    final userPassword = _userPasswordController.text;
    if (userPassword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a password to open the PDF.')),
      );
      return;
    }
    if (_confirmPasswordController.text != userPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The two passwords don’t match.')),
      );
      return;
    }

    setState(() {
      _busy = true;
      _saved = null;
      _error = null;
    });
    try {
      final storage = widget.deps.fileStorage;
      final temp = await storage.createTempFile(
        prefix: 'protect',
        suffix: '.pdf',
      );
      final output = await widget.deps.encryptPort.encryptWithPassword(
        input: _file!,
        outputPath: temp,
        userPassword: userPassword,
        ownerPassword: _ownerPasswordController.text,
        inputPassword: _inputPasswordController.text.isEmpty
            ? null
            : _inputPasswordController.text,
        permissions: PdfEncryptPermissions(
          allowPrinting: _allowPrinting,
          allowModify: _allowModify,
          allowExtract: _allowCopy,
          allowAnnotate: _allowAnnotate,
        ),
      );
      if (widget.embedInViewerPanel) {
        if (!mounted) return;
        await commitTempPathToActiveSession(
          ref: ref,
          context: context,
          tempPath: output.path,
          successMessage: 'Password protection applied to this document.',
          configureSession: (session) {
            session.password = userPassword;
          },
        );
        return;
      }
      final LocalFileRef? saved;
      try {
        saved = await promptSavePdfFromTemp(
          storage: storage,
          source: output,
          suggestedBaseName:
              '${p.basenameWithoutExtension(_file!.displayName)}-protected',
        );
      } finally {
        File(output.path).delete().ignore();
      }
      if (!mounted || saved == null) return;
      setState(() {
        _saved = saved;
        _savedPassword = userPassword;
      });
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

  Widget _formBody({required bool lockFile}) {
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
        DsToolSection(
          topPadding: false,
          title: 'Source file',
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
                  emptyTitle: 'Drop a PDF to encrypt',
                  emptySubtitle:
                      'Set an open password and choose what readers may do',
                  icon: Icons.lock_outline_rounded,
                ),
        ),
        DsToolSection(
          title: 'Passwords',
          child: Column(
            children: [
              TextField(
                key: const Key('protect_user_password'),
                controller: _userPasswordController,
                obscureText: !_showPasswords,
                decoration: InputDecoration(
                  labelText: 'Password to open',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _showPasswords ? 'Hide passwords' : 'Show passwords',
                    icon: Icon(
                      _showPasswords
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _showPasswords = !_showPasswords),
                  ),
                ),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: DsSpacing.lg),
              TextField(
                key: const Key('protect_confirm_password'),
                controller: _confirmPasswordController,
                obscureText: !_showPasswords,
                decoration: InputDecoration(
                  labelText: 'Confirm password',
                  border: const OutlineInputBorder(),
                  errorText: _confirmPasswordController.text.isNotEmpty &&
                          _confirmPasswordController.text !=
                              _userPasswordController.text
                      ? 'Passwords don’t match'
                      : null,
                ),
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: DsSpacing.lg),
              TextField(
                controller: _ownerPasswordController,
                obscureText: !_showPasswords,
                decoration: const InputDecoration(
                  labelText: 'Permissions password (optional)',
                  helperText: 'Needed to change the permissions below later. '
                      'Leave empty to lock them permanently.',
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
              const SizedBox(height: DsSpacing.lg),
              TextField(
                controller: _inputPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current PDF password (if already encrypted)',
                  border: OutlineInputBorder(),
                ),
                enabled: !_busy,
              ),
            ],
          ),
        ),
        DsToolSection(
          title: 'Permissions',
          subtitle: 'Applied when saving the encrypted copy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<ProtectPermissionPreset>(
                value: _preset,
                decoration: InputDecoration(
                  labelText: 'Preset',
                  helperText: _preset.subtitle,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final preset in ProtectPermissionPreset.values)
                    DropdownMenuItem(
                      value: preset,
                      enabled: preset != ProtectPermissionPreset.custom,
                      child: Text(preset.label),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (v) {
                        if (v != null) _applyPreset(v);
                      },
              ),
              const SizedBox(height: DsSpacing.lg),
              for (final row in [
                (
                  'Allow printing',
                  _allowPrinting,
                  (bool v) => _onPermissionToggle(
                        allowPrinting: v,
                        allowCopy: _allowCopy,
                        allowModify: _allowModify,
                        allowAnnotate: _allowAnnotate,
                      ),
                ),
                (
                  'Allow copying text',
                  _allowCopy,
                  (bool v) => _onPermissionToggle(
                        allowPrinting: _allowPrinting,
                        allowCopy: v,
                        allowModify: _allowModify,
                        allowAnnotate: _allowAnnotate,
                      ),
                ),
                (
                  'Allow modifying',
                  _allowModify,
                  (bool v) => _onPermissionToggle(
                        allowPrinting: _allowPrinting,
                        allowCopy: _allowCopy,
                        allowModify: v,
                        allowAnnotate: _allowAnnotate,
                      ),
                ),
                (
                  'Allow annotating',
                  _allowAnnotate,
                  (bool v) => _onPermissionToggle(
                        allowPrinting: _allowPrinting,
                        allowCopy: _allowCopy,
                        allowModify: _allowModify,
                        allowAnnotate: v,
                      ),
                ),
              ])
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(row.$1),
                    value: row.$2,
                    onChanged: _busy ? null : row.$3,
                  ),
                ),
            ],
          ),
        ),
        if (_error != null && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Could not encrypt this PDF',
              message: _error,
              tone: DsResultTone.error,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        if (_saved case final saved? when !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Encrypted PDF saved',
              message: 'Readers need the open password to view it.',
              file: saved,
              stats: [
                DsResultStat('Encryption', 'AES'),
                DsResultStat(
                  'Printing',
                  _allowPrinting ? 'Allowed' : 'Blocked',
                ),
                DsResultStat('Copying', _allowCopy ? 'Allowed' : 'Blocked'),
              ],
              onOpen: () =>
                  openToolResult(context, saved, password: _savedPassword),
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
        primaryLabel: 'Encrypt',
        primaryIcon: Icons.lock,
        primaryEnabled: _file != null && qpdf == true,
        primaryBusy: _busy,
        onPrimary: _run,
        children: [_formBody(lockFile: lockFile)],
      );
    }

    return DsToolPage(
      title: 'Encrypt',
      subtitle: 'Encrypt with a password and set permissions.',
      icon: Icons.lock_outline_rounded,
      iconColor: const Color(0xFF7C3AED),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => handleDsToolFormCancel(context, ref),
      ),
      primaryLabel: 'Encrypt & save as',
      primaryIcon: Icons.lock,
      primaryEnabled: _file != null && qpdf == true,
      primaryBusy: _busy,
      onPrimary: _run,
      onCancel: () => handleDsToolFormCancel(context, ref),
      busy: _busy,
      busyMessage: _busy ? 'Encrypting…' : null,
      footer: SecurityRelatedToolsPanel(
        compact: true,
        busy: _busy,
        excludePath: protectRoutePath,
        sourceFile: _file,
        sourcePassword: _inputPasswordController.text.isEmpty
            ? widget.initialPassword
            : _inputPasswordController.text,
      ),
      child: _formBody(lockFile: false),
    );
  }
}
