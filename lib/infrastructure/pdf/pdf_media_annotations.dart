import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:flutter/painting.dart';

enum PdfMediaKind { video, audio, richMedia, threeD }

/// A multimedia annotation on a page (video / audio / rich media / 3D).
///
/// PDFium draws only the poster appearance stream and never plays media, so
/// the viewer overlays a play badge on [normRect] and hands [extract] output
/// to the system player.
class PdfMediaAnnotation {
  PdfMediaAnnotation({
    required this.page,
    required this.normRect,
    required this.kind,
    required this.fileName,
    this.uri,
    this.stream,
    bool? embedded,
  }) : embedded = embedded ?? stream != null;

  final int page;

  /// Normalized (0..1), top-left origin, displayed orientation.
  final Rect normRect;
  final PdfMediaKind kind;
  final String fileName;

  /// External media (rendition `/URL`) when nothing is embedded.
  final Uri? uri;
  final PdfStream? stream;

  /// True when playable bytes exist inside the PDF (even if [stream] was
  /// stripped to cross an isolate boundary).
  final bool embedded;

  bool get canPlay => embedded || uri != null;

  /// Copy without the (possibly huge) stream, safe to send between isolates.
  PdfMediaAnnotation stripped() => PdfMediaAnnotation(
    page: page,
    normRect: normRect,
    kind: kind,
    fileName: fileName,
    uri: uri,
    embedded: embedded,
  );

  /// Decoded embedded bytes, or null when the media is external / unsupported.
  Uint8List? extract() {
    final s = stream;
    if (s == null) return null;
    try {
      return decodeStreamData(s.dict, s.data);
    } catch (_) {
      return null;
    }
  }
}

/// Finds multimedia annotations on [page1] of [bytes]. Never throws.
List<PdfMediaAnnotation> readPdfMediaAnnotations(Uint8List bytes, int page1) {
  try {
    final doc = PdfEditDocument.open(bytes);
    if (page1 < 1 || page1 > doc.pageCount) return const [];
    return _read(doc, page1);
  } catch (_) {
    return const [];
  }
}

/// Page numbers that carry multimedia annotations, so the viewer only builds
/// overlays where they exist.
Set<int> pdfPagesWithMedia(Uint8List bytes) {
  final out = <int>{};
  try {
    final doc = PdfEditDocument.open(bytes);
    for (var p = 1; p <= doc.pageCount; p++) {
      if (_read(doc, p).isNotEmpty) out.add(p);
    }
  } catch (_) {}
  return out;
}

List<PdfMediaAnnotation> _read(PdfEditDocument doc, int page1) {
  final page = doc.pageDict(page1);
  final annots = doc.resolve(page['Annots']);
  if (annots is! PdfArray) return const [];
  final geom = doc.pageGeometry(page1);
  final out = <PdfMediaAnnotation>[];
  for (final item in annots.items) {
    final a = doc.dictOf(item);
    if (a == null) continue;
    final sub = a.nameOf('Subtype');
    final kind = switch (sub) {
      'Screen' || 'Movie' => PdfMediaKind.video,
      'Sound' => PdfMediaKind.audio,
      'RichMedia' => PdfMediaKind.richMedia,
      '3D' => PdfMediaKind.threeD,
      _ => null,
    };
    if (kind == null) continue;
    final rect = doc.resolve(a['Rect']);
    if (rect is! PdfArray || rect.length < 4) continue;
    final nums = [for (final e in rect.items.take(4)) doc.numOf(e) ?? 0.0];
    final r = geom.userRectToDisplay(nums);
    final norm = Rect.fromLTRB(
      r.left / geom.displayWidth,
      r.top / geom.displayHeight,
      r.right / geom.displayWidth,
      r.bottom / geom.displayHeight,
    );
    final media = _findMedia(doc, a, sub!);
    out.add(
      PdfMediaAnnotation(
        page: page1,
        normRect: norm,
        kind: media.$3 ?? kind,
        fileName: media.$1 ?? 'media',
        stream: media.$2,
        uri: media.$4,
      ),
    );
  }
  return out;
}

/// (file name, embedded stream, kind override, external uri)
(String?, PdfStream?, PdfMediaKind?, Uri?) _findMedia(
  PdfEditDocument doc,
  PdfDict annot,
  String subtype,
) {
  (String?, PdfStream?) fromFileSpec(PdfObj? spec) {
    final fs = doc.dictOf(spec);
    if (fs == null) return (null, null);
    final ef = doc.dictOf(fs['EF']);
    final f = doc.resolve(ef?['F'] ?? ef?['UF']);
    final nameObj = doc.resolve(fs['UF'] ?? fs['F']);
    final name = nameObj is PdfString ? nameObj.text : null;
    return (name, f is PdfStream ? f : null);
  }

  switch (subtype) {
    case 'Movie':
      final movie = doc.dictOf(annot['Movie']);
      final r = fromFileSpec(movie?['F']);
      return (r.$1, r.$2, null, null);
    case 'RichMedia':
      final content = doc.dictOf(annot['RichMediaContent']);
      final assets = doc.dictOf(content?['Assets']);
      final names = doc.resolve(assets?['Names']);
      if (names is PdfArray) {
        for (var i = 0; i + 1 < names.length; i += 2) {
          final n = doc.resolve(names[i]);
          final nm = n is PdfString ? n.text : '';
          final r = fromFileSpec(names[i + 1]);
          if (r.$2 != null && _looksLikeMedia(nm)) {
            return (nm, r.$2, null, null);
          }
        }
      }
      return (null, null, PdfMediaKind.richMedia, null);
    case 'Screen':
      final action = doc.dictOf(annot['A']);
      final rendition = doc.dictOf(action?['R']);
      final clip = doc.dictOf(rendition?['C']);
      final data = doc.resolve(clip?['D']);
      if (data is PdfDict) {
        final r = fromFileSpec(data);
        if (r.$2 != null) return (r.$1, r.$2, null, null);
        final fsName = doc.resolve(data['F']);
        if (fsName is PdfString) {
          final u = Uri.tryParse(fsName.text);
          if (u != null && u.hasScheme && u.scheme.startsWith('http')) {
            return (fsName.text, null, null, u);
          }
        }
      }
      return (null, null, null, null);
    default:
      return (null, null, null, null);
  }
}

bool _looksLikeMedia(String name) {
  final n = name.toLowerCase();
  return const [
    '.mp4',
    '.m4v',
    '.mov',
    '.avi',
    '.wmv',
    '.webm',
    '.mkv',
    '.mpg',
    '.mpeg',
    '.mp3',
    '.wav',
    '.m4a',
    '.ogg',
    '.flv',
    '.swf',
  ].any(n.endsWith);
}

/// Media annotations of every page, without embedded bytes (isolate safe).
Map<int, List<PdfMediaAnnotation>> indexPdfMedia(Uint8List bytes) {
  final out = <int, List<PdfMediaAnnotation>>{};
  try {
    final doc = PdfEditDocument.open(bytes);
    for (var p = 1; p <= doc.pageCount; p++) {
      final found = _read(doc, p);
      if (found.isNotEmpty) out[p] = [for (final a in found) a.stripped()];
    }
  } catch (_) {}
  return out;
}
