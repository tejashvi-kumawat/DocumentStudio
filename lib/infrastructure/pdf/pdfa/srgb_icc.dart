import 'dart:math' as math;
import 'dart:typed_data';

/// A standard sRGB (IEC 61966-2.1) ICC v2 display profile, generated in code
/// so the app ships no third-party profile file. Used as the PDF/A output
/// intent. Primaries are the Bradford-adapted D50 values of the ICC sRGB
/// profile; the tone curve is the exact sRGB piecewise function (1024 steps).
Uint8List buildSrgbIccProfile() {
  final tags = <(String, Uint8List)>[];

  Uint8List xyz(double x, double y, double z) {
    final b = ByteData(20);
    b.setUint32(0, 0x58595A20); // 'XYZ '
    b.setInt32(8, _s15(x));
    b.setInt32(12, _s15(y));
    b.setInt32(16, _s15(z));
    return b.buffer.asUint8List();
  }

  Uint8List desc(String text) {
    final ascii = [...text.codeUnits, 0];
    final b = BytesBuilder()
      ..add(_u32(0x64657363)) // 'desc'
      ..add(_u32(0))
      ..add(_u32(ascii.length))
      ..add(ascii)
      ..add(_u32(0)) // unicode language
      ..add(_u32(0)) // unicode count
      ..add([0, 0]) // scriptcode code
      ..addByte(0) // scriptcode count
      ..add(Uint8List(67));
    return b.toBytes();
  }

  Uint8List text(String t) =>
      (BytesBuilder()
            ..add(_u32(0x74657874)) // 'text'
            ..add(_u32(0))
            ..add([...t.codeUnits, 0]))
          .toBytes();

  Uint8List curve() {
    const n = 1024;
    final b = ByteData(12 + n * 2);
    b.setUint32(0, 0x63757276); // 'curv'
    b.setUint32(8, n);
    for (var i = 0; i < n; i++) {
      final v = i / (n - 1);
      final lin = v <= 0.04045
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      b.setUint16(12 + i * 2, (lin * 65535).round().clamp(0, 65535));
    }
    return b.buffer.asUint8List();
  }

  final trc = curve();
  tags
    ..add(('desc', desc('sRGB IEC61966-2.1')))
    ..add(('cprt', text('No copyright, use freely')))
    ..add(('wtpt', xyz(0.9642, 1.0, 0.8249)))
    ..add(('rXYZ', xyz(0.4360747, 0.2225045, 0.0139322)))
    ..add(('gXYZ', xyz(0.3850649, 0.7168786, 0.0971045)))
    ..add(('bXYZ', xyz(0.1430804, 0.0606169, 0.7141733)))
    ..add(('rTRC', trc))
    ..add(('gTRC', trc))
    ..add(('bTRC', trc));

  // Layout: header, tag table, then tag data (shared TRC stored once).
  final tableLen = 4 + tags.length * 12;
  var offset = 128 + tableLen;
  final data = BytesBuilder();
  final entries = <(String, int, int)>[];
  final placed = <Uint8List, int>{};
  for (final (sig, bytes) in tags) {
    final existing = placed[bytes];
    if (existing != null) {
      entries.add((sig, existing, bytes.length));
      continue;
    }
    entries.add((sig, offset, bytes.length));
    placed[bytes] = offset;
    data.add(bytes);
    offset += bytes.length;
    final pad = (4 - offset % 4) % 4;
    data.add(Uint8List(pad));
    offset += pad;
  }
  final size = offset;
  final out = ByteData(size);
  out
    ..setUint32(0, size)
    ..setUint32(8, 0x02100000) // version 2.1
    ..setUint32(12, 0x6D6E7472) // 'mntr'
    ..setUint32(16, 0x52474220) // 'RGB '
    ..setUint32(20, 0x58595A20) // 'XYZ '
    ..setUint16(24, 2026)
    ..setUint16(26, 1)
    ..setUint16(28, 1)
    ..setUint32(36, 0x61637370) // 'acsp'
    ..setUint32(64, 0) // perceptual
    ..setInt32(68, _s15(0.9642))
    ..setInt32(72, _s15(1.0))
    ..setInt32(76, _s15(0.8249));
  out.setUint32(128, entries.length);
  for (var i = 0; i < entries.length; i++) {
    final (sig, off, len) = entries[i];
    final o = 132 + i * 12;
    out
      ..setUint32(o, _sig(sig))
      ..setUint32(o + 4, off)
      ..setUint32(o + 8, len);
  }
  final bytes = out.buffer.asUint8List();
  bytes.setAll(128 + tableLen, data.toBytes());
  return bytes;
}

int _s15(double v) => (v * 65536).round();

int _sig(String s) =>
    (s.codeUnitAt(0) << 24) |
    (s.codeUnitAt(1) << 16) |
    (s.codeUnitAt(2) << 8) |
    s.codeUnitAt(3);

List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];
