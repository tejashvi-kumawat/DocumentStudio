import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// One range in a PDF `/PageLabels` number tree (0-based start index).
class PdfPageLabelRange {
  const PdfPageLabelRange({
    required this.startIndex0,
    this.style,
    this.prefix = '',
    this.startAt = 1,
  });

  final int startIndex0;

  /// `/S` style: `D`, `R`, `r`, `A`, `a`, or null (prefix-only).
  final String? style;
  final String prefix;
  final int startAt;
}

/// Status-bar page text: PDF label when present, else `Page N of M`.
String formatPdfViewerPageStatus({
  required int page1Based,
  required int pageCount,
  String? pageLabel,
}) {
  final label = pageLabel?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return 'Page $page1Based of $pageCount';
}

/// Resolves the label for 1-based [page1Based] from [ranges] (sorted by start).
String? resolvePdfPageLabel({
  required int page1Based,
  required List<PdfPageLabelRange> ranges,
}) {
  if (page1Based < 1 || ranges.isEmpty) return null;
  final index0 = page1Based - 1;
  PdfPageLabelRange? active;
  for (final range in ranges) {
    if (range.startIndex0 > index0) break;
    active = range;
  }
  if (active == null) return null;
  final value = active.startAt + (index0 - active.startIndex0);
  final styled = _formatStyle(active.style, value);
  final prefix = active.prefix;
  if (styled == null) {
    return prefix.isEmpty ? null : prefix;
  }
  return '$prefix$styled';
}

/// Formats one label number. [style] is a PDF `/S` name: `D`, `r`, `R`,
/// `A`, or `a`. Roman and alphabetic styles are real `/PageLabels` values.
String formatPdfPageLabelNumber(String? style, int value) =>
    _formatStyle(style, value) ?? '';

String? _formatStyle(String? style, int value) {
  if (value < 1) return null;
  switch (style) {
    case 'D':
    case null:
      if (style == null) return null;
      return '$value';
    case 'R':
      return _toRoman(value).toUpperCase();
    case 'r':
      return _toRoman(value).toLowerCase();
    case 'A':
      return _toAlpha(value).toUpperCase();
    case 'a':
      return _toAlpha(value).toLowerCase();
    default:
      return '$value';
  }
}

String _toRoman(int n) {
  const vals = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const syms = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  var remaining = n;
  final buf = StringBuffer();
  for (var i = 0; i < vals.length; i++) {
    while (remaining >= vals[i]) {
      buf.write(syms[i]);
      remaining -= vals[i];
    }
  }
  return buf.toString();
}

String _toAlpha(int n) {
  // 1=A … 26=Z, 27=AA …
  var remaining = n;
  final chars = <String>[];
  while (remaining > 0) {
    remaining--;
    chars.add(String.fromCharCode(65 + (remaining % 26)));
    remaining ~/= 26;
  }
  return chars.reversed.join();
}

/// Parses `/PageLabels` `/Nums` array from qpdf catalog JSON.
List<PdfPageLabelRange> parsePdfPageLabelRangesFromNums(List<dynamic> nums) {
  final ranges = <PdfPageLabelRange>[];
  for (var i = 0; i + 1 < nums.length; i += 2) {
    final startRaw = nums[i];
    final start = startRaw is int ? startRaw : int.tryParse('$startRaw') ?? 0;
    final dict = nums[i + 1];
    if (dict is! Map) continue;
    final map = Map<String, dynamic>.from(dict);
    final styleRaw = map['/S']?.toString();
    final style = styleRaw == null
        ? null
        : (styleRaw.startsWith('/') ? styleRaw.substring(1) : styleRaw);
    final prefix = _decodePdfString(map['/P']) ?? '';
    final stRaw = map['/St'];
    final startAt = stRaw is int ? stRaw : int.tryParse('$stRaw') ?? 1;
    ranges.add(
      PdfPageLabelRange(
        startIndex0: start,
        style: style,
        prefix: prefix,
        startAt: startAt < 1 ? 1 : startAt,
      ),
    );
  }
  ranges.sort((a, b) => a.startIndex0.compareTo(b.startIndex0));
  return ranges;
}

String? _decodePdfString(Object? raw) {
  if (raw == null) return null;
  if (raw is! String) return raw.toString();
  if (raw.startsWith('u:')) {
    try {
      return utf8.decode(base64.decode(raw.substring(2)));
    } catch (_) {
      return raw.substring(2);
    }
  }
  if (raw.startsWith('b:') || raw.startsWith('n:')) {
    return raw.substring(2);
  }
  return raw;
}

/// Page count from the open file’s page tree (no page render).
///
/// Used when the viewer has not reported a count yet. Returns null if the
/// file cannot be read.
Future<int?> probePdfPageCountForLabels(
  String inputPath, [
  String? password,
]) async {
  try {
    final bytes = Uint8List.fromList(await File(inputPath).readAsBytes());
    final doc = await openPdfForPageLabels(bytes, password);
    return doc.pageCount;
  } catch (_) {
    return null;
  }
}

