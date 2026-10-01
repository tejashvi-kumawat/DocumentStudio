import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Session bookmark stored beside the PDF (not a PDF outline entry).
class PdfSessionBookmark {
  const PdfSessionBookmark({
    required this.title,
    required this.page1Based,
    this.createdAtMs,
  });

  final String title;
  final int page1Based;
  final int? createdAtMs;

  Map<String, dynamic> toJson() => {
        'title': title,
        'page1Based': page1Based,
        if (createdAtMs != null) 'createdAtMs': createdAtMs,
      };

  factory PdfSessionBookmark.fromJson(Map<String, dynamic> json) {
    return PdfSessionBookmark(
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Bookmark',
      page1Based: (json['page1Based'] as num?)?.toInt() ?? 1,
      createdAtMs: (json['createdAtMs'] as num?)?.toInt(),
    );
  }
}

/// Sidecar path for Document Studio session bookmarks next to [pdfPath].
String pdfSessionBookmarksSidecarPath(String pdfPath) {
  return '$pdfPath.documentstudio.bookmarks.json';
}

/// Loads session bookmarks from the sidecar beside [pdfPath] (empty if missing).
Future<List<PdfSessionBookmark>> loadPdfSessionBookmarks(String pdfPath) async {
  final file = File(pdfSessionBookmarksSidecarPath(pdfPath));
  if (!await file.exists()) return const [];
  try {
    final root = jsonDecode(await file.readAsString());
    if (root is! Map) return const [];
    final list = root['bookmarks'];
    if (list is! List) return const [];
    return list
        .whereType<Map>()
        .map((e) => PdfSessionBookmark.fromJson(Map<String, dynamic>.from(e)))
        .where((b) => b.page1Based >= 1)
        .toList();
  } catch (_) {
    return const [];
  }
}

/// Persists [bookmarks] beside [pdfPath]. Does not write PDF outlines.
Future<void> savePdfSessionBookmarks({
  required String pdfPath,
  required List<PdfSessionBookmark> bookmarks,
}) async {
  final file = File(pdfSessionBookmarksSidecarPath(pdfPath));
  final payload = <String, dynamic>{
    'version': 1,
    'source': 'document_studio',
    'pdf': p.basename(pdfPath),
    'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
  };
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
}
