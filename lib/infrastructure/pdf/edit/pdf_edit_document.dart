import 'dart:convert';
import 'dart:typed_data';

import 'package:document_studio/domain/pdf_markup/pdf_page_geometry.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';

class _XrefEntry {
  const _XrefEntry.offset(this.offset, this.gen)
    : stream = 0,
      index = 0,
      compressed = false;
  const _XrefEntry.compressed(this.stream, this.index)
    : offset = 0,
      gen = 0,
      compressed = true;

  final bool compressed;
  final int offset;
  final int gen;
  final int stream;
  final int index;
}

/// A PDF opened for pure-Dart incremental editing.
///
/// Reads classic and stream cross-reference sections (including object
/// streams), lets callers replace or add objects, and [save]s the result as
/// an incremental update appended to the original bytes. Works identically on
/// every platform (no native engine, no CLI).
class PdfEditDocument {
  PdfEditDocument._(this.bytes);

  /// Parses [bytes]. Throws [PdfEditException] for encrypted or broken files.
  factory PdfEditDocument.open(Uint8List bytes) {
    final doc = PdfEditDocument._(bytes);
    doc._load();
    return doc;
  }

  final Uint8List bytes;
  final Map<int, _XrefEntry> _xref = {};
  final Map<int, PdfObj> _cache = {};
  final Map<int, (List<int> offsets, Uint8List data, int first)> _objStreams =
      {};
  late PdfDict trailer;
  int _startXref = 0;
  bool _xrefIsStream = false;
  bool _reconstructed = false;
  int _size = 0;

  final Map<int, PdfObj> _changed = {};
  List<PdfRef>? _pageRefs;

  bool get isEncrypted => trailer.containsKey('Encrypt');

  // ---------------------------------------------------------------- loading

  void _load() {
    if (bytes.length < 16) throw const PdfEditException('Not a PDF');
    final sx = lastIndexOfBytes(bytes, latin1.encode('startxref'));
    var ok = false;
    if (sx >= 0) {
      final lx = PdfLexer(bytes, sx + 9);
      final off = int.tryParse(lx.readToken());
      if (off != null && off > 0 && off < bytes.length) {
        _startXref = off;
        try {
          _readXrefChain(off);
          ok = _xref.isNotEmpty && trailer.containsKey('Root');
        } catch (_) {
          ok = false;
        }
      }
    }
    if (!ok) _reconstruct();
    if (isEncrypted) {
      throw const PdfEditException('This PDF is encrypted.', encrypted: true);
    }
    final size = trailer['Size'];
    _size = size is PdfNum ? size.i : 0;
    for (final k in _xref.keys) {
      if (k >= _size) _size = k + 1;
    }
  }

  void _readXrefChain(int start) {
    final seen = <int>{};
    int? offset = start;
    PdfDict? newest;
    var first = true;
    while (offset != null && !seen.contains(offset)) {
      seen.add(offset);
      final section = _readXrefSection(offset, isFirst: first);
      first = false;
      newest ??= section;
      final xrefStm = section['XRefStm'];
      if (xrefStm is PdfNum && !seen.contains(xrefStm.i)) {
        seen.add(xrefStm.i);
        _readXrefSection(xrefStm.i, isFirst: false);
      }
      final prev = section['Prev'];
      offset = prev is PdfNum ? prev.i : null;
    }
    trailer = newest ?? PdfDict();
  }

