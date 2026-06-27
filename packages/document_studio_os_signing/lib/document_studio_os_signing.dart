import 'package:flutter/services.dart';

/// Thin Dart wrapper around the darwin Keychain plugin.
class DocumentStudioOsSigning {
  DocumentStudioOsSigning._();

  static const MethodChannel _channel =
      MethodChannel('document_studio_os_signing');

  static Future<List<Map<String, Object?>>> listIdentities() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('listIdentities');
    if (raw == null) return const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, Object?>.from(e),
    ];
  }

  static Future<Uint8List> signHash({
    required String identityRef,
    required Uint8List data,
  }) async {
    final result = await _channel.invokeMethod<dynamic>('signHash', {
      'identityRef': identityRef,
      'data': data,
    });
    if (result is Uint8List) return result;
    if (result is List) return Uint8List.fromList(result.cast<int>());
    throw StateError('signHash returned no data');
  }
}
