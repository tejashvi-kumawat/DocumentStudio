import 'package:document_studio/infrastructure/pdf/edit/pdf_page_editor.dart';
import 'package:flutter/foundation.dart' show compute;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// URI or GoTo link written as a real PDF `/Annot /Subtype /Link`.
class PdfLinkAnnotationSpec {
  const PdfLinkAnnotationSpec.uri({
    required this.pageIndex1Based,
    required this.llx,
    required this.lly,
    required this.urx,
    required this.ury,
    required this.uri,
    this.visibleBorder = false,
  }) : destPage1Based = null,
       displayNormRect = null,
       assert(uri != null);

  const PdfLinkAnnotationSpec.goTo({
    required this.pageIndex1Based,
    required this.llx,
    required this.lly,
    required this.urx,
    required this.ury,
    required this.destPage1Based,
    this.visibleBorder = false,
  }) : uri = null,
       displayNormRect = null,
       assert(destPage1Based != null);

  /// URI link placed by a display-normalized rect (see [displayNormRect]).
  const PdfLinkAnnotationSpec.uriDisplayNorm({
    required this.pageIndex1Based,
    required Rect this.displayNormRect,
    required String this.uri,
    this.visibleBorder = false,
  }) : destPage1Based = null,
       llx = 0,
       lly = 0,
       urx = 0,
       ury = 0;

  /// GoTo link placed by a display-normalized rect (see [displayNormRect]).
  const PdfLinkAnnotationSpec.goToDisplayNorm({
    required this.pageIndex1Based,
    required Rect this.displayNormRect,
    required int this.destPage1Based,
    this.visibleBorder = false,
  }) : uri = null,
       llx = 0,
       lly = 0,
       urx = 0,
       ury = 0;

  final int pageIndex1Based;

  /// Unrotated PDF user-space rect; used only when [displayNormRect] is null.
  final double llx;
  final double lly;
  final double urx;
  final double ury;
  final String? uri;
  final int? destPage1Based;

  /// 0..1 rect, top-left origin, in the displayed page (after `/Rotate`,
  /// relative to the crop box). When set, overrides [llx]..[ury].
  final Rect? displayNormRect;

  /// Draw a thin blue border (`/Border [0 0 1]`); invisible otherwise.
  final bool visibleBorder;

  bool get isUri => uri != null && uri!.trim().isNotEmpty;
}

/// Injects Link annotations via qpdf `--update-from-json`.
class PdfLinkAnnotationService {
  PdfLinkAnnotationService({QpdfCliRunner? cli})
    : _cli = cli ?? QpdfCliRunner();

  final QpdfCliRunner _cli;

  /// Pure Dart for any file our editor opens (no qpdf needed); qpdf only
  /// for encrypted or damaged files.
  Future<Uint8List> addLinkToBytes({
    required LocalFileRef input,
    required PdfLinkAnnotationSpec link,
    String? password,
    Rect? replaceDisplayNormRect,
  }) async {
    final norm = link.displayNormRect;
    if (norm != null && (password == null || password.isEmpty)) {
      final bytes = await File(input.path).readAsBytes();
      final out = await compute(_addLinkIsolate, (
        bytes,
        link.pageIndex1Based,
        norm,
        link.uri,
        link.destPage1Based,
        link.visibleBorder,
        replaceDisplayNormRect,
      ));
      if (out != null) return out;
    }
    return _toBytes(
      prefix: 'ds_link_annot_',
      run: (outPath) => addLink(
        inputPath: input.path,
        outputPath: outPath,
        link: link,
        password: password,
        replaceDisplayNormRect: replaceDisplayNormRect,
      ),
    );
  }

  /// Removes every Link annotation on the page whose rect matches
  /// [displayNormRect] (display-normalized, top-left origin).
  Future<Uint8List> removeLinksToBytes({
    required LocalFileRef input,
    required int pageIndex1Based,
    required Rect displayNormRect,
    String? password,
  }) async {
    if (password == null || password.isEmpty) {
      final bytes = await File(input.path).readAsBytes();
      final out = await compute(_removeLinkIsolate, (
        bytes,
        pageIndex1Based,
        displayNormRect,
      ));
      if (out != null) return out;
    }
    return _toBytes(
      prefix: 'ds_link_remove_',
      run: (outPath) => _edit(
        inputPath: input.path,
        outputPath: outPath,
        password: password,
        errorMessage: 'Could not remove link annotation',
        mutate: (doc, updates) {
          final pageKey = doc.pageKey(pageIndex1Based);
          final removed = _removeMatchingLinks(
            doc,
            updates,
            pageKey,
            displayNormRect,
          );
          if (removed == 0) throw _linkNotFound();
        },
      ),
    );
  }

