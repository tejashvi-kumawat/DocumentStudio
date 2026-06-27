import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:document_studio/core/errors/document_studio_error.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_parser.dart';
import 'package:document_studio/infrastructure/pdf/pdf_standard_security.dart';
import 'package:document_studio/infrastructure/pdf/pdfrx_error_mapping.dart';
import 'package:pdfrx/pdfrx.dart';

/// Pure-Dart / PDFium helpers for protect, unlock, and Info metadata when
/// the qpdf CLI is not available (notably Android).
class DartPdfSecurityService {
  const DartPdfSecurityService();

  /// Opens [path] with [password] and writes an unencrypted copy.
  Future<void> decryptToFile({
    required String inputPath,
    required String outputPath,
    required String password,
  }) async {
    PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(
        inputPath,
        passwordProvider: _oneShotPassword(password),
        firstAttemptByEmptyPassword: password.isEmpty,
      );
    } catch (e) {
      throw documentStudioErrorFromPdfrxOpen(
        e,
        password: password.isEmpty ? null : password,
      );
    }
    try {
      if (!doc.isEncrypted) {
        // Still rewrite so callers get a normal saved copy.
        final bytes = await doc.encodePdf();
        await _writeBytes(outputPath, bytes);
        return;
      }
      final bytes = await doc.encodePdf(removeSecurity: true);
      await _writeBytes(outputPath, bytes);
    } finally {
      await doc.dispose();
    }
  }

  /// Encrypts [inputPath] with AES-128 (Standard Security Handler R4).
  ///
  /// Input may already be encrypted when [inputPassword] is supplied; it is
  /// normalized via PDFium first, then rewritten with a new `/Encrypt` dict.
  Future<void> encryptToFile({
    required String inputPath,
    required String outputPath,
    required String userPassword,
    String ownerPassword = '',
    String? inputPassword,
    bool allowPrinting = true,
    bool allowModify = false,
    bool allowExtract = false,
    bool allowAnnotate = false,
  }) async {
    if (userPassword.isEmpty) {
      throw const DocumentStudioError(
        code: DocumentStudioErrorCode.invalidFile,
        message: 'Enter a password to encrypt the PDF.',
      );
    }
    final plain = await _normalizePlainPdfBytes(
      inputPath,
      password: inputPassword,
    );
    final encrypted = encryptPdfBytes(
      plain,
      userPassword: userPassword,
      ownerPassword: ownerPassword,
      allowPrinting: allowPrinting,
      allowModify: allowModify,
      allowExtract: allowExtract,
      allowAnnotate: allowAnnotate,
    );
    await _writeBytes(outputPath, encrypted);
  }

  /// Rewrites Info dictionary fields on an unencrypted (or password-openable)
  /// PDF. Encrypted inputs are decrypted first; the saved copy is unencrypted
  /// unless [reencryptUserPassword] is set.
  Future<void> writeDocumentInfo({
    required String inputPath,
    required String outputPath,
    required Map<String, String> fields,
    String? inputPassword,
    String? reencryptUserPassword,
  }) async {
    final plain = await _normalizePlainPdfBytes(
      inputPath,
      password: inputPassword,
    );
    final doc = PdfEditDocument.open(plain);
    doc.writeInfoFields(fields);
    var out = doc.save();
    final rePw = reencryptUserPassword;
    if (rePw != null && rePw.isNotEmpty) {
      out = encryptPdfBytes(out, userPassword: rePw);
    }
    await _writeBytes(outputPath, out);
  }

  Future<void> stripAllMetadata({
    required String inputPath,
    required String outputPath,
    String? inputPassword,
    String? reencryptUserPassword,
  }) async {
    final plain = await _normalizePlainPdfBytes(
      inputPath,
      password: inputPassword,
    );
    final doc = PdfEditDocument.open(plain);
    doc.stripDocumentMetadata();
    // Force an incremental update even when Info was already absent: touch
    // catalog so save() emits a revision (or rewrite fully below).
    if (!doc.hasChanges) {
      final root = doc.trailer['Root'];
      if (root is PdfRef) {
        final cat = doc.catalog.clone();
        doc.setObject(root, cat);
      }
    }
    var out = doc.save();
    final rePw = reencryptUserPassword;
    if (rePw != null && rePw.isNotEmpty) {
      out = encryptPdfBytes(out, userPassword: rePw);
    }
    await _writeBytes(outputPath, out);
  }

  /// Cheap protection probe without qpdf.
  Future<PdfProtectionProbe> probeProtection(String path) async {
    try {
      final doc = await PdfDocument.openFile(
        path,
        // Empty first try; returning null afterwards stops pdfrx's retry loop.
        passwordProvider: () async => null,
        firstAttemptByEmptyPassword: true,
      );
      try {
        if (!doc.isEncrypted) return PdfProtectionProbe.none;
        return PdfProtectionProbe.restrictionsOnly;
      } finally {
        await doc.dispose();
      }
    } on PdfPasswordException {
      return PdfProtectionProbe.openPassword;
    } catch (_) {
      return PdfProtectionProbe.unknown;
    }
  }

  Future<Uint8List> _normalizePlainPdfBytes(
    String path, {
    String? password,
  }) async {
    PdfDocument doc;
    try {
      doc = await PdfDocument.openFile(
        path,
        passwordProvider: password == null || password.isEmpty
            ? () async => null
            : _oneShotPassword(password),
        firstAttemptByEmptyPassword: password == null || password.isEmpty,
      );
    } catch (e) {
      final mapped = documentStudioErrorFromPdfrxOpen(e, password: password);
      if (mapped.code == DocumentStudioErrorCode.passwordRequired &&
          password != null &&
          password.isNotEmpty) {
        throw DocumentStudioError(
          code: DocumentStudioErrorCode.wrongPassword,
          message: 'Incorrect password for the source PDF.',
          cause: e,
        );
      }
      throw mapped;
    }
    try {
      if (doc.isEncrypted) {
        return await doc.encodePdf(removeSecurity: true);
      }
      // Prefer original bytes when already plain — preserves structure for
      // Info-only incremental edits. Fall back to encode when open failed
      // to keep a usable file.
      try {
        return await File(path).readAsBytes();
      } catch (_) {
        return await doc.encodePdf();
      }
    } finally {
      await doc.dispose();
    }
  }

  /// pdfrx calls the provider again while the password is wrong. Answer once.
  static PdfPasswordProvider _oneShotPassword(String password) {
    var asked = false;
    return () async {
      if (asked) return null;
      asked = true;
      return password;
    };
  }

  Future<void> _writeBytes(String path, Uint8List bytes) async {
    await Directory(File(path).parent.path).create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
  }
}

