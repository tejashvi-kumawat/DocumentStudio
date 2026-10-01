import 'dart:convert';
import 'dart:io';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Snapshot of PDF accessibility-related catalog fields (honest, not PDF/UA).
class PdfAccessibilityStructureInfo {
  const PdfAccessibilityStructureInfo({
    required this.documentLanguage,
    required this.hasStructTreeRoot,
    required this.markInfoMarked,
    required this.hasMarkInfo,
    required this.readingOrderLines,
  });

  /// Catalog `/Lang` when present (decoded from qpdf `u:…` form).
  final String? documentLanguage;

  /// True when catalog has `/StructTreeRoot` (real tag tree may still be empty).
  final bool hasStructTreeRoot;

  /// `/MarkInfo` /Marked when present.
  final bool? markInfoMarked;

  final bool hasMarkInfo;

  /// Plain-text lines in page order (from extractPlainText), not a tag tree walk.
  final List<String> readingOrderLines;

  bool get isTaggedClaim =>
      hasStructTreeRoot || markInfoMarked == true;
}

/// Reads catalog structure flags and writes `/Lang` + `/MarkInfo /Marked`
/// via qpdf `--update-from-json` only. Does **not** claim PDF/UA compliance
/// and does not invent `/Alt` text without a structure element.
class PdfAccessibilityTagsService {
  PdfAccessibilityTagsService({QpdfCliRunner? cli}) : _cli = cli ?? QpdfCliRunner();

  final QpdfCliRunner _cli;

  Future<bool> isAvailable() => isQpdfCliAvailable();

  Future<PdfAccessibilityStructureInfo> inspect({
    required String inputPath,
    String? password,
    List<String> readingOrderLines = const [],
  }) async {
    await _ensureAvailable();
    final tempDir = await Directory.systemTemp.createTemp('ds_a11y_inspect_');
    final jsonPath = p.join(tempDir.path, 'doc.json');
    try {
      await _cli.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        '--json-output',
        inputPath,
        jsonPath,
      ]);
      final root = jsonDecode(await File(jsonPath).readAsString())
          as Map<String, dynamic>;
      final catalog = _findCatalog(root);
      if (catalog == null) {
        return PdfAccessibilityStructureInfo(
          documentLanguage: null,
          hasStructTreeRoot: false,
          markInfoMarked: null,
          hasMarkInfo: false,
          readingOrderLines: readingOrderLines,
        );
      }
      final langRaw = catalog['/Lang'];
      final lang = _decodePdfString(langRaw);
      final hasStruct = catalog.containsKey('/StructTreeRoot');
      final markInfo = catalog['/MarkInfo'];
      bool? marked;
      var hasMark = false;
      if (markInfo is Map) {
        hasMark = true;
        final m = markInfo['/Marked'];
        if (m is bool) {
          marked = m;
        } else if (m != null) {
          marked = m.toString().toLowerCase() == 'true';
        }
      } else if (markInfo is String) {
        // Indirect reference — treat as present but unknown Marked value.
        hasMark = true;
      }
      return PdfAccessibilityStructureInfo(
        documentLanguage: lang,
        hasStructTreeRoot: hasStruct,
        markInfoMarked: marked,
        hasMarkInfo: hasMark,
        readingOrderLines: readingOrderLines,
      );
    } on QpdfCliException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Could not inspect PDF structure.',
        recoveryHint: e.stderr.trim().isEmpty ? e.stdout.trim() : e.stderr.trim(),
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Sets catalog `/Lang` and `/MarkInfo` `{/Marked: true}` via qpdf JSON update.
  Future<void> setLanguageAndMarked({
    required String inputPath,
    required String outputPath,
    required String languageTag,
    String? password,
    bool markAsMarked = true,
  }) async {
    await _ensureAvailable();
    final lang = languageTag.trim();
    if (lang.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.unknownError,
        message: 'Document language cannot be empty.',
        recoveryHint: 'Use a BCP 47 tag such as en-US or hi-IN.',
      );
    }
    final tempDir = await Directory.systemTemp.createTemp('ds_a11y_write_');
    final jsonPath = p.join(tempDir.path, 'doc.json');
    final updatePath = p.join(tempDir.path, 'update.json');
    try {
      await _cli.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        '--json-output',
        inputPath,
        jsonPath,
      ]);
      final root = jsonDecode(await File(jsonPath).readAsString())
          as Map<String, dynamic>;
      final qpdfList = root['qpdf'];
      if (qpdfList is! List || qpdfList.length < 2) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'Unexpected qpdf JSON layout.',
        );
      }
      final objects = Map<String, dynamic>.from(qpdfList[1] as Map);
      String? catKey;
      Map<String, dynamic>? catVal;
      for (final entry in objects.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        final value = v['value'];
        if (value is Map && value['/Type'] == '/Catalog') {
          catKey = entry.key;
          catVal = Map<String, dynamic>.from(value);
          break;
        }
      }
      if (catKey == null || catVal == null) {
        throw const DocumentStudioError(
          code: DocumentStudioErrorCode.nativeEngineError,
          message: 'PDF catalog object not found.',
        );
      }
      catVal['/Lang'] = 'u:$lang';
      if (markAsMarked) {
        catVal['/MarkInfo'] = {'/Marked': true};
      }
      final updateDoc = {
        'qpdf': [
          {'jsonversion': 2},
          {
            catKey: {'value': catVal},
          },
        ],
      };
      await File(updatePath).writeAsString(jsonEncode(updateDoc));
      await Directory(p.dirname(outputPath)).create(recursive: true);
      await _cli.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        inputPath,
        '--update-from-json=$updatePath',
        outputPath,
      ]);
    } on QpdfCliException catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: 'Could not update document language / MarkInfo.',
        recoveryHint: e.stderr.trim().isEmpty ? e.stdout.trim() : e.stderr.trim(),
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  Map<String, dynamic>? _findCatalog(Map<String, dynamic> root) {
    final qpdfList = root['qpdf'];
    if (qpdfList is! List || qpdfList.length < 2) return null;
    final objects = qpdfList[1];
    if (objects is! Map) return null;
    for (final entry in objects.entries) {
      final v = entry.value;
      if (v is! Map) continue;
      final value = v['value'];
      if (value is Map && value['/Type'] == '/Catalog') {
        return Map<String, dynamic>.from(value);
      }
    }
    return null;
  }

  String? _decodePdfString(Object? raw) {
    if (raw == null) return null;
    if (raw is! String) return raw.toString();
    if (raw.startsWith('u:')) return raw.substring(2);
    if (raw.startsWith('b:')) {
      // Binary hex — leave as opaque.
      return raw;
    }
    return raw;
  }

  Future<void> _ensureAvailable() async {
    if (!await isAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'Accessibility tags require the bundled qpdf engine.',
        recoveryHint: 'Rebuild so engines/ includes qpdf.',
      );
    }
  }
}
