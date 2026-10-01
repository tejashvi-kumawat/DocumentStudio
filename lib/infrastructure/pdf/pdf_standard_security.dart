import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Padding string from ISO 32000-1 §7.6.3.3 (Algorithm 2).
final pdfPasswordPadding = Uint8List.fromList(const [
  0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, //
  0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08, //
  0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, //
  0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
]);

/// Builds the `/P` permission flags (signed 32-bit) for revision 3/4.
int pdfPermissionFlags({
  required bool allowPrinting,
  required bool allowModify,
  required bool allowExtract,
  required bool allowAnnotate,
}) {
  // Bits 1–2 must be zero; high bits set for compatibility (ISO 32000 Table 22).
  var p = 0xFFFFF0C0;
  if (allowPrinting) {
    p |= 0x04; // bit 3
    p |= 0x800; // bit 12 high-quality print
  }
  if (allowModify) {
    p |= 0x08; // bit 4
    p |= 0x400; // bit 11 assemble
  }
  if (allowExtract) {
    p |= 0x10; // bit 5
    p |= 0x200; // bit 10 accessibility extract
  }
  if (allowAnnotate) {
    p |= 0x20; // bit 6
    p |= 0x100; // bit 9 fill form fields
  }
  return p > 0x7FFFFFFF ? p - 0x100000000 : p;
}

Uint8List padPdfPassword(String password) {
  final bytes = latin1.encode(password);
  final out = Uint8List(32);
  final n = math.min(32, bytes.length);
  out.setRange(0, n, bytes);
  out.setRange(n, 32, pdfPasswordPadding);
  return out;
}

Uint8List rc4(List<int> key, Uint8List data) {
  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }
  var j = 0;
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
  }
  final out = Uint8List(data.length);
  var i = 0;
  j = 0;
  for (var k = 0; k < data.length; k++) {
    i = (i + 1) & 0xFF;
    j = (j + s[i]) & 0xFF;
    final t = s[i];
    s[i] = s[j];
    s[j] = t;
    out[k] = data[k] ^ s[(s[i] + s[j]) & 0xFF];
  }
  return out;
}

/// Algorithm 3 — compute `/O` (revision ≥ 3, 128-bit).
Uint8List computeOwnerEntry({
  required String ownerPassword,
  required String userPassword,
  int keyLengthBytes = 16,
}) {
  final owner = ownerPassword.isEmpty ? userPassword : ownerPassword;
  var hash = md5.convert(padPdfPassword(owner)).bytes;
  for (var i = 0; i < 50; i++) {
    hash = md5.convert(hash).bytes;
  }
  final key = hash.sublist(0, keyLengthBytes);
  var data = padPdfPassword(userPassword);
  data = rc4(key, data);
  for (var i = 1; i <= 19; i++) {
    final stepKey = [for (final b in key) b ^ i];
    data = rc4(stepKey, data);
  }
  return data;
}

/// Algorithm 2 — file encryption key (revision ≥ 3).
Uint8List computeFileKey({
  required String userPassword,
  required Uint8List ownerEntry,
  required int permissions,
  required Uint8List fileId,
  int keyLengthBytes = 16,
  bool encryptMetadata = true,
}) {
  final input = BytesBuilder(copy: false)
    ..add(padPdfPassword(userPassword))
    ..add(ownerEntry.length >= 32 ? ownerEntry.sublist(0, 32) : ownerEntry)
    ..add([
      permissions & 0xFF,
      (permissions >> 8) & 0xFF,
      (permissions >> 16) & 0xFF,
      (permissions >> 24) & 0xFF,
    ])
    ..add(fileId);
  if (!encryptMetadata) {
    input.add(const [0xFF, 0xFF, 0xFF, 0xFF]);
  }
  var hash = md5.convert(input.takeBytes()).bytes;
  for (var i = 0; i < 50; i++) {
    hash = md5.convert(hash.sublist(0, keyLengthBytes)).bytes;
  }
  return Uint8List.fromList(hash.sublist(0, keyLengthBytes));
}

