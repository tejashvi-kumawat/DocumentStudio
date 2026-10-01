import 'dart:convert';
import 'dart:io' show ZLibCodec, ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';

/// Minimal pure-Dart PDF object model (COS): parse objects through classic
/// xref tables, xref streams and object streams, and append incremental
/// updates. Used for signing and burning signatures/stamps on every platform.

abstract class PdfObj {
  const PdfObj();
}

class PdfNull extends PdfObj {
  const PdfNull();
}

class PdfBool extends PdfObj {
  const PdfBool(this.value);
  final bool value;
}

class PdfNum extends PdfObj {
  const PdfNum(this.value);
  final num value;
  double get d => value.toDouble();
  int get i => value.toInt();
}

class PdfName extends PdfObj {
  const PdfName(this.name);
  final String name;
  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

class PdfString extends PdfObj {
  PdfString(this.bytes, {this.hex = false});
  PdfString.text(String s, {this.hex = false}) : bytes = _encodeTextString(s);
  final Uint8List bytes;
  final bool hex;

  /// Decodes PDFDocEncoding / UTF-16BE text strings.
  String get text {
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return latin1.decode(bytes);
  }

  static Uint8List _encodeTextString(String s) {
    final ascii = s.codeUnits.every((c) => c < 0x7F);
    if (ascii) return Uint8List.fromList(s.codeUnits);
    final out = <int>[0xFE, 0xFF];
    for (final c in s.codeUnits) {
      out
        ..add(c >> 8)
        ..add(c & 0xFF);
    }
    return Uint8List.fromList(out);
  }
}

class PdfArray extends PdfObj {
  PdfArray([List<PdfObj>? items]) : items = items ?? <PdfObj>[];
  final List<PdfObj> items;
  int get length => items.length;
  PdfObj operator [](int i) => items[i];
}

class PdfDict extends PdfObj {
  PdfDict([Map<String, PdfObj>? map]) : map = map ?? <String, PdfObj>{};
  final Map<String, PdfObj> map;

  PdfObj? operator [](String key) => map[key];
  void operator []=(String key, PdfObj value) => map[key] = value;
  bool has(String key) => map.containsKey(key);
  void remove(String key) => map.remove(key);

  String? nameOf(String key) {
    final v = map[key];
    return v is PdfName ? v.name : null;
  }

  PdfDict clone() => PdfDict(Map<String, PdfObj>.from(map));
}

class PdfRef extends PdfObj {
  const PdfRef(this.num, [this.gen = 0]);
  final int num;
  final int gen;
  @override
  bool operator ==(Object other) =>
      other is PdfRef && other.num == num && other.gen == gen;
  @override
  int get hashCode => Object.hash(num, gen);
  @override
  String toString() => '$num $gen R';
}

class PdfStream extends PdfObj {
  PdfStream(this.dict, this.raw);
  final PdfDict dict;

  /// Encoded stream bytes (as stored in the file).
  final Uint8List raw;
}

/// Pre-serialized token written verbatim (signature placeholders).
class PdfRaw extends PdfObj {
  const PdfRaw(this.text);
  final String text;
}

class PdfCosException implements Exception {
  PdfCosException(this.message);
  final String message;
  @override
  String toString() => message;
}

class PdfEncryptedException extends PdfCosException {
  PdfEncryptedException()
    : super(
        'This PDF is encrypted. Remove its password protection first, '
        'then sign or stamp it.',
      );
}

// ---------------------------------------------------------------------------
// Lexer / parser

bool _isWs(int c) =>
    c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09 || c == 0x0C || c == 0x00;

bool _isDelim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3C ||
    c == 0x3E ||
    c == 0x5B ||
    c == 0x5D ||
    c == 0x7B ||
    c == 0x7D ||
    c == 0x2F ||
    c == 0x25;

class _Keyword extends PdfObj {
  const _Keyword(this.word);
  final String word;
}

class PdfParser {
  PdfParser(this.data, [this.pos = 0]);
  final Uint8List data;
  int pos;

  bool get atEnd => pos >= data.length;

