import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:document_studio/infrastructure/pdf/signing/cms_builder.dart'
    show Der;
import 'package:document_studio/infrastructure/pdf/signing/der.dart';
import 'package:pointycastle/export.dart' as pc;

/// Pure-Dart PKI used on every platform (no OpenSSL binary needed): PKCS#12
/// read/write, RSA / ECDSA signing and verification, self-signed IDs.

// ---------------------------------------------------------------------------
// BER reader (indefinite lengths + constructed strings, keeps raw slices).

class Ber {
  Ber._(this.tag, this.content, this.raw, this.children);

  final int tag;
  final Uint8List content;

  /// Exact encoded bytes (header + content) as they appeared in the input.
  final Uint8List raw;
  final List<Ber>? children;

  bool get constructed => (tag & 0x20) != 0;
  List<Ber> get kids => children ?? const [];
  Ber operator [](int i) => kids[i];
  int get length => kids.length;

  static Ber parse(Uint8List bytes) => _read(bytes, 0).$1;

  static List<Ber> parseAll(Uint8List bytes) {
    final out = <Ber>[];
    var i = 0;
    while (i < bytes.length) {
      if (i + 1 < bytes.length && bytes[i] == 0 && bytes[i + 1] == 0) break;
      final r = _read(bytes, i);
      out.add(r.$1);
      i = r.$2;
    }
    return out;
  }

  static (Ber, int) _read(Uint8List b, int start) {
    var i = start;
    if (i >= b.length) throw const FormatException('BER truncated');
    final tag = b[i++];
    if (tag & 0x1f == 0x1f) {
      while (i < b.length && b[i] & 0x80 != 0) {
        i++;
      }
      i++;
    }
    if (i >= b.length) throw const FormatException('BER length missing');
    var len = b[i++];
    var indefinite = false;
    if (len == 0x80) {
      indefinite = true;
      len = -1;
    } else if (len & 0x80 != 0) {
      final n = len & 0x7f;
      if (n > 4 || i + n > b.length) {
        throw const FormatException('BER bad length');
      }
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | b[i++];
      }
    }
    final constructed = tag & 0x20 != 0;
    if (indefinite) {
      final kids = <Ber>[];
      var j = i;
      while (true) {
        if (j + 1 >= b.length) throw const FormatException('BER EOC missing');
        if (b[j] == 0 && b[j + 1] == 0) {
          j += 2;
          break;
        }
        final r = _read(b, j);
        kids.add(r.$1);
        j = r.$2;
      }
      final content = Uint8List.sublistView(b, i, j - 2);
      return (Ber._(tag, content, Uint8List.sublistView(b, start, j), kids), j);
    }
    if (i + len > b.length) throw const FormatException('BER truncated');
    final content = Uint8List.sublistView(b, i, i + len);
    List<Ber>? kids;
    if (constructed) {
      try {
        kids = parseAll(content);
      } catch (_) {
        kids = const [];
      }
    }
    return (
      Ber._(tag, content, Uint8List.sublistView(b, start, i + len), kids),
      i + len,
    );
  }

  /// Octet content, concatenating constructed (BER) string segments.
  Uint8List get octets {
    if (!constructed) return content;
    final out = BytesBuilder(copy: false);
    for (final k in kids) {
      out.add(k.octets);
    }
    return out.toBytes();
  }

  String? get oid {
    if (tag != 0x06) return null;
    return DerNode(tag, content).asOid();
  }

  BigInt get integer {
    var v = BigInt.zero;
    for (final x in content) {
      v = (v << 8) | BigInt.from(x);
    }
    if (content.isNotEmpty && content[0] & 0x80 != 0) {
      v -= BigInt.one << (content.length * 8);
    }
    return v;
  }

  int get intValue => integer.toInt();
}

// ---------------------------------------------------------------------------
// Helpers

Uint8List bigIntBytes(BigInt v, [int? length]) {
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  var bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  if (length != null && bytes.length < length) {
    final padded = Uint8List(length);
    padded.setRange(length - bytes.length, length, bytes);
    bytes = padded;
  } else if (length != null && bytes.length > length) {
    bytes = Uint8List.sublistView(bytes, bytes.length - length);
  }
  return bytes;
}

BigInt bytesToBigInt(List<int> b) {
  var v = BigInt.zero;
  for (final x in b) {
    v = (v << 8) | BigInt.from(x);
  }
  return v;
}

