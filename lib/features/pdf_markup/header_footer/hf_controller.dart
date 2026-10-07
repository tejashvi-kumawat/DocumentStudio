import 'dart:async';
import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_templates.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/features/pdf_markup/header_footer/hf_preview_painter.dart';
import 'package:document_studio/infrastructure/pdf/hf_template_store.dart';
import 'package:document_studio/infrastructure/pdf/pdf_header_footer_service.dart';
import 'package:document_studio/infrastructure/pdf/stamp/pdf_stamp_engine.dart';
import 'package:flutter/foundation.dart';

const defaultHeaderFooterSpec = HeaderFooterSpec(
  zones: {
    HfZone.footerCenter: HfZoneStyle(
      text: 'Page {page} of {pages}',
      sizePt: 9,
      colorRgb: 0x1F2937,
    ),
  },
);

/// State shared by the viewer panel and the standalone Headers & footers /
/// Page numbers screens: the spec being edited, document geometry,
/// existing-stamp detection and template persistence.
///
/// Page numbers are the same engine with [kind] = `PageNumbers`, so both can
/// coexist on a page and each can be replaced/removed on its own.
class HeaderFooterController extends ChangeNotifier {
  HeaderFooterController({
    this.kind = PdfStampKind.headerFooter,
    this.defaultSpec = defaultHeaderFooterSpec,
    HfTemplateStore? store,
  }) : service = PdfHeaderFooterService(kind: kind),
       _store = store ?? HfTemplateStore();

  final String kind;
  final HeaderFooterSpec defaultSpec;
  final PdfHeaderFooterService service;
  final HfTemplateStore _store;

  late HeaderFooterSpec _spec = defaultSpec;
  HfZone _focus = HfZone.footerCenter;
  HeaderFooterDocument? _document;
  HeaderFooterInspection _existing = HeaderFooterInspection.none;
  List<HfTemplate> _custom = const [];
  bool _loading = false;
  bool _busy = false;
  bool _justApplied = false;
  String? _error;
  bool _disposed = false;
  bool _userEdited = false;

  HeaderFooterSpec get spec => _spec;
  HfZone get focusZone => _focus;
  HeaderFooterDocument? get document => _document;
  HeaderFooterInspection get existing => _existing;
  List<HfTemplate> get customTemplates => _custom;
  bool get loading => _loading;
  bool get busy => _busy;
  bool get justApplied => _justApplied;
  String? get error => _error;

  int get pageCount => _document?.info.pageCount ?? 1;

  HfDocInfo docInfo(LocalFileRef? file) =>
      _document?.info ??
      HfDocInfo(fileName: file?.displayName ?? 'document.pdf', pageCount: 1);

  List<String> get issues => validateHeaderFooterSpec(_spec, pageCount);

  int get targetPageCount {
    var n = 0;
    for (var i = 1; i <= pageCount; i++) {
      if (hfAppliesToPage(_spec, i, pageCount)) n++;
    }
    return n;
  }

  HeaderFooterPreviewState previewState(
    LocalFileRef? file, {
    bool showGuides = false,
    bool showFocus = true,
  }) => HeaderFooterPreviewState(
    spec: _spec,
    doc: docInfo(file),
    visible: !_justApplied,
    showGuides: showGuides,
    focusZone: showFocus ? _focus : null,
  );

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  String _describe(Object e) {
    if (e is DocumentStudioError) {
      final hint = e.recoveryHint;
      return hint == null ? e.message : '${e.message} $hint';
    }
    return '$e';
  }

  Future<void> load(LocalFileRef file) async {
    _loading = true;
    _error = null;
    _notify();
    final customF = _store.loadCustom();
    final lastF = _store.loadLast(scope: kind);
    final forFileF = _store.loadForFile(kind, file.path);
    try {
      final bytes = await File(file.path).readAsBytes();
      final (doc, found) = await service.load(
        bytes,
        fileName: file.displayName,
      );
      _document = doc;
      _existing = found;
    } catch (e) {
      _error = _describe(e);
      _existing = HeaderFooterInspection.none;
    }
    _custom = await customF;
    final last = await lastF;
    final forFile = await forFileF;
    if (!_userEdited) {
      final fromDoc =
          _existing.spec ?? (_existing.hasExisting ? forFile : null);
      _spec = fromDoc ?? last ?? defaultSpec;
      _focus = HfZone.values.firstWhere(
        (z) => !_spec.zone(z).isEmpty,
        orElse: () => HfZone.footerCenter,
      );
    }
    _loading = false;
    _notify();
  }

  void update(HeaderFooterSpec next) {
    if (next == _spec) return;
    _spec = next;
    _userEdited = true;
    _justApplied = false;
    _notify();
  }

  void focus(HfZone z) {
    if (z == _focus) return;
    _focus = z;
    _notify();
  }

  void loadExistingSettings() {
    final s = _existing.spec;
    if (s == null) return;
    update(s);
  }

  /// Stamps the current spec onto [file]'s current bytes.
  Future<Uint8List> applyToBytes(LocalFileRef file) async {
    final doc = _document;
    if (doc == null) throw StateError('Document not loaded yet');
    return _run(() async {
      final bytes = await File(file.path).readAsBytes();
      final out = await service.apply(bytes, spec: _spec, info: doc.info);
      _justApplied = true;
      unawaited(_store.saveLast(_spec, scope: kind));
      unawaited(_store.saveForFile(kind, file.path, _spec));
      return out;
    });
  }

  Future<Uint8List> removeToBytes(LocalFileRef file) {
    return _run(() async {
      final bytes = await File(file.path).readAsBytes();
      final out = await service.remove(bytes);
      unawaited(_store.saveForFile(kind, file.path, null));
      return out;
    });
  }

  /// Re-scans [file] after it changed on disk (e.g. after Apply/Remove).
  Future<void> refresh(LocalFileRef file) async {
    try {
      final bytes = await File(file.path).readAsBytes();
      final (doc, found) = await service.load(
        bytes,
        fileName: file.displayName,
      );
      _document = doc;
      _existing = found;
    } catch (_) {}
    _notify();
  }

  Future<Uint8List> _run(Future<Uint8List> Function() work) async {
    _busy = true;
    _error = null;
    _notify();
    try {
      return await work();
    } catch (e) {
      _error = _describe(e);
      rethrow;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<void> saveTemplate(String name) async {
    _custom = await _store.saveCustom(name: name, spec: _spec);
    _notify();
  }

  Future<List<HfTemplate>> deleteTemplate(String id) async {
    _custom = await _store.delete(id);
    _notify();
    return _custom;
  }
}