  Future<void> addLink({
    required String inputPath,
    required String outputPath,
    required PdfLinkAnnotationSpec link,
    String? password,
    Rect? replaceDisplayNormRect,
  }) {
    return _edit(
      inputPath: inputPath,
      outputPath: outputPath,
      password: password,
      errorMessage: 'Could not write link annotation',
      mutate: (doc, updates) {
        final pageKey = doc.pageKey(link.pageIndex1Based);
        if (replaceDisplayNormRect != null) {
          final removed = _removeMatchingLinks(
            doc,
            updates,
            pageKey,
            replaceDisplayNormRect,
          );
          if (removed == 0) throw _linkNotFound();
        }

        final annotRef = '${doc.allocateObjNum()} 0 R';

        final action = <String, dynamic>{};
        if (link.isUri) {
          var uri = link.uri!.trim();
          if (!uri.contains('://') &&
              !uri.startsWith('mailto:') &&
              !uri.startsWith('#')) {
            uri = 'https://$uri';
          }
          action['/S'] = '/URI';
          action['/URI'] = 'u:$uri';
        } else {
          final destKey = doc.pageObjKeys[link.destPage1Based!];
          if (destKey == null) {
            throw QpdfCliException(
              exitCode: 2,
              stderr: 'Destination page ${link.destPage1Based} not found',
              stdout: '',
            );
          }
          action['/S'] = '/GoTo';
          action['/D'] = [_refOf(destKey), '/Fit'];
        }

        final List<double> rect;
        final norm = link.displayNormRect;
        if (norm != null) {
          rect = _displayNormToUser(doc.pageGeometry(pageKey), norm);
        } else {
          rect = [
            math.min(link.llx, link.urx),
            math.min(link.lly, link.ury),
            math.max(link.llx, link.urx),
            math.max(link.lly, link.ury),
          ];
        }

        final annotValue = <String, dynamic>{
          '/Type': '/Annot',
          '/Subtype': '/Link',
          '/Rect': [for (final v in rect) _round3(v)],
          '/P': _refOf(pageKey),
          '/F': 4,
          '/H': '/I',
          if (link.visibleBorder) ...{
            '/Border': [0, 0, 1],
            '/C': [0.0, 0.0, 1.0],
          } else
            '/Border': [0, 0, 0],
          '/A': action,
        };
        updates['obj:$annotRef'] = {'value': annotValue};

        final annots = _readAnnots(doc, updates, pageKey);
        annots.list.add(annotRef);
        _writeAnnots(doc, updates, pageKey, annots);
      },
    );
  }

