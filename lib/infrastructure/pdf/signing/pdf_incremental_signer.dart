
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_visual_stamp_writer.dart';

/// An AcroForm signature field widget (/FT /Sig) found in a PDF.
class PdfSignatureFieldInfo {
  const PdfSignatureFieldInfo({
    required this.name,
    required this.fieldObj,
    required this.widgetObj,
    required this.pageIndex1Based,
    required this.normLeft,
    required this.normTop,
    required this.normRight,
    required this.normBottom,
    required this.widthPt,
    required this.heightPt,
    required this.signed,
    required this.visible,
  });

  final String name;

  /// Object numbers of the terminal field and its widget annotation.
  final int fieldObj;
  final int widgetObj;
  final int pageIndex1Based;

  /// Box on the displayed (rotated, cropped) page, top-left origin, 0–1.
  final double normLeft;
  final double normTop;
  final double normRight;
  final double normBottom;

  /// Displayed size in points.
  final double widthPt;
  final double heightPt;
  final bool signed;

  /// False for invisible (zero-size or hidden) signature widgets.
  final bool visible;

  String get id => '$fieldObj/$widgetObj';
}

/// Where a new digital signature goes.
class PdfSignatureTarget {
  /// Signs an existing empty signature field.
  const PdfSignatureTarget.field(PdfSignatureFieldInfo this.field)
    : page1Based = 0,
      left = 0,
      top = 0,
      width = 0,
      height = 0;

  /// Creates a new visible field on the displayed page (normalized box).
  const PdfSignatureTarget.newField({
    required this.page1Based,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  }) : field = null;

  final PdfSignatureFieldInfo? field;
  final int page1Based;
  final double left;
  final double top;
  final double width;
  final double height;

  bool get isNewField => field == null;
}

class PdfSignDetails {
  const PdfSignDetails({
    required this.signingTime,
    this.name,
    this.reason,
    this.location,
    this.contactInfo,
    this.appearancePng,
  });

  final DateTime signingTime;
  final String? name;
  final String? reason;
  final String? location;
  final String? contactInfo;

  /// Visible appearance drawn into the widget box (null = invisible look).
  final Uint8List? appearancePng;
}

/// Lists signature fields and applies PAdES / CAdES detached signatures as
/// incremental updates (pure Dart; earlier signatures stay valid).
class PdfIncrementalSigner {
  PdfIncrementalSigner();

  static const int defaultReserveBytes = 24 * 1024;

  Future<List<PdfSignatureFieldInfo>> listSignatureFields(
    String path, {
    String? password,
  }) async {
    final bytes = await File(path).readAsBytes();
    return runIsolated(listSignatureFieldsSync, bytes);
  }

  static List<PdfSignatureFieldInfo> listSignatureFieldsSync(Uint8List pdf) {
    try {
      final doc = PdfCosDocument.parse(pdf);
      if (doc.isEncrypted) return const [];
      return _SigFieldScanner(doc).scan();
    } catch (_) {
      return const [];
    }
  }

  /// Signs [input] with [cms] (callback receives the ByteRange data).
  Future<Uint8List> sign({
    required Uint8List input,
    required PdfSignatureTarget target,
    required PdfSignDetails details,
    required Future<Uint8List> Function(Uint8List signedData) cms,
    String subFilter = 'ETSI.CAdES.detached',
    int reserveBytes = defaultReserveBytes,
  }) async {
    final prepared = await runIsolated(_prepareEntry, (
      input,
      target,
      details,
      subFilter,
      reserveBytes,
    ));
    final pdf = prepared.bytes;
    final signedData = Uint8List(prepared.range[1] + prepared.range[3])
      ..setRange(0, prepared.range[1], pdf)
      ..setRange(
        prepared.range[1],
        prepared.range[1] + prepared.range[3],
        pdf,
        prepared.range[2],
      );
    final signature = await cms(signedData);
    if (signature.length > reserveBytes) {
      if (reserveBytes < 256 * 1024) {
        return sign(
          input: input,
          target: target,
          details: details,
          cms: cms,
          subFilter: subFilter,
          reserveBytes: signature.length + 4096,
        );
      }
      throw StateError('Signature is too large (${signature.length} bytes).');
    }
    final hex = StringBuffer();
    for (final b in signature) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    final hexBytes = ascii.encode(hex.toString());
    pdf.setRange(
      prepared.contentsHexStart,
      prepared.contentsHexStart + hexBytes.length,
      hexBytes,
    );
    return pdf;
  }
}

