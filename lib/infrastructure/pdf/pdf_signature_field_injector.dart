import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/desktop/desktop_engine_resolver.dart';
import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:path/path.dart' as p;

/// Injects an unsigned `/FT /Sig` widget at [pdfRect] via bundled qpdf JSON.
///
/// Used when the open PDF has no signature field yet but the user dragged a
/// rectangle for certificate appearance. Returns bytes ready for `pdfsig -sign`.
class PdfSignatureFieldInjector {
  PdfSignatureFieldInjector({
    DesktopEngineResolver? resolver,
    Future<ProcessResult> Function(String exe, List<String> args)? run,
  }) : _resolver = resolver ?? desktopEngineResolver,
       _run =
           run ??
           ((exe, args) => Process.run(
             exe,
             args,
             stdoutEncoding: systemEncoding,
             stderrEncoding: systemEncoding,
           ));

  final DesktopEngineResolver _resolver;
  final Future<ProcessResult> Function(String exe, List<String> args) _run;

  /// PDF user-space rect: left, bottom, right, top (llx, lly, urx, ury).
  Future<Uint8List> injectUnsignedField({
    required Uint8List inputBytes,
    required double llx,
    required double lly,
    required double urx,
    required double ury,
    required int pageIndex1Based,
    String fieldName = 'DS_Signature',
  }) async {
    final qpdf = await _resolver.resolveQpdf();
    if (qpdf == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'qpdf was not found in the app engines bundle.',
        recoveryHint:
            'Rebuild the desktop app so engines/ includes qpdf '
            '(scripts/bundle_linux_engines.sh on Linux).',
      );
    }