  void skipWs() {
    while (pos < data.length) {
      final c = data[pos];
      if (_isWs(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < data.length && data[pos] != 0x0A && data[pos] != 0x0D) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  String _readRegular() {
    final start = pos;
    while (pos < data.length && !_isWs(data[pos]) && !_isDelim(data[pos])) {
      pos++;
    }
    return latin1.decode(data.sublist(start, pos));
  }

  PdfObj _token() {
    skipWs();
    if (atEnd) throw PdfCosException('Unexpected end of PDF data');
    final c = data[pos];
    switch (c) {
      case 0x2F: // /
        pos++;
        return PdfName(_readName());
      case 0x28: // (
        pos++;
        return _readLiteralString();
      case 0x3C: // <
        if (pos + 1 < data.length && data[pos + 1] == 0x3C) {
          pos += 2;
          return const _Keyword('<<');
        }
        pos++;
        return _readHexString();
      case 0x3E:
        if (pos + 1 < data.length && data[pos + 1] == 0x3E) {
          pos += 2;
          return const _Keyword('>>');
        }
        pos++;
        return const _Keyword('>');
      case 0x5B:
        pos++;
        return const _Keyword('[');
      case 0x5D:
        pos++;
        return const _Keyword(']');
      case 0x7B:
      case 0x7D:
        pos++;
        return _Keyword(String.fromCharCode(c));
    }
    final word = _readRegular();
    if (word.isEmpty) {
      pos++;
      return const _Keyword('');
    }
    final n = num.tryParse(word);
    if (n != null) return PdfNum(n);
    if (word.startsWith('.') || word.startsWith('-.')) {
      final m = num.tryParse(word.replaceFirst('.', '0.'));
      if (m != null) return PdfNum(m);
    }
    switch (word) {
      case 'true':
        return const PdfBool(true);
      case 'false':
        return const PdfBool(false);
      case 'null':
        return const PdfNull();
    }
    return _Keyword(word);
  }

  String _readName() {
    final out = <int>[];
    while (pos < data.length && !_isWs(data[pos]) && !_isDelim(data[pos])) {
      final c = data[pos];
      if (c == 0x23 && pos + 2 < data.length) {
        final h = int.tryParse(
          latin1.decode(data.sublist(pos + 1, pos + 3)),
          radix: 16,
        );
        if (h != null) {
          out.add(h);
          pos += 3;
          continue;
        }
      }
      out.add(c);
      pos++;
    }
    return utf8.decode(out, allowMalformed: true);
  }

  PdfString _readLiteralString() {
    final out = <int>[];
    var depth = 1;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x5C) {
        if (pos >= data.length) break;
        final e = data[pos++];
        switch (e) {
          case 0x6E:
            out.add(0x0A);
          case 0x72:
            out.add(0x0D);
          case 0x74:
            out.add(0x09);
          case 0x62:
            out.add(0x08);
          case 0x66:
            out.add(0x0C);
          case 0x0D:
            if (pos < data.length && data[pos] == 0x0A) pos++;
          case 0x0A:
            break;
          default:
            if (e >= 0x30 && e <= 0x37) {
              var v = e - 0x30;
              for (var k = 0; k < 2; k++) {
                if (pos < data.length &&
                    data[pos] >= 0x30 &&
                    data[pos] <= 0x37) {
                  v = v * 8 + (data[pos++] - 0x30);
                }
              }
              out.add(v & 0xFF);
            } else {
              out.add(e);
            }
        }
        continue;
      }
      if (c == 0x28) depth++;
      if (c == 0x29) {
        depth--;
        if (depth == 0) break;
      }
      out.add(c);
    }
    return PdfString(Uint8List.fromList(out));
  }

  PdfString _readHexString() {
    final digits = <int>[];
    while (pos < data.length && data[pos] != 0x3E) {
      final c = data[pos++];
      final v = _hexVal(c);
      if (v >= 0) digits.add(v);
    }
    pos++; // >
    if (digits.length.isOdd) digits.add(0);
    final out = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = (digits[i * 2] << 4) | digits[i * 2 + 1];
    }
    return PdfString(out, hex: true);
  }

  static int _hexVal(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x37;
    if (c >= 0x61 && c <= 0x66) return c - 0x57;
    return -1;
  }

  /// Parses one object; resolves `n g R` into [PdfRef].
  PdfObj parseObject() {
    final t = _token();
    return _complete(t);
  }

  PdfObj _complete(PdfObj t) {
    if (t is _Keyword) {
      switch (t.word) {
        case '<<':
          final dict = PdfDict();
          while (true) {
            final k = _token();
            if (k is _Keyword && k.word == '>>') break;
            if (k is! PdfName) {
              if (atEnd) break;
              continue;
            }
            final v = parseObject();
            if (v is _Keyword && v.word == '>>') {
              dict[k.name] = const PdfNull();
              break;
            }
            dict[k.name] = v;
          }
          return dict;
        case '[':
          final arr = PdfArray();
          while (true) {
            final save = pos;
            final k = _token();
            if (k is _Keyword && k.word == ']') break;
            if (atEnd && k is _Keyword) break;
            pos = save;
            arr.items.add(parseObject());
          }
          return arr;
      }
      return t;
    }
    if (t is PdfNum && t.value is int) {
      final save = pos;
      try {
        final t2 = _token();
        if (t2 is PdfNum && t2.value is int) {
          final t3 = _token();
          if (t3 is _Keyword && t3.word == 'R') {
            return PdfRef(t.i, t2.i);
          }
        }
      } catch (_) {}
      pos = save;
    }
    return t;
  }