class _Prepared {
  _Prepared(this.bytes, this.range, this.contentsHexStart);
  final Uint8List bytes;
  final List<int> range;
  final int contentsHexStart;
}

_Prepared _prepareEntry(
  (Uint8List, PdfSignatureTarget, PdfSignDetails, String, int) a,
) => _prepare(a.$1, a.$2, a.$3, a.$4, a.$5);

_Prepared _prepare(
  Uint8List input,
  PdfSignatureTarget target,
  PdfSignDetails details,
  String subFilter,
  int reserveBytes,
) {
  final doc = PdfCosDocument.parse(input);
  if (doc.isEncrypted) throw PdfEncryptedException();
  final w = PdfIncrementalWriter(doc);
  final pages = doc.pages;

  final sigRef = w.allocate();
  const brPlaceholder = '[0 0000000000 0000000000 0000000000]';
  final contentsPlaceholder = '<${'0' * (reserveBytes * 2)}>';
  final sig = PdfDict({
    'Type': const PdfName('Sig'),
    'Filter': const PdfName('Adobe.PPKLite'),
    'SubFilter': PdfName(subFilter),
    'ByteRange': const PdfRaw(brPlaceholder),
    'Contents': PdfRaw(contentsPlaceholder),
    'M': PdfString(ascii.encode(_pdfDate(details.signingTime))),
    if (details.name?.trim().isNotEmpty == true)
      'Name': PdfString.text(details.name!.trim()),
    if (details.reason?.trim().isNotEmpty == true)
      'Reason': PdfString.text(details.reason!.trim()),
    if (details.location?.trim().isNotEmpty == true)
      'Location': PdfString.text(details.location!.trim()),
    if (details.contactInfo?.trim().isNotEmpty == true)
      'ContactInfo': PdfString.text(details.contactInfo!.trim()),
    'Prop_Build': PdfDict({
      'App': PdfDict({'Name': const PdfName('Document_Studio')}),
    }),
  });
  w.put(sigRef, sig);

  // AcroForm (indirect or inline in the catalog).
  final catalog = doc.catalog;
  final acroObj = catalog['AcroForm'];
  final acro = doc.resolveDict(acroObj)?.clone() ?? PdfDict();
  final fieldsObj = doc.resolve(acro['Fields']);
  final fields = PdfArray([if (fieldsObj is PdfArray) ...fieldsObj.items]);
  acro['SigFlags'] = const PdfNum(3);

  PdfCosPage page;
  double boxW, boxH;
  final field = target.field;
  if (field != null) {
    final fieldRef = PdfRef(field.fieldObj);
    final widgetRef = PdfRef(field.widgetObj);
    final fieldDict = doc.resolveDict(fieldRef)?.clone();
    final widgetDict = field.widgetObj == field.fieldObj
        ? fieldDict
        : doc.resolveDict(widgetRef)?.clone();
    if (fieldDict == null || widgetDict == null) {
      throw PdfCosException('Signature field not found');
    }
    if (fieldDict.has('V') && doc.resolve(fieldDict['V']) is PdfDict) {
      throw PdfCosException('This signature field is already signed.');
    }
    page = pages[(field.pageIndex1Based - 1).clamp(0, pages.length - 1)];
    boxW = field.widthPt;
    boxH = field.heightPt;
    fieldDict['V'] = sigRef;
    if (!widgetDict.has('P')) widgetDict['P'] = page.ref;
    final ap = _appearance(w, page, boxW, boxH, details.appearancePng);
    widgetDict['AP'] = PdfDict({'N': ap});
    // Print, and lock the widget like Acrobat does once signed.
    final flags = (doc.resolve(widgetDict['F']) is PdfNum)
        ? (doc.resolve(widgetDict['F']) as PdfNum).i
        : 0;
    widgetDict['F'] = PdfNum((flags | 4 | 128) & ~2);
    w.put(fieldRef, fieldDict);
    if (field.widgetObj != field.fieldObj) w.put(widgetRef, widgetDict);
    if (!_containsRef(fields, fieldRef) && !_hasParent(doc, fieldDict)) {
      fields.items.add(fieldRef);
    }
  } else {
    if (target.page1Based < 1 || target.page1Based > pages.length) {
      throw PdfCosException('Page ${target.page1Based} does not exist');
    }
    page = pages[target.page1Based - 1];
    final pw = page.displayWidth, ph = page.displayHeight;
    boxW = target.width * pw;
    boxH = target.height * ph;
    final m = displayToUserMatrix(page);
    final (ax, ay) = m.apply(target.left * pw, target.top * ph);
    final (bx, by) = m.apply(
      (target.left + target.width) * pw,
      (target.top + target.height) * ph,
    );
    final rect = PdfArray([
      PdfNum(ax < bx ? ax : bx),
      PdfNum(ay < by ? ay : by),
      PdfNum(ax < bx ? bx : ax),
      PdfNum(ay < by ? by : ay),
    ]);
    final names = _SigFieldScanner(doc).allFieldNames();
    var n = 1;
    while (names.contains('Signature$n')) {
      n++;
    }
    final widgetRef = w.allocate();
    final ap = _appearance(w, page, boxW, boxH, details.appearancePng);
    w.put(
      widgetRef,
      PdfDict({
        'Type': const PdfName('Annot'),
        'Subtype': const PdfName('Widget'),
        'FT': const PdfName('Sig'),
        'T': PdfString.text('Signature$n'),
        'F': const PdfNum(132),
        'Rect': rect,
        'P': page.ref,
        'V': sigRef,
        'AP': PdfDict({'N': ap}),
      }),
    );
    fields.items.add(widgetRef);
    // Append the widget to the page's /Annots.
    final annotsObj = page.dict['Annots'];
    final annots = doc.resolve(annotsObj);
    final list = PdfArray([if (annots is PdfArray) ...annots.items, widgetRef]);
    if (annotsObj is PdfRef && annots is PdfArray) {
      w.put(annotsObj, list);
    } else {
      w.put(page.ref, page.dict.clone()..['Annots'] = list);
    }
  }
  acro['Fields'] = fields;
  if (acroObj is PdfRef && doc.resolve(acroObj) is PdfDict) {
    w.put(acroObj, acro);
  } else {
    final rootRef = doc.rootRef;
    if (rootRef == null) throw PdfCosException('PDF catalog is not indirect');
    w.put(rootRef, catalog.clone()..['AcroForm'] = acro);
  }

  final out = w.build();
  // Locate placeholders inside the appended update only.
  final from = doc.bytes.length;
  final brAt = pdfIndexOf(out, ascii.encode(brPlaceholder), from);
  final cAt = pdfIndexOf(out, ascii.encode(contentsPlaceholder), from);
  if (brAt < 0 || cAt < 0) {
    throw PdfCosException('Could not prepare the signature dictionary');
  }
  final a = cAt;
  final b = cAt + contentsPlaceholder.length;
  final range = [0, a, b, out.length - b];
  String pad(int v) => v.toString().padLeft(10);
  final br = '[0 ${pad(range[1])} ${pad(range[2])} ${pad(range[3])}]';
  if (br.length != brPlaceholder.length) {
    throw PdfCosException('Document too large to sign');
  }
  out.setRange(brAt, brAt + br.length, ascii.encode(br));
  return _Prepared(out, range, cAt + 1);
}

