import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_stream.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';

/// Draws page 1 of [overlayPdf] (built in display-up coordinates at the
/// target page's displayed size) on top of page [page1] of [target], plus
/// optional filled [covers] (display-space rects, normalized) underneath it.
///
/// Pure Dart and incremental: the overlay becomes a form XObject and one
/// small content stream is appended — the rest of the file is untouched, so
/// it costs milliseconds instead of a qpdf rewrite of the whole document.
Uint8List? stampOverlayOnPage(
  Uint8List target,
  int page1,
  Uint8List? overlayPdf, {
  List<Rect> covers = const [],
  (double, double, double) coverRgb = (1, 1, 1),
}) {
  try {
    final doc = PdfEditDocument.open(target);
    final geo = doc.pageGeometry(page1);
    final dw = geo.displayWidth, dh = geo.displayHeight;
    final body = StringBuffer();
    if (covers.isNotEmpty) {
      final (r, g, b) = coverRgb;
      body.write('q ${formatMatrix([r, g, b])} rg\n');
      for (final c in covers) {
        // Normalized display (y down) → display-up points.
        body.write(
          '${formatMatrix([c.left * dw, (1 - c.bottom) * dh, c.width * dw, c.height * dh])} re\n',
        );
      }
      body.write('f Q\n');
    }
    PdfObj? resources;
    if (overlayPdf != null) {
      final o = PdfEditDocument.open(overlayPdf);
      final content = readPageContent(o, 1);
      if (content == null) return null;
      body.write(latin1.decode(content));
      final res = o.resolve(o.pageDict(1)['Resources']);
      if (res != null) resources = _copy(o, doc, res, {});
    }
    final form = flateStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': PdfArray.nums([0, 0, dw, dh]),
        'Matrix': PdfArray.nums(geo.displayUpToUserMatrix),
        'Resources': ?resources,
      }),
      Uint8List.fromList(latin1.encode(body.toString())),
    );
    final formRef = doc.addObject(form);
    final name = 'DsOv${formRef.num}';

    final pageRef = doc.pageRef(page1);
    final page = doc.pageDict(page1).clone();
    final res = (doc.dictOf(doc.inherited(page, 'Resources')) ?? PdfDict())
        .clone();
    final xo = (doc.dictOf(res['XObject']) ?? PdfDict()).clone();
    xo[name] = formRef;
    res['XObject'] = xo;
    page['Resources'] = res;

    // Existing content is wrapped in q … Q so a CTM it leaves behind cannot
    // shift the stamp.
    final pre = doc.addObject(flateStream(PdfDict(), Uint8List.fromList(latin1.encode('q\n'))));
    final post = doc.addObject(
      flateStream(PdfDict(), Uint8List.fromList(latin1.encode('\nQ q /$name Do Q\n'))),
    );
    final old = page['Contents'];
    final oldItems = switch (doc.resolve(old)) {
      PdfArray a => a.items,
      null => const <PdfObj>[],
      _ => [old!],
    };
    page['Contents'] = PdfArray([pre, ...oldItems, post]);
    doc.setObject(pageRef, page);
    return doc.save();
  } catch (_) {
    return null;
  }
}

/// Deep copy of [o] from [src] into [dst] (indirect objects re-numbered).
PdfObj _copy(
  PdfEditDocument src,
  PdfEditDocument dst,
  PdfObj o,
  Map<int, PdfRef> done,
) {
  switch (o) {
    case PdfRef r:
      final seen = done[r.num];
      if (seen != null) return seen;
      final placeholder = dst.addObject(const PdfNull());
      done[r.num] = placeholder;
      final v = src.getObject(r.num);
      dst.setObject(placeholder, v == null ? const PdfNull() : _copy(src, dst, v, done));
      return placeholder;
    case PdfArray a:
      return PdfArray([for (final i in a.items) _copy(src, dst, i, done)]);
    case PdfDict d:
      return PdfDict({
        for (final e in d.entries.entries) e.key: _copy(src, dst, e.value, done),
      });
    case PdfStream s:
      final d = _copy(src, dst, s.dict, done) as PdfDict;
      return PdfStream(d, s.data);
    default:
      return o;
  }
}