/// Opens [bytes] for a catalog edit. Encrypted files are unlocked with
/// PDFium first so Android can write `/PageLabels` without qpdf.
Future<PdfEditDocument> openPdfForPageLabels(
  Uint8List bytes,
  String? password,
) async {
  try {
    return PdfEditDocument.open(bytes);
  } on PdfEditException catch (e) {
    if (!e.encrypted) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Could not read this PDF’s catalog.',
        cause: e,
      );
    }
    try {
      final unlocked = await _unlockPdfBytes(bytes, password);
      return PdfEditDocument.open(unlocked);
    } on PdfEditException catch (again) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Could not read this PDF’s catalog.',
        cause: again,
      );
    } catch (error) {
      throw documentStudioErrorFromPdfrxOpen(error, password: password);
    }
  }
}

/// Reads catalog `/PageLabels` (flat `/Nums` or a `/Kids` number tree).
List<PdfPageLabelRange> readPdfPageLabelRanges(PdfEditDocument doc) {
  PdfDict catalog;
  try {
    catalog = doc.catalog;
  } on PdfEditException {
    return const [];
  }
  final ranges = List<PdfPageLabelRange>.of(
    _readLabelTree(doc, catalog['PageLabels'], 0),
  );
  ranges.sort((a, b) => a.startIndex0.compareTo(b.startIndex0));
  return ranges;
}

List<PdfPageLabelRange> _readLabelTree(
  PdfEditDocument doc,
  PdfObj? node,
  int depth,
) {
  if (depth > 32) return const [];
  final dict = doc.dictOf(node);
  if (dict == null) return const [];
  final ranges = <PdfPageLabelRange>[];
  final nums = doc.resolve(dict['Nums']);
  if (nums is PdfArray) {
    for (var i = 0; i + 1 < nums.length; i += 2) {
      final start = doc.numOf(nums[i])?.round();
      final body = doc.dictOf(nums[i + 1]);
      if (start == null || body == null) continue;
      final style = body.nameOf('S');
      final prefixObj = doc.resolve(body['P']);
      final prefix = prefixObj is PdfString ? prefixObj.text : '';
      final startAt = doc.numOf(body['St'])?.round() ?? 1;
      ranges.add(
        PdfPageLabelRange(
          startIndex0: start,
          style: (style == null || style.isEmpty) ? null : style,
          prefix: prefix,
          startAt: startAt < 1 ? 1 : startAt,
        ),
      );
    }
  }
  final kids = doc.resolve(dict['Kids']);
  if (kids is PdfArray) {
    for (final kid in kids.items) {
      ranges.addAll(_readLabelTree(doc, kid, depth + 1));
    }
  }
  return ranges;
}

Future<Uint8List> _unlockPdfBytes(Uint8List input, String? password) async {
  try {
    final doc = await PdfDocument.openData(
      input,
      passwordProvider: password == null || password.isEmpty
          ? null
          : () async => password,
      firstAttemptByEmptyPassword: password == null || password.isEmpty,
    );
    try {
      return await doc.encodePdf(removeSecurity: true);
    } finally {
      await doc.dispose();
    }
  } catch (e) {
    throw documentStudioErrorFromPdfrxOpen(e, password: password);
  }
}

/// Loads page-label ranges. Desktop uses qpdf JSON when the binary exists.
/// Android and other builds without qpdf read the catalog in Dart.
Future<List<PdfPageLabelRange>> loadPdfPageLabelRanges({
  required String inputPath,
  String? password,
  QpdfCliRunner? cli,
}) async {
  if (!Platform.isAndroid && await isQpdfCliAvailable()) {
    return _loadPdfPageLabelRangesWithQpdf(
      inputPath: inputPath,
      password: password,
      cli: cli,
    );
  }
  try {
    final bytes = Uint8List.fromList(await File(inputPath).readAsBytes());
    final doc = await openPdfForPageLabels(bytes, password);
    return readPdfPageLabelRanges(doc);
  } catch (_) {
    return const [];
  }
}