bool _containsRef(PdfArray arr, PdfRef ref) =>
    arr.items.any((e) => e is PdfRef && e.num == ref.num);

bool _hasParent(PdfCosDocument doc, PdfDict d) => d.has('Parent');

/// Appearance form XObject sized to the displayed box, counter-rotated so it
/// reads upright on rotated pages.
PdfRef _appearance(
  PdfIncrementalWriter w,
  PdfCosPage page,
  double boxW,
  double boxH,
  Uint8List? png,
) {
  final matrix = switch (page.rotate) {
    90 => [0, 1, -1, 0, boxH, 0],
    180 => [-1, 0, 0, -1, boxW, boxH],
    270 => [0, -1, 1, 0, 0, boxW],
    _ => [1, 0, 0, 1, 0, 0],
  };
  final resources = PdfDict();
  var content = '';
  if (png != null) {
    final img = addPngImageXObject(w, png);
    resources['XObject'] = PdfDict({'Img': img});
    content = 'q ${pdfNumber(boxW)} 0 0 ${pdfNumber(boxH)} 0 0 cm /Img Do Q\n';
  }
  return w.add(
    PdfStream(
      PdfDict({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': PdfArray([
          const PdfNum(0),
          const PdfNum(0),
          PdfNum(boxW),
          PdfNum(boxH),
        ]),
        'Matrix': PdfArray([for (final v in matrix) PdfNum(v)]),
        'Resources': resources,
      }),
      Uint8List.fromList(content.codeUnits),
    ),
  );
}