enum PdfProtectionProbe { none, restrictionsOnly, openPassword, unknown }

/// Full rewrite of [plainPdf] with AES-128 Standard Security Handler (R4).
Uint8List encryptPdfBytes(
  Uint8List plainPdf, {
  required String userPassword,
  String ownerPassword = '',
  bool allowPrinting = true,
  bool allowModify = false,
  bool allowExtract = false,
  bool allowAnnotate = false,
}) {
  final doc = PdfEditDocument.open(plainPdf);
  if (doc.isEncrypted) {
    throw const PdfEditException(
      'Internal error: expected a plaintext PDF before encrypt.',
      encrypted: true,
    );
  }
  final security = buildAes128Security(
    userPassword: userPassword,
    ownerPassword: ownerPassword,
    allowPrinting: allowPrinting,
    allowModify: allowModify,
    allowExtract: allowExtract,
    allowAnnotate: allowAnnotate,
  );

  final sink = PdfWriterSink();
  sink.raw('%PDF-1.7\n');
  sink.bytes(const [0x25, 0xe2, 0xe3, 0xcf, 0xd3, 0x0a]);

  final offsets = <int, int>{};
  final gens = <int, int>{};
  final encryptNum = math.max(doc.nextObjectNumber, 1);

  for (final n in doc.liveObjectNumbers) {
    final obj = doc.getObject(n);
    if (obj == null || _isStructuralSkip(obj)) continue;
    final gen = doc.generationOf(n);
    final encrypted = _encryptObjectGraph(obj, n, gen, security);
    offsets[n] = sink.length;
    gens[n] = gen;
    sink.raw('$n $gen obj\n');
    sink.obj(encrypted);
    sink.raw('\nendobj\n');
  }

  final encryptDict = PdfDict({
    'Filter': const PdfName('Standard'),
    'V': const PdfNum(4),
    'R': const PdfNum(4),
    'Length': const PdfNum(128),
    'P': PdfNum(security.permissions),
    'O': PdfString(security.ownerEntry, hex: true),
    'U': PdfString(security.userEntry, hex: true),
    'EncryptMetadata': const PdfBool(true),
    'CF': PdfDict({
      'StdCF': PdfDict({
        'AuthEvent': const PdfName('DocOpen'),
        'CFM': const PdfName('AESV2'),
        'Length': const PdfNum(16),
      }),
    }),
    'StmF': const PdfName('StdCF'),
    'StrF': const PdfName('StdCF'),
  });
  offsets[encryptNum] = sink.length;
  gens[encryptNum] = 0;
  sink.raw('$encryptNum 0 obj\n');
  sink.obj(encryptDict);
  sink.raw('\nendobj\n');

  final id2 = Uint8List.fromList([
    for (var i = 0; i < 16; i++) math.Random.secure().nextInt(256),
  ]);
  final trailer = PdfDict({
    'Size': PdfNum(encryptNum + 1),
    'Root': doc.trailer['Root']!,
    if (doc.trailer['Info'] != null) 'Info': doc.trailer['Info']!,
    'Encrypt': PdfRef(encryptNum),
    'ID': PdfArray([
      PdfString(security.fileId, hex: true),
      PdfString(id2, hex: true),
    ]),
  });

  final xrefOffset = sink.length;
  final nums = offsets.keys.toList()..sort();
  final sb = StringBuffer('xref\n0 1\n0000000000 65535 f\r\n');
  var i = 0;
  while (i < nums.length) {
    var j = i;
    while (j + 1 < nums.length && nums[j + 1] == nums[j] + 1) {
      j++;
    }
    sb.write('${nums[i]} ${j - i + 1}\n');
    for (var k = i; k <= j; k++) {
      final off = offsets[nums[k]]!.toString().padLeft(10, '0');
      final gen = (gens[nums[k]] ?? 0).toString().padLeft(5, '0');
      sb.write('$off $gen n\r\n');
    }
    i = j + 1;
  }
  sink.raw(sb.toString());
  sink.raw('trailer\n');
  sink.obj(trailer);
  sink.raw('\nstartxref\n$xrefOffset\n%%EOF\n');
  return sink.take();
}

