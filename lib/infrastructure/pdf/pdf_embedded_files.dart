import 'dart:io';
import 'dart:typed_data';

import 'package:document_studio/core/storage/file_storage_port.dart';
import 'package:document_studio/infrastructure/pdf/signing/pdf_cos.dart';
import 'package:path/path.dart' as p;

/// Largest embedded-file stream this app will decode or write out.
const int kPdfEmbeddedFileMaxBytes = 64 * 1024 * 1024;

/// One file from the catalog `/Names` `/EmbeddedFiles` name tree.
class PdfEmbeddedFile {
  const PdfEmbeddedFile({
    required this.name,
    required this.fileName,
    this.description,
    this.declaredBytes,
  });

  /// Name-tree key.
  final String name;

  /// File name used for Open and Save (sanitized, no directories).
  final String fileName;

  final String? description;

  /// `/Params` `/Size` when the file spec declares it. Not the decoded length.
  final int? declaredBytes;
}

class PdfEmbeddedFileException implements Exception {
  const PdfEmbeddedFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lists embedded files from the catalog EmbeddedFiles name tree.
///
/// Walks `/Catalog` `/Names` `/EmbeddedFiles` (including `/Kids`) and the
/// related `/EF` streams. Does not walk the page tree.
List<PdfEmbeddedFile> listPdfEmbeddedFiles(Uint8List pdfBytes) {
  try {
    return _list(pdfBytes);
  } on PdfEmbeddedFileException {
    rethrow;
  } catch (_) {
    throw const PdfEmbeddedFileException('Could not read attachments.');
  }
}

/// Decodes the embedded file at [index] from a previous [listPdfEmbeddedFiles]
/// of the same bytes. Does not modify [pdfBytes].
Uint8List extractPdfEmbeddedFileBytes(Uint8List pdfBytes, int index) {
  try {
    return _extract(pdfBytes, index);
  } on PdfEmbeddedFileException {
    rethrow;
  } on PdfCosException catch (e) {
    throw PdfEmbeddedFileException(_extractFailureMessage(e));
  } catch (_) {
    throw const PdfEmbeddedFileException('Could not read this attachment.');
  }
}

/// Reads [path] and lists embedded files. Does not render pages.
Future<List<PdfEmbeddedFile>> listPdfEmbeddedFilesAtPath(String path) async {
  final bytes = await File(path).readAsBytes();
  return listPdfEmbeddedFiles(bytes);
}

/// Reads [path] and extracts one embedded file. Does not write [path].
Future<Uint8List> extractPdfEmbeddedFileAtPath(String path, int index) async {
  final bytes = await File(path).readAsBytes();
  return extractPdfEmbeddedFileBytes(bytes, index);
}

/// Strips directories and characters that are unsafe in an output file name.
String sanitizeAttachmentFileName(String name) {
  var base = p.basename(name.replaceAll('\\', '/')).trim();
  base = base.replaceAll(RegExp(r'[^\w.\- ]+'), '_').trim();
  if (base.isEmpty || base == '.' || base == '..' || base == '_') {
    return 'attachment';
  }
  if (base.length > 180) base = base.substring(base.length - 180);
  return base;
}

/// True when writing [destination] would replace an open PDF path.
bool attachmentSaveReplacesOpenPdf(
  String destination,
  Iterable<String> protectedPdfPaths,
) {
  final dest = p.normalize(p.absolute(destination));
  for (final raw in protectedPdfPaths) {
    if (raw.isEmpty) continue;
    if (p.normalize(p.absolute(raw)) == dest) return true;
  }
  return false;
}

/// Writes [bytes] under [directory] using [fileName].
///
/// Refuses when the destination is one of [protectedPdfPaths] (the session
/// working copy or the user's original PDF).
Future<String> writePdfAttachmentFile({
  required FileStoragePort storage,
  required String directory,
  required String fileName,
  required Uint8List bytes,
  required Iterable<String> protectedPdfPaths,
}) async {
  if (bytes.length > kPdfEmbeddedFileMaxBytes) {
    throw const PdfEmbeddedFileException(
      'This attachment is too large to extract.',
    );
  }
  final name = sanitizeAttachmentFileName(fileName);
  final dest = p.join(directory, name);
  if (attachmentSaveReplacesOpenPdf(dest, protectedPdfPaths)) {
    throw const PdfEmbeddedFileException(
      'Choose a different folder so the open PDF is not replaced.',
    );
  }
  await storage.writeAtomic(
    destinationPath: dest,
    writeToTemp: (tempPath) async {
      await File(tempPath).writeAsBytes(bytes, flush: true);
    },
  );
  return dest;
}

/// Writes [bytes] to a new temp file so it can be opened outside the PDF.
Future<String> writeExtractedAttachmentToTemp({
  required Uint8List bytes,
  required String fileName,
  required Iterable<String> protectedPdfPaths,
}) async {
  if (bytes.length > kPdfEmbeddedFileMaxBytes) {
    throw const PdfEmbeddedFileException(
      'This attachment is too large to extract.',
    );
  }
  final dir = await Directory.systemTemp.createTemp('ds_attach_');
  final dest = p.join(dir.path, sanitizeAttachmentFileName(fileName));
  if (attachmentSaveReplacesOpenPdf(dest, protectedPdfPaths)) {
    throw const PdfEmbeddedFileException(
      'Could not extract this attachment without replacing the open PDF.',
    );
  }
  await File(dest).writeAsBytes(bytes, flush: true);
  return dest;
}

/// Opens an extracted attachment with the desktop shell. Returns false on failure.
Future<bool> openExtractedAttachmentWithSystem(String path) async {
  try {
    if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [path]);
      return result.exitCode == 0;
    }
    if (Platform.isMacOS) {
      final result = await Process.run('open', [path]);
      return result.exitCode == 0;
    }
    if (Platform.isWindows) {
      final result = await Process.run('cmd', ['/c', 'start', '', path]);
      return result.exitCode == 0;
    }
  } catch (_) {
    return false;
  }
  return false;
}

String formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

List<PdfEmbeddedFile> _list(Uint8List pdfBytes) {
  final doc = PdfCosDocument.parse(pdfBytes);
  if (doc.isEncrypted) {
    throw const PdfEmbeddedFileException('Unlock this PDF to see attachments.');
  }
  final names = doc.resolveDict(doc.catalog['Names']);
  final tree = names?['EmbeddedFiles'];
  if (tree == null) return const [];
  final found = <PdfEmbeddedFile>[];
  final seen = <int>{};
  void walk(PdfObj? node, int depth) {
    if (node == null || depth > 40) return;
    if (node is PdfRef && !seen.add(node.num)) return;
    final dict = doc.resolveDict(node);
    if (dict == null) return;
    final pairs = doc.resolve(dict['Names']);
    if (pairs is PdfArray) {
      for (var i = 0; i + 1 < pairs.length; i += 2) {
        final key = _pdfText(doc.resolve(pairs[i]));
        if (key == null || key.isEmpty) continue;
        final entry = _entryFromValue(doc, key, pairs[i + 1]);
        if (entry != null) found.add(entry);
      }
    }
    final kids = doc.resolve(dict['Kids']);
    if (kids is PdfArray) {
      for (final kid in kids.items) {
        walk(kid, depth + 1);
      }
    }
  }

  walk(tree, 0);
  return found;
}

