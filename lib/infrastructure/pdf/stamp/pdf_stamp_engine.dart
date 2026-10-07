import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_layout.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_spec.dart';
import 'package:document_studio/domain/pdf_markup/header_footer/hf_tokens.dart';
import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/domain/pdf_stamp/watermark_layout.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_page_stamper.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';

/// Stamp families written by Document Studio.
abstract final class PdfStampKind {
  static const watermark = 'Watermark';
  static const headerFooter = 'HeaderFooter';
  static const pageNumbers = 'PageNumbers';
}

/// What a PDF already carries, plus the geometry/info needed for layout.
class PdfStampInspection {
  const PdfStampInspection({
    required this.pageSizesPt,
    this.title,
    this.author,
    this.subject,
    this.pagesByKind = const {},
    this.settingsByKind = const {},
  });

  /// Display size (after `/Rotate`, crop box) of every page — equal to
  /// pdfrx `PdfPage.width/height`.
  final List<(double, double)> pageSizesPt;
  final String? title;
  final String? author;
  final String? subject;
  final Map<String, List<int>> pagesByKind;

  /// Last settings JSON stored per stamp kind (header/footer, page numbers).
  final Map<String, String> settingsByKind;

  int get pageCount => pageSizesPt.length;

  List<int> pagesWith(String kind) => pagesByKind[kind] ?? const [];
  bool has(String kind) => pagesWith(kind).isNotEmpty;
}

/// Watermark burn request (all values are isolate-sendable).
class WatermarkStampRequest {
  const WatermarkStampRequest({
    required this.spec,
    required this.pages1Based,
    this.textForPage = const {},
    this.imageBytes,
    this.behind = false,
    this.replaceExisting = false,
  });

  final WatermarkSpec spec;
  final Set<int> pages1Based;

  /// Resolved text (tokens substituted) per page; falls back to spec text.
  final Map<int, String> textForPage;
  final Uint8List? imageBytes;
  final bool behind;
  final bool replaceExisting;
}

/// Pure-Dart stamping for watermarks, headers & footers and page numbers.
///
/// Everything runs in a background isolate on top of [PdfPageStamper], so the
/// output is an incremental update identical on every platform. Geometry is
/// computed by the same domain functions the on-screen previews paint.
abstract final class PdfStampEngine {
  static Future<PdfStampInspection> inspect(Uint8List pdf) =>
      Isolate.run(() => _guard(() => _inspect(_open(pdf))));

  static Future<Uint8List> applyWatermark(
    Uint8List pdf,
    WatermarkStampRequest request,
  ) => Isolate.run(() => _guard(() => _applyWatermark(pdf, request)));

  /// Stamps [spec] as [kind]; always replaces a previous stamp of that kind
  /// (on every page) and stores [spec] in the catalog for later editing.
  static Future<Uint8List> applyHeaderFooter(
    Uint8List pdf, {
    required HeaderFooterSpec spec,
    required HfDocInfo info,
    String kind = PdfStampKind.headerFooter,
    String settingsJson = '',
  }) => Isolate.run(
    () => _guard(() => _applyHeaderFooter(pdf, spec, info, kind, settingsJson)),
  );

  /// Removes every stamp of [kind]; returns the original bytes if none.
  static Future<Uint8List> remove(Uint8List pdf, String kind) =>
      Isolate.run(() => _guard(() => _remove(pdf, kind)));
}

T _guard<T>(T Function() body) {
  try {
    return body();
  } on PdfEditException catch (e) {
    if (e.encrypted) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.passwordRequired,
        message: 'This PDF is encrypted, so it can\'t be stamped.',
        recoveryHint:
            'Remove security first (Tools → Unlock / Remove security), then '
            'try again.',
      );
    }
    throw DocumentStudioError(
      code: DocumentStudioErrorCode.corruptedPdf,
      message: 'Could not edit this PDF: ${e.message}',
      cause: e,
    );
  }
}

PdfEditDocument _open(Uint8List pdf) => PdfEditDocument.open(pdf);

String _catalogKey(String kind) => 'DS${kind}Settings';

String? _infoString(PdfEditDocument doc, String key) {
  final info = doc.dictOf(doc.trailer['Info']);
  final v = doc.resolve(info?[key]);
  if (v is! PdfString) return null;
  final s = v.text.trim();
  return s.isEmpty ? null : s;
}

