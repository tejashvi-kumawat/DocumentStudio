import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/features/pdf_viewer/pdf_page_labels.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// Bytes plus the `/PageLabels` ranges written into them.
class PdfPageLabelWriteResult {
  const PdfPageLabelWriteResult({required this.bytes, required this.ranges});

  final Uint8List bytes;
  final List<PdfPageLabelRange> ranges;
}

/// Writes catalog `/PageLabels`.
///
/// Desktop uses qpdf `--update-from-json` when the binary is present.
/// Android (and any build without qpdf) writes the same number tree with
/// [PdfEditDocument]. Page content is not changed. Callers commit
/// [PdfPageLabelWriteResult.bytes] into the session working copy; Save is
/// what updates the original file.
Future<PdfPageLabelWriteResult> writePdfPageLabels({
  required String inputPath,
  required PdfPageLabelEdit edit,
  required int pageCount,
  String? password,
  QpdfCliRunner? cli,
}) async {
  if (pageCount < 1) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidPdf,
      message: 'This PDF has no pages to number.',
    );
  }
  if (Platform.isAndroid || !await isQpdfCliAvailable()) {
    final raw = Uint8List.fromList(await File(inputPath).readAsBytes());
    final doc = await openPdfForPageLabels(raw, password);
    return writePdfPageLabelsOnDocument(
      doc: doc,
      edit: edit,
      pageCount: pageCount,
    );
  }
  return _writePdfPageLabelsWithQpdf(
    inputPath: inputPath,
    edit: edit,
    pageCount: pageCount,
    password: password,
    cli: cli,
  );
}

/// Pure-Dart `/PageLabels` write. [doc] is not encrypted.
PdfPageLabelWriteResult writePdfPageLabelsOnDocument({
  required PdfEditDocument doc,
  required PdfPageLabelEdit edit,
  required int pageCount,
}) {
  if (pageCount < 1) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidPdf,
      message: 'This PDF has no pages to number.',
    );
  }
  final ranges = mergePdfPageLabels(
    existing: readPdfPageLabelRanges(doc),
    pageCount: pageCount,
    edit: edit,
  );
  _writeLabelRanges(doc, ranges);
  return PdfPageLabelWriteResult(bytes: doc.save(), ranges: ranges);
}

void _writeLabelRanges(PdfEditDocument doc, List<PdfPageLabelRange> ranges) {
  final root = doc.trailer['Root'];
  PdfDict catalog;
  try {
    catalog = doc.catalog.clone();
  } on PdfEditException {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidPdf,
      message: 'Could not read this PDF’s catalog.',
    );
  }
  if (ranges.isEmpty) {
    if (!catalog.containsKey('PageLabels')) return;
    catalog.remove('PageLabels');
    _storeCatalog(doc, root, catalog);
    return;
  }

  final nums = PdfArray();
  for (final range in ranges) {
    nums.items.add(PdfNum(range.startIndex0));
    final dict = PdfDict();
    final style = range.style;
    if (style != null && style.isNotEmpty) {
      dict['S'] = PdfName(style);
    }
    if (range.prefix.isNotEmpty) {
      dict['P'] = PdfString.text(range.prefix);
    }
    dict['St'] = PdfNum(range.startAt < 1 ? 1 : range.startAt);
    nums.items.add(dict);
  }
  final labels = PdfDict({'Nums': nums});
  final existing = catalog['PageLabels'];
  if (existing is PdfRef) {
    doc.setObject(existing, labels);
    return;
  }
  catalog['PageLabels'] = doc.addObject(labels);
  _storeCatalog(doc, root, catalog);
}

void _storeCatalog(PdfEditDocument doc, PdfObj? root, PdfDict catalog) {
  if (root is PdfRef) {
    doc.setObject(root, catalog);
    return;
  }
  doc.trailer['Root'] = doc.addObject(catalog);
}

