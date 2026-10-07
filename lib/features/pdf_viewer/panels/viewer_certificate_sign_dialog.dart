import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/pdf/machine_certificate_scanner.dart';
import 'package:document_studio/infrastructure/pdf/pdf_certificate_signer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pick a machine `.p12`/`.pfx` or NSS nickname, then sign the open PDF in place.
///
/// [signatureFieldName] targets an existing `/FT /Sig` widget.
/// [appearancePdfRect] (PDF user space llx/lly/urx/ury) is used only when no
/// field name is given — a Sig widget is injected there before pdfsig signs.
Future<bool?> showViewerCertificateSignDialog({
  required BuildContext context,
  required WidgetRef ref,
  required PdfViewerDocumentHandoff handoff,
  String? signatureFieldName,
  ({double llx, double lly, double urx, double ury})? appearancePdfRect,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _CertificateSignDialog(
      handoff: handoff,
      parentRef: ref,
      signatureFieldName: signatureFieldName,
      appearancePdfRect: appearancePdfRect,
    ),
  );
}

class _CertificateSignDialog extends ConsumerStatefulWidget {
  const _CertificateSignDialog({
    required this.handoff,
    required this.parentRef,
    this.signatureFieldName,
    this.appearancePdfRect,
  });

  final PdfViewerDocumentHandoff handoff;
  final WidgetRef parentRef;
  final String? signatureFieldName;
  final ({double llx, double lly, double urx, double ury})? appearancePdfRect;

  @override
  ConsumerState<_CertificateSignDialog> createState() =>
      _CertificateSignDialogState();
}