/// Algorithm 5 — compute `/U` (revision ≥ 3).
Uint8List computeUserEntry({
  required Uint8List fileKey,
  required Uint8List fileId,
}) {
  final hash = md5.convert([...pdfPasswordPadding, ...fileId]).bytes;
  var cipher = rc4(fileKey, Uint8List.fromList(hash));
  for (var i = 1; i <= 19; i++) {
    final stepKey = [for (final b in fileKey) b ^ i];
    cipher = rc4(stepKey, cipher);
  }
  final out = Uint8List(32);
  out.setRange(0, math.min(16, cipher.length), cipher);
  final rng = math.Random.secure();
  for (var i = 16; i < 32; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

/// Algorithm 1 object key (+ AES `sAlT` for AESV2).
Uint8List objectEncryptionKey({
  required Uint8List fileKey,
  required int objectNumber,
  required int generation,
  required bool aes,
}) {
  final input = BytesBuilder(copy: false)
    ..add(fileKey)
    ..add([
      objectNumber & 0xFF,
      (objectNumber >> 8) & 0xFF,
      (objectNumber >> 16) & 0xFF,
      generation & 0xFF,
      (generation >> 8) & 0xFF,
    ]);
  if (aes) input.add(const [0x73, 0x41, 0x6C, 0x54]); // sAlT
  final hash = md5.convert(input.takeBytes()).bytes;
  final n = math.min(fileKey.length + 5, 16);
  return Uint8List.fromList(hash.sublist(0, n));
}

Uint8List _randomIv() {
  final rng = math.Random.secure();
  return Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
}

/// AES-128-CBC content encryption with random IV prefix (ISO 32000 §7.6.2).
Uint8List aesEncryptPdfContent(Uint8List key, Uint8List data, {Uint8List? iv}) {
  final useIv = iv ?? _randomIv();
  final cipher = PaddedBlockCipher('AES/CBC/PKCS7')
    ..init(
      true,
      PaddedBlockCipherParameters(
        ParametersWithIV(KeyParameter(key), useIv),
        null,
      ),
    );
  final encrypted = cipher.process(data);
  return Uint8List.fromList([...useIv, ...encrypted]);
}

/// Holds computed Standard Security Handler revision-4 (AES-128) material.
class PdfAes128SecurityMaterial {
  PdfAes128SecurityMaterial({
    required this.fileKey,
    required this.ownerEntry,
    required this.userEntry,
    required this.permissions,
    required this.fileId,
  });

  final Uint8List fileKey;
  final Uint8List ownerEntry;
  final Uint8List userEntry;
  final int permissions;
  final Uint8List fileId;

  Uint8List encryptString(Uint8List data, int objectNumber, int generation) {
    final key = objectEncryptionKey(
      fileKey: fileKey,
      objectNumber: objectNumber,
      generation: generation,
      aes: true,
    );
    return aesEncryptPdfContent(key, data);
  }

  Uint8List encryptStream(Uint8List data, int objectNumber, int generation) =>
      encryptString(data, objectNumber, generation);
}

PdfAes128SecurityMaterial buildAes128Security({
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
      : (restricted ? _randomPassword() : userPassword);
  final id = fileId ?? _randomId();
  final p = pdfPermissionFlags(
    allowPrinting: allowPrinting,
    allowModify: allowModify,
    allowExtract: allowExtract,
    allowAnnotate: allowAnnotate,
  );
  final o = computeOwnerEntry(ownerPassword: owner, userPassword: userPassword);
  final key = computeFileKey(
    userPassword: userPassword,
    ownerEntry: o,
    permissions: p,
    fileId: id,
  );
  final u = computeUserEntry(fileKey: key, fileId: id);
  return PdfAes128SecurityMaterial(
    fileKey: key,
    ownerEntry: o,
    userEntry: u,
    permissions: p,
    fileId: id,
  );
}

String _randomPassword() {
  const chars =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  final rng = math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 32; i++) chars.codeUnitAt(rng.nextInt(chars.length)),
  ]);
}

Uint8List _randomId() {
  final rng = math.Random.secure();
  return Uint8List.fromList([for (var i = 0; i < 16; i++) rng.nextInt(256)]);
}