  PdfDict _readXrefSection(int offset, {required bool isFirst}) {
    final lx = PdfLexer(bytes, offset);
    lx.skipWhite();
    final save = lx.pos;
    final tok = lx.readToken();
    if (tok == 'xref') {
      if (isFirst) _xrefIsStream = false;
      while (true) {
        final t = lx.peekToken();
        if (t == 'trailer') {
          lx.readToken();
          break;
        }
        final startNum = int.tryParse(lx.readToken());
        final count = int.tryParse(lx.readToken());
        if (startNum == null || count == null) {
          throw const PdfEditException('Bad xref table');
        }
        for (var i = 0; i < count; i++) {
          final off = int.parse(lx.readToken());
          final gen = int.parse(lx.readToken());
          final kind = lx.readToken();
          final num = startNum + i;
          if (_xref.containsKey(num)) continue;
          if (kind == 'n' && off > 0) {
            _xref[num] = _XrefEntry.offset(off, gen);
          } else {
            _xref[num] = const _XrefEntry.offset(0, -1);
          }
        }
      }
      final t = lx.parse();
      if (t is! PdfDict) throw const PdfEditException('Bad trailer');
      return t;
    }
    lx.pos = save;
    if (isFirst) _xrefIsStream = true;
    final (_, obj) = _parseIndirectAt(offset);
    if (obj is! PdfStream) throw const PdfEditException('Bad xref stream');
    final d = obj.dict;
    final data = decodeStreamData(d, obj.data);
    final w = [for (final e in (d['W'] as PdfArray).items) (e as PdfNum).i];
    final size = (d['Size'] as PdfNum).i;
    final index = d['Index'] is PdfArray
        ? [for (final e in (d['Index'] as PdfArray).items) (e as PdfNum).i]
        : [0, size];
    final rowLen = w.fold<int>(0, (a, b) => a + b);
    var p = 0;
    int field(int width, int def) {
      if (width == 0) return def;
      var v = 0;
      for (var k = 0; k < width; k++) {
        v = (v << 8) | data[p++];
      }
      return v;
    }

    for (var s = 0; s + 1 < index.length; s += 2) {
      final startNum = index[s];
      final count = index[s + 1];
      for (var i = 0; i < count; i++) {
        if (p + rowLen > data.length) break;
        final type = field(w[0], 1);
        final f2 = field(w[1], 0);
        final f3 = field(w[2], 0);
        final num = startNum + i;
        if (_xref.containsKey(num)) continue;
        switch (type) {
          case 1:
            _xref[num] = _XrefEntry.offset(f2, f3);
          case 2:
            _xref[num] = _XrefEntry.compressed(f2, f3);
          default:
            _xref[num] = const _XrefEntry.offset(0, -1);
        }
      }
    }
    return d;
  }

  /// Rebuilds the xref by scanning for `n g obj` headers (damaged files).
  void _reconstruct() {
    _xref.clear();
    _xrefIsStream = false;
    final re = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    final text = latin1.decode(bytes, allowInvalid: true);
    for (final m in re.allMatches(text)) {
      final num = int.parse(m.group(1)!);
      final gen = int.parse(m.group(2)!);
      _xref[num] = _XrefEntry.offset(m.start, gen);
    }
    PdfDict? t;
    var idx = text.lastIndexOf('trailer');
    while (idx >= 0 && t == null) {
      try {
        final parsed = PdfLexer(bytes, idx + 7).parse();
        if (parsed is PdfDict && parsed.containsKey('Root')) t = parsed;
      } catch (_) {}
      idx = idx > 0 ? text.lastIndexOf('trailer', idx - 1) : -1;
    }
    if (t == null) {
      // Look for a catalog object directly.
      for (final num in _xref.keys) {
        final o = getObject(num);
        if (o is PdfDict && o.nameOf('Type') == 'Catalog') {
          t = PdfDict({'Root': PdfRef(num)});
          break;
        }
        if (o is PdfStream && o.dict.nameOf('Type') == 'XRef') {
          if (o.dict.containsKey('Root')) t = o.dict;
        }
      }
    }
    if (t == null) throw const PdfEditException('Could not read this PDF');
    trailer = t;
    _startXref = 0;
    _reconstructed = true;
  }

  (PdfRef, PdfObj) _parseIndirectAt(int offset) {
    final lx = PdfLexer(bytes, offset);
    final n = int.tryParse(lx.readToken());
    final g = int.tryParse(lx.readToken());
    final kw = lx.readToken();
    if (n == null || g == null || kw != 'obj') {
      throw PdfEditException('Bad object at $offset');
    }
    final obj = lx.parse();
    lx.skipWhite();
    final save = lx.pos;
    if (obj is PdfDict && lx.readToken() == 'stream') {
      var p = lx.pos;
      if (p < bytes.length && bytes[p] == 0x0d) p++;
      if (p < bytes.length && bytes[p] == 0x0a) p++;
      var len = -1;
      final lenObj = obj['Length'];
      if (lenObj is PdfNum) {
        len = lenObj.i;
      } else if (lenObj is PdfRef) {
        final r = _resolveNoStream(lenObj);
        if (r is PdfNum) len = r.i;
      }
      final valid =
          len >= 0 && p + len <= bytes.length && _looksLikeEndstream(p + len);
      if (!valid) {
        final end = indexOfBytes(bytes, latin1.encode('endstream'), p);
        if (end < 0) throw const PdfEditException('Unterminated stream');
        var e = end;
        if (e > p && bytes[e - 1] == 0x0a) e--;
        if (e > p && bytes[e - 1] == 0x0d) e--;
        len = e - p;
      }
      return (
        PdfRef(n, g),
        PdfStream(obj, Uint8List.sublistView(bytes, p, p + len)),
      );
    }
    lx.pos = save;
    return (PdfRef(n, g), obj);
  }

