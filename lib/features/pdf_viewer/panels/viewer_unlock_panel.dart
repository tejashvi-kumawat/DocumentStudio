import 'dart:async';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Right-rail Decrypt: remove encryption from the open PDF.
class ViewerUnlockPanel extends ConsumerStatefulWidget {
  const ViewerUnlockPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerUnlockPanel> createState() => _ViewerUnlockPanelState();
}

class _ViewerUnlockPanelState extends ConsumerState<ViewerUnlockPanel> {
  late final TextEditingController _password;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _password = TextEditingController(text: widget.handoff.password ?? '');
  }

  @override
  void dispose() {
    _password.dispose();
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
      final detail =
          e.stderr.trim().isEmpty ? e.stdout.trim() : e.stderr.trim();
      return detail.isEmpty ? e.toString() : detail;
    }
    return '$e';
  }

  Future<void> _apply() async {
    final password = _password.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final deps = unlockDepsFromRef(ref);
      final temp = await deps.fileStorage.createTempFile(
        prefix: 'unlock',
        suffix: '.pdf',
      );
      await deps.encryptPort.decryptToFile(
        input: widget.handoff.file,
        outputPath: temp,
        password: password,
      );
      if (!mounted) return;
      await commitTempPathToActiveSession(
        ref: ref,
        context: context,
        tempPath: temp,
        successMessage: 'Decrypted this document.',
        configureSession: (session) {
          session.password = null;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ViewerToolFormScaffold(
      primaryKey: const Key('viewer_unlock_apply'),
      primaryLabel: _busy ? 'Decrypting…' : 'Decrypt',
      primaryIcon: Icons.lock_open_outlined,
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
          title: 'Current password',
          subtitle: 'Decrypts this open PDF. Save when you want to replace '
              'the original file. Leave this empty if the file opens without '
              'a password and only blocks printing or editing.',
          child: TextField(
            key: const Key('viewer_unlock_password'),
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) {
              if (!_busy) unawaited(_apply());
            },
          ),
        ),
      ],
    );
  }
}
