import 'dart:typed_data';

import 'package:document_studio/infrastructure/pdf/edit/pdf_content_stream.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_edit_document.dart';
import 'package:document_studio/infrastructure/pdf/edit/pdf_objects.dart';

enum A11ySeverity { pass, warning, fail }

class A11yFinding {
  const A11yFinding(this.severity, this.title, this.detail, {this.fixId});

  final A11ySeverity severity;
  final String title;
  final String detail;

  /// Set when the app can repair it (see [fixPdfAccessibility]).
  final String? fixId;
}

/// Acrobat-style accessibility check on the structure that can be read
/// without rendering: title, language, tagging, text vs scanned images,
/// bookmarks on long files, form field labels. Not a PDF/UA certification.
List<A11yFinding> checkPdfAccessibility(Uint8List bytes) {
  final out = <A11yFinding>[];
  try {
    final doc = PdfEditDocument.open(bytes);
    final cat = doc.catalog;

    // Title shown in the title bar.
    final info = doc.dictOf(doc.trailer['Info']);
    final title = doc.resolve(info?['Title']);
    final vp = doc.dictOf(cat['ViewerPreferences']);
    final displayTitle = doc.resolve(vp?['DisplayDocTitle']);
    final hasTitle = title is PdfString && title.text.trim().isNotEmpty;
    final showsTitle = displayTitle is PdfBool && displayTitle.value;
    out.add(
      hasTitle && showsTitle
          ? const A11yFinding(A11ySeverity.pass, 'Document title',
              'A title is set and shown in the window title.')
          : const A11yFinding(
              A11ySeverity.fail,
              'Document title',
              'Screen readers announce the title. Set one and tell viewers to show it.',
              fixId: 'title',
            ),
    );

    // Language.
    final lang = doc.resolve(cat['Lang']);
    out.add(
      lang is PdfString && lang.text.trim().isNotEmpty
          ? A11yFinding(A11ySeverity.pass, 'Language', 'Set to ${lang.text}.')
          : const A11yFinding(
              A11ySeverity.fail,
              'Language',
              'No document language. Readers cannot pick the right voice.',
              fixId: 'lang',
            ),
    );

    // Tags.
    final tagged = cat.containsKey('StructTreeRoot');
    final marked = doc.dictOf(cat['MarkInfo']);
    final markedTrue = doc.resolve(marked?['Marked']);
    out.add(
      tagged && markedTrue is PdfBool && markedTrue.value
          ? const A11yFinding(A11ySeverity.pass, 'Tagged PDF',
              'The file has a structure tree.')
          : const A11yFinding(
              A11ySeverity.fail,
              'Tagged PDF',
              'No structure tree. Headings, lists and reading order are unknown '
                  'to assistive technology.',
            ),
    );

    // Text vs scanned pages (sample up to 20 pages).
    var textPages = 0;
    var imageOnly = 0;
    final n = doc.pageCount;
    final step = n <= 20 ? 1 : (n / 20).ceil();
    var sampled = 0;
    for (var p = 1; p <= n; p += step) {
      sampled++;
      final content = readPageContent(doc, p);
      if (content == null) continue;
      final a = analyzeContent(content, imageNames: pageImageNames(doc, p));
      if (a.texts.isNotEmpty) {
        textPages++;
      } else if (a.images.isNotEmpty) {
        imageOnly++;
      }
    }
    if (sampled > 0 && imageOnly > 0 && textPages < sampled) {
      out.add(
        A11yFinding(
          A11ySeverity.fail,
          'Scanned pages',
          '$imageOnly of $sampled checked pages are pictures with no text. '
              'Run Scan & OCR so the text can be read.',
        ),
      );
    } else {
      out.add(
        const A11yFinding(A11ySeverity.pass, 'Real text',
            'Pages contain selectable text.'),
      );
    }

    // Bookmarks on long documents.
    if (n > 20) {
      out.add(
        cat.containsKey('Outlines')
            ? const A11yFinding(A11ySeverity.pass, 'Bookmarks',
                'Long document has bookmarks.')
            : A11yFinding(
                A11ySeverity.warning,
                'Bookmarks',
                'A $n-page document should have bookmarks for navigation.',
              ),
      );
    }

    // Form fields without a tooltip (/TU).
    var fields = 0;
    var unlabeled = 0;
    for (var p = 1; p <= n; p++) {
      for (final (_, d) in doc.annotations(p)) {
        if (d.nameOf('Subtype') != 'Widget') continue;
        fields++;
        if (!d.containsKey('TU')) unlabeled++;
      }
    }
    if (fields > 0) {
      out.add(
        unlabeled == 0
            ? const A11yFinding(A11ySeverity.pass, 'Form fields',
                'Every field has a description.')
            : A11yFinding(
                A11ySeverity.warning,
                'Form fields',
                '$unlabeled of $fields form fields have no tooltip text.',
              ),
      );
    }
  } catch (e) {
    out.add(
      const A11yFinding(
        A11ySeverity.warning,
        'Check incomplete',
        'The file is encrypted or damaged, so only part could be checked.',
      ),
    );
  }
  return out;
}

/// Repairs what can be fixed in pure Dart. Returns new bytes or null.
Uint8List? fixPdfAccessibility(
  Uint8List bytes, {
  required String fixId,
  String? title,
  String? language,
}) {
  try {
    final doc = PdfEditDocument.open(bytes);
    final root = doc.trailer['Root'];
    if (root is! PdfRef) return null;
    final cat = doc.catalog.clone();
    switch (fixId) {
      case 'title':
        final infoRef = doc.trailer['Info'];
        final info = (doc.dictOf(infoRef) ?? PdfDict()).clone();
        info['Title'] = PdfString.text((title ?? 'Untitled').trim());
        if (infoRef is PdfRef) {
          doc.setObject(infoRef, info);
        } else {
          doc.trailer['Info'] = doc.addObject(info);
        }
        final vp = (doc.dictOf(cat['ViewerPreferences']) ?? PdfDict()).clone();
        vp['DisplayDocTitle'] = const PdfBool(true);
        cat['ViewerPreferences'] = vp;
      case 'lang':
        cat['Lang'] = PdfString.text((language ?? 'en-US').trim());
      default:
        return null;
    }
    doc.setObject(root, cat);
    return doc.save();
  } catch (_) {
    return null;
  }
}