Uint8List _concat(List<List<int>> parts) {
  final out = BytesBuilder(copy: false);
  for (final p in parts) {
    out.add(p);
  }
  return out.toBytes();
}

Uint8List _utf8Der(String s) => Der.encodePrimitive(0x0c, utf8.encode(s));

Uint8List _bmp(String s, {bool nullTerminated = false}) {
  final out = <int>[];
  for (final c in s.codeUnits) {
    out
      ..add(c >> 8)
      ..add(c & 0xff);
  }
  if (nullTerminated) out.addAll([0, 0]);
  return Uint8List.fromList(out);
}

pc.SecureRandom _secureRandom() {
  final rnd = math.Random.secure();
  final seed = Uint8List.fromList(List.generate(32, (_) => rnd.nextInt(256)));
  return pc.FortunaRandom()..seed(pc.KeyParameter(seed));
}

Uint8List randomBytes(int n) {
  final rnd = math.Random.secure();
  return Uint8List.fromList(List.generate(n, (_) => rnd.nextInt(256)));
}

// ---------------------------------------------------------------------------
// Hashes

const oidSha1 = '1.3.14.3.2.26';
const oidSha224 = '2.16.840.1.101.3.4.2.4';
const oidSha256 = '2.16.840.1.101.3.4.2.1';
const oidSha384 = '2.16.840.1.101.3.4.2.2';
const oidSha512 = '2.16.840.1.101.3.4.2.3';

crypto.Hash? hashForOid(String? oid) => switch (oid) {
  oidSha1 => crypto.sha1,
  oidSha224 => crypto.sha224,
  oidSha256 => crypto.sha256,
  oidSha384 => crypto.sha384,
  oidSha512 => crypto.sha512,
  '1.2.840.113549.1.1.5' || '1.2.840.10045.4.1' => crypto.sha1,
  '1.2.840.113549.1.1.14' || '1.2.840.10045.4.3.1' => crypto.sha224,
  '1.2.840.113549.1.1.11' || '1.2.840.10045.4.3.2' => crypto.sha256,
  '1.2.840.113549.1.1.12' || '1.2.840.10045.4.3.3' => crypto.sha384,
  '1.2.840.113549.1.1.13' || '1.2.840.10045.4.3.4' => crypto.sha512,
  _ => null,
};

String? hashOidForSignatureOid(String oid) => switch (oid) {
  '1.2.840.113549.1.1.5' || '1.2.840.10045.4.1' => oidSha1,
  '1.2.840.113549.1.1.14' || '1.2.840.10045.4.3.1' => oidSha224,
  '1.2.840.113549.1.1.11' || '1.2.840.10045.4.3.2' => oidSha256,
  '1.2.840.113549.1.1.12' || '1.2.840.10045.4.3.3' => oidSha384,
  '1.2.840.113549.1.1.13' || '1.2.840.10045.4.3.4' => oidSha512,
  _ => null,
};

// ---------------------------------------------------------------------------
// Keys

abstract class DartPrivateKey {
  const DartPrivateKey();

  /// Signs [data] with SHA-256 (PKCS#1 v1.5 for RSA, DER ECDSA for EC).
  Uint8List signSha256(Uint8List data);

  /// DER PKCS#8 PrivateKeyInfo.
  Uint8List toPkcs8();
}

class DartRsaPrivateKey extends DartPrivateKey {
  DartRsaPrivateKey({
    required this.n,
    required this.e,
    required this.d,
    required this.p,
    required this.q,
    BigInt? dp,
    BigInt? dq,
    BigInt? qInv,
  }) : dp = dp ?? d % (p - BigInt.one),
       dq = dq ?? d % (q - BigInt.one),
       qInv = qInv ?? q.modInverse(p);

  final BigInt n, e, d, p, q, dp, dq, qInv;

  int get byteLength => (n.bitLength + 7) ~/ 8;

  BigInt _private(BigInt m) {
    if (p <= BigInt.one || q <= BigInt.one) return m.modPow(d, n);
    final m1 = m.modPow(dp, p);
    final m2 = m.modPow(dq, q);
    final h = (qInv * (m1 - m2)) % p;
    return m2 + h * q;
  }

  @override
  Uint8List signSha256(Uint8List data) {
    final digest = crypto.sha256.convert(data).bytes;
    return signDigestInfo(digestInfo(oidSha256, digest));
  }