  bool matchKeyword(String word) {
    final save = pos;
    skipWs();
    final w = _readRegular();
    if (w == word) return true;
    pos = save;
    return false;
  }
}

// ---------------------------------------------------------------------------
// Filters

Uint8List pdfInflate(Uint8List raw, {int? maxOutputBytes}) {
  if (maxOutputBytes != null) {
    return _pdfInflateCapped(raw, maxOutputBytes);
  }
  try {
    return Uint8List.fromList(ZLibDecoder().convert(raw));
  } catch (_) {
    // Tolerate truncated / trailing-garbage streams.
    final out = <int>[];
    final sink = ZLibDecoder().startChunkedConversion(
      ByteConversionSink.withCallback(out.addAll),
    );
    try {
      sink.add(raw);
      sink.close();
    } catch (_) {}
    if (out.isEmpty) rethrow;
    return Uint8List.fromList(out);
  }
}

/// Inflates [raw] and throws [PdfCosException] once output passes [maxOutputBytes].
Uint8List _pdfInflateCapped(Uint8List raw, int maxOutputBytes) {
  final out = BytesBuilder(copy: false);
  var total = 0;
  final sink = ZLibDecoder().startChunkedConversion(
    ByteConversionSink.withCallback((chunk) {
      total += chunk.length;
      if (total > maxOutputBytes) {
        throw PdfCosException('Stream expands beyond the size limit');
      }
      out.add(chunk);
    }),
  );
  try {
    sink.add(raw);
    sink.close();
  } on PdfCosException {
    rethrow;
  } catch (_) {
    if (total > maxOutputBytes) {
      throw PdfCosException('Stream expands beyond the size limit');
    }
    if (out.isEmpty) {
      throw PdfCosException('Could not decompress the stream');
    }
  }
  return out.toBytes();
}

Uint8List pdfDeflate(List<int> data) =>
    Uint8List.fromList(ZLibCodec(level: 6).encode(data));

Uint8List _unpredict(Uint8List data, PdfDict? parms) {
  if (parms == null) return data;
  final predictor = (parms['Predictor'] as PdfNum?)?.i ?? 1;
  if (predictor < 10) return data;
  final colors = (parms['Colors'] as PdfNum?)?.i ?? 1;
  final bpc = (parms['BitsPerComponent'] as PdfNum?)?.i ?? 8;
  final columns = (parms['Columns'] as PdfNum?)?.i ?? 1;
  final bpp = math.max(1, (colors * bpc + 7) ~/ 8);
  final rowLen = (colors * bpc * columns + 7) ~/ 8;
  final out = BytesBuilder(copy: false);
  var prev = Uint8List(rowLen);
  var i = 0;
  while (i + 1 + rowLen <= data.length) {
    final type = data[i];
    final row = Uint8List.fromList(data.sublist(i + 1, i + 1 + rowLen));
    for (var x = 0; x < rowLen; x++) {
      final left = x >= bpp ? row[x - bpp] : 0;
      final up = prev[x];
      final upLeft = x >= bpp ? prev[x - bpp] : 0;
      switch (type) {
        case 1:
          row[x] = (row[x] + left) & 0xFF;
        case 2:
          row[x] = (row[x] + up) & 0xFF;
        case 3:
          row[x] = (row[x] + ((left + up) >> 1)) & 0xFF;
        case 4:
          final p = left + up - upLeft;
          final pa = (p - left).abs();
          final pb = (p - up).abs();
          final pc = (p - upLeft).abs();
          final pr = (pa <= pb && pa <= pc) ? left : (pb <= pc ? up : upLeft);
          row[x] = (row[x] + pr) & 0xFF;
      }
    }
    out.add(row);
    prev = row;
    i += 1 + rowLen;
  }
  return out.toBytes();
}

// ---------------------------------------------------------------------------
// Document

class _XrefEntry {
  const _XrefEntry.offset(this.offset, this.gen) : stream = -1, index = -1;
  const _XrefEntry.compressed(this.stream, this.index) : offset = -1, gen = 0;
  final int offset;
  final int gen;
  final int stream;
  final int index;
  bool get isCompressed => stream >= 0;
}

/// One page of the document with inherited attributes resolved.
class PdfCosPage {
  PdfCosPage({
    required this.ref,
    required this.dict,
    required this.mediaBox,
    required this.cropBox,
    required this.rotate,
    required this.resources,
  });

  final PdfRef ref;
  final PdfDict dict;
  final List<double> mediaBox;

  /// Effective crop box (intersected with the media box).
  final List<double> cropBox;
  final int rotate;
  final PdfObj? resources;

  double get cropWidth => (cropBox[2] - cropBox[0]).abs();
  double get cropHeight => (cropBox[3] - cropBox[1]).abs();

  /// Displayed size (rotation applied), like pdfium's page width/height.
  double get displayWidth => rotate % 180 == 0 ? cropWidth : cropHeight;
  double get displayHeight => rotate % 180 == 0 ? cropHeight : cropWidth;
}

class PdfCosDocument {
  PdfCosDocument._(this.bytes);

  final Uint8List bytes;
  final Map<int, _XrefEntry> _xref = {};
  final Map<int, PdfObj> _cache = {};
  final Map<int, List<(int, int)>> _objStmIndex = {};
  late PdfDict trailer;
  late int lastXrefOffset;
  bool lastXrefIsStream = false;
  int _maxObj = 0;
  List<PdfCosPage>? _pages;

