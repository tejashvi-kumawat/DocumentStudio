import 'dart:io' show ZLibDecoder;
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';

/// Thrown when a PDF can't be edited by the pure-Dart editor.
class PdfEditException implements Exception {
  const PdfEditException(this.message, {this.encrypted = false});
  final String message;
  final bool encrypted;
  @override
  String toString() => 'PdfEditException: $message';
}

bool _isWhite(int c) =>
    c == 0x20 || c == 0x0a || c == 0x0d || c == 0x09 || c == 0x0c || c == 0x00;

bool _isDelim(int c) =>
    c == 0x28 ||
    c == 0x29 ||
    c == 0x3c ||
    c == 0x3e ||
    c == 0x5b ||
    c == 0x5d ||
    c == 0x7b ||
    c == 0x7d ||
    c == 0x2f ||
    c == 0x25;

/// Recursive-descent parser for PDF objects over a byte buffer.
class PdfLexer {
  PdfLexer(this.data, [this.pos = 0]);

  final Uint8List data;
  int pos;

  bool get atEnd => pos >= data.length;

  void skipWhite() {
    while (pos < data.length) {
      final c = data[pos];
      if (_isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < data.length && data[pos] != 0x0a && data[pos] != 0x0d) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  /// Reads a bare keyword / number token without consuming delimiters.
  String readToken() {
    skipWhite();
    final start = pos;
    while (pos < data.length && !_isWhite(data[pos]) && !_isDelim(data[pos])) {
      pos++;
    }
    return String.fromCharCodes(data, start, pos);
  }

  String peekToken() {
    final save = pos;
    final t = readToken();
    pos = save;
    return t;
  }

  /// Parses the next object. Indirect references `n g R` are recognized.
  PdfObj parse() {
    skipWhite();
    if (pos >= data.length) throw const PdfEditException('Unexpected EOF');
    final c = data[pos];
    switch (c) {
      case 0x2f: // /
        return _parseName();
      case 0x28: // (
        return _parseLiteralString();
      case 0x3c: // <
        if (pos + 1 < data.length && data[pos + 1] == 0x3c) {
          return _parseDict();
        }
        return _parseHexString();
      case 0x5b: // [
        pos++;
        final items = <PdfObj>[];
        while (true) {
          skipWhite();
          if (pos >= data.length) break;
          if (data[pos] == 0x5d) {
            pos++;
            break;
          }
          items.add(parse());
        }
        return PdfArray(items);
    }
    final tok = readToken();
    if (tok.isEmpty) {
      pos++;
      return PdfNull.instance;
    }
    switch (tok) {
      case 'true':
        return const PdfBool(true);
      case 'false':
        return const PdfBool(false);
      case 'null':
        return PdfNull.instance;
    }
    final n = num.tryParse(tok);
    if (n == null) {
      // Unknown keyword (e.g. stray operator) — treat as null.
      return PdfNull.instance;
    }
    if (n is int && !tok.contains('.')) {
      final save = pos;
      final t2 = readToken();
      final g = int.tryParse(t2);
      if (g != null && !t2.contains('.')) {
        final t3 = readToken();
        if (t3 == 'R') return PdfRef(n, g);
      }
      pos = save;
    }
    return PdfNum(n);
  }

  PdfName _parseName() {
    pos++;
    final bytes = <int>[];
    while (pos < data.length && !_isWhite(data[pos]) && !_isDelim(data[pos])) {
      final c = data[pos];
      if (c == 0x23 && pos + 2 < data.length) {
        final h = int.tryParse(
          String.fromCharCodes(data, pos + 1, pos + 3),
          radix: 16,
        );
        if (h != null) {
          bytes.add(h);
          pos += 3;
          continue;
        }
      }
      bytes.add(c);
      pos++;
    }
    return PdfName(String.fromCharCodes(bytes));
  }

  PdfString _parseLiteralString() {
    pos++;
    final out = BytesBuilder();
    var depth = 1;
    while (pos < data.length) {
      final c = data[pos++];
      if (c == 0x5c) {
        if (pos >= data.length) break;
        final e = data[pos++];
        switch (e) {
          case 0x6e:
            out.addByte(0x0a);
          case 0x72:
            out.addByte(0x0d);
          case 0x74:
            out.addByte(0x09);
          case 0x62:
            out.addByte(0x08);
          case 0x66:
            out.addByte(0x0c);
          case 0x0d:
            if (pos < data.length && data[pos] == 0x0a) pos++;
          case 0x0a:
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
              out.addByte(v & 0xff);
            } else {
              out.addByte(e);
            }
        }
      } else if (c == 0x28) {
        depth++;
        out.addByte(c);
      } else if (c == 0x29) {
        depth--;
        if (depth == 0) break;
        out.addByte(c);
      } else {
        out.addByte(c);
      }
    }
    return PdfString(out.toBytes());
  }

  PdfString _parseHexString() {
    pos++;
    final digits = <int>[];
    while (pos < data.length && data[pos] != 0x3e) {
      final c = data[pos++];
      final v = _hexVal(c);
      if (v >= 0) digits.add(v);
    }
    pos++;
    if (digits.length.isOdd) digits.add(0);
    final out = Uint8List(digits.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = (digits[i * 2] << 4) | digits[i * 2 + 1];
    }
    return PdfString(out, hex: true);
  }

  static int _hexVal(int c) {
    if (c >= 0x30 && c <= 0x39) return c - 0x30;
    if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
    if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
    return -1;
  }

  PdfDict _parseDict() {
    pos += 2;
    final map = <String, PdfObj>{};
    while (true) {
      skipWhite();
      if (pos >= data.length) break;
      if (data[pos] == 0x3e && pos + 1 < data.length && data[pos + 1] == 0x3e) {
        pos += 2;
        break;
      }
      if (data[pos] != 0x2f) {
        // Malformed entry; skip a token to make progress.
        parse();
        continue;
      }
      final key = _parseName().name;
      skipWhite();
      if (pos < data.length &&
          data[pos] == 0x3e &&
          pos + 1 < data.length &&
          data[pos + 1] == 0x3e) {
        map[key] = PdfNull.instance;
        continue;
      }
      map[key] = parse();
    }
    return PdfDict(map);
  }
}

/// Finds [pattern] in [data] searching backwards from [from].
int lastIndexOfBytes(Uint8List data, List<int> pattern, [int? from]) {
  var i = (from ?? data.length) - pattern.length;
  outer:
  for (; i >= 0; i--) {
    for (var k = 0; k < pattern.length; k++) {
      if (data[i + k] != pattern[k]) continue outer;
    }
    return i;
  }
  return -1;
}

int indexOfBytes(Uint8List data, List<int> pattern, [int from = 0]) {
  final end = data.length - pattern.length;
  outer:
  for (var i = from; i <= end; i++) {
    for (var k = 0; k < pattern.length; k++) {
      if (data[i + k] != pattern[k]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Decodes stream data for the filters the editor understands.
Uint8List decodeStreamData(PdfDict dict, Uint8List raw) {
  final filter = dict['Filter'];
  final filters = <String>[
    if (filter is PdfName) filter.name,
    if (filter is PdfArray)
      for (final f in filter.items)
        if (f is PdfName) f.name,
  ];
  final parmsRaw = dict['DecodeParms'];
  var data = raw;
  for (var i = 0; i < filters.length; i++) {
    final f = filters[i];
    if (f == 'FlateDecode' || f == 'Fl') {
      data = inflateBytes(data);
      PdfObj? parms = parmsRaw;
      if (parmsRaw is PdfArray) {
        parms = i < parmsRaw.length ? parmsRaw[i] : null;
      }
      if (parms is PdfDict) data = _undoPredictor(data, parms);
    } else {
      throw PdfEditException('Unsupported stream filter $f');
    }
  }
  return data;
}

Uint8List inflateBytes(Uint8List data) {
  try {
    return Uint8List.fromList(ZLibDecoder().convert(data));
  } catch (_) {
    return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
  }
}

Uint8List _undoPredictor(Uint8List data, PdfDict parms) {
  final predictor = (parms['Predictor'] as PdfNum?)?.i ?? 1;
  if (predictor < 10) return data;
  final colors = (parms['Colors'] as PdfNum?)?.i ?? 1;
  final bpc = (parms['BitsPerComponent'] as PdfNum?)?.i ?? 8;
  final columns = (parms['Columns'] as PdfNum?)?.i ?? 1;
  final bpp = ((colors * bpc) + 7) ~/ 8;
  final rowLen = ((colors * bpc * columns) + 7) ~/ 8;
  final out = BytesBuilder();
  var prev = Uint8List(rowLen);
  var p = 0;
  while (p + 1 + rowLen <= data.length) {
    final type = data[p];
    final row = Uint8List.fromList(data.sublist(p + 1, p + 1 + rowLen));
    for (var i = 0; i < rowLen; i++) {
      final left = i >= bpp ? row[i - bpp] : 0;
      final up = prev[i];
      final upLeft = i >= bpp ? prev[i - bpp] : 0;
      switch (type) {
        case 1:
          row[i] = (row[i] + left) & 0xff;
        case 2:
          row[i] = (row[i] + up) & 0xff;
        case 3:
          row[i] = (row[i] + ((left + up) >> 1)) & 0xff;
        case 4:
          final pa = (up - upLeft).abs();
          final pb = (left - upLeft).abs();
          final pc = (left + up - 2 * upLeft).abs();
          final pred = (pa <= pb && pa <= pc)
              ? left
              : (pb <= pc ? up : upLeft);
          row[i] = (row[i] + pred) & 0xff;
      }
    }
    out.add(row);
    prev = row;
    p += 1 + rowLen;
  }
  return out.toBytes();
}
