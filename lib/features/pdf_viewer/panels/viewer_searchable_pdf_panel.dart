import 'dart:async';
import 'dart:typed_data';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/ocr/ocr_errors.dart';
import 'package:document_studio/features/ocr/ocr_tool_widgets.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_scope.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/widgets/pdf_page_scope_field.dart';
import 'package:document_studio/infrastructure/ocr/android_searchable_pdf_service.dart';
import 'package:document_studio/infrastructure/ocr/ocr_engine_environment.dart';
import 'package:document_studio/infrastructure/ocr/ocr_port.dart';
import 'package:document_studio/infrastructure/ocr/ocr_providers.dart';
import 'package:document_studio/infrastructure/ocr/tesseract_searchable_pdf_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// OCR the open document into an invisible text layer and commit in place.
class ViewerSearchablePdfPanel extends ConsumerStatefulWidget {
  const ViewerSearchablePdfPanel({
    super.key,
    required this.handoff,
    this.pageCount,
    this.selectedPages1Based = const {},
  });

  final PdfViewerDocumentHandoff handoff;
  final int? pageCount;
  final Set<int> selectedPages1Based;

  @override
  ConsumerState<ViewerSearchablePdfPanel> createState() =>
      _ViewerSearchablePdfPanelState();
}

class _ViewerSearchablePdfPanelState
    extends ConsumerState<ViewerSearchablePdfPanel> {
  PdfPageScopeKind _scopeKind = PdfPageScopeKind.allPages;
  String _rangeExpression = '';
  String? _rangeError;
  OcrOptions _options = const OcrOptions();
  bool _busy = false;
  String? _progress;
  double? _fraction;
  OcrCancelToken? _token;
  SearchablePdfEngineStatus? _engine;
  String? _engineError;

  @override
  void dispose() {
    _token?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    final port = ref.read(searchablePdfPortProvider);
    if (port is BlockedSearchablePdfPort) {
      if (mounted) {
        setState(() {
          _engineError = port.reason;
          _engine = null;
        });
      }
      return;
    }
    try {
      final SearchablePdfEngineStatus status;
      if (port is TesseractSearchablePdfService) {
        status = await port.probeEngine(language: _options.language);
      } else if (port is AndroidSearchablePdfService) {
        status = await port.probeEngine(language: _options.language);
      } else {
        // Alternate / test ports skip binary probe and stay ready.
        if (mounted) {
          setState(() {
            _engine = const SearchablePdfEngineStatus(
              tesseractPath: 'injected',
              tessdataPrefix: 'injected',
              missingMessage: null,
            );
            _engineError = null;
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _engine = status;
        _engineError = status.missingMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _engineError = '$e');
    }
  }

  Set<int>? _resolvePages() {
    final total = widget.pageCount;
    if (total == null || total < 1) {
      _snack('Page count not ready yet.');
      return null;
    }
    final resolved = resolvePdfPageScope(
      kind: _scopeKind,
      currentPage1: widget.handoff.currentPage1,
      selectedPages1Based: widget.selectedPages1Based,
      totalPages: total,
      rangeExpression: _rangeExpression,
    );
    if (!resolved.isOk) {
      setState(() => _rangeError = resolved.error);
      return null;
    }
    setState(() => _rangeError = null);
    return resolved.pages;
  }

  Future<void> _apply() async {
    final pages = _resolvePages();
    if (pages == null || pages.isEmpty) return;
    if (_engineError != null) {
      _snack(_engineHelper(_engineError));
      return;
    }

    final token = OcrCancelToken();
    setState(() {
      _busy = true;
      _progress = 'Starting…';
      _fraction = null;
      _token = token;
    });
    try {
      final port = ref.read(searchablePdfPortProvider);
      final Uint8List bytes;
      if (port is TesseractSearchablePdfService ||
          port is AndroidSearchablePdfService) {
        final result = port is TesseractSearchablePdfService
            ? await port.makeSearchable(
                file: widget.handoff.file,
                password: widget.handoff.password,
                options: _options,
                pages1Based: pages,
                cancelToken: token,
                onProgress: (prog) {
                  if (mounted) {
                    setState(() {
                      _progress = prog.message;
                      _fraction = prog.fraction;
                    });
                  }
                },
              )
            : await (port as AndroidSearchablePdfService).makeSearchable(
                file: widget.handoff.file,
                password: widget.handoff.password,
                options: _options,
                pages1Based: pages,
                cancelToken: token,
                onProgress: (prog) {
                  if (mounted) {
                    setState(() {
                      _progress = prog.message;
                      _fraction = prog.fraction;
                    });
                  }
                },
              );
        if (result.unchanged) {
          _snack('These pages already contain text — nothing to recognize.');
          return;
        }
        bytes = result.bytes;
      } else {
        final input =
            await ref.read(fileStorageProvider).readBytes(widget.handoff.file);
        bytes = await port.createSearchablePdf(input, options: _options);
      }
      if (!mounted) return;
      final session = ref.read(documentTabsControllerProvider).activeSession;
      if (session != null && session.sameDocumentPath(widget.handoff.file.path)) {
        await commitBytesToSession(
          context: context,
          storage: ref.read(fileStorageProvider),
          tabs: ref.read(documentTabsControllerProvider),
          session: session,
          bytes: bytes,
          successMessage: 'Searchable text layer added.',
        );
      } else {
        await commitOrganizeExport(
          ref: ref,
          context: context,
          bytes: bytes,
          successMessage: 'Searchable text layer added.',
          suggestedName: 'searchable-${widget.handoff.file.displayName}',
        );
      }
    } on OcrCancelledException {
      if (mounted) _snack('OCR cancelled. The document was not changed.');
    } catch (e) {
      if (!mounted) return;
      final mapped = mapOcrException(e);
      _snack(
        shortToolHelper(
          mapped.recoveryHint ?? mapped.message,
          fallback: 'Couldn’t make this PDF searchable.',
        ),
      );
    } finally {
      _token = null;
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _fraction = null;
        });
      }
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _engineHelper(String? raw) {
    return shortToolHelper(
      raw,
      fallback: 'Searchable PDF isn’t ready on this device yet.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    final ready = _engineError == null && _engine != null;

    return ViewerToolFormBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Adds a hidden text layer so Find and copy work on scanned pages. '
            'The page pictures stay as they are.',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
              color: secondary,
            ),
          ),
          if (_engineError != null) ...[
            const SizedBox(height: DsSpacing.md),
            Text(
              _engineHelper(_engineError),
              key: const Key('viewer_searchable_pdf_engine_error'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: DsSpacing.md),
          PdfPageScopeField(
            kind: _scopeKind,
            onKindChanged: (k) => setState(() => _scopeKind = k),
            rangeExpression: _rangeExpression,
            onRangeExpressionChanged: (v) =>
                setState(() => _rangeExpression = v),
            selectedPageCount: widget.selectedPages1Based.length,
            rangeError: _rangeError,
          ),
          const SizedBox(height: DsSpacing.md),
          OcrOptionsPanel(
            options: _options,
            busy: _busy,
            searchablePdf: true,
            onChanged: (o) {
              final langChanged = o.language != _options.language;
              setState(() => _options = o);
              if (langChanged) unawaited(_probe());
            },
          ),
          if (_busy) ...[
            const SizedBox(height: DsSpacing.md),
            OcrProgressCard(
              fraction: _fraction,
              message: _progress ?? 'Starting…',
              cancelling: _token?.isCancelled ?? false,
              onCancel: () => setState(() => _token?.cancel()),
            ),
          ],
          const SizedBox(height: DsSpacing.md),
          ViewerToolPrimaryButton(
            key: const Key('viewer_searchable_pdf_apply'),
            onPressed: ready && !_busy ? _apply : null,
            icon: Icons.find_in_page_outlined,
            label: _busy ? 'Working…' : 'Make searchable',
          ),
        ],
      ),
    );
  }
}
