import 'dart:async';
import 'dart:io';

import 'package:document_studio/app/providers.dart';
import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/widgets/ds_buttons.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/conversion/conversion_route.dart';
import 'package:document_studio/features/pdf_viewer/pdf_viewer_providers.dart';
import 'package:document_studio/features/pdf_viewer/panels/viewer_tool_form_body.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/infrastructure/conversion/dart_office_convert_service.dart';
import 'package:document_studio/infrastructure/conversion/libreoffice_engine_installer.dart';
import 'package:document_studio/infrastructure/conversion/libreoffice_headless.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

/// LibreOffice headless Office → PDF (and related) from the Tools hub.
///
/// Shows a real engine error when `soffice` is missing — never a dead tile.
class OfficeConvertScreen extends ConsumerStatefulWidget {
  const OfficeConvertScreen({
    super.key,
    this.initialFile,
  });

  final LocalFileRef? initialFile;

  @override
  ConsumerState<OfficeConvertScreen> createState() =>
      _OfficeConvertScreenState();
}

class _OfficeConvertScreenState extends ConsumerState<OfficeConvertScreen> {
  bool _busy = false;
  String? _enginePath;
  bool _engineChecked = false;
  String? _progress;
  String? _error;
  double? _fraction;
  LocalFileRef? _file;
  String? _pdfPassword;
  LocalFileRef? _saved;
  bool _installingEngine = false;

  /// Mobile always uses Dart. Desktop uses LibreOffice when [ _enginePath ] is set.
  bool get _useDartPath =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _ready =>
      _engineChecked && (_useDartPath || _enginePath != null);