PdfStampInspection _inspect(PdfEditDocument doc) {
  final stamper = PdfPageStamper(doc);
  final sizes = <(double, double)>[];
  final byKind = <String, List<int>>{};
  for (var p = 1; p <= doc.pageCount; p++) {
    final g = doc.pageGeometry(p);
    sizes.add((g.displayWidth, g.displayHeight));
    for (final k in stamper.stampKinds(p)) {
      (byKind[k] ??= <int>[]).add(p);
    }
  }
  final settings = <String, String>{};
  final catalog = doc.catalog;
  for (final kind in const [
    PdfStampKind.headerFooter,
    PdfStampKind.pageNumbers,
    PdfStampKind.watermark,
  ]) {
    final v = doc.resolve(catalog[_catalogKey(kind)]);
    if (v is PdfString) settings[kind] = v.text;
  }
  return PdfStampInspection(
    pageSizesPt: sizes,
    title: _infoString(doc, 'Title'),
    author: _infoString(doc, 'Author'),
    subject: _infoString(doc, 'Subject'),
    pagesByKind: byKind,
    settingsByKind: settings,
  );
}

void _setCatalogSettings(PdfEditDocument doc, String kind, String? json) {
  final root = doc.trailer['Root'];
  if (root is! PdfRef) return;
  final key = _catalogKey(kind);
  final catalog = doc.catalog;
  if (json == null && !catalog.containsKey(key)) return;
  final next = catalog.clone();
  if (json == null) {
    next.remove(key);
  } else {
    next[key] = PdfString.text(json);
  }
  doc.setObject(root, next);
}

PdfStdFont _stdFont(HfFont f) => PdfStdFont.values.firstWhere(
  (s) => s.baseFont == f.pdfBaseFont,
  orElse: () => PdfStdFont.helvetica,
);

int _removeEverywhere(PdfPageStamper stamper, int pageCount, String kind) {
  var n = 0;
  for (var p = 1; p <= pageCount; p++) {
    if (stamper.hasStamp(p, kind)) n += stamper.removeStamps(p, kind);
  }
  return n;
}

Uint8List _applyWatermark(Uint8List pdf, WatermarkStampRequest req) {
  final doc = _open(pdf);
  final stamper = PdfPageStamper(doc);
  final spec = req.spec;
  PdfRef? imageRef;
  var effective = spec;
  if (spec.isImage) {
    final bytes = req.imageBytes;
    final image = bytes == null ? null : PdfImageXObject.fromEncoded(bytes);
    if (image == null) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Unsupported or corrupt watermark image.',
      );
    }
    imageRef = stamper.addImage(image);
    effective = spec.copyWith(
      imageAspect: image.widthPx / math.max(1, image.heightPx),
    );
  }
  if (req.replaceExisting) {
    _removeEverywhere(stamper, doc.pageCount, PdfStampKind.watermark);
  }
  final fontRef = effective.isImage ? null : stamper.font(_stdFont(spec.font));
  final alpha = effective.clampedOpacity;
  final (r, g, b) = effective.colorRgb;
  var stamped = 0;
  for (final page in req.pages1Based.toList()..sort()) {
    if (page < 1 || page > doc.pageCount) continue;
    final geo = doc.pageGeometry(page);
    final w = geo.displayWidth;
    final h = geo.displayHeight;
    final marks = layoutWatermark(
      spec: effective,
      pageWidthPt: w,
      pageHeightPt: h,
      resolvedText: effective.isImage
          ? ''
          : (req.textForPage[page] ?? effective.text),
    );
    if (marks.isEmpty) continue;
    final res = PdfStampResources();
    res.extGStates['GSw'] = extGStateAlpha(
      fillAlpha: alpha,
      strokeAlpha: alpha,
    );
    final cb = PdfContentBuilder()
      ..save()
      ..gs('GSw');
    if (imageRef != null) {
      res.xObjects['Im0'] = imageRef;
    } else {
      res.fonts['F0'] = fontRef!;
      cb.fillRgb(r, g, b);
    }
    for (final m in marks) {
      final place = Affine2.translate(
        m.centerXNorm * w,
        (1 - m.centerYNorm) * h,
      ).multiply(Affine2.rotate(m.rotationDegrees * math.pi / 180));
      if (imageRef != null) {
        cb
          ..save()
          ..cm(
            place
                .multiply(Affine2.translate(-m.widthPt / 2, -m.heightPt / 2))
                .multiply(Affine2.scale(m.widthPt, m.heightPt)),
          )
          ..doXObject('Im0')
          ..restore();
      } else {
        cb.text(
          'F0',
          m.fontSizePt,
          place.multiply(
            Affine2.translate(m.baselineStartXPt, -m.baselineYDownPt),
          ),
          m.text,
        );
      }
    }
    cb.restore();
    stamper.stamp(
      page,
      kind: PdfStampKind.watermark,
      content: cb.bytes(),
      resources: res,
      behind: req.behind,
    );
    stamped++;
  }
  if (stamped == 0 && !doc.hasChanges) {
    throw const DocumentStudioError(
      code: DocumentStudioErrorCode.invalidFile,
      message: 'Nothing to stamp — check the watermark text and pages.',
    );
  }
  return doc.save();
}