  Future<Uint8List> _toBytes({
    required String prefix,
    required Future<void> Function(String outPath) run,
  }) async {
    if (!await isQpdfCliAvailable()) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.featureUnavailable,
        message: 'qpdf is required to write link annotations',
      );
    }
    final tempDir = await Directory.systemTemp.createTemp(prefix);
    try {
      final outPath = p.join(tempDir.path, 'out.pdf');
      await run(outPath);
      return Uint8List.fromList(await File(outPath).readAsBytes());
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Loads the qpdf JSON, lets [mutate] fill the update objects map, and
  /// applies it in a single `--update-from-json` pass.
  Future<void> _edit({
    required String inputPath,
    required String outputPath,
    required String? password,
    required String errorMessage,
    required void Function(_QpdfJsonDoc doc, Map<String, dynamic> updates)
    mutate,
  }) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final tempDir = await Directory.systemTemp.createTemp('ds_link_json_');
    final jsonPath = p.join(tempDir.path, 'doc.json');
    final updatePath = p.join(tempDir.path, 'update.json');
    try {
      await _cli.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        '--json-output',
        '--json-key=pages',
        inputPath,
        jsonPath,
      ]);
      final doc = _QpdfJsonDoc.parse(
        jsonDecode(await File(jsonPath).readAsString()) as Map<String, dynamic>,
      );

      final updates = <String, dynamic>{};
      mutate(doc, updates);

      final updateDoc = {
        'qpdf': [
          {'jsonversion': 2},
          updates,
        ],
      };
      await File(updatePath).writeAsString(jsonEncode(updateDoc));

      await _cli.runRaw([
        if (password != null && password.isNotEmpty) '--password=$password',
        inputPath,
        '--update-from-json=$updatePath',
        outputPath,
      ]);
    } on QpdfCliException {
      rethrow;
    } on DocumentStudioError {
      rethrow;
    } catch (e) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.nativeEngineError,
        message: errorMessage,
        recoveryHint: '$e',
      );
    } finally {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

DocumentStudioError _linkNotFound() => const DocumentStudioError(
  code: DocumentStudioErrorCode.unknownError,
  message: 'Link not found',
);

String _refOf(String objKey) => objKey.replaceFirst('obj:', '');

double _round3(double v) => (v * 1000).roundToDouble() / 1000;

final RegExp _refPattern = RegExp(r'^\d+ \d+ R$');

/// Parsed qpdf JSON v2 document (`--json-key=pages`).
class _QpdfJsonDoc {
  _QpdfJsonDoc(this.objects, this.pageObjKeys, this._maxObj);

  factory _QpdfJsonDoc.parse(Map<String, dynamic> root) {
    final qpdfList = root['qpdf'];
    if (qpdfList is! List || qpdfList.length < 2) {
      throw QpdfCliException(
        exitCode: 2,
        stderr: 'Unexpected qpdf JSON layout',
        stdout: '',
      );
    }
    final objects = Map<String, dynamic>.from(qpdfList[1] as Map);

    final pageObjKeys = <int, String>{};
    final pagesMeta = root['pages'];
    if (pagesMeta is List) {
      for (final page in pagesMeta) {
        if (page is! Map) continue;
        final pos = page['pageposfrom1'];
        final obj = page['object'];
        if (pos is int && obj is String) {
          pageObjKeys[pos] = 'obj:$obj';
        }
      }
    }
    if (pageObjKeys.isEmpty) {
      var index = 0;
      for (final key in objects.keys) {
        final value = _valueOf(objects[key]);
        if (value is Map && value['/Type'] == '/Page') {
          index += 1;
          pageObjKeys[index] = key;
        }
      }
    }

    var maxObj = 0;
    for (final key in objects.keys) {
      final m = RegExp(r'^obj:(\d+) ').firstMatch(key);
      if (m != null) {
        final n = int.tryParse(m.group(1)!);
        if (n != null && n > maxObj) maxObj = n;
      }
    }
    return _QpdfJsonDoc(objects, pageObjKeys, maxObj);
  }

  final Map<String, dynamic> objects;
  final Map<int, String> pageObjKeys;
  int _maxObj;

  int allocateObjNum() => ++_maxObj;

  static dynamic _valueOf(dynamic entry) =>
      entry is Map ? entry['value'] : null;

  /// Raw `value` of an object key like `obj:3 0 R`.
  dynamic objectValue(String objKey) => _valueOf(objects[objKey]);

  /// Follows indirect references (`"N 0 R"`) to their values.
  dynamic resolve(dynamic v) {
    var cur = v;
    for (var i = 0; i < 16; i++) {
      if (cur is String && _refPattern.hasMatch(cur)) {
        cur = objectValue('obj:$cur');
      } else {
        return cur;
      }
    }
    return cur;
  }

  Map<String, dynamic>? dictOf(dynamic v) {
    final r = resolve(v);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  String pageKey(int pageIndex1Based) {
    final key = pageObjKeys[pageIndex1Based];
    if (key == null || dictOf(objectValue(key)) == null) {
      throw QpdfCliException(
        exitCode: 2,
        stderr: 'Page $pageIndex1Based not found',
        stdout: '',
      );
    }
    return key;
  }

  /// Page attribute, walking `/Parent` for inheritable keys.
  dynamic inherited(String pageKey, String name) {
    var node = dictOf(objectValue(pageKey));
    for (var depth = 0; node != null && depth < 64; depth++) {
      if (node.containsKey(name)) return resolve(node[name]);
      node = dictOf(node['/Parent']);
    }
    return null;
  }

  _PageGeometry pageGeometry(String pageKey) {
    final media =
        _box(inherited(pageKey, '/MediaBox')) ?? const (0.0, 0.0, 612.0, 792.0);
    var crop = media;
    final cropRaw = _box(inherited(pageKey, '/CropBox'));
    if (cropRaw != null) {
      final x0 = math.max(cropRaw.$1, media.$1);
      final y0 = math.max(cropRaw.$2, media.$2);
      final x1 = math.min(cropRaw.$3, media.$3);
      final y1 = math.min(cropRaw.$4, media.$4);
      if (x1 > x0 && y1 > y0) crop = (x0, y0, x1, y1);
    }
    final rotRaw = inherited(pageKey, '/Rotate');
    var rot = rotRaw is num ? rotRaw.round() : 0;
    rot = ((rot % 360) + 360) % 360;
    rot = ((rot + 45) ~/ 90) * 90 % 360;
    return _PageGeometry(
      cx0: crop.$1,
      cy0: crop.$2,
      cw: crop.$3 - crop.$1,
      ch: crop.$4 - crop.$2,
      rotate: rot,
    );
  }

  (double, double, double, double)? _box(dynamic raw) {
    final v = resolve(raw);
    if (v is! List || v.length < 4) return null;
    final n = <double>[];
    for (final e in v.take(4)) {
      final r = resolve(e);
      if (r is! num) return null;
      n.add(r.toDouble());
    }
    final box = (
      math.min(n[0], n[2]),
      math.min(n[1], n[3]),
      math.max(n[0], n[2]),
      math.max(n[1], n[3]),
    );
    if (box.$3 - box.$1 <= 0 || box.$4 - box.$2 <= 0) return null;
    return box;
  }
}

/// Effective crop box (unrotated user space) and normalized `/Rotate`.
class _PageGeometry {
  const _PageGeometry({
    required this.cx0,
    required this.cy0,
    required this.cw,
    required this.ch,
    required this.rotate,
  });

  final double cx0;
  final double cy0;
  final double cw;
  final double ch;
  final int rotate;

  bool get _swapped => rotate == 90 || rotate == 270;
  double get displayW => _swapped ? ch : cw;
  double get displayH => _swapped ? cw : ch;

  /// Display-normalized (u, v), top-left origin -> unrotated user space.
  (double, double) toUser(double u, double v) {
    final dx = u * displayW;
    final dy = v * displayH;
    final (x, y) = switch (rotate) {
      90 => (dy, dx),
      180 => (cw - dx, dy),
      270 => (cw - dy, ch - dx),
      _ => (dx, ch - dy),
    };
    return (x + cx0, y + cy0);
  }

  /// Unrotated user space -> display-normalized (u, v), top-left origin.
  (double, double) toDisplayNorm(double x, double y) {
    final lx = x - cx0;
    final ly = y - cy0;
    final (dx, dy) = switch (rotate) {
      90 => (ly, lx),
      180 => (cw - lx, ly),
      270 => (ch - ly, cw - lx),
      _ => (lx, ch - ly),
    };
    return (dx / displayW, dy / displayH);
  }
}

List<double> _displayNormToUser(_PageGeometry g, Rect norm) {
  final (ax, ay) = g.toUser(norm.left, norm.top);
  final (bx, by) = g.toUser(norm.right, norm.bottom);
  return [
    math.min(ax, bx),
    math.min(ay, by),
    math.max(ax, bx),
    math.max(ay, by),
  ];
}

Rect _userToDisplayNorm(_PageGeometry g, List<double> r) {
  final (au, av) = g.toDisplayNorm(r[0], r[1]);
  final (bu, bv) = g.toDisplayNorm(r[2], r[3]);
  return Rect.fromLTRB(
    math.min(au, bu),
    math.min(av, bv),
    math.max(au, bu),
    math.max(av, bv),
  );
}

bool _rectsMatch(Rect a, Rect b) {
  final inter = a.intersect(b);
  if (inter.width > 0 && inter.height > 0) {
    final interArea = inter.width * inter.height;
    final union = a.width * a.height + b.width * b.height - interArea;
    if (union > 0 && interArea / union >= 0.5) return true;
  }
  final ca = a.center;
  final cb = b.center;
  return (ca.dx - cb.dx).abs() <= 0.01 &&
      (ca.dy - cb.dy).abs() <= 0.01 &&
      (a.width - b.width).abs() <= 0.02 &&
      (a.height - b.height).abs() <= 0.02;
}

/// Page `/Annots` array plus the object that owns it (null = inline on page).
typedef _Annots = ({List<dynamic> list, String? arrayObjKey});

Map<String, dynamic> _currentPage(
  _QpdfJsonDoc doc,
  Map<String, dynamic> updates,
  String pageKey,
) {
  final pending = updates[pageKey];
  if (pending is Map && pending['value'] is Map) {
    return Map<String, dynamic>.from(pending['value'] as Map);
  }
  return doc.dictOf(doc.objectValue(pageKey)) ?? <String, dynamic>{};
}

_Annots _readAnnots(
  _QpdfJsonDoc doc,
  Map<String, dynamic> updates,
  String pageKey,
) {
  final page = _currentPage(doc, updates, pageKey);
  final raw = page['/Annots'];
  if (raw is String && _refPattern.hasMatch(raw)) {
    final arrayKey = 'obj:$raw';
    final pending = updates[arrayKey];
    final value = pending is Map ? pending['value'] : doc.resolve(raw);
    return (
      list: value is List ? List<dynamic>.from(value) : <dynamic>[],
      arrayObjKey: arrayKey,
    );
  }
  return (
    list: raw is List ? List<dynamic>.from(raw) : <dynamic>[],
    arrayObjKey: null,
  );
}

void _writeAnnots(
  _QpdfJsonDoc doc,
  Map<String, dynamic> updates,
  String pageKey,
  _Annots annots,
) {
  if (annots.arrayObjKey != null) {
    updates[annots.arrayObjKey!] = {'value': annots.list};
    return;
  }
  final page = _currentPage(doc, updates, pageKey);
  page['/Annots'] = annots.list;
  updates[pageKey] = {'value': page};
}

/// Removes Link annotations on [pageKey] matching [target]; returns the count.
int _removeMatchingLinks(
  _QpdfJsonDoc doc,
  Map<String, dynamic> updates,
  String pageKey,
  Rect target,
) {
  final geometry = doc.pageGeometry(pageKey);
  final annots = _readAnnots(doc, updates, pageKey);
  final kept = <dynamic>[];
  var removed = 0;
  for (final entry in annots.list) {
    final annot = doc.dictOf(entry);
    if (annot != null && annot['/Subtype'] == '/Link') {
      final rawRect = doc.resolve(annot['/Rect']);
      if (rawRect is List && rawRect.length >= 4) {
        final nums = [for (final e in rawRect.take(4)) doc.resolve(e)];
        if (nums.every((e) => e is num)) {
          final r = [for (final e in nums) (e as num).toDouble()];
          final norm = _userToDisplayNorm(geometry, [
            math.min(r[0], r[2]),
            math.min(r[1], r[3]),
            math.max(r[0], r[2]),
            math.max(r[1], r[3]),
          ]);
          if (_rectsMatch(norm, target)) {
            removed++;
            continue;
          }
        }
      }
    }
    kept.add(entry);
  }
  if (removed > 0) {
    _writeAnnots(doc, updates, pageKey, (
      list: kept,
      arrayObjKey: annots.arrayObjKey,
    ));
  }
  return removed;
}

Uint8List? _addLinkIsolate(
  (Uint8List, int, Rect, String?, int?, bool, Rect?) a,
) => addPageLink(
  a.$1,
  a.$2,
  rect: a.$3,
  uri: a.$4,
  destPage1: a.$5,
  visibleBorder: a.$6,
  replaceNorm: a.$7,
);

Uint8List? _removeLinkIsolate((Uint8List, int, Rect) a) =>
    removePageLinks(a.$1, a.$2, a.$3);