  @override
  void initState() {
    super.initState();
    _file = widget.initialFile;
    unawaited(_probe());
    if (widget.initialFile == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _file != null) return;
        final tab = ref.read(documentTabsControllerProvider).activeTab;
        final file = tab?.file;
        if (file != null && file.isPdf) {
          _setFile(file, pdfPassword: tab?.password);
        }
      });
    }
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
    if (mounted) {
      setState(() {
        _enginePath = path;
        _engineChecked = true;
      });
    }
  }

  Future<void> _installLibreOffice() async {
    final installer = LibreOfficeEngineInstaller();
    if (!installer.isSupported) return;
    setState(() {
      _installingEngine = true;
      _error = null;
      _progress = 'Starting LibreOffice download…';
      _fraction = 0;
    });
    try {
      final path = await installer.installIntoAppStorage(
        onProgress: (f, msg) {
          if (!mounted) return;
          setState(() {
            _fraction = f;
            _progress = msg;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _enginePath = path;
        _engineChecked = true;
        _installingEngine = false;
        _progress = null;
        _fraction = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installingEngine = false;
        _progress = null;
        _fraction = null;
        _error = shortToolHelper(
          '$e',
          fallback: 'Couldn’t finish setting up conversion.',
        );
      });
    }
  }

  String get _missingEngineMessage {
    if (_useDartPath) {
      return DartOfficeConvertService.fidelityNote;
    }
    if (Platform.isWindows) {
      return 'Office conversion isn’t set up yet. You can download it into this app.';
    }
    return 'Office conversion isn’t set up on this computer yet.';
  }

  String _convertError(Object error, {String? stderr}) {
    return shortToolHelper(
      LibreOfficeHeadless.formatConvertError(error, stderr: stderr),
      fallback: 'Couldn’t convert this file. Try again.',
    );
  }

  static const _officeExts = {
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'odt',
    'ods',
    'odp',
  };

  void _setFile(LocalFileRef? file, {String? pdfPassword}) {
    setState(() {
      _file = file;
      _pdfPassword = pdfPassword;
      _saved = null;
      _error = null;
    });
  }

  Future<void> _pickSource() async {
    final picked = await ref.read(fileStorageProvider).pickOpenFile(
          allowedExtensions: _useDartPath
              ? [...DartOfficeConvertService.officeToPdfExtensions, 'pdf']
              : [..._officeExts, 'pdf'],
        );
    if (picked != null) _setFile(picked);
  }

  bool _isOffice(LocalFileRef? file) {
    if (file == null) return false;
    final ext = p.extension(file.path).toLowerCase().replaceFirst('.', '');
    return _officeExts.contains(ext);
  }

  bool _isPdf(LocalFileRef? file) {
    if (file == null) return false;
    return p.extension(file.path).toLowerCase() == '.pdf';
  }

  Future<void> _officeToPdf({bool forcePick = false}) async {
    if (_useDartPath) {
      await _officeToPdfDart(forcePick: forcePick);
      return;
    }
    final exe = _enginePath;
    if (exe == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Choose a file…';
      _fraction = 0.05;
      _saved = null;
    });
    Directory? workDir;
    try {
      final storage = ref.read(fileStorageProvider);
      var picked = (!forcePick && _isOffice(_file)) ? _file : null;
      picked ??= await storage.pickOpenFile(
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
      if (picked == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
            _fraction = null;
          });
        }
        return;
      }
      setState(() => _file = picked);
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
      final produced =
          await LibreOfficeHeadless.findProduced(outDir, stem, 'pdf');
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
      setState(() {
        _saved = LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: bytes.length,
        );
      });
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() => _error = _convertError(e, stderr: e.message));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _convertError(e));
      }
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

  Future<void> _officeToPdfDart({bool forcePick = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Choose a file…';
      _fraction = 0.05;
      _saved = null;
    });
    try {
      final storage = ref.read(fileStorageProvider);
      var picked = (!forcePick &&
              _file != null &&
              DartOfficeConvertService.canConvertOfficeToPdf(_file!.path))
          ? _file
          : null;
      picked ??= await storage.pickOpenFile(
        allowedExtensions: DartOfficeConvertService.officeToPdfExtensions,
      );
      if (picked == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _progress = null;
            _fraction = null;
          });
        }
        return;
      }
      setState(() => _file = picked);
      final bytes = await DartOfficeConvertService().officeToPdf(
        inputPath: picked.path,
        onProgress: (f, msg) {
          if (!mounted) return;
          setState(() {
            _fraction = f;
            _progress = msg;
          });
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
      setState(() {
        _saved = LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: bytes.length,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = shortToolHelper(
            '$e',
            fallback: 'Couldn’t convert this file. Try again.',
          ),
        );
      }
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

  Future<void> _pdfToOffice() async {
    if (_useDartPath) {
      await _pdfToOfficeDart();
      return;
    }
    final exe = _enginePath;
    final source = _file;
    if (exe == null || source == null || !_isPdf(source)) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Starting LibreOffice…';
      _fraction = 0.1;
      _saved = null;
    });
    Directory? workDir;
    try {
      final storage = ref.read(fileStorageProvider);
      const ext = 'docx';
      const filter = 'docx:MS Word 2007 XML';
      workDir = await LibreOfficeHeadless.createWorkDir();
      final outDir = workDir.path;
      final localIn = p.join(
        outDir,
        'in-${DateTime.now().microsecondsSinceEpoch}.pdf',
      );
      await File(source.path).copy(localIn);
      setState(() {
        _progress = 'Converting to .$ext…';
        _fraction = 0.45;
      });
      final result = await LibreOfficeHeadless.run(
        exe: exe,
        workDir: outDir,
        args: [
          // Without this LibreOffice opens PDFs in Draw, which cannot write DOCX.
          LibreOfficeHeadless.pdfWriterInfilter,
          '--convert-to',
          filter,
          '--outdir',
          outDir,
          localIn,
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
      final stem = p.basenameWithoutExtension(localIn);
      final produced =
          await LibreOfficeHeadless.findProduced(outDir, stem, ext);
      if (produced == null) {
        throw StateError(
          LibreOfficeHeadless.formatConvertError(
            'LibreOffice did not produce $stem.$ext.',
            stderr: result.stderr.toString(),
          ),
        );
      }
      setState(() {
        _progress = 'Saving…';
        _fraction = 0.85;
      });
      final bytes = await produced.readAsBytes();
      final saveStem = p.basenameWithoutExtension(source.displayName);
      final savePath = await storage.pickSavePath(
        suggestedName: '$saveStem.$ext',
        bytes: bytes,
        allowedExtensions: const [ext],
      );
      if (savePath == null) return;
      await storage.writeAtomic(
        destinationPath: savePath,
        writeToTemp: (temp) async {
          await File(temp).writeAsBytes(bytes, flush: true);
        },
      );
      if (!mounted) return;
      setState(() {
        _saved = LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: bytes.length,
        );
      });
    } on TimeoutException catch (e) {
      if (mounted) {
        setState(() => _error = _convertError(e, stderr: e.message));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = _convertError(e));
      }
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
    final source = _file;
    if (source == null || !_isPdf(source)) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Extracting text…';
      _fraction = 0.1;
      _saved = null;
    });
    try {
      final storage = ref.read(fileStorageProvider);
      final bytes = await DartOfficeConvertService().pdfToDocx(
        pdfPath: source.path,
        password: _pdfPassword,
        onProgress: (f, msg) {
          if (!mounted) return;
          setState(() {
            _fraction = f;
            _progress = msg;
          });
        },
      );
      final saveStem = p.basenameWithoutExtension(source.displayName);
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
      setState(() {
        _saved = LocalFileRef(
          path: savePath,
          displayName: p.basename(savePath),
          sizeBytes: bytes.length,
        );
      });
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = shortToolHelper(
            '$e',
            fallback: 'Couldn’t convert this file. Try again.',
          ),
        );
      }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _ready;
    final engineMissing = _engineChecked && !_useDartPath && _enginePath == null;
    final hasOffice = _useDartPath
        ? (_file != null &&
            DartOfficeConvertService.canConvertOfficeToPdf(_file!.path))
        : _isOffice(_file);
    final hasPdf = _isPdf(_file);
    final primaryLabel = _busy
        ? 'Converting…'
        : hasOffice
            ? 'Convert to PDF'
            : hasPdf
                ? 'Convert PDF → Word…'
                : (ready ? 'Choose office file → PDF…' : 'Convert');
    final VoidCallback? onPrimary = !ready || _busy
        ? null
        : hasOffice
            ? () => unawaited(_officeToPdf())
            : hasPdf
                ? () => unawaited(_pdfToOffice())
                : () => unawaited(_officeToPdf(forcePick: true));

    void close() => context.canPop() ? context.pop() : context.go('/');

    return DsToolPage(
      title: 'Office convert',
      subtitle: _useDartPath
          ? 'Plain text: PDF to Word, or Word, text, and Markdown to PDF. '
              'Excel, PowerPoint, .doc, and OpenDocument need the desktop app.'
          : 'Word, Excel and PowerPoint to PDF — or PDF to Word.',
      icon: Icons.description_outlined,
      iconColor: const Color(0xFF2563EB),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: close,
      ),
      onCancel: close,
      primaryLabel: primaryLabel,
      primaryIcon: Icons.picture_as_pdf_outlined,
      primaryBusy: _busy,
      primaryEnabled: ready && !_busy,
      onPrimary: onPrimary,
      footer: Wrap(
        spacing: DsSpacing.sm,
        runSpacing: DsSpacing.sm,
        children: [
          ActionChip(
            avatar: const Icon(Icons.note_add_outlined, size: 16),
            label: const Text('Create PDF from text'),
            visualDensity: VisualDensity.compact,
            onPressed: () => context.push(createPdfRoutePath),
          ),
          ActionChip(
            avatar: const Icon(Icons.collections_outlined, size: 16),
            label: const Text('Images to PDF'),
            visualDensity: VisualDensity.compact,
            onPressed: () => context.push(imagesToPdfRoutePath),
          ),
        ],
      ),
      child: !_engineChecked
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: DsSpacing.md),
              child: LinearProgressIndicator(),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DsToolSection(
                  topPadding: false,
                  title: 'Engine',
                  child: Text(
                    ready
                        ? (_useDartPath
                            ? '${DartOfficeConvertService.fidelityNote} '
                                'Excel, PowerPoint, .doc, and OpenDocument '
                                'need the desktop app.'
                            : 'Ready to convert on this computer.')
                        : _missingEngineMessage,
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      color: engineMissing
                          ? const Color(0xFFE4002B)
                          : null,
                    ),
                  ),
                ),
                if (ready)
                  DsToolSection(
                    title: 'Source file',
                    child: DsToolFileSource(
                      key: const Key('office_convert_selected_file'),
                      files: [?_file],
                      allowedExtensions: _useDartPath
                          ? [
                              ...DartOfficeConvertService.officeToPdfExtensions,
                              'pdf',
                            ]
                          : [..._officeExts, 'pdf'],
                      enabled: !_busy,
                      onPick: _pickSource,
                      onFilesDropped: (files) => _setFile(files.first),
                      onRemove: (_) => _setFile(null),
                      metaFor: (f) => hasPdf
                          ? 'PDF — will be converted to Word (.docx)'
                          : 'Office document — will be converted to PDF',
                      emptyTitle: _useDartPath
                          ? 'Drop a Word (.docx) or text file'
                          : 'Drop a Word, Excel or PowerPoint file',
                      emptySubtitle: _useDartPath
                          ? 'DOCX, TXT, MD — or a PDF to turn into Word'
                          : 'DOC, DOCX, XLS, XLSX, PPT, PPTX, ODT, ODS, ODP — '
                              'or a PDF to turn into Word',
                      icon: Icons.upload_file_rounded,
                    ),
                  ),
                if (engineMissing) ...[
                  const SizedBox(height: DsSpacing.md),
                  if (Platform.isWindows) ...[
                    DsPrimaryButton(
                      label: _installingEngine
                          ? (_progress ?? 'Downloading…')
                          : 'Download LibreOffice into app storage',
                      icon: Icons.download_outlined,
                      onPressed: (_busy || _installingEngine)
                          ? null
                          : () => unawaited(_installLibreOffice()),
                    ),
                    if (_installingEngine && _fraction != null) ...[
                      const SizedBox(height: DsSpacing.sm),
                      LinearProgressIndicator(value: _fraction),
                    ],
                    const SizedBox(height: DsSpacing.sm),
                  ],
                  DsSecondaryButton(
                    label: 'Check again',
                    icon: Icons.refresh,
                    onPressed: (_busy || _installingEngine)
                        ? null
                        : () {
                            setState(() {
                              _engineChecked = false;
                              _error = null;
                            });
                            unawaited(_probe());
                          },
                  ),
                ],
                if (_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpacing.lg),
                    child: DsToolProgressCard(
                      message: _progress ?? 'Converting…',
                      fraction: _fraction,
                      detail: _useDartPath
                          ? DartOfficeConvertService.fidelityNote
                          : 'LibreOffice runs locally; large files can take '
                              'up to ${LibreOfficeHeadless.timeout.inSeconds} s.',
                    ),
                  ),
                if (_error != null && !_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpacing.lg),
                    child: DsToolResultCard(
                      title: 'Conversion failed',
                      message: _error,
                      tone: DsResultTone.error,
                      onDismiss: () => setState(() => _error = null),
                    ),
                  ),
                if (_saved case final saved? when !_busy)
                  Padding(
                    padding: const EdgeInsets.only(top: DsSpacing.lg),
                    child: DsToolResultCard(
                      title: saved.isPdf ? 'PDF created' : 'Word document created',
                      file: saved,
                      stats: [
                        if (saved.sizeBytes != null)
                          DsResultStat('Size', dsFormatBytes(saved.sizeBytes!)),
                      ],
                      onOpen: saved.isPdf
                          ? () => openToolResult(context, saved)
                          : null,
                      openLabel: 'Open in viewer',
                      onShowInFolder: documentSaveResultCanRevealInFolder
                          ? () => revealToolResult(context, saved)
                          : null,
                      onDismiss: () => setState(() => _saved = null),
                    ),
                  ),
              ],
            ),
    );
  }
}
