import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_builder.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';

/// Resources referenced by a stamp's content (names → objects/refs).
class PdfStampResources {
  PdfStampResources();

  final Map<String, PdfObj> fonts = {};
  final Map<String, PdfObj> xObjects = {};
  final Map<String, PdfObj> extGStates = {};

  PdfDict toDict() => PdfDict({
        if (fonts.isNotEmpty) 'Font': PdfDict(Map.of(fonts)),
        if (xObjects.isNotEmpty) 'XObject': PdfDict(Map.of(xObjects)),
        if (extGStates.isNotEmpty) 'ExtGState': PdfDict(Map.of(extGStates)),
      });
}

/// Burns vector/text/image stamps into page content (watermarks, headers &
/// footers, Bates numbers) as tagged Form XObjects, and finds/removes them
/// again later. Pure Dart; works on every platform.
///
/// Stamp content is written in *display-up* coordinates (display x, y up from
/// the displayed bottom edge, points) and positioned with the page's
/// [PdfPageGeometry.displayUpToUserMatrix], so `/Rotate` and crop boxes are
/// handled once, here.
class PdfPageStamper {
  PdfPageStamper(this.doc);

  final PdfEditDocument doc;
  final Map<PdfImageXObject, PdfRef> _images = {};
  final Map<String, PdfRef> _fonts = {};

  static const _kindKey = 'DSKind';

  /// Adds (once) an image XObject and returns its reference.
  PdfRef addImage(PdfImageXObject image) {
    final existing = _images[image];
    if (existing != null) return existing;
    final dict = image.image.dict.clone();
    if (image.smask != null) dict['SMask'] = doc.addObject(image.smask!);
    final ref = doc.addObject(PdfStream(dict, image.image.data));
    _images[image] = ref;
    return ref;
  }

  /// Shared standard font object reference.
  PdfRef font(PdfStdFont f) =>
      _fonts.putIfAbsent(f.baseFont, () => doc.addObject(f.toFontDict()));

  /// Stamps [content] on [page1]. [kind] identifies the stamp family
  /// (e.g. `Watermark`, `HeaderFooter`) for later detection/removal.
  void stamp(
    int page1, {
    required String kind,
    required Uint8List content,
    required PdfStampResources resources,
    bool behind = false,
  }) {
    final geo = doc.pageGeometry(page1);
    final form = flateStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': PdfArray.nums([0, 0, geo.displayWidth, geo.displayHeight]),
        'Matrix': PdfArray.nums(geo.displayUpToUserMatrix),
        'Resources': resources.toDict(),
        _kindKey: PdfName(kind),
      }),
      content,
    );
    final formRef = doc.addObject(form);

    final page = doc.pageDict(page1).clone();
    final res = (doc.dictOf(doc.inherited(page, 'Resources')) ?? PdfDict())
        .clone();
    final xo = (doc.dictOf(res['XObject']) ?? PdfDict()).clone();
    final prefix = 'DS${kind}_';
    var idx = 1;
    while (xo.containsKey('$prefix$idx')) {
      idx++;
    }
    final name = '$prefix$idx';
    xo[name] = formRef;
    res['XObject'] = xo;
    page['Resources'] = res;

    final artifact = switch (kind) {
      'Watermark' => 'Watermark',
      'HeaderFooter' => 'Header',
      'PageNumbers' => 'Footer',
      _ => 'Watermark',
    };
    final call = PdfContentBuilder()
      ..save()
      ..beginArtifact(artifact)
      ..doXObject(name)
      ..endMarked()
      ..restore();
    final callRef = doc.addObject(
      PdfStream(PdfDict({_kindKey: PdfName(kind)}), call.bytes()),
    );

    final items = _contentItems(page);
    if (behind) {
      items.insert(0, callRef);
    } else {
      final hasWrap = items.any((e) => _kindOf(e) == 'WrapEnd');
      if (!hasWrap) {
        final firstForeground = items.indexWhere((e) {
          final k = _kindOf(e);
          return k == null;
        });
        final qRef = doc.addObject(
          PdfStream(
            PdfDict({_kindKey: const PdfName('Wrap')}),
            Uint8List.fromList(latin1.encode('q\n')),
          ),
        );
        final endRef = doc.addObject(
          PdfStream(
            PdfDict({_kindKey: const PdfName('WrapEnd')}),
            Uint8List.fromList(latin1.encode('\nQ\n')),
          ),
        );
        items.insert(firstForeground < 0 ? items.length : firstForeground, qRef);
        items.add(endRef);
      }
      items.add(callRef);
    }
    page['Contents'] = PdfArray(items);
    doc.setObject(doc.pageRef(page1), page);
  }

  /// Stamp kinds currently present on [page1].
  Set<String> stampKinds(int page1) {
    final page = doc.pageDict(page1);
    return {
      for (final e in _contentItems(page))
        if (_kindOf(e) case final k? when k != 'Wrap' && k != 'WrapEnd') k,
    };
  }

  bool hasStamp(int page1, String kind) => stampKinds(page1).contains(kind);

  /// Removes every stamp of [kind] from [page1]; returns how many.
  int removeStamps(int page1, String kind) {
    final page = doc.pageDict(page1).clone();
    final items = _contentItems(page);
    final before = items.length;
    items.removeWhere((e) => _kindOf(e) == kind);
    final removed = before - items.length;
    if (removed == 0) return 0;
    final stillStamped = items.any((e) {
      final k = _kindOf(e);
      return k != null && k != 'Wrap' && k != 'WrapEnd';
    });
    if (!stillStamped) {
      items.removeWhere((e) {
        final k = _kindOf(e);
        return k == 'Wrap' || k == 'WrapEnd';
      });
    }
    page['Contents'] = PdfArray(items);
    final res = doc.dictOf(doc.inherited(page, 'Resources'))?.clone();
    final xo = doc.dictOf(res?['XObject'])?.clone();
    if (res != null && xo != null) {
      xo.entries.removeWhere((k, _) => k.startsWith('DS${kind}_'));
      res['XObject'] = xo;
      page['Resources'] = res;
    }
    doc.setObject(doc.pageRef(page1), page);
    return removed;
  }

  List<PdfObj> _contentItems(PdfDict page) {
    final raw = page['Contents'];
    if (raw == null) return <PdfObj>[];
    final resolved = doc.resolve(raw);
    if (resolved is PdfArray) return List<PdfObj>.of(resolved.items);
    return <PdfObj>[raw];
  }

  String? _kindOf(PdfObj e) {
    final d = doc.dictOf(e);
    return d?.nameOf(_kindKey);
  }
}
