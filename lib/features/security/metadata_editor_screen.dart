import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/design_system/ds_spacing.dart';
import 'package:document_studio/design_system/shell/ds_tool_form_layout.dart';
import 'package:document_studio/design_system/shell/ds_tool_route_actions.dart';
import 'package:document_studio/design_system/widgets/ds_tool_blocks.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/features/document_lifecycle/document_save_result_actions.dart';
import 'package:document_studio/features/document_lifecycle/document_session_commit.dart';
import 'package:document_studio/features/security/security_password_workflow.dart';
import 'package:document_studio/features/security/security_route.dart';
import 'package:document_studio/features/security/security_save_helper.dart';
import 'package:document_studio/features/security/security_tool_widgets.dart';
import 'package:document_studio/infrastructure/pdf/pdf_render_port.dart';
import 'package:document_studio/infrastructure/pdf/qpdf_metadata_adapter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class MetadataEditorDeps {
  const MetadataEditorDeps({
    required this.fileStorage,
    required this.pdf,
    required this.metadataPort,
  });

  final FileStoragePort fileStorage;
  final PdfRenderPort pdf;
  final PdfMetadataPort metadataPort;
}

class MetadataEditorScreen extends ConsumerStatefulWidget {
  const MetadataEditorScreen({
    super.key,
    required this.deps,
    this.initialFile,
    this.initialPassword,
    this.embedInViewerPanel = false,
  });

  final MetadataEditorDeps deps;
  final LocalFileRef? initialFile;
  final String? initialPassword;
  final bool embedInViewerPanel;

  @override
  ConsumerState<MetadataEditorScreen> createState() =>
      _MetadataEditorScreenState();
}

class _MetadataEditorScreenState extends ConsumerState<MetadataEditorScreen> {
  LocalFileRef? _file;
  bool _busy = false;
  bool _loading = false;
  bool? _qpdfAvailable;
  String? _inputPassword;
  PdfDocumentInfo? _loadedInfo;
  LocalFileRef? _saved;
  String? _error;

  late final _title = TextEditingController();
  late final _author = TextEditingController();
  late final _subject = TextEditingController();
  late final _keywords = TextEditingController();
  late final _creator = TextEditingController();
  late final _producer = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refreshAvailability();
    final file = widget.initialFile;
    if (file != null) {
      _file = file;
      final pw = widget.initialPassword;
      if (pw != null && pw.isNotEmpty) _inputPassword = pw;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadMetadata());
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _author, _subject, _keywords, _creator, _producer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _refreshAvailability() async {
    final available = await widget.deps.metadataPort.isAvailable();
    if (mounted) setState(() => _qpdfAvailable = available);
  }

  void _applyInfoToFields(PdfDocumentInfo? info) {
    _title.text = info?.title ?? '';
    _author.text = info?.author ?? '';
    _subject.text = info?.subject ?? '';
    _keywords.text = info?.keywords ?? '';
    _creator.text = info?.creator ?? '';
    _producer.text = info?.producer ?? '';
  }

  static bool _isPasswordError(DocumentStudioError e) =>
      e.code == DocumentStudioErrorCode.passwordRequired ||
      e.code == DocumentStudioErrorCode.wrongPassword;

  Future<bool> _askPassword(DocumentStudioError e) async {
    if (!mounted) return false;
    final pw = await promptPdfPasswordAfterRejection(
      context,
      rejected: e.code == DocumentStudioErrorCode.wrongPassword ? e : null,
    );
    if (pw == null || pw.isEmpty || !mounted) return false;
    setState(() => _inputPassword = pw);
    return true;
  }

