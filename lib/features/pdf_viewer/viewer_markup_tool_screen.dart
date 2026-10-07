import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_edit_text_panel.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_ink_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_document_route_args.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const editTextRoutePath = '/edit-text';
const drawInkRoutePath = '/draw';

/// Shared chooser → shell viewer (or embedded panel) for page markup tools.
class ViewerMarkupToolScreen extends ConsumerStatefulWidget {
  const ViewerMarkupToolScreen({
    super.key,
    required this.tool,
    required this.title,
    required this.subtitle,
    required this.chooseHint,
    this.initialFile,
    this.initialPassword,
    this.openInViewer = true,
    this.chooseKey,
  });

  final ViewerToolId tool;
  final String title;
  final String subtitle;
  final String chooseHint;
  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool openInViewer;
  final Key? chooseKey;

  @override
  ConsumerState<ViewerMarkupToolScreen> createState() =>
      _ViewerMarkupToolScreenState();
}

class _ViewerMarkupToolScreenState
    extends ConsumerState<ViewerMarkupToolScreen> {
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
      openToolPanel: widget.tool,
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

  Widget _embeddedPanel(LocalFileRef file) {
    final handoff = PdfViewerDocumentHandoff(file: file, password: _password);
    return switch (widget.tool) {
      ViewerToolId.editText => ViewerEditTextPanel(handoff: handoff),
      ViewerToolId.ink => ViewerInkPanel(handoff: handoff),
      _ => Center(child: Text('Unsupported tool ${widget.tool}')),
    };
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) {
      return Scaffold(
        appBar: DsToolbar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: widget.title,
          subtitle: widget.subtitle,
          dense: true,
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
                    widget.chooseHint,
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
                    key:
                        widget.chooseKey ?? const Key('markup_tool_choose_pdf'),
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
        appBar: DsToolbar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: widget.title,
          dense: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: DsToolbar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: widget.title,
        subtitle: file.displayName,
        dense: true,
      ),
      body: _embeddedPanel(file),
    );
  }
}

ViewerMarkupToolScreen editTextScreenFromExtra(Object? extra) {
  final args = PdfDocumentRouteArgs.tryParse(extra);
  return ViewerMarkupToolScreen(
    tool: ViewerToolId.editText,
    title: 'Add text',
    subtitle: 'Drag to set width, then type',
    chooseHint: 'Choose a PDF to add or edit text on the page.',
    chooseKey: const Key('edit_text_choose_pdf'),
    initialFile: args?.file,
    initialPassword: args?.password,
  );
}

ViewerMarkupToolScreen drawInkScreenFromExtra(Object? extra) {
  final args = PdfDocumentRouteArgs.tryParse(extra);
  return ViewerMarkupToolScreen(
    tool: ViewerToolId.ink,
    title: 'Draw',
    subtitle: 'Ink strokes on the page',
    chooseHint: 'Choose a PDF to draw ink on the page.',
    chooseKey: const Key('draw_ink_choose_pdf'),
    initialFile: args?.file,
    initialPassword: args?.password,
  );
}