bool _isStructuralSkip(PdfObj obj) {
  String? type;
  if (obj is PdfStream) {
    type = obj.dict.nameOf('Type');
  } else if (obj is PdfDict) {
    type = obj.nameOf('Type');
  }
  return type == 'ObjStm' || type == 'XRef';
}

PdfObj _encryptObjectGraph(
  PdfObj object,
  int objectNumber,
  int generation,
  PdfAes128SecurityMaterial security,
) {
  PdfObj copy(PdfObj value, {PdfDict? parentDict, String? parentKey}) {
    switch (value) {
      case PdfString():
        if (parentDict != null &&
            parentKey == 'Contents' &&
            _isSignatureDict(parentDict)) {
          return value;
        }
        return PdfString(
          security.encryptString(value.bytes, objectNumber, generation),
          hex: true,
        );
      case PdfArray():
        return PdfArray([
          for (final item in value.items)
            copy(item, parentDict: parentDict, parentKey: parentKey),
        ]);
      case PdfDict():
        final out = PdfDict();
        value.entries.forEach((key, v) {
          out[key] = copy(v, parentDict: value, parentKey: key);
        });
        return out;
      case PdfStream():
        final dict = copy(value.dict) as PdfDict;
        final type = value.dict.nameOf('Type');
        if (type == 'XRef') {
          return PdfStream(dict, value.data);
        }
        final cipher =
            security.encryptStream(value.data, objectNumber, generation);
        dict['Length'] = PdfNum(cipher.length);
        return PdfStream(dict, cipher);
      default:
        return value;
    }
  }

  return copy(object);
}

bool _isSignatureDict(PdfDict dict) {
  final type = dict.nameOf('Type');
  if (type == 'Sig' || type == 'DocTimeStamp') return true;
  return dict.containsKey('ByteRange');
}