  Future<void> _loadMetadata() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    var retry = false;
    try {
      final info =
          await widget.deps.pdf.loadInfo(file, password: _inputPassword);
      if (!mounted || _file?.path != file.path) return;
      setState(() {
        _loadedInfo = info;
        _applyInfoToFields(info);
      });
    } on DocumentStudioError catch (e) {
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
      } else if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (retry && mounted) await _loadMetadata();
  }

  void _setFile(LocalFileRef? file) {
    setState(() {
      _file = file;
      _inputPassword = null;
      _loadedInfo = null;
      _saved = null;
      _error = null;
      _applyInfoToFields(null);
    });
    if (file != null) _loadMetadata();
  }

  Future<void> _pick() async {
    final picked = await widget.deps.fileStorage.pickOpenFile(
      allowedExtensions: ['pdf'],
    );
    if (picked != null) _setFile(picked);
  }

  Future<void> _save() async {
    final file = _file;
    if (file == null || _busy) return;
    setState(() {
      _busy = true;
      _saved = null;
      _error = null;
    });
    var retry = false;
    String? temp;
    try {
      final storage = widget.deps.fileStorage;
      temp = await storage.createTempFile(prefix: 'metadata', suffix: '.pdf');
      await widget.deps.metadataPort.writeDocumentInfo(
        input: file,
        outputPath: temp,
        inputPassword: _inputPassword,
        fields: PdfDocumentInfoFields(
          title: _title.text,
          author: _author.text,
          subject: _subject.text,
          keywords: _keywords.text,
          creator: _creator.text,
          producer: _producer.text,
        ),
      );
      if (!mounted) return;
      if (widget.embedInViewerPanel) {
        await commitTempPathToActiveSession(
          ref: ref,
          context: context,
          tempPath: temp,
          successMessage: 'Document properties updated.',
        );
        temp = null;
        return;
      }
      final saved = await promptSavePdfFromTemp(
        storage: storage,
        source: LocalFileRef(path: temp, displayName: 'metadata.pdf'),
        suggestedBaseName: p.basenameWithoutExtension(file.displayName),
      );
      if (!mounted || saved == null) return;
      setState(() => _saved = saved);
    } on DocumentStudioError catch (e) {
      if (_isPasswordError(e)) {
        retry = await _askPassword(e);
      } else if (mounted) {
        setState(() => _error = e.recoveryHint ?? e.message);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (temp != null) File(temp).delete().ignore();
      if (mounted) setState(() => _busy = false);
    }
    if (retry && mounted) await _save();
  }

  Widget _body({required bool lockFile}) {
    final theme = Theme.of(context);
    final qpdf = _qpdfAvailable;
    final info = _loadedInfo;
    final fields = [
      (_title, 'Title', Icons.title_rounded),
      (_author, 'Author', Icons.person_outline_rounded),
      (_subject, 'Subject', Icons.subject_rounded),
      (_keywords, 'Keywords', Icons.sell_outlined),
      (_creator, 'Creator app', Icons.apps_rounded),
      (_producer, 'Producer', Icons.precision_manufacturing_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (qpdf == false) ...[
          SecurityQpdfUnavailablePanel(
            onRecheck: _refreshAvailability,
            busy: _busy,
          ),
          const SizedBox(height: DsSpacing.lg),
        ],
        DsToolSection(
          topPadding: false,
          title: 'Source PDF',
          child: lockFile
              ? Text(_file!.displayName, style: theme.textTheme.titleSmall)
              : DsToolFileSource(
                  files: [?_file],
                  enabled: !_busy,
                  loading: _loading,
                  onPick: _pick,
                  onFilesDropped: (files) => _setFile(files.first),
                  onRemove: (_) => _setFile(null),
                  metaFor: (_) => info == null
                      ? null
                      : '${info.pageCount} '
                          '${info.pageCount == 1 ? 'page' : 'pages'}'
                          '${info.encrypted == true ? ' · encrypted' : ''}',
                  emptyTitle: 'Drop a PDF to edit its properties',
                  emptySubtitle: 'Title, author, subject and keywords',
                  icon: Icons.description_outlined,
                ),
        ),
        DsToolSection(
          title: 'Document properties',
          subtitle: 'Clear a field to remove it from the saved PDF',
          child: LayoutBuilder(
            builder: (context, c) {
              final twoCol = c.maxWidth >= 560;
              final width =
                  twoCol ? (c.maxWidth - DsSpacing.md) / 2 : c.maxWidth;
              return Wrap(
                spacing: DsSpacing.md,
                runSpacing: DsSpacing.md,
                children: [
                  for (final (controller, label, icon) in fields)
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: controller,
                        enabled: !_busy && !_loading && _file != null,
                        minLines: 1,
                        maxLines: controller == _keywords ? 2 : 1,
                        decoration: InputDecoration(
                          labelText: label,
                          prefixIcon: Icon(icon, size: 18),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolProgressCard(message: 'Writing document properties…'),
          ),
        if (_error != null && !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Something went wrong',
              message: _error,
              tone: DsResultTone.error,
              onDismiss: () => setState(() => _error = null),
            ),
          ),
        if (_saved case final saved? when !_busy)
          Padding(
            padding: const EdgeInsets.only(top: DsSpacing.lg),
            child: DsToolResultCard(
              title: 'Properties saved',
              file: saved,
              onOpen: () =>
                  openToolResult(context, saved, password: _inputPassword),
              openLabel: 'Open in viewer',
              onShowInFolder: documentSaveResultCanRevealInFolder
                  ? () => revealToolResult(context, saved)
                  : null,
              onDismiss: () => setState(() => _saved = null),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final qpdf = _qpdfAvailable;
    final embed = widget.embedInViewerPanel;
    final canSave = _file != null && !_busy && !_loading && qpdf == true;

    if (embed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(DsSpacing.md),
              children: [_body(lockFile: _file != null)],
            ),
          ),
          DsToolStickyActionBar(
            primaryLabel: 'Apply',
            primaryIcon: Icons.check_rounded,
            primaryEnabled: canSave,
            primaryBusy: _busy,
            onPrimary: _save,
          ),
        ],
      );
    }

    return DsToolPage(
      title: 'Edit metadata',
      subtitle: 'Change the title, author and keywords stored in a PDF.',
      icon: Icons.description_outlined,
      iconColor: const Color(0xFF7C3AED),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => handleDsToolFormCancel(context, ref),
      ),
      primaryLabel: 'Save copy as…',
      primaryIcon: Icons.save_alt_rounded,
      primaryEnabled: canSave,
      primaryBusy: _busy,
      onPrimary: _save,
      onCancel: () => handleDsToolFormCancel(context, ref),
      footer: SecurityRelatedToolsPanel(
        compact: true,
        busy: _busy,
        excludePath: metadataRoutePath,
        sourceFile: _file,
        sourcePassword: _inputPassword,
      ),
      child: _body(lockFile: false),
    );
  }
}