  static PdfCosDocument parse(Uint8List bytes) {
    final doc = PdfCosDocument._(bytes);
    doc._load();
    return doc;
  }

  bool get isEncrypted => trailer.has('Encrypt');

  int get size {
    final s = (trailer['Size'] as PdfNum?)?.i ?? 0;
    return math.max(s, _maxObj + 1);
  }

  PdfRef? get rootRef {
    final r = trailer['Root'];
    return r is PdfRef ? r : null;
  }

  PdfDict get catalog {
    final c = resolve(trailer['Root']);
    if (c is! PdfDict) throw PdfCosException('PDF catalog not found');
    return c;
  }

  // -- xref ----------------------------------------------------------------

  void _load() {
    final sx = _lastIndexOf(bytes, ascii.encode('startxref'));
    var ok = false;
    if (sx >= 0) {
      final p = PdfParser(bytes, sx + 9);
      final off = p.parseObject();
      if (off is PdfNum && off.i > 0 && off.i < bytes.length) {
        lastXrefOffset = off.i;
        try {
          _readXrefChain(off.i);
          ok = _xref.isNotEmpty && trailer.has('Root');
        } catch (_) {
          ok = false;
        }
      }
    }
    if (!ok) _reconstruct();
  }

  void _readXrefChain(int offset) {
    final seen = <int>{};
    PdfDict? first;
    int? next = offset;
    var isFirst = true;
    while (next != null && !seen.contains(next) && next < bytes.length) {
      seen.add(next);
      final p = PdfParser(bytes, next);
      p.skipWs();
      PdfDict dict;
      if (p.matchKeyword('xref')) {
        dict = _readClassicXref(p);
        if (isFirst) lastXrefIsStream = false;
        final stm = dict['XRefStm'];
        if (stm is PdfNum) {
          try {
            _readXrefStreamAt(stm.i);
          } catch (_) {}
        }
      } else {
        dict = _readXrefStreamAt(next);
        if (isFirst) lastXrefIsStream = true;
      }
      first ??= dict;
      isFirst = false;
      final prev = dict['Prev'];
      next = prev is PdfNum ? prev.i : null;
    }
    if (first == null) throw PdfCosException('No trailer');
    trailer = first;
  }

  PdfDict _readClassicXref(PdfParser p) {
    while (true) {
      p.skipWs();
      if (p.matchKeyword('trailer')) break;
      final startObj = p.parseObject();
      final countObj = p.parseObject();
      if (startObj is! PdfNum || countObj is! PdfNum) {
        throw PdfCosException('Bad xref subsection');
      }
      final start = startObj.i;
      for (var i = 0; i < countObj.i; i++) {
        final off = p.parseObject();
        final gen = p.parseObject();
        p.skipWs();
        final type = p._readRegular();
        final n = start + i;
        if (off is! PdfNum || gen is! PdfNum) {
          throw PdfCosException('Bad xref entry');
        }
        if (n > _maxObj) _maxObj = n;
        if (type == 'n' && !_xref.containsKey(n) && off.i > 0) {
          _xref[n] = _XrefEntry.offset(off.i, gen.i);
        } else if (type == 'f') {
          _xref.putIfAbsent(n, () => const _XrefEntry.offset(-1, 0));
        }
      }
    }
    final t = p.parseObject();
    if (t is! PdfDict) throw PdfCosException('Bad trailer');
    return t;
  }

  PdfDict _readXrefStreamAt(int offset) {
    final obj = _parseIndirectAt(offset);
    final s = obj.$2;
    if (s is! PdfStream) throw PdfCosException('Bad xref stream');
    final dict = s.dict;
    final data = decodeStream(s);
    final w = (dict['W'] as PdfArray).items
        .map((e) => (e as PdfNum).i)
        .toList();
    final sizeObj = dict['Size'] as PdfNum;
    final index = dict['Index'] is PdfArray
        ? (dict['Index'] as PdfArray).items.map((e) => (e as PdfNum).i).toList()
        : [0, sizeObj.i];
    final rowLen = w.fold<int>(0, (a, b) => a + b);
    var pos = 0;
    int field(int k, int start) {
      var v = 0;
      for (var j = 0; j < w[k]; j++) {
        v = (v << 8) | data[start + j];
      }
      return v;
    }

    for (var s0 = 0; s0 + 1 < index.length; s0 += 2) {
      final start = index[s0];
      final count = index[s0 + 1];
      for (var i = 0; i < count; i++) {
        if (pos + rowLen > data.length) break;
        final type = w[0] == 0 ? 1 : field(0, pos);
        final f2 = field(1, pos + w[0]);
        final f3 = w[2] == 0 ? 0 : field(2, pos + w[0] + w[1]);
        pos += rowLen;
        final n = start + i;
        if (n > _maxObj) _maxObj = n;
        if (_xref.containsKey(n)) continue;
        if (type == 1) {
          _xref[n] = _XrefEntry.offset(f2, f3);
        } else if (type == 2) {
          _xref[n] = _XrefEntry.compressed(f2, f3);
        } else {
          _xref[n] = const _XrefEntry.offset(-1, 0);
        }
      }
    }
    return dict;
  }