Future<List<PdfPageLabelRange>> _loadPdfPageLabelRangesWithQpdf({
  required String inputPath,
  String? password,
  QpdfCliRunner? cli,
}) async {
  if (!await isQpdfCliAvailable()) return const [];
  final runner = cli ?? QpdfCliRunner();
  final tempDir = await Directory.systemTemp.createTemp('ds_page_labels_');
  final jsonPath = p.join(tempDir.path, 'doc.json');
  try {
    await runner.runRaw([
      if (password != null && password.isNotEmpty) '--password=$password',
      '--json-output',
      inputPath,
      jsonPath,
    ]);
    final root =
        jsonDecode(await File(jsonPath).readAsString()) as Map<String, dynamic>;
    final catalog = _findCatalog(root);
    if (catalog == null) return const [];
    final labels = catalog['/PageLabels'];
    if (labels is! Map) return const [];
    final nums = labels['/Nums'];
    if (nums is! List) return const [];
    return parsePdfPageLabelRangesFromNums(nums);
  } catch (_) {
    return const [];
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Styles the page-label writer emits. Roman is included because `/r` and
/// `/R` are written into `/PageLabels` and formatted on read.
const pdfPageLabelStyleChoices = <(String code, String sample)>[
  ('D', '1, 2, 3, …'),
  ('r', 'i, ii, iii, …'),
  ('R', 'I, II, III, …'),
];

/// What the page-labels dialog applies to a page range.
class PdfPageLabelEdit {
  const PdfPageLabelEdit({
    required this.allPages,
    required this.fromPage1,
    required this.toPage1,
    required this.beginNewSection,
    this.style = 'D',
    this.prefix = '',
    this.startAt = 1,
  });

  final bool allPages;
  final int fromPage1;
  final int toPage1;

  /// When false, numbering already used before [fromPage1] covers the range.
  final bool beginNewSection;

  /// `/S` name without the slash: `D`, `r`, or `R`.
  final String style;
  final String prefix;
  final int startAt;
}

/// First [count] labels of a new section, including [prefix].
String previewPdfPageLabelRun({
  required String style,
  required String prefix,
  required int startAt,
  int count = 3,
}) {
  final start = startAt < 1 ? 1 : startAt;
  final normalized = _writableStyle(style);
  return [
    for (var i = 0; i < count; i++)
      '$prefix${formatPdfPageLabelNumber(normalized, start + i)}',
  ].join(', ');
}

/// Revisions whose only change is `/PageLabels`. The page pixels do not
/// change, so the viewer must not reload or jump back to page 1.
abstract final class PageLabelOwnRevisions {
  static final Map<String, int> _byPath = {};

  static void mark(String path, int revision) => _byPath[path] = revision;

  static bool isOwn(String path, int revision) => _byPath[path] == revision;
}

/// Merges [edit] into [existing] `/PageLabels` ranges.
///
/// A new section replaces ranges that start inside the chosen pages and, when
/// the section stops before the last page, resumes the numbering those later
/// pages already had. Extending drops section starts inside the range so the
/// preceding section covers it.
List<PdfPageLabelRange> mergePdfPageLabels({
  required List<PdfPageLabelRange> existing,
  required int pageCount,
  required PdfPageLabelEdit edit,
}) {
  if (pageCount < 1) return List<PdfPageLabelRange>.of(existing);
  var from1 = edit.allPages ? 1 : edit.fromPage1;
  var to1 = edit.allPages ? pageCount : edit.toPage1;
  from1 = from1.clamp(1, pageCount);
  to1 = to1.clamp(1, pageCount);
  if (from1 > to1) {
    final swap = from1;
    from1 = to1;
    to1 = swap;
  }
  final from0 = from1 - 1;
  final to0 = to1 - 1;
  final after = to0 + 1;
  final sorted = List<PdfPageLabelRange>.of(existing)
    ..sort((a, b) => a.startIndex0.compareTo(b.startIndex0));

  final byStart = <int, PdfPageLabelRange>{
    for (final range in sorted)
      if (range.startIndex0 < from0 || range.startIndex0 > to0)
        if (range.startIndex0 >= 0 && range.startIndex0 < pageCount)
          range.startIndex0: range,
  };

  if (!edit.beginNewSection) {
    return _sortedRanges(byStart);
  }

  byStart[from0] = PdfPageLabelRange(
    startIndex0: from0,
    style: _writableStyle(edit.style),
    prefix: edit.prefix,
    startAt: edit.startAt < 1 ? 1 : edit.startAt,
  );

  if (after < pageCount && !byStart.containsKey(after)) {
    final active = _activeAt(sorted, after);
    if (active == null) {
      byStart[after] = PdfPageLabelRange(
        startIndex0: after,
        style: 'D',
        startAt: after + 1,
      );
    } else if (active.startIndex0 != after) {
      final value = active.startAt + (after - active.startIndex0);
      byStart[after] = PdfPageLabelRange(
        startIndex0: after,
        style: active.style ?? 'D',
        prefix: active.prefix,
        startAt: value < 1 ? 1 : value,
      );
    }
  }
  return _sortedRanges(byStart);
}

String _writableStyle(String style) => switch (style) {
  'D' || 'r' || 'R' => style,
  _ => 'D',
};

PdfPageLabelRange? _activeAt(List<PdfPageLabelRange> ranges, int index0) {
  PdfPageLabelRange? active;
  for (final range in ranges) {
    if (range.startIndex0 > index0) break;
    active = range;
  }
  return active;
}

List<PdfPageLabelRange> _sortedRanges(Map<int, PdfPageLabelRange> byStart) {
  final ranges = byStart.values.toList()
    ..sort((a, b) => a.startIndex0.compareTo(b.startIndex0));
  return ranges;
}

Map<String, dynamic>? _findCatalog(Map<String, dynamic> root) {
  final qpdfList = root['qpdf'];
  if (qpdfList is! List || qpdfList.length < 2) return null;
  final objects = qpdfList[1];
  if (objects is! Map) return null;
  for (final value in objects.values) {
    if (value is! Map) continue;
    final body = value['value'] is Map
        ? Map<String, dynamic>.from(value['value'] as Map)
        : Map<String, dynamic>.from(value);
    if (body['/Type'] == '/Catalog') return body;
  }
  return null;
}