  Uint8List signDigestInfo(Uint8List t) {
    final k = byteLength;
    if (t.length + 11 > k) throw StateError('RSA key too small');
    final em = Uint8List(k);
    em[1] = 0x01;
    for (var i = 2; i < k - t.length - 1; i++) {
      em[i] = 0xff;
    }
    em.setRange(k - t.length, k, t);
    return bigIntBytes(_private(bytesToBigInt(em)), k);
  }

  Uint8List get publicKeyDer => Der.sequence([Der.integer(n), Der.integer(e)]);

  Uint8List get spki => Der.sequence([
    Der.sequence([Der.objectIdentifier('1.2.840.113549.1.1.1'), Der.null_()]),
    Der.bitString(publicKeyDer),
  ]);

  @override
  Uint8List toPkcs8() => Der.sequence([
    Der.integer(BigInt.zero),
    Der.sequence([Der.objectIdentifier('1.2.840.113549.1.1.1'), Der.null_()]),
    Der.octetString(
      Der.sequence([
        Der.integer(BigInt.zero),
        Der.integer(n),
        Der.integer(e),
        Der.integer(d),
        Der.integer(p),
        Der.integer(q),
        Der.integer(dp),
        Der.integer(dq),
        Der.integer(qInv),
      ]),
    ),
  ]);
}

class DartEcPrivateKey extends DartPrivateKey {
  DartEcPrivateKey({required this.curveOid, required this.d});

  final String curveOid;
  final BigInt d;

  @override
  Uint8List signSha256(Uint8List data) {
    final params = ecDomainForOid(curveOid);
    if (params == null) throw StateError('Unsupported EC curve $curveOid');
    final digest = Uint8List.fromList(crypto.sha256.convert(data).bytes);
    final signer = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64))
      ..init(
        true,
        pc.PrivateKeyParameter<pc.ECPrivateKey>(pc.ECPrivateKey(d, params)),
      );
    var sig = signer.generateSignature(digest) as pc.ECSignature;
    sig = sig.normalize(params);
    return Der.sequence([Der.integer(sig.r), Der.integer(sig.s)]);
  }

  @override
  Uint8List toPkcs8() => Der.sequence([
    Der.integer(BigInt.zero),
    Der.sequence([
      Der.objectIdentifier('1.2.840.10045.2.1'),
      Der.objectIdentifier(curveOid),
    ]),
    Der.octetString(
      Der.sequence([Der.integer(BigInt.one), Der.octetString(bigIntBytes(d))]),
    ),
  ]);
}

pc.ECDomainParameters? ecDomainForOid(String oid) => switch (oid) {
  '1.2.840.10045.3.1.7' => pc.ECCurve_secp256r1(),
  '1.3.132.0.34' => pc.ECCurve_secp384r1(),
  '1.3.132.0.35' => pc.ECCurve_secp521r1(),
  '1.3.132.0.10' => pc.ECCurve_secp256k1(),
  _ => null,
};

Uint8List digestInfo(String hashOid, List<int> digest) => Der.sequence([
  Der.sequence([Der.objectIdentifier(hashOid), Der.null_()]),
  Der.octetString(Uint8List.fromList(digest)),
]);

DartPrivateKey parsePkcs8(Uint8List der) {
  final root = Ber.parse(der);
  final alg = root[1][0].oid;
  final keyOctets = root[2].octets;
  if (alg == '1.2.840.113549.1.1.1') {
    final k = Ber.parse(keyOctets);
    return DartRsaPrivateKey(
      n: k[1].integer,
      e: k[2].integer,
      d: k[3].integer,
      p: k[4].integer,
      q: k[5].integer,
      dp: k[6].integer,
      dq: k[7].integer,
      qInv: k[8].integer,
    );
  }
  if (alg == '1.2.840.10045.2.1') {
    var curve = root[1].length > 1 ? root[1][1].oid : null;
    final k = Ber.parse(keyOctets);
    for (final c in k.kids.skip(2)) {
      if (c.tag == 0xa0 && c.kids.isNotEmpty) curve ??= c[0].oid;
    }
    if (curve == null) throw StateError('EC key without curve');
    return DartEcPrivateKey(curveOid: curve, d: bytesToBigInt(k[1].octets));
  }
  throw StateError('Unsupported private key type ($alg)');
}

// ---------------------------------------------------------------------------
// Verification

/// Public key from a SubjectPublicKeyInfo DER.
class DartPublicKey {
  DartPublicKey._({this.n, this.e, this.curveOid, this.point});