  /// Rebuilds the xref by scanning for `n g obj` when the table is broken.
  void _reconstruct() {
    _xref.clear();
    final re = RegExp(r'(\d+)\s+(\d+)\s+obj\b');
    final text = latin1.decode(bytes);
    for (final m in re.allMatches(text)) {
      final n = int.parse(m.group(1)!);
      if (n > _maxObj) _maxObj = n;
      _xref[n] = _XrefEntry.offset(m.start, int.parse(m.group(2)!));
    }
    PdfDict? t;
    final ti = _lastIndexOf(bytes, ascii.encode('trailer'));
    if (ti >= 0) {
      final o = PdfParser(bytes, ti + 7).parseObject();
      if (o is PdfDict) t = o;
    }
    if (t == null || !t.has('Root')) {
      for (final e in _xref.entries) {
        try {
          final o = _parseIndirectAt(e.value.offset).$2;
          if (o is PdfStream && o.dict.nameOf('Type') == 'XRef') {
            t = o.dict;
          }
          if (o is PdfDict && o.nameOf('Type') == 'Catalog') {
            t ??= PdfDict();
            t['Root'] = PdfRef(e.key, e.value.gen);
          }
        } catch (_) {}
      }
    }
    if (t == null || !t.has('Root')) {
      throw PdfCosException('Could not read the PDF structure');
    }
    trailer = t;
    final sx = _lastIndexOf(bytes, ascii.encode('startxref'));
    lastXrefOffset = 0;
    if (sx >= 0) {
      final off = PdfParser(bytes, sx + 9).parseObject();
      if (off is PdfNum) lastXrefOffset = off.i;
    }
    lastXrefIsStream = trailer.nameOf('Type') == 'XRef';
    // Rebuild object-stream members too.
    for (final e in Map.of(_xref).entries) {
      try {
        final o = _parseIndirectAt(e.value.offset).$2;
        if (o is PdfStream && o.dict.nameOf('Type') == 'ObjStm') {
          final members = _objStmMembers(e.key, o);
          for (var i = 0; i < members.length; i++) {
            _xref.putIfAbsent(
              members[i].$1,
              () => _XrefEntry.compressed(e.key, i),
            );
          }
        }
      } catch (_) {}
    }
  }

  // -- objects ---------------------------------------------------------------

  (int, PdfObj) _parseIndirectAt(int offset) {
    final p = PdfParser(bytes, offset);
    final n = p.parseObject();
    final g = p.parseObject();
    if (n is! PdfNum || g is! PdfNum || !p.matchKeyword('obj')) {
      throw PdfCosException('Expected object at $offset');
    }
    final obj = p.parseObject();
    if (obj is PdfDict) {
      final save = p.pos;
      if (p.matchKeyword('stream')) {
        if (p.pos < bytes.length && bytes[p.pos] == 0x0D) p.pos++;
        if (p.pos < bytes.length && bytes[p.pos] == 0x0A) p.pos++;
        final start = p.pos;
        var len = -1;
        final lenObj = obj['Length'];
        if (lenObj is PdfNum) {
          len = lenObj.i;
        } else if (lenObj is PdfRef) {
          try {
            final l = resolve(lenObj);
            if (l is PdfNum) len = l.i;
          } catch (_) {}
        }
        var end = start + len;
        if (len < 0 || end > bytes.length || !_hasEndstreamNear(end)) {
          final es = _indexOf(bytes, ascii.encode('endstream'), start);
          end = es < 0 ? bytes.length : es;
          while (end > start &&
              (bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D)) {
            end--;
          }
        }
        return (n.i, PdfStream(obj, Uint8List.sublistView(bytes, start, end)));
      }
      p.pos = save;
    }
    return (n.i, obj);
  }

  bool _hasEndstreamNear(int end) {
    final p = PdfParser(bytes, end);
    p.skipWs();
    return p.matchKeyword('endstream');
  }

  List<(int, int)> _objStmMembers(int stmNum, PdfStream s) {
    final cached = _objStmIndex[stmNum];
    if (cached != null) return cached;
    final data = decodeStream(s);
    final count = (s.dict['N'] as PdfNum).i;
    final p = PdfParser(data);
    final out = <(int, int)>[];
    for (var i = 0; i < count; i++) {
      final n = p.parseObject() as PdfNum;
      final off = p.parseObject() as PdfNum;
      out.add((n.i, off.i));
    }
    _objStmIndex[stmNum] = out;
    _objStmData[stmNum] = data;
    return out;
  }

  final Map<int, Uint8List> _objStmData = {};

