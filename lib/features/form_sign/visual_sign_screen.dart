import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/errors/document_studio_error_ui.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_shell_page.dart';
import 'package:document_studio/design_system/shell/ds_toolbar.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_visual_sign_panel.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Visual (non-cryptographic) signature on one page ([DS-SIG-001]).
class VisualSignScreen extends ConsumerStatefulWidget {
  const VisualSignScreen({
    super.key,
    this.initialFile,
    this.initialPassword,
    this.initialPage1 = 1,
  });

  final LocalFileRef? initialFile;
  final String? initialPassword;
  final int initialPage1;

  @override
  ConsumerState<VisualSignScreen> createState() => _VisualSignScreenState();
}

class _VisualSignScreenState extends ConsumerState<VisualSignScreen> {
  LocalFileRef? _file;
  String? _password;
  bool _picking = false;
  String? _pickError;

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    _password = widget.initialPassword;
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
          title: 'Sign PDF',
          subtitle: 'Add a visual signature',
          dense: true,
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: dsUseCompactToolLayout(context)
                    ? double.infinity
                    : DsSpacing.formMaxWidth,
              ),
              child: Padding(
                padding: const EdgeInsets.all(DsSpacing.pagePaddingCompact),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a PDF to place a visual signature.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    if (_pickError != null) ...[
                      const SizedBox(height: DsSpacing.md),
                      Text(
                        _pickError!,
                        textAlign: TextAlign.center,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFFE4002B),
                            ),
                      ),
                    ],
                    const SizedBox(height: DsSpacing.lg),
                    Theme(
                      data: Theme.of(context).copyWith(
                        filledButtonTheme: FilledButtonThemeData(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(
                              double.infinity,
                              DsSpacing.controlHeightComfortable,
                            ),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                      child: DsPrimaryButton(
                        label: _picking ? 'Opening…' : 'Choose PDF…',
                        icon: Icons.folder_open_outlined,
                        onPressed: _picking ? null : _pickPdf,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final handoff = PdfViewerDocumentHandoff(
      file: file,
      password: _password,
      currentPage1: widget.initialPage1,
    );

    return Scaffold(
      appBar: DsToolbar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: 'Sign PDF',
        subtitle: 'Visual signature — not cryptographic',
        dense: dsUseCompactToolLayout(context),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: dsUseCompactToolLayout(context)
                  ? double.infinity
                  : DsSpacing.formMaxWidth,
            ),
            child: ViewerVisualSignPanel(handoff: handoff),
          ),
        ),
      ),
    );
  }
}