  factory DartPublicKey.fromSpki(Uint8List spki) {
    final root = Ber.parse(spki);
    final alg = root[0][0].oid;
    final bits = root[1].content.sublist(1);
    if (alg == '1.2.840.10045.2.1') {
      return DartPublicKey._(curveOid: root[0][1].oid, point: bits);
    }
    final k = Ber.parse(Uint8List.fromList(bits));
    return DartPublicKey._(n: k[0].integer, e: k[1].integer);
  }

  final BigInt? n;
  final BigInt? e;
  final String? curveOid;
  final Uint8List? point;

  bool get isRsa => n != null;

  /// Verifies [signature] over [data] for signature algorithm [sigAlgOid]
  /// (or plain rsaEncryption / ecPublicKey with [hashOid]).
  bool verify({
    required Uint8List data,
    required Uint8List signature,
    required String? hashOid,
  }) {
    final hash = hashForOid(hashOid);
    if (hash == null) return false;
    final digest = hash.convert(data).bytes;
    if (isRsa) {
      final k = (n!.bitLength + 7) ~/ 8;
      final m = bytesToBigInt(signature).modPow(e!, n!);
      final em = bigIntBytes(m, k);
      if (em[0] != 0 || em[1] != 1) return false;
      var i = 2;
      while (i < em.length && em[i] == 0xff) {
        i++;
      }
      if (i >= em.length || em[i] != 0) return false;
      try {
        final di = Ber.parse(Uint8List.sublistView(em, i + 1));
        final got = di[1].octets;
        if (got.length != digest.length) return false;
        for (var j = 0; j < got.length; j++) {
          if (got[j] != digest[j]) return false;
        }
        return true;
      } catch (_) {
        return false;
      }
    }
    final params = ecDomainForOid(curveOid ?? '');
    if (params == null || point == null) return false;
    try {
      final q = params.curve.decodePoint(point!);
      final sig = Ber.parse(signature);
      final verifier = pc.ECDSASigner()
        ..init(
          false,
          pc.PublicKeyParameter<pc.ECPublicKey>(pc.ECPublicKey(q, params)),
        );
      return verifier.verifySignature(
        Uint8List.fromList(digest),
        pc.ECSignature(sig[0].integer, sig[1].integer),
      );
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// PKCS#12

class Pkcs12WrongPassword implements Exception {
  @override
  String toString() => 'Wrong password for this digital ID.';
}

class Pkcs12Unsupported implements Exception {
  Pkcs12Unsupported(this.what);
  final String what;
  @override
  String toString() => 'Unsupported PKCS#12 feature: $what';
}

class Pkcs12Identity {
  Pkcs12Identity({
    required this.key,
    required this.certificateDer,
    required this.chainDer,
    this.friendlyName,
  });

  final DartPrivateKey key;
  final Uint8List certificateDer;

  /// Other certificates in the file (issuer chain).
  final List<Uint8List> chainDer;
  final String? friendlyName;
}

Uint8List _pkcs12Kdf({
  required crypto.Hash hash,
  required int u,
  required Uint8List password,
  required Uint8List salt,
  required int iterations,
  required int id,
  required int n,
}) {
  const v = 64;
  final d = Uint8List(v)..fillRange(0, v, id);
  Uint8List fill(Uint8List src) {
    if (src.isEmpty) return Uint8List(0);
    final len = v * ((src.length + v - 1) ~/ v);
    final out = Uint8List(len);
    for (var i = 0; i < len; i++) {
      out[i] = src[i % src.length];
    }
    return out;
  }

  final i0 = _concat([fill(salt), fill(password)]);
  final c = (n + u - 1) ~/ u;
  final out = BytesBuilder(copy: false);
  for (var round = 0; round < c; round++) {
    var a = hash.convert(_concat([d, i0])).bytes;
    for (var r = 1; r < iterations; r++) {
      a = hash.convert(a).bytes;
    }
    out.add(a);
    final b = Uint8List(v);
    for (var k = 0; k < v; k++) {
      b[k] = a[k % a.length];
    }
    for (var j = 0; j < i0.length ~/ v; j++) {
      var carry = 1;
      for (var k = v - 1; k >= 0; k--) {
        final idx = j * v + k;
        final sum = i0[idx] + b[k] + carry;
        i0[idx] = sum & 0xff;
        carry = sum >> 8;
      }
    }
  }
  return Uint8List.sublistView(out.toBytes(), 0, n);
}

Uint8List _cbc(
  pc.BlockCipher engine,
  pc.CipherParameters keyParams,
  Uint8List iv,
  Uint8List data, {
  required bool encrypt,
}) {
  final cbc = pc.CBCBlockCipher(engine)
    ..init(encrypt, pc.ParametersWithIV(keyParams, iv));
  final bs = cbc.blockSize;
  Uint8List input = data;
  if (encrypt) {
    final pad = bs - (data.length % bs);
    input = Uint8List(data.length + pad)
      ..setRange(0, data.length, data)
      ..fillRange(data.length, data.length + pad, pad);
  } else if (data.length % bs != 0 || data.isEmpty) {
    throw Pkcs12WrongPassword();
  }
  final out = Uint8List(input.length);
  for (var off = 0; off < input.length; off += bs) {
    cbc.processBlock(input, off, out, off);
  }
  if (encrypt) return out;
  final pad = out.last;
  if (pad < 1 || pad > bs) throw Pkcs12WrongPassword();
  for (var i = out.length - pad; i < out.length; i++) {
    if (out[i] != pad) throw Pkcs12WrongPassword();
  }
  return Uint8List.sublistView(out, 0, out.length - pad);
}

Uint8List _pbkdf2(
  String? prfOid,
  Uint8List password,
  Uint8List salt,
  int iterations,
  int keyLen,
) {
  final pc.Digest digest = switch (prfOid) {
    '1.2.840.113549.2.9' => pc.SHA256Digest(),
    '1.2.840.113549.2.10' => pc.SHA384Digest(),
    '1.2.840.113549.2.11' => pc.SHA512Digest(),
    '1.2.840.113549.2.8' => pc.SHA224Digest(),
    _ => pc.SHA1Digest(),
  };
  final blockLen = digest.byteLength;
  final kdf = pc.PBKDF2KeyDerivator(pc.HMac(digest, blockLen))
    ..init(pc.Pbkdf2Parameters(salt, iterations, keyLen));
  return kdf.process(password);
}

/// Decrypts PKCS#12 / PKCS#8 encrypted content for [algId].
Uint8List _pbeDecrypt(Ber algId, Uint8List data, String password) {
  final oid = algId[0].oid;
  if (oid == '1.2.840.113549.1.5.13') {
    final params = algId[1];
    final kdf = params[0];
    if (kdf[0].oid != '1.2.840.113549.1.5.12') {
      throw Pkcs12Unsupported('key derivation ${kdf[0].oid}');
    }
    final kp = kdf[1];
    final salt = kp[0].octets;
    final iter = kp[1].intValue;
    String? prf;
    for (final c in kp.kids.skip(2)) {
      if (c.tag == 0x30) prf = c[0].oid;
    }
    final enc = params[1];
    final encOid = enc[0].oid;
    final iv = enc[1].octets;
    final pw = Uint8List.fromList(utf8.encode(password));
    switch (encOid) {
      case '2.16.840.1.101.3.4.1.2':
      case '2.16.840.1.101.3.4.1.22':
      case '2.16.840.1.101.3.4.1.42':
        final keyLen = encOid!.endsWith('.2')
            ? 16
            : encOid.endsWith('.22')
            ? 24
            : 32;
        final key = _pbkdf2(prf, pw, salt, iter, keyLen);
        return _cbc(
          pc.AESEngine(),
          pc.KeyParameter(key),
          iv,
          data,
          encrypt: false,
        );
      case '1.2.840.113549.3.7':
        final key = _pbkdf2(prf, pw, salt, iter, 24);
        return _cbc(
          pc.DESedeEngine(),
          pc.KeyParameter(key),
          iv,
          data,
          encrypt: false,
        );
    }
    throw Pkcs12Unsupported('cipher $encOid');
  }
  final salt = algId[1][0].octets;
  final iter = algId[1][1].intValue;
  final pw = _bmp(password, nullTerminated: true);
  Uint8List kdf(int id, int n) => _pkcs12Kdf(
    hash: crypto.sha1,
    u: 20,
    password: pw,
    salt: salt,
    iterations: iter,
    id: id,
    n: n,
  );
  switch (oid) {
    case '1.2.840.113549.1.12.1.3':
      return _cbc(
        pc.DESedeEngine(),
        pc.KeyParameter(kdf(1, 24)),
        kdf(2, 8),
        data,
        encrypt: false,
      );
    case '1.2.840.113549.1.12.1.4':
      final k = kdf(1, 16);
      final key = _concat([k, k.sublist(0, 8)]);
      return _cbc(
        pc.DESedeEngine(),
        pc.KeyParameter(key),
        kdf(2, 8),
        data,
        encrypt: false,
      );
    case '1.2.840.113549.1.12.1.5':
      return _cbc(
        pc.RC2Engine(),
        pc.RC2Parameters(kdf(1, 16), bits: 128),
        kdf(2, 8),
        data,
        encrypt: false,
      );
    case '1.2.840.113549.1.12.1.6':
      return _cbc(
        pc.RC2Engine(),
        pc.RC2Parameters(kdf(1, 5), bits: 40),
        kdf(2, 8),
        data,
        encrypt: false,
      );
  }
  throw Pkcs12Unsupported('encryption $oid');
}

bool _checkMac(Ber pfx, Uint8List authSafe, String password) {
  if (pfx.length < 3) return true;
  final mac = pfx[2];
  final di = mac[0];
  final algOid = di[0][0].oid;
  final expected = di[1].octets;
  final salt = mac[1].octets;
  final iter = mac.length > 2 ? mac[2].intValue : 1;
  final (crypto.Hash hash, int u) = switch (algOid) {
    oidSha256 => (crypto.sha256, 32),
    oidSha384 => (crypto.sha384, 48),
    oidSha512 => (crypto.sha512, 64),
    oidSha1 => (crypto.sha1, 20),
    _ => (crypto.sha1, -1),
  };
  if (u < 0) return true;
  bool tryPw(Uint8List pw) {
    final key = _pkcs12Kdf(
      hash: hash,
      u: u,
      password: pw,
      salt: salt,
      iterations: iter,
      id: 3,
      n: u,
    );
    final got = crypto.Hmac(hash, key).convert(authSafe).bytes;
    if (got.length != expected.length) return false;
    for (var i = 0; i < got.length; i++) {
      if (got[i] != expected[i]) return false;
    }
    return true;
  }

  return tryPw(_bmp(password, nullTerminated: true)) ||
      (password.isEmpty && tryPw(Uint8List(0)));
}

/// Parses a PKCS#12 (.p12 / .pfx) file in pure Dart.
Pkcs12Identity parsePkcs12(Uint8List bytes, String password) {
  final pfx = Ber.parse(bytes);
  final authSafeCi = pfx[1];
  if (authSafeCi[0].oid != '1.2.840.113549.1.7.1') {
    throw Pkcs12Unsupported('public-key protected PKCS#12');
  }
  final authSafe = authSafeCi[1][0].octets;
  if (!_checkMac(pfx, authSafe, password)) throw Pkcs12WrongPassword();

  final keys = <(Uint8List?, DartPrivateKey)>[];
  final certs = <(Uint8List?, Uint8List, String?)>[];

  void readBags(Uint8List safeContents) {
    for (final bag in Ber.parse(safeContents).kids) {
      final bagId = bag[0].oid;
      final value = bag[1][0];
      Uint8List? localKeyId;
      String? friendly;
      if (bag.length > 2) {
        for (final attr in bag[2].kids) {
          final aOid = attr[0].oid;
          final v = attr[1].kids.isEmpty ? null : attr[1][0];
          if (v == null) continue;
          if (aOid == '1.2.840.113549.1.9.21') localKeyId = v.octets;
          if (aOid == '1.2.840.113549.1.9.20') {
            final b = v.octets;
            final units = <int>[
              for (var i = 0; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1],
            ];
            friendly = String.fromCharCodes(units);
          }
        }
      }
      switch (bagId) {
        case '1.2.840.113549.1.12.10.1.1':
          keys.add((localKeyId, parsePkcs8(value.raw)));
        case '1.2.840.113549.1.12.10.1.2':
          final plain = _pbeDecrypt(value[0], value[1].octets, password);
          keys.add((localKeyId, parsePkcs8(plain)));
        case '1.2.840.113549.1.12.10.1.3':
          if (value[0].oid == '1.2.840.113549.1.9.22.1') {
            certs.add((localKeyId, value[1][0].octets, friendly));
          }
      }
    }
  }

  for (final ci in Ber.parse(authSafe).kids) {
    final type = ci[0].oid;
    if (type == '1.2.840.113549.1.7.1') {
      readBags(ci[1][0].octets);
    } else if (type == '1.2.840.113549.1.7.6') {
      final ed = ci[1][0];
      final eci = ed[1];
      final alg = eci[1];
      final encContent = eci[2];
      final plain = _pbeDecrypt(alg, encContent.octets, password);
      readBags(plain);
    }
  }
  if (keys.isEmpty)
    throw StateError('This file does not contain a private key.');
  if (certs.isEmpty)
    throw StateError('This file does not contain a certificate.');
  final key = keys.first;
  var signer = certs.first;
  if (key.$1 != null) {
    for (final c in certs) {
      final id = c.$1;
      if (id != null && _eq(id, key.$1!)) signer = c;
    }
  }
  return Pkcs12Identity(
    key: key.$2,
    certificateDer: signer.$2,
    chainDer: [
      for (final c in certs)
        if (!identical(c, signer)) c.$2,
    ],
    friendlyName: signer.$3,
  );
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Uint8List _encryptPbes2(Uint8List plain, String password, int iterations) {
  final salt = randomBytes(16);
  final iv = randomBytes(16);
  final key = _pbkdf2(
    '1.2.840.113549.2.9',
    Uint8List.fromList(utf8.encode(password)),
    salt,
    iterations,
    32,
  );
  final enc = _cbc(
    pc.AESEngine(),
    pc.KeyParameter(key),
    iv,
    plain,
    encrypt: true,
  );
  final alg = Der.sequence([
    Der.objectIdentifier('1.2.840.113549.1.5.13'),
    Der.sequence([
      Der.sequence([
        Der.objectIdentifier('1.2.840.113549.1.5.12'),
        Der.sequence([
          Der.octetString(salt),
          Der.integer(BigInt.from(iterations)),
          Der.sequence([
            Der.objectIdentifier('1.2.840.113549.2.9'),
            Der.null_(),
          ]),
        ]),
      ]),
      Der.sequence([
        Der.objectIdentifier('2.16.840.1.101.3.4.1.42'),
        Der.octetString(iv),
      ]),
    ]),
  ]);
  return Der.sequence([alg, Der.octetString(enc)]);
}

/// Writes an OpenSSL-3-compatible PKCS#12 (PBES2/AES-256, SHA-256 MAC).
Uint8List writePkcs12({
  required DartPrivateKey key,
  required Uint8List certificateDer,
  required String password,
  String? friendlyName,
  int iterations = 2048,
}) {
  final localKeyId = Uint8List.fromList(
    crypto.sha1.convert(certificateDer).bytes,
  );
  final attrs = Der.set([
    Der.sequence([
      Der.objectIdentifier('1.2.840.113549.1.9.21'),
      Der.set([Der.octetString(localKeyId)]),
    ]),
    if (friendlyName != null && friendlyName.isNotEmpty)
      Der.sequence([
        Der.objectIdentifier('1.2.840.113549.1.9.20'),
        Der.set([Der.encodePrimitive(0x1e, _bmp(friendlyName))]),
      ]),
  ]);
  final certBag = Der.sequence([
    Der.objectIdentifier('1.2.840.113549.1.12.10.1.3'),
    Der.context(0, [
      Der.sequence([
        Der.objectIdentifier('1.2.840.113549.1.9.22.1'),
        Der.context(0, [Der.octetString(certificateDer)]),
      ]),
    ]),
    attrs,
  ]);
  final keyBag = Der.sequence([
    Der.objectIdentifier('1.2.840.113549.1.12.10.1.2'),
    Der.context(0, [_encryptPbes2(key.toPkcs8(), password, iterations)]),
    attrs,
  ]);
  Uint8List dataCi(Uint8List content) => Der.sequence([
    Der.objectIdentifier('1.2.840.113549.1.7.1'),
    Der.context(0, [Der.octetString(content)]),
  ]);
  final authSafe = Der.sequence([
    dataCi(Der.sequence([certBag])),
    dataCi(Der.sequence([keyBag])),
  ]);
  final macSalt = randomBytes(16);
  final macKey = _pkcs12Kdf(
    hash: crypto.sha256,
    u: 32,
    password: _bmp(password, nullTerminated: true),
    salt: macSalt,
    iterations: iterations,
    id: 3,
    n: 32,
  );
  final mac = crypto.Hmac(crypto.sha256, macKey).convert(authSafe).bytes;
  return Der.sequence([
    Der.integer(BigInt.from(3)),
    dataCi(authSafe),
    Der.sequence([
      Der.sequence([
        Der.sequence([Der.objectIdentifier(oidSha256), Der.null_()]),
        Der.octetString(Uint8List.fromList(mac)),
      ]),
      Der.octetString(macSalt),
      Der.integer(BigInt.from(iterations)),
    ]),
  ]);
}

// ---------------------------------------------------------------------------
// Self-signed IDs

DartRsaPrivateKey generateRsaKeySync(int bits) {
  final gen = pc.RSAKeyGenerator()
    ..init(
      pc.ParametersWithRandom(
        pc.RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64),
        _secureRandom(),
      ),
    );
  final pair = gen.generateKeyPair();
  final priv = pair.privateKey;
  final pub = pair.publicKey;
  return DartRsaPrivateKey(
    n: pub.modulus!,
    e: pub.exponent!,
    d: priv.privateExponent!,
    p: priv.p!,
    q: priv.q!,
  );
}

Uint8List _name({required String cn, String org = '', String email = ''}) {
  Uint8List rdn(String oid, Uint8List value) => Der.set([
    Der.sequence([Der.objectIdentifier(oid), value]),
  ]);
  return Der.sequence([
    rdn('2.5.4.3', _utf8Der(cn)),
    if (org.isNotEmpty) rdn('2.5.4.10', _utf8Der(org)),
    if (email.isNotEmpty) rdn('1.2.840.113549.1.9.1', Der.ia5String(email)),
  ]);
}

Uint8List _time(DateTime t) {
  final u = t.toUtc();
  if (u.year >= 2050) {
    String p(int n) => n.toString().padLeft(2, '0');
    final s =
        '${u.year}${p(u.month)}${p(u.day)}${p(u.hour)}${p(u.minute)}'
        '${p(u.second)}Z';
    return Der.encodePrimitive(0x18, Uint8List.fromList(s.codeUnits));
  }
  return Der.utcTime(u);
}

/// Builds a self-signed X.509 certificate (DER) for [key].
Uint8List buildSelfSignedCertificate({
  required DartRsaPrivateKey key,
  required String commonName,
  String organization = '',
  String email = '',
  int days = 1095,
}) {
  final now = DateTime.now().toUtc();
  final serial = randomBytes(16)..[0] &= 0x7f;
  final name = _name(cn: commonName, org: organization, email: email);
  final sigAlg = Der.sequence([
    Der.objectIdentifier('1.2.840.113549.1.1.11'),
    Der.null_(),
  ]);
  final spki = key.spki;
  final ski = crypto.sha1.convert(key.publicKeyDer).bytes;
  Uint8List ext(String oid, Uint8List value, {bool critical = false}) =>
      Der.sequence([
        Der.objectIdentifier(oid),
        if (critical) Der.encodePrimitive(0x01, Uint8List.fromList([0xff])),
        Der.octetString(value),
      ]);
  final extensions = Der.context(3, [
    Der.sequence([
      ext('2.5.29.19', Der.sequence([]), critical: true),
      ext(
        '2.5.29.15',
        Der.encodePrimitive(0x03, Uint8List.fromList([0x06, 0xc0])),
        critical: true,
      ),
      ext(
        '2.5.29.37',
        Der.sequence([
          Der.objectIdentifier('1.3.6.1.5.5.7.3.4'),
          Der.objectIdentifier('1.3.6.1.5.5.7.3.2'),
          Der.objectIdentifier('1.3.6.1.4.1.311.10.3.12'),
        ]),
      ),
      ext('2.5.29.14', Der.octetString(Uint8List.fromList(ski))),
    ]),
  ]);
  final tbs = Der.sequence([
    Der.context(0, [Der.integer(BigInt.two)]),
    Der.integerBytes(serial),
    sigAlg,
    name,
    Der.sequence([
      _time(now.subtract(const Duration(minutes: 5))),
      _time(now.add(Duration(days: days))),
    ]),
    name,
    spki,
    extensions,
  ]);
  final sig = key.signSha256(tbs);
  return Der.sequence([tbs, sigAlg, Der.bitString(sig)]);
}

/// Creates a new self-signed digital ID as PKCS#12 bytes (off the UI isolate).
Future<Uint8List> createSelfSignedPkcs12({
  required String commonName,
  required String password,
  String organization = '',
  String email = '',
  int days = 1095,
  int bits = 2048,
}) {
  return Isolate.run(() {
    final key = generateRsaKeySync(bits);
    final cert = buildSelfSignedCertificate(
      key: key,
      commonName: commonName,
      organization: organization,
      email: email,
      days: days,
    );
    return writePkcs12(
      key: key,
      certificateDer: cert,
      password: password,
      friendlyName: commonName,
    );
  });
}
