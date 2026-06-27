import 'dart:io';

import 'package:document_studio/infrastructure/pdf/signing/signing_credential.dart';
import 'package:flutter/services.dart';

/// macOS / iOS Keychain identities via `document_studio_os_signing`.
class AppleKeychainBackend {
  const AppleKeychainBackend();

  static const _channel = MethodChannel('document_studio_os_signing');

  Future<List<SigningCredential>> listCredentials() async {
    if (!(Platform.isMacOS || Platform.isIOS)) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>('listIdentities');
      if (raw == null) return const [];
      final out = <SigningCredential>[];
      for (final e in raw) {
        if (e is! Map) continue;
        final m = Map<String, Object?>.from(e);
        final derList = m['certificateDer'];
        Uint8List? der;
        if (derList is Uint8List) {
          der = derList;
        } else if (derList is List) {
          der = Uint8List.fromList(derList.cast<int>());
        }
        final notBeforeMs = m['notBeforeMs'];
        final notAfterMs = m['notAfterMs'];
        out.add(
          SigningCredential(
            id: 'keychain:${m['identityRef'] ?? m['fingerprint'] ?? ''}',
            displayName: (m['commonName'] as String?)?.trim().isNotEmpty == true
                ? m['commonName'] as String
                : 'Keychain identity',
            source: SigningCredentialSource.keychain,
            subjectDn: m['subjectDn'] as String? ?? '',
            issuerDn: m['issuerDn'] as String? ?? '',
            notBefore: notBeforeMs is int
                ? DateTime.fromMillisecondsSinceEpoch(notBeforeMs)
                : DateTime.fromMillisecondsSinceEpoch(0),
            notAfter: notAfterMs is int
                ? DateTime.fromMillisecondsSinceEpoch(notAfterMs)
                : DateTime.fromMillisecondsSinceEpoch(0),
            fingerprint: m['fingerprint'] as String? ?? '',
            keyDescription: m['keyDescription'] as String? ?? '',
            keyUsage: (m['keyUsage'] as List?)?.cast<String>() ?? const [],
            isSelfSigned: m['isSelfSigned'] == true,
            hardwareBacked: m['hardwareBacked'] == true,
            requiresPin: m['requiresPin'] == true,
            hasPrivateKey: true,
            certificateDer: der,
            osIdentityRef: m['identityRef'] as String?,
          ),
        );
      }
      return out;
    } on MissingPluginException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<Uint8List> signHash(
    SigningCredential credential,
    Uint8List dataToSign,
  ) async {
    if (!(Platform.isMacOS || Platform.isIOS)) {
      throw UnsupportedError(
        'Apple Keychain signing is only available on Apple platforms.',
      );
    }
    final ref = credential.osIdentityRef;
    if (ref == null) throw StateError('Missing Keychain identity reference.');
    final result = await _channel.invokeMethod<dynamic>('signHash', {
      'identityRef': ref,
      'data': dataToSign,
    });
    if (result is Uint8List) return result;
    if (result is List) return Uint8List.fromList(result.cast<int>());
    throw StateError('Keychain signing returned no signature.');
  }
}
