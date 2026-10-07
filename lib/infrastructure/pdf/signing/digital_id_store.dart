import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/isolate/run_isolated.dart';
import 'package:document_studio/infrastructure/pdf/signing/dart_pki.dart';
import 'package:document_studio/infrastructure/pdf/signing/openssl_pki.dart';
import 'package:document_studio/infrastructure/pdf/signing/x509.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DigitalIdSource { selfSigned, imported }

class DigitalId {
  const DigitalId({
    required this.id,
    required this.displayName,
    required this.source,
    required this.p12Path,
    this.subject = '',
    this.certificateDer,
  });

  final String id;
  final String displayName;
  final DigitalIdSource source;
  final String p12Path;
  final String subject;

  /// Public certificate cached at import so the list shows validity without
  /// asking for the password.
  final Uint8List? certificateDer;
}

/// Persists digital ID metadata + copies of .p12 files under app support.
class DigitalIdStore {
  static const _indexKey = 'ds_digital_ids_v1';

  /// Shared across store instances so a password typed once lasts the session.
  static final Map<String, String> _sessionPasswords = {};
  final OpenSslPki _pki = OpenSslPki();

  Future<Directory> _dir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'digital_ids'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<List<DigitalId>> loadAll() async {
    final out = <DigitalId>[];
    for (final e in await _readIndex()) {
      final id = e['id'];
      final name = e['displayName'];
      final path = e['p12Path'];
      if (id is! String || name is! String || path is! String) continue;
      if (!await File(path).exists()) continue;
      Uint8List? cert;
      final c = e['certDer'];
      if (c is String && c.isNotEmpty) {
        try {
          cert = base64.decode(c);
        } catch (_) {}
      }
      out.add(
        DigitalId(
          id: id,
          displayName: name,
          p12Path: path,
          source: e['source'] == 'imported'
              ? DigitalIdSource.imported
              : DigitalIdSource.selfSigned,
          subject: e['subject'] as String? ?? '',
          certificateDer: cert,
        ),
      );
    }
    return out;
  }

  Future<void> _writeIndex(List<Map<String, Object?>> index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(index));
  }

  Future<List<Map<String, Object?>>> _readIndex() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return [
        for (final e in list)
          if (e is Map) Map<String, Object?>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  Future<DigitalId> _register({
    required String displayName,
    required DigitalIdSource source,
    required String p12Path,
    required Uint8List? certDer,
    required String password,
    String subject = '',
  }) async {
    final id = p.basenameWithoutExtension(p12Path).replaceFirst('id_', '');
    var subj = subject;
    if (certDer != null) {
      try {
        subj = X509Certificate.parse(certDer).subjectDn;
      } catch (_) {}
    }
    final idObj = DigitalId(
      id: id,
      displayName: displayName,
      source: source,
      p12Path: p12Path,
      subject: subj,
      certificateDer: certDer,
    );
    final index = await _readIndex();
    index.insert(0, {
      'id': idObj.id,
      'displayName': idObj.displayName,
      'p12Path': idObj.p12Path,
      'source': source == DigitalIdSource.imported ? 'imported' : 'selfSigned',
      'subject': idObj.subject,
      if (certDer != null) 'certDer': base64.encode(certDer),
    });
    await _writeIndex(index);
    rememberSession(idObj.id, password);
    return idObj;
  }

  /// Creates an RSA-2048 self-signed ID in pure Dart (works on mobile too).
  Future<DigitalId> createSelfSigned({
    required String displayName,
    required String password,
    String organization = '',
    String email = '',
  }) async {
    final dir = await _dir();
    final p12Path = p.join(dir.path, 'id_${_newId()}.p12');
    final cn = displayName.trim().isEmpty
        ? 'Self-signed ID'
        : displayName.trim();
    final bytes = await createSelfSignedPkcs12(
      commonName: cn,
      password: password,
      organization: organization.trim(),
      email: email.trim(),
    );
    await File(p12Path).writeAsBytes(bytes, flush: true);
    final identity = await runIsolated(_parseP12, (bytes, password));
    return _register(
      displayName: cn,
      source: DigitalIdSource.selfSigned,
      p12Path: p12Path,
      certDer: identity.certificateDer,
      password: password,
    );
  }

  /// Imports a .p12 / .pfx after checking the password.
  Future<DigitalId> importP12({
    required String sourcePath,
    required String displayName,
    required String password,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    Uint8List? certDer;
    String commonName = '';
    String subject = '';
    try {
      final identity = await runIsolated(_parseP12, (bytes, password));
      certDer = identity.certificateDer;
      commonName = X509Certificate.parse(certDer).commonName;
    } on Pkcs12WrongPassword {
      rethrow;
    } catch (e) {
      // Legacy / exotic encodings: fall back to OpenSSL on desktop.
      try {
        final info = await _pki.inspectP12(sourcePath, password);
        commonName = info.commonName;
        subject = info.subjectDn;
        final unpacked = await _pki.unpack(sourcePath, password);
        certDer = unpacked.certDer;
        await unpacked.dispose();
      } catch (_) {
        throw StateError('Could not open this digital ID: $e');
      }
    }
    final dir = await _dir();
    final dest = p.join(dir.path, 'id_${_newId()}.p12');
    await File(dest).writeAsBytes(bytes, flush: true);
    final name = displayName.trim().isNotEmpty
        ? displayName.trim()
        : (commonName.isNotEmpty
              ? commonName
              : p.basenameWithoutExtension(sourcePath));
    return _register(
      displayName: name,
      source: DigitalIdSource.imported,
      p12Path: dest,
      certDer: certDer,
      password: password,
      subject: subject,
    );
  }

  Future<void> remove(String id) async {
    final index = await _readIndex();
    final kept = <Map<String, Object?>>[];
    for (final e in index) {
      if (e['id'] == id) {
        final path = e['p12Path'];
        if (path is String) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      } else {
        kept.add(e);
      }
    }
    await _writeIndex(kept);
    _sessionPasswords.remove(id);
  }

  Future<void> exportTo(DigitalId id, String destPath) async {
    await File(id.p12Path).copy(destPath);
  }

  void rememberSession(String id, String password) {
    _sessionPasswords[id] = password;
  }

  String? sessionPassword(String id) => _sessionPasswords[id];

  void forgetSession(String id) {
    _sessionPasswords.remove(id);
  }

  Future<Uint8List> readP12Bytes(DigitalId id) =>
      File(id.p12Path).readAsBytes();
}

Pkcs12Identity _parseP12((Uint8List, String) a) => parsePkcs12(a.$1, a.$2);