Uint8List _applyHeaderFooter(
  Uint8List pdf,
  HeaderFooterSpec spec,
  HfDocInfo info,
  String kind,
  String settingsJson,
) {
  final doc = _open(pdf);
  final stamper = PdfPageStamper(doc);
  final pageCount = doc.pageCount;
  final docInfo = HfDocInfo(
    fileName: info.fileName,
    pageCount: pageCount,
    title: info.title ?? _infoString(doc, 'Title'),
    author: info.author ?? _infoString(doc, 'Author'),
    subject: info.subject ?? _infoString(doc, 'Subject'),
    now: info.now ?? DateTime.now(),
  );
  _removeEverywhere(stamper, pageCount, kind);
  final bates = hfBatesValues(spec, pageCount);
  final fontRefs = <HfFont, PdfRef>{};
  for (var page = 1; page <= pageCount; page++) {
    final geo = doc.pageGeometry(page);
    final layout = layoutHeaderFooterPage(
      spec: spec,
      doc: docInfo,
      page1Based: page,
      pageWidthPt: geo.displayWidth,
      pageHeightPt: geo.displayHeight,
      batesValue: bates[page],
    );
    if (layout.isEmpty) continue;
    final content = _headerFooterContent(layout, geo, stamper, fontRefs);
    stamper.stamp(page, kind: kind, content: content.$1, resources: content.$2);
  }
  _setCatalogSettings(doc, kind, settingsJson.isEmpty ? null : settingsJson);
  return doc.save();
}

(Uint8List, PdfStampResources) _headerFooterContent(
  HfPageLayout layout,
  PdfPageGeometry geo,
  PdfPageStamper stamper,
  Map<HfFont, PdfRef> fontRefs,
) {
  final h = geo.displayHeight;
  final res = PdfStampResources();
  final cb = PdfContentBuilder()..save();
  final gsNames = <double, String>{};
  void rgb(int c) => cb.fillRgb(
    ((c >> 16) & 0xFF) / 255,
    ((c >> 8) & 0xFF) / 255,
    (c & 0xFF) / 255,
  );
  for (final r in layout.rects) {
    cb.save();
    final a = r.opacity.clamp(0.0, 1.0).toDouble();
    if (a < 0.999) {
      final name = gsNames.putIfAbsent(a, () => 'GS${gsNames.length}');
      res.extGStates[name] = extGStateAlpha(fillAlpha: a, strokeAlpha: a);
      cb.gs(name);
    }
    rgb(r.colorRgb);
    cb
      ..rect(r.leftPt, h - r.topPt - r.heightPt, r.widthPt, r.heightPt)
      ..fill()
      ..restore();
  }
  for (final t in layout.texts) {
    final ref = fontRefs.putIfAbsent(
      t.font,
      () => stamper.font(_stdFont(t.font)),
    );
    final name = 'F${t.font.index}';
    res.fonts[name] = ref;
    rgb(t.colorRgb);
    cb.text(name, t.sizePt, Affine2.translate(t.xPt, h - t.baselinePt), t.text);
  }
  cb.restore();
  return (cb.bytes(), res);
}

Uint8List _remove(Uint8List pdf, String kind) {
  final doc = _open(pdf);
  final stamper = PdfPageStamper(doc);
  _removeEverywhere(stamper, doc.pageCount, kind);
  _setCatalogSettings(doc, kind, null);
  return doc.save();
}
