import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';

/// One bookmark. [page] is 1-based; [children] nest under it.
class OutlineEntry {
  OutlineEntry({
    required this.title,
    required this.page,
    List<OutlineEntry>? children,
  }) : children = children ?? [];

  String title;
  int page;
  final List<OutlineEntry> children;

  OutlineEntry copy() => OutlineEntry(
        title: title,
        page: page,
        children: [for (final c in children) c.copy()],
      );
}

/// Reads the bookmark tree of [bytes] (pure Dart). Named destinations that
/// cannot be resolved fall back to page 1. Never throws.
List<OutlineEntry> readPdfOutline(Uint8List bytes) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final pageIndex = <int, int>{
      for (var i = 0; i < doc.pageRefs.length; i++) doc.pageRefs[i].num: i + 1,
    };
    int pageOf(PdfDict item) {
      PdfObj? dest = doc.resolve(item['Dest']);
      if (dest == null) {
        final a = doc.dictOf(item['A']);
        dest = doc.resolve(a?['D']);
      }
      if (dest is PdfArray && dest.items.isNotEmpty) {
        final first = dest.items.first;
        if (first is PdfRef) return pageIndex[first.num] ?? 1;
        if (first is PdfNum) return first.i + 1;
      }
      return 1;
    }

    List<OutlineEntry> walk(PdfObj? first, int depth) {
      final out = <OutlineEntry>[];
      var cur = first;
      var guard = 0;
      while (cur != null && guard++ < 5000) {
        final d = doc.dictOf(cur);
        if (d == null) break;
        final t = doc.resolve(d['Title']);
        out.add(
          OutlineEntry(
            title: t is PdfString ? t.text : 'Untitled',
            page: pageOf(d),
            children: depth < 12 ? walk(d['First'], depth + 1) : null,
          ),
        );
        cur = d['Next'];
      }
      return out;
    }

    final root = doc.dictOf(doc.catalog['Outlines']);
    if (root == null) return [];
    return walk(root['First'], 0);
  } catch (_) {
    return [];
  }
}

/// Writes [entries] as the document's bookmarks (replacing any existing
/// outline) and returns the new bytes, or null if the file cannot be edited.
Uint8List? writePdfOutline(Uint8List bytes, List<OutlineEntry> entries) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final cat = doc.catalog.clone();
    final root = doc.trailer['Root'];
    if (root is! PdfRef) return null;
    if (entries.isEmpty) {
      cat.remove('Outlines');
      doc.setObject(root, cat);
      return doc.save();
    }
    final rootRef = doc.addObject(PdfDict()); // filled below

    int countOpen(List<OutlineEntry> l) {
      var n = l.length;
      for (final e in l) {
        n += countOpen(e.children);
      }
      return n;
    }

    // Returns (firstRef, lastRef) of the sibling chain.
    (PdfRef, PdfRef) build(List<OutlineEntry> list, PdfRef parent) {
      final refs = [for (final _ in list) doc.addObject(PdfDict())];
      for (var i = 0; i < list.length; i++) {
        final e = list[i];
        final page = e.page.clamp(1, doc.pageCount);
        final d = PdfDict({
          'Title': PdfString.text(e.title),
          'Parent': parent,
          'Dest': PdfArray([doc.pageRef(page), const PdfName('Fit')]),
          if (i > 0) 'Prev': refs[i - 1],
          if (i < list.length - 1) 'Next': refs[i + 1],
        });
        if (e.children.isNotEmpty) {
          final (f, l) = build(e.children, refs[i]);
          d['First'] = f;
          d['Last'] = l;
          d['Count'] = PdfNum(countOpen(e.children));
        }
        doc.setObject(refs[i], d);
      }
      return (refs.first, refs.last);
    }

    final (first, last) = build(entries, rootRef);
    doc.setObject(
      rootRef,
      PdfDict({
        'Type': const PdfName('Outlines'),
        'First': first,
        'Last': last,
        'Count': PdfNum(countOpen(entries)),
      }),
    );
    cat['Outlines'] = rootRef;
    doc.setObject(root, cat);
    return doc.save();
  } catch (_) {
    return null;
  }
}
