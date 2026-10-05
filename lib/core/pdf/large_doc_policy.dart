import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/features/document_lifecycle/document_session.dart';

/// Guards for features that parse a whole PDF in memory (content analysis,
/// image / font recognition, bookmarks, accessibility check, vector
/// redaction). A 500 MB or 50 000-page file must never be read whole just to
/// decorate the screen, so those features switch off above these limits and
/// say so, instead of risking an out-of-memory crash.
abstract final class LargeDocPolicy {
  /// Above this many bytes the in-memory editing helpers stay off.
  static const analysisByteLimit = 120 * 1024 * 1024;

  /// Above this many bytes the Dart-only (in-memory) compressor refuses and
  /// asks for the qpdf engine, which streams.
  static const inMemoryCompressLimit = 400 * 1024 * 1024;

  static Future<int> sizeOf(DocumentSession session) async {
    final known = session.file.sizeBytes;
    if (known != null) return known;
    try {
      return await File(session.file.path).length();
    } catch (_) {
      return 0;
    }
  }

  static Future<bool> allowsAnalysis(DocumentSession session) async =>
      await sizeOf(session) <= analysisByteLimit;

  /// The document's bytes, or null when it is too large to hold in memory.
  static Future<Uint8List?> readBounded(DocumentSession session) async {
    if (!await allowsAnalysis(session)) return null;
    return session.readCurrentBytes();
  }

  static const message =
      'This file is very large, so this feature is switched off to protect '
      'memory. Viewing, searching, page tools and compression still work.';
}