  /// Returns the object for [num], or [PdfNull] when missing.
  PdfObj getObject(int num) {
    final cached = _cache[num];
    if (cached != null) return cached;
    final e = _xref[num];
    PdfObj result = const PdfNull();
    if (e != null) {
      try {
        if (e.isCompressed) {
          final stm = getObject(e.stream);
          if (stm is PdfStream) {
            final members = _objStmMembers(e.stream, stm);
            final first = (stm.dict['First'] as PdfNum).i;
            final data = _objStmData[e.stream]!;
            var idx = e.index;
            if (idx >= members.length || members[idx].$1 != num) {
              idx = members.indexWhere((m) => m.$1 == num);
            }
            if (idx >= 0) {
              result = PdfParser(data, first + members[idx].$2).parseObject();
            }
          }
        } else if (e.offset > 0) {
          result = _parseIndirectAt(e.offset).$2;
        }
      } catch (_) {
        result = const PdfNull();
      }
    }
    _cache[num] = result;
    return result;
  }

  PdfObj resolve(PdfObj? o) {
    var cur = o;
    var guard = 0;
    while (cur is PdfRef && guard++ < 32) {
      cur = getObject(cur.num);
    }
    return cur ?? const PdfNull();
  }

  PdfDict? resolveDict(PdfObj? o) {
    final r = resolve(o);
    if (r is PdfDict) return r;
    if (r is PdfStream) return r.dict;
    return null;
  }

  Uint8List decodeStream(PdfStream s, {int? maxOutputBytes}) {
    var data = Uint8List.fromList(s.raw);
    final f = resolve(s.dict['Filter']);
    final parmsObj = resolve(s.dict['DecodeParms']);
    final filters = <String>[
      if (f is PdfName) f.name,
      if (f is PdfArray)
        for (final x in f.items)
          if (x is PdfName) x.name,
    ];
    final parms = <PdfDict?>[
      if (parmsObj is PdfDict) parmsObj,
      if (parmsObj is PdfArray)
        for (final x in parmsObj.items)
          resolve(x) is PdfDict ? resolve(x) as PdfDict : null,
    ];
    for (var i = 0; i < filters.length; i++) {
      final name = filters[i];
      if (name == 'FlateDecode' || name == 'Fl') {
        data = pdfInflate(data, maxOutputBytes: maxOutputBytes);
        data = _unpredict(data, i < parms.length ? parms[i] : null);
      } else {
        throw PdfCosException('Unsupported stream filter $name');
      }
    }
    if (maxOutputBytes != null && data.length > maxOutputBytes) {
      throw PdfCosException('Stream expands beyond the size limit');
    }
    return data;
  }

  // -- pages -----------------------------------------------------------------

  List<PdfCosPage> get pages {
    final cached = _pages;
    if (cached != null) return cached;
    final out = <PdfCosPage>[];
    final root = catalog['Pages'];
    final visited = <int>{};
    void walk(
      PdfObj? node, {
      List<double>? media,
      List<double>? crop,
      int? rotate,
      PdfObj? resources,
    }) {
      if (node is! PdfRef || visited.contains(node.num)) return;
      visited.add(node.num);
      final d = resolveDict(node);
      if (d == null) return;
      final m = _box(d['MediaBox']) ?? media;
      final c = _box(d['CropBox']) ?? crop;
      final r = resolve(d['Rotate']) is PdfNum
          ? (resolve(d['Rotate']) as PdfNum).i
          : rotate;
      final res = d['Resources'] ?? resources;
      final type = d.nameOf('Type');
      final kids = resolve(d['Kids']);
      if (type == 'Pages' || (type == null && kids is PdfArray)) {
        if (kids is PdfArray) {
          for (final k in kids.items) {
            walk(k, media: m, crop: c, rotate: r, resources: res);
          }
        }
        return;
      }
      final mediaBox = m ?? const [0.0, 0.0, 612.0, 792.0];
      var cropBox = c ?? mediaBox;
      cropBox = [
        math.max(cropBox[0], mediaBox[0]),
        math.max(cropBox[1], mediaBox[1]),
        math.min(cropBox[2], mediaBox[2]),
        math.min(cropBox[3], mediaBox[3]),
      ];
      if (cropBox[2] <= cropBox[0] || cropBox[3] <= cropBox[1]) {
        cropBox = mediaBox;
      }
      var rot = (r ?? 0) % 360;
      if (rot < 0) rot += 360;
      out.add(
        PdfCosPage(
          ref: node,
          dict: d,
          mediaBox: mediaBox,
          cropBox: cropBox,
          rotate: rot,
          resources: res,
        ),
      );
    }

    walk(root);
    return _pages = out;
  }

  List<double>? _box(PdfObj? o) {
    final a = resolve(o);
    if (a is! PdfArray || a.length < 4) return null;
    final v = [for (final x in a.items.take(4)) resolve(x)];
    if (v.any((e) => e is! PdfNum)) return null;
    final n = v.map((e) => (e as PdfNum).d).toList();
    return [
      math.min(n[0], n[2]),
      math.min(n[1], n[3]),
      math.max(n[0], n[2]),
      math.max(n[1], n[3]),
    ];
  }

