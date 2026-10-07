import 'package:document_studio/design_system/shell/ds_tool_chrome.dart';
import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_fill_form_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fill AcroForm / detected spots — same panel as the open-PDF rail.
class FillFormScreen extends ConsumerStatefulWidget {
  const FillFormScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.openInViewer = true,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool openInViewer;

  @override
  ConsumerState<FillFormScreen> createState() => _FillFormScreenState();
}

class _FillFormScreenState extends ConsumerState<FillFormScreen> {
  LocalFileRef? _file;
  String? _password;
  bool _picking = false;
  String? _pickError;
  bool _openedViewer = false;

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    _password = widget.initialPassword;
    if (_file != null && widget.openInViewer) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handoffToViewer());
    }
  }

  Future<void> _handoffToViewer() async {
    final file = _file;
    if (file == null || _openedViewer || !mounted) return;
    _openedViewer = true;
    await openPdfInShellViewer(
      context,
      ref,
      file,
      password: _password,
      openToolPanel: ViewerToolId.fillForm,
    );
  }

  Future<void> _pickPdf() async {
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final picked = await ref
          .read(fileStorageProvider)
          .pickOpenFile(allowedExtensions: ['pdf']);
      if (!mounted || picked == null) return;
      setState(() {
        _file = picked;
        _password = null;
      });
      if (widget.openInViewer) _handoffToViewer();
    } on DocumentStudioError catch (e) {
      if (!mounted) return;
      setState(() => _pickError = e.userFacingMessage);
      showDocumentStudioErrorSnackBar(context, e);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) {
      return Scaffold(
        appBar: const DsToolAppBar(
          title: 'Fill PDF form',
          subtitle: 'Tap detected fields on the page',
          icon: Icons.assignment_outlined,
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(DsSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose a PDF to fill detected form fields on the page.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_pickError != null) ...[
                    const SizedBox(height: DsSpacing.md),
                    Text(
                      _pickError!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: const Color(0xFFE4002B)),
                    ),
                  ],
                  const SizedBox(height: DsSpacing.lg),
                  DsPrimaryButton(
                    key: const Key('fill_form_choose_pdf'),
                    label: _picking ? 'Opening…' : 'Choose PDF…',
                    icon: Icons.folder_open_outlined,
                    onPressed: _picking ? null : _pickPdf,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (widget.openInViewer) {
      return Scaffold(
        appBar: const DsToolAppBar(
          title: 'Fill PDF form',
          icon: Icons.assignment_outlined,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: DsToolAppBar(
        title: 'Fill PDF form',
        subtitle: file.displayName,
        icon: Icons.assignment_outlined,
      ),
      body: ViewerFillFormPanel(
        handoff: PdfViewerDocumentHandoff(file: file, password: _password),
      ),
    );
  }
}

/// Parses route extras for [FillFormScreen].
FillFormScreen fillFormScreenFromExtra(Object? extra) {
  final args = PdfDocumentRouteArgs.tryParse(extra);
  return FillFormScreen(
    initialFile: args?.file,
    initialPassword: args?.password,
  );
}
