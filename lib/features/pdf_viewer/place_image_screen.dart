import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_place_image_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/shell_pdf_open.dart';
import 'package:document_studio/features/pdf_viewer/viewer_tool_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const placeImageRoutePath = '/place-image';

/// Standalone place-image: choose a PDF, then the same viewer panel (and live
/// page tool when opened in the shell viewer).
class PlaceImageScreen extends ConsumerStatefulWidget {
  const PlaceImageScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.openInViewer = true,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;

  /// When true (default), after pick/handoff open the shell viewer with the
  /// place-image panel so drag-to-move works on the live page.
  final bool openInViewer;

  @override
  ConsumerState<PlaceImageScreen> createState() => _PlaceImageScreenState();
}

class _PlaceImageScreenState extends ConsumerState<PlaceImageScreen> {
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
      openToolPanel: ViewerToolId.placeImage,
    );
  }

  Future<void> _pickPdf() async {
    setState(() {
      _picking = true;
      _pickError = null;
    });
    try {
      final storage = ref.read(fileStorageProvider);
      final picked = await storage.pickOpenFile(allowedExtensions: ['pdf']);
      if (!mounted) return;
      if (picked == null) return;
      setState(() {
        _file = picked;
        _password = null;
      });
      if (widget.openInViewer) {
        _handoffToViewer();
      }
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
        appBar: DsToolbar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          title: 'Place image',
          subtitle: 'Insert an image onto a PDF page',
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
                    'Choose a PDF, then pick an image and drag it on the page.',
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
                    key: const Key('place_image_choose_pdf'),
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
          title: 'Place image',
          dense: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final handoff = PdfViewerDocumentHandoff(file: file, password: _password);
    return Scaffold(
      appBar: DsToolbar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: 'Place image',
        subtitle: file.displayName,
        dense: true,
      ),
      body: ViewerPlaceImagePanel(handoff: handoff),
    );
  }
}
