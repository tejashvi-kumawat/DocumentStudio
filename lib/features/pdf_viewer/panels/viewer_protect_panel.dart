import 'dart:async';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_encrypt_adapter.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Right-rail Encrypt: AES password and permissions on the open PDF.
class ViewerProtectPanel extends ConsumerStatefulWidget {
  const ViewerProtectPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerProtectPanel> createState() => _ViewerProtectPanelState();
}

class _ViewerProtectPanelState extends ConsumerState<ViewerProtectPanel> {
  final _userPassword = TextEditingController();
  final _ownerPassword = TextEditingController();
  bool _allowPrinting = true;
  bool _allowCopy = false;
  bool _allowModify = false;
  bool _allowAnnotate = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _userPassword.dispose();
    _ownerPassword.dispose();
    super.dispose();
  }

  String _errorText(Object e) {
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
      final detail = e.stderr.trim().isEmpty
          ? e.stdout.trim()
          : e.stderr.trim();
      return detail.isEmpty ? e.toString() : detail;
    }
    return '$e';
  }

  Future<void> _apply() async {
    final userPassword = _userPassword.text;
    if (userPassword.isEmpty) {
      setState(() => _error = 'Enter a password to encrypt the PDF.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deps = protectDepsFromRef(ref);
      final temp = await deps.fileStorage.createTempFile(
        prefix: 'protect',
        suffix: '.pdf',
      );
      final output = await deps.encryptPort.encryptWithPassword(
        input: widget.handoff.file,
        outputPath: temp,
        userPassword: userPassword,
        ownerPassword: _ownerPassword.text,
        inputPassword: widget.handoff.password,
        permissions: PdfEncryptPermissions(
          allowPrinting: _allowPrinting,
          allowModify: _allowModify,
          allowExtract: _allowCopy,
          allowAnnotate: _allowAnnotate,
        ),
      );
      if (!mounted) return;
      await commitTempPathToActiveSession(
        ref: ref,
        context: context,
        tempPath: output.path,
        successMessage: 'Encrypted this document.',
        configureSession: (session) {
          session.password = userPassword;
        },
      );
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _toggle({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      value: value,
      onChanged: _busy ? null : onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_protect_apply'),
      primaryLabel: _busy ? 'Encrypting…' : 'Encrypt',
      primaryIcon: Icons.lock_outline,
      primaryEnabled: !_busy,
      primaryBusy: _busy,
      onPrimary: () => unawaited(_apply()),
      notice: _error == null
          ? null
          : Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
      children: [
        ViewerToolFormSection(
          first: true,
          title: 'Passwords',
          subtitle:
              'Encrypts this open PDF. Save when you want to replace '
              'the original file. Readers need the open password. The owner '
              'password is only for changing permissions later.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('viewer_protect_user_password'),
                controller: _userPassword,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Password to open',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: DsSpacing.lg),
              TextField(
                controller: _ownerPassword,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Owner password (optional)',
                  helperText:
                      'Controls permission changes. It may differ from '
                      'the open password.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        ViewerToolFormSection(
          title: 'Permissions',
          subtitle: 'What a reader can do after the PDF opens.',
          child: Column(
            children: [
              _toggle(
                label: 'Allow printing',
                value: _allowPrinting,
                onChanged: (v) => setState(() => _allowPrinting = v),
              ),
              _toggle(
                label: 'Allow copying text',
                value: _allowCopy,
                onChanged: (v) => setState(() => _allowCopy = v),
              ),
              _toggle(
                label: 'Allow modifying',
                value: _allowModify,
                onChanged: (v) => setState(() => _allowModify = v),
              ),
              _toggle(
                label: 'Allow annotating',
                value: _allowAnnotate,
                onChanged: (v) => setState(() => _allowAnnotate = v),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