String _pdfDate(DateTime dt) {
  final l = dt.toLocal();
  String p(int n) => n.toString().padLeft(2, '0');
  final off = l.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final oh = p(off.inHours.abs());
  final om = p(off.inMinutes.abs() % 60);
  return 'D:${l.year}${p(l.month)}${p(l.day)}${p(l.hour)}${p(l.minute)}'
      "${p(l.second)}$sign$oh'$om'";
}

/// Walks AcroForm fields and page annotations for signature widgets.
class _SigFieldScanner {
  _SigFieldScanner(this.doc);
  final PdfCosDocument doc;

  Set<String> allFieldNames() {
    final out = <String>{};
    final acro = doc.resolveDict(doc.catalog['AcroForm']);
    final fields = doc.resolve(acro?['Fields']);
    final seen = <int>{};
    void walk(PdfObj o, String prefix) {
      if (o is! PdfRef || !seen.add(o.num)) return;
      final d = doc.resolveDict(o);
      if (d == null) return;
      final t = doc.resolve(d['T']);
      final name = t is PdfString
          ? (prefix.isEmpty ? t.text : '$prefix.${t.text}')
          : prefix;
      if (name.isNotEmpty) out.add(name);
      final kids = doc.resolve(d['Kids']);
      if (kids is PdfArray) {
        for (final k in kids.items) {
          walk(k, name);
        }
      }
    }

    if (fields is PdfArray) {
      for (final f in fields.items) {
        walk(f, '');
      }
    }
    return out;
  }