    final work = await Directory.systemTemp.createTemp('ds_sig_field_');
    try {
      final inPdf = File(p.join(work.path, 'in.pdf'));
      final jsonPath = p.join(work.path, 'doc.json');
      final outPdf = File(p.join(work.path, 'out.pdf'));
      await inPdf.writeAsBytes(inputBytes, flush: true);

      final dump = await _run(qpdf, ['--json-output', inPdf.path, jsonPath]);
      if (dump.exitCode != 0 || !await File(jsonPath).exists()) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Could not read PDF structure for a signature field.',
          recoveryHint: dump.stderr.toString().trim(),
        );
      }

      final raw = await File(jsonPath).readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Unexpected qpdf JSON shape.',
        );
      }
      final qpdfArr = decoded['qpdf'];
      if (qpdfArr is! List || qpdfArr.length < 2) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'qpdf JSON missing object table.',
        );
      }
      final meta = qpdfArr[0];
      final objs = qpdfArr[1];
      if (meta is! Map<String, dynamic> || objs is! Map<String, dynamic>) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'qpdf JSON object table is invalid.',
        );
      }

      final pageRef = _pageObjectRef(objs, pageIndex1Based);
      if (pageRef == null) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Page $pageIndex1Based not found for signature field.',
        );
      }

      final maxId =
          (meta['maxobjectid'] as num?)?.toInt() ?? _maxObjectId(objs);
      final widgetId = maxId + 1;
      final formId = maxId + 2;
      final widgetRef = '$widgetId 0 R';
      final formRef = '$formId 0 R';

      objs['obj:$widgetRef'] = {
        'value': {
          '/Type': '/Annot',
          '/Subtype': '/Widget',
          '/FT': '/Sig',
          '/T': 'u:$fieldName',
          '/Rect': [llx, lly, urx, ury],
          '/F': 4,
          '/P': pageRef,
        },
      };

      final pageObj = objs['obj:$pageRef'];
      if (pageObj is! Map<String, dynamic>) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Page dictionary missing in qpdf JSON.',
        );
      }
      final pageValue = pageObj['value'];
      if (pageValue is! Map<String, dynamic>) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Page value missing in qpdf JSON.',
        );
      }
      final annots = pageValue['/Annots'];
      if (annots is List) {
        pageValue['/Annots'] = [...annots, widgetRef];
      } else {
        pageValue['/Annots'] = [widgetRef];
      }

      final catalogRef = _catalogRef(objs);
      final catalogObj = catalogRef == null ? null : objs['obj:$catalogRef'];
      String? existingFormRef;
      if (catalogObj is Map<String, dynamic> &&
          catalogObj['value'] is Map<String, dynamic>) {
        final cv = catalogObj['value'] as Map<String, dynamic>;
        final af = cv['/AcroForm'];
        if (af is String) existingFormRef = af;
      }

      if (existingFormRef != null && objs['obj:$existingFormRef'] != null) {
        final formObj = objs['obj:$existingFormRef'];
        if (formObj is Map<String, dynamic> &&
            formObj['value'] is Map<String, dynamic>) {
          final fv = formObj['value'] as Map<String, dynamic>;
          final fields = fv['/Fields'];
          if (fields is List) {
            fv['/Fields'] = [...fields, widgetRef];
          } else {
            fv['/Fields'] = [widgetRef];
          }
          fv['/SigFlags'] = 3;
        }
      } else {
        objs['obj:$formRef'] = {
          'value': {
            '/Fields': [widgetRef],
            '/SigFlags': 3,
          },
        };
        if (catalogObj is Map<String, dynamic> &&
            catalogObj['value'] is Map<String, dynamic>) {
          (catalogObj['value'] as Map<String, dynamic>)['/AcroForm'] = formRef;
        }
        meta['maxobjectid'] = formId;
      }

      if ((meta['maxobjectid'] as num?)?.toInt() != formId) {
        meta['maxobjectid'] =
            widgetId > ((meta['maxobjectid'] as num?)?.toInt() ?? 0)
            ? (existingFormRef != null ? widgetId : formId)
            : meta['maxobjectid'];
        if (existingFormRef == null) {
          meta['maxobjectid'] = formId;
        } else {
          meta['maxobjectid'] = widgetId;
        }
      }

      final trailer = objs['trailer'];
      if (trailer is Map<String, dynamic> &&
          trailer['value'] is Map<String, dynamic>) {
        (trailer['value'] as Map<String, dynamic>)['/Size'] =
            ((meta['maxobjectid'] as num).toInt()) + 1;
      }

      final outJson = File(p.join(work.path, 'out.json'));
      await outJson.writeAsString(jsonEncode(decoded), flush: true);

      final build = await _run(qpdf, [
        '--json-input',
        outJson.path,
        outPdf.path,
      ]);
      if (build.exitCode != 0 || !await outPdf.exists()) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Could not write signature field into the PDF.',
          recoveryHint: build.stderr.toString().trim(),
        );
      }
      return Uint8List.fromList(await outPdf.readAsBytes());
    } finally {
      try {
        await work.delete(recursive: true);
      } catch (_) {}
    }
  }

  String? _pageObjectRef(Map<String, dynamic> objs, int pageIndex1Based) {
    // Prefer pages array from top-level if present in a fuller dump; else walk Kids.
    final pagesRoot = _findPagesRoot(objs);
    if (pagesRoot == null) return null;
    final kids = _collectPageKids(objs, pagesRoot);
    final idx = pageIndex1Based - 1;
    if (idx < 0 || idx >= kids.length) return null;
    return kids[idx];
  }

  String? _findPagesRoot(Map<String, dynamic> objs) {
    final catalog = _catalogRef(objs);
    if (catalog == null) return null;
    final cat = objs['obj:$catalog'];
    if (cat is! Map<String, dynamic>) return null;
    final value = cat['value'];
    if (value is! Map<String, dynamic>) return null;
    final pages = value['/Pages'];
    return pages is String ? pages : null;
  }

  String? _catalogRef(Map<String, dynamic> objs) {
    final trailer = objs['trailer'];
    if (trailer is Map<String, dynamic> &&
        trailer['value'] is Map<String, dynamic>) {
      final root = (trailer['value'] as Map<String, dynamic>)['/Root'];
      if (root is String) return root;
    }
    for (final e in objs.entries) {
      final v = e.value;
      if (v is! Map<String, dynamic>) continue;
      final value = v['value'];
      if (value is Map && value['/Type'] == '/Catalog') {
        return e.key.replaceFirst('obj:', '');
      }
    }
    return null;
  }

  List<String> _collectPageKids(Map<String, dynamic> objs, String pagesRef) {
    final out = <String>[];
    void walk(String ref) {
      final obj = objs['obj:$ref'];
      if (obj is! Map<String, dynamic>) return;
      final value = obj['value'];
      if (value is! Map<String, dynamic>) return;
      final type = value['/Type'];
      if (type == '/Page') {
        out.add(ref);
        return;
      }
      final kids = value['/Kids'];
      if (kids is List) {
        for (final k in kids) {
          if (k is String) walk(k);
        }
      }
    }

    walk(pagesRef);
    return out;
  }

  int _maxObjectId(Map<String, dynamic> objs) {
    var max = 0;
    for (final key in objs.keys) {
      final m = RegExp(r'^obj:(\d+)\s+0\s+R$').firstMatch(key);
      if (m != null) {
        final id = int.tryParse(m.group(1)!) ?? 0;
        if (id > max) max = id;
      }
    }
    return max;
  }
}