  bool _looksLikeEndstream(int p) {
    final lx = PdfLexer(bytes, p);
    return lx.readToken() == 'endstream';
  }

  PdfObj? _resolveNoStream(PdfRef r) {
    final o = getObject(r.num);
    return o is PdfRef ? null : o;
  }

  /// Returns the current (possibly edited) object [num], or null when free.
  PdfObj? getObject(int num) {
    final changed = _changed[num];
    if (changed != null) return changed;
    final cached = _cache[num];
    if (cached != null) return cached;
    final e = _xref[num];
    if (e == null) return null;
    PdfObj? obj;
    try {
      if (e.compressed) {
        obj = _readFromObjStream(e.stream, e.index, num);
      } else if (e.gen >= 0 && e.offset > 0) {
        obj = _parseIndirectAt(e.offset).$2;
      }
    } catch (_) {
      obj = null;
    }
    if (obj != null) _cache[num] = obj;
    return obj;
  }

  PdfObj? _readFromObjStream(int streamNum, int index, int num) {
    var entry = _objStreams[streamNum];
    if (entry == null) {
      final s = getObject(streamNum);
      if (s is! PdfStream) return null;
      final data = decodeStreamData(s.dict, s.data);
      final n = (s.dict['N'] as PdfNum).i;
      final first = (s.dict['First'] as PdfNum).i;
      final lx = PdfLexer(data);
      final offsets = <int>[];
      for (var i = 0; i < n; i++) {
        lx.readToken();
        offsets.add(int.parse(lx.readToken()));
      }
      entry = (offsets, data, first);
      _objStreams[streamNum] = entry;
    }
    final (offsets, data, first) = entry;
    if (index >= offsets.length) return null;
    return PdfLexer(data, first + offsets[index]).parse();
  }

  /// Follows references until a direct object.
  PdfObj? resolve(PdfObj? o) {
    var cur = o;
    for (var i = 0; i < 32 && cur is PdfRef; i++) {
      cur = getObject(cur.num);
    }
    return cur is PdfRef ? null : cur;
  }

  PdfDict? dictOf(PdfObj? o) {
    final r = resolve(o);
    if (r is PdfDict) return r;
    if (r is PdfStream) return r.dict;
    return null;
  }

  double? numOf(PdfObj? o) {
    final r = resolve(o);
    return r is PdfNum ? r.d : null;
  }

  // ------------------------------------------------------------------ pages

  PdfDict get catalog {
    final c = dictOf(trailer['Root']);
    if (c == null) throw const PdfEditException('Missing catalog');
    return c;
  }

  List<PdfRef> get pageRefs => _pageRefs ??= _collectPages();

  int get pageCount => pageRefs.length;

  List<PdfRef> _collectPages() {
    final out = <PdfRef>[];
    final seen = <int>{};
    void walk(PdfObj? node, int depth) {
      if (depth > 64 || node is! PdfRef || !seen.add(node.num)) return;
      final d = dictOf(node);
      if (d == null) return;
      final kids = resolve(d['Kids']);
      final type = d.nameOf('Type');
      if (type == 'Page' || (type == null && kids == null)) {
        out.add(node);
        return;
      }
      if (kids is PdfArray) {
        for (final k in kids.items) {
          walk(k, depth + 1);
        }
      }
    }

    walk(catalog['Pages'], 0);
    return out;
  }

  PdfRef pageRef(int page1) {
    if (page1 < 1 || page1 > pageCount) {
      throw PdfEditException('Page $page1 not found');
    }
    return pageRefs[page1 - 1];
  }

  PdfDict pageDict(int page1) {
    final d = dictOf(pageRef(page1));
    if (d == null) throw PdfEditException('Page $page1 is damaged');
    return d;
  }

  /// Page attribute including inherited `/Parent` values.
  PdfObj? inherited(PdfDict page, String key) {
    PdfDict? node = page;
    for (var i = 0; node != null && i < 64; i++) {
      if (node.containsKey(key)) return resolve(node[key]);
      node = dictOf(node['Parent']);
    }
    return null;
  }