  /// 1-based page index for a page object number, or 0.
  int pageIndexOf(PdfRef ref) {
    final list = pages;
    for (var i = 0; i < list.length; i++) {
      if (list[i].ref.num == ref.num) return i + 1;
    }
    return 0;
  }
}

int _indexOf(Uint8List data, List<int> pattern, [int from = 0]) {
  outer:
  for (var i = from; i <= data.length - pattern.length; i++) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

int _lastIndexOf(Uint8List data, List<int> pattern) {
  outer:
  for (var i = data.length - pattern.length; i >= 0; i--) {
    for (var j = 0; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) continue outer;
    }
    return i;
  }
  return -1;
}

int pdfIndexOf(Uint8List data, List<int> pattern, [int from = 0]) =>
    _indexOf(data, pattern, from);

// ---------------------------------------------------------------------------
// Serialization

String pdfNumber(num v) {
  if (v is int) return '$v';
  if (v.isNaN || v.isInfinite) return '0';
  if (v == v.roundToDouble() && v.abs() < 1e15) return '${v.toInt()}';
  var s = v.toStringAsFixed(4);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'0+$'), '');
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  }
  if (s == '-0') s = '0';
  return s;
}

void writePdfObj(BytesBuilder out, PdfObj o) {
  void s(String text) => out.add(latin1.encode(text));
  switch (o) {
    case PdfNull():
      s('null');
    case PdfBool(:final value):
      s(value ? 'true' : 'false');
    case PdfNum(:final value):
      s(pdfNumber(value));
    case PdfName(:final name):
      final b = StringBuffer('/');
      for (final c in utf8.encode(name)) {
        if (c < 0x21 || c > 0x7E || c == 0x23 || _isDelim(c)) {
          b.write('#${c.toRadixString(16).padLeft(2, '0')}');
        } else {
          b.writeCharCode(c);
        }
      }
      s(b.toString());
    case PdfString(:final bytes, :final hex):
      if (hex) {
        final b = StringBuffer('<');
        for (final c in bytes) {
          b.write(c.toRadixString(16).padLeft(2, '0'));
        }
        b.write('>');
        s(b.toString());
      } else {
        out.addByte(0x28);
        for (final c in bytes) {
          if (c == 0x28 || c == 0x29 || c == 0x5C) {
            out
              ..addByte(0x5C)
              ..addByte(c);
          } else if (c == 0x0D) {
            s(r'\r');
          } else if (c == 0x0A) {
            s(r'\n');
          } else {
            out.addByte(c);
          }
        }
        out.addByte(0x29);
      }
    case PdfArray(:final items):
      s('[');
      for (var i = 0; i < items.length; i++) {
        if (i > 0) s(' ');
        writePdfObj(out, items[i]);
      }
      s(']');
    case PdfDict(:final map):
      s('<<');
      for (final e in map.entries) {
        writePdfObj(out, PdfName(e.key));
        s(' ');
        writePdfObj(out, e.value);
      }
      s('>>');
    case PdfRef(:final num, :final gen):
      s('$num $gen R');
    case PdfRaw(:final text):
      s(text);
    case PdfStream():
      final d = o.dict.clone()..['Length'] = PdfNum(o.raw.length);
      writePdfObj(out, d);
      s('\nstream\n');
      out.add(o.raw);
      s('\nendstream');
    default:
      s('null');
  }
}

Uint8List pdfObjBytes(PdfObj o) {
  final b = BytesBuilder(copy: false);
  writePdfObj(b, o);
  return b.toBytes();
}

/// Appends new / replaced objects to the original file as one incremental
/// update, leaving every original byte (and earlier signatures) untouched.
class PdfIncrementalWriter {
  PdfIncrementalWriter(this.doc) : _next = doc.size;

  final PdfCosDocument doc;
  int _next;
  final Map<int, PdfObj> _objects = {};

  PdfRef allocate() => PdfRef(_next++);

  void put(PdfRef ref, PdfObj obj) => _objects[ref.num] = obj;

  PdfRef add(PdfObj obj) {
    final r = allocate();
    put(r, obj);
    return r;
  }

  bool get isEmpty => _objects.isEmpty;

