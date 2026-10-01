import 'dart:convert';
import 'dart:typed_data';

/// Minimal DER encoder/decoder for CMS and X.509 needs.
class DerNode {
  DerNode(this.tag, this.value, {this.children});
  final int tag;
  final Uint8List value;
  final List<DerNode>? children;

  bool get isConstructed => (tag & 0x20) != 0;

  static DerNode decode(Uint8List bytes, [int offset = 0]) {
    final r = _read(bytes, offset);
    return r.node;
  }

  static List<DerNode> decodeAll(Uint8List bytes) {
    final out = <DerNode>[];
    var i = 0;
    while (i < bytes.length) {
      final r = _read(bytes, i);
      out.add(r.node);
      i = r.next;
    }
    return out;
  }

  Uint8List encode() {
    final content = children != null
        ? _concat([for (final c in children!) c.encode()])
        : value;
    return _concat([
      Uint8List.fromList([tag]),
      _encodeLength(content.length),
      content,
    ]);
  }

  static Uint8List integer(BigInt v) {
    if (v == BigInt.zero) return encodePrimitive(0x02, Uint8List.fromList([0]));
    var bytes = _bigIntToBytes(v);
    if (bytes[0] & 0x80 != 0) {
      bytes = Uint8List.fromList([0, ...bytes]);
    }
    return encodePrimitive(0x02, bytes);
  }

  static Uint8List integerBytes(Uint8List raw) {
    var bytes = raw;
    if (bytes.isEmpty) bytes = Uint8List.fromList([0]);
    if (bytes[0] & 0x80 != 0) bytes = Uint8List.fromList([0, ...bytes]);
    return encodePrimitive(0x02, bytes);
  }

  static Uint8List octetString(Uint8List raw) => encodePrimitive(0x04, raw);
  static Uint8List bitString(Uint8List raw, {int unusedBits = 0}) =>
      encodePrimitive(0x03, Uint8List.fromList([unusedBits, ...raw]));
  static Uint8List null_() => encodePrimitive(0x05, Uint8List(0));
  static Uint8List utf8String(String s) =>
      encodePrimitive(0x0c, Uint8List.fromList(utf8.encode(s)));
  static Uint8List printableString(String s) =>
      encodePrimitive(0x13, Uint8List.fromList(s.codeUnits));
  static Uint8List ia5String(String s) =>
      encodePrimitive(0x16, Uint8List.fromList(s.codeUnits));
  static Uint8List utcTime(DateTime dt) {
    final u = dt.toUtc();
    final yy = (u.year % 100).toString().padLeft(2, '0');
    String p(int n) => n.toString().padLeft(2, '0');
    final s =
        '$yy${p(u.month)}${p(u.day)}${p(u.hour)}${p(u.minute)}${p(u.second)}Z';
    return encodePrimitive(0x17, Uint8List.fromList(s.codeUnits));
  }

  static Uint8List objectIdentifier(String oid) {
    final parts = oid.split('.').map(int.parse).toList();
    if (parts.length < 2) throw ArgumentError('OID $oid');
    final body = <int>[(40 * parts[0]) + parts[1]];
    for (final n in parts.skip(2)) {
      body.addAll(_base128(n));
    }
    return encodePrimitive(0x06, Uint8List.fromList(body));
  }

  static Uint8List sequence(List<Uint8List> items) =>
      encodeConstructed(0x30, items);
  static Uint8List set(List<Uint8List> items) => encodeConstructed(0x31, items);
  static Uint8List context(
    int n,
    List<Uint8List> items, {
    bool constructed = true,
  }) => encodeConstructed((constructed ? 0xa0 : 0x80) | n, items);

  static Uint8List encodePrimitive(int tag, Uint8List value) => _concat([
    Uint8List.fromList([tag]),
    _encodeLength(value.length),
    value,
  ]);

  static Uint8List encodeConstructed(int tag, List<Uint8List> items) {
    final content = _concat(items);
    return _concat([
      Uint8List.fromList([tag]),
      _encodeLength(content.length),
      content,
    ]);
  }

  static Uint8List _encodeLength(int len) {
    if (len < 0x80) return Uint8List.fromList([len]);
    final bytes = <int>[];
    var n = len;
    while (n > 0) {
      bytes.insert(0, n & 0xff);
      n >>= 8;
    }
    return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
  }

  static List<int> _base128(int value) {
    if (value == 0) return [0];
    final stack = <int>[];
    var n = value;
    stack.add(n & 0x7f);
    n >>= 7;
    while (n > 0) {
      stack.add(0x80 | (n & 0x7f));
      n >>= 7;
    }
    return stack.reversed.toList();
  }

  static Uint8List _bigIntToBytes(BigInt v) {
    if (v < BigInt.zero) throw ArgumentError('negative');
    var hex = v.toRadixString(16);
    if (hex.length.isOdd) hex = '0$hex';
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static Uint8List _concat(List<Uint8List> parts) {
    final n = parts.fold<int>(0, (a, b) => a + b.length);
    final out = Uint8List(n);
    var i = 0;
    for (final p in parts) {
      out.setRange(i, i + p.length, p);
      i += p.length;
    }
    return out;
  }

  static ({DerNode node, int next}) _read(Uint8List bytes, int offset) {
    if (offset >= bytes.length) throw FormatException('DER truncated');
    final tag = bytes[offset];
    var i = offset + 1;
    if (i >= bytes.length) throw FormatException('DER length missing');
    var len = bytes[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n == 0 || i + n > bytes.length)
        throw FormatException('DER bad length');
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | bytes[i++];
      }
    }
    if (i + len > bytes.length) throw FormatException('DER content truncated');
    final content = bytes.sublist(i, i + len);
    i += len;
    List<DerNode>? children;
    if (tag & 0x20 != 0) {
      children = decodeAll(content);
    }
    return (node: DerNode(tag, content, children: children), next: i);
  }
}

extension DerNodeX on DerNode {
  String? asOid() {
    if (tag != 0x06 || value.isEmpty) return null;
    final first = value[0];
    final parts = <int>[first ~/ 40, first % 40];
    var acc = 0;
    for (var i = 1; i < value.length; i++) {
      final b = value[i];
      acc = (acc << 7) | (b & 0x7f);
      if (b & 0x80 == 0) {
        parts.add(acc);
        acc = 0;
      }
    }
    return parts.join('.');
  }

  BigInt? asInteger() {
    if (tag != 0x02) return null;
    var v = BigInt.zero;
    for (final b in value) {
      v = (v << 8) | BigInt.from(b);
    }
    return v;
  }

  String? asString() {
    if (tag == 0x0c) return utf8.decode(value, allowMalformed: true);
    if (tag == 0x1e) {
      return String.fromCharCodes([
        for (var i = 0; i + 1 < value.length; i += 2)
          (value[i] << 8) | value[i + 1],
      ]);
    }
    if (tag == 0x13 || tag == 0x16 || tag == 0x1a || tag == 0x14) {
      return String.fromCharCodes(value);
    }
    if (tag == 0x17 || tag == 0x18) return String.fromCharCodes(value);
    return null;
  }
}