  List<double>? _box(PdfObj? raw) {
    final v = resolve(raw);
    if (v is! PdfArray || v.length < 4) return null;
    final n = <double>[];
    for (final e in v.items.take(4)) {
      final d = numOf(e);
      if (d == null) return null;
      n.add(d);
    }
    final l = n[0] < n[2] ? n[0] : n[2];
    final r = n[0] < n[2] ? n[2] : n[0];
    final b = n[1] < n[3] ? n[1] : n[3];
    final t = n[1] < n[3] ? n[3] : n[1];
    if (r - l <= 0 || t - b <= 0) return null;
    return [l, b, r, t];
  }

  /// Effective crop box + normalized `/Rotate` of [page1].
  PdfPageGeometry pageGeometry(int page1) {
    final page = pageDict(page1);
    final media = _box(inherited(page, 'MediaBox')) ?? [0, 0, 612, 792];
    var crop = media;
    final c = _box(inherited(page, 'CropBox'));
    if (c != null) {
      final x0 = c[0] > media[0] ? c[0] : media[0];
      final y0 = c[1] > media[1] ? c[1] : media[1];
      final x1 = c[2] < media[2] ? c[2] : media[2];
      final y1 = c[3] < media[3] ? c[3] : media[3];
      if (x1 > x0 && y1 > y0) crop = [x0, y0, x1, y1];
    }
    final rot = numOf(inherited(page, 'Rotate'))?.round() ?? 0;
    return PdfPageGeometry(
      cropLeft: crop[0],
      cropBottom: crop[1],
      cropWidth: crop[2] - crop[0],
      cropHeight: crop[3] - crop[1],
      rotate: rot,
    );
  }

  // ---------------------------------------------------------------- editing

  /// Replaces object [ref] in the next incremental update.
  void setObject(PdfRef ref, PdfObj obj) {
    _changed[ref.num] = obj;
    _cache.remove(ref.num);
    if (ref.num >= _size) _size = ref.num + 1;
  }

  /// Adds a new indirect object and returns its reference.
  PdfRef addObject(PdfObj obj) {
    final ref = PdfRef(_size++);
    _changed[ref.num] = obj;
    return ref;
  }

  bool get hasChanges => _changed.isNotEmpty;

  /// Object numbers present in the cross-reference table (excluding 0).
  Iterable<int> get liveObjectNumbers => _xref.keys.where((n) => n > 0);

  /// Generation number for [num], or `0` for compressed / unknown entries.
  int generationOf(int num) {
    final e = _xref[num];
    if (e == null || e.compressed || e.gen < 0) return 0;
    return e.gen;
  }

  /// Next free object number (does not allocate).
  int get nextObjectNumber => _size;

  /// Replaces or creates the trailer `/Info` dictionary fields.
  ///
  /// Empty string values remove the key. Returns the Info object reference.
  PdfRef writeInfoFields(Map<String, String> fields) {
    PdfDict info;
    PdfRef ref;
    final existing = trailer['Info'];
    if (existing is PdfRef) {
      ref = existing;
      final cur = dictOf(existing);
      info = cur?.clone() ?? PdfDict();
    } else if (existing is PdfDict) {
      info = existing.clone();
      ref = addObject(info);
      trailer['Info'] = ref;
    } else {
      info = PdfDict();
      ref = addObject(info);
      trailer['Info'] = ref;
    }
    for (final e in fields.entries) {
      if (e.value.isEmpty) {
        info.remove(e.key);
      } else {
        info[e.key] = PdfString.text(e.value);
      }
    }
    setObject(ref, info);
    return ref;
  }

  /// Clears trailer `/Info` and catalog `/Metadata` (XMP).
  void stripDocumentMetadata() {
    trailer.remove('Info');
    final cat = catalog.clone();
    if (cat.containsKey('Metadata')) {
      cat.remove('Metadata');
      final root = trailer['Root'];
      if (root is PdfRef) {
        setObject(root, cat);
      }
    }
  }

  /// Page `/Annots` entries (resolved dicts) paired with their references.
  List<(PdfRef? ref, PdfDict dict)> annotations(int page1) {
    final page = pageDict(page1);
    final arr = resolve(page['Annots']);
    if (arr is! PdfArray) return const [];
    final out = <(PdfRef?, PdfDict)>[];
    for (final e in arr.items) {
      final d = dictOf(e);
      if (d != null) out.add((e is PdfRef ? e : null, d));
    }
    return out;
  }

