import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/pdf_form_spot_detector.dart';
import 'package:document_studio_qpdf/document_studio_qpdf.dart';
import 'package:path/path.dart' as p;

/// AcroForm field widget found on a page, with the widget object reference so
/// it can be removed once its value is flattened into the page.
class LiveFormField {
  const LiveFormField({required this.spot, required this.widgetRef});

  final PdfFormSpot spot;
  final String widgetRef;
}

final RegExp _ref = RegExp(r'^\d+ \d+ R$');

class _QpdfJson {
  _QpdfJson(this.objects, this.pageRefs);

  final Map<String, dynamic> objects;
  final Map<int, String> pageRefs;

  dynamic value(String ref) {
    final e = objects['obj:$ref'];
    return e is Map ? e['value'] : null;
  }

  dynamic resolve(dynamic v) {
    var cur = v;
    for (var i = 0; i < 16 && cur is String && _ref.hasMatch(cur); i++) {
      cur = value(cur);
    }
    return cur;
  }

  Map<String, dynamic>? dict(dynamic v) {
    final r = resolve(v);
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  dynamic inherited(String pageRef, String key) {
    var node = dict(pageRef);
    for (var d = 0; node != null && d < 64; d++) {
      if (node.containsKey(key)) return resolve(node[key]);
      node = dict(node['/Parent']);
    }
    return null;
  }

  List<double>? box(dynamic raw) {
    final v = resolve(raw);
    if (v is! List || v.length < 4) return null;
    final n = <double>[];
    for (final e in v.take(4)) {
      final r = resolve(e);
      if (r is! num) return null;
      n.add(r.toDouble());
    }
    return [
      math.min(n[0], n[2]),
      math.min(n[1], n[3]),
      math.max(n[0], n[2]),
      math.max(n[1], n[3]),
    ];
  }

  /// User-space rect -> 0..1 rect in the displayed page (crop + `/Rotate`).
  Rect? displayNorm(String pageRef, List<double> r) {
    final media = box(inherited(pageRef, '/MediaBox')) ?? [0, 0, 612, 792];
    var crop = media;
    final c = box(inherited(pageRef, '/CropBox'));
    if (c != null) {
      final x0 = math.max(c[0], media[0]);
      final y0 = math.max(c[1], media[1]);
      final x1 = math.min(c[2], media[2]);
      final y1 = math.min(c[3], media[3]);
      if (x1 > x0 && y1 > y0) crop = [x0, y0, x1, y1];
    }
    final cw = crop[2] - crop[0];
    final ch = crop[3] - crop[1];
    if (cw <= 0 || ch <= 0) return null;
    final rotRaw = inherited(pageRef, '/Rotate');
    var rot = rotRaw is num ? rotRaw.round() : 0;
    rot = ((rot % 360) + 360) % 360;
    rot = ((rot + 45) ~/ 90) * 90 % 360;
    final swapped = rot == 90 || rot == 270;
    final dw = swapped ? ch : cw;
    final dh = swapped ? cw : ch;
    (double, double) norm(double x, double y) {
      final lx = x - crop[0];
      final ly = y - crop[1];
      final (dx, dy) = switch (rot) {
        90 => (ly, lx),
        180 => (cw - lx, ly),
        270 => (ch - ly, cw - lx),
        _ => (lx, ch - ly),
      };
      return (dx / dw, dy / dh);
    }

    final (au, av) = norm(r[0], r[1]);
    final (bu, bv) = norm(r[2], r[3]);
    return Rect.fromLTRB(
      math.min(au, bu),
      math.min(av, bv),
      math.max(au, bu),
      math.max(av, bv),
    );
  }
}

Future<_QpdfJson> _readJson(
  QpdfCliRunner cli,
  String inputPath,
  String? password,
  List<String> keys,
) async {
  final tmp = await Directory.systemTemp.createTemp('ds_form_json_');
  try {
    final out = p.join(tmp.path, 'doc.json');
    await cli.runRaw([
      if (password != null && password.isNotEmpty) '--password=$password',
      '--json-output',
      for (final k in keys) '--json-key=$k',
      inputPath,
      out,
    ]);
    final root =
        jsonDecode(await File(out).readAsString()) as Map<String, dynamic>;
    final q = root['qpdf'];
    final objects = q is List && q.length > 1
        ? Map<String, dynamic>.from(q[1] as Map)
        : <String, dynamic>{};
    final pageRefs = <int, String>{};
    final pages = root['pages'];
    if (pages is List) {
      for (final pg in pages) {
        if (pg is Map && pg['pageposfrom1'] is int && pg['object'] is String) {
          pageRefs[pg['pageposfrom1'] as int] = pg['object'] as String;
        }
      }
    }
    final json = _QpdfJson(objects, pageRefs);
    json._acroform = root['acroform'];
    return json;
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}

extension on _QpdfJson {
  static final _acro = Expando<Object>();
  set _acroform(Object? v) => _acro[this] = v;
  Object? get _acroform => _acro[this];
}

/// Real AcroForm fields of the whole document, assigned to their pages.
///
/// Returns null when qpdf is unavailable or the file has no AcroForm fields.
Future<List<LiveFormField>?> loadLiveFormFields({
  required LocalFileRef file,
  String? password,
}) async {
  if (!await isQpdfCliAvailable()) return null;
  try {
    final doc = await _readJson(QpdfCliRunner(), file.path, password, const [
      'acroform',
      'pages',
    ]);
    final acro = doc._acroform;
    if (acro is! Map || acro['fields'] is! List) return null;
    final out = <LiveFormField>[];
    var i = 0;
    for (final f in acro['fields'] as List) {
      if (f is! Map) continue;
      final page = f['pageposfrom1'];
      final ann = f['annotation'];
      final widgetRef = ann is Map ? ann['object'] : null;
      if (page is! int || widgetRef is! String) continue;
      final pageRef = doc.pageRefs[page];
      if (pageRef == null) continue;
      final type = f['fieldtype'];
      final PdfFormSpotKind kind;
      if (f['ischeckbox'] == true || f['isradiobutton'] == true) {
        kind = PdfFormSpotKind.checkbox;
      } else if (type == '/Sig') {
        kind = PdfFormSpotKind.signature;
      } else if (type == '/Tx' || type == '/Ch') {
        kind = PdfFormSpotKind.text;
      } else {
        continue;
      }
      final annotFlags = ann is Map ? ann['annotationflags'] : null;
      if (annotFlags is int && (annotFlags & 2) != 0) continue;
      final widget = doc.dict(widgetRef);
      final rect = widget == null ? null : doc.box(widget['/Rect']);
      if (rect == null || rect[2] - rect[0] < 2 || rect[3] - rect[1] < 2) {
        continue;
      }
      final norm = doc.displayNorm(pageRef, rect);
      if (norm == null) continue;
      final name = f['fullname'];
      out.add(
        LiveFormField(
          widgetRef: widgetRef,
          spot: PdfFormSpot(
            id: 'acro_${page}_$i',
            name: name is String && name.isNotEmpty ? name : 'Field ${i + 1}',
            kind: kind,
            pdfRect: Rect.fromLTRB(rect[0], rect[1], rect[2], rect[3]),
            normRect: norm,
            pageIndex1Based: page,
          ),
        ),
      );
      i++;
    }
    return out.isEmpty ? null : out;
  } catch (_) {
    return null;
  }
}

/// Removes the given widget annotations from their pages' `/Annots`, so a
/// field whose value was flattened into the page no longer paints on top.
Future<void> removeFormWidgets({
  required String inputPath,
  required String outputPath,
  required Map<int, Set<String>> widgetRefsByPage,
  String? password,
}) async {
  final cli = QpdfCliRunner();
  final doc = await _readJson(cli, inputPath, password, const ['pages']);
  final updates = <String, dynamic>{};
  widgetRefsByPage.forEach((page, refs) {
    final pageRef = doc.pageRefs[page];
    if (pageRef == null || refs.isEmpty) return;
    final pageDict = doc.dict(pageRef);
    if (pageDict == null) return;
    final raw = pageDict['/Annots'];
    final list = doc.resolve(raw);
    if (list is! List) return;
    final kept = [
      for (final e in list)
        if (!refs.contains(e)) e,
    ];
    if (kept.length == list.length) return;
    if (raw is String && _ref.hasMatch(raw)) {
      updates['obj:$raw'] = {'value': kept};
    } else {
      pageDict['/Annots'] = kept;
      updates['obj:$pageRef'] = {'value': pageDict};
    }
  });
  if (updates.isEmpty) {
    await File(inputPath).copy(outputPath);
    return;
  }
  final tmp = await Directory.systemTemp.createTemp('ds_form_upd_');
  try {
    final upd = p.join(tmp.path, 'update.json');
    await File(upd).writeAsString(
      jsonEncode({
        'qpdf': [
          {'jsonversion': 2},
          updates,
        ],
      }),
    );
    await cli.runRaw([
      if (password != null && password.isNotEmpty) '--password=$password',
      inputPath,
      '--update-from-json=$upd',
      outputPath,
    ]);
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}