  List<PdfSignatureFieldInfo> scan() {
    final pages = doc.pages;
    final pageOfAnnot = <int, int>{};
    for (var i = 0; i < pages.length; i++) {
      final annots = doc.resolve(pages[i].dict['Annots']);
      if (annots is! PdfArray) continue;
      for (final a in annots.items) {
        if (a is PdfRef) pageOfAnnot[a.num] = i + 1;
      }
    }
    final out = <PdfSignatureFieldInfo>[];
    final seenWidgets = <int>{};

    void addWidget({
      required int fieldNum,
      required PdfDict fieldDict,
      required int widgetNum,
      required PdfDict widget,
      required String name,
    }) {
      if (!seenWidgets.add(widgetNum)) return;
      var page1 = pageOfAnnot[widgetNum] ?? 0;
      final p = widget['P'];
      if (page1 == 0 && p is PdfRef) page1 = doc.pageIndexOf(p);
      if (page1 == 0) return;
      final page = pages[page1 - 1];
      final rect = doc.resolve(widget['Rect']);
      var l = 0.0, t = 0.0, r = 0.0, b = 0.0;
      var visible = false;
      if (rect is PdfArray && rect.length >= 4) {
        final v = [for (final x in rect.items.take(4)) doc.resolve(x)];
        if (v.every((e) => e is PdfNum)) {
          final n = v.map((e) => (e as PdfNum).d).toList();
          final (x1, y1) = userToDisplay(page, n[0], n[1]);
          final (x2, y2) = userToDisplay(page, n[2], n[3]);
          final pw = page.displayWidth, ph = page.displayHeight;
          l = (x1 < x2 ? x1 : x2) / pw;
          r = (x1 < x2 ? x2 : x1) / pw;
          t = (y1 < y2 ? y1 : y2) / ph;
          b = (y1 < y2 ? y2 : y1) / ph;
          final flags = doc.resolve(widget['F']);
          final hidden = flags is PdfNum && (flags.i & 2) != 0;
          visible = !hidden && (r - l) * pw > 2 && (b - t) * ph > 2;
        }
      }
      final pw = page.displayWidth, ph = page.displayHeight;
      out.add(
        PdfSignatureFieldInfo(
          name: name,
          fieldObj: fieldNum,
          widgetObj: widgetNum,
          pageIndex1Based: page1,
          normLeft: l.clamp(0.0, 1.0),
          normTop: t.clamp(0.0, 1.0),
          normRight: r.clamp(0.0, 1.0),
          normBottom: b.clamp(0.0, 1.0),
          widthPt: (r - l) * pw,
          heightPt: (b - t) * ph,
          signed: doc.resolve(fieldDict['V']) is PdfDict,
          visible: visible,
        ),
      );
    }

    final acro = doc.resolveDict(doc.catalog['AcroForm']);
    final fields = doc.resolve(acro?['Fields']);
    final seen = <int>{};
    void walk(PdfObj o, String prefix, String? inheritedFt) {
      if (o is! PdfRef || !seen.add(o.num)) return;
      final d = doc.resolveDict(o);
      if (d == null) return;
      final ft = d.nameOf('FT') ?? inheritedFt;
      final t = doc.resolve(d['T']);
      final name = t is PdfString
          ? (prefix.isEmpty ? t.text : '$prefix.${t.text}')
          : prefix;
      final kids = doc.resolve(d['Kids']);
      final kidFields = <PdfRef>[];
      final kidWidgets = <PdfRef>[];
      if (kids is PdfArray) {
        for (final k in kids.items) {
          if (k is! PdfRef) continue;
          final kd = doc.resolveDict(k);
          if (kd == null) continue;
          if (kd.has('T') || kd.has('FT')) {
            kidFields.add(k);
          } else {
            kidWidgets.add(k);
          }
        }
      }
      for (final k in kidFields) {
        walk(k, name, ft);
      }
      if (ft != 'Sig') return;
      if (kidWidgets.isNotEmpty) {
        for (final k in kidWidgets) {
          addWidget(
            fieldNum: o.num,
            fieldDict: d,
            widgetNum: k.num,
            widget: doc.resolveDict(k)!,
            name: name,
          );
        }
      } else if (kidFields.isEmpty) {
        addWidget(
          fieldNum: o.num,
          fieldDict: d,
          widgetNum: o.num,
          widget: d,
          name: name.isEmpty ? 'Signature' : name,
        );
      }
    }

    if (fields is PdfArray) {
      for (final f in fields.items) {
        walk(f, '', null);
      }
    }
    // Orphan widgets not reachable from /Fields.
    for (final e in pageOfAnnot.entries) {
      if (seenWidgets.contains(e.key)) continue;
      final d = doc.resolveDict(PdfRef(e.key));
      if (d == null || d.nameOf('Subtype') != 'Widget') continue;
      var fieldDict = d;
      var fieldNum = e.key;
      var ft = d.nameOf('FT');
      final parent = d['Parent'];
      if (ft == null && parent is PdfRef) {
        final pd = doc.resolveDict(parent);
        ft = pd?.nameOf('FT');
        if (pd != null) {
          fieldDict = pd;
          fieldNum = parent.num;
        }
      }
      if (ft != 'Sig') continue;
      final t = doc.resolve(fieldDict['T']);
      addWidget(
        fieldNum: fieldNum,
        fieldDict: fieldDict,
        widgetNum: e.key,
        widget: d,
        name: t is PdfString ? t.text : 'Signature',
      );
    }
    out.sort((a, b) {
      final p = a.pageIndex1Based.compareTo(b.pageIndex1Based);
      if (p != 0) return p;
      return a.normTop.compareTo(b.normTop);
    });
    return out;
  }
}