class _CertificateSignDialogState
    extends ConsumerState<_CertificateSignDialog> {
  final _passwordCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _scanner = MachineCertificateScanner();

  MachineCertificateSource? _selected;
  List<P12CertificateSource> _scannedP12 = const [];
  List<NssNicknameCertificateSource> _nssNicks = const [];
  String? _extraFolder;
  bool _scanning = true;
  bool _busy = false;
  String? _error;
  bool? _pkcs11Present;
  bool? _toolsAvailable;

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
    unawaited(_refreshSources());
  }

  Future<void> _probe() async {
    final signer = PdfCertificateSigner();
    final available = await signer.isAvailable();
    final pkcs11 = await signer.isPkcs11Available();
    if (mounted) {
      setState(() {
        _toolsAvailable = available;
        _pkcs11Present = pkcs11;
      });
    }
  }

  Future<void> _refreshSources() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final p12 = await _scanner.scanP12Files(extraFolder: _extraFolder);
      final nss = await _scanner.listNssNicknames();
      if (!mounted) return;
      setState(() {
        _scannedP12 = p12;
        _nssNicks = nss;
        _scanning = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _error = '$e';
      });
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickP12() async {
    final storage = widget.parentRef.read(fileStorageProvider);
    final picked = await storage.pickOpenFile(
      allowedExtensions: ['p12', 'pfx'],
    );
    if (picked == null) return;
    setState(() {
      _selected = P12CertificateSource(
        path: picked.path,
        displayName: picked.displayName,
      );
      _error = null;
    });
  }

  Future<void> _pickExtraFolder() async {
    final storage = widget.parentRef.read(fileStorageProvider);
    try {
      final folder = await storage.pickOutputDirectory(
        dialogTitle: 'Folder with .p12 / .pfx certificates',
      );
      if (folder == null) return;
      setState(() => _extraFolder = folder);
      await _refreshSources();
    } catch (_) {
      setState(() {
        _error = 'Folder picker is not available; choose a .p12 file instead, or place certificates in Documents/Downloads.';
      });
    }
  }

  Future<void> _sign() async {
    final source = _selected;
    if (source == null) {
      setState(() => _error = 'Choose a certificate file or NSS nickname.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await File(widget.handoff.file.path).readAsBytes();
      final signer = PdfCertificateSigner();
      late final PdfCertificateSignResult result;
      if (source is P12CertificateSource) {
        result = await signer.signWithP12(
          inputBytes: bytes,
          p12Path: source.path,
          password: _passwordCtrl.text,
          reason: _reasonCtrl.text,
          signatureFieldName: widget.signatureFieldName,
          appearancePdfRect: widget.appearancePdfRect,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      } else if (source is NssNicknameCertificateSource) {
        result = await signer.signWithNssNickname(
          inputBytes: bytes,
          nssDir: source.nssDir,
          nickname: source.nickname,
          nssPassword: _passwordCtrl.text,
          reason: _reasonCtrl.text,
          signatureFieldName: widget.signatureFieldName,
          appearancePdfRect: widget.appearancePdfRect,
          pageIndex1Based: widget.handoff.currentPage1,
        );
      } else {
        setState(() => _error = 'Unsupported certificate source.');
        return;
      }

      if (!result.verifiedByTool) {
        if (!mounted) return;
        // Do not badge as verified — show real pdfsig output and offer discard.
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Signature not verified'),
            content: SingleChildScrollView(
              child: Text(
                'The signed file contains a signature dictionary, but pdfsig '
                'did not report “Signature is Valid”.\n\n'
                '${result.verificationSummary}',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Discard'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Save anyway'),
              ),
            ],
          ),
        );
        if (proceed != true) {
          if (mounted) Navigator.pop(context, false);
          return;
        }
      }
      if (!mounted) return;
      final session = widget.parentRef
          .read(documentTabsControllerProvider)
          .activeSession;
      if (session == null) {
        setState(() => _error = 'No open document session.');
        return;
      }
      await commitBytesToSession(
        context: context,
        storage: widget.parentRef.read(fileStorageProvider),
        tabs: widget.parentRef.read(documentTabsControllerProvider),
        session: session,
        bytes: result.signedBytes,
        successMessage: result.verifiedByTool
            ? 'Certificate signature applied (pdfsig: Signature is Valid).'
            : 'Certificate signature written (not verified by pdfsig).',
      );
      if (mounted) Navigator.pop(context, true);
    } on DocumentStudioError catch (e) {
      if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Sign with certificate'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Uses a real PKCS#7 detached signature. A verified state is shown '
                'only when bundled pdfsig reports “Signature is Valid”. '
                'Certificates stay on this machine.',
                style: theme.textTheme.bodySmall,
              ),
              if (widget.signatureFieldName != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  'Signing field: ${widget.signatureFieldName}',
                  style: theme.textTheme.labelLarge,
                ),
              ] else if (widget.appearancePdfRect != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  'No /FT /Sig widget found — signing at the rectangle you placed '
                  'on the page.',
                  style: theme.textTheme.bodySmall,
                ),
              ] else ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  'No signature field or page rectangle — pdfsig will add a new '
                  'signature (appearance may be invisible). Place a box on the '
                  'page first for a visible field.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_toolsAvailable == false) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  'Signing tools were not found in the engines bundle. '
                  'Rebuild the desktop app (Linux: scripts/bundle_linux_engines.sh).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: DsSpacing.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _pickP12,
                icon: const Icon(Icons.upload_file, size: 18),
                label: Text(
                  _selected is P12CertificateSource &&
                          !(_selected as P12CertificateSource).fromScan
                      ? (_selected as P12CertificateSource).displayName
                      : 'Choose .p12 / .pfx…',
                ),
              ),
              const SizedBox(height: DsSpacing.sm),
              OutlinedButton.icon(
                onPressed: _busy || _scanning ? null : _pickExtraFolder,
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(
                  _extraFolder == null
                      ? 'Scan another folder…'
                      : 'Rescan: $_extraFolder',
                ),
              ),
              const SizedBox(height: DsSpacing.md),
              if (_scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else ...[
                Text('On this machine', style: theme.textTheme.titleSmall),
                const SizedBox(height: DsSpacing.xs),
                if (_scannedP12.isEmpty && _nssNicks.isEmpty)
                  Text(
                    'No .p12/.pfx in Documents, Downloads, or ~/.pki, '
                    'and no NSS nicknames found.',
                    style: theme.textTheme.bodySmall,
                  ),
                if (_scannedP12.isNotEmpty) ...[
                  Text('Certificate files', style: theme.textTheme.labelLarge),
                  ..._scannedP12.map((c) {
                    final selected =
                        _selected is P12CertificateSource &&
                        (_selected as P12CertificateSource).path == c.path;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                      ),
                      title: Text(
                        c.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        c.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _selected = c;
                              _error = null;
                            }),
                    );
                  }),
                ],
                if (_nssNicks.isNotEmpty) ...[
                  const SizedBox(height: DsSpacing.sm),
                  Text('NSS certificates', style: theme.textTheme.labelLarge),
                  ..._nssNicks.map((c) {
                    final selected =
                        _selected is NssNicknameCertificateSource &&
                        (_selected as NssNicknameCertificateSource).nickname ==
                            c.nickname &&
                        (_selected as NssNicknameCertificateSource).nssDir ==
                            c.nssDir;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: Icon(
                        selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                      ),
                      title: Text(c.nickname, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        c.dbLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: _busy
                          ? null
                          : () => setState(() {
                              _selected = c;
                              _error = null;
                            }),
                    );
                  }),
                ],
              ],
              const SizedBox(height: DsSpacing.sm),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: _selected is NssNicknameCertificateSource
                      ? 'NSS / key password'
                      : 'Certificate password',
                ),
              ),
              const SizedBox(height: DsSpacing.sm),
              TextField(
                controller: _reasonCtrl,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
              if (_pkcs11Present == true) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  'A PKCS#11 tool is available. USB token signing is only used '
                  'when a token is already configured in NSS — otherwise export '
                  'a .p12 from the token.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: DsSpacing.sm),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        DsPrimaryButton(
          label: _busy ? 'Signing…' : 'Sign',
          onPressed: _busy || _toolsAvailable == false ? null : _sign,
        ),
      ],
    );
  }
}
