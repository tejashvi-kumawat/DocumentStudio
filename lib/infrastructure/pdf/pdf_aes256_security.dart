import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/pdf_standard_security.dart';
import 'package:pointycastle/export.dart';

/// Standard Security Handler **revision 6 / AES-256** (ISO 32000-2, PDF 2.0),
/// the strongest PDF encryption: random 256-bit file key, key wrapped by a
/// hardened SHA-256/384/512 + AES iteration (Algorithm 2.B) instead of MD5/RC4,
/// random IV for every string and stream, no per-object key derivation.
class PdfAes256SecurityMaterial implements PdfSecurityMaterial {
  PdfAes256SecurityMaterial._({
    required this.fileKey,
    required this.o,
    required this.u,
    required this.oe,
    required this.ue,
    required this.perms,
    required this.permissions,
    required this.fileId,
  });

  final Uint8List fileKey;
  final Uint8List o;
  final Uint8List u;
  final Uint8List oe;
  final Uint8List ue;
  final Uint8List perms;

  @override
  final int permissions;
  @override
  final Uint8List fileId;

  @override
  Uint8List encryptString(Uint8List data, int objectNumber, int generation) =>
      aesEncryptPdfContent(fileKey, data);

  @override
  Uint8List encryptStream(Uint8List data, int objectNumber, int generation) =>
      aesEncryptPdfContent(fileKey, data);

  static final _rng = math.Random.secure();

  static Uint8List _random(int n) =>
      Uint8List.fromList([for (var i = 0; i < n; i++) _rng.nextInt(256)]);

  /// Password as the spec wants it: UTF-8, at most 127 bytes.
  static Uint8List _pw(String s) {
    final b = utf8.encode(s);
    return Uint8List.fromList(b.length > 127 ? b.sublist(0, 127) : b);
  }

  static Uint8List _aesCbcNoPad(
    Uint8List key,
    Uint8List iv,
    Uint8List data, {
    bool encrypt = true,
  }) {
    final c = CBCBlockCipher(AESEngine())
      ..init(encrypt, ParametersWithIV(KeyParameter(key), iv));
    final out = Uint8List(data.length);
    for (var off = 0; off < data.length; off += 16) {
      c.processBlock(data, off, out, off);
    }
    return out;
  }

  static Uint8List _sha(int bits, Uint8List data) {
    final Digest d = switch (bits) {
      256 => SHA256Digest(),
      384 => SHA384Digest(),
      _ => SHA512Digest(),
    };
    return d.process(data);
  }

  /// Algorithm 2.B — the revision 6 hash.
  static Uint8List hashR6(Uint8List password, Uint8List salt, Uint8List udata) {
    var k = _sha(256, Uint8List.fromList([...password, ...salt, ...udata]));
    var e = Uint8List.fromList([0]);
    var i = 0;
    while (i < 64 || e.last > i - 32) {
      final unit = Uint8List.fromList([...password, ...k, ...udata]);
      final k1 = Uint8List(unit.length * 64);
      for (var r = 0; r < 64; r++) {
        k1.setRange(r * unit.length, (r + 1) * unit.length, unit);
      }
      e = _aesCbcNoPad(
        Uint8List.fromList(k.sublist(0, 16)),
        Uint8List.fromList(k.sublist(16, 32)),
        k1,
      );
      var mod = 0;
      for (var b = 0; b < 16; b++) {
        mod += e[b];
      }
      mod %= 3;
      k = _sha(mod == 0 ? 256 : (mod == 1 ? 384 : 512), e);
      i++;
    }
    return Uint8List.fromList(k.sublist(0, 32));
  }

  /// Builds the encryption entries. An empty [ownerPassword] gets a random
  /// 32-byte one when restrictions are set, or the open password otherwise.
  factory PdfAes256SecurityMaterial.build({
    required String userPassword,
    String ownerPassword = '',
    required bool allowPrinting,
    required bool allowModify,
    required bool allowExtract,
    required bool allowAnnotate,
    Uint8List? fileId,
  }) {
    final restricted =
        !allowPrinting || !allowModify || !allowExtract || !allowAnnotate;
    final owner = ownerPassword.isNotEmpty
        ? ownerPassword
        : (restricted ? base64Url.encode(_random(24)) : userPassword);
    final p = pdfPermissionFlags(
      allowPrinting: allowPrinting,
      allowModify: allowModify,
      allowExtract: allowExtract,
      allowAnnotate: allowAnnotate,
    );
    final fileKey = _random(32);
    final upw = _pw(userPassword);
    final opw = _pw(owner);
    final empty = Uint8List(0);
    final zeroIv = Uint8List(16);

    final uVal = _random(8);
    final uKey = _random(8);
    final u = Uint8List.fromList([
      ...hashR6(upw, uVal, empty),
      ...uVal,
      ...uKey,
    ]);
    final ue = _aesCbcNoPad(hashR6(upw, uKey, empty), zeroIv, fileKey);

    final oVal = _random(8);
    final oKey = _random(8);
    final o = Uint8List.fromList([
      ...hashR6(opw, oVal, u),
      ...oVal,
      ...oKey,
    ]);
    final oe = _aesCbcNoPad(hashR6(opw, oKey, u), zeroIv, fileKey);

    final permsPlain = Uint8List.fromList([
      p & 0xFF,
      (p >> 8) & 0xFF,
      (p >> 16) & 0xFF,
      (p >> 24) & 0xFF,
      0xFF, 0xFF, 0xFF, 0xFF,
      0x54, // 'T': metadata is encrypted
      0x61, 0x64, 0x62, // "adb"
      ..._random(4),
    ]);
    final ecb = AESEngine()..init(true, KeyParameter(fileKey));
    final perms = Uint8List(16);
    ecb.processBlock(permsPlain, 0, perms, 0);

    return PdfAes256SecurityMaterial._(
      fileKey: fileKey,
      o: o,
      u: u,
      oe: oe,
      ue: ue,
      perms: perms,
      permissions: p,
      fileId: fileId ?? _random(16),
    );
  }

  /// True when [password] opens a file written with these entries (used by
  /// tests; mirrors what a reader does).
  static bool verifyUser(String password, Uint8List u) {
    final pw = _pw(password);
    final h = hashR6(pw, Uint8List.fromList(u.sublist(32, 40)), Uint8List(0));
    for (var i = 0; i < 32; i++) {
      if (h[i] != u[i]) return false;
    }
    return true;
  }
}
