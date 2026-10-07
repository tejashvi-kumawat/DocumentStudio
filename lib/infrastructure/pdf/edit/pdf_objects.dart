import 'dart:convert';
import 'dart:typed_data';

/// Minimal PDF object model used by the pure-Dart incremental editor.
sealed class PdfObj {
  const PdfObj();
}

final class PdfNull extends PdfObj {
  const PdfNull();
  static const instance = PdfNull();
}

final class PdfBool extends PdfObj {
  const PdfBool(this.value);
  final bool value;
}

final class PdfNum extends PdfObj {
  const PdfNum(this.value);
  final num value;
  double get d => value.toDouble();
  int get i => value.round();
}

final class PdfName extends PdfObj {
  const PdfName(this.name);

  /// Name without the leading slash.
  final String name;

  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

final class PdfString extends PdfObj {
  PdfString(this.bytes, {this.hex = false});

  /// PDFDocEncoding / UTF-16BE (with BOM) text string.
  factory PdfString.text(String s) {
    final ascii = s.codeUnits.every((c) => c >= 0x20 && c < 0x7f);
    if (ascii) return PdfString(Uint8List.fromList(s.codeUnits));
    final out = BytesBuilder()..add([0xfe, 0xff]);
    for (final c in s.codeUnits) {
      out.add([(c >> 8) & 0xff, c & 0xff]);
    }
    return PdfString(out.toBytes(), hex: true);
  }

  final Uint8List bytes;
  final bool hex;

  /// Decodes UTF-16BE (BOM) or PDFDocEncoding (latin-1 approximation).
  String get text {
    if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(units);
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      return utf8.decode(bytes.sublist(3), allowMalformed: true);
    }
    return latin1.decode(bytes);
  }
}

final class PdfArray extends PdfObj {
  PdfArray([List<PdfObj>? items]) : items = items ?? <PdfObj>[];
  final List<PdfObj> items;

  factory PdfArray.nums(Iterable<num> values) =>
      PdfArray([for (final v in values) PdfNum(v)]);

  int get length => items.length;
  PdfObj operator [](int i) => items[i];
}

final class PdfDict extends PdfObj {
  PdfDict([Map<String, PdfObj>? entries])
    : entries = entries ?? <String, PdfObj>{};

  /// Keys without the leading slash.
  final Map<String, PdfObj> entries;

  PdfObj? operator [](String key) => entries[key];
  void operator []=(String key, PdfObj value) => entries[key] = value;
  bool containsKey(String key) => entries.containsKey(key);
  PdfObj? remove(String key) => entries.remove(key);

  PdfDict clone() => PdfDict(Map<String, PdfObj>.of(entries));

  String? nameOf(String key) {
    final v = entries[key];
    return v is PdfName ? v.name : null;
  }
}

final class PdfRef extends PdfObj {
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

final class PdfStream extends PdfObj {
  PdfStream(this.dict, this.data);

  /// Stream dictionary; `/Length` is rewritten on serialization.
  final PdfDict dict;

  /// Raw (still encoded) stream bytes.
  final Uint8List data;
}

/// Serializes [PdfObj]s to PDF syntax.
class PdfWriterSink {
  final BytesBuilder _out = BytesBuilder(copy: false);

  int get length => _out.length;

  void raw(String s) => _out.add(latin1.encode(s));
  void bytes(List<int> b) => _out.add(b);

  Uint8List take() => _out.takeBytes();

  void obj(PdfObj o) {
    switch (o) {
      case PdfNull():
        raw('null');
      case PdfBool(:final value):
        raw(value ? 'true' : 'false');
      case PdfNum(:final value):
        raw(formatPdfNum(value));
      case PdfName(:final name):
        raw('/${_escapeName(name)}');
      case PdfString(:final bytes, :final hex):
        if (hex) {
          final sb = StringBuffer('<');
          for (final b in bytes) {
            sb.write(b.toRadixString(16).padLeft(2, '0'));
          }
          sb.write('>');
          raw(sb.toString());
        } else {
          _out.addByte(0x28);
          for (final b in bytes) {
            if (b == 0x28 || b == 0x29 || b == 0x5c) {
              _out.addByte(0x5c);
              _out.addByte(b);
            } else if (b == 0x0d) {
              raw(r'\r');
            } else if (b == 0x0a) {
              raw(r'\n');
            } else {
              _out.addByte(b);
            }
          }
          _out.addByte(0x29);
        }
      case PdfArray(:final items):
        raw('[');
        for (var i = 0; i < items.length; i++) {
          if (i > 0) raw(' ');
          obj(items[i]);
        }
        raw(']');
      case PdfDict(:final entries):
        raw('<<');
        entries.forEach((k, v) {
          raw('/${_escapeName(k)} ');
          obj(v);
          raw('\n');
        });
        raw('>>');
      case PdfRef(:final num, :final gen):
        raw('$num $gen R');
      case PdfStream(:final dict, :final data):
        final d = dict.clone()..['Length'] = PdfNum(data.length);
        obj(d);
        raw('\nstream\n');
        _out.add(data);
        raw('\nendstream');
    }
  }

  static String _escapeName(String name) {
    final sb = StringBuffer();
    for (final c in latin1.encode(name)) {
      final regular =
          c > 0x20 && c < 0x7f && !'()<>[]{}/%#'.codeUnits.contains(c);
      if (regular) {
        sb.writeCharCode(c);
      } else {
        sb.write('#${c.toRadixString(16).padLeft(2, '0')}');
      }
    }
    return sb.toString();
  }
}

/// Compact number formatting (max 4 decimals, no exponent).
String formatPdfNum(num v) {
  if (v is int) return v.toString();
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return '0';
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.round().toString();
  var s = d.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  if (s == '-0') s = '0';
  return s;
}