Future<PdfPageLabelWriteResult> _writePdfPageLabelsWithQpdf({
  required String inputPath,
  required PdfPageLabelEdit edit,
  required int pageCount,
  String? password,
  QpdfCliRunner? cli,
}) async {
  final runner = cli ?? QpdfCliRunner();
  final tempDir = await Directory.systemTemp.createTemp('ds_page_label_write_');
  try {
    final jsonPath = p.join(tempDir.path, 'doc.json');
    final updatePath = p.join(tempDir.path, 'update.json');
    final outPath = p.join(tempDir.path, 'out.pdf');
    await runner.runRaw([
      if (password != null && password.isNotEmpty) '--password=$password',
      '--json-output',
      inputPath,
      jsonPath,
    ]);
    final root =
        jsonDecode(await File(jsonPath).readAsString()) as Map<String, dynamic>;
    final qpdfList = root['qpdf'];
    if (qpdfList is! List || qpdfList.length < 2 || qpdfList[1] is! Map) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Could not read this PDF’s catalog.',
      );
    }
    final objects = Map<String, dynamic>.from(qpdfList[1] as Map);
    final catalog = _catalogEntry(objects);
    if (catalog == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Could not read this PDF’s catalog.',
      );
    }
    final existing = _existingRanges(objects, catalog.value);
    final ranges = mergePdfPageLabels(
      existing: existing,
      pageCount: pageCount,
      edit: edit,
    );
    final updates = _updateObjects(
      objects: objects,
      catalogKey: catalog.key,
      catalogValue: catalog.value,
      ranges: ranges,
      meta: qpdfList[0],
    );
    await File(updatePath).writeAsString(
      jsonEncode({
        'qpdf': [
          {'jsonversion': 2},
          updates,
        ],
      }),
    );
    await runner.runRaw([
      if (password != null && password.isNotEmpty) '--password=$password',
      inputPath,
      '--update-from-json=$updatePath',
      outPath,
    ]);
    return PdfPageLabelWriteResult(
      bytes: Uint8List.fromList(await File(outPath).readAsBytes()),
      ranges: ranges,
    );
  } on DocumentStudioError {
    rethrow;
  } on QpdfCliException catch (e) {
    throw DocumentStudioError(
      code: DocumentStudioErrorCode.nativeEngineError,
      message: 'Could not write page labels.',
      recoveryHint: e.stderr.trim().isEmpty ? null : e.stderr.trim(),
    );
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

class _CatalogEntry {
  const _CatalogEntry(this.key, this.value);
  final String key;
  final Map<String, dynamic> value;
}

_CatalogEntry? _catalogEntry(Map<String, dynamic> objects) {
  for (final entry in objects.entries) {
    final raw = entry.value;
    if (raw is! Map) continue;
    final value = raw['value'];
    if (value is Map && value['/Type'] == '/Catalog') {
      return _CatalogEntry(entry.key, Map<String, dynamic>.from(value));
    }
  }
  return null;
}

final _refPattern = RegExp(r'^\d+ \d+ R$');

dynamic _resolve(Map<String, dynamic> objects, dynamic value) {
  var current = value;
  for (var i = 0; i < 8; i++) {
    if (current is String && _refPattern.hasMatch(current)) {
      final obj = objects['obj:$current'];
      if (obj is Map && obj.containsKey('value')) {
        current = obj['value'];
        continue;
      }
    }
    return current;
  }
  return current;
}

List<PdfPageLabelRange> _existingRanges(
  Map<String, dynamic> objects,
  Map<String, dynamic> catalog,
) {
  final labels = _resolve(objects, catalog['/PageLabels']);
  if (labels is! Map) return const [];
  final nums = labels['/Nums'];
  if (nums is! List) return const [];
  return parsePdfPageLabelRangesFromNums(nums);
}

Map<String, dynamic> _updateObjects({
  required Map<String, dynamic> objects,
  required String catalogKey,
  required Map<String, dynamic> catalogValue,
  required List<PdfPageLabelRange> ranges,
  required Object? meta,
}) {
  final catalog = Map<String, dynamic>.from(catalogValue);
  final updates = <String, dynamic>{};
  if (ranges.isEmpty) {
    catalog.remove('/PageLabels');
    updates[catalogKey] = {'value': catalog};
    return updates;
  }

  final nums = <dynamic>[
    for (final range in ranges) ...[
      range.startIndex0,
      <String, dynamic>{
        if (range.style != null) '/S': '/${range.style}',
        if (range.prefix.isNotEmpty) '/P': 'u:${range.prefix}',
        '/St': range.startAt < 1 ? 1 : range.startAt,
      },
    ],
  ];
  final labelsValue = <String, dynamic>{'/Nums': nums};

  final existingRef = catalog['/PageLabels'];
  if (existingRef is String && _refPattern.hasMatch(existingRef)) {
    updates['obj:$existingRef'] = {'value': labelsValue};
    return updates;
  }

  final newId = _nextObjectId(objects, meta);
  final ref = '$newId 0 R';
  catalog['/PageLabels'] = ref;
  updates[catalogKey] = {'value': catalog};
  updates['obj:$ref'] = {'value': labelsValue};
  return updates;
}

int _nextObjectId(Map<String, dynamic> objects, Object? meta) {
  var maxId = 0;
  if (meta is Map) {
    final raw = meta['maxobjectid'];
    if (raw is int) maxId = raw;
  }
  for (final key in objects.keys) {
    final match = RegExp(r'^obj:(\d+) ').firstMatch(key);
    final n = match == null ? null : int.tryParse(match.group(1)!);
    if (n != null && n > maxId) maxId = n;
  }
  return maxId + 1;
}
