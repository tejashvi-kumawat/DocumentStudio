import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Page-by-page preview of a PDF that fills the space it is given, with a
/// small stepper underneath. Used as the right-hand pane of tool pages.
///
/// A password-protected file shows a "locked" state with an Unlock button
/// ([onUnlock]) instead of an error.
class DsPdfPreview extends StatefulWidget {
  const DsPdfPreview({
    super.key,
    required this.file,
    this.password,
    this.onUnlock,
  });

  final LocalFileRef file;
  final String? password;
  final VoidCallback? onUnlock;

  @override
  State<DsPdfPreview> createState() => _DsPdfPreviewState();
}

class _DsPdfPreviewState extends State<DsPdfPreview> {
  late PdfDocumentRefFile _ref = _makeRef();
  int _page = 1;

  PdfDocumentRefFile _makeRef() {
    final pw = widget.password;
    return PdfDocumentRefFile(
      widget.file.path,
      passwordProvider: pw == null ? null : () async => pw,
    );
  }

  @override
  void didUpdateWidget(DsPdfPreview old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path || old.password != widget.password) {
      _ref = _makeRef();
      if (old.file.path != widget.file.path) _page = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return PdfDocumentViewBuilder(
      documentRef: _ref,
      loadingBuilder: (_) =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      errorBuilder: (_, e, _) => _message(
        context,
        locked: e is PdfPasswordException,
        text: e is PdfPasswordException
            ? 'This PDF is password-protected'
            : 'Preview unavailable',
      ),
      builder: (context, document) {
        if (document == null || document.pages.isEmpty)
          return const SizedBox.shrink();
        final count = document.pages.length;
        final page = _page.clamp(1, count);
        final pg = document.pages[page - 1];
        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(DsSpacing.xl),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: pg.width / math.max(pg.height, 1),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: DsSpacing.cardShadowLight(opacity: 0.14),
                      ),
                      child: PdfPageView(
                        key: ValueKey('${widget.file.path}#$page'),
                        document: document,
                        pageNumber: page,
                        maximumDpi: 150,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: DsSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: page > 1
                        ? () => setState(() => _page = page - 1)
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Text(
                    'Page $page of $count',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: DsColors.textSecondary(b),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: page < count
                        ? () => setState(() => _page = page + 1)
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _message(
    BuildContext context, {
    required bool locked,
    required String text,
  }) {
    final theme = Theme.of(context);
    final b = theme.brightness;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? Icons.lock_outline_rounded : Icons.visibility_off_outlined,
            size: 40,
            color: DsColors.textSecondary(b),
          ),
          const SizedBox(height: DsSpacing.md),
          Text(text, style: theme.textTheme.titleSmall),
          if (locked && widget.onUnlock != null) ...[
            const SizedBox(height: DsSpacing.md),
            FilledButton.tonalIcon(
              onPressed: widget.onUnlock,
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Enter password'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The preview pane of a single-PDF tool page: a large drop zone until a file
/// is chosen, then the file's pages. Pass it as `DsToolPage.preview`.
class DsPdfPreviewPane extends StatelessWidget {
  const DsPdfPreviewPane({
    super.key,
    required this.file,
    required this.onPick,
    required this.onFilesDropped,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.icon = Icons.upload_file_rounded,
    this.password,
    this.onUnlock,
    this.enabled = true,
  });

  final LocalFileRef? file;
  final VoidCallback onPick;
  final ValueChanged<List<LocalFileRef>> onFilesDropped;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData icon;
  final String? password;
  final VoidCallback? onUnlock;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final f = file;
    if (f != null)
      return DsPdfPreview(file: f, password: password, onUnlock: onUnlock);
    return DsDropPane(
      enabled: enabled,
      onPick: onPick,
      onFilesDropped: onFilesDropped,
      emptyTitle: emptyTitle,
      emptySubtitle: emptySubtitle,
      icon: icon,
    );
  }
}

/// The empty state of a preview pane: one large drop zone, centred.
class DsDropPane extends StatelessWidget {
  const DsDropPane({
    super.key,
    required this.onPick,
    required this.onFilesDropped,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.icon = Icons.upload_file_rounded,
    this.enabled = true,
    this.loading = false,
    this.allowedExtensions = const ['pdf'],
    this.multiple = false,
    this.pickLabel,
  });

  final VoidCallback onPick;
  final ValueChanged<List<LocalFileRef>> onFilesDropped;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData icon;
  final bool enabled;
  final bool loading;
  final List<String> allowedExtensions;
  final bool multiple;
  final String? pickLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => Padding(
        padding: EdgeInsets.all(
          c.maxHeight < 420 ? DsSpacing.sm : DsSpacing.xxl,
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DsToolFileSource(
                files: const [],
                enabled: enabled,
                loading: loading,
                allowedExtensions: allowedExtensions,
                multiple: multiple,
                pickLabel: pickLabel,
                onPick: onPick,
                onFilesDropped: onFilesDropped,
                emptyTitle: emptyTitle,
                emptySubtitle: emptySubtitle,
                icon: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A picture that fills its pane (contained, pinch/scroll to zoom).
class DsImagePreview extends StatelessWidget {
  const DsImagePreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DsSpacing.xl),
      child: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: DsSpacing.cardShadowLight(opacity: 0.14),
            ),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, _, _) =>
                  const Text('Preview not available for this format.'),
            ),
          ),
        ),
      ),
    );
  }
}