  /// Rewrites the page's `/Annots` array (always inline in the page dict).
  void setPageAnnots(int page1, List<PdfObj> annots) {
    final ref = pageRef(page1);
    final page = pageDict(page1).clone();
    if (annots.isEmpty) {
      page.remove('Annots');
    } else {
      page['Annots'] = PdfArray(List<PdfObj>.of(annots));
    }
    setObject(ref, page);
  }

  /// Raw `/Annots` items (references or inline dicts).
  List<PdfObj> pageAnnotItems(int page1) {
    final arr = resolve(pageDict(page1)['Annots']);
    return arr is PdfArray ? List<PdfObj>.of(arr.items) : <PdfObj>[];
  }

  /// Serializes the incremental update. Returns the original bytes when
  /// nothing changed.
  Uint8List save() {
    if (_changed.isEmpty) return bytes;
    final sink = PdfWriterSink();
    sink.bytes(bytes);
    final last = bytes.isEmpty ? 0x0a : bytes[bytes.length - 1];
    if (last != 0x0a && last != 0x0d) sink.raw('\n');
    final offsets = <int, int>{};
    final nums = _changed.keys.toList()..sort();
    for (final n in nums) {
      offsets[n] = sink.length;
      final gen = _genFor(n);
      sink.raw('$n $gen obj\n');
      sink.obj(_changed[n]!);
      sink.raw('\nendobj\n');
    }
    final newTrailer = PdfDict({
      'Size': PdfNum(_size),
      'Root': trailer['Root']!,
      if (trailer['Info'] != null) 'Info': trailer['Info']!,
      if (trailer['ID'] != null) 'ID': trailer['ID']!,
      if (_startXref > 0) 'Prev': PdfNum(_startXref),
    });
    final xrefOffset = sink.length;
    if (_xrefIsStream) {
      final xrefNum = _size;
      offsets[xrefNum] = xrefOffset;
      final all = [...nums, xrefNum];
      final rows = BytesBuilder();
      final index = <int>[];
      var i = 0;
      while (i < all.length) {
        var j = i;
        while (j + 1 < all.length && all[j + 1] == all[j] + 1) {
          j++;
        }
        index
          ..add(all[i])
          ..add(j - i + 1);
        for (var k = i; k <= j; k++) {
          final off = offsets[all[k]]!;
          final gen = all[k] == xrefNum ? 0 : _genFor(all[k]);
          rows.add([
            1,
            (off >> 24) & 0xff,
            (off >> 16) & 0xff,
            (off >> 8) & 0xff,
            off & 0xff,
            (gen >> 8) & 0xff,
            gen & 0xff,
          ]);
        }
        i = j + 1;
      }
      final d = newTrailer.clone()
        ..['Type'] = const PdfName('XRef')
        ..['Size'] = PdfNum(xrefNum + 1)
        ..['W'] = PdfArray.nums([1, 4, 2])
        ..['Index'] = PdfArray.nums(index);
      sink.raw('$xrefNum 0 obj\n');
      sink.obj(PdfStream(d, rows.toBytes()));
      sink.raw('\nendobj\n');
    } else {
      final sb = StringBuffer('xref\n');
      var i = 0;
      final all = nums;
      if (_reconstructed) {
        // No valid prior xref: list every original object too.
        for (final e in _xref.entries) {
          if (offsets.containsKey(e.key)) continue;
          if (e.value.compressed || e.value.gen < 0) continue;
          offsets[e.key] = e.value.offset;
          all.add(e.key);
        }
        all.sort();
      }
      if (!all.contains(0)) sb.write('0 1\n0000000000 65535 f\r\n');
      while (i < all.length) {
        var j = i;
        while (j + 1 < all.length && all[j + 1] == all[j] + 1) {
          j++;
        }
        sb.write('${all[i]} ${j - i + 1}\n');
        for (var k = i; k <= j; k++) {
          final off = offsets[all[k]]!.toString().padLeft(10, '0');
          final gen = _genFor(all[k]).toString().padLeft(5, '0');
          sb.write('$off $gen n\r\n');
        }
        i = j + 1;
      }
      sink.raw(sb.toString());
      sink.raw('trailer\n');
      sink.obj(newTrailer);
      sink.raw('\n');
    }
    sink.raw('startxref\n$xrefOffset\n%%EOF\n');
    return sink.take();
  }

  int _genFor(int num) {
    final e = _xref[num];
    if (e == null || e.compressed || e.gen < 0) return 0;
    return e.gen;
  }
}