Uint8List _extract(Uint8List pdfBytes, int index) {
  final doc = PdfCosDocument.parse(pdfBytes);
  if (doc.isEncrypted) {
    throw const PdfEmbeddedFileException('Unlock this PDF to see attachments.');
  }
  final names = doc.resolveDict(doc.catalog['Names']);
  final tree = names?['EmbeddedFiles'];
  if (tree == null) {
    throw const PdfEmbeddedFileException('Could not read this attachment.');
  }
  final streams = <PdfStream?>[];
  final seen = <int>{};
  void walk(PdfObj? node, int depth) {
    if (node == null || depth > 40) return;
    if (node is PdfRef && !seen.add(node.num)) return;
    final dict = doc.resolveDict(node);
    if (dict == null) return;
    final pairs = doc.resolve(dict['Names']);
    if (pairs is PdfArray) {
      for (var i = 0; i + 1 < pairs.length; i += 2) {
        final key = _pdfText(doc.resolve(pairs[i]));
        if (key == null || key.isEmpty) continue;
        if (_entryFromValue(doc, key, pairs[i + 1]) == null) continue;
        streams.add(_streamFromValue(doc, pairs[i + 1]));
      }
    }
    final kids = doc.resolve(dict['Kids']);
    if (kids is PdfArray) {
      for (final kid in kids.items) {
        walk(kid, depth + 1);
      }
    }
  }

  walk(tree, 0);
  if (index < 0 || index >= streams.length) {
    throw const PdfEmbeddedFileException('Could not read this attachment.');
  }
  final stream = streams[index];
  if (stream == null) {
    throw const PdfEmbeddedFileException('Could not read this attachment.');
  }
  final params = doc.resolveDict(stream.dict['Params']);
  final declared = params?['Size'];
  if (declared is PdfNum && declared.i > kPdfEmbeddedFileMaxBytes) {
    throw const PdfEmbeddedFileException(
      'This attachment is too large to extract.',
    );
  }
  final data = doc.decodeStream(
    stream,
    maxOutputBytes: kPdfEmbeddedFileMaxBytes,
  );
  if (data.length > kPdfEmbeddedFileMaxBytes) {
    throw const PdfEmbeddedFileException(
      'This attachment is too large to extract.',
    );
  }
  return data;
}

String _extractFailureMessage(PdfCosException e) {
  final message = e.message.toLowerCase();
  if (message.contains('size limit') || message.contains('too large')) {
    return 'This attachment is too large to extract.';
  }
  if (message.contains('unsupported')) {
    return 'This attachment uses a compression Document Studio cannot read.';
  }
  if (message.contains('encrypted')) {
    return 'Unlock this PDF to see attachments.';
  }
  return 'Could not read this attachment.';
}

PdfEmbeddedFile? _entryFromValue(PdfCosDocument doc, String key, PdfObj value) {
  final resolved = doc.resolve(value);
  PdfDict? spec;
  PdfStream? stream;
  if (resolved is PdfStream && resolved.dict.nameOf('Type') == 'EmbeddedFile') {
    stream = resolved;
  } else {
    spec = doc.resolveDict(value);
    if (spec == null) return null;
    final ef = doc.resolveDict(spec['EF']);
    if (ef == null) return null;
    stream = _firstEfStream(doc, ef);
  }
  final desc = spec == null ? null : _pdfText(doc.resolve(spec['Desc']));
  int? size;
  if (stream != null) {
    final params = doc.resolveDict(stream.dict['Params']);
    final n = params?['Size'];
    if (n is PdfNum && n.i >= 0) size = n.i;
  }
  return PdfEmbeddedFile(
    name: key,
    fileName: sanitizeAttachmentFileName(_fileName(doc, spec, key)),
    description: (desc == null || desc.trim().isEmpty) ? null : desc.trim(),
    declaredBytes: size,
  );
}

PdfStream? _streamFromValue(PdfCosDocument doc, PdfObj value) {
  final resolved = doc.resolve(value);
  if (resolved is PdfStream && resolved.dict.nameOf('Type') == 'EmbeddedFile') {
    return resolved;
  }
  final spec = doc.resolveDict(value);
  if (spec == null) return null;
  final ef = doc.resolveDict(spec['EF']);
  if (ef == null) return null;
  return _firstEfStream(doc, ef);
}

PdfStream? _firstEfStream(PdfCosDocument doc, PdfDict ef) {
  for (final key in const ['UF', 'F', 'Unix', 'Mac', 'DOS']) {
    final resolved = doc.resolve(ef[key]);
    if (resolved is PdfStream) return resolved;
  }
  return null;
}

String _fileName(PdfCosDocument doc, PdfDict? spec, String treeKey) {
  if (spec != null) {
    final uf = _pdfText(doc.resolve(spec['UF']));
    if (uf != null && uf.trim().isNotEmpty) return uf.trim();
    final f = _pdfText(doc.resolve(spec['F']));
    if (f != null && f.trim().isNotEmpty) return f.trim();
  }
  return treeKey;
}

String? _pdfText(PdfObj? obj) {
  if (obj is PdfString) return obj.text;
  if (obj is PdfName) return obj.name;
  return null;
}
