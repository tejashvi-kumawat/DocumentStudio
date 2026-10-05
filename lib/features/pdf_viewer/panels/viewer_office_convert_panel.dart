import 'package:document_studio/features/conversion/pdf_to_docx_layout.dart';
import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/design_system/ds_colors.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_scaffold.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_document_actions.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/infrastructure/conversion/dart_office_convert_service.dart';
import 'package:document_studio/infrastructure/conversion/libreoffice_headless.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

enum _OfficeTarget { docx, xlsx, pptx }

/// LibreOffice `soffice --headless` on desktop; Dart plain-text path on Android.
class ViewerOfficeConvertPanel extends ConsumerStatefulWidget {
  const ViewerOfficeConvertPanel({super.key, required this.handoff});

  final PdfViewerDocumentHandoff handoff;

  @override
  ConsumerState<ViewerOfficeConvertPanel> createState() =>
      _ViewerOfficeConvertPanelState();
}

class _ViewerOfficeConvertPanelState
    extends ConsumerState<ViewerOfficeConvertPanel> {
  bool _busy = false;
  String? _enginePath;
  bool _engineChecked = false;
  _OfficeTarget _target = _OfficeTarget.docx;
  String? _progress;
  String? _error;
  double? _fraction;

  bool get _useDartPath =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    unawaited(_probe());
  }

  Future<void> _probe() async {
    if (_useDartPath) {
      if (mounted) {
        setState(() {
          _enginePath = 'dart';
          _engineChecked = true;
        });
      }
      return;
    }
    final path = await desktopEngineResolver.resolveSoffice();
    // Start LibreOffice's first-run work now so the conversion itself is quick.
    if (path != null) unawaited(LibreOfficeHeadless.prewarm(path));
    if (mounted) {
      setState(() {
        _enginePath = path;
        _engineChecked = true;
      });
    }
  }

  Future<void> _pdfToOffice() async {
    // Word: the on-device layout converter keeps fonts, sizes, colours,
    // pictures and page breaks better (and faster) than LibreOffice's PDF
    // import, which turns every line into a floating text box.
    if (_useDartPath || _target == _OfficeTarget.docx) {
      await _pdfToOfficeDart();
      return;
    }
    final exe = _enginePath;
    if (exe == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Starting LibreOffice…';
      _fraction = 0.1;
    });
    Directory? workDir;
    try {
      final storage = ref.read(fileStorageProvider);
      final ext = switch (_target) {
        _OfficeTarget.docx => 'docx',
        _OfficeTarget.xlsx => 'xlsx',
        _OfficeTarget.pptx => 'pptx',
      };
      workDir = await LibreOfficeHeadless.createWorkDir();
      final outDir = workDir.path;
      final localIn = p.join(
        outDir,
        'in-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      await File(widget.handoff.file.path).copy(localIn);
      setState(() {
        _progress = 'Converting to .$ext…';
        _fraction = 0.45;
      });
      final outFile = await LibreOfficeHeadless.convertPdf(
        exe: exe,
        pdfPath: localIn,
        target: ext,
        outDir: outDir,
      );
      setState(() {
        _progress = 'Saving…';
        _fraction = 0.85;
      });
      final bytes = await outFile.readAsBytes();
      final saveStem =
          p.basenameWithoutExtension(widget.handoff.file.displayName);
      final savePath = await storage.pickSavePath(
        suggestedName: '$saveStem.$ext',
        bytes: bytes,
        allowedExtensions: [ext],
      );
      if (savePath == null) {
        setState(() {
          _progress = null;
          _fraction = null;
        });
        return;
      }
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      setState(() {
        _progress = 'Done';
        _fraction = 1;
      });
      showDocumentSaveResultActions(
        context,
        file: LocalFileRef(path: savePath, displayName: p.basename(savePath)),
        message: 'Converted to ${p.basename(savePath)}',
        showOpenInViewer: false,
      );
    } on TimeoutException catch (e) {
      _fail(e, stderr: e.message);
    } catch (e) {
      _fail(e);
    } finally {
      LibreOfficeHeadless.deleteQuietly(workDir);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _fraction = null;
        });
      }
    }
  }

  Future<void> _pdfToOfficeDart() async {
    if (_target != _OfficeTarget.docx) {
      setState(() {
        _error =
            'On this device, PDF converts to Word (.docx) only. '
            'Excel and PowerPoint need the desktop app.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Reading the PDF…';
      _fraction = 0.1;
    });
    try {
      final storage = ref.read(fileStorageProvider);
      final bytes = await pdfToDocxWithLayout(
        file: widget.handoff.file,
        password: widget.handoff.password,
        onProgress: (f, msg) {
          if (mounted) {
            setState(() {
              _fraction = f;
              _progress = msg;
            });
          }
        },
      );
      final saveStem =
          p.basenameWithoutExtension(widget.handoff.file.displayName);
      final savePath = await storage.pickSavePath(
        suggestedName: '$saveStem.docx',
        bytes: bytes,
        allowedExtensions: const ['docx'],
      );
      if (savePath == null) return;
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      showDocumentSaveResultActions(
        context,
        file: LocalFileRef(path: savePath, displayName: p.basename(savePath)),
        message: 'Converted to ${p.basename(savePath)}',
        showOpenInViewer: false,
      );
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _fraction = null;
        });
      }
    }
  }

  Future<void> _officeToPdf() async {
    if (_useDartPath) {
      await _officeToPdfDart();
      return;
    }
    final exe = _enginePath;
    if (exe == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Choose a file…';
      _fraction = 0.05;
    });
    Directory? workDir;
    try {
      final storage = ref.read(fileStorageProvider);
      final picked = await storage.pickOpenFile(
        allowedExtensions: const [
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'odt',
          'ods',
          'odp',
        ],
      );
      if (picked == null) return;
      workDir = await LibreOfficeHeadless.createWorkDir();
      final outDir = workDir.path;
      setState(() {
        _progress = 'Converting to PDF…';
        _fraction = 0.45;
      });
      final result = await LibreOfficeHeadless.run(
        exe: exe,
        workDir: outDir,
        args: [
          '--convert-to',
          'pdf',
          '--outdir',
          outDir,
          picked.path,
        ],
      );
      if (result.exitCode != 0) {
        throw StateError(
          LibreOfficeHeadless.formatConvertError(
            'LibreOffice convert failed (exit ${result.exitCode})',
            stderr: result.stderr.toString(),
            exitCode: result.exitCode,
          ),
        );
      }
      final stem = p.basenameWithoutExtension(picked.path);
      final produced = await LibreOfficeHeadless.findProduced(outDir, stem, 'pdf');
      if (produced == null) {
        throw StateError(
          LibreOfficeHeadless.formatConvertError(
            'LibreOffice did not produce $stem.pdf.',
            stderr: result.stderr.toString(),
          ),
        );
      }
      setState(() {
        _progress = 'Saving…';
        _fraction = 0.85;
      });
      final bytes = await produced.readAsBytes();
      final savePath = await storage.pickSavePath(
        suggestedName: '$stem.pdf',
        bytes: bytes,
        allowedExtensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (savePath == null) return;
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      final out = LocalFileRef(
        path: savePath,
        displayName: p.basename(savePath),
      );
      showDocumentSaveResultActions(
        context,
        file: out,
        message: 'Created ${out.displayName}',
      );
      ref.read(documentTabsControllerProvider).openDocument(out);
    } on TimeoutException catch (e) {
      _fail(e, stderr: e.message);
    } catch (e) {
      _fail(e);
    } finally {
      LibreOfficeHeadless.deleteQuietly(workDir);
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _fraction = null;
        });
      }
    }
  }

  Future<void> _officeToPdfDart() async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Choose a file…';
      _fraction = 0.05;
    });
    try {
      final storage = ref.read(fileStorageProvider);
      final picked = await storage.pickOpenFile(
        allowedExtensions: DartOfficeConvertService.officeToPdfExtensions,
      );
      if (picked == null) return;
      final converter = DartOfficeConvertService();
      final bytes = await converter.officeToPdf(
        inputPath: picked.path,
        onProgress: (f, msg) {
          if (mounted) {
            setState(() {
              _fraction = f;
              _progress = msg;
            });
          }
        },
      );
      final stem = p.basenameWithoutExtension(picked.path);
      final savePath = await storage.pickSavePath(
        suggestedName: '$stem.pdf',
        bytes: bytes,
        allowedExtensions: const ['pdf'],
        mimeType: 'application/pdf',
      );
      if (savePath == null) return;
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      final out = LocalFileRef(
        path: savePath,
        displayName: p.basename(savePath),
      );
      showDocumentSaveResultActions(
        context,
        file: out,
        message: 'Created ${out.displayName} (plain text)',
      );
      ref.read(documentTabsControllerProvider).openDocument(out);
    } catch (e) {
      _fail(e);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
          _fraction = null;
        });
      }
    }
  }

  void _fail(Object error, {String? stderr}) {
    if (!mounted) return;
    setState(() {
      _error = shortToolHelper(
        LibreOfficeHeadless.formatConvertError(error, stderr: stderr),
        fallback: 'Couldn’t convert this file. Try again.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = DsColors.textSecondary(theme.brightness);
    if (!_engineChecked) {
      return const Padding(
        padding: EdgeInsets.all(DsSpacing.pagePaddingCompact),
        child: LinearProgressIndicator(),
      );
    }
    final ready = _enginePath != null;
    final helper = _useDartPath
        ? '${DartOfficeConvertService.fidelityNote} '
            'Excel, PowerPoint, .doc, and OpenDocument need the desktop app.'
        : ready
            ? 'Word, Excel, and PowerPoint convert on this computer.'
            : 'Office conversion isn’t set up on this computer yet.';
    return ViewerToolFormScaffold(
      primaryLabel: _busy ? 'Converting…' : 'Convert',
      primaryIcon: Icons.description_outlined,
      primaryEnabled: !_busy && ready,
      primaryBusy: _busy,
      onPrimary: _busy || !ready ? null : () => unawaited(_pdfToOffice()),
      notice: _error == null
          ? null
          : Text(
              _error!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: DsColors.error,
                fontSize: 12,
              ),
            ),
      children: [
          Text(
            helper,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: secondary,
            ),
          ),
          const SizedBox(height: DsSpacing.sm),
          Text(
            'PDF to Office',
            style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.sm),
          DropdownButtonFormField<_OfficeTarget>(
            initialValue: _target,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Format',
              labelStyle: TextStyle(fontSize: 13),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: _OfficeTarget.docx,
                child: Text('Word (.docx)'),
              ),
              if (!_useDartPath) ...const [
                DropdownMenuItem(
                  value: _OfficeTarget.xlsx,
                  child: Text('Excel (.xlsx)'),
                ),
                DropdownMenuItem(
                  value: _OfficeTarget.pptx,
                  child: Text('PowerPoint (.pptx)'),
                ),
              ],
            ],
            onChanged: _busy || !ready
                ? null
                : (v) {
                    if (v != null) setState(() => _target = v);
                  },
          ),
          const SizedBox(height: DsSpacing.sm),
          Text(
            'Office to PDF',
            style: theme.textTheme.labelLarge?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: DsSpacing.sm),
          ViewerToolSecondaryButton(
            label: _useDartPath ? 'Choose Word or text' : 'Choose an office file',
            icon: Icons.picture_as_pdf_outlined,
            onPressed: _busy || !ready ? null : _officeToPdf,
          ),
          if (_busy) ...[
            const SizedBox(height: DsSpacing.md),
            LinearProgressIndicator(value: _fraction),
            if (_progress != null) ...[
              const SizedBox(height: DsSpacing.xs),
              Text(
                _progress!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
              ),
            ],
          ],
          Text(
            'To save pages as pictures, use Export images.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: secondary,
            ),
          ),
        ],
    );
  }
}
