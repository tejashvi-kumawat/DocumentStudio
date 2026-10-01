import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/domain/models/local_file_ref.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/pdf_page_box_options.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

/// Fraction of the page the viewer is showing (after `/Rotate`).
///
/// Origin is the top-left of that visible page; y grows downward. Values are
/// 0–1. Mapping onto each page's CropBox hides the outside; it does not
/// delete content streams.
class PdfVisibleFraction {
  const PdfVisibleFraction({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  bool get isUsable =>
      right - left > 0.01 && bottom - top > 0.01;
}

/// On-device CropBox / MediaBox edits (Android and desktop without qpdf).
///
/// Sets page boxes with [PdfEditDocument]. Content streams stay in the file;
/// a tighter CropBox hides the area outside the rectangle. Encrypted inputs
/// are unlocked with PDFium first, then edited the same way.
///
/// Desktop keeps the qpdf CLI when the binary exists
/// (`CompositePdfStructureAdapter` prefers qpdf, then this editor).
class DartPdfPageBox {
  DartPdfPageBox._();

  /// Insets CropBox by [margin] on [pageNumbers1Based]. A zero margin copies
  /// the file unchanged.
  static Future<LocalFileRef> cropPages({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropMarginPreset margin,
    required String outputPath,
    String? password,
  }) {
    if (margin.marginMm <= 0) {
      return _copyFile(input, outputPath);
    }
    final marginPt = margin.marginMm * 72 / 25.4;
    return _apply(
      input: input,
      outputPath: outputPath,
      password: password,
      pages: pageNumbers1Based,
      edit: (doc, page, _) {
        final media = _referenceBox(doc, page);
        final box = PdfCropRectPt(
          llx: media.llx + marginPt,
          lly: media.lly + marginPt,
          urx: media.urx - marginPt,
          ury: media.ury - marginPt,
        );
        if (box.width <= 1 || box.height <= 1) {
          throw const DocumentStudioError(
            code: DocumentStudioErrorCode.invalidPdf,
            message: 'The margin is larger than the page.',
          );
        }
        _writeBox(page, 'CropBox', box);
      },
    );
  }

  /// CropBox for [pageNumber1Based] from a display-space [fraction].
  ///
  /// Uses that page's visible box and `/Rotate`. Does not write the file.
  static Future<PdfCropRectPt> boxForVisibleFraction({
    required LocalFileRef input,
    required int pageNumber1Based,
    required PdfVisibleFraction fraction,
    String? password,
  }) async {
    final shared = await sharedBoxForVisibleFraction(
      input: input,
      pageNumbers1Based: {pageNumber1Based},
      fraction: fraction,
      password: password,
    );
    return shared!;
  }

  /// The CropBox every selected page would get, or null when those rectangles
  /// differ. Each page is measured from its own visible box and `/Rotate`.
  /// Does not write the file.
  static Future<PdfCropRectPt?> sharedBoxForVisibleFraction({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfVisibleFraction fraction,
    String? password,
  }) async {
    if (pageNumbers1Based.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Select at least one page.',
      );
    }
    if (!fraction.isUsable) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Crop rectangle is too small.',
      );
    }
    final raw = await File(input.path).readAsBytes();
    final doc = await _open(Uint8List.fromList(raw), password);
    PdfCropRectPt? first;
    for (final n in pageNumbers1Based) {
      _requirePage(doc, n);
      final box = _fractionToBox(doc, n, fraction);
      if (first == null) {
        first = box;
      } else if (!_sameBox(first, box)) {
        return null;
      }
    }
    return first;
  }

  static bool _sameBox(PdfCropRectPt a, PdfCropRectPt b) {
    const epsilon = 0.05;
    return (a.llx - b.llx).abs() < epsilon &&
        (a.lly - b.lly).abs() < epsilon &&
        (a.urx - b.urx).abs() < epsilon &&
        (a.ury - b.ury).abs() < epsilon;
  }

  /// Sets CropBox on each selected page to [fraction] of that page's visible
  /// box. Content streams and MediaBox stay; the tighter CropBox only hides
  /// the area outside the rectangle.
  static Future<LocalFileRef> cropVisibleFraction({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfVisibleFraction fraction,
    required String outputPath,
    String? password,
  }) {
    if (!fraction.isUsable) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Crop rectangle is too small.',
      );
    }
    return _apply(
      input: input,
      outputPath: outputPath,
      password: password,
      pages: pageNumbers1Based,
      edit: (doc, page, page1) {
        _writeBox(page, 'CropBox', _fractionToBox(doc, page1, fraction));
      },
    );
  }

  /// Sets CropBox on [pageNumbers1Based] to [box] (PDF points, origin
  /// bottom-left). Same rectangle the crop UI already collects.
  static Future<LocalFileRef> cropPagesToBox({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfCropRectPt box,
    required String outputPath,
    String? password,
  }) {
    if (box.width <= 1 || box.height <= 1) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Crop rectangle is too small.',
      );
    }
    return _apply(
      input: input,
      outputPath: outputPath,
      password: password,
      pages: pageNumbers1Based,
      edit: (_, page, _) {
        _writeBox(page, 'CropBox', box);
      },
    );
  }

  /// Sets MediaBox and CropBox to [paperSize] (origin at 0,0). Content is
  /// not scaled.
  static Future<LocalFileRef> setPageSize({
    required LocalFileRef input,
    required Set<int> pageNumbers1Based,
    required PdfPaperSize paperSize,
    required String outputPath,
    String? password,
  }) {
    final (w, h) = paperSize.mediaBoxPt;
    final box = PdfCropRectPt(llx: 0, lly: 0, urx: w, ury: h);
    return _apply(
      input: input,
      outputPath: outputPath,
      password: password,
      pages: pageNumbers1Based,
      edit: (_, page, _) {
        _writeBox(page, 'MediaBox', box);
        _writeBox(page, 'CropBox', box);
      },
    );
  }

  static Future<LocalFileRef> _apply({
    required LocalFileRef input,
    required String outputPath,
    required String? password,
    required Set<int> pages,
    required void Function(PdfEditDocument doc, PdfDict page, int page1) edit,
  }) async {
    if (pages.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Select at least one page.',
      );
    }
    final raw = await File(input.path).readAsBytes();
    final doc = await _open(Uint8List.fromList(raw), password);
    for (final n in pages) {
      _requirePage(doc, n);
      final dict = doc.pageDict(n).clone();
      edit(doc, dict, n);
      doc.setObject(doc.pageRef(n), dict);
    }
    final out = doc.save();
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(outputPath).writeAsBytes(out, flush: true);
    final stat = await File(outputPath).stat();
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
    );
  }

  static void _requirePage(PdfEditDocument doc, int page1) {
    if (page1 < 1 || page1 > doc.pageCount) {
      throw DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Page $page1 is outside this document.',
      );
    }
  }

  /// Display-space fraction → CropBox in user space for this page only.
  static PdfCropRectPt _fractionToBox(
    PdfEditDocument doc,
    int page1,
    PdfVisibleFraction fraction,
  ) {
    final geo = doc.pageGeometry(page1);
    final display = Rect.fromLTRB(
      fraction.left.clamp(0, 1) * geo.displayWidth,
      fraction.top.clamp(0, 1) * geo.displayHeight,
      fraction.right.clamp(0, 1) * geo.displayWidth,
      fraction.bottom.clamp(0, 1) * geo.displayHeight,
    );
    final user = geo.displayRectToUser(display);
    final box = PdfCropRectPt(
      llx: user[0],
      lly: user[1],
      urx: user[2],
      ury: user[3],
    );
    if (box.width <= 1 || box.height <= 1) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidPdf,
        message: 'Crop rectangle is too small.',
      );
    }
    return box;
  }

  static PdfCropRectPt _referenceBox(PdfEditDocument doc, PdfDict page) {
    return _rect(doc, doc.inherited(page, 'MediaBox')) ??
        _rect(doc, doc.inherited(page, 'CropBox')) ??
        const PdfCropRectPt(llx: 0, lly: 0, urx: 612, ury: 792);
  }

  static PdfCropRectPt? _rect(PdfEditDocument doc, PdfObj? raw) {
    final v = doc.resolve(raw);
    if (v is! PdfArray || v.length < 4) return null;
    final n = <double>[];
    for (final e in v.items.take(4)) {
      final d = doc.numOf(e);
      if (d == null) return null;
      n.add(d);
    }
    final llx = math.min(n[0], n[2]);
    final urx = math.max(n[0], n[2]);
    final lly = math.min(n[1], n[3]);
    final ury = math.max(n[1], n[3]);
    if (urx - llx <= 0 || ury - lly <= 0) return null;
    return PdfCropRectPt(llx: llx, lly: lly, urx: urx, ury: ury);
  }

  static void _writeBox(PdfDict page, String key, PdfCropRectPt box) {
    final llx = math.min(box.llx, box.urx);
    final urx = math.max(box.llx, box.urx);
    final lly = math.min(box.lly, box.ury);
    final ury = math.max(box.lly, box.ury);
    page[key] = PdfArray.nums([llx, lly, urx, ury]);
  }

  static Future<PdfEditDocument> _open(Uint8List input, String? password) async {
    try {
      return PdfEditDocument.open(input);
    } on PdfEditException catch (e) {
      if (!e.encrypted && (password == null || password.isEmpty)) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.invalidPdf,
          message: 'Could not edit page boxes in this PDF.',
          cause: e,
        );
      }
      try {
        final unlocked = await _unlockWithPdfrx(input, password);
        return PdfEditDocument.open(unlocked);
      } on PdfEditException catch (again) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.invalidPdf,
          message: 'Could not edit page boxes in this PDF.',
          cause: again,
        );
      }
    }
  }

  static Future<Uint8List> _unlockWithPdfrx(
    Uint8List input,
    String? password,
  ) async {
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

  static Future<LocalFileRef> _copyFile(
    LocalFileRef input,
    String outputPath,
  ) async {
    await Directory(p.dirname(outputPath)).create(recursive: true);
    final bytes = await File(input.path).readAsBytes();
    await File(outputPath).writeAsBytes(bytes, flush: true);
    final stat = await File(outputPath).stat();
    return LocalFileRef(
      path: outputPath,
      displayName: p.basename(outputPath),
      sizeBytes: stat.size,
      lastModified: stat.modified,
    );
  }
}