  /// Builds the updated file. When [signaturePlaceholder] objects exist the
  /// caller patches /ByteRange and /Contents afterwards.
  Uint8List build() {
    final out = BytesBuilder(copy: false)..add(doc.bytes);
    final last = doc.bytes.isEmpty ? 0x0A : doc.bytes.last;
    if (last != 0x0A && last != 0x0D) out.addByte(0x0A);
    final offsets = <int, int>{};
    final nums = _objects.keys.toList()..sort();
    for (final n in nums) {
      offsets[n] = out.length;
      out.add(latin1.encode('$n 0 obj\n'));
      writePdfObj(out, _objects[n]!);
      out.add(latin1.encode('\nendobj\n'));
    }
    final t = PdfDict();
    for (final key in const ['Root', 'Info', 'ID']) {
      final v = doc.trailer[key];
      if (v != null) t[key] = v;
    }
    t['Prev'] = PdfNum(doc.lastXrefOffset);

    if (doc.lastXrefIsStream) {
      final xrefNum = _next++;
      offsets[xrefNum] = out.length;
      final all = offsets.keys.toList()..sort();
      final index = <int>[];
      final rows = BytesBuilder(copy: false);
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
          rows
            ..addByte(1)
            ..add([
              (off >> 24) & 0xFF,
              (off >> 16) & 0xFF,
              (off >> 8) & 0xFF,
              off & 0xFF,
            ])
            ..add([0, 0]);
        }
        i = j + 1;
      }
      t['Type'] = const PdfName('XRef');
      t['Size'] = PdfNum(_next);
      t['W'] = PdfArray([const PdfNum(1), const PdfNum(4), const PdfNum(2)]);
      t['Index'] = PdfArray([for (final v in index) PdfNum(v)]);
      out.add(latin1.encode('$xrefNum 0 obj\n'));
      writePdfObj(out, PdfStream(t, rows.toBytes()));
      out.add(latin1.encode('\nendobj\n'));
      out.add(latin1.encode('startxref\n${offsets[xrefNum]}\n%%EOF\n'));
      return out.toBytes();
    }

    final xrefStart = out.length;
    final b = StringBuffer('xref\n');
    final all = offsets.keys.toList()..sort();
    var i = 0;
    while (i < all.length) {
      var j = i;
      while (j + 1 < all.length && all[j + 1] == all[j] + 1) {
        j++;
      }
      b.write('${all[i]} ${j - i + 1}\n');
      for (var k = i; k <= j; k++) {
        b.write('${offsets[all[k]]!.toString().padLeft(10, '0')} 00000 n\r\n');
      }
      i = j + 1;
    }
    t['Size'] = PdfNum(_next);
    out.add(latin1.encode(b.toString()));
    out.add(latin1.encode('trailer\n'));
    writePdfObj(out, t);
    out.add(latin1.encode('\nstartxref\n$xrefStart\n%%EOF\n'));
    return out.toBytes();
  }
}

// ---------------------------------------------------------------------------
// Geometry: displayed page (top-left origin, points) ↔ PDF user space.

/// 2D affine matrix [a b c d e f] (PDF convention: x' = a x + c y + e).
class PdfMatrix {
  const PdfMatrix(this.a, this.b, this.c, this.d, this.e, this.f);
  static const identity = PdfMatrix(1, 0, 0, 1, 0, 0);

  final double a, b, c, d, e, f;

  /// Returns `this` followed by [m] (apply this first, then m).
  PdfMatrix then(PdfMatrix m) => PdfMatrix(
    a * m.a + b * m.c,
    a * m.b + b * m.d,
    c * m.a + d * m.c,
    c * m.b + d * m.d,
    e * m.a + f * m.c + m.e,
    e * m.b + f * m.d + m.f,
  );

  (double, double) apply(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);

  String toPdf() => [a, b, c, d, e, f].map(pdfNumber).join(' ');

  static PdfMatrix translate(double x, double y) => PdfMatrix(1, 0, 0, 1, x, y);
  static PdfMatrix scale(double sx, double sy) => PdfMatrix(sx, 0, 0, sy, 0, 0);
  static PdfMatrix rotate(double rad) {
    final cs = math.cos(rad), sn = math.sin(rad);
    return PdfMatrix(cs, sn, -sn, cs, 0, 0);
  }
}

/// Maps displayed-page points (x right, y down, origin top-left of the
/// rotated crop box) to PDF user space.
PdfMatrix displayToUserMatrix(PdfCosPage page) {
  final x0 = page.cropBox[0], y0 = page.cropBox[1];
  final x1 = page.cropBox[2], y1 = page.cropBox[3];
  switch (page.rotate) {
    case 90:
      // x_user = x0 + dy, y_user = y0 + dx
      return PdfMatrix(0, 1, 1, 0, x0, y0);
    case 180:
      // x_user = x1 - dx, y_user = y0 + dy
      return PdfMatrix(-1, 0, 0, 1, x1, y0);
    case 270:
      // x_user = x1 - dy, y_user = y1 - dx
      return PdfMatrix(0, -1, -1, 0, x1, y1);
    default:
      // x_user = x0 + dx, y_user = y1 - dy
      return PdfMatrix(1, 0, 0, -1, x0, y1);
  }
}

/// Inverse of [displayToUserMatrix]: user space → displayed points.
(double, double) userToDisplay(PdfCosPage page, double x, double y) {
  final x0 = page.cropBox[0], y0 = page.cropBox[1];
  final x1 = page.cropBox[2], y1 = page.cropBox[3];
  return switch (page.rotate) {
    90 => (y - y0, x - x0),
    180 => (x1 - x, y - y0),
    270 => (y1 - y, x1 - x),
    _ => (x - x0, y1 - y),
  };
}
